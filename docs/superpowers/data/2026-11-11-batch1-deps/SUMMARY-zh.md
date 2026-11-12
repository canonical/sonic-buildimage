# 第一批四个容器的真实依赖（Task 4 审阅材料）

**采集日期**：2026-11-11
**对应设计**：`docs/superpowers/specs/2026-11-11-chiselled-rocks-batch1-design-zh.md` 6.2
**对应计划**：`docs/superpowers/plans/2026-11-11-chiselled-rocks-batch1-plan-zh.md` Task 4

## 1 · 采集方法与环境

| 项 | 内容 |
|---|---|
| broadcom | dut2（Dell S5232F），镜像 `HEAD.0-8b4c9d5b9`，只采 trace（与本机之间的链路约 150 KB/s，rootfs 导不回来） |
| VS | 本机 KVM 虚拟机，`~/Downloads/sonic-vs-img.zip`，镜像 `202605_resolute.0-7a081af43`；四个容器的 rootfs 也从这里导出 |
| 动态 | `scripts/rock-deps/trace.bt`（bpftrace 0.25，放在 `rockdeps-bpftrace:1` 镜像里运行），记录 `execve` 与 `openat` 的路径，按容器 cgroup 拆分 |
| 路径 | `hostcmds`（host 侧 `docker exec` 调用，见 `host-callers.txt` 与 `scripts/rock-deps/hostcmds.sh`）、`restart`、`reload`、`cold`、`warm`；mgmt-framework 另加 `cli`（host 上的 `sonic-cli`） |
| 静态 | 自建 deb、wheel 里的 ELF 和被 trace 到的 ELF 求 `DT_NEEDED` 闭包；radv 的 `/usr/sbin/radvd` 作为静态根（dut2 和 VS 都没配 IPv6 VLAN，radvd 从未启动过） |
| path→包 | resolute、resolute-updates、resolute-security 的 `Contents-amd64.gz`，取于 2026-11-11T14:04:47Z，sha256 见 `contents-SHA256SUMS` |
| slice 覆盖 | chisel-releases `origin/ubuntu-26.04@5500a56`，加上 PR #1104（rsyslog）、#1169（radvd）的 SDF（本地预览，未提交） |
| 复现 | `scripts/rock-deps/run-paths.sh <host> <outdir>`，然后 `scripts/rock-deps/analyze.py ...`（参数见 `reports/*.md` 首行和计划 Task 4） |

### 基线

| 路径 | dut2 | VS |
|---|---|---|
| hostcmds / restart / reload / cold | PASS | PASS |
| warm | PASS | **FAIL**：warm-reboot 后 swss、snmp、sflow 没起来；四个批次内容器正常 |

VS 的 warm 失败在改动前就存在，与本批次无关。按设计“基线先行”，VS warm 只验收四个容器本身，且不能出现新的失败。

## 2 · 结论总览

| | database | radv | eventd | mgmt-framework |
|---|---|---|---|---|
| slice 数（含 essential 前） | 96 | 78 | 63 | 92 |
| `chisel cut` 预览 | 通过，80 MB | 通过，79 MB | 通过，40 MB | 通过，85 MB |
| 缺 slice（需新写） | python3-cffi-backend | python3-cffi-backend | — | python3-cffi-backend |
| 待合并 PR | #1104 | #1104、#1169 | #1104 | #1104 |
| 只在 VS 或只在 broadcom 用到的 archive 包 | 无 | 无 | 无 | 无 |

删除项的逐条原因、症状与恢复方式见 `REMOVALS-zh.md`（用户 2026-11-11 审阅同意删除）。

完整 slice 清单：`reports/<容器>.slices.txt`；每个包的证据：`reports/<容器>.md`。

## 3 · 需要你确认的删除项

### 3.1 自建 deb（`dpkg -x`）

| deb | database | radv | eventd | mgmt-framework | 证据 |
|---|---|---|---|---|---|
| socat | 删 | 删 | 删 | 删 | 两个平台、六条路径都没有任何进程执行或打开它；database 里它现在就缺 `libwrap.so.0`，本来就跑不起来 |
| libdashapi | 删 | — | — | — | 从未被加载；database 里它现在就缺 `libprotobuf.so.32`，本来就加载不了 |
| sonic-eventd | 删 | 删 | **留** | 删 | 只有 eventd 用到（`eventd`、`eventdb`、rsyslog 插件） |
| sonic-db-cli | 留 | 留 | 删 | 删 | eventd、mgmt-framework 的脚本和 host 侧调用都不用它 |
| python3-swsscommon、python3-libyang | 留 | 留 | 删 | 留 | eventd 运行期不跑任何 Python（见 3.3） |
| libswsscommon、libyang3、sonic-supervisord-utilities-rs | 留 | 留 | 留 | 留（mgmt 没有 supervisord-utilities-rs） | |
| sonic-mgmt-common、sonic-mgmt-framework | — | — | — | 留 | |

删掉 socat 后，`libwrap0`、`libreadline8t64`（只被 socat 的 `filan`、`procan` 需要）也一起从清单里去掉了。

### 3.2 现有 `stage-packages` 里没有消费者的包

| 容器 | 删除 |
|---|---|
| database | `libnl-cli-3-200`（及 `_cls`、`_qdisc` slice）、`python3-venv`、`grep`（只在 DPU 分支用） |
| radv | `iproute2`、`jq`、`libdaemon0`、`libdbus-1-3`、`libjansson4`、`libnl-cli-3-200`、`net-tools`、`python3-redis`、`redis-tools`、`python3-venv` |
| eventd | `iproute2`、`libdaemon0`、`libdbus-1-3`、`libjansson4`、`libnl-cli-3-200`、`net-tools`、`python3-redis`、`python3-yaml`、`python3-cffi-backend`、`redis-tools`、`python3`、`libpython3.14`、`python3-venv` |
| mgmt-framework | `iproute2`、`libdaemon0`、`libdbus-1-3`、`libjansson4`、`libnl-cli-3-200`、`net-tools`、`python3-redis`、`redis-tools`、`python3-venv` |

`radvd` 在 radv 里保留：trace 没抓到是因为两台设备都不是 ToR 且没有 IPv6 VLAN，`start.sh` 在那种配置下才会启动它。

`jq` 在 radv、database 里没有消费者，但四个容器都带着 `/usr/bin/readiness_probe.sh`（KubeSonic 的 readiness 探针，用 jq 和 awk）。我们的部署不走 k8s，所以按口径删掉 radv 的 jq；database 本来就没有 jq。若要保留 KubeSonic 兼容，需要给 radv、database 加回 `jq_bins`。

### 3.3 eventd 去掉整个 Python 运行时

eventd 的 `start.sh` 只做 `pebble start eventd` 和 `eventdb_wrapper.sh`（bash + jq），六条路径里没有任何 Python 进程，也没有任何 `.py` 被打开。

提议：eventd 删除 `install-python` part（config-engine 的 wheel 和 jinjanator 等 PyPI 包）以及 python3 相关 slice。这会连带去掉 `container_startup.py`、`sonic-cfggen` 等 config-engine 文件。PyPI wheel 本身按口径“不处理”，这里删的是“没有消费者的 Python 运行时”，所以单列出来请你确认。

### 3.4 新增的必需项

| 容器 | 新增 | 原因 |
|---|---|---|
| mgmt-framework | `dash_bins`（`/bin/sh`） | `sonic-cli` 的 klish 通过 `/bin/sh` 执行动作 |
| mgmt-framework | `libcurl4t64`、`libxml2-16`、`libcjson1` 及其依赖 | klish（`/usr/sbin/cli/clish`）需要 |
| 全部 | `procps_bins`、`procps_ps-bin` | host 侧 `show services`（`docker exec <c> ps aux`）、`pgrep -x pebble`、`kill` |
| database | `procps_sysctl`、`iproute2_ip-bin` | `docker_image_ctl.j2` 的 `sysctl`，init 脚本的 `ip -4 -o addr` |

## 4 · 已知的覆盖缺口

- `/etc/gnutls/config`（libgnutls30t64）没有 slice 覆盖。它是可选的系统级优先级配置，缺省时 gnutls 用内建默认值，不补。
- mgmt-framework 的 klish 库在 `/usr/sbin/cli/.libs`，依赖 `clish_start` 里设置的 `LD_LIBRARY_PATH`，静态闭包按默认搜索路径解析时报“缺失”，属于误报。
- database 的 warm 路径 trace 偏少（tracer 容器在开机时与 database 抢启动顺序）；warm 专有分支只是 `cp`/`chown` dump.rdb，已由 cold 路径和静态审阅覆盖。

## 5 · `run-user: _daemon_`（按 2026-11-11 用户决定：四个 rock 全部切成 slice 后统一改用，database 的 redis 也用 `_daemon_`；见计划 Task 11a）

切 slice 阶段保持 root。下面是改用时要处理的点：

- database：去掉 redis 服务的 `user: redis`，改由 `run-user: _daemon_` 统一身份；init 脚本的 `chown -R redis:redis` 与绑定挂载的 `/var/run/redis` 属主要随之调整。
- radv：radvd 需要 raw socket。
- mgmt-framework：REST 服务监听 443；`sonic-cli` 本身已用 `-u uid:gid` 进入。
- eventd：最有希望，但 host 侧 `docker exec eventd ls /etc/rsyslog.d/...` 和 `docker cp` 需要文件可读，rsyslogd 需要 root；待验证。
