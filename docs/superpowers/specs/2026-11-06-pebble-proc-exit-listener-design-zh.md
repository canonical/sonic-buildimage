# pebble/rock 路径下补齐 supervisor-proc-exit-listener 功能 — 设计

- **日期：** 2026-11-06
- **状态：** 已评审通过（2026-11-06）
- **适用分支：** `202605_resolute`（rock + pebble 路径）；后续单独开 PR 实现
- **范围：** 单 ASIC；不改 Docker + supervisord 路径的行为

## 1. 背景与目的

Docker + supervisord 路径里，大多数容器（mgmt-framework、iccpd 等除外，见 §6.5）都跑一个 supervisord eventlistener
`supervisor-proc-exit-listener-rs`（`src/sonic-supervisord-utilities-rs`）。它负责：

1. 关键进程（`/etc/supervisor/critical_processes`）意外退出时，写 syslog、发布
   `sonic-events-host` / `process-exited-unexpectedly` 事件，并杀掉 supervisord，让容器退出、由 systemd 重启；
2. orchagent 心跳看门狗：心跳超时写 WARNING syslog。

rock + pebble 路径里没有 supervisord，也没有这个 listener。现状：

- 关键进程退出后，容器因 `on-failure: shutdown` 能够正常退出并被 systemd 重启，但**不发事件、不写 listener 那条 syslog**；
- orchagent 心跳没有任何检测；心跳行被 pebble 当普通 stdout 转进宿主机 syslog
  （dut2 上一天约 3200 行 `<!--XSUPERVISOR:BEGIN-->heartbeat<!--XSUPERVISOR:END-->`）。

本设计补齐这两项，使 rock 路径对外可观察的行为（syslog 文本、事件、告警节奏）与 Docker 路径一致。

## 2. 目标 / 非目标 / 反目标

**目标**
- 关键进程意外退出：rock 路径写出与 listener 相同文本的 syslog，并发布相同 source/tag/字段的事件。
- orchagent 心跳：rock 路径写出与 listener 相同文本、相同级别、相同节奏的卡死告警；心跳行不再进入 syslog。
- 两项功能由一个常驻 pebble 服务实现，复用现有 Rust 代码。

**非目标**
- `auto_restart` 不是 `enabled` 的场景（见 §7.1，作为已知缺陷记录）。
- `group:` 形式的关键进程条目（dhcp-relay 的问题，已推迟，见 §7.4）。
- 多 ASIC / 多 DB / chassis 的 namespace 处理。

**反目标**（技术上能用、但视为失败）
- 改变 Docker + supervisord 路径的任何运行方式。
- 在宿主机侧解析 pebble 日志文本来推断进程退出。
- 让 rock 依赖 Python swsscommon 来实现这项功能（eventd rock 里目前 `import swsscommon` 失败，见 §9）。

## 3. 约束

- `orchagent.sh` 同时被 supervisord 和 pebble 两条路径使用；pebble 专属逻辑必须放在运行时判断里，
  沿用 `dockers/docker-orchagent/start.sh` 中已有的写法 `if pgrep -x pebble > /dev/null 2>&1; then`。
  在 supervisord 路径里该判断为假（pgrep 不存在时同样为假），行为与现在逐字节一致。
- 不改 sonic-swss 子模块（orchagent 继续输出原心跳标记）。
- 所有 rock 都已有：`libswsscommon.so.0`、`CONTAINER_NAME` 环境变量、tmpfs `/tmp`、
  pebble socket `/var/lib/pebble/default/.pebble.socket`（dut2 上 14 个运行中的 rock 已逐一核实）。
- database rock 没有 `/usr/bin/sh`（chisel 有意裁掉），后续所有 rocks 都要裁掉 sh，新组件不得依赖 shell。

## 4. 原 listener 的行为（实现必须对齐的事实）

均出自 `src/sonic-supervisord-utilities-rs/src/proc_exit_listener.rs`；事件处理和告警都在 `main_with_parsed_args_and_stdin()` 的主循环里。

| 输入事件 | 处理 |
|---|---|
| `PROCESS_STATE_EXITED` | 关键进程且 `expected == 0`：`auto_restart == enabled` → `info!("Process '{}' exited unexpectedly. Terminating supervisor '{}'")`、发事件、deinit、SIGTERM 父进程 supervisord；否则加入 `process_under_alerting` |
| `PROCESS_STATE_RUNNING` | 仅把进程移出 `process_under_alerting` |
| `PROCESS_COMMUNICATION_STDOUT` | 进程在 `watchdog_processes` 中 → 记录 `last_heart_beat = 单调时钟 now` |
| 每次循环（poll 超时 1s） | `process_under_alerting` 每 60s 一条 ERR `... is not running ...`；心跳超过阈值则**每次循环**一条 WARNING `Process '{}' is stuck in namespace '{}' ({} minutes).`，无限速 |

其他细节：
- 事件：source `sonic-events-host`，tag `process-exited-unexpectedly`，字段 `process_name`、`ctr_name`（常量 `EVENTS_PUBLISHER_SOURCE`/`EVENTS_PUBLISHER_TAG`，函数 `publish_events()`）。
- 心跳阈值：启动时读一次 CONFIG_DB `HEARTBEAT|<proc>` 的 `alert_interval`（毫秒），缺省 60s；`0` 表示关闭（`load_heartbeat_alert_interval()`、`get_heartbeat_alert_interval()`，常量 `ALERTING_INTERVAL_SECS`）。
- 只有收到第一次心跳后才开始跟踪；从未收到心跳不告警。
- namespace：`NAMESPACE_PREFIX` 与 `NAMESPACE_ID` 都非空时为二者拼接，否则 `host`（`generate_alerting_message()`）。
- syslog tag 来自 `syslog` crate 的 `get_process_info()`，即**可执行文件名**；Docker 路径下为 `supervisor-proc-exit-listener-rs`。
- orchagent 心跳：`OrchDaemon::heartBeat()` 每 `heartBeatInterval`（缺省 10s，`-I` 可改，0 关闭）输出一行
  `<!--XSUPERVISOR:BEGIN-->heartbeat<!--XSUPERVISOR:END-->`，用 `endl` 立即刷出
  （`src/sonic-swss/orchagent/orchdaemon.cpp`）；warm restart 冻结期间也持续输出（`OrchDaemon::freezeAndHeartBeat()`）。
- 下游消费：sonic-mgmt 以文本 `Process 'orchagent' is stuck in namespace` 匹配卡死告警
  （`tests/system_health/test_watchdog.py`、`tests/process_monitoring/test_critical_process_monitoring.py`）。

**`auto_restart` 前提下的简化：** SONiC 默认所有 feature `auto_restart = enabled`。在此前提下
`process_under_alerting` 恒为空，`PROCESS_STATE_RUNNING` 无作用，"not running" 告警不会出现。
因此 pebble 版只需对应 EXITED（enabled 分支）和 STDOUT 两类。

## 5. 方案对比

| | A. 每个 rock 一个 Python reporter + bash exec check | **B. 现有 Rust listener 增加 pebble 模式（选定）** | C. 在 pebble 上重建 supervisord 事件协议 |
|---|---|---|---|
| 进程退出 | Python 脚本收 SIGTERM 后调 `pebble services` | Rust 收 SIGTERM 后直接访问 pebble API | pebble 无服务状态类 notice（只有 change-update/custom/warning），无法实现 |
| 心跳 | `orchagent.sh` 过滤 + pebble exec check，每 10s 一次，每次调 `sonic-db-cli` | `orchagent.sh` 过滤 + 同一 Rust 进程每秒检查 | pebble 不识别 stdout 标记 |
| 依赖 | 每个 rock 需要可用的 python3-swsscommon（eventd 已不满足） | libswsscommon（所有 rock 已有）+ 一个 deb | — |
| 与原行为一致性 | tag、告警节奏不同 | 文本、tag、级别、节奏、阈值来源均复用原代码 | — |
| 已验证 | 两项均在 dut2 上做过 spike | 机制与 A 相同（同一 pebble 行为、同一过滤器），只换实现语言 | — |

用户 2026-11-06 选定 B。理由：不引入 Python 依赖；与原 listener 共享代码和对外表现，sonic-mgmt 的匹配不受影响；运行时只有一个进程。

## 6. 设计

### 6.1 组件总览

```
rock 容器 (pebble PID 1)
├── rsyslogd                                    （各 rock 已有）
├── proc-exit-listener              ← 新 pebble 服务，requires+after rsyslogd
│     /usr/bin/supervisor-proc-exit-listener-rs --pebble
│     ├─ 每 1s：检查 watchdog 进程的心跳文件 mtime → 超时写 WARNING
│     └─ 收到 SIGTERM：GET /v1/services → error 且关键 → syslog + 事件 → exit 0
└── orchagent（仅 swss）
      orchagent.sh 在 pebble 下：exec orchagent > >(heartbeat_filter)
      heartbeat_filter：心跳行 → 刷新 /tmp/orchagent.heartbeat；其他行 → 原样给 pebble
```

### 6.2 关键进程意外退出

**触发链路**
1. 关键服务在 pebble plan 中为 `on-failure: shutdown`。服务非零退出时，pebble `exited()` 在
   `servicesLock` 内先 `HandleRestart(RestartServiceFailure)`，再把该服务置为 `stateExited`
   （pebble v1.33.2 `internals/overlord/servstate/handlers.go` 的 `serviceData.exited()`，`stateRunning` 下 `plan.ActionShutdown` 分支）。
2. 守护进程关停：`Daemon.stopRunningServices()`（`internals/daemon/daemon.go`）→ `servicesToStop()`
   只挑出 `starting/running/backoff` 状态的服务（`internals/overlord/servstate/manager.go`）。
   **已 exited 的服务不在停止列表里，不会被 stop，也就不会经过 `serviceForStop()` 里
   `stateExited → stateStopped` 的转换（`handlers.go` 的 `ServiceManager.serviceForStop()`）。**
3. 被停止的服务依次收到 `kill(-pgid, SIGTERM)`，状态 `running → terminating → stopped`（`handlers.go` 的 `serviceData.stop()`，以及 `serviceData.exited()` 的 `stateTerminating, stateKilling` 分支）。
   注意：即使它们因 SIGTERM 以非零码退出，走的也是 `stateTerminating` 分支，结果是 `stopped`，不是 `exited`。
4. HTTP API 在所有服务停完之后才关闭（`daemon.go` 的 `Daemon.Stop()` 先调 `stopRunningServices()`，之后才 `d.serve.Shutdown()`）。

**状态映射**（`manager.go` 的 `stateToStatus()`）：`exited → error`，`terminating/killing/stopped → inactive`。

**结论：** listener 收到 SIGTERM 时查询到的 `error` 状态，只可能来自"关停前已经自行非零退出"的服务。
其他关键服务被 pebble 停掉后是 `inactive`，不会被误判。dut2 实测快照：
`{'snmp-subagent': 'error', 'snmpd': 'inactive', ...}`（snmpd 先于 listener 被停，状态为 inactive）。

**判定规则**
- 收到 SIGTERM 时才读 `/etc/supervisor/critical_processes`（理由见 §6.4"延迟读取"）。
  文件不存在或无法解析：写一条 WARNING 后 `exit(0)`，不崩溃；文件为空（如 pmon）：不查询、不写日志，直接 `exit(0)`。
- `failed = { s | s.current == "error" 且 s.name 在 critical_processes 的 program: 条目中 }`
- 对每个 failed 服务：`info!("Process '{}' exited unexpectedly. Terminating supervisor '{}'", name, ctr)`，
  然后 `publish_events()`；全部完成后 `deinit()`，`exit(0)`。
  文本保留 "Terminating supervisor"，与 Docker 路径一致，便于现有日志匹配。
- `failed` 为空（`systemctl stop/restart`、`docker stop` 等正常停止）：不写、不发，`exit(0)`。dut2 已验证。
- "意外"的语义与原来一致：supervisord 以 `exitcodes`（缺省 0）判定 expected；pebble 下退出码 0 走
  `on-success: ignore` → `stopped`，既不触发关停也不是 `error`。

**pebble API 访问**
- socket：`$PEBBLE_SOCKET`，否则 `${PEBBLE:-/var/lib/pebble/default}/.pebble.socket`。
- 请求：`GET /v1/services`（HTTP/1.0 over Unix socket，读到 EOF），超时 2s。
- 响应（dut2 实测）：`{"type":"sync","status-code":200,"status":"OK","result":[{"name":"snmpd","startup":"disabled","current":"active","current-since":"..."}]}`。
- 不调用 `pebble` CLI，不 fork。
- 连接失败、超时或响应无法解析：写一条 ERR 后 `exit(0)`（关停仍由 pebble 完成，只是不上报）。

**时间预算：** pebble 对 listener 的 kill-delay 为缺省 5s。dut2 两次实测从收到 SIGTERM 到发完事件 40-50ms（Python 版）。

### 6.3 orchagent 心跳

**orchagent.sh（swss，pebble 分支）**

把现在最后一行
```bash
exec /usr/bin/orchagent ${ORCHAGENT_ARGS}
```
改为：
```bash
if pgrep -x pebble > /dev/null 2>&1; then
    # pebble has no supervisord stdout-capture: turn heartbeat lines into a file mtime for the watchdog
    HEARTBEAT_FILE=/tmp/orchagent.heartbeat
    rm -f "$HEARTBEAT_FILE"
    heartbeat_filter() {
        trap '' TERM    # keep draining until orchagent closes stdout
        local line
        while IFS= read -r line || [[ -n $line ]]; do
            if [[ $line == '<!--XSUPERVISOR:BEGIN-->heartbeat<!--XSUPERVISOR:END-->' ]]; then
                : > "$HEARTBEAT_FILE"
            else
                printf '%s\n' "$line"
            fi
        done
    }
    exec /usr/bin/orchagent ${ORCHAGENT_ARGS} > >(heartbeat_filter)
fi
exec /usr/bin/orchagent ${ORCHAGENT_ARGS}
```

要点：
- `> >(heartbeat_filter)` 是 bash 进程替换：bash 建一根管道并在子进程里运行过滤函数，orchagent 的 stdout 接到管道写端。
  不是重定向到文件：其余 stdout 照常进入 pebble 日志；文件为空、只用 mtime，不增长、无需轮转。
- 进程关系（dut2 实测）：orchagent（pid 159）是过滤子进程（pid 189）的父进程，二者同一进程组；
  pebble 停 orchagent 时 `kill(-pgid)` 两者都会收到 SIGTERM，过滤器忽略它并在 orchagent 关闭 stdout 后读到 EOF 退出。
- `rm -f` 保证每次 orchagent 启动都从"未收到心跳"开始，与 listener 的"首次心跳后才跟踪"一致。
- 心跳文件放在 tmpfs `/tmp`，容器重启即清空。
- 在 supervisord 路径中 `if` 为假，直接走原来的 `exec`。

**listener 看门狗循环（pebble 模式）**
- 每 1s 读一次 `/etc/supervisor/watchdog_processes`（可选，`program:` 条目；不存在即无看门狗进程，开销是一次 `stat`）。
- 每个 watchdog 进程对应心跳文件 `/tmp/<process>.heartbeat`。
- 某进程的心跳文件**第一次出现**时，读 CONFIG_DB `HEARTBEAT` 表取阈值（同原 `load_heartbeat_alert_interval()`），
  之后不再读；文件出现说明 orchagent 已在运行，DB 必然可用。读取失败按缺省 60s 处理。
- 每 1s：对每个进程 `stat` 心跳文件。
  - 文件不存在：不跟踪（清除该进程的跟踪状态）。
  - mtime 与上次看到的不同：记 `last_heart_beat = 单调时钟 now`。用单调时钟记录"观察到变化的时刻"，
    不直接拿 mtime 与墙钟相减，避免 NTP 跳变造成误报或漏报；语义与原 listener"收到事件的时刻"一致。
  - `threshold > 0 且 now - last_heart_beat >= threshold`：`generate_alerting_message(proc, "stuck", elapsed/60, LOG_WARNING)`。每次循环一条，与原 listener 相同（无限速）。
- 告警延迟：最多比原 listener 多约 1s（轮询间隔）。

### 6.4 二进制与参数

- 在 `sonic-supervisord-utilities-rs` 现有二进制 `supervisor-proc-exit-listener-rs` 上增加 `--pebble` 模式，
  不新增二进制。理由：syslog tag 取可执行文件名，保持 `supervisor-proc-exit-listener-rs` 与 Docker 路径一致；
  复用 `get_group_and_process_list`、`generate_alerting_message`、`publish_events`、`load_heartbeat_alert_interval`；
  打包仍是同一个 deb。
- `--container-name` 在 pebble 模式下允许缺省，取环境变量 `CONTAINER_NAME`（pebble 不展开 command 里的变量，所有 rock 都有该变量）。
- 不带 `--pebble` 时行为完全不变。
- **延迟读取（与原 listener 不同之处）。** pebble 模式启动时不读任何文件、不连 DB、不建 EventPublisher，直接进入 1s 循环；
  SIGTERM 中断循环并执行 §6.2。原因：
  - listener 随 rsyslogd 在 start.sh 之前启动（§6.5），而 swss（`dockers/docker-orchagent/start.sh`）、
    bgp（`dockers/docker-fpm-frr/start.sh`）、database（`dockers/docker-database/docker-database-init.sh`）
    的 `critical_processes` 是 start 阶段才渲染的；启动时读会因文件不存在而退出，或在 `docker start` 复用容器时读到上一次的旧文件；
  - database rock 启动早期 redis 尚未起来，启动时连 ConfigDB 会失败或阻塞；
  - 退出上报路径不需要 DB（不读 FEATURE 表，§7.1）。
- EventPublisher 在 SIGTERM 时才创建，用完 deinit。dut2 实验中 Python 版就是这样做的：创建、发布、deinit 共约 30ms，事件被 eventd 侧接收到（2026-10-29）。
- `group:` 条目：pebble 无对应概念，读取时忽略并写一条 WARNING。
- `critical_processes` 中不在 pebble plan 里的名字：查询结果里不会出现，自然忽略，不报错。

### 6.5 pebble 服务定义

**范围：与 Docker 路径对齐。** 只给 Docker 路径 supervisord 配置里有 `[eventlistener:supervisor-proc-exit-listener]` 的 rock 安装：
database、dhcp-relay、dhcp-server、eventd、fpm-frr（bgp）、lldp、macsec、nat、orchagent（swss）、platform-monitor、
router-advertiser、sflow、snmp、sonic-gnmi、sysmgr、teamd、`platform/broadcom/docker-syncd-brcm*`。
其中 dhcp-server 目前在 `build_rocks.sh` 中被注释掉、不构建，可留到它重新启用时再加。
**不装：** sonic-mgmt-framework、iccpd（Docker 路径也没有）。

在这些 rock 的 rockcraft.yaml 顶层 `services:` 中、紧跟 `rsyslogd` 之后，加入同一段定义：

```yaml
services:
  proc-exit-listener:
    command: /usr/bin/supervisor-proc-exit-listener-rs --pebble
    override: replace
    startup: enabled
    on-success: ignore
    requires: [rsyslogd]
    after: [rsyslogd]
```

- **`requires` 与 `after` 都必须写。** pebble 按 `requires` 划分 lane，不同 lane 并行停止；只写 `after`
  时 rsyslogd 与 listener 在不同 lane，rsyslogd 先停，listener 的 syslog 全部丢失（dut2 第 2 轮实验）。
  两者都写后停止顺序为 listener → rsyslogd（dut2 第 3 轮：exit-reporter 51.999 停，rsyslogd 52.017 停）。
- 不写 `on-failure`：pebble 默认值即 `restart`，listener 自身崩溃时由 pebble 重启，不拖垮容器。listener **不得**列入 `critical_processes`。
- 服务名不带 `supervisor-` 前缀：rock 里没有 supervisord；二进制与 deb 名沿用原名不变。
- 加载方式：与 `rsyslogd` 的定义方式相同，写在 rockcraft.yaml 里，由 rockcraft 生成进镜像自带的
  `/var/lib/pebble/default/layers/001-rockcraft-*.yaml`；pebble 启动时加载，listener 与 rsyslogd 一起在 start.sh 之前启动，
  不需要额外 layer 文件，也不需要改各 rock 的 start.sh。代价是 16 个 rock 各有一份相同的 8 行定义。

### 6.6 打包

- **为什么要装这个 deb：** rock 路径目前没有 listener，所以现有 rockcraft.yaml 都不引用它；方案 B 的可执行文件就是它。
  该 deb 只含一个文件 `/usr/bin/supervisor-proc-exit-listener-rs`（`debian/install`），运行依赖 libswsscommon（各 rock 已有）。
- **Docker 路径怎么装的：** `rules/docker-config-engine-resolute.mk` 把 `$(SONIC_SUPERVISORD_UTILITIES_RS)` 列入
  `docker-config-engine-resolute` 的 `_DEPENDS`，其 Dockerfile 安装这些 deb；各业务镜像以它为基础镜像继承，
  supervisord.conf 中以 `/usr/bin/supervisor-proc-exit-listener-rs --container-name <ctr>` 启动。
- **rock 路径怎么拿到：** `build_rocks.sh` 要求先完成整机镜像构建（届时该 deb 已作为 `docker-config-engine-resolute`
  的依赖生成），再把 `target/debs/resolute/` 下全部非 dbg deb 拷进每个 rock 的 `debs/`。因此不需要改 `rules/*.mk`，
  只需在 §6.5 列出的每个 rock 的 rockcraft.yaml 里 `dpkg -x debs/sonic-supervisord-utilities-rs_*.deb ${CRAFT_PART_INSTALL}`。
- swss rock：取消 `dockers/docker-orchagent/rockcraft.yaml` 中对 `watchdog_processes.j2` 的排除，
  把 `program:orchagent` 放到 `/etc/supervisor/watchdog_processes`（内容静态，可直接 organize，或在 start.sh 中渲染）。
- Docker 路径的 supervisord.conf、Dockerfile 不变。

## 7. 已知缺陷与限制

### 7.1 不支持 `auto_restart` 非 enabled（已知缺陷）
原 listener 在 `auto_restart` 不是 `enabled` 时，不杀 supervisord，而是保留容器运行并每 60s 写一条 ERR
`Process '<p>' is not running in namespace '<ns>' (<n> minutes).`，进程恢复 RUNNING 后停止告警。
rock 路径里关键服务固定 `on-failure: shutdown`，进程退出必然导致容器退出；本设计**不实现**这条分支：
- 退出时仍会写 "exited unexpectedly" 并发事件（不读 FEATURE 表）；
- 不会有 "not running" 周期告警。

如果将来需要支持：在 pebble 模式中读 FEATURE 表，`auto_restart` 非 enabled 时由 start.sh 把关键服务的
`on-failure` 改为 `ignore`，listener 每秒轮询 `/v1/services` 来维护 `process_under_alerting`，对应 EXITED/RUNNING 两类事件。

### 7.2 pebble 本身被 SIGKILL
OOM、`docker kill`、kill-delay 后的 SIGKILL 等情况下 listener 收不到 SIGTERM，不会上报。原 listener 在
supervisord 被强杀时同样无法工作，属同类限制。

### 7.3 关停窗口内的第二个退出
第一个关键服务退出触发关停后，在 `servicesToStop()` 取快照之前又自行退出的关键服务也会是 `error`，会被一并上报
（与事实相符）。快照之后再退出的服务走 terminating 分支变为 `inactive`，不会上报。原 listener 在杀掉
supervisord 后同样不再上报后续退出。

### 7.4 `group:` 条目不支持
dhcp_relay 的 `critical_processes` 是 `group:dhcp-relay`。pebble 没有 group 概念，这类条目被忽略，
对应进程退出时不会上报。这是相对 Docker 路径的真实差异，随 dhcp-relay 一起推迟处理。

### 7.5 与 Docker 路径一致、不属于缺陷的情况
dut2（镜像 `8b4c9d5b9`）上逐个核对了"`critical_processes` 中的名字是否在当前 pebble plan 里、是否为 `on-failure: shutdown`"。
下列不一致在 Docker 路径中同样存在，listener 的结果也相同，因此**不是缺陷**：
- radv：`radvd` 定义在单独的 `radvd-layer.yaml` 中，`start.sh` 仅在有 IPv6 VLAN 配置时 `pebble add` 并启动，
  与 `docker-router-advertiser.supervisord.conf.j2` 仅在 `vlan_v6.count > 0` 时渲染 `[program:radvd]` 一致。
  dut2 未配置，所以 plan 中没有 radvd。listener 在 SIGTERM 时才查询 plan（§6.4），加载后的 radvd 可正常被上报。
- syncd（brcm）：`critical_processes` 列有 `dsserve`，但 Docker 路径的 `platform/broadcom/docker-syncd-brcm/supervisord.conf`
  同样没有 `[program:dsserve]`。
- pmon：`dockers/docker-platform-monitor/critical_processes` 本身为空文件，两条路径相同。

其余 rock 的关键服务均在 plan 中且均为 `on-failure: shutdown`。

### 7.6 其他
- 卡死告警只写 WARNING，不发事件、不重启，与原 listener 相同。
- HEARTBEAT 表在每次容器运行中只读一次（心跳文件首次出现时），运行中改 `alert_interval` 需重启容器，与原 listener 相同。
- 不处理多 ASIC namespace（`NAMESPACE_*` 逻辑原样保留，未验证）。

## 8. 验证

**单元测试（cargo test）**
- pebble API 响应解析与 failed 判定：error+关键 → 上报；inactive/active → 不上报；不在关键列表 → 不上报；空结果。
- `critical_processes` 不存在 / 为空 / 含 `group:`：不崩溃，不上报（group 写 WARNING）。
- pebble API 不可达或超时：写 ERR，`exit(0)`。
- 心跳：文件不存在不告警；mtime 变化刷新；超阈值告警文本/级别；阈值 0 关闭；缺省 60s。
- 用临时目录下的假 Unix socket 模拟 pebble API。

**dut2 实机（单 ASIC，S5232F）**
1. `kill -9` 某 rock 的一个关键进程：syslog 出现
   `<ctr>#supervisor-proc-exit-listener-rs: Process '<p>' exited unexpectedly. Terminating supervisor '<ctr>'`
   和 `EVENT_PUBLISHED ... process-exited-unexpectedly`；`docker logs` 中 listener 先于 rsyslogd 停止；容器退出码 10。
2. `systemctl restart <svc>`：无上述 syslog、无事件。
3. swss：重启后 syslog 不再有 `XSUPERVISOR` 行；`/tmp/orchagent.heartbeat` 每 10s 更新；
   `kill -STOP <orchagent>` 超过 60s 出现 `Process 'orchagent' is stuck in namespace 'host' (1 minutes).`（约每秒一条），
   `kill -CONT` 后停止。
4. 事件接收：在 eventd 中 `events_tool -r -n 1` 收到 `process-exited-unexpectedly` 的完整内容。

**Docker 路径回归**
- `orchagent.sh` 在无 pebble 的环境中走原 `exec`：对比 supervisord 下 orchagent 的父进程与 stdout 管道（`ls -l /proc/<pid>/fd/1` 指向 supervisord 的管道），心跳仍被 listener 接收。
- `supervisor-proc-exit-listener-rs` 不带 `--pebble` 的现有测试全部通过。

## 9. 实验记录（spike，均已清理）

| 日期 | 镜像 / pebble | 内容 | 结果 |
|---|---|---|---|
| 2026-10-29 | `dd6d0891a` / v1.33.0 | snmp：Python reporter，`kill -9` 关键进程，三轮调整服务依赖 | 第 3 轮（requires+after rsyslogd）syslog 与事件完整；反向测试 `systemctl restart snmp` 无事件 |
| 2026-11-05 | `8b4c9d5b9` / v1.33.2 | snmp：同上，改读镜像自带 `critical_processes` | 收到 SIGTERM 后 49ms 完成；`snmp-subagent: error`、`snmpd: inactive`；listener 51.999→rsyslogd 52.017 |
| 2026-11-05 | `8b4c9d5b9` / v1.33.2 | swss：`orchagent.sh` 过滤 + pebble exec check，`kill -STOP` 150s | syslog 无新心跳行；冻结后 68s 首条 stuck 告警，分钟数 1→2；恢复后告警停止；orchagent 停止耗时 2.58s（对照 2.63s） |
| 2026-11-06 | `8b4c9d5b9` / v1.33.2 | 实现版（Rust `--pebble`）部署到 snmp、eventd、database、swss 的可写层验证 | 4 个容器 listener 启动即 active、无重启循环；snmp/eventd/database `kill -9` 关键进程后十几毫秒内（snmp 16ms、database 13ms）写出 `<ctr>#supervisor-proc-exit-listener-rs: Process '<p>' exited unexpectedly. Terminating supervisor '<ctr>'` 并 `EVENT_PUBLISHED`，listener 先于 rsyslogd 停止；eventd 侧 `events_tool -o` 收到完整事件；`systemctl restart snmp` 无上报；swss syslog 无心跳行，冻结 orchagent 后约 60s 起每秒一条 `Process 'orchagent' is stuck in namespace 'host' (1 minutes).`，转为 `(2 minutes)`，解冻后停止 |

v1.33.0 → v1.33.2 的 pebble 改动未涉及服务关停与状态机（仅日志、metrics 名称、check 参数校验）。

附带发现（不在本设计范围）：eventd rock 中 `python3 -c 'import swsscommon.swsscommon'` 报
`libpython3.14.so.1.0: cannot open shared object file`。

## 10. 留给实现者

- 信号处理方式（`signal-hook` 或 nix + self-pipe）与 1s 循环的组织方式。
- HTTP over Unix socket 的实现（std `UnixStream` + `serde_json`，后者已在 Cargo.lock 中，需从 dev-dependencies 提为 dependencies）。
- 各 rock rockcraft.yaml 与 rules 的具体改动清单。
