# 第一批 fully chiselled rocks 设计：database / radv / eventd / mgmt-framework

**日期**：2026-11-11
**代码分支**：`canonical/sonic-buildimage` 的 `202605_resolute`（截至 `7a081af43`）
**slice 仓库**：`canonical/chisel-releases` 的 `ubuntu-26.04`（截至 `5500a56`），个人 fork `jy5275/chisel-releases`
**上游文档**：`docs/superpowers/2026-09-21-resolute-sonic-chisel-blueprint-zh.md`（以下简称“蓝图”）。蓝图负责“切 slice”这条供给线，第 8 节把“在 rock 里用 slice”留给单独成文——本文就是它针对第一批 4 个容器的那一份
**状态**：已批准（2026-11-11）

---

## 1 · 为什么做

- 上层要求 SONiC 容器“完全 chisel”。这是口头目标，本文第 3 节把它落成可检查的口径。
- 驱动力是**来源统一与安全合规**：容器内容尽量来自 Ubuntu archive，并以 slice 形式只带进运行期真正需要的文件，便于 SBOM、漏洞扫描和缩小攻击面。
- 先挑 4 个容器做成 fully chiselled rock，**尽快交付一批成果**，同时把方法（依赖识别、slice 过渡接入、验证）跑通并固化，供后续 15 个 rock 复用。

## 2 · 目标、非目标、反目标

**目标**

1. `docker-database`、`docker-router-advertiser`（radv）、`docker-eventd`、`docker-sonic-mgmt-framework` 四个 rock 全部 `base: bare`。
2. 四个 rock 依赖的 **Ubuntu archive 包全部以 slice 形式消费**，`stage-packages` 里不再出现整包。
3. 依赖清单经过“真实依赖”核实：每个保留的包都能指出运行期消费者；迁移时多列的包删除。
4. 上游 slice PR 未合并期间，rock 照样能构建；`rockcraft.yaml` 里用注释写清合并后删什么、取消注释什么。
5. 在 broadcom 实机 dut2 上验证功能不回退。

**非目标**

- SONiC 自建 deb（含本地打补丁重编的 Ubuntu 包）不切 slice，继续 `dpkg -x`。
- PyPI wheel 不处理（python 插件照常 `pip install`）。
- vs 平台独有的包和容器、其余 15 个 rock。
- 把 rock 构建接进 `slave.mk`、抽取四个配方的公共部分、去掉 supervisord 共存分支。

**反目标**（技术上“成功”但仍算失败）

- 服务起来了但运行期缺文件（某个 `.so`、`/etc` 配置、数据文件），功能静默降级。
- 为了“换成 archive”把带 SONiC 补丁的包换成不含补丁的 archive 版。
- 为凑 slice 写出上游不会接受的投机性 slice。
- 动生产机器（`et3-dh3-f-sw1` 不作为参考，不登录、不修改）。

## 3 · “完全 chisel”的口径

按顺序适用于每个运行期依赖：

| # | 情形 | 处理 |
|---|---|---|
| 1 | 本地构建流程只是从 Ubuntu archive **原样下载** `.deb` | 不再自建，改为由 rock 直接从 archive 消费（最终是 slice） |
| 2 | 本地从 Ubuntu/Debian 源码**打 SONiC 补丁**重编，且**所有补丁都已包含在 resolute archive 的版本里** | 同上 |
| 3 | 本地打补丁重编，且**有任何补丁未包含在 archive 版本里** | 保留自建，`dpkg -x`；默认补丁的功能是需要的 |
| 4 | 纯 SONiC 软件或 vendor 二进制 | 保留自建，`dpkg -x` |
| 5 | PyPI wheel | 不处理 |
| 6 | 其余 Ubuntu archive 包 | **全部走 slice** |

自建 deb 的 `Depends` 里指向 archive 的那部分（例如 libhiredis、libzmq5、libreadline）属于第 6 类，要切。

范围：只为 **broadcom 镜像**依赖的包写 slice。四个容器都在 broadcom 镜像里。

但同一份 `rockcraft.yaml` 同时用于 VS 和 broadcom 构建（`build_rocks.sh` 不区分平台），所以 **VS 上的真实依赖也要保留**，不能因为 broadcom 用不到就删。VS 独有的 archive 依赖：上游已有 slice 的照常用 slice；没有的不为它新写 slice，而是放进单独的、注释标明“VS-only, intentionally not chiselled”的整包 part。

## 4 · 现状与约束

### 4.1 四个 rock 现状

| rock | base | 现有 dut2 镜像体积 | 整包 stage | `dpkg -x` 的自建 deb |
|---|---|--:|---|---|
| database | bare（已部分切） | 202 MB | rsyslog、rsyslog-relp、python3-cffi-backend、python3-venv | socat、libswsscommon、sonic-supervisord-utilities-rs、libyang3、python3-libyang、python3-swsscommon、sonic-db-cli、sonic-eventd、libdashapi |
| radv | ubuntu@26.04 | 245 MB | 21 个（config-engine 清单 + radvd）+ python3-venv | 同上去掉 libdashapi |
| eventd | ubuntu@26.04 | 236 MB | 18 个 + python3-venv | 同 radv |
| mgmt-framework | ubuntu@26.04 | 312 MB | 24 个 + python3-venv | 同 radv，去掉 supervisord-utilities-rs，加 sonic-mgmt-common、sonic-mgmt-framework |

后三个的清单是从 config-engine 层整体抄来的，已知含多余项，例如：

- `libnl-cli-3-200`：自建 deb 的 ELF `NEEDED` 只有 `libnl-3`、`libnl-nf-3`、`libnl-route-3`，没有 `libnl-cli-3`。
- `python3-venv`：26.04 上 `plugin: python` 是 v2，用 `PIP_USER` 安装，不建 venv。

### 4.2 第 3 节口径对四个容器的结论

| 自建包 | 类别 | 依据 | 结论 |
|---|---|---|---|
| socat | 3 | `src/socat/patch/enable_readline.patch` 打开 readline，archive 版没有 | 若是真依赖则保留自建 |
| libyang3 | 3 | `0001-pr2362-lyd_validate_noextdeps.patch`；上游 libyang#2362 已关闭未合并 | 保留自建 |
| python3-libyang | 3 | resolute archive 无此包（`libyang-python` 只在 26.10 之后） | 保留自建 |
| 其余（swss-common 系、sonic-eventd、sonic-db-cli、supervisord-utilities-rs、dashapi、mgmt-common、mgmt-framework） | 4 | 纯 SONiC | 保留自建 |
| libnl3 | 1 | `rules/libnl3.mk` 已是 `SONIC_ONLINE_DEBS` 原样下载；rock 本就用 archive slice | 已符合 |

所以第一批**没有**需要从自建改为 archive 的包；第 1、2 类规则在后续批次逐包复核。

### 4.3 硬约束

- **chisel 只能从 Ubuntu 官方 archive（含 ESM）取包**，URL 写死在源码里，不支持 PPA 和本地 deb。这是第 3 节第 3、4 类只能 `dpkg -x` 的原因。
- **`base: bare` 不能用 overlay**（`overlay-script` 等），rockcraft 校验时直接报错。radv、eventd、mgmt-framework 现在用 `overlay-script` 建 syslog 用户，必须改。
- **同一个 part 里不能混用整包和 slice**；rockcraft 1.21 起推荐 `stage-slices`，与 `stage-packages` 在同一 part 互斥。
- **rockcraft 版本**：CI 的 `canonical/craft-actions/rockcraft/setup` 未指定 channel，装的是 `latest/stable`，当前 1.21.2，支持 `stage-slices`。channel 不锁，rockcraft 升级会直接进入 CI。
- `stage-slices` 拉的是上游 `ubuntu-26.04` 分支的**当前头**，不能锁 commit。
- rock 构建在 host 上由 `build_rocks.sh` 驱动（LXD provider），不在 sonic-slave 里；构建需要网络。
- 只做 amd64。
- 参考环境只有两个：
  - **dut2**：Dell S5232F，broadcom，已跑 rock 镜像；内核 `7.0.0-1002-sonic` 带 BTF；容器均非 privileged、`network=host`、无额外 cap。可修改。
  - **sonic-vs 虚拟机**：使用 CI 已构建好的镜像，不在本地构建（太耗时）。镜像已下载到本机 `~/Downloads/sonic-vs-img.zip`（内含 `sonic-vs.img.gz`；zip 的 sha256 为 `355eb1bf3879dc1ff5ed33a3ede32f148dfd8f42b667813b5b09bda95c66b2c6`），来源是 [run 42562456825 的 artifact `sonic-vs-img`](https://github.com/canonical/sonic-buildimage/actions/runs/42562456825/artifacts/13654753860)，对应 `202605_resolute` 的 `7a081af43`。启动方式与 CI `test-vs` job 相同（`qemu-system-x86_64 -enable-kvm`，8 GB 内存、4 vCPU，SSH 转发到 2200 端口）。

## 5 · 方案：PR 未合并期间 slice 怎么接进 rock

考虑过三种：

| | 做法 | 优点 | 代价 |
|---|---|---|---|
| **A（选定）** | fork 上建集成分支 = 上游 `ubuntu-26.04` + 所有待合并 PR；每个 rock 用**一个** part 从它按 commit `chisel cut` 出全部 slice | 只有一个 slice 来源，不会出现两个 part 切出同一路径而内容不一致；commit 锁定，可复现；合并后一次性切回 | 要维护集成分支，PR 有更新就同步 |
| B | 已合并的走 `stage-slices`，未合并的另一个 part 从 fork 分支切 | 不用维护集成分支；渐进切换 | 共同依赖（libc6、base-files 等）两边各切一份，fork 落后时可能冲突导致构建失败 |
| C | 把 chisel-releases 子集 vendor 进本仓库 | 构建不依赖网络 | 仓库里多一份外部源码副本，违背“不直接改外部源码”的规范，合并后清理麻烦 |

**选 A 的理由**：B 的冲突风险正是蓝图 5.6 指出“没有答案”的那个问题，A 从结构上消除了它；C 违背仓库规范。

## 6 · 设计

### 6.1 集成分支

- 位置：`jy5275/chisel-releases`，分支名 `sonic-26.04`。
- fork 的 `ubuntu-26.04` 已于 2026-11-11 fast-forward 到上游 `5500a56`（fork 无独有提交）。
- 内容：fork `ubuntu-26.04` 之上，**逐个 merge** 第一批涉及的待合并 PR 分支（用 merge 而非 cherry-pick，保留与 PR 的对应关系）。
- 更新规则：上游前进或 PR 有新提交时，从最新 `ubuntu-26.04` **重建**该分支（重新 merge 仍未合并的 PR），重建后更新各 rock 里的 `source-commit`。某个 PR 合并后，重建时就不再 merge 它。
- 已知会进入的 PR：#1104（rsyslog、rsyslog-relp，带 libestr0、libfastjson4、librelp0）、#1169（radvd）。6.3 新增的 PR 同样加入。

### 6.2 真实依赖识别

对每个容器得到一份“最小依赖清单”，每项写明消费者（哪个二进制/脚本/模块需要它）。两条腿走路，取并集：

**静态**

1. ELF：对所有自建 deb 里的 ELF、以及容器会调用的 archive 二进制，求 `DT_NEEDED` 闭包，再在 ubuntu:26.04 环境里 `dpkg -S` 反查到包。
2. 脚本：`start.sh`、`*-init.sh`、`*.j2` 渲染结果、pebble layer 里 `command:` 调用的外部命令。
3. Python：服务运行后导出解释器实际加载的模块（`sys.modules`），区分 stdlib 子集、deb 提供的模块、wheel 提供的模块。

**动态（dut2 与 sonic-vs 各跑一遍）**

4. 在 dut2 上装 bpftrace（或 bpfcc-tools），按容器 cgroup 抓 `execve` 与 `openat`，覆盖：容器冷启动、`config reload`、warm reboot、容器重启。把打开过的路径映射回包。
5. 在 sonic-vs 虚拟机（4.3 的 CI 镜像）上用同样的脚本、同样的路径再采一遍。VS 上不支持的路径（例如 warm reboot）按“基线先行”的规则剔除。

**产出**

- 每容器的最小清单 = 静态结果 ∪ dut2 动态结果 ∪ sonic-vs 动态结果。每项标注来源平台（broadcom、VS 或两者），以便 3 节的“VS 独有”判断。
- 与现有 `stage-packages` 的 diff（删除项要写理由）。
- 顺带确定 socat、python3-libyang 是否是真依赖；python3-libyang 是真依赖时，python3-cffi-backend 才需要 slice。
- 采集与反查脚本固化为可重跑的产物（脚本头部写清用途、用法、依赖；参数走环境变量），后续批次复用。

**准入标准**：清单里每个包都有至少一个运行期消费者的证据；只在 Docker 镜像里出现、无消费者的包不进清单。

**自建 deb 同样适用**（作者决定）：`dpkg -x` 的自建 deb 也要过准入标准。静态、动态两条都找不到消费者的，从配方里删除，并在 PR 描述里逐个写明证据。理由：目标 3 不区分来源；多余的自建 deb 还会连带要求切它们的 archive 依赖，增加 slice 工作量。

**基线先行**（作者决定）：采集前先在 dut2 和 sonic-vs 的现有 rock 镜像上分别确认冷启动、`config reload`、warm reboot、容器重启四条路径本身正常。某条路径在基线上就不工作的，记录下来并从本批的采集与验收里剔除，不在本设计内修复。

### 6.3 补齐 slice

- 已知缺口：rsyslog、rsyslog-relp、libestr0、libfastjson4、librelp0（#1104）；radvd（#1169）；python3-cffi-backend（条件见 6.2）；socat 及其 archive 依赖若有缺口也要补（socat 本身自建，不切）。
- 6.2 新发现的缺口，按 chisel-releases 的 `AGENTS.md` 要求用 chisel-slicer skill 编写，带 spread 测试。
- 每个包同时提 26.04 与 26.10（上游 forward-port 规则）。
- slice 粒度：只选运行期需要的 slice，例如 Python 优先 `python3.14_core` 加需要的 stdlib 功能 slice，而不是 `python3.14_standard`；以 6.2 的 Python 模块清单为准。

### 6.4 rock 配方结构

每个 rock 的 parts 收敛为以下几类（名字示意）：

| part | 作用 |
|---|---|
| `slices-interim` | 从集成分支 `chisel cut` 出**全部** Ubuntu slice，包括 `base-files_chisel`（生成 `/var/lib/chisel/manifest.wall` 供 SBOM/扫描）、`base-passwd_data`、`base-files_base` |
| `sonic-debs` | `dpkg -x` 第 3、4 类自建 deb；处理 usrmerge（`bin/`、`lib/` organize 到 `usr/` 下或 `build-attributes: [enable-usrmerge]`） |
| `setup-<name>` | 本容器的脚本、模板、配置文件，及 override-prime 里的定制（如 redis.conf 的 sed） |
| `install-python` | `plugin: python` 安装 wheel；删除 `python3-venv` |
| 建用户 | `after` slices 与 debs，在 override-build/override-prime 里 `groupadd/useradd -R`，显式 `-u/-g` 钉 uid，并用 `prime:` 过滤 `etc/passwd-`、`etc/group-`、`etc/.pwd.lock`。替代现有 `overlay-script` |

过渡期写法（注释用英文，与代码一致）：

```yaml
  # INTERIM: Ubuntu slices are cut from jy5275/chisel-releases@sonic-26.04
  # (upstream ubuntu-26.04 + pending PRs) because these slices are not upstream yet:
  #   rsyslog, rsyslog-relp, libestr0, libfastjson4, librelp0  <- canonical/chisel-releases#1104
  #   radvd                                                    <- canonical/chisel-releases#1169
  # Once ALL PRs above are merged into canonical/chisel-releases ubuntu-26.04:
  #   1. delete this `slices-interim` part
  #   2. uncomment the `ubuntu-slices` part below (same slice list)
  #   3. drop `slices-interim` from any `after:` list
  slices-interim:
    plugin: nil
    source: https://github.com/jy5275/chisel-releases.git
    source-type: git
    source-commit: <sha of sonic-26.04>
    override-build: |
      chisel cut --release ./ --root ${CRAFT_PART_INSTALL} \
        base-files_chisel base-files_base base-passwd_data bash_bins ... rsyslog_bins radvd_bins

  # ubuntu-slices:
  #   plugin: nil
  #   stage-slices:
  #     - base-files_chisel
  #     - ...
```

**这种写法 rockcraft 支持，且有先例**：

- git source：craft-parts 用正则 `(^git(\+.+:|[@:])|\.git$)` 识别 git 源，`source-type: git` 也可以显式写；`source-commit`、`source-branch`、`source-tag` 三选一（`craft_parts/sources/git_source.py`）。`override-build` 的工作目录是拉下来的源码目录，所以 `--release ./` 即指向集成分支。
- `chisel` 命令：rockcraft snap 自带 chisel（`libexec/rockcraft/chisel`，1.21.2 里是 v1.5.1，满足 26.04 v3 格式要求的 ≥1.4.0），构建环境里直接可用。
- 先例：`ad9aa27c2`（“Chisel docker-database”）的 `dockers/docker-database/rockcraft.yaml` L70-102 就是这样写的，当时用的是 `source-branch: dev/docker-database`。本设计改用 `source-commit`：分支会移动，commit 才能保证可复现。

**约定**：`slices-interim` 的 cut 列表与注释掉的 `ubuntu-slices` 列表必须一致，评审时逐项比对。某个 rock 依赖的 PR 全部合并后，该 rock 就可以单独切回，不必等其他 rock。

### 6.5 运行用户

（2026-11-11 用户决定修订）

- **时机**：四个 rock 的 Ubuntu archive 依赖全部换成 slice、并通过 6.7 验证之后，再统一改用 `run-user: _daemon_`。切 slice 阶段一律保持 root，避免两类变化叠加、出问题时无法区分原因。
- **database 的 redis 也以 `_daemon_` 运行**：去掉 service 上的 `user: redis` / `group: redis` 与配方里建 redis 用户的步骤，由 `run-user` 统一身份；`docker-database-init.sh` 里 `chown -R redis:redis` 的目标随之改为 `_daemon_`（或改为无需 chown 的权限设置）。
- 改用 `_daemon_` 时要处理的要点：
  - host 侧大量 `docker exec <容器> ...` 调用会默认以 uid 584792 执行，需逐条确认仍能工作（`host-callers.txt`、`hostcmds.sh`）。
  - 绑定挂载进来的 `/var/run/redis` 等目录由 host 的 root 所有，需要调整属主或权限。
  - 非 root 进程拿不到 Docker 默认 capability：radvd 需要 raw socket，mgmt-framework 的 REST 服务监听特权端口，rsyslogd 需要写日志与 `/dev/log`。
- 某个容器确实无法以 `_daemon_` 运行时，记录阻塞原因与证据，交用户决定。

### 6.6 顺序与交付

按 **database → radv → eventd → mgmt-framework** 逐个推进，每个 rock 独立可交付（单独一个 PR）：

- database 已是 bare，剩余工作最少，用来先跑通 6.1、6.4 的过渡接入路径。
- radv 只多一个 radvd。
- eventd 有构建期 j2 渲染。
- mgmt-framework 依赖最多（libxml2、libcurl、libcjson 等），放最后。

### 6.7 验证

每个 rock：

1. 构建：`rockcraft pack` 成功；`scripts/rock_image_check.sh` 通过（entrypoint 是 pebble）。
2. 静态检查：rootfs 里没有 shell 以外不该有的整包残留；`/var/lib/chisel/manifest.wall` 存在；`docker run --rm <img> exec <每个服务二进制> --version`（或等价调用）无缺库。
3. dut2 实机：装入 broadcom 镜像（或替换单个容器镜像后重启服务），运行 `scripts/vs_rock_runtime_check.sh`（检查 pebble、服务状态、日志里无 `ImportError`/`cannot open shared object file` 等）。该脚本以 VS 为目标编写，在 broadcom 上需要确认 `ALLOWED_ERRORS`、`OPTIONAL_FEATURES` 是否适用。
4. 功能自检（沿用蓝图 8.1）：
   - database：`redis-cli ping`，`sonic-db-cli CONFIG_DB keys '*'`。
   - eventd：触发一个事件，确认写进 DB。
   - radv：确认发出 RA（抓包或看邻居）。
   - mgmt-framework：REST 端点响应。
5. 覆盖 6.2 的四条路径：冷启动、`config reload`、warm reboot、容器重启（基线上就不工作的路径除外，见 6.2“基线先行”）。
6. VS：在 sonic-vs 虚拟机上重复第 3 至 5 步；CI 的 `test-vs` job 也会跑 `vs_rock_runtime_check.sh`，必须通过。
7. 体积：与 4.1 的基线对比，记录结果。

## 7 · 风险

| 风险 | 应对 |
|---|---|
| 动态追踪漏掉低频路径（错误处理、特定配置下才执行的脚本），删多了 | 静态与动态取并集；删除项必须写理由；dut2 跑满四条路径 |
| 集成分支落后上游，或 PR 评审中 slice 改名 | rock 只引用集成分支的锁定 commit；重建分支时同步修改引用；slice 名集中在一个 part，替换一次即可 |
| rockcraft `latest/stable` 升级引入行为变化 | 本设计不改 CI；如遇问题再单独锁版本 |
| chiselled rootfs 没有 maintainer script 的副作用（用户、alternatives、`ld.so.cache`、`.pyc`） | 用户在配方里建；需要的 alternatives 链接靠 slice 的 `symlink:`；每容器抽查一次非默认库目录；`.pyc` 不处理（性能问题而非正确性问题） |
| 自建 libyang3 与 archive 版本号相同 | 本批不改；记录为已知风险，建议日后给自建版本加 `+sonic` 后缀 |
| 上游 PR 长期不合并 | 不阻塞交付：rock 一直按集成分支构建；上游推进按蓝图第 5 节 |

## 8 · 留给实施者

- 依赖采集脚本的具体实现（bpftrace 还是 bpfcc、放在本仓库的哪个目录）。
- 6.4 各 part 的命名与拆分细节，只要满足表中职责与“slice 只有一个来源”。
- 每个容器具体选哪些 slice（以 6.2 的清单为准）。
- dut2 上替换镜像的方式（整镜像安装或单容器替换）。

## 9 · 手动核对本文结论的方法

- slice 是否已在上游：在 chisel-releases 下执行 `git cat-file -e origin/ubuntu-26.04:slices/<pkg>.yaml`。
- libnl-cli 多余：`dpkg -x target/debs/resolute/libswsscommon_*.deb /tmp/x && readelf -d /tmp/x/usr/lib/x86_64-linux-gnu/libswsscommon.so.0* | grep NEEDED`。
- libyang 补丁未进上游：`gh pr view 2362 --repo CESNET/libyang --json state`。
- python3-libyang 不在 resolute：Launchpad API 查 `libyang-python` 的已发布版本。
- fork 已同步：在 chisel-releases 下执行 `git fetch fork && git rev-parse fork/ubuntu-26.04 origin/ubuntu-26.04`，两者应相同。
- bare 不能用 overlay：rockcraft 源码 `rockcraft/models/project.py` 的 `_validate_base_and_overlay`。
- git source 与自带 chisel：`grep -n pattern /snap/rockcraft/current/lib/python3*/site-packages/craft_parts/sources/git_source.py`；`/snap/rockcraft/current/libexec/rockcraft/chisel version`。
- 过渡写法先例：`git show ad9aa27c2:dockers/docker-database/rockcraft.yaml | sed -n 70,102p`。
- VS 镜像对应的 commit：`gh api repos/canonical/sonic-buildimage/actions/artifacts/13654753860 --jq .workflow_run.head_sha`；本机文件完整性：`sha256sum ~/Downloads/sonic-vs-img.zip`。
