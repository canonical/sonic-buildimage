# sonic-mgmt 202605 在 202605_resolute 的 Dockerfile 版与 rock 版 vs 镜像上的 A/B 实测

- 日期:2026-11-10
- 镜像,都来自 `canonical/sonic-buildimage` `202605_resolute` 的 `7a081af43c`:
  - rock + pebble:CI 运行 42562456825 的 artifact `sonic-vs-img`,镜像版本 `202605_resolute.0-7a081af43`
  - Dockerfile + supervisord:同一 commit 在本地构建(detached HEAD),镜像版本 `HEAD.0-7a081af4`
- 测试代码:`canonical/sonic-mgmt` 分支 `202605_resolute`,在 `sonic-net/sonic-mgmt` `202605` 的 `36c29fc` 之上有 11 个签名提交,只在本地(未推送)。上游那一轮用未修改的 `36c29fc`。
- Testbed:构建机上的 vms-kvm-t0,cEOS 4.32.5M 做邻居,docker-sonic-mgmt 带 ansible-core 2.20.11。inventory 给 DUT 设了 `ansible_python_interpreter: /usr/bin/python3`。
- 设计:[specs/2026-11-10-sonic-mgmt-ubuntu-rock-compat-design-zh.md](specs/2026-11-10-sonic-mgmt-ubuntu-rock-compat-design-zh.md)
- 原始结果与脚本:[data/2026-11-10-sonic-mgmt-ab/](data/2026-11-10-sonic-mgmt-ab/)
- 本文为中文版;英文版(`-en.md`)为唯一事实来源

## 0. 结论

1. 有了 `202605_resolute` 分支,所选的 sonic-mgmt 测试能在两个镜像上跑起来。sanity、pretest、posttest 在两边都通过,autorestart 测到的 13 个容器在 pebble 和 supervisord 下都通过。
2. 该分支没有改变 supervisord 路径上的结果。在 Dockerfile 版上,分支(R2)与上游(R3)有 8 个用例结果不同,每一个都是上游撞上了分支修掉的两个 Ubuntu 问题之一:monit 5.35 报告 `Waiting`,以及 sshd banner 的正则。
3. rock 版与 Dockerfile 版只在一个测试上不同:`process_monitoring::test_monitoring_critical_processes`。`auto_restart` 关闭时,关键进程退出会让整个 rock 容器停掉,而 supervisord 会让容器里的其他程序继续运行。这正是 PR #28 声明的局限。
4. `memory_checker::test_memory_checker_recover` 在 rock 上失败、在 R2 中通过,但在 Dockerfile 版上单独运行 5 次全部失败。这是测试本身的竞争,不是 rock 的差异。
5. 跑测试暴露了设计之外的 6 个 sonic-mgmt 兼容问题,都已在分支上修复,并各自带单元测试(§4)。

## 1. 设置

| 轮次 | sonic-mgmt | 镜像 | 时间(UTC) |
|---|---|---|---|
| R1b | 分支 `202605_resolute` | rock | 11:45–12:47 |
| R2 | 分支 `202605_resolute` | Dockerfile | 12:57–14:54 |
| R3 | 上游 `36c29fc` | Dockerfile | 15:05–17:11 |

R1b 是在 rock 镜像上的第二轮。第一轮 R1 发现了后来在 `a6be7f4` 和 `5d2fbdf` 里修掉的 autorestart 与 memory_checker 问题。R2 和 R3 用同一次部署;R3 在 R2 结束 11 分钟后开始,因为 memory_checker 在 teardown 时会重启 monit,而上游不接受随后 10 分钟的 `Waiting` 状态(§3.1)。

每一轮都通过 `run_tests.sh -m individual` 运行 pretest、posttest,以及 `autorestart/test_container_autorestart.py`、`platform_tests/daemon/` 下的 7 个文件、`memory_checker/test_memory_checker.py`、`copp/test_copp.py` 和 `process_monitoring/test_critical_process_monitoring.py`。

有两组在这个 testbed 上没有信息量:copp 的 28 个用例都被条件标记在 t0 上跳过("covered by t1-lag topology");platform daemon 的用例在 vs 上全部跳过。

两个镜像的版本号不同,所以 sonic-mgmt 推断出的 release 在 rock 版上是 `202605`,在 Dockerfile 版上是 `unknown`。所选测试里只有 4 条条件标记用到 release 或 build version:copp 里的两条(反正整组跳过),以及 memory_checker 和 `test_orchagent_heartbeat` 里的 `release in ['202412']`,对两个镜像都是 false。版本命名不影响这次对比。

## 2. 结果

| 模块 | R1b rock | R2 Dockerfile | R3 Dockerfile,上游 |
|---|---|---|---|
| pretest | 8 通过,4 跳过 | 8 通过,4 跳过 | 8 通过,4 跳过 |
| autorestart | 13 通过,7 跳过 | 13 通过,7 跳过 | 13 通过,6 跳过,1 错误 |
| memory_checker | 3 通过,1 失败 | 4 通过 | 4 错误 |
| process_monitoring | 1 通过,1 失败 | 2 通过 | 2 错误 |
| copp | 28 跳过 | 28 跳过 | 28 跳过 |
| platform_tests/daemon | 28 跳过 | 28 跳过 | 28 跳过 |
| posttest | 4 通过,1 跳过 | 4 通过,1 跳过 | 3 通过,1 跳过,1 错误 |

计数是 `compare.py` 合并后的用例数:在 teardown 报错的用例只计一次,算作错误,不论其主体结果如何。junit 文件在 pretest 和 posttest 里还各计了一条采集阶段的跳过(`transceiver/oir`),表中不计。

## 3. 差异

### 3.1 R2 对 R3:同一个 Dockerfile 版镜像,分支对上游

结果不同的 8 个用例,都是 R2 通过、R3 报错:

| 用例 | R3 |
|---|---|
| memory_checker 的 `test_memory_checker`、`test_memory_checker_recover`、`test_monit_reset_counter_failure` | "Monit is not running after restarted!" |
| memory_checker 的 `test_memory_checker_without_container_created` | 同样的 monit 等待之后 teardown 报错 |
| process_monitoring 的 `test_monitoring_critical_processes`、`test_orchagent_heartbeat` | sanity 恢复时 "DUT vlab-01 did not startup" |
| autorestart 的 `test_containers_autorestart[telemetry]` | 同上,在 teardown |
| posttest 的 `test_collect_dualtor_logs` | 同上,在 teardown |

两条链都从 monit 被重启开始,重启来自 memory_checker 的 setup,或 teardown 里的 config reload。之后 monit 5.35 把 `arp_update_checker`、`container_eventd`、`controlPlaneDropCheck` 显示为 `Waiting`:

- memory_checker 自己的 `check_monit_running()` 等 400 秒后放弃(分支上由 `5d2fbdf` 修复)。
- 上游的 sanity monit 检查失败,恢复流程重启 DUT,再等待 banner `OpenSSH_[\w\.]+ Debian`。Ubuntu 的 banner 是 `OpenSSH_10.2p1 Ubuntu-2ubuntu3`,于是等待超时,之后每个用例都在恢复时报错(由 `db8849b` 和 `8b57ba6` 修复)。

没有其他用例结果不同,所以这次重构没有改变 supervisord 路径(设计 §6.3 验收标准 2)。

### 3.2 R1b 对 R2:同一个分支,rock 对 Dockerfile

有两个用例不同。

**`process_monitoring::test_monitoring_critical_processes`——rock 的差异。** 这个测试先把所有容器的 `auto_restart` 关掉,再依次杀掉每个关键进程,期待出现告警。在 R1 和 R1b 中,bgp 里的 zebra 被 `kill -SIGKILL` 之后,下一个关键进程 staticd 读到的是 `STOPPED`,teardown 时 bgp 容器已经不在运行。rock 容器把关键服务声明为 `on-failure: shutdown`,所以 pebble 会停掉整个容器。在 supervisord 下,`auto_restart` 关闭时只有被杀的程序退出,R2 通过。PR #28 把 `enabled` 以外的 `auto_restart` 取值列为 rock 不支持。这是产品侧的缺口;sonic-mgmt 不为它修改。

**`memory_checker::test_memory_checker_recover`——测试本身的竞争,不是 rock。** 这个测试让 gnmi 超过内存阈值,等 monit 报告一次失败,撤掉内存占用,期待不发生重启。测试期间的 monit 规则是 `if status == 3 for 2 times within 20 cycles`,周期 5 秒。在 R1b 中第二次检查仍然看到 445 MB,monit 重启了 gnmi。在 Dockerfile 版上单独运行,这个测试以同样方式 5 次失败 5 次(`memory_checker_recover-alone-on-dockerfile.txt`);它只在整组模块一起运行的 R2 中通过过。在容器里模拟同样的规则(先失败,monit 一显示失败就立刻撤掉条件),monit 5.34.3(Debian 13)和 5.35.2(Ubuntu 26.04)都会触发动作,因为测试看到第一次结果时,下一次检查已经开始了。这个测试在 Debian 版 vs 镜像上能否通过,这里没有验证。

`docker exec gnmi pkill -f time.sleep` 还会返回 -15:gnmi 与宿主共用 PID 命名空间,pkill 会杀掉整台交换机上命令行含该字符串的所有进程,包括执行它的 shell。复现时 pkill 也杀掉了占内存的进程,内存降到 78 MiB,所以这不是失败的原因。测试忽略了这个错误。

## 4. 实测发现的 sonic-mgmt 问题

| 问题 | 证据 | 提交 |
|---|---|---|
| sshd banner 正则有 14 处拷贝,只接受 `Debian` | deploy-mg 600 秒后超时;R3 里上游的 sanity 恢复 | `8b57ba6` |
| monit 5.35 把 `every N cycles` 的程序检查在第一次出结果前显示为 `Waiting`;sanity 不接受 | pretest 失败;容器里 2 秒周期下,5.34.3 在 2 秒时显示 `OK`,5.35.2 直到 18 秒都是 `Waiting` | `db8849b` |
| memory_checker 自己的 monit 就绪检查有同样的问题 | R1 中 memory_checker 的 4 个用例全部报错 | `5d2fbdf` |
| `/proc/stat` 的 btime 丢掉秒以下部分,绝对的启动时间窗口匹配不上 pebble 服务 | 部署后的 DUT 上差值为 0.18 秒,第一次抓取时为 1.0 秒;gnmi-native、dialout、rest-server、redis 丢了 pid | `a9175dc` |
| `modify_syslog_rate_limit()` 用 supervisorctl 重启 rsyslogd,并用容器里的 sed 改文件;database rock 里没有 sed | pretest 的 `test_disable_rsyslog_rate_limit` 在每个 rock 上失败 | `08d506e` |
| autorestart 还有两处在调用 supervisorctl | R1 中 10 个 rock 容器全部失败;bmp 和 syncd 通过 | `a6be7f4` |

`08d506e` 还把 `SonicHost.is_service_running()` 和 `dut_utils.verify_orchagent_running_or_assert()` 改为不依赖 supervisorctl。

## 5. 设计中待实测的类别

| 类别(设计 §6.3 验收标准 4) | 本次实测 |
|---|---|
| 版本命名 | 对所选测试没有影响(§1) |
| SNMP `sysDescr`、宿主 `bgpd.log` | 不在所选测试中;属于产品侧,留待之后 |
| Rust coreutils、docker 29、Python 3.14 | 所选测试中没有可归因于它们的失败 |
| 日志噪声(loganalyzer、dmesg) | 所选测试中没有 loganalyzer 失败 |
| sshd | banner 正则已修;deploy-mg 重启 sshd 不需要 7 月的本地补丁 |
| 7 月 conftest 的 `collect_ignore_glob` 补丁 | 用 `run_tests.sh -c` 指定测试时不需要 |

## 6. 没有做的

- 手头没有 Debian 版 vs 镜像,所以 `test_memory_checker_recover` 没有在 Debian 上运行。
- 其他测试领域:测试领域代码里还有 134 处直接调用 `supervisorctl`;copp 需要 t1-lag 拓扑;platform daemon 测试需要硬件。
- 多 ASIC 与 Dual-ToR 路径只有单元测试覆盖。
- 分支没有推送;产品侧事项(rock 的 `auto_restart` 缺口、SNMP `sysDescr`、`bgpd.log`、镜像版本命名)留待之后。
