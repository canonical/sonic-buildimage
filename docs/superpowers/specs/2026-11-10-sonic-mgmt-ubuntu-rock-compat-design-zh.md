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
2. OS 画像辅助函数,以及按 Debian codename 分支的调用点(§5)。
3. 在两个镜像上做 A/B 实测,并对剩下的每一处差异归类(§6)。

**不在范围内:** 迁移各测试里直接拼写的 134 处 `docker exec <容器> supervisorctl`(之后按测试领域逐个迁移);修复产品侧问题,例如 SNMP `sysDescr` 的文字、宿主上缺失的 `/var/log/frr/bgpd.log`、镜像版本命名(先由 A/B 实测归类);PTF 主机上的 `supervisorctl`;在多 ASIC、Dual-ToR、机框 testbed 上的运行验证(没有环境);推回 sonic-net 上游。

## 2. 已定决策

| 议题 | 决定 |
|---|---|
| 兼容层放在哪 | 放在 sonic-mgmt。镜像按构建出来的原样测试 |
| 后端识别 | 按容器、在查询时、在容器内识别。不缓存 |
| 迁移范围 | 公共辅助函数和取 pid / kill 类辅助函数。直接调用的地方之后按测试领域迁移 |
| pebble 容器里的 `group:` 条目 | 读容器内 `/etc/supervisor/conf.d/*.conf` 里渲染出来的 `[group:X]` 段。渲染出的 conf 里没有该组时,组内没有成员,与 supervisord 相同;完全没有渲染出 conf 时判检查失败 |
| 状态词 | 用 supervisord 的状态名;pebble 原生状态一并保留 |
| 操作系统判断 | 按 Debian 基线代际判断,不比较 codename 字符串 |
| 其他 Ubuntu 差异(版本命名、SNMP、coreutils、docker 29、Python 3.14、日志噪声、sshd) | A/B 实测之后按结果再定 |
| 7 月的两个本地补丁(deploy-mg 重启 `ssh.service`、conftest 的 `collect_ignore_glob`) | 不带。A/B 实测表明需要时再加回 |

## 3. 已验证的事实

下列各项都在被测镜像上确认,没有推断。

| 事实 | 证据 |
|---|---|
| rock 镜像带 `/etc/supervisor/critical_processes` 和 bash,但没有 `supervisorctl` | 16 个 `rockcraft.yaml` stage 了这个文件;database、orchagent、fpm-frr 在启动脚本里渲染;database rock(`base: bare`)stage 了 bash |
| sonic-mgmt 依据 `docker exec X supervisorctl status` 判断进程健康;输出为空或无法识别时判容器不健康 | `tests/common/devices/sonic.py` 的 `SonicHost.all_critical_process_status()` 与 `parse_service_status_and_critical_process()` |
| sanity 检查与 `config reload`、重启之后的等待都用这同一个函数,所以 `--skip_sanity` 绕不过 | `sanity_check/checks.py` 的 `check_processes`;`platform/processes_utils.py` 的 `wait_critical_processes()` |
| 同一台交换机上两种后端并存:rock 版 vs 镜像上 16 个运行中的容器是 rock;syncd 和 gbsyncd,以及 deploy-mg 之后的 bmp 和 otel,是 supervisord | deploy-mg 前后对全部运行中容器的探针 |
| syncd 和 gbsyncd 里有 `pebble` 可执行文件,但没有运行 pebble 守护进程,所以靠可执行文件判断不了后端;能判断的是 `pebble services` 有没有应答 | 同一次探针 |
| `pebble services --format json` 返回 `name`、`startup`、`current`、`current-since`,没有 pid;文本输出的 `Since` 列含空格(`today at 07:40 UTC`) | docker-teamd rock,pebble 1.33 |
| 每个 pebble 服务都是 pebble 的直接子进程,并自成进程组组长 | 同一次实测:`sleep 1000` 服务 pid = pgid = 56,ppid 为 1;vs 镜像上全部 16 个 rock |
| 运行中服务的 `current-since` 就是运行它的那个进程的启动时间。用丢掉了秒以下部分的 `/proc/stat` btime 来算,两者之差在一次开机里是 1.000–1.024 秒,在另一次开机里是 0.178–0.193 秒;同一容器内的差值相差不超过 0.02 秒 | 两次抓取;在 t0 DUT 上,`$EPOCHREALTIME` 减去 `/proc/uptime` 等于 btime + 0.18 秒 |
| gnmi 与宿主共用 PID 命名空间(`--pid=host`);database rock 里 root 也读不了 `/proc/1/root` | `docker inspect`;rock 版 vs 镜像上的探针 |
| dhcp-relay rock 启动时把 `docker-dhcp-relay.supervisord.conf` 渲染到 `/etc/supervisor/conf.d/`。其中的 `[group:dhcp-relay]` 段只在有 VLAN 配了 DHCP 服务器时才生成;Dockerfile 版镜像渲染的是同一个模板 | `dockers/docker-dhcp-relay/start.sh`(pebble 分支);rock 版 vs 镜像上渲染出的 conf |
| 没有 VLAN 配置时,radv rock 不定义 `radvd` 服务 | radv 的探针 |
| Python 的 `str.splitlines()`(Ansible 生成 `stdout_lines` 用的就是它)还会在 `\x1c`、`\x1d`、`\x1e` 处切分 | Python 文档;一个失败的探针测试复现了这一点 |
| 测试从 `supervisorctl status` 一行的 `split()[1]` 取状态、`split()[3]` 取 pid;pmon 守护进程测试在 stop 之后断言 `STOPPED` | `get_pmon_daemon_status()`;`dut_utils.py` 与 `test_container_autorestart.py` 里的 `get_program_info()` / `get_group_program_info()`;`tests/platform_tests/daemon/test_*.py` |
| 缺少 `critical_processes` 文件表示没有关键进程:`get_critical_group_and_process_lists()` 返回空名单和成功 | `36c29fc` 的 `tests/common/devices/sonic.py` |
| Ubuntu:`VERSION_CODENAME=resolute`,`/etc/debian_version` 为 `forky/sid`。Debian 202605:`trixie`、`13.5` | 两边的根文件系统 |
| 两个镜像没有差异的项:sudo(C 版 sudo 1.9.x,不是 sudo-rs);bash 带 plugin 补丁和 `bash_tacplus`;sysctl 文件为 `/usr/lib/sysctl.d/90-sonic.conf`;chrony;OpenSSH 10.x;`sonic_version.yml` 里 `release: 'none'` | 两边根文件系统的包与文件对比 |

观察到的 pebble 状态:

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

新模块 `tests/common/helpers/container_processes.py`,不依赖 Ansible 也能导入(与 `ansible/module_utils/sonic_release_utils.py` 同样的要求)。它需要标准库和 PyYAML,docker-sonic-mgmt 里都有。

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

`ContainerProcesses`:`container`、`backend`(`"supervisord"`、`"pebble"` 或 `None`)、`running`、`processes`、`critical_groups`、`critical_programs`、`critical_parse_ok`(`critical_processes` 有格式错误的行时为 `False`)、`error`。`get(name, bare=True)` 接受带组名的名字;除非 `bare=False`,也接受不带组名的名字——supervisorctl 自己只认带组名的全名。

函数:`build_probe_command(container, timeout=None)`、`parse_probe_output(container, rc, stdout, allow_bare_critical=False)`、`build_control_command(container, action, names)`、`critical_process_status(result, groups=None, programs=None, strict=True)`,以及 `parse_proc_line(line)`。`timeout` 会在命令前加上 `timeout <n>`。`strict=False` 时跳过 `critical_processes` 里格式错误的行,而不是判整个容器失败,这是 `all_critical_process_status()` 原来的做法。

### 4.2 探针

每个容器一条命令:`docker exec <容器> bash -c '<脚本>'`。命令保留 `docker exec <容器>` 前缀。脚本只用 bash 内建命令,这样不依赖各个 rock 各自 stage 了哪些工具(例如 database rock 里没有 `sed`)。输出分成若干段,每段以整行恰好为 `@@<段名>@@` 的标记行开头:

| 段 | 内容 |
|---|---|
| `backend` | `pebble services` 成功时为 `pebble`;否则 `supervisorctl` 在 `PATH` 里时为 `supervisord`;否则为 `unknown` |
| `critical` | `/etc/supervisor/critical_processes` 的内容,或标记 `@@critical-missing@@` |
| `status`(supervisord) | `supervisorctl status` |
| `services`(pebble) | `pebble services --format json` |
| `plan`(pebble) | `pebble plan` |
| `btime`(pebble) | `/proc/stat` 里的开机时间 |
| `procs`(pebble) | 每个进程一行:pid、ppid、pgid、以时钟 tick 计的启动时间,再接以 `\x1f` 连接的 argv;参数里的换行写成 `\x02` |
| `groups`(pebble) | `/etc/supervisor/conf.d/*.conf` |
| `end` | 标志输出完整 |

探针不列出它自己和它派生的子 shell。PID 1 不是 pebble 时,说明容器与宿主共用 PID 命名空间,此时只保留 `/proc/<pid>/root` 是本容器根目录的进程。`docker exec` 返回非零表示容器没在运行。

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

`critical_processes` 里列出、但 pebble 没有定义的程序,报告为 `STOPPED`,`raw_state` 为 `undefined`,与 supervisord 报告"已配置但没启动的程序"一致。

组成员:`[group:G]` 段里的 `programs=` 列表把其中的名字归入组 `G`。渲染出的 conf 里没有某个组时,该组没有成员,与 supervisord 相同。`critical_processes` 列了某个组、而容器里完全没有渲染出 conf 时,设置 `error`。

运行中服务的 pid 是运行它的那个 pebble 直接子进程,也就是包装脚本 exec 之后 supervisord 报告的那个 pid。匹配前先去掉末尾的空参数(会改写自身标题的程序会留下这些空参数)。下列规则按顺序尝试;每条规则里,一个服务只有在某个子进程是它唯一的候选、且没有别的未解析服务也列出这个子进程时,才认领它:

1. argv 等于 `shlex.split(command)`。
2. argv 等于 command 前面加上一到两个解释器参数:按 shebang 运行的脚本(`python3 /usr/bin/bgpcfgd`)。
3. 进程名——argv[0] 的 basename 截到第一个 `:` 或空格——等于服务名:`orchagent.sh` exec 成 orchagent;lldpd 把标题改成 `lldpd: monitor.`。
4. 子进程的启动时间加上本容器的常规差值,与服务的 `current-since` 相差不超过 0.1 秒。这条规则覆盖 exec 成别的名字的包装脚本(`gnmi-native.sh` → `telemetry`),以及外观相同的多个实例(`redis` 与 `redis_bmp`)。

常规差值是「`current-since` 减启动时间」,取自同一容器内被规则 1 匹配上的服务。它抵消了 btime 丢掉的那部分小数秒(t0 DUT 上是 0.18 秒)。开机后的时钟跳变会让此前启动的所有服务的差值一起偏移,所以只算彼此相差不超过 0.1 秒的最大那一组差值,取其中位数作为常规差值;如果有两组一样大,就没有常规差值,不用规则 4。规则 3 的匹配在两种情况下作废:它自己的差值与常规差值不符,或者另有一个未被认领的子进程也符合它的启动时间;这时改由规则 4 决定。

都不满足时 `pid` 为 `-1`,`pid_note` 写明没有规则匹配上。在 rock 版 vs 镜像的两次抓取里,这些规则都让每个运行中的服务各自得到不同的 pid。

### 4.4 控制

`build_control_command(container, action, names)`(`action` 为 `start`、`stop` 或 `restart`)生成一条保留 `docker exec <容器>` 前缀的命令,在容器内分支:pebble 下执行 `pebble <action>`,并去掉每个名字的组前缀;supervisord 下执行 `supervisorctl <action>`,名字不变。两种后端下,成功返回 0,失败返回非零。

`build_signal_command(container, signal, names)` 以同样的方式分支到 `pebble signal` 或 `supervisorctl signal`。signal 是 `SIGHUP` 或 `HUP` 这样的名字;其他任何值在到达 shell 之前就被拒绝。容器里没有定义的程序,两种后端都返回 1。

### 4.5 SonicHost 接口与迁移的辅助函数

`SonicHost` 新增方法:

- `get_process_table(container)` 返回 `ContainerProcesses`。
- `get_process_tables(containers)` 把多个探针放进一次 `shell_cmds` 批量执行,每个探针限时 60 秒,按位置对应结果,不再从命令串里解析容器名。
- `control_container_process(container, action, names, module_ignore_errors=False)`。
- `signal_container_process(container, signal, names, module_ignore_errors=False)`。
- `os_profile(container=None)`(§5)。

这样命名是为了避开已有的、基于 `docker top` 的 `dut_utils.get_container_processes()`。

改为调用新接口的辅助函数,签名与返回值都不变:

| 文件 | 函数 |
|---|---|
| `tests/common/devices/sonic.py` | `get_critical_group_and_process_lists`、`critical_process_status`、`all_critical_process_status`、`start_pmon_daemon`、`stop_pmon_daemon_service`、`get_pmon_daemon_status`、`get_pmon_daemon_states`、`kill_bgpd`、`start_bgpd`、`is_service_running` |
| `tests/common/devices/multi_asic.py` | `modify_syslog_rate_limit`:因为 database rock 里没有 `sed`,改为从宿主经 `/proc/<pid>/root` 编辑 `rsyslog.conf`,再用控制命令重启 rsyslogd |
| `tests/common/helpers/dut_utils.py` | `get_program_info`、`get_group_program_info`、`verify_orchagent_running_or_assert` |
| `tests/common/utilities.py`、`tests/common/helpers/dut_utils.py` | `kill_process_by_pid` 拒绝非正数的 pid |
| `tests/autorestart/test_container_autorestart.py` | 它自己的 `get_program_info`、`get_group_program_info` 和 `kill_process_by_pid` 拷贝改用 `dut_utils` 里的版本;它自己的运行检查和程序启动改走进程表和控制命令 |
| `tests/process_monitoring/test_critical_process_monitoring.py` | 把已停止的关键进程重新拉起的那处 `supervisorctl start` |

从 supervisorctl 解析沿用下来的行为:pmon 的关键进程名单只保留正在运行的程序;`get_program_info()` 取名字包含给定字符串的第一个程序。对容器里不存在的守护进程,`get_pmon_daemon_status()` 返回 `(None, -1)`。`get_pmon_daemon_status()` 和 `is_service_running()` 用 `bare=False` 查找程序,因为它们原来解析的 supervisorctl 输出只用 `组名:程序名` 称呼带组的程序。`all_critical_process_status()` 用 `strict=False`。`critical_group_process()` 没有其他调用方,已删除;`parse_service_status_and_critical_process()` 保持公开且不变。

### 4.6 出错处理

| 情况 | 结果 |
|---|---|
| 容器没在运行 | `running=False`;关键进程状态为 `False`,与现在相同 |
| 后端为 `unknown` | 设置 `error`;关键进程状态为 `False` |
| 缺少 `critical_processes` | 没有关键进程,与现在相同;状态取决于其余程序能否读出 |
| `critical_processes` 有格式错误的行 | `critical_parse_ok=False`;关键进程状态为 `False`,与现在相同 |
| pebble 容器有关键组,但没有渲染出 supervisord conf | `error` 写明组名;关键进程状态为 `False` |
| 进程在运行但没解析出 pid | `pid=-1`,设置 `pid_note`;不影响关键进程状态。`kill_process_by_pid()` 拒绝非正数的 pid:gnmi 与宿主共用 PID 命名空间,在它里面执行 `kill -SIGKILL -1` 会杀掉交换机上的所有进程 |
| JSON 或 YAML 无法解析、pebble 输出的结构不符合预期,或输出没有 `end` | 设置 `error`;关键进程状态为 `False` |
| 探针卡住 | `get_process_tables()` 给每个探针加上 `timeout 60`,因为命令里含单引号时 `shell_cmds` 会丢掉它自己的超时 |

## 5. 组件 2:OS 画像

新模块 `tests/common/helpers/os_profile.py`,只用标准库。

`parse_os_profile(os_release_text, debian_version_text)` 返回 `OsProfile(id, version_id, codename, debian_base)`:

- Debian:`debian_base` 就是它的 codename。
- Ubuntu:`debian_base` 取自 `/etc/debian_version`。`forky/sid` 得到 `forky`;纯数字按大版本映射(10 `buster`、11 `bullseye`、12 `bookworm`、13 `trixie`、14 `forky`)。
- 其他取值得到 `debian_base=None`。

`debian_base_at_least(name)` 按 `buster < bullseye < bookworm < trixie < forky < duke` 的顺序比较,`debian_base` 为 `None` 时返回 `False`,名字不在这个列表里时抛 `ValueError`。`ID` 为 `debian` 时 `is_debian` 为真。

`os_profile_command(container=None)` 生成打印这两个文件的命令,`parse_os_profile_output(stdout)` 解析它的输出。读不到 `/etc/os-release` 时命令失败;`/etc/debian_version` 可以没有,因为单凭 `os-release` 就能认出 Debian。`SonicHost.os_profile(container=None)` 在宿主上运行它,给了 `container` 时在该容器里运行,失败时抛异常。宿主上成功的结果按 `SonicHost` 对象缓存,容器结果不缓存。

| 调用点 | 改动 | 怎么验证 |
|---|---|---|
| `tests/memory_checker/test_memory_checker.py` 的 `get_restart_expected_logre` | 用 `debian_base_at_least("bookworm")` 选择带单元名的 systemd 日志格式 | vs testbed |
| `tests/copp/copp_utils.py` 的 `_install_nano`(syncd 容器) | 用 `debian_base_at_least("bookworm")` 选择现行的安装方式 | vs testbed |
| `tests/dualtor/test_mux_port_iptables_entries.py` | `debian_base_at_least("trixie")` | 没有 Dual-ToR testbed;只有 `os_profile` 的单元测试 |

等待 DUT 恢复的地方都在匹配 sshd 的 banner。Ubuntu 上的 banner 是 `SSH-2.0-OpenSSH_10.2p1 Ubuntu-2ubuntu3`,`OpenSSH_[\w\.]+ Debian` 匹配不上:deploy-mg 等了 600 秒后超时,`reboot()` 也会在每个重启测试里超时。这个正则的全部 14 处拷贝——`tests/common/reboot.py`、6 个测试、deploy-mg、`reboot_sonic.yml` 以及 l2 模式、vchassis、nut 的 playbook——都改为接受 `(Debian|Ubuntu)`。

不改的地方:

- `tests/test_pretest.py` 里改写 saithrift URL 的逻辑会读 syncd 的 codename,但只对微软官方镜像的版本号生效;其他版本号(包括 `202605_resolute` 构建出来的)按私有镜像处理,URL 原样保留。
- `dut_utils.enable_nat_for_dpus` 和 `dpu_utils` 里的 sysctl 判断在 Ubuntu 上本来就走对的分支。

## 6. 验证

### 6.1 单元测试

文件放在 `tests/common/unit_tests/helpers/`,用 `python3 -m pytest --noconftest --confcutdir=tests/common/unit_tests tests/common/unit_tests/helpers/` 运行,先于被测代码编写。输入:

- rock 版 vs 镜像上每个运行中容器的探针输出,存放在 `tests/common/unit_tests/helpers/data/container_processes/`:`rock-7a081af43c/` 是无配置时的,`rock-7a081af43c-t0/` 是 deploy-mg 之后的;`dockerfile-7a081af43c-t0/` 是 Dockerfile 版 vs 镜像 deploy-mg 之后的,新解析器与旧的 supervisorctl 解析必须对它读出相同结果;
- 把 btime 平移一秒、以及在服务之间插入一次时钟跳变后的同一批探针输出;
- `36c29fc` 的 `critical_processes` 解析,与新解析器在相同输入上对照;
- 两边根文件系统里的 `/etc/os-release` 和 `/etc/debian_version`;
- 在本地用假的 `pebble` 和 `supervisorctl` 命令运行探针脚本;
- 构造的情形:pid 解析不出、缺少组定义、容器没在运行、后端未知、JSON 格式错误、输出被截断。

SonicHost 的方法和 `dut_utils` 的辅助函数用 `ast` 加载,在一个返回抓取样本的假 DUT 上运行。

### 6.2 A/B 实测

在构建机上用 cEOS 4.32.5M 做邻居搭 vms-kvm-t0,两个镜像各一次。测试:每个模块前后自动运行的 sanity 检查,以及 `test_pretest.py`、`autorestart`、`platform_tests/daemon`、`memory_checker`、`copp`、`process_monitoring`。

第二轮在两个镜像上跑上游的 t0 PR 测试清单,共 271 个文件。它在一台 Testflinger 机器上运行,分到 LXD 虚拟机里的 12 个 testbed:每个镜像 6 个分片。这一轮发现的测试代码调用点也迁移到同一套接口上,受影响的文件在两个镜像上重跑。

### 6.3 验收标准

1. 单元测试通过。
2. 在 Dockerfile 版镜像上,所选测试用新分支跑的结果与用未修改的上游 `202605` 跑的结果逐项相同。重构不能改变 supervisord 路径。
3. 在 rock 版镜像上,交换机健康时 sanity 的进程检查通过;每个运行中容器的 `critical_processes` 里每一项都能解析出状态;rock 容器里每个关键进程都有 pid,或有说明原因的 `pid_note`。
4. 两个镜像之间结果不同的每一项、以及剩下的每一处失败,都归到一个原因并附证据:版本命名、SNMP `sysDescr`、`bgpd.log`、coreutils、docker 29、Python 3.14、日志噪声、sshd、真实的 rock 差异,或 testbed 本身。`process_monitoring` 在 rock 版上预期失败:rock 的监听器在 `auto_restart` 不是 `enabled` 时不发周期告警。

归类结果写成本仓库里的一份文档,作为下一轮的输入。

## 7. 分支与提交

`canonical/sonic-mgmt` 上的 `202605_resolute` 就是上游 `sonic-net/sonic-mgmt` `202605` 的 `36c29fc`。改动在 draft PR [canonical/sonic-mgmt#2](https://github.com/canonical/sonic-mgmt/pull/2) 里,分支 `feat/resolute-ubuntu-rock-compat`:共 21 个 GPG 签名提交,顺序如下,每个提交一个主题,单独都能通过单元测试:

1. OS 画像模块、`SonicHost.os_profile()` 及其单元测试
2. OS 调用点
3. sshd banner 正则
4. monit 的 sanity 检查和 memory_checker 接受 `Waiting`
5. 容器进程模块(探针、解析、pid 规则、控制和 signal 命令)、其单元测试、抓取的探针样本,以及与被替换的 supervisorctl 解析的对照测试
6. `SonicHost` 接口,以及迁移到它上面的 `sonic.py`、`dut_utils.py` 和 `multi_asic.py` 公共辅助函数,连同单元测试
7. `autorestart` 与 `process_monitoring` 里的测试内辅助函数
8. `kill_process_by_pid()` 拒绝非正数的 pid
9. SNMP 子代理检查
10. dhcp_relay 的程序状态与 pid
11. gnmi helper
12. arp、crm、dualtor、vlan、pc、syslog 里对 arp_update 和 rsyslogd 的控制
13. like-bgp 容器的入口,以及 fpmsyncd 重启
14. bmp 的程序状态
15. radvd 的 SIGHUP
16. thermalctld、lm-sensors 和 lldpmgrd
17. telemetry 事件 helper
18. dualtor 测试里的 arp_update 与 ycabled
19. qos_sai 的服务控制
20. dhcp_server fixture
21. 两处改为记录进程表的诊断输出

A/B 实测结果见 [../2026-11-10-sonic-mgmt-resolute-ab-report-zh.md](../2026-11-10-sonic-mgmt-resolute-ab-report-zh.md),t0 运行结果见 [../2026-11-11-sonic-mgmt-t0-run-report-zh.md](../2026-11-11-sonic-mgmt-t0-run-report-zh.md)。

## 8. 风险

| 风险 | 应对 |
|---|---|
| `current-since` 不再是进程启动时间,或两个需要规则 4 的服务在 0.1 秒内先后启动 | 只有规则 4 依赖它。在 rock 版 vs 镜像上,规则 1–3 在 deploy-mg 之前能解析 75 个运行中服务里的 70 个,之后能解析 70 个里的 65 个;两次剩下的 5 个都是 redis、redis_bmp、gnmi-native、dialout 和 rest-server。一个子进程同时是多个服务的候选时不匹配,所以解析不出时 `pid=-1` 并附说明,不猜 |
| 以后的 pebble 改动 JSON 输出 | 无法解析的输出或未知的状态词会设置 `error`,不抛异常 |
| 重构改变 supervisord 路径 | 验收标准 2 |
| 每次查询每个容器一次探针 | `docker exec` 次数不超过现在(现在每个容器两次) |
