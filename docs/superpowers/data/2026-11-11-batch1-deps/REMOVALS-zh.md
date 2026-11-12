# 第一批四个容器的删除记录（排障参考）

**用途**：第一批 rock 改造时删掉的每一项都记录在这里。它们都是“在已测场景里没有发现消费者”而删的，**不等于确认不需要**。线上或新场景出现问题时，先按本表的“判断错时的症状”比对，再按“恢复方式”加回。
**依据**：`SUMMARY-zh.md`（2026-11-11 采集）；证据原文在 `reports/<容器>.md`、`traces/`、`host-callers.txt`。
**决定**：2026-11-11 用户审阅同意删除。

## 证据口径（下表各列的含义）

- **动态**：dut2（broadcom，`HEAD.0-8b4c9d5b9`）与 sonic-vs（`7a081af43`）上，bpftrace 记录的 `execve`/`openat`，覆盖的场景：
  - `hostcmds`（host 侧 `docker exec` 命令，`scripts/rock-deps/hostcmds.sh`）
  - `restart`（`systemctl restart radv eventd mgmt-framework`）
  - `reload`（`config reload -y`）
  - `cold`（`systemctl restart database`，即全部容器重启）
  - `warm`（`warm-reboot`）
  - `cli`（仅 mgmt-framework：host 上的 `sonic-cli`）
  “0 次”指上述所有场景、两个平台都没有任何进程执行或打开该包的任何文件。
- **静态**：在容器自己的脚本、模板、pebble layer（`dockers/<容器>/` 除 Dockerfile/supervisord 文件外）、共享脚本（`container_startup.py`、`readiness_probe.sh`、`update_chassisdb_config`、`syslog-layer.yaml`、`rsyslog.conf`），以及 host 侧调用清单（`host-callers.txt`）里 grep 命令名或模块名。
- **未覆盖的场景**（下列场景一律没测，删除项若出问题最可能出在这里）：
  - chassis（linecard / supervisor，`chassisdb.conf` 存在）
  - DPU / smart switch（`DATABASE_TYPE=dpudb`、`IS_DPU_DEVICE`）
  - multi-ASIC（`NAMESPACE_ID`、`NAMESPACE_COUNT>1`）
  - KubeSonic（`RUNTIME_OWNER=kube`、k8s readiness 探针）
  - ToR 角色 + IPv6 VLAN（radvd 实际运行）
  - 配置了 REST 证书、客户端认证等非默认 mgmt 配置
  - techsupport（`show techsupport` / `generate_dump`）全流程
  - fast-reboot、配置了 `/etc/evprofile/default.json` 事件的 eventdb

## 1 · 自建 deb（`dpkg -x`）

| 容器 | 删除项 | 动态 | 静态 | 判断错时的症状 | 恢复方式 |
|---|---|---|---|---|---|
| database、radv、eventd、mgmt-framework | `socat`（含 `socat1`、`filan`、`procan`） | 0 次 | 容器脚本、共享脚本、host 侧调用均无 `socat` | `socat: command not found`；host 侧经 `docker exec` 用 socat 转发 redis 或 unix socket 的工具失败 | 加回 `dpkg -x debs/socat_*.deb`，并加回 `libwrap0_libs`、`libreadline8t64_libs` |
| database | `libdashapi` | 0 次 | 无 `dash_api`/`libdashapi` 引用 | DPU / smart switch 场景下 DASH 相关 Python 模块 `import dash_api` 失败 | 加回 `dpkg -x debs/libdashapi_*.deb`；它还需要 `libprotobuf.so.32`（`libprotobuf32t64`，26.04 上尚无 slice，需新写） |
| database、radv、mgmt-framework | `sonic-eventd` | 0 次（只有 eventd 容器用到 `eventd`、`eventdb`、rsyslog 插件） | 三个容器的脚本、pebble 服务都不调用 | 这三个容器内的 rsyslog 配置若引用 eventd 的 rsyslog 插件（`omprog` 调 `rsyslog_plugin`），日志事件不再上报 | 加回 `dpkg -x debs/sonic-eventd_*.deb` |
| eventd、mgmt-framework | `sonic-db-cli` | 0 次 | 脚本不用；host 侧 `docker_image_ctl.j2` 只对 database 和 chassis 场景的 `${DOCKERNAME}` 调 `sonic-db-cli`（L150-152、L286、L344、L358） | chassis 场景下 host 对这两个容器 `docker exec ... sonic-db-cli` 报 `not found` | 加回 `dpkg -x debs/sonic-db-cli_*.deb` |
| eventd | `python3-swsscommon`、`python3-libyang` | 0 次 | eventd 的 `start.sh`、`eventdb_wrapper.sh` 只用 bash、jq；`host_events_info.json` 里的 `"python3"` 是事件匹配名，不是调用 | 见第 3 节 | 见第 3 节 |

## 2 · 原 `stage-packages` 里的 Ubuntu 包

| 容器 | 删除项 | 动态 | 静态 | 判断错时的症状 | 恢复方式（slice） |
|---|---|---|---|---|---|
| 全部 | `libnl-cli-3-200` | 0 次；自建 deb 的 ELF `DT_NEEDED` 只有 `libnl-3`、`libnl-nf-3`、`libnl-route-3` | 无 `nl-*` 命令 | 某个自建程序 `dlopen` libnl-cli（静态闭包看不到 dlopen）时报 `cannot open shared object file: libnl-cli-3.so.200` | `libnl-cli-3-200_cls`、`libnl-cli-3-200_qdisc`（该 SDF 只有这两个功能 slice） |
| 全部 | `python3-venv` | 0 次 | 26.04 的 `plugin: python` 是 v2，不建 venv | 构建期如果 python 插件改回需要 venv 的行为，`pack` 失败（不是运行期问题） | 构建报错时按提示加 `python3.14-venv_ensurepip` |
| database | `grep` | 0 次 | 只有 `docker-database-init.sh:33` 用，位于 `DATABASE_TYPE=dpudb` 分支；host 侧 4 处 `grep` 都在管道的 host 一侧 | DPU 场景 database 启动时 `grep: command not found`，导致 host_ip 判断错 | `grep_bins` |
| radv、eventd、mgmt-framework | `iproute2` | 0 次 | 脚本不用；host 侧 `docker_image_ctl.j2:263` 的 `docker exec ${DOCKERNAME} ip addr show eth1-midplane` 只针对 chassis linecard 的 database | 有人进容器调 `ip` 排障时找不到命令 | `iproute2_ip-bin` |
| radv、eventd、mgmt-framework | `net-tools` | 0 次 | 无 `ifconfig`/`netstat`/`route`/`arp` | 同上，`ifconfig` 等找不到 | `net-tools_bins` |
| radv、eventd、mgmt-framework | `libdaemon0`、`libdbus-1-3`、`libjansson4` | 0 次；无任何 ELF 需要 | — | 加载某个自建程序时报缺 `.so` | `libdaemon0_libs`、`libdbus-1-3_libs`、`libjansson4_libs` |
| radv、eventd、mgmt-framework | `python3-redis` | 0 次（无 `redis/` 模块被打开） | 无 `import redis` | Python 脚本 `ModuleNotFoundError: No module named 'redis'` | `python3-redis_libs` |
| radv、eventd、mgmt-framework | `redis-tools` | 0 次 | 无 `redis-cli` | 进容器排障时 `redis-cli` 找不到 | `redis-tools_bins` |
| eventd | `python3-yaml`、`python3-cffi-backend`、`python3`、`libpython3.14` | 0 次 | 见第 3 节 | 见第 3 节 | 见第 3 节 |

## 3 · eventd 的整个 Python 运行时

| 项 | 内容 |
|---|---|
| 删除 | `install-python` part（config-engine 的 5 个 wheel，以及 jinjanator、click、pyangbind、lxml）；python3 相关 slice；`python3-swsscommon`、`python3-libyang` 两个自建 deb；随之不再有 `container_startup.py`、`sonic-cfggen`、`jinjanate` |
| 动态 | 六条路径、两个平台都没有 Python 进程，也没有打开任何 `.py` 或 `python3.14` 下的文件 |
| 静态 | `start.sh`：`pgrep`、`pebble add/start`、`eventdb_wrapper.sh`；`eventdb_wrapper.sh`：`jq`、`exec /usr/bin/eventdb`。eventd 的 `start.sh` 不调用 `container_startup.py`（radv 的会调） |
| 判断错时的症状 | KubeSonic 或其他运行时若期望 eventd 里执行 `container_startup.py`、`sonic-cfggen`，会报 `python3: not found` 或文件不存在；host 侧若有工具 `docker exec eventd python3 ...` 也会失败 |
| 恢复方式 | 加回 `install-python` part 与 `python3.14-minimal_bins`、`python3-minimal_python3`、`libpython3.14-minimal_libs`、`libpython3.14-stdlib_core`、`libpython3.14_libs`；加回 `python3-swsscommon`、`python3-libyang` 的 `dpkg -x`，以及 `python3-cffi-backend` 的 slice |

## 4 · 有意不补的覆盖缺口

| 容器 | 路径 | 原因 | 判断错时的症状 |
|---|---|---|---|
| 全部 | `/etc/gnutls/config`（libgnutls30t64） | 可选的系统级优先级配置，缺省时 gnutls 用内建默认值；chisel-releases 里没有 slice 覆盖它 | rsyslog-relp 的 TLS 行为与 Ubuntu 默认不同（只有启用 TLS 的 RELP 才会遇到） |

## 5 · 粗粒度 slice 拆细后少掉的部分（Task 8 起）

只保留 trace 与 ELF 闭包证明用到的子 slice；原粗粒度 slice 里其余文件不再进 rock。

| 容器 | 原 slice | 现在保留 | 判断错时的症状 | 恢复方式 |
|---|---|---|---|---|
| database | `coreutils_bins` | `coreutils_{cat,chown,cp-bin,cut,echo,env,expr,head,mkdir,rm-bin,sleep,touch,tr-bin}` | 进容器排障或新脚本调用 `ls`、`mv`、`date` 等报 `executable file not found` / `command not found` | 加对应的 `coreutils_<命令>`，或整个 `coreutils_bins` |
| database | `iproute2_bins` | `iproute2_ip-bin`、`iproute2_config` | `ss`、`bridge`、`tc` 等找不到 | 加 `iproute2_bins` |
| database | `python3.14_standard` | `libpython3.14_libs`、`libpython3.14-stdlib_{data-types,internet,zstd}` 及其 essential | 某个 Python 路径 `ModuleNotFoundError: No module named '<stdlib 模块>'` | 按模块所在加 `libpython3.14-stdlib_<组>`（`grep -n '<模块>.py' slices/libpython3.14-stdlib.yaml`），或整个 `python3.14_standard` |
| database | `python3-venv` 整包依赖链（`python3.14-venv` → `python3-pip-whl` → `ca-certificates` → `openssl`） | 只保留 `openssl_config`（import `swsscommon` 时打开 `/usr/lib/ssl/openssl.cnf`） | 容器内需要 CA 证书的 TLS 客户端校验失败；需要 `openssl` 命令的脚本找不到 | 加 `ca-certificates_data-with-certs`、`openssl_bins` |

| radv | `coreutils_bins` | `coreutils_{cat,chmod,cut,echo,env,mkdir,rm-bin,sleep,touch}` | 进容器排障或新脚本调用 `ls`、`mv`、`date` 等报 `executable file not found` / `command not found` | 加对应的 `coreutils_<命令>`，或整个 `coreutils_bins` |
| radv | `python3.14_standard` | `libpython3.14_libs`、`python3-yaml_libs`、`python3-cffi-backend_libs` 及其 essential | 某个 Python 路径 `ModuleNotFoundError: No module named '<stdlib 模块>'` | 同 database 行 |
| radv | `python3-venv` 整包依赖链 | 只保留 `openssl_config` | 同 database 行 | 同 database 行 |
