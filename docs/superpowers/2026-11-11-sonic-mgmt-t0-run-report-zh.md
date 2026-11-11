# sonic-mgmt t0 测试清单在 202605_resolute 的 Dockerfile 版与 rock 版 vs 镜像上的运行结果

- 日期:2026-11-10 至 2026-11-11
- 镜像,均来自 `canonical/sonic-buildimage` `202605_resolute` 的 `7a081af43c`,与 [A/B 报告](2026-11-10-sonic-mgmt-resolute-ab-report-zh.md)是同一对:
  - rock + pebble:镜像版本 `202605_resolute.0-7a081af43`
  - Dockerfile + supervisord:镜像版本 `HEAD.0-7a081af4`
- 测试清单:上游 t0 PR 测试清单,共 271 个文件,用 `run_tests.sh -m individual` 运行
- 测试代码:`canonical/sonic-mgmt` 的 `202605_resolute` 分支。主轮使用设计文档里的 19 个提交,即 `031aeb4`。§4 的修复又增加了 11 个提交,只在本地,未推送。
- testbed:12 个 vms-kvm-t0,每个镜像 6 个,各自跑在 Testflinger 机器 jasperoid 上的一个 LXD 虚拟机里(§1)
- 设计文档:[specs/2026-11-10-sonic-mgmt-ubuntu-rock-compat-design-zh.md](specs/2026-11-10-sonic-mgmt-ubuntu-rock-compat-design-zh.md)
- 原始结果与脚本:[data/2026-11-11-sonic-mgmt-t0-run/](data/2026-11-11-sonic-mgmt-t0-run/)
- 本文为中文版;以英文版 `-en.md` 为准

## 0. 结论

1. t0 清单的 271 个文件在两个镜像上都跑完,每个镜像 3040 个用例。分支在 `031aeb4` 时,Dockerfile 版有 18 个失败,rock 版有 110 个。
2. 两个镜像的结果在 37 个文件的 109 个用例上不同,每一个都找到了原因:
   - 93 个:sonic-mgmt 测试代码直接调用 `supervisorctl`、假定容器入口会执行镜像名后面的命令,或在容器里运行 `python`。§4 的提交修复了它们:rock 版上 93 个里有 92 个现在与 Dockerfile 版一样通过或跳过,第 93 个走到了一处 rock 差异(§5)。在 Dockerfile 版上,这些修复不改变任何结果;重跑中出现的变化都是修复前也出现过的偶发失败。
   - 1 个:A/B 报告里已经报告过的 rock `auto_restart` 限制。
   - 15 个不是差异:14 个使用每次运行都不同的随机参数,1 个是某台 Dockerfile testbed 上的 loop 设备被占用。
3. 测试越过 supervisorctl 之后,又发现两处 rock 差异(§5):容器停止时 pebble 把 rsyslogd 和其他服务一起停掉,关停阶段的日志因此丢失;rock 的 eventd 里没有 `/usr/bin/python`。这两处都不在 sonic-mgmt 里改。
4. 有 16 个用例在两个镜像上都失败。它们是 Ubuntu-SONiC 或 vs 平台的问题,与 rock 无关(§6)。它们都在上游 PR 测试清单里,所以在 Debian vs 镜像上预期能通过;这次没有跑 Debian 镜像。另外,两个镜像的大多数 teardown 都被 loganalyzer 报出同一条 AppArmor 消息(§6)。

## 1. 环境

| 项目 | 值 |
|---|---|
| 机器 | Testflinger jasperoid:256 线程,251 GB,NVMe;Ubuntu 26.04 |
| testbed | 12 个 LXD 虚拟机(`ubuntu:26.04`),每个 18 vCPU、18 GiB、140 GiB;vms-kvm-t0,邻居为 cEOS 4.32.5M |
| 分片 | 6 个分片,每片 45–46 个文件;第 N 片在两个镜像上跑同一批文件 |
| 主轮 | 2026-11-10 23:04 至 2026-11-11 04:53 UTC,两个镜像同时跑 |
| 测试时间 | pytest 时间合计 rock 25.5 小时、Dockerfile 31.1 小时,墙钟 5 小时 49 分 |

每个虚拟机运行 [scripts/tb-bootstrap.sh](data/2026-11-11-sonic-mgmt-t0-run/scripts/tb-bootstrap.sh):装包、add-topo、deploy-mg,然后跑自己的分片。文件清单在 `shards/` 下。

单个文件的耗时从 1 秒到 66 分钟不等,所以按文件数切的分片会相隔几个小时才跑完。主机上的均衡器([scripts/balancer.py](data/2026-11-11-sonic-mgmt-t0-run/scripts/balancer.py))把最慢分片里还没开始的文件的后一半,交给同一镜像下已经跑完的虚拟机。它把出让方本地的这些文件改名,让出让方的 `run_tests.sh` 跳过它们,不杀任何进程。一共交接 5 次,移交 39 个文件(`handoffs.json`)。被其他模块 import 的 12 个测试模块从不交接:有一次改名 `platform_tests/test_reboot.py` 导致 import 它的模块收集失败,损失了出让方上的 1 个文件,以及之后交给它的一次交接里的 2 个文件;这 3 个文件都已补跑。

## 2. 主轮结果

| | 通过 | 跳过 | 失败 | setup 错误 |
|---|---|---|---|---|
| Dockerfile | 1089 | 1933 | 15 | 3 |
| rock | 1001 | 1929 | 44 | 66 |

按用例的调用阶段结果计数。teardown 错误单独统计(§6);完整对比见 `compare-main-df-vs-rock.txt`,由 `scripts/analyze.py` 生成。

## 3. 两个镜像之间的差异

| 原因 | 用例 | 文件 |
|---|---|---|
| gnmi helper:通过 supervisorctl 查状态、停止、重启;rock 随后关掉 gnmi 容器 | 40 | 10 |
| 通过 supervisorctl 控制 arp_update 和 rsyslogd | 16 | 6 |
| 通过 supervisorctl 检查 SNMP 子代理 | 15 | 10 |
| 通过 supervisorctl 取 dhcp_relay 程序状态和 pid | 13 | 2 |
| 通过 supervisorctl 控制 pmon 和 lldp 里的程序 | 3 | 2 |
| like-bgp 容器靠镜像名后面的命令启动 | 2 | 1 |
| telemetry 事件 helper:supervisorctl,以及 eventd 里的 `python` | 2 | 1 |
| 通过 supervisorctl 取 bmp 程序状态 | 1 | 1 |
| 通过 supervisorctl 给 radvd 发 SIGHUP | 1 | 1 |
| rock 产品侧:关键服务 `on-failure: shutdown` 与 `auto_restart` 的冲突 | 1 | 1 |
| 非差异:`hash/test_generic_hash` 随机抽取参数 | 14 | 1 |
| 非差异:某台 Dockerfile testbed 上 `losetup` 发现 loop 设备被占用 | 1 | 1 |
| 合计 | 109 | 37 |

supervisorctl 引起的失败,在不同测试里表现不同:

- 命令失败,测试随即中止(arp、crm、dualtor、radv、monit、platform_info)。
- 失败被当成"还没运行起来",测试一直等到超时。SNMP 子代理检查在 16 个用例里各等了 300 秒,于是一个根本不碰进程的测试也会报 "Timeout waiting for SNMP facts"。
- shell 管道掩盖了退出码。`generic_config_updater/test_dhcp_relay` 取到的 pid 是空的,测试到后面的 `ps -p` 才失败。
- 测试忽略错误,跳过这一步继续跑(vlan 重启 arp_update,bgp_port_disable 重启 fpmsyncd)。
- 失败引出只在 rock 上发生的连锁反应。gnmi helper 杀 gnmi-native 的进程之前没有先停掉它,于是 pebble 按 `on-failure: shutdown` 停掉整个 gnmi 容器。之后的 gnmi 测试报 "The 'gnmi' container does not exist",monit 的 container_checker 告警还会进入不相关测试的 loganalyzer(`iface_namingmode` 里 rock 多出的 11 行)。

`bgp/test_bgp_command` 用 `docker run docker-database:latest sleep infinity` 启动第二个容器。rock 的入口是 `pebble enter`,不会执行镜像名后面给的命令,所以容器立刻退出。改用 `--entrypoint /bin/sleep` 后,两种镜像都能得到同样的空闲容器。

## 4. 修复与验证

| 提交 | 范围 | rock 上修复的用例 |
|---|---|---|
| `011a5d3` | `build_signal_command()` / `SonicHost.signal_container_process()`,附单元测试 | — |
| `1cb1b22` | snmp_helpers:子代理状态改从进程表读取 | 15 |
| `d98176b` | dhcp_relay_utils、test_dhcpv6_relay、GCU test_dhcp_relay | 13 |
| `2147e61` | gnmi helper、gnmi_setup、grpc_fixtures、GNMIEnvironment | 40 |
| `82ecd48` | arp、crm、dualtor、vlan、pc、syslog 里的 arp_update 与 rsyslogd | 15 |
| `5aae892` | like-bgp 入口;fpmsyncd 重启 | 2 |
| `f977a99` | bmp 状态 | 1 |
| `0239d07` | radvd SIGHUP | 1 |
| `16c9fb7` | thermalctld、lm-sensors、lldpmgrd | 3 |
| `8e0b354` | telemetry 事件 helper;事件发布工具改用 `python3` | 2 |
| `5c2f2e4` | 程序名与 signal 名按整串校验 | — |

分支的单元测试在每个提交上都通过(`011a5d3` 之后为 289 个,`5c2f2e4` 之后为 293 个)。

验证时,在两个镜像上用修复后的代码重跑了 64 个文件:所有被修复改到或用到被改 helper 的文件、所有出现过 rock 特有失败的文件,以及所有卷入 gnmi 连锁反应的文件。在 rock 版上,这些文件从 98 通过、33 失败、64 setup 错误,变为 186 通过、5 失败。剩下的 5 个失败:

| 用例 | 原因 |
|---|---|
| `pc/test_po_cleanup` | rock 产品侧:关停日志丢失(§5) |
| `process_monitoring` | rock 产品侧:`auto_restart`(A/B 报告) |
| `test_snmp_v2mib`、`test_platform_info` 的 psu、`test_pktgen` | 两个镜像都失败(§6) |

在 Dockerfile 版上,同一批文件修复前后的调用结果相同,只有三个用例例外:

- `test_gnoi_system_reboot_cold` 主轮失败、修复后通过;`test_continuous_reboot` 主轮通过、修复后失败。两次失败都是重启 300 秒后 lldp 的关键进程还没运行,这在任何修复之前就出现过。第二次失败发生时 testbed 的链路是断开的(§7)。
- `telemetry/test_events` 两次重跑通过,第三次失败:gNMI 订阅在 30 秒期限内没有收到 `mem-threshold-exceeded` 事件。修复没有碰这条路径。

对这些提交的独立审查没有发现严重问题。它指出了几处:迁移后的代码把探针失败读成"程序不存在",于是在旧代码会失败的地方跳过或通过;一个原本在无匹配时会失败的管道;一个不再提前返回的 SNMP 轮询;一个变宽松的 teardown 检查;一个在 Ansible 下从来没生效过的 `docker exec -it`;以及会放行末尾换行的校验。上面的提交已包含这些修复。受这些修复影响的 14 个文件(包括 `crm`、`syslog/test_syslog_rate_limit`、`dhcp_relay/test_dhcp_relay` 和 `telemetry/test_events`)在两个镜像上又跑了一遍:各 50 个通过、15 个跳过,没有失败(`verify-review-rerun.txt`)。

## 5. 本轮发现的 rock 差异

**关停日志丢失。** `pc/test_po_cleanup` 重新加载配置,并等待 teammgrd 收到 SIGTERM 时写出的 `cleanTeamProcesses` 消息。修复之后测试能走到重新加载这一步,但在 rock 版上 4 条消息一条也没出现。在一台 vs DUT 上:

| 操作 | syslog 里的 `cleanTeamProcesses` 行数 |
|---|---|
| Dockerfile:`systemctl restart teamd` | 20 |
| rock:`systemctl restart teamd` | 0 |
| rock:`pebble stop teammgrd`,rsyslogd 在运行 | 10 |

在 pebble 下 teammgrd 会正常清理并写日志。整个容器停止时,pebble 把 rsyslogd 和其他服务同时停掉,于是其他服务最后的消息被丢弃;supervisord 则按优先级最后才停 rsyslogd。teamd 的 rock 计划没有给 rsyslogd 和其他服务之间规定任何顺序。可能的修法在 rock 计划里:各服务 `after: rsyslogd`,这样 pebble 会最后停 rsyslogd。这影响所有 rock 容器,不只是 teamd。

**eventd 里没有 `/usr/bin/python`。** Dockerfile 版的 eventd 有 `python -> python3`;rock 版只有 `python3`。`telemetry/events/event_utils.py` 原来调用 `python`,现在改为两种镜像都有的 `python3`。rock 里其他调用 `python` 的地方会以同样的方式失败。

## 6. 两个镜像都失败的用例

| 用例 | 失败 | 类别 |
|---|---|---|
| `test_show_platform` 5 个、`test_sfputil` 3 个、`test_platform_info` 1 个 | 测试期望的 vs 平台数据缺失:"Platform x86_64-kvm_x86_64-r0 does not support EEPROM",没有 `/etc/sonic/vs_chassis_metadata.json`,`/usr/share/sonic/device/x86_64-kvm_x86_64-r0` 下没有 pcie 文件,没有状态为 OK 的 PSU;`sfputil` 和 `psuutil status` 返回 2 | Ubuntu-SONiC 的 vs 平台 |
| `tacacs/test_authorization` 4 个 | 对 `/etc/passwd` 和 tacplus 服务器日志的检查失败 | Ubuntu-SONiC |
| `radv/test_radv_run::test_radv_deployment_id` | 设置 deployment id 后 radvd 仍在运行 | Ubuntu-SONiC |
| `snmp/test_snmp_v2mib` | sysDescr 里没有测试从 DUT 读到的 `Ubuntu forky/sid` | Ubuntu-SONiC(A/B 报告已知) |
| `test_pktgen` | 它自己的 loganalyzer 匹配到 18 行,全是下面这条 AppArmor 消息 | Ubuntu-SONiC |

**两个镜像共有的 loganalyzer 噪声。** t0 清单里大多数测试的 teardown,都因为 `ERR unix_chkpwd: nss_tacplus: /etc/tacplus_nss.conf fopen failed` 和 `bad config or server line for nss_tacplus` 这两行被 loganalyzer 判失败。rsyslogd 也会写同样这一对。sudo 的 PAM account 阶段会运行 `unix_chkpwd`,它通过 nsswitch 的 `passwd: tacplus files` 解析用户,于是 `libnss_tacplus` 去打开 `/etc/tacplus_nss.conf`。Ubuntu 26.04 的 apparmor 5.0.2 以 enforce 模式加载 profile `unix-chkpwd`,它放行 NSS 库,但不放行这个文件。镜像上运行着 auditd,所以每次拒绝都记在 `/var/log/audit/audit.log` 里(一台 DUT 上有 3285 条,每次 sudo 一条),不进 dmesg。用 `apparmor_parser -R` 卸载这个 profile 后消息消失。Debian trixie 的 apparmor 4.1.0 带的是同一个 profile,但标记为 `flags=(complain)`;两个镜像都安装 apparmor,所以基于 Debian 的镜像不会记这两行。[canonical/sonic-buildimage#30](https://github.com/canonical/sonic-buildimage/pull/30) 以 `/etc/apparmor.d/local/unix-chkpwd` 的形式加入 `/etc/tacplus_nss.conf r,`。本报告的对比把这两行单独剔除。

## 7. testbed 注意事项

- 主机上的 Docker 把 iptables 的 FORWARD 策略设成了 DROP,虚拟机因此完全断网,直到在 `DOCKER-USER` 里放行 `lxdbr0`。
- sonic-mgmt 的 `vm_set` role 在没有 docker apt 源时,会用 `apt_key` 添加 docker-ce 源;Ubuntu 26.04 已经没有 `apt-key`。虚拟机改用 download.docker.com 的 docker-ce。
- openvswitch-switch 3.7.1 首次安装时,ovsdb-server 在 `ovs-vswitchd` 的 alternative 建好之前就启动了,systemd 随后不再重试;add-topo 之前需要重启一次。
- 2026-11-11 06:23,每个虚拟机里的 unattended-upgrades 都重启了 openvswitch。add-topo 装进去的流表随之丢失,每台 DUT 都断开了与 cEOS 邻居的链路。主轮在 04:53 已经结束。验证阶段有 21 个文件全部或部分在 06:23 之后运行;除了 §4 的重启测试,它们的结果与之前的运行一致。`testbed-cli.sh connect-topo` 可以恢复流表;bootstrap 现在会关掉自动升级的定时器。
- 中途被杀掉的测试可能留下配置。这一轮之前,在本地 testbed 上手动中止的一个 `acl/test_acl.py` 留下了表 `DATA_INGRESS_IPV4_TEST`,它通不过 YANG 校验,于是那台 testbed 上之后的每个测试都在 setup 阶段失败。

## 8. 没有做的

- 在 t0 清单之外的 34 个文件里(dualtor、dualtor_mgmt、qos、dash、ha、gnmi_e2e、platform API 等),还有大约 70 行在 DUT 上运行 `supervisorctl`。t0 清单里只剩两处,而且都只写日志:`arp/test_arp_extended` 的调试输出和 `snmp/test_snmp_lldp` 的诊断信息。
- rock 产品侧的问题(关停日志顺序、`auto_restart`、eventd 的 `python`)和 §6 的 Ubuntu-SONiC 失败,留给产品侧处理;只有 AppArmor 噪声已有修复在审(#30)。
- 分支没有推送。
