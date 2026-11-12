# sonic-mgmt t0 测试清单在 202605_resolute arm64 vs 镜像上的运行结果

- 日期:2026-11-12
- 镜像:`canonical/sonic-buildimage` `202605_resolute` 的 `7a081af43c`,加上 draft PR #18(`feat/resolute-arm64-vs`,`d3b6c4c08b`)的 9 个提交。PR #18 基于较早的 `d2f9ae8502`;它的提交可以无冲突地应用到 `7a081af43c` 上,得到的 diff 相同(15 个文件,+56/−6)。构建用的就是这次重放,即本地分支 `test/arm64-vs-on-7a081af43c`(`ddac4b7eec`),没有推送。镜像版本 `test_arm64-vs-on-7a081af43c.0-ddac4b7ee`,Dockerfile 模式,supervisord。没有 arm64 的 rock 镜像:所有 `rockcraft.yaml` 都只声明了 `platforms: amd64`,`build_rocks.sh` 写的也是 `_amd64.rock`。
- 基线:同一提交的 amd64 Dockerfile 镜像 `HEAD.0-7a081af4`,即 [t0 报告](2026-11-11-sonic-mgmt-t0-run-report-zh.md) §5 的最终重跑。
- 测试代码:[canonical/sonic-mgmt#2](https://github.com/canonical/sonic-mgmt/pull/2) 的 `7b70925`,另加一个支持 aarch64 DUT 的本地提交(`sonic-mgmt-aarch64-testbed.patch`,§2)。
- 测试清单:与之前相同的上游 t0 PR 测试清单,271 个文件,`run_tests.sh -m individual`。
- 原始结果与脚本:[data/2026-11-12-sonic-mgmt-t0-arm64-run/](data/2026-11-12-sonic-mgmt-t0-arm64-run/)
- 本文为中文版;以英文版 `-en.md` 为准

## 0. 结论

1. arm64 镜像跑完了整个 t0 清单:3040 个用例,1046 通过、1943 跳过、35 失败、16 个 setup 错误;amd64 是 1088、1933、16、3。有 71 个用例结果不同(§3)。
2. 这 71 个里没有一个是镜像在 arm64 上的功能故障。45 个来自测试侧:14 个是哈希用例随机抽取参数,26 个是 sonic-mgmt 不认识 arm64 vs 的平台名,5 个是 dualtor helper 里的抓包竞争。19 个 TACACS 用例来自本次自建的 arm64 ptf 镜像的缺陷,1 个来自较新的 cEOS 邻居,2 个是偶发测试(§4)。
3. 有 4 个重启用例在 arm64 上偶发失败。lldp、pmon 和 snmp 在开机两到三分钟后才启动,离测试的 300 秒等待很近,开机稍慢就会超时(§5)。
4. arm64 上用例耗时的中位数是 amd64 的 1.33 倍(§3)。
5. sonic-mgmt 按现在发布的形态跑不了 arm64:docker-sonic-mgmt 和 docker-ptf 只有 amd64 版,在 qemu-user 下运行慢得无法使用;cEOS 4.32.5M 没有 arm64 版;DUT 需要 aarch64 的 libvirt domain。§2 列出了本次构建或改动的内容。

## 1. 环境

| 项目 | 值 |
|---|---|
| 机器 | Testflinger papat:2 颗 Ampere Altra Max(Neoverse-N1),256 核,501 GB,一块 894 GB NVMe;Ubuntu 26.04 |
| testbed | 16 个特权 LXD 系统容器,每个一个 vms-kvm-t0 testbed。Neoverse-N1 不支持嵌套虚拟化,所以 DUT 虚拟机直接使用宿主的 `/dev/kvm`,而不是像 amd64 那样跑在 LXD 虚拟机里 |
| DUT | 4 vCPU、6 GiB、33 个 e1000 网卡,`virt` 机型,GICv3,UEFI |
| 邻居 | cEOSarm-lab 4.35.7.2M(amd64 基线:cEOS64-lab 4.32.5M) |
| 分片 | 按 amd64 的文件耗时切成 16 片;交接 3 次,移交 7 个文件(`handoffs.json`) |
| 构建 | slave 镜像和 `target/sonic-vs.bin` 在 papat 上原生构建:包和镜像共 46 分钟 |
| 主运行 | 14:55 至 18:10 UTC |

DUT 磁盘的制作方式与 `build_kvm_image.sh` 制作 amd64 磁盘相同:用 SONiC 的 arm64 ONIE recovery ISO 把 `sonic-vs.bin` 装到一块空的 16 GB 磁盘上(`scripts/make-vs-img.py`)。

## 2. arm64 testbed 需要的东西

| 项目 | 问题 | 本次的做法 |
|---|---|---|
| UEFI 固件 | resolute 的 edk2 2025.11 在 KVM 下崩溃 | 解包 qemu-efi-aarch64 2026.05-2ubuntu3;直接安装会连带拉入更新的 qemu |
| DUT 启动 | libvirt 给每个 DUT 一份空的 NVRAM,于是固件走可移动介质路径,而 ONIE 在那里装的是它自己的 GRUB;DUT 起来进的是 ONIE Rescue | 把 SONiC 的 `grubaa64.efi` 和 `grub.cfg` 复制到磁盘的 `\EFI\BOOT`(`scripts/esp-fallback.sh`)。amd64 vs 经 MBR 启动,不会遇到这个问题 |
| DUT domain | `sonic.xml.j2` 描述的是 x86 q35 机器 | `sonic_aarch64.xml.j2`,按 `ansible_architecture` 选用;`stop_sonic_vm.yml` 在 undefine 时带 `nvram` 标志,UEFI domain 不带它 libvirt 会拒绝(`sonic-mgmt-aarch64-testbed.patch`) |
| docker-sonic-mgmt | registry 镜像只有 amd64;在 qemu-user 下 `ansible --version` 要 25 秒,原生 1.4 秒 | 用同一个上游 Dockerfile 原生构建(上游 `e8bb4d24b`,即该镜像的 Tag 标签);resolute 分叉里的 `sonic_py_common` wheel 缺少 `sonic_grpc`,所以用 amd64 镜像里的纯 Python 文件重建了上游的 wheel |
| docker-ptf | add-topo 使用的标签 `202605` 只有 amd64;在 qemu-user 下 `import scapy.all, ptf` 要 20 秒,原生不到 1 秒 | 原生构建 202605 的 Dockerfile(`50b78a3b5`):Go 和 InfluxDB 换成 arm64;不装 p4lang 和 python-saithrift 的 deb(只有 DASH 和 SAI 测试用);补一个 SONiC 构建会留下的空 `/sonic`;ptf-py3(纯 Python)取自 amd64 镜像。`tacacs_plus` 和 `ptf_tgen.sh` 必须保留可执行位(§4.2) |
| ptf 标签 | add-topo 会从 registry 拉取 `docker-ptf:202605`,覆盖本地镜像 | 在 host_vars 里设 `ptf_modified: true` |
| cEOS | 4.32.5M 没有 arm64 版 | cEOSarm-lab 4.35.7.2M |

容器环境还有两点:特权 LXD 容器启动时,其中的 systemd-binfmt 会清空宿主的 binfmt 表;vm_set 的宿主设置会写全宿主范围的 sysctl,所以由宿主来设,容器里跳过这一步。

## 3. 结果

| | 通过 | 跳过 | 失败 | setup 错误 |
|---|---|---|---|---|
| amd64,Dockerfile | 1088 | 1933 | 16 | 3 |
| arm64,Dockerfile | 1046 | 1943 | 35 | 16 |

与 t0 报告一样按用例的调用阶段结果计数。完整对比见 `compare-main-amd64-vs-arm64.txt`,由 `scripts/analyze2.py` 生成;71 个不同的用例见 `differing-cases-main.txt`。

在 amd64 上耗时超过 30 秒的 208 个文件里,arm64/amd64 耗时比的中位数是 1.33(四分位数 1.23 和 1.43);pytest 时间合计 38.5 小时对 30.9 小时。

## 4. 差异及其原因

有差异用例的 27 个文件(`hash/test_generic_hash` 除外)在新的 testbed 上又各跑了两遍:一遍让 sonic-mgmt 把 DUT 的平台看作 `x86_64-kvm_x86_64-r0`(重跑 A,`eval-platform-alias.diff`,仅用于评估),一遍不做改动(重跑 B)。`rerun-table.txt` 列出了这些文件的每个用例在四次运行中的结果。

| 原因 | 用例 | 依据 |
|---|---|---|
| 测试随机抽取参数 | 14 | `hash/test_generic_hash`,与 t0 报告相同 |
| sonic-mgmt 不认识 arm64 vs 的平台名 | 26 | 重跑 A 得到 amd64 的结果,重跑 B 得到 arm64 的结果 |
| arm64 ptf 镜像里的 TACACS 服务器没有运行 | 19 | §4.2 |
| dualtor 流量 helper 里的抓包竞争 | 5 | §4.3 |
| 重启时间 | 4 | §5 |
| cEOS 4.35 的命令语法 | 1 | §4.4 |
| 偶发 | 2 | `dhcpv6_multicast_recv` 在 amd64 上失败,与 t0 报告相同;`telemetry/test_events` 被上游在 vs 上标为不稳定的 xfail(sonic-buildimage#19943),在主运行和重跑 B 失败、在重跑 A 通过 |

### 4.1 平台名

在 arm64 上,vs 镜像报告的平台是 `arm64-qemu_armv8a-r0`,这是 PR #18 加的 x86 vs 平台的别名。sonic-mgmt 在大约 49 处按字面名 `x86_64-kvm_x86_64-r0` 识别 vs:mark 文件里的 24 条条件、`is_virtual_platform()`、重启和平台 helper,以及 gnmi helper。在 arm64 上,这些地方都走了硬件分支:

| 用例 | amd64 → arm64 |
|---|---|
| `ecmp/inner_hashing` 16 个 | 通过 → 跳过;跳过条件把 `x86_64-kvm_x86_64-r0` 列在允许运行的平台里 |
| `bgp/test_bgp_session` 4 个、`bgp/test_bgp_stress_link_flap` 2 个 | 以 "not supported on Virtual Switch" 跳过 → 实际运行;其中 3 个失败 |
| `lldp/test_lldp` 2 个 | 通过 → "eth0 is missing from LLDP table";vs 的 eth0 没有邻居,`is_virtual_platform()` 只按名字考虑了这一点 |
| `ip/test_ip_packet` 的 0xffff 校验和用例 | 通过 → `is_mellanox_fanout()` 里 KeyError,这个函数在 vs 上按名字提前返回 |
| `platform_tests/test_service_warm_restart` | 以 "not supported for kvm" 跳过 → setup 错误 |
| `generic_config_updater/test_lo_interface`、`radv` 4 个、`snmp_interfaces` 4 个、`snmp_memory` 2 个、`syslog` 5 个、`vlan/test_autostate_disabled` | 只有 loganalyzer 不同,不计入上面的数字:这些用例跑在同一台 DUT 上,那次开机时 database.service 第一次启动读到的 `database_config.json` 是空的,`process-reboot-cause` 因此一直重启。在两次重跑中全部干净通过。其余 15 台 DUT 最近一次开机没有出现这种情况 |

### 4.2 TACACS

19 个 TACACS 用例在 arm64 的三次运行中都失败或报错。测试用 `service tacacs_plus restart` 在 ptf 容器里启动 TACACS 服务器,得到的回答是 `tacacs_plus: unrecognized service`。arm64 ptf 构建通过 GitHub contents API 获取文件,而这个接口会丢掉可执行位;`/etc/init.d/tacacs_plus` 正是上游目录里两个可执行文件之一(另一个是 `ptf_tgen.sh`)。于是 testbed 退回本地账户,所有 TACACS 登录都失败。这是本次测试环境的缺陷,不是镜像的问题。在运行中的 ptf 容器里给这两个脚本加上可执行位之后,把用到 TACACS 服务器的 9 个文件(`tacacs/` 下的 6 个、`generic_config_updater/test_aaa`、`ip/test_mgmt_ipv6_only` 和 `ssh/test_ssh_limit`)又跑了一遍:44 个用例,22 通过、18 跳过、4 失败,与 amd64 的用例和结果完全相同,teardown 也相同(`tacacs-rerun.txt`)。

### 4.3 dualtor 抓包竞争

5 个 dualtor 失败都是 scapy 报 "No data could be read!"。`dump_intf_packets` 用 `kill -s 2` 停掉 ptf 容器里的 tcpdump,随即取回 pcap,不等 tcpdump 退出。每一个这样的失败,日志里都有一次取回空文件(sha1 `da39a3ee…`)的记录,而 scapy 对空文件报的就是这个错。同样的用例在 arm64 的其他运行中通过;`active_tor_downstream[ipv6]` 三次都失败。

### 4.4 cEOS 4.35

`pc/test_lag_2` 的 lacp_rate 用例在邻居上设置 `lacp rate fast`。cEOS 4.35.7.2M 回答 `% Invalid input`;这条命令现在叫 `lacp timer`。sonic-mgmt 的 `set_interface_lacp_rate_mode` 在第一条命令失败或没有改变时会退回 `lacp timer`,但 `eos_config` 在这个判断之前就因失败抛出了异常。

## 5. 重启时间

`platform_tests/test_reboot`(gNOI 冷启动、gNOI 热启动、连续重启)和 `gnmi/test_gnoi_system_reboot` 冷启动都报 "Not all critical processes are healthy":重启 300 秒后,lldp-syncd、lldpd 和 lldpmgrd 仍未运行,pmon 也还没有启动。不同运行的结果不一样:重跑 A 中 4 个失败 2 个,重跑 B 一个也没有失败。在两台重启过的 DUT 上,内核和 systemd 在开机后 37 秒和 41 秒就绪,而 SONiC 延后启动的 lldp、pmon 和 snmp 分别在开机后 166 秒和 116 秒才启动。宿主繁忙时,测试的 300 秒等待余量很小。

## 6. 没有做的

- 没有 arm64 的 rock 镜像(没有 arm64 的 `rockcraft.yaml`)。
- 没有 rebase PR #18;本次用的是在 `7a081af43c` 上的本地重放。
- sonic-mgmt 按名字识别 vs(§4.1)、aarch64 DUT domain 和 cEOS 4.35 的 lacp 退回(§4.4)都没有在 sonic-mgmt 里修改;aarch64 domain 只以本次的本地补丁存在。
- 两台 arm64 DUT 上出现的 dhcpmon core 文件在 amd64 上也有(Dockerfile 和 rock 都有),这里没有跟进。
