# sonic-mgmt 支持 Ubuntu(Resolute)SONiC 与 rock 容器 — 设计

- 日期:2026-11-10
- 测试仓库分支:`canonical/sonic-mgmt` 的 `202605_resolute`(新建),基于 `sonic-net/sonic-mgmt` `202605` 的 `36c29fc`
- 被测镜像:`canonical/sonic-buildimage` `202605_resolute` 的 `7a081af43c`
  - rock + pebble 版 vs 镜像:CI 运行 42562456825 的 artifact `sonic-vs-img`
  - Dockerfile + supervisord 版 vs 镜像:同一 commit 在本地构建
- 本文为中文版;英文版(`-en.md`)为唯一事实来源

## 1. 目标与范围

用同一份测试代码,让 sonic-mgmt `202605` 的测试同时跑 `202605_resolute` 的两种构建模式:supervisord 管理的 Dockerfile 容器,和 pebble 管理的 rock 容器。两个镜像结果不同时,差异必须来自镜像本身,而不是测试框架里的假设。

**范围内:**

1. 在 `SonicHost` 里提供 supervisord / pebble 双后端的容器进程接口,并把 §4.5 列出的公共辅助函数迁移过去。
2. OS 画像辅助函数,以及按 Debian codename 分支的 4 处调用点(§5)。
3. 在两个镜像上做 A/B 实测,并对剩下的每一处差异归类(§6)。

**不在范围内:** 迁移各测试里直接拼写的 134 处 `docker exec <容器> supervisorctl`(之后按测试领域逐个迁移);修复产品侧问题,例如 SNMP `sysDescr` 的文字、宿主上缺失的 `/var/log/frr/bgpd.log`、镜像版本命名(先由 A/B 实测归类);PTF 主机上的 `supervisorctl`;在多 ASIC、Dual-ToR、机框 testbed 上的运行验证(没有环境);推回 sonic-net 上游。

## 2. 已定决策

| 议题 | 决定 |
|---|---|
| 兼容层放在哪 | 放在 sonic-mgmt。镜像按构建出来的原样测试 |
| 后端识别 | 按容器、在查询时、在容器内识别。不缓存 |
| 迁移范围 | 公共辅助函数和取 pid / kill 类辅助函数。直接调用的地方之后按测试领域迁移 |
| pebble 容器里的 `group:` 条目 | 读容器内 `/etc/supervisor/conf.d/*.conf` 里渲染出来的 `[group:X]` 段。读不到定义的组判检查失败 |
| 状态词 | 用 supervisord 的状态名;pebble 原生状态一并保留 |
| 操作系统判断 | 按 Debian 基线代际判断,不比较 codename 字符串 |
| 其他 Ubuntu 差异(版本命名、SNMP、coreutils、docker 29、Python 3.14、日志噪声、sshd) | A/B 实测之后按结果再定 |
| 7 月的两个本地补丁(deploy-mg 重启 `ssh.service`、conftest 的 `collect_ignore_glob`) | 不带。A/B 实测表明需要时再加回 |

## 3. 已验证的事实

下列各项都在本设计之前确认,没有推断。

| 事实 | 证据 |
|---|---|
| rock 镜像带 `/etc/supervisor/critical_processes` 和 bash,但没有 `supervisorctl` | 16 个 `rockcraft.yaml` stage 了这个文件;database、orchagent、fpm-frr 在启动脚本里渲染;database rock(`base: bare`)stage 了 bash |
| sonic-mgmt 依据 `docker exec X supervisorctl status` 判断进程健康;输出为空或无法识别时判容器不健康 | `tests/common/devices/sonic.py` 的 `SonicHost.all_critical_process_status()` 与 `parse_service_status_and_critical_process()` |
| sanity 检查与 `config reload`、重启之后的等待都用这同一个函数,所以 `--skip_sanity` 绕不过 | `sanity_check/checks.py` 的 `check_processes`;`platform/processes_utils.py` 的 `wait_critical_processes()` |
| `pebble services --format json` 返回 `name`、`startup`、`current`、`current-since`,没有 pid;文本输出的 `Since` 列含空格(`today at 07:40 UTC`) | 在 docker-teamd rock 上实测,pebble 1.33 |
| 每个 pebble 服务都是 pebble 的直接子进程,并自成进程组组长;程序不 exec 时,argv 与服务的 command 相同 | 同一次实测:`sleep 1000` 服务 pid = pgid = 56,ppid 为 1 |
| 同一台交换机上两种后端并存:rock 版 vs 镜像有 17 个 rock 容器,syncd、mux、stp、dhcp-server 等仍是 supervisord | `build_rocks.sh --list` |
| dhcp-relay rock 启动时把 `docker-dhcp-relay.supervisord.conf` 渲染到 `/etc/supervisor/conf.d/`,其中有 `[group:dhcp-relay] programs=dhcprelayd,...` | `dockers/docker-dhcp-relay/start.sh`(pebble 分支) |
| 测试从 `supervisorctl status` 一行的 `split()[1]` 取状态、`split()[3]` 取 pid;pmon 守护进程测试在 stop 之后断言 `STOPPED` | `get_pmon_daemon_status()`;`dut_utils.py` 与 `test_container_autorestart.py` 里的 `get_program_info()` / `get_group_program_info()`;`tests/platform_tests/daemon/test_*.py` |
| Ubuntu:`VERSION_CODENAME=resolute`,`/etc/debian_version` 为 `forky/sid`。Debian 202605:`trixie`、`13.5` | 两边的根文件系统 |
| 两个镜像没有差异的项:sudo(C 版 sudo 1.9.x,不是 sudo-rs);bash 带 plugin 补丁和 `bash_tacplus`;sysctl 文件为 `/usr/lib/sysctl.d/90-sonic.conf`;chrony;OpenSSH 10.x;`sonic_version.yml` 里 `release: 'none'` | 两边根文件系统的包与文件对比 |

同一次实测观察到的 pebble 状态:

| 情形 | `current` | `current-since` |
|---|---|---|
| 运行中 | `active` | 有 |
| 用 `pebble stop` 停止后 | `inactive` | 有 |
| 退出码 0,且 `on-success: ignore` | `inactive` | 有 |
| 退出码 1,且 `on-failure: ignore` | `error` | 有 |
| 等待重启 | `backoff` | 有 |
| 从未启动 | `inactive` | 无 |

## 4. 组件 1:容器进程接口

### 4.1 模块与数据结构

新模块 `tests/common/helpers/container_processes.py`,只用标准库,不依赖 Ansible 也能导入(与 `ansible/module_utils/sonic_release_utils.py` 同样的要求)。

`ProcessInfo`:

| 字段 | 含义 |
|---|---|
| `name` | 不带组名的程序名 |
| `group` | 组名,或 `None` |
| `state` | `RUNNING`、`STOPPED`、`EXITED`、`FATAL`、`BACKOFF`、`STARTING` 之一 |
| `pid` | 容器命名空间内的 pid;没在运行或没解析出来时为 `-1` |
| `raw_state` | 后端自己的状态词 |
| `pid_note` | 进程在运行但 `pid` 为 `-1` 的原因 |

`full_name` 在有组时返回 `组名:程序名`,否则返回 `name`。

`ContainerProcesses`:`container`、`backend`(`"supervisord"`、`"pebble"` 或 `None`)、`running`、`processes`、`critical_groups`、`critical_programs`、`critical_file_found`、`error`。`get(name)` 接受带组名或不带组名的名字。

函数:`build_probe_command(container)`、`parse_probe_output(container, rc, stdout)`、`build_control_command(container, action, names)`,以及它们调用的各后端解析器。

### 4.2 探针

每个容器一条命令:`docker exec <容器> bash -c '<脚本>'`。命令保留 `docker exec <容器>` 前缀。脚本只用 bash 内建命令,这样不依赖各个 rock 各自 stage 了哪些工具(例如 database rock 里没有 `sed`)。输出分成若干段,每段以标记行 `@@<段名>@@` 开头:

| 段 | 内容 |
|---|---|
| `backend` | `pebble services` 成功时为 `pebble`;否则 `supervisorctl` 在 `PATH` 里时为 `supervisord`;否则为 `unknown` |
| `critical` | `/etc/supervisor/critical_processes` 的内容,或标记 `@@critical-missing@@` |
| `status`(supervisord) | `supervisorctl status` |
| `services`(pebble) | `pebble services --format json` |
| `plan`(pebble) | `pebble plan` |
| `procs`(pebble) | 每个进程一行:pid、ppid、pgid,再接以 `\x1f` 连接的 argv(用 `mapfile -d ''` 从 `/proc/<pid>/cmdline` 读取) |
| `groups`(pebble) | `/etc/supervisor/conf.d/*.conf` 里的 `[group:...]` 段 |

`docker exec` 返回非零表示容器没在运行。

### 4.3 解析规则

**supervisord:** 保持现有规则:每行拆成名字、状态和其余部分;状态不在 6 个词之内,结果判无效;`RUNNING` 时从 `pid N,` 取 pid;`组名:程序名` 给出组。

**pebble:**

| `current` | `state` |
|---|---|
| `active` | `RUNNING` |
| `backoff` | `BACKOFF` |
| `error` | `EXITED` |
| `inactive` | `STOPPED` |

已知局限:正常退出的一次性服务显示为 `STOPPED`,而 supervisord 显示 `EXITED`。一次性服务都不是关键进程,现有测试在进程停止后两个词都接受。

组成员:`[group:G]` 段里的 `programs=` 列表把其中的名字归入组 `G`。

运行中服务的 pid 按下列顺序解析,第一条恰好得到一个进程的规则生效:

1. 在 argv 等于 `shlex.split(command)` 的那个 pebble 子进程所在的进程组里,取 argv[0] 的 basename 等于服务名的进程。这样能找到包装脚本背后的那个程序,例如 `orchagent.sh` 背后的 orchagent,与 supervisord 在包装脚本 `exec` 之后报告的进程一致。
2. argv 等于 `shlex.split(command)` 的 pebble 子进程。
3. 自成进程组组长、且 argv[0] 的 basename 与 command 的 argv[0] basename 相同的 pebble 子进程。

都不满足时 `pid` 为 `-1`,`pid_note` 写明哪条规则没有匹配上。`plan` 段是 YAML,解析用 PyYAML,docker-sonic-mgmt 里已经有。

### 4.4 控制

`build_control_command(container, action, names)`(`action` 为 `start`、`stop` 或 `restart`)生成一条保留 `docker exec <容器>` 前缀的命令,在容器内分支:pebble 下执行 `pebble <action>`,并去掉每个名字的组前缀;supervisord 下执行 `supervisorctl <action>`,名字不变。两种后端下,成功返回 0,失败返回非零。

### 4.5 SonicHost 接口与迁移的辅助函数

`SonicHost` 新增方法:

- `get_container_processes(container)` 返回 `ContainerProcesses`。
- `get_containers_processes(containers)` 把多个探针放进一次 `shell_cmds` 批量执行,按位置对应结果,不再从命令串里解析容器名。
- `control_container_process(container, action, names, module_ignore_errors=False)`。

改为调用新接口的辅助函数,签名与返回值都不变:

| 文件 | 函数 |
|---|---|
| `tests/common/devices/sonic.py` | `get_critical_group_and_process_lists`、`critical_group_process`、`critical_process_status`、`all_critical_process_status`、`start_pmon_daemon`、`stop_pmon_daemon_service`、`get_pmon_daemon_status`、`get_pmon_daemon_states`、`kill_bgpd`、`start_bgpd` |
| `tests/common/helpers/dut_utils.py` | `get_program_info`、`get_group_program_info` |
| `tests/autorestart/test_container_autorestart.py` | `get_program_info`、`get_group_program_info` |
| `tests/process_monitoring/test_critical_process_monitoring.py` | 把已停止的关键进程重新拉起的那处 `supervisorctl start` |

`parse_service_status_and_critical_process()` 保持公开且不变,供其他调用方使用。

### 4.6 出错处理

| 情况 | 结果 |
|---|---|
| 容器没在运行 | `running=False`;关键进程状态为 `False`,与现在相同 |
| 后端为 `unknown` | 设置 `error`;关键进程状态为 `False` |
| 缺少 `critical_processes` | 与现在相同:名单读不出来,状态为 `False` |
| pebble 容器里 `group:` 条目读不到定义 | 状态为 `False`;`error` 写明组名 |
| 进程在运行但没解析出 pid | `pid=-1`,设置 `pid_note`;不影响关键进程状态 |
| JSON 或 YAML 无法解析 | 设置 `error`;关键进程状态为 `False` |

## 5. 组件 2:OS 画像

新模块 `tests/common/helpers/os_profile.py`,只用标准库。

`parse_os_profile(os_release_text, debian_version_text)` 返回 `OsProfile(id, version_id, codename, debian_base)`:

- Debian:`debian_base` 就是它的 codename。
- Ubuntu:`debian_base` 取自 `/etc/debian_version`。`forky/sid` 得到 `forky`;纯数字按大版本映射(10 `buster`、11 `bullseye`、12 `bookworm`、13 `trixie`、14 `forky`)。
- 其他取值得到 `debian_base=None`。

`debian_base_at_least(name)` 按 `buster < bullseye < bookworm < trixie < forky < duke` 的顺序比较,`debian_base` 为 `None` 时返回 `False`。

`SonicHost.os_profile(container=None)` 读取宿主上的 `/etc/os-release` 和 `/etc/debian_version`;给了 `container` 时读该容器里的。宿主结果按 `SonicHost` 对象缓存,容器结果不缓存。

| 调用点 | 改动 | 怎么验证 |
|---|---|---|
| `tests/memory_checker/test_memory_checker.py` 的 `get_restart_expected_logre` | 用 `debian_base_at_least("bookworm")` 选择带单元名的 systemd 日志格式 | vs testbed |
| `tests/copp/copp_utils.py` 的 `_install_nano`(syncd 容器) | 用 `debian_base_at_least("bookworm")` 选择现行的安装方式 | vs testbed |
| `tests/test_pretest.py` 的 saithrift URL | 只在 syncd 容器是 Debian 时改写 URL | vs 走不到;只有单元测试 |
| `tests/dualtor/test_mux_port_iptables_entries.py` | `debian_base_at_least("trixie")` | 没有 Dual-ToR testbed;只有单元测试 |

`dut_utils.enable_nat_for_dpus` 和 `dpu_utils` 里的 sysctl 判断在 Ubuntu 上本来就走对的分支,不改。

## 6. 验证

### 6.1 单元测试

新文件放在 `tests/common/unit_tests/helpers/`,用 `python3 -m pytest --noconftest --confcutdir=tests/common/unit_tests tests/common/unit_tests/helpers/` 运行,先于被测代码编写。输入:

- 从两种 VM 上抓取的探针输出,存放在 `tests/common/unit_tests/helpers/data/`;
- 两边根文件系统里的 `/etc/os-release` 和 `/etc/debian_version`;
- 构造的情形:pid 解析不出、缺少组定义、容器没在运行、后端未知、JSON 格式错误。

### 6.2 A/B 实测

在构建机上用 cEOS 4.32.5M 做邻居搭 vms-kvm-t0,两个镜像各一次。测试:每个模块前后自动运行的 sanity 检查,以及 `test_pretest.py`、`autorestart`、`platform_tests/daemon`、`memory_checker`、`copp`、`process_monitoring`。

### 6.3 验收标准

1. 单元测试通过。
2. 在 Dockerfile 版镜像上,所选测试用新分支跑的结果与用未修改的上游 `202605` 跑的结果逐项相同。重构不能改变 supervisord 路径。
3. 在 rock 版镜像上,交换机健康时 sanity 的进程检查通过;每个运行中容器的 `critical_processes` 里每一项都能解析出状态;rock 容器里每个关键进程都有 pid,或有说明原因的 `pid_note`。
4. 两个镜像之间结果不同的每一项、以及剩下的每一处失败,都归到一个原因并附证据:版本命名、SNMP `sysDescr`、`bgpd.log`、coreutils、docker 29、Python 3.14、日志噪声、sshd、真实的 rock 差异,或 testbed 本身。`process_monitoring` 在 rock 版上预期失败:rock 的监听器在 `auto_restart` 不是 `enabled` 时不发周期告警。

归类结果写成本仓库里的一份文档,作为下一轮的输入。

## 7. 分支与提交

`canonical/sonic-mgmt` 上的 `202605_resolute`,从 `sonic-net/sonic-mgmt` `202605` 的 `36c29fc` 开出。GPG 签名提交,顺序如下:

1. OS 画像模块及其单元测试
2. 4 处 OS 调用点
3. 容器进程模块及其单元测试
4. `SonicHost` 接口
5. `sonic.py` 与 `dut_utils.py` 里的公共辅助函数
6. `autorestart` 与 `process_monitoring` 里的测试内辅助函数

推送分支需要另行确认。

## 8. 风险

| 风险 | 应对 |
|---|---|
| 包装脚本或 `exec` 改变 pebble 服务的 argv | §4.3 的三条 pid 规则;解析不出的如实报告,不猜 |
| 以后的 pebble 改动 JSON 字段 | 缺字段时设置 `error` 并写明字段名,不抛异常 |
| 重构改变 supervisord 路径 | 验收标准 2 |
| 每次查询每个容器一次探针 | `docker exec` 次数不超过现在(现在每个容器两次) |
