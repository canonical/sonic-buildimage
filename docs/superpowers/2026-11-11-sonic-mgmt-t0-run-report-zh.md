# sonic-mgmt t0 测试清单在 202605_resolute 的 Dockerfile 版与 rock 版 vs 镜像上的运行结果

- 日期:2026-11-10 至 2026-11-12
- 镜像,均来自 `canonical/sonic-buildimage` `202605_resolute` 的 `7a081af43c`,与 [A/B 报告](2026-11-10-sonic-mgmt-resolute-ab-report-zh.md)是同一对:
  - rock + pebble:镜像版本 `202605_resolute.0-7a081af43`
  - Dockerfile + supervisord:镜像版本 `HEAD.0-7a081af4`
- 测试清单:上游 t0 PR 测试清单,共 271 个文件,用 `run_tests.sh -m individual` 运行;另外还有 dualtor、t0-2vlans 和 t0-sonic 清单(§8)
- 测试代码:[canonical/sonic-mgmt#2](https://github.com/canonical/sonic-mgmt/pull/2),分支 `feat/resolute-ubuntu-rock-compat`,在 `sonic-net/sonic-mgmt` `202605` 的 `36c29fc` 之上共 21 个签名提交,位于 `7b70925`。首轮(§2、§3)只包含进程框架和公共 helper,即调用点提交 9–21 之前的代码。
- testbed:跑在 Testflinger 机器 jasperoid 上 LXD 虚拟机里的 vms-kvm testbed(§1)
- 设计文档:[specs/2026-11-10-sonic-mgmt-ubuntu-rock-compat-design-zh.md](specs/2026-11-10-sonic-mgmt-ubuntu-rock-compat-design-zh.md)
- 原始结果与脚本:[data/2026-11-11-sonic-mgmt-t0-run/](data/2026-11-11-sonic-mgmt-t0-run/)
- 本文为中文版;以英文版 `-en.md` 为准

## 0. 结论

1. 用最终代码,t0 清单的 271 个文件在两个镜像上都跑完,每个镜像 3040 个用例,两者只有 18 个用例结果不同(§5)。其中 14 个不是差异(测试参数随机),2 个是两个镜像上都会出现的偶发失败,2 个是 rock 产品侧问题:A/B 报告已经报告过的 `auto_restart` 限制,以及 pebble 把 rsyslogd 和其他服务一起停掉导致关停日志丢失(§6)。teardown 和 loganalyzer 的结果两个镜像相同。
2. 首轮在调用点提交之前,两个镜像在 37 个文件的 109 个用例上不同(§3)。其中 93 个来自 sonic-mgmt 测试代码直接调用 `supervisorctl`、假定容器入口会执行镜像名后面的命令,或在容器里运行 `python`;提交 9–21 修复了它们(§4)。
3. dualtor、t0-2vlans 和 t0-sonic 清单在两个镜像上结果完全相同(§8)。
4. 有 18 个用例在两个镜像上都失败。它们是 Ubuntu-SONiC、vs 平台或 testbed 的问题,与 rock 无关(§7)。它们都在上游 PR 测试清单里,所以在 Debian vs 镜像上预期能通过;这次没有跑 Debian 镜像。另外,两个镜像的大多数 teardown 都被 loganalyzer 报出同一条 AppArmor 消息(§7);canonical/sonic-buildimage#30 修复了它。

## 1. 环境

| 项目 | 值 |
|---|---|
| 机器 | Testflinger jasperoid:256 线程,251 GB,NVMe;Ubuntu 26.04 |
| testbed | 12 个 LXD 虚拟机(`ubuntu:26.04`),每个 18 vCPU、18 GiB、140 GiB;vms-kvm-t0,邻居为 cEOS 4.32.5M |
| 分片 | 6 个分片,每片 45–46 个文件;第 N 片在两个镜像上跑同一批文件 |
| 首轮 | 2026-11-10 23:04 至 2026-11-11 04:53 UTC,两个镜像同时跑 |
| 最终重跑 | 2026-11-12 02:50 至 08:44 UTC,两个镜像同时跑(§5) |
| 首轮测试时间 | pytest 时间合计 rock 25.5 小时、Dockerfile 31.1 小时,墙钟 5 小时 49 分 |

每个虚拟机运行 [scripts/tb-bootstrap.sh](data/2026-11-11-sonic-mgmt-t0-run/scripts/tb-bootstrap.sh):装包、add-topo、deploy-mg,然后跑自己的分片。文件清单在 `shards/` 下。

单个文件的耗时从 1 秒到 66 分钟不等,所以按文件数切的分片会相隔几个小时才跑完。主机上的均衡器([scripts/balancer.py](data/2026-11-11-sonic-mgmt-t0-run/scripts/balancer.py))把最慢分片里还没开始的文件的后一半,交给同一镜像下已经跑完的虚拟机。它把出让方本地的这些文件改名,让出让方的 `run_tests.sh` 跳过它们,不杀任何进程。一共交接 5 次,移交 39 个文件(`handoffs.json`)。被其他模块 import 的 12 个测试模块从不交接:有一次改名 `platform_tests/test_reboot.py` 导致 import 它的模块收集失败,损失了出让方上的 1 个文件,以及之后交给它的一次交接里的 2 个文件;这 3 个文件都已补跑。

## 2. 首轮结果

| | 通过 | 跳过 | 失败 | setup 错误 |
|---|---|---|---|---|
| Dockerfile | 1089 | 1933 | 15 | 3 |
| rock | 1001 | 1929 | 44 | 66 |

按用例的调用阶段结果计数。teardown 错误单独统计(§7);完整对比见 `compare-main-df-vs-rock.txt`,由 `scripts/analyze.py` 生成。

## 3. 首轮中的差异

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

## 4. 修复

| # | 提交 | 范围 | 在首轮清单中修复的 rock 用例 |
|---|---|---|---|
| 5、6 | `e6af484`、`7536a03` | 包含 `build_signal_command()` 与 `SonicHost.signal_container_process()` | — |
| 9 | `d6bdb02` | snmp_helpers:子代理状态改从进程表读取 | 15 |
| 10 | `7d418e2` | dhcp_relay_utils、test_dhcpv6_relay、GCU test_dhcp_relay | 13 |
| 11 | `5284ceb` | gnmi helper、gnmi_setup、grpc_fixtures、GNMIEnvironment | 40 |
| 12 | `6bc47ef` | arp、crm、dualtor、vlan、pc、syslog 里的 arp_update 与 rsyslogd | 15 |
| 13 | `6f16cd2` | like-bgp 入口;fpmsyncd 重启 | 2 |
| 14 | `fa0c72e` | bmp 状态 | 1 |
| 15 | `603ce6a` | radvd SIGHUP | 1 |
| 16 | `d407932` | thermalctld、lm-sensors、lldpmgrd | 3 |
| 17 | `6d39a82` | telemetry 事件 helper;事件发布工具改用 `python3` | 2 |
| 18 | `f55a879` | dualtor 清单里的 arp_update 与 ycabled(§8) | — |
| 19 | `33a574b` | qos_sai:radvd、arp_update、lacpd | —(只在真机上走到) |
| 20 | `f9f14d7` | dhcp_server fixture | —(只在真机上走到) |
| 21 | `7b70925` | 两处只写日志的诊断输出 | — |

分支的单元测试在每个提交上都通过,最后一个提交为 294 个。

第一批修复的验证,是在两个镜像上重跑 64 个文件:所有被修复改到或用到被改 helper 的文件、所有出现过 rock 特有失败的文件,以及所有卷入 gnmi 连锁反应的文件。在 rock 版上,这些文件从 98 通过、33 失败、64 setup 错误变为 186 通过、5 失败;这 5 个是 rock 产品侧问题和两个镜像都失败的用例(`verify-before-after-rock.txt`)。

对这些提交的三次独立审查都没有发现严重问题。它们指出了几处:迁移后的代码把探针失败读成"程序不存在",于是在旧代码会失败的地方跳过或通过;一个原本在无匹配时会失败的管道;一个不再提前返回的 SNMP 轮询;一个变宽松的 teardown 检查;一个在 Ansible 下从来没生效过的 `docker exec -it`;会放行末尾换行的校验;以及三处只在真机上走到的调用点(提交 19–21)。这些提交已包含修复。受影响的文件在两个镜像上又跑了一遍,没有失败,两个镜像结果相同(`verify-review-rerun.txt`、`audit-fix-rerun.txt`)。

## 5. 用最终代码全量重跑

271 个文件在两个镜像上又全部跑了一遍,用 12 个 testbed,分片按首轮实测的文件耗时切分(`shards-final-rerun/`);交接 3 次,移交 12 个文件(`handoffs-final-rerun.json`)。代码是提交 1–18;提交 19–21 改到的文件之后在两个镜像上单独跑了一遍,每个镜像都是 23 通过、343 跳过,与全量重跑相同(`audit-fix-rerun.txt`)。

| | 通过 | 跳过 | 失败 | setup 错误 |
|---|---|---|---|---|
| Dockerfile | 1088 | 1933 | 16 | 3 |
| rock | 1085 | 1935 | 17 | 3 |

结果不同的用例(`compare-final-rerun-df-vs-rock.txt`):

| 用例 | Dockerfile → rock | 类别 |
|---|---|---|
| `hash/test_generic_hash` 14 个 | 只在一个镜像上出现 | 不是差异:测试随机抽取参数,所以用例名不同;按测试函数看结果一致 |
| `process_monitoring::test_monitoring_critical_processes` | 通过 → 失败 | rock 产品侧:`auto_restart`(A/B 报告) |
| `pc/test_po_cleanup` | 通过 → 失败 | rock 产品侧:关停日志丢失(§6) |
| `dhcp_relay/test_dhcp_pkt_recv` 的 dhcpv6 multicast | 失败 → 通过 | 偶发:没收到带预期 transaction id 的包 |
| `telemetry/test_events` | 通过 → xfail | 偶发:上游在 vs 上把它标为 xfail(sonic-buildimage#19943);之前几次重跑在 rock 上都通过 |

teardown 结果,以及已知 AppArmor 噪声之外的 loganalyzer 匹配,两个镜像相同。两个镜像都失败的 18 个用例见 §7。

## 6. 这几轮发现的 rock 差异

**关停日志丢失。** `pc/test_po_cleanup` 重新加载配置,并等待 teammgrd 收到 SIGTERM 时写出的 `cleanTeamProcesses` 消息。修复之后测试能走到重新加载这一步,但在 rock 版上 4 条消息一条也没出现。在一台 vs DUT 上:

| 操作 | syslog 里的 `cleanTeamProcesses` 行数 |
|---|---|
| Dockerfile:`systemctl restart teamd` | 20 |
| rock:`systemctl restart teamd` | 0 |
| rock:`pebble stop teammgrd`,rsyslogd 在运行 | 10 |

在 pebble 下 teammgrd 会正常清理并写日志。整个容器停止时,pebble 把 rsyslogd 和其他服务同时停掉,于是其他服务最后的消息被丢弃;supervisord 则按优先级最后才停 rsyslogd。teamd 的 rock 计划没有给 rsyslogd 和其他服务之间规定任何顺序。可能的修法在 rock 计划里:各服务 `after: rsyslogd`,这样 pebble 会最后停 rsyslogd。这影响所有 rock 容器,不只是 teamd。

**eventd 里没有 `/usr/bin/python`。** Dockerfile 版的 eventd 有 `python -> python3`;rock 版只有 `python3`。`telemetry/events/event_utils.py` 原来调用 `python`,现在改为两种镜像都有的 `python3`。rock 里其他调用 `python` 的地方会以同样的方式失败。

## 7. 两个镜像都失败的用例

| 用例 | 失败 | 类别 |
|---|---|---|
| `test_show_platform` 5 个、`test_sfputil` 3 个、`test_platform_info` 1 个 | 测试期望的 vs 平台数据缺失:"Platform x86_64-kvm_x86_64-r0 does not support EEPROM",没有 `/etc/sonic/vs_chassis_metadata.json`,`/usr/share/sonic/device/x86_64-kvm_x86_64-r0` 下没有 pcie 文件,没有状态为 OK 的 PSU;`sfputil` 和 `psuutil status` 返回 2 | Ubuntu-SONiC 的 vs 平台 |
| `tacacs/test_authorization` 4 个 | 对 `/etc/passwd` 和 tacplus 服务器日志的检查失败 | Ubuntu-SONiC |
| `radv/test_radv_run::test_radv_deployment_id` | 设置 deployment id 后对 radvd 的检查失败 | Ubuntu-SONiC |
| `snmp/test_snmp_v2mib` | sysDescr 里没有测试从 DUT 读到的 `Ubuntu forky/sid` | Ubuntu-SONiC(A/B 报告已知) |
| `test_pktgen` | 它自己的 loganalyzer 匹配到 18 行,全是下面这条 AppArmor 消息 | Ubuntu-SONiC |
| `disk/test_disk_exhaustion` | 磁盘写满期间 DUT 转发的包数不在预期范围内 | Ubuntu-SONiC 或 vs;t1-lag testbed 上也出现过 |
| `syslog/test_logrotate::test_logrotate_full_partition_no_archives_cleanup` | setup 时 `losetup` 发现 loop 设备被占用 | testbed |

**两个镜像共有的 loganalyzer 噪声。** t0 清单里大多数测试的 teardown,都因为 `ERR unix_chkpwd: nss_tacplus: /etc/tacplus_nss.conf fopen failed` 和 `bad config or server line for nss_tacplus` 这两行被 loganalyzer 判失败。rsyslogd 也会写同样这一对。sudo 的 PAM account 阶段会运行 `unix_chkpwd`,它通过 nsswitch 的 `passwd: tacplus files` 解析用户,于是 `libnss_tacplus` 去打开 `/etc/tacplus_nss.conf`。Ubuntu 26.04 的 apparmor 5.0.2 以 enforce 模式加载 profile `unix-chkpwd`,它放行 NSS 库,但不放行这个文件。镜像上运行着 auditd,所以每次拒绝都记在 `/var/log/audit/audit.log` 里(一台 DUT 上有 3285 条,每次 sudo 一条),不进 dmesg。用 `apparmor_parser -R` 卸载这个 profile 后消息消失。Debian trixie 的 apparmor 4.1.0 带的是同一个 profile,但标记为 `flags=(complain)`;两个镜像都安装 apparmor,所以基于 Debian 的镜像不会记这两行。[canonical/sonic-buildimage#30](https://github.com/canonical/sonic-buildimage/pull/30) 以 `/etc/apparmor.d/local/unix-chkpwd` 的形式加入 `/etc/tacplus_nss.conf r,`。本报告的对比把这两行单独剔除。

## 8. 其他 vs 拓扑

dualtor、t0-2vlans 和 t0-sonic 拓扑的上游 PR 测试清单,每个镜像用一个 testbed 依次跑完(`compare-other-topologies.txt`):

| 清单 | testbed | rock | Dockerfile |
|---|---|---|---|
| dualtor,22 个文件 | vms-kvm-dual-t0,两台 DUT | 61 通过、137 跳过、6 失败 | 61 通过、137 跳过、6 失败 |
| t0-2vlans,3 个文件 | vms-kvm-t0,`vlan_config=two_vlan_a` | 2 通过、6 跳过 | 2 通过、6 跳过 |
| t0-sonic,8 个文件 | vms-kvm-t0-64-32,vSONiC 邻居,`--enable_macsec` | 45 通过、11 跳过 | 45 通过、11 跳过 |

把 dualtor 测试随机挑选的 DUT 名字排除后,没有一个用例结果不同。dualtor 的 6 个失败两个镜像相同:`arp/test_arp_dualtor` 里 4 个 IPv6 failed-neighbor 用例,以及 `dualtor/test_mux_port_iptables_entries` 的 2 个,后者在 IPv4 nat 表里看到一条测试在 Ubuntu-SONiC 上不预期的 DOCKER 链。在提交 18 之前,rock 版还会因为直接调用 supervisorctl 而在 `arp_dualtor`、`test_standalone_tunnel_route` 和 `test_switchover_faulty_ycable` 上失败。

t1-lag 不在范围内。停掉之前它 224 个文件里大约跑了三分之二:两个镜像都跑完的 1531 个用例里只有 1 个不同,是 Dockerfile 版重启后 lldp 偶发起得慢。

## 9. testbed 注意事项

- 主机上的 Docker 把 iptables 的 FORWARD 策略设成了 DROP,虚拟机因此完全断网,直到在 `DOCKER-USER` 里放行 `lxdbr0`。
- sonic-mgmt 的 `vm_set` role 在没有 docker apt 源时,会用 `apt_key` 添加 docker-ce 源;Ubuntu 26.04 已经没有 `apt-key`。虚拟机改用 download.docker.com 的 docker-ce。
- openvswitch-switch 3.7.1 首次安装时,ovsdb-server 在 `ovs-vswitchd` 的 alternative 建好之前就启动了,systemd 随后不再重试;add-topo 之前需要重启一次。
- 2026-11-11 06:23,每个虚拟机里的 unattended-upgrades 都重启了 openvswitch。add-topo 装进去的流表随之丢失,每台 DUT 都断开了与 cEOS 邻居的链路。首轮在 04:53 已经结束。在修复后的重跑中,有 21 个文件全部或部分在 06:23 之后运行;除了一个重启测试,它们的结果与之前的运行一致。`testbed-cli.sh connect-topo` 可以恢复流表;bootstrap 现在会关掉自动升级的定时器。
- 中途被杀掉的测试可能留下配置。这一轮之前,在本地 testbed 上手动中止的一个 `acl/test_acl.py` 留下了表 `DATA_INGRESS_IPV4_TEST`,它通不过 YANG 校验,于是那台 testbed 上之后的每个测试都在 setup 阶段失败。
- LXD 虚拟机的内存在宿主上是共享内存,而 guest 的页缓存几分钟内就会把它填到上限,所以各虚拟机的内存上限加起来必须小于宿主内存。一个 vms-kvm-t1-lag testbed(24 个 cEOS 邻居)跑几个小时后需要超过 44 GiB。在 251 GB 的宿主上给 6 个虚拟机分了 240 GiB,宿主就杀掉了其中一个;宿主上加 swap 文件、调小 ZFS ARC 后不再发生。
- 有一次 Testflinger 装机因 MAAS API 接连出错而失败;重新提交任务后成功。

## 10. 没有做的

- 在这几个清单之外的测试领域(dualtor_mgmt、qos、dash、ha、gnmi_e2e、platform API 等)里,还有大约 70 行在 DUT 上运行 `supervisorctl`,其中包括 Mellanox 的 dynamic buffer 脚本。
- multi-ASIC 路径只有单元测试覆盖;t1-lag、multi-asic、t2 和 VPP 拓扑没有跑。
- rock 产品侧的问题(关停日志顺序、`auto_restart`、eventd 的 `python`)和 §7 的 Ubuntu-SONiC 失败,留给产品侧处理;只有 AppArmor 噪声已有修复在审(#30)。
