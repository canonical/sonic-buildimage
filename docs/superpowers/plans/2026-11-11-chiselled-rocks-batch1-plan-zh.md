# 第一批 fully chiselled rocks 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 database、radv、eventd、mgmt-framework 四个 rock 改成 `base: bare`，Ubuntu archive 依赖全部以 slice 消费，依赖清单经实测核实。

**Architecture:** 先在 dut2（broadcom）和 sonic-vs 虚拟机上采集四个容器的真实依赖（静态 ELF/脚本分析 + bpftrace 动态追踪），产出带证据的最小清单；缺的 slice 在 chisel-releases 补齐，并汇总进 fork 上的集成分支 `sonic-26.04`；各 rock 用一个 `slices-interim` part 从该分支按 commit `chisel cut`，自建 deb 继续 `dpkg -x`；逐个 rock 在两套环境上验证。

**Tech Stack:** rockcraft 1.21.2（自带 chisel v1.5.1）、chisel-releases `ubuntu-26.04`（v3 格式）、bpftrace、Python 3（分析脚本 + pytest）、bash、qemu/KVM、SONiC `make`。

**Spec:** `docs/superpowers/specs/2026-11-11-chiselled-rocks-batch1-design-zh.md`（以下称“设计”，节号指设计的节号）

**双仓库约定：**
- 本计划和设计在文档仓库 `~/repos/sonic-buildimage-doc`（`202605_resolute_doc` 分支）。
- 代码改动在 `~/repos/sonic-buildimage`（`202605_resolute` 分支）。下文“仓库”指它，路径都相对它的根目录。
- slice 改动在 `~/repos/chisel-releases`。remote `origin` = `canonical/chisel-releases`，`fork` = `jy5275/chisel-releases`。

## Global Constraints

- 所有改动**只留在工作区，不提交**（sonic-buildimage 与文档仓库）。唯一例外：chisel-releases 集成分支 `sonic-26.04` 的 merge 提交及推送到 `fork`（已获批准）。新 SDF 的提交、推送、开 PR，**先问用户**。
- 保留 `dockers/docker-database/rockcraft.yaml` 现有的未提交改动（用户 WIP），在其基础上修改；不碰 `justfile`、`dockers/docker-database/justfile`、`PR-9-review.md`。
- 口径（设计第 3 节）：补丁未全部进入 resolute archive 的包保留自建；socat、libyang3、python3-libyang 保留自建 `dpkg -x`；PyPI wheel 不处理。
- VS 上的真实依赖必须保留；VS 独有、上游无 slice 的 archive 包放进单独整包 part，注释 `VS-only, intentionally not chiselled`。
- 过渡写法见设计 6.4：part 名 `slices-interim`，`source: https://github.com/jy5275/chisel-releases.git`，`source-type: git`，`source-commit: <sonic-26.04 的 sha>`，`chisel cut --release ./ --root ${CRAFT_PART_INSTALL} ...`；注释掉的 `ubuntu-slices` part 列表必须与 cut 列表一致；注释写明对应 PR 号、合并后的三步操作。yaml 注释用英文。
- Task 8–11 期间 `run-user` 一律不设（root）；四个 rock 全部切成 slice 并验证后，在 Task 11a 统一改用 `_daemon_`，database 的 redis 也以 `_daemon_` 运行（设计 6.5，2026-11-11 修订）。
- 每个删除的包、自建 deb 都必须在 `docs/superpowers/data/2026-11-11-batch1-deps/REMOVALS-zh.md` 有一行：动态证据、静态证据、判断错时的症状、恢复方式；rockcraft.yaml 里用一行注释指向该文件。
- 参考环境只有 dut2 和本机 sonic-vs 虚拟机；**不得登录或修改 et3-dh3-f-sw1**。
- sonic-vs 镜像：`~/Downloads/sonic-vs-img.zip`（内含 `sonic-vs.img.gz`，对应 `7a081af43`，zip sha256 `355eb1bf3879dc1ff5ed33a3ede32f148dfd8f42b667813b5b09bda95c66b2c6`）。不在本地构建 VS 镜像。
- 只做 amd64；不改 CI；不改 `slave.mk`。
- 体积基线（dut2）：database 202 MB、eventd 236 MB、mgmt-framework 312 MB、radv 245 MB。

## Review Focus

1. **低频路径被追踪漏掉**：容器能起，但特定配置下执行的脚本（database 的 `update_chassisdb_config`、multi-DB 配置；radv 无 VLAN 时的 `wait_for_link`）缺命令或库。期望：功能不回退。→ Task 4 的静态脚本命令清单逐条复核，Task 8–11 的冒烟里显式调用这些脚本。
2. **host 侧 `docker exec <容器> <命令>` 调用**：show 命令、monit、`sonic-db-cli`、`docker_image_ctl.j2` 在容器里执行的命令不在容器自身启动路径上。期望：全部照常。→ Task 1 产出 host 侧调用清单，Task 8–11 逐条在新 rock 上执行。
3. **bare 下没有 shell**：pebble `command:` 里的 `bash -c`、host 侧 `docker exec <ctr> bash/sh -c`。期望：需要 shell 的地方有 `bash_bins`/`dash_bins`。→ 同上清单里 grep `sh -c|bash -c`，Task 8–11 冒烟覆盖。
4. **用户与属主**：redis 以 `redis` 用户运行、warm reboot 的 `dump.rdb` 由 init 脚本 chown；syslog 用户；运行期创建的目录。期望：redis 能写 dump、warm reboot 恢复数据。→ Task 8 冒烟：`docker exec database pebble services` 中 redis active，且 `redis-cli -n 0 SAVE` 成功、`/var/lib/redis/dump.rdb` 属主为 redis。
5. **VS 与 broadcom 的差异**：只在 VS 上用到的文件（例如 libdashapi 相关）。期望：VS CI 不回退。→ Task 3 单独采集，Task 8–11 都在 VS 上重跑验证。

---

## 文件结构

| 路径 | 职责 |
|---|---|
| `scripts/rock-deps/trace.bt` | bpftrace 脚本：按 cgroup id 过滤，输出 `EXEC <path>` / `OPEN <path>` |
| `scripts/rock-deps/collect.sh` | 在指定交换机上对指定容器：导出 rootfs、pebble plan，运行追踪并拉回结果 |
| `scripts/rock-deps/host-callers.sh` | 静态扫描仓库里 host 侧 `docker exec <容器>` 调用，输出清单 |
| `scripts/rock-deps/analyze.py` | 合并静态/动态证据，path→包 映射，包→slice 匹配，输出 Markdown 清单 |
| `scripts/rock-deps/test_analyze.py` | analyze.py 的 pytest |
| `scripts/rock-deps/vs-vm.sh` | 启动/停止本机 sonic-vs 虚拟机（无 sudo，KVM） |
| `build_rocks.sh` | 增加可选参数：只构建指定的 rock |
| `dockers/docker-{database,router-advertiser,eventd,sonic-mgmt-framework}/rockcraft.yaml` | 按设计 6.4 重写 |
| 文档仓库 `docs/superpowers/data/2026-11-11-batch1-deps/` | 采集原始数据与每容器最小清单（证据） |

---

### Task 0: 执行环境就绪

**背景**：本 opencode 会话 `NoNewPrivs=1`，sudo 和所有 snap（rockcraft、lxc）都无法运行。docker、qemu+KVM、`~/go/bin/chisel`、ssh dut2（dut2 上 sudo 可用）可用。

- [ ] **Step 1: 确认 rockcraft 可运行**

Run: `rockcraft --version && lxc list >/dev/null && sudo -n true && echo OK`
Expected: 输出 `rockcraft 1.21.2` 和 `OK`。若仍报 `snap-confine ... cap_dac_override` 或 `no new privileges`，**停下来请用户**：在非受限终端重启会话，或由用户代为执行 rockcraft 相关步骤（Task 7–11 的 pack/skopeo 步骤）。Task 1–6 不依赖它，可先行。

- [ ] **Step 2: 确认其余资源**

Run: `nproc; free -g | awk '/Mem/{print $7}'; df -h --output=avail ~ | tail -1; ssh dut2 'sudo -n true && echo dut2-ok'`
Expected: 可用内存 ≥ 10 GB（VS 虚拟机 8 GB），磁盘 ≥ 100 GB，`dut2-ok`。

---

### Task 1: 依赖采集工具

**Files:**
- Create: `scripts/rock-deps/trace.bt`、`collect.sh`、`host-callers.sh`、`analyze.py`、`test_analyze.py`

**Interfaces:**
- Produces:
  - `collect.sh <ssh-host> <container> <outdir> <seconds> [trigger-cmd]`：在 `<outdir>/<host>/<container>/` 下生成 `rootfs.tar`、`plan.yaml`（`pebble plan`）、`trace.txt`（追踪期间执行 `trigger-cmd`，例如 `sudo config reload -y`）。参数也可经环境变量 `ROCKDEPS_*` 传入。
  - `trace.txt` 每行 `EXEC <abs path>` 或 `OPEN <abs path>`，路径相对容器 rootfs。
  - `host-callers.sh > host-callers.txt`：每行 `<file>:<line>: <container> <command...>`。
  - `analyze.py --rootfs rootfs.tar --trace t1.txt [t2.txt...] --contents <Contents-amd64 文件...> --chisel-release ~/repos/chisel-releases --out deps.md`：输出表格 `package | source(archive/self/wheel/unknown) | evidence | platforms | covering slices`。
  - `analyze.py` 内部函数：`elf_needed_closure(rootfs: Path, roots: set[str]) -> set[str]`、`map_paths(paths: set[str], contents: dict[str, str]) -> dict[str, str]`、`covering_slices(path: str, sdfs: dict) -> list[str]`。

- [ ] **Step 1: 写失败的测试 `test_analyze.py`**

用小型夹具（在 tmp_path 里造假 Contents 文件、假 SDF、假 trace）：
```python
def test_map_paths_uses_contents_and_marks_unknown():
    contents = {"usr/bin/redis-server": "database/redis-server"}
    assert map_paths({"/usr/bin/redis-server", "/usr/bin/sonic-db-cli"}, contents) == {
        "/usr/bin/redis-server": "redis-server", "/usr/bin/sonic-db-cli": None}

def test_covering_slices_matches_globs():
    sdfs = {"libzmq5": {"slices": {"libs": {"contents": {"/usr/lib/*-linux-*/libzmq.so.5*": {}}}}}}
    assert covering_slices("/usr/lib/x86_64-linux-gnu/libzmq.so.5.2.5", sdfs) == ["libzmq5_libs"]

def test_trace_lines_relative_to_rootfs_and_ignore_proc_sys_dev():
    assert parse_trace(["OPEN /proc/1/stat", "EXEC /usr/bin/ip", "OPEN /dev/null"]) == {"/usr/bin/ip"}
```
chisel glob 语义：`*`、`?` 不跨 `/`，`**` 跨 `/`。

- [ ] **Step 2: 运行测试确认失败**

Run: `python3 -m pytest scripts/rock-deps/test_analyze.py -q`
Expected: FAIL（`ModuleNotFoundError: analyze` 或函数未定义）

- [ ] **Step 3: 实现 `analyze.py`**

ELF 解析用 `pyelftools`（在 `docker run --rm -v ... python:3` 或 venv 中安装；不装到系统）或调用 `readelf -d`；`elf_needed_closure` 按 `/usr/lib/x86_64-linux-gnu`、`/lib/x86_64-linux-gnu`、`/usr/lib`、`/lib` 解析 `DT_NEEDED`，同时纳入 `DT_RUNPATH/RPATH`。roots = trace 里的 EXEC ∪ OPEN 到的 ELF ∪ 自建 deb 文件（`unknown` 来源里的 ELF）。Contents 格式为 Ubuntu 的 `Contents-amd64`（路径无前导 `/`，值为 `section/pkg[,section/pkg]`）。python wheel 文件以 `*.dist-info/RECORD` 识别为 `wheel`。

- [ ] **Step 4: 运行测试确认通过**

Run: `python3 -m pytest scripts/rock-deps/test_analyze.py -q`
Expected: PASS

- [ ] **Step 5: 实现 `trace.bt`、`collect.sh`、`host-callers.sh`**

- `trace.bt`：`tracepoint:syscalls:sys_enter_execve` 与 `sys_enter_openat`，`/cgroup == $1/` 过滤；cgroup id 由 `collect.sh` 用 `docker inspect -f '{{.Id}}'` 定位 `/sys/fs/cgroup/system.slice/docker-<id>.scope` 后取 inode 号（`stat -c %i`）传入。需要追踪容器**启动**时，`collect.sh` 先 `docker stop`，按 cgroup 父目录（`system.slice`）的 docker scope 创建事件追踪，或改为追踪 `comm` 属于该容器的进程——实现者择一，但必须覆盖冷启动。
- `collect.sh`：dut2 上先 `sudo apt-get update && sudo apt-get install -y bpftrace`（幂等：已装则跳过）；rootfs 用 `docker export`（bare 容器无 shell 也可用）；`pebble plan` 用 `docker exec <c> pebble plan`。脚本头三行注释写清用途、用法、依赖。
- `host-callers.sh`：在仓库 `files/`、`src/sonic-utilities/`、`src/sonic-host-services/`、`dockers/*/base_image_files/`、`files/build_templates/` 下 grep `docker exec`，抽出目标容器为 database/radv/eventd/mgmt-framework 的行。

- [ ] **Step 6: 冒烟**

Run: `scripts/rock-deps/host-callers.sh | wc -l` 和 `scripts/rock-deps/collect.sh dut2 radv /tmp/rockdeps 30`
Expected: host 调用清单非空；`/tmp/rockdeps/dut2/radv/` 下三个文件非空，`trace.txt` 含 `EXEC /usr/sbin/radvd` 或 radvd 打开的文件。

- [ ] **Step 7: 留在工作区，不提交**

---

### Task 2: dut2 基线与采集

**Interfaces:**
- Consumes: Task 1 的 `collect.sh`
- Produces: 文档仓库 `docs/superpowers/data/2026-11-11-batch1-deps/dut2/<container>/{rootfs.tar 不入库, plan.yaml, trace-<path>.txt}` 与 `baseline.md`

- [ ] **Step 1: 基线检查**

在 dut2 上依次执行四条路径，每条之后检查四个容器 `docker exec <c> pebble services` 全部预期服务 active、`show feature status` 正常：
1. 冷启动：`sudo systemctl restart database`（会连带重启依赖容器）
2. `sudo config reload -y`
3. warm reboot：`sudo warm-reboot -v`（先 `show warm_restart config`；不支持则记录并跳过）
4. 单容器重启：`sudo systemctl restart radv eventd mgmt-framework`
Expected: 结果写入 `baseline.md`，每条 PASS/FAIL/SKIP 及原因。FAIL/SKIP 的路径从后续采集与验收中剔除（设计 6.2“基线先行”）。

- [ ] **Step 2: 采集**

对四个容器 × 基线 PASS 的路径各跑一次 `collect.sh`（触发命令即上面的命令），另外执行 Task 1 `host-callers.txt` 中涉及这四个容器的命令各一次（追踪中）。
Expected: 每个 `trace-*.txt` 非空。

- [ ] **Step 3: 留在工作区，不提交**

---

### Task 3: sonic-vs 基线与采集

**Files:**
- Create: `scripts/rock-deps/vs-vm.sh`

**Interfaces:**
- Produces: `vs-vm.sh start|stop|ssh <cmd>`；镜像解压到 `${ROCKDEPS_WORK:-/tmp/opencode/vs}/sonic-vs.img`；SSH `admin@127.0.0.1:2200`，密码 `YourPaSsWoRd`（VS 默认密码，非机密）。数据输出到 `.../data/2026-11-11-batch1-deps/vs/`。

- [ ] **Step 1: 实现 `vs-vm.sh`**

参数同 CI `test-vs` job：`qemu-system-x86_64 -enable-kvm -cpu host -m 8192 -smp 4 ... -netdev user,id=net0,hostfwd=tcp:127.0.0.1:2200-:22`，**不用 sudo**（本机 `/dev/kvm` 已有用户 ACL）；`-daemonize -pidfile`。`start` 幂等：已在运行则直接返回；镜像已解压则不重复解压（先 `unzip -p ~/Downloads/sonic-vs-img.zip sonic-vs.img.gz | gunzip`）。

- [ ] **Step 2: 启动并确认**

Run: `scripts/rock-deps/vs-vm.sh start && scripts/rock-deps/vs-vm.sh ssh 'show version | head -3; docker ps --format {{.Names}}'`
Expected: 20 分钟内可 SSH，`docker ps` 含 database、radv、eventd、mgmt-framework。

- [ ] **Step 3: 基线检查与采集**

同 Task 2 Step 1–2，`collect.sh` 的 ssh 目标改为 `vs-vm.sh` 提供的 ssh 配置（`collect.sh` 接受 `ROCKDEPS_SSH` 覆盖 ssh 命令）。VS 上 bpftrace 安装方法同 dut2。warm reboot 在 VS 上不支持时记 SKIP。
Expected: `vs/baseline.md` 与各 `trace-*.txt`。

- [ ] **Step 4: 留在工作区，不提交；`vs-vm.sh stop`**

---

### Task 4: 生成最小依赖清单（用户审阅点）

**Interfaces:**
- Consumes: Task 2、3 的数据；`analyze.py`
- Produces: `.../2026-11-11-batch1-deps/<container>.md`：最小清单、与现有配方的 diff、slice 缺口、`run-user` 评估初步结论

- [ ] **Step 1: 准备 Contents 索引**

下载 `resolute`、`resolute-updates`、`resolute-security` 的 `main`/`universe` `Contents-amd64.gz` 到 `/tmp/opencode/contents/`，在清单里记录下载日期与 sha256。

- [ ] **Step 2: 运行分析**

对每个容器：`analyze.py --rootfs dut2/<c>/rootfs.tar --trace dut2/<c>/trace-*.txt vs/<c>/trace-*.txt ...`。`platforms` 列由 trace 来源目录得出。
Expected: 每个容器一份表格；每个 archive 包至少一条证据。

- [ ] **Step 3: 人工复核**

逐条复核 Task 1 `host-callers.txt` 与静态脚本命令（`start.sh`、`docker-database-init.sh`、`flush_unused_database`、`update_chassisdb_config`、`wait_for_link.sh.j2`、`radvd.conf.j2`、`rest-server.sh`、`eventdb_wrapper.sh`、pebble layer `command:`），把动态没覆盖到但静态确有调用的命令补进清单，标 `static-only`。
同时给出：socat、python3-libyang 是否为真依赖（决定 python3-cffi-backend 是否需要 slice）；自建 deb 中无消费者、拟删除的项及证据；VS-only 的项。

- [ ] **Step 4: 停下来，请用户审阅四份清单**

Expected: 用户确认删除项与 slice 缺口列表后再进入 Task 5。

---

### Task 5: 补齐缺失的 slice（chisel-releases）

**Interfaces:**
- Consumes: Task 4 的 slice 缺口列表（已知：#1104 rsyslog/rsyslog-relp/libestr0/libfastjson4/librelp0、#1169 radvd 已有 PR；python3-cffi-backend 视 Task 4 结论）
- Produces: 每个新包一个本地分支 `feat-26.04-<pkg>`（以及 `feat-26.10-<pkg>`），含 SDF + spread 测试

- [ ] **Step 1: 每个新包用 chisel-slicer skill 编写**（chisel-releases 的 `AGENTS.md` 要求），基于最新 `origin/ubuntu-26.04` 开分支。
- [ ] **Step 2: 本地验证**

Run: `~/go/bin/chisel cut --release ./ --root /tmp/opencode/cut-<pkg> <pkg>_<slice>`，再按 skill 跑 spread（需要 lxd 时受 Task 0 限制，改用 docker backend）。
Expected: cut 成功，spread 通过。
- [ ] **Step 3: 停下来问用户**是否提交、推送到 `fork` 并开 PR（26.04 与 26.10 各一个）。

---

### Task 6: 集成分支 `sonic-26.04`

**Interfaces:**
- Consumes: PR 分支 `fork/feat-26.04-rsyslog`（#1104）、`fork/feat-26.04-radvd`（#1169）、Task 5 的新分支
- Produces: `fork/sonic-26.04` 及其 sha（下称 `SONIC_SLICES_SHA`）；文档仓库清单里记录“sha → 包含的 PR”

- [ ] **Step 1: 构建分支**

```bash
cd ~/repos/chisel-releases && git fetch origin fork
git checkout -B sonic-26.04 origin/ubuntu-26.04
git merge --no-ff fork/feat-26.04-rsyslog fork/feat-26.04-radvd   # 加上 Task 5 的分支
```
有冲突则停下报告，不擅自解决 SDF 语义冲突。

- [ ] **Step 2: 验证四个 rock 的 slice 列表都能一次 cut 出来**

Run: 对 Task 4 每个容器的 slice 列表执行 `~/go/bin/chisel cut --release ./ --root /tmp/opencode/cut-<container> <slices...>`
Expected: 全部成功；`/tmp/opencode/cut-<container>/var/lib/chisel/manifest.wall` 存在。

- [ ] **Step 3: 推送**

Run: 首次推送 `git push fork sonic-26.04`，记录 `git rev-parse sonic-26.04`。以后按设计 6.1 重建时需要强推（`--force-with-lease`），**每次强推前先问用户**。

---

### Task 7: 构建前置与单 rock 构建入口

**Files:**
- Modify: `build_rocks.sh:6-35`（rocklist 之后）

**Interfaces:**
- Produces: `./build_rocks.sh [<rock 目录名>...]`：带参数时只构建 rocklist 中名字匹配的项；不带参数行为不变；`--list` 不变。

- [ ] **Step 1: 实现参数过滤并验证**

Run: `./build_rocks.sh --list | wc -l`（应仍为 17）；`bash -n build_rocks.sh`
Expected: 不变；语法通过。

- [ ] **Step 2: 构建四个容器所需的 target 产物**

`target/` 目前缺 sonic-eventd、sonic-supervisord-utilities-rs、libdashapi、socat、sonic-mgmt-common、sonic-mgmt-framework 等 deb，以及部分 wheel；`build_rocks.sh` 还要求 `target/<rock>.gz` 存在以读取标签。
Run: `make configure PLATFORM=vs`（若尚未配置）后 `make target/docker-database.gz target/docker-router-advertiser.gz target/docker-eventd.gz target/docker-sonic-mgmt-framework.gz`
Expected: 四个 `.gz` 生成，`target/debs/resolute/` 中出现上述 deb。若 Makefile.work 的 sudo 步骤因 Task 0 限制失败，停下请用户代跑此命令。

---

### Task 8–11: 逐个改造 rock

依次为 **Task 8 database → Task 9 radv（`docker-router-advertiser`）→ Task 10 eventd → Task 11 mgmt-framework（`docker-sonic-mgmt-framework`）**。每个 Task 结构相同，前一个通过后再开始下一个。

**Files:**
- Modify: `dockers/<dir>/rockcraft.yaml`（database 在用户 WIP 基础上改）

**Interfaces:**
- Consumes: Task 4 的 `<container>.md`、Task 6 的 `SONIC_SLICES_SHA`、Task 7 的 `build_rocks.sh <name>`

- [ ] **Step 1: 重写 `rockcraft.yaml`**（设计 6.4）
  - `base: bare`、`build-base: ubuntu@26.04`。
  - `slices-interim` part：cut 列表 = Task 4 清单中的 slice，必含 `base-files_chisel`、`base-files_base`、`base-passwd_data`；注释列出所依赖的 PR 号与合并后的三步操作；下方附注释掉的 `ubuntu-slices` part，列表逐项相同。
  - 自建 deb 的 `dpkg -x` 只保留 Task 4 确认有消费者的；处理 usrmerge。
  - 删除 `python3-venv`、`overlay-script`；用户在 `override-prime` 用 `groupadd/useradd -R ${CRAFT_PRIME}` 并显式 `-u/-g`（database 的 redis、其余容器的 syslog），`prime` 过滤 `etc/passwd-`、`etc/group-`、`etc/.pwd.lock`。
  - VS-only 且无 slice 的 archive 包放入 `vs-only-packages` 整包 part，注释 `VS-only, intentionally not chiselled`。
  - services 保持不变（除非 Task 4 证明需要调整）。

- [ ] **Step 2: 静态检查**

Run: `python3 - <<'EOF'` 解析 yaml，断言：`base == "bare"`；无任何 part 含 `overlay-script`；`stage-packages` 只出现在 `vs-only-packages`；`slices-interim` cut 列表的集合 == 注释中 `ubuntu-slices` 列表的集合（解析注释行）。
Expected: 全部断言通过。

- [ ] **Step 3: 构建**（需要 Task 0 Step 1 通过）

Run: `./build_rocks.sh <dir 名>`，然后 `scripts/rock_image_check.sh`
Expected: pack 成功；该 rock `PASS ... entrypoint '/usr/bin/pebble enter'`（其余未构建的 rock 显示 SKIP 或沿用旧产物）。

- [ ] **Step 4: 镜像自检（本机 docker）**

Run: `docker load -i target/<dir>.gz`，然后：
- `docker run --rm <img> exec <每个 service 的可执行文件> --version`（或 `--help`），无 `cannot open shared object file`；
- `docker create` + `docker export | tar -t | grep var/lib/chisel/manifest.wall`；
- `docker image inspect -f '{{.Size}}'` 记录体积。
Expected: 全部通过；体积写入 `<container>.md`。

- [ ] **Step 5: dut2 实机验证**

把镜像拷到 dut2 并替换：`docker load` 覆盖 `<dir>:latest` 后 `sudo systemctl restart <service>`。执行：
- 基线 PASS 的四条路径；
- `scripts/vs_rock_runtime_check.sh <dir>`（broadcom 上若 `ALLOWED_ERRORS`/`OPTIONAL_FEATURES` 不适用，在输出里说明，不改脚本逻辑除非用户同意）；
- 功能自检：database `redis-cli ping` 为 `PONG`、`sonic-db-cli CONFIG_DB keys '*'` 非空、redis 进程属主为 `redis`、`redis-cli SAVE` 后 `dump.rdb` 属主 redis；eventd 触发一个事件并在 DB 中查到；radv 用 `tcpdump -i <vlan> icmp6` 看到 RA（无 VLAN 配置时确认 `wait_for_link` 路径正常）；mgmt-framework `curl -k https://127.0.0.1:443/` 有响应；
- Task 1 `host-callers.txt` 中针对该容器的每条命令。
Expected: 全部 PASS；日志无 `ImportError|Traceback|cannot open shared object file|undefined symbol`。

- [ ] **Step 6: sonic-vs 验证**

用 `vs-vm.sh` 启动 VM，替换镜像后重复 Step 5（VS 不支持的路径按基线 SKIP）。

- [ ] **Step 7: 删除记录核对**

`git diff dockers/<dir>/rockcraft.yaml` 里每个被删的包、`dpkg -x` 行，都能在 `REMOVALS-zh.md` 找到对应行；配方顶部有注释 `# Removed dependencies and why: see sonic-buildimage 202605_resolute_doc docs/superpowers/data/2026-11-11-batch1-deps/REMOVALS-zh.md`。验证中若发现删错，加回并在 REMOVALS 该行标注“已恢复，原因”。

- [ ] **Step 8: 留在工作区，不提交**；在 `<container>.md` 记录 `git diff --stat` 与体积对比。

---

### Task 11a: 四个 rock 统一改用 `_daemon_`

**前置**：Task 8–11 全部通过。

**Files:**
- Modify: 四个 `rockcraft.yaml`、`dockers/docker-database/docker-database-init.sh`（pebble 分支的 `chown -R redis:redis`）

- [ ] **Step 1:** 四个配方加 `run-user: _daemon_`；database 去掉 `user: redis`/`group: redis` 与建 redis 用户的步骤，init 脚本 pebble 分支的属主改为 `_daemon_`（supervisord 分支不动，共存路径仍用 redis）。
- [ ] **Step 2:** 按设计 6.5 要点处理权限：绑定挂载目录、capability（radvd、REST 443、rsyslogd）。
- [ ] **Step 3:** 重跑 Task 8–11 的 Step 3–6（构建、镜像自检、dut2、VS），外加 `docker exec <c> id -u` 为 `584792`、`ps -o user= -C redis-server` 为 `_daemon_`。
- [ ] **Step 4:** 无法以 `_daemon_` 运行的容器：保留 root，把阻塞原因与证据写进 `SUMMARY-zh.md` 第 5 节，停下问用户。

---

### Task 12: 英文版文档

- [ ] **Step 1:** 在文档仓库生成 `specs/2026-11-11-chiselled-rocks-batch1-design-en.md` 与 `plans/2026-11-11-chiselled-rocks-batch1-plan-en.md`，内容与中文版一致。留在工作区，不提交。
