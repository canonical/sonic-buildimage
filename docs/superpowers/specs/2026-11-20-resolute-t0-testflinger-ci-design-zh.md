# 在 Testflinger 上为 `202605_resolute` 自动运行 sonic-mgmt t0——设计

- 日期：2026-11-20
- 仓库：`canonical/sonic-buildimage` 的 `202605_resolute` 存放 workflow、Testflinger 脚本和已知失败清单
- 测试代码：`canonical/sonic-mgmt` 的锁定提交 `2c54e70968`，即叠在 PR #5–#9 这一串之上的 PR #4
- 被测镜像：`resolute-build` workflow 产出的 rock 版 vs 镜像（artifact `sonic-vs-img`）
- 英文版是唯一的权威版本；中文版（本文件）是翻译

## 1. 目标与范围

在 Testflinger 的机器上，用上游 KVM t0 PR 检查的测试清单测试 `resolute-build` 产出的 vs 镜像，全程无需人工操作。每晚运行一次，每次 push 或 tag 构建成功后运行一次，也可以在 PR 评论里按需触发。每次运行都对照一份经过评审的已知失败清单报告回归。

**范围内：**

1. 一个 GitHub Actions workflow：选定构建，提交一个 Testflinger 任务，等它结束，判定结果并报告。
2. Testflinger 任务和在预留机器上运行的脚本。脚本负责准备主机、建测试床、跑测试、打包结果。
3. 判定逻辑和已知失败清单。
4. 一次性准备：Testflinger 队列、cEOS 镜像及其访问权限、Testflinger 凭据。

**范围外：** Dockerfile（supervisord）版镜像，因为 CI 只构建 rock 版；t0 以外的拓扑（dualtor、t0-2vlans、t0-sonic、t1-lag）；arm64；broadcom 镜像和物理 DUT；`resolute-build.yml` 中除 artifact 保留期以外的改动；推送到上游。

## 2. 决定

| 主题 | 决定 |
|---|---|
| 一次运行的规模 | 一台 Testflinger 机器、rock 版 vs 镜像、上游完整的 t0 检查清单。清单由锁定的 sonic-mgmt 提交里的 `get_test_scripts.py` 生成，去掉 `run_tests.sh` 永远不会运行的目录（`2c54e70968` 下为 389 个文件） |
| 镜像 | 最近一次成功构建的 `sonic-vs-img` artifact，不重新构建。`resolute-build` 将该 artifact 保留 30 天 |
| 触发方式 | 每晚定时；`202605_resolute` 的 push 或 `v*` tag 触发的 `resolute-build` 成功后；PR 评论 `/test-t0`；手动触发 |
| 谁能通过评论触发 | 对仓库有 `write`、`maintain` 或 `admin` 权限的用户 |
| 通过与否 | 仓库里维护一份已知失败清单。失败的文件重跑一次。清单未覆盖的失败使运行判红 |
| 放在哪里 | 全部放在 `canonical/sonic-buildimage`，包括锁定的 sonic-mgmt 提交 |
| Runner | `t0` job 从提交到判定都跑在 Canonical 的普通 runner `self-hosted-linux-amd64-noble-medium` 上。`resolve` 和 `report` 两个 job 跑在 `ubuntu-latest` 上 |
| 机器 | Testflinger 队列 `sonic-ci` |
| 测试机如何拿到镜像和 cEOS | 测试机自己下载构建 artifact、拉取 cEOS 镜像，用的是 `t0` job 的 `GITHUB_TOKEN`。这个令牌只能读 actions、contents 和 packages，job 结束即失效，以每次运行单独的 secret 送到 Testflinger。不涉及任何个人访问令牌 |
| cEOS | `ghcr.io/canonical/sonic-ceos:4.32.5M-1`，可见性为 internal，并给 `canonical/sonic-buildimage` 开了 Actions 读权限。它就是 sonic-mgmt 自己从 cEOS 压缩包构建出的 `ceosimage:4.32.5M-1`；sonic-mgmt 在本地找到这个标签后就跳过自己的 cEOS 准备 |
| 装机 | 每次最多 25 分钟；超时或失败就取消任务并重新提交，最多再交两次。在队列里排队的时间不设限 |
| 日志 | 全部结果和日志用 zstd 压缩，通过 Testflinger artifacts 取回 |
| 测试块时长 | 脚本目录里的 `durations.json` 是在 M3 上实测的；最近一次任意类型的完成 run 中测到的条目会覆盖它。每个测试块的目标大小是估计总时长除以「测试床数 × 2 轮」 |

## 3. 已核实的事实

| 事实 | 依据 |
|---|---|
| 392 个文件的清单每个镜像要 40.7 测试床小时；旧的 271 个文件的清单要 33.7 | 2026-11-19 rock 版运行的 JUnit 文件时长之和（旧清单以外的 125 个文件多出 7.0 小时） |
| 在 16 个测试床的机器上，389 个文件含 pretest 和 posttest 共需 45.7 测试床小时；每个测试块的 pretest 约 7 分钟、posttest 约 5 分钟 | M3，run 45114609003（alarmmonkey） |
| Canonical 的普通 runner 几秒内就能接到 job。private-endpoint 那一池很小，只留给需要访问内部服务的 job | `canonical/self-hosted-github-runner-docs`；在 `private-endpoint-small` 上的 job 等了 18 分钟也没分到 runner，`noble-medium` 5 秒内就开始了（run 45097064692 和 45099274044） |
| self-hosted runner 上的 job 最长可跑 5 天；`timeout-minutes` 默认 360，必须调高 | GitHub Actions 使用限制；runner 文档 |
| maas2 的装机超时（60 分钟）来自 agent 配置（`timeout_min`），不能按任务设置；`canonical/testflinger` 的 submit action 自身也没有任何上限 | `device-connectors/.../maas2/maas2.py`；`.github/actions/submit/action.yaml` |
| `sonic-ci` 机器上成功的部署用时 3.4–26.5 分钟（p90 16.1）；50 次失败的装机里有 49 次跑满 62–66 分钟才报失败；我们自己 28 次装 resolute，MAAS 部署最长 17.7 分钟，整个装机阶段最长 19.6 分钟 | 11 台 `sonic-ci` agent 自 2026-11-16 起保留的 Testflinger 结果；我们自己的任务日志 |
| `sonic-ci` 的 agent 设置为 `global_timeout` 43200 秒、`output_timeout` 8000 秒 | `canonical/testflinger-agent-charm-configs` 里各 agent 的 `testflinger-agent.conf` |
| agent 把 `artifacts/` 目录打成一个压缩包上传；服务器默认每个请求最多接受 500 MB | agent 的 `save_artifacts`；服务器的 `MAX_BODY_SIZE` |
| 一个镜像的全部结果（389 个文件的 JUnit 和日志）共 1198 MB，`zstd -19` 后 17 MB | 2026-11-19 的 rock 版结果 |
| 即使仓库是公开的，下载 workflow artifact 也需要令牌（匿名返回 401；只有 `read:packages` 的 classic PAT 返回 403，提示需要 actions 权限）。API 返回一个跳转到签名 blob URL 的重定向，有效期只有几分钟。带 `actions: read` 的 `GITHUB_TOKEN` 在任何主机上都能用 | 2026-11-23 的测试；M2，run 45107247028 |
| 个人令牌中 GHCR 只接受 classic PAT。workflow 的 `GITHUB_TOKEN` 可以拉取给该仓库开了 Actions 访问权限的包。用令牌登录时 GHCR 不检查用户名 | GitHub 文档；故意用错误用户名拉取的测试；M2 |
| 组织成员 push 时创建的 GHCR 包可见性为 internal；匿名拉取被拒绝 | 探测包 `ghcr.io/canonical/sonic-ci-probe`（测试后已删除） |
| 在预留的机器上：嵌套 KVM 已开启；MAAS 配置了 apt 代理，它走 HTTPS 时解析不了 download.docker.com；GitHub、download.docker.com、azurecr.io、ghcr.io、PyPI 和 Testflinger 都能直连；从 GitHub 下载约 5.9 MB/s | 2026-11-20 在 romano 上的探测任务；M1 |
| 在 C3 的「Customized queues」里加的队列，要等认证机器人同步 `testflinger-agent-charm-configs` 后才会到达 agent，而同步没有固定时间 | `server-cert/data-tor3-dh1` 的提交历史 |
| 事件负载里的 `author_association` 会把私密身份的组织成员显示为 `CONTRIBUTOR` | 本仓库 4 名活跃成员中有 3 名是私密身份 |
| 在 docker-sonic-mgmt 镜像里运行 `get_test_scripts.py --features "" --location <tests>`，得到同样的 392 个文件的 `t0_checker` 清单。`run_tests.sh` 会悄悄丢掉其 `SKIP_FOLDERS`（`ptftests acstests saitests scripts k8s sai_qualify`）下的所有文件，因此去掉了 3 个 k8s 文件 | 在 `a88d1d5f93` 上运行；`tests/run_tests.sh` |
| 上游 KVM PR 检查会加上 `--device_type=vs`，在 fixture 建立之前就跳过标了 `device_type('physical')` 的测试；`t0_checker` 清单里有 23 个文件带这个标记 | `.azure-pipelines/test_plan.py`；`tests/common/plugins/custom_markers` |
| sonic-mgmt 发现本地有标签为 `ceosimage:4.32.5M-1` 的镜像时，就跳过下载、导入和构建 cEOS | `ansible/roles/vm_set/tasks/add_ceos_list.yml` |
| add-topo 运行的 `docker-ptf` 用的是 sonic-mgmt 分支对应的标签（`202605`），不是 `latest` | `ansible/roles/vm_set/tasks/add_topo.yml` |
| 在 sonic-buildimage PR #30 合入之前，一次运行会有几十个 loganalyzer 报错，其唯一匹配行是 `nss_tacplus: /etc/tacplus_nss.conf fopen failed`，每次落在不同的用例上。自带 LogAnalyzer 的测试会报成 `LogAnalyzerError: match: N`，完整的日志行在 traceback 的 `E` 块里 | 2026-11-19 有 36 个这样的报错；M3 上的 `test_pktgen` 和模拟温度的那个测试 |
| JUnit 用例的 `classname="tests.<以点分隔的模块路径>[.<类名>]"`；`run_tests.sh -m individual` 为每个测试文件写一个 JUnit 文件，路径与测试文件一致 | 2026-11-19 的结果 |

## 4. 架构

```
触发（schedule / workflow_run / issue_comment / workflow_dispatch）
  │
  ▼
resolve（ubuntu-latest）：选定构建及其 artifact；评论触发时校验权限；
                          把提交状态 "resolute-t0" 设为 pending
  │
  ▼
t0（noble-medium，超时 1440 分钟，令牌：actions/contents/packages 只读）
  1. 单元测试；测试块时长；打包测试脚本和已知失败清单；渲染任务
  2. 把本 job 的 GITHUB_TOKEN 写成本次运行专用的 Testflinger secret
  3. submit.sh：提交任务，每次装机最多 25 分钟，重试 2 次 ──► Testflinger
                                                                   │
     分到的机器，队列 sonic-ci，Ubuntu 26.04 ◄─────────────────────┘
       主机准备 → 用令牌下载 artifact、拉取 cEOS →
       LXD 虚拟机中的测试床 → 分块跑 t0 → 重跑 → results.tar.zst
                                                                   │
  4. 跟踪测试阶段；删除 secret                                     │
  5. 下载 Testflinger artifacts ◄──────────────────────────────────┘
  6. 对照 known-failures.yaml 判定；job summary；workflow artifact
  │
  ▼
report（ubuntu-latest）：最终提交状态；PR 置顶评论
```

信任边界：在测试机上运行的所有脚本都来自默认分支（运行时的 `202605_resolute`），因为 `schedule`、`workflow_run` 和 `issue_comment` 都运行默认分支上的 workflow 文件。只有两样东西来自被测提交：vs 镜像，以及作为数据的 `known-failures.yaml`。只有有写权限的用户才能通过评论触发运行。测试机拿到的是 `t0` job 的令牌，它只能读，并随该 job 结束而失效；写提交状态和评论都在另外两个 job 里完成。

## 5. Workflow `.github/workflows/resolute-t0.yml`

### 5.1 选定构建

| 触发 | 条件 | 被测构建 |
|---|---|---|
| `schedule` | 每天 UTC 15:00 | `202605_resolute` 上事件为 `push` 的最近一次成功的 `resolute-build` run |
| `workflow_run` | `resolute-build` 以 `success` 完成，事件为 `push`，分支为 `202605_resolute` 或 `v*` tag | 触发它的那次 run |
| `issue_comment` | PR 上以 `/test-t0` 开头的评论（第一行含 `smoke` 则用冒烟清单） | head SHA 等于 PR head SHA 的最近一次成功的 `resolute-build` run |
| `workflow_dispatch` | 手动；输入 `run_id`（一次 `resolute-build` run）；输入 `scope` 为 `full` 或 `smoke` | 指定的 run，或最近一次 push 构建 |
| `push` | 名为 `ci-workflow/t0-*` 的分支，仅用于开发。默认 `smoke`，分支名为 `ci-workflow/t0-full-*` 时为 `full`。提交状态和已知失败清单都用被推送的那个提交 | 分支名后缀 `-run<id>` 指定的构建 run，否则为 `202605_resolute` 最近一次成功的 push 构建 |

评论触发时，workflow 先调用 `GET /repos/{repo}/collaborators/{user}/permission`，结果不是 `admin`、`maintain` 或 `write` 就停止。随后给评论加一个「eyes」表情。如果该 head SHA 没有成功的构建，或其 artifact 已过期，就在 PR 上回复并停止。

### 5.2 步骤

**`resolve`**（权限：`actions: read`、`issues: write`、`pull-requests: write`、`statuses: write`）

1. 选定构建（5.1）。输出提交 SHA、构建 run id、`sonic-vs-img` artifact 的 id 以及 GitHub 为它记录的摘要。
2. 将提交状态 `resolute-t0` 设为 `pending`，链接到本次运行。

**`t0`**（权限：`actions: read`、`contents: read`、`packages: read`）

1. 在用机器之前，先跑脚本的单元测试（7.6）。
2. 生成 `durations.json`：以脚本目录里的那份为底，再用最近一次完成的 `resolute-t0` run（任意类型）的 `durations.json` 覆盖其中已有的条目。
3. 打包 `t0-harness.tar.gz`：默认分支上 `.github/testflinger/t0/` 的内容、被测提交里的 `known-failures.yaml`，以及 `durations.json`。
4. 渲染 Testflinger 任务（6.1）。
5. 把本 job 的 `GITHUB_TOKEN` 写入 Testflinger secret `sonic-buildimage/t0-run-<run id>-<attempt>`，一天后过期；用的是仓库 secrets 里的 CI client id 和密钥。
6. `submit.sh` 提交任务，在测试阶段开始时返回。装机阶段超过 25 分钟就取消；被取消或失败的 setup、装机会重新提交，最多再交两次。装机之前的各个状态都不设时限，包括 `running`（agent 已接下任务、还没开始 setup）。失败的那次尝试会先取消再提交下一次，免得它继续占着机器。这一步被中断时，它会取消 Testflinger 任务。
7. 跟踪测试阶段直到任务结束；workflow 被取消时，取消 Testflinger 任务。
8. 无论前面发生了什么，都删除这个 secret。
9. 下载 Testflinger 的结果和 artifacts（`testflinger results`、`testflinger artifacts`）。
10. 运行判定（7.3），写 job summary。
11. 上传 workflow artifact `resolute-t0-<sha12>-<attempt>`（`summary.json`、`report.md`、`durations.json` 和 Testflinger artifacts），保留 30 天。

**`report`**（权限：`actions: read`、`issues: write`、`pull-requests: write`、`statuses: write`）

1. 根据 `t0` 的结果设置最终提交状态；`t0` 没有跑完则为 `error`。
2. 评论触发时，创建或更新带标记 `<!-- resolute-t0 -->` 的那一条 PR 评论。

Job 设置：`t0` 的 `timeout-minutes: 1440`，并发组 `resolute-t0-<sha>`，`cancel-in-progress: false`；只要 `resolve` 选定了构建，`report` 就会运行，包括 `t0` 被取消或超时的情况。

## 6. Testflinger 任务与测试机脚本

### 6.1 任务文件

```yaml
job_queue: sonic-ci
global_timeout: 43200
output_timeout: 7200
tags: [sonic-buildimage-t0, "sha:<sha12>", "gh-run:<run id>"]
provision_data:
  distro: resolute
test_data:
  attachments:
    - local: t0-harness.tar.gz
  secrets:
    GH_TOKEN: sonic-buildimage/t0-run-<run id>-<attempt>
  test_cmds: |
    <agent side, 6.2>
```

`render_job.py` 会校验填入模板的每个值：SHA、run id、仓库名、artifact id 和摘要、scope、secret 路径。

### 6.2 Agent 端（`test_cmds`）

Agent 端做的事尽量少：

1. 把附件复制到测试机（`ubuntu@$DEVICE_IP`，`BatchMode=yes`）。
2. 在测试机上以脱离会话的方式（`setsid nohup`）启动 `run-t0.sh`，传入仓库、artifact id 和摘要、运行范围。`GH_TOKEN` 经由 SSH 会话的 stdin 进入后台进程的环境变量，绝不出现在命令行上。因此 SSH 连接断开也不会中止运行。
3. 每分钟取回测试机 `progress.log` 的新增行并打印，直到脚本写出 `EXIT` 文件。
4. 无论退出状态如何，都把 `results.tar.zst`、`run-meta.json`、脚本日志和各测试床的日志复制到 `artifacts/`。

### 6.3 测试机上的脚本（`run-t0.sh`）

1. **主机准备。** 下面这些修正来自 2026-11-10/11-19 的运行和 M1：
   - 对每个 LXD 虚拟机的根文件系统做 growpart；
   - 在 `DOCKER-USER` 链中放行 `lxdbr0`；
   - 虚拟机里 HTTP 继续用 MAAS 的 apt 代理，HTTPS 直连；
   - 从 download.docker.com 安装 docker-ce；
   - openvswitch-switch 首次安装后执行 `reset-failed` 并重启；
   - add-topo 之前先拉取 `publicmirror.azurecr.io/debian:trixie`；
   - 预先下载 `docker-sonic-mgmt:latest` 和 add-topo 实际运行的 `docker-ptf:202605`；
   - 在虚拟机里关掉 `apt-daily*` 和 `unattended-upgrades`；
   - 机器上有至少 200 GB 的空闲 SSD 时，用它们建 zfs 池放虚拟机，否则用根 SSD 上的 LXD `default` dir 池；从不使用机械盘。
2. **规模。** 测试床数 T = min(⌊(内存 GiB − 16) / 18⌋, ⌊线程数 / 8⌋, ⌊存储池空闲 GB / 40⌋)。每个虚拟机分到 ⌊线程数 / T⌋ 个 vCPU、18 GiB 内存和 140 GiB 的稀疏磁盘。`scope=smoke` 时 T 最多为 2。T 会打印出来并记入 `run-meta.json`。
3. **下载。**
   - 用 `GH_TOKEN` 向 GitHub API 取 artifact 的下载地址，立即下载 zip，失败则换一个新地址重试。用 artifact 摘要校验 zip，解出 `sonic-vs.img.gz` 并记录其 SHA-256。
   - 用同一个令牌 `docker pull` cEOS 镜像，docker 配置目录放在 `/dev/shm`，拉完立即删除。随后丢弃令牌，所以它既不会写入磁盘，也不会进入任何虚拟机。把镜像标为 `ceosimage:4.32.5M-1`，保存到虚拟机以只读方式挂载的共享目录。
   - 以 GitHub 压缩包的形式把锁定提交的 sonic-mgmt 下载到共享目录。用 `configure_sonic_mgmt.py` 应用上游 KVM 指南里的测试床设置：虚拟机宿主的用户名和密码、`ansible_python_interpreter`，以及被 git 忽略的 `ansible/password.txt`。虚拟机用 `cp -a` 复制这棵树，保留所有符号链接。
4. **测试清单。** 在锁定提交的 docker-sonic-mgmt 镜像里运行 `get_test_scripts.py --features ""`，取其 `t0_checker` 清单，去掉 `run_tests.sh` 的 `SKIP_FOLDERS` 下的文件。`scope=smoke` 时清单为 `smoke.txt`：4 个短文件；pretest 和 posttest 由 `run_tests.sh` 自己加上。
5. **测试块。** 按 `durations.json`（没有条目的文件按 480 秒算）从长到短装箱，每块的目标大小是估计总时长除以 2 × T。每个测试块的 pretest 和 posttest 约 12 分钟，所以块少而大反而更快：用 M3 校准的调度模型估算，16 个测试床的测试阶段约 3.1 小时，而 M3 按统一估值切块实际用了 3.9 小时。`scope=smoke` 时每个文件单独成块。测试块放进共享队列，最长的在前；每个测试床通过原子重命名领取下一块。
6. **执行。** 每个测试床先跑一次 add-topo 和 deploy-mg，然后像上游 PR 检查一样，用 `run_tests.sh -t t0,any -e --device_type=vs -m individual` 跑领到的测试块。每块跑完后，`verdict.py rerun-files` 列出有失败或报错、且未被已知失败清单覆盖的文件；测试床用 deploy-mg 恢复 DUT 配置，再把这些文件重跑一次。用例的最终结果取最后一次运行的结果，首次结果保留下来供报告使用。如果测试床在跑某块时挂掉，这块会退回队列一次。
7. **时间保护。** 脚本启动 10.5 小时后不再派发新的测试块。从未开始的文件记为「未运行」。
8. **进度。** 每 5 分钟向 `progress.log` 追加一行，记录待领、在跑、已完成的测试块数和已结束的测试床数。agent 会打印这些行，这也防止了 `output_timeout` 触发。
9. **输出。**
   - `results.tar.zst`：按测试床和测试块存放的所有 JUnit 文件和日志，以及每块的开始和结束时间；
   - `run-meta.json`：机器、T、artifact id、镜像 SHA-256、sonic-mgmt 提交、范围、完整文件清单、各阶段用时、时间保护是否触发，以及脚本的退出码。没有任何测试床跑完一块时，脚本以 3 退出。

解析 JUnit 文件的是 runner，不是测试机：`verdict.py report` 写出 `summary.json`（结论和每个用例的结果）和 `durations.json`（本次各文件的用时，每块的 pretest 和 posttest 分摊到块内文件上）。

### 6.4 文件布局

```
.github/workflows/resolute-t0.yml
.github/testflinger/t0/
  job.yaml.in            任务模板（6.1）
  render_job.py          渲染 job.yaml.in
  submit.sh              带装机时限和重试的提交（5.2）
  agent.sh               agent 端（6.2）
  run-t0.sh              测试机上的入口（6.3）
  host-setup.sh          主机修正、存储池、规模计算
  configure_sonic_mgmt.py  sonic-mgmt 目录的测试床设置
  tb-run.sh              每个测试床的工作脚本：add-topo、deploy-mg、领块循环、重跑
  make_chunks.py         测试块装箱
  durations.json         M3 实测的各文件用时
  verdict.py             重跑选择、判定和报告生成（7）
  tests/                 pytest 单元测试
  known-failures.yaml    经过评审的已知失败（7.1）
  sonic-mgmt.ref         锁定的 canonical/sonic-mgmt 提交 SHA
  smoke.txt              冒烟清单
```

## 7. 判定与报告

### 7.1 `known-failures.yaml`

```yaml
known:
  - id: "pc/test_po_cleanup.py::test_po_cleanup[*]"
    kind: error
    reason: "rock: Pebble stops rsyslogd in parallel with teammgrd, so the cleanTeamProcesses syslog lines are lost"
  - id: "radv/test_radv_run.py::test_radv_deployment_id"
    kind: fail
    reason: "test race: radvd respawns 6-7 s after the restart and on resolute the check runs after that"
loganalyzer_noise:
  - pattern: 'nss_tacplus: (/etc/tacplus_nss\.conf fopen failed|bad config or server line)'
    reason: "AppArmor stops unix_chkpwd reading tacplus_nss.conf; fixed by sonic-buildimage PR #30"
```

- `id`：相对于 `tests/` 的 pytest 节点 id，由 JUnit 文件路径、类名和测试名拼成。`*` 匹配任意文本；其他字符（包括 `[` 和 `]`）都按字面匹配。
- `kind`：`fail`（测试失败）、`error`（setup 或 teardown 报错）或 `flaky`（任何结果都接受，通过了也不提示）。
- `reason`：必填，用英文写。
- `loganalyzer_noise`：针对日志行的正则表达式。teardown 的 loganalyzer 报错里，如果匹配到的行全都命中其中某个模式，就忽略这个报错。测试自带的分析器抛出的 `LogAnalyzerError` 同样处理，前提是没有缺少预期消息、traceback 里完整日志行的数目正好等于报告的匹配数、并且每一行都命中某个模式。只要有一行不命中，报错就保留。
- 清单的每次修改都要走 PR。

### 7.2 每个用例的分类

最终结果为失败或报错的用例，如果有一条 `id` 匹配、且 `kind` 相同或为 `flaky` 的条目，就算**已覆盖**；否则算**新增**。清单条目还另外分两组报告：

- **已转为通过**：`kind` 为 `fail` 或 `error`、`id` 至少匹配到一个用例，并且匹配到的用例全部通过的条目；
- **过时**：`id` 一个用例都没匹配到，但其文件部分匹配到了本次运行过的文件的条目。文件不在本次清单里的条目（例如 `scope=smoke` 时）不报告。

### 7.3 运行结论

| 条件 | 提交状态 | 摘要标题 |
|---|---|---|
| 至少有一个新增的失败或报错 | `failure` | Regressions |
| 没有新增失败，但有文件未运行 | `error` | Incomplete |
| 任务没有提交成功、每次装机都失败或超时、workflow 被取消、没有取回 `run-meta.json`，或脚本以非零退出 | `error` | Infrastructure |
| 其他情况 | `success` | Pass |

「已转为通过」和「过时」的条目从不改变结论；把它们列出来，是为了方便清理清单。

### 7.4 报告

Job summary 和 PR 评论包含：

- 结论，以及通过、跳过、失败、报错、未运行的总数；
- 新增的失败，附每条消息的第一行和对应的文件日志名；
- 已覆盖的失败，默认折叠；
- 「已转为通过」和「过时」的条目；
- 只在重跑时才通过的用例；
- 机器、测试床数、镜像 SHA-256、sonic-mgmt 提交和各阶段用时。

### 7.5 清单的第一版

第一版清单来自 M3（run 45114609003：镜像 `d47807d2e1`，即 sonic-buildimage PR #34 的顶端；sonic-mgmt `a88d1d5f93`；alarmmonkey，16 个测试床）。经 loganalyzer 噪声过滤后有 44 个用例失败。这 44 个在 2026-11-19 的 rock 版运行里也全都失败，其中 41 个在当天的 Dockerfile 版镜像上同样失败。其中 16 个属于只能在物理机上跑的测试，M3 因为没有传 `--device_type=vs` 才跑了它们；脚本现在像上游一样跳过它们。另有 15 个是测试代码的问题，在锁定的 sonic-mgmt `2c54e70968` 里已经修好：sflow 的 setup 调用了 Python 3.14 已删除的 `pkgutil.find_loader`（14 个；sonic-mgmt #5 改用 `importlib.util.find_spec`），`test_snmp_v2mib` 期望 sysDescr 里是 Debian（1 个；sonic-mgmt #4，镜像侧由 sonic-buildimage #34 修复）。在这个锁定提交下，这两个文件在同一镜像上全部通过（run 45184346540：15 个通过，1 个跳过）。剩下的 13 个用例组成清单（9 条）。对照这份清单判定，M3 里没被覆盖的失败是那 16 个物理机专用的用例和在 sonic-mgmt 里修好的 15 个。

| 分组 | 用例数 | 原因 |
|---|---|---|
| TACACS 逐命令授权 | 3 | bash 插件把 `/usr/bin/*` 解析成 uutils 的二进制，任何服务器规则都匹配不上；这是产品问题 |
| radv deployment id | 1 | 测试竞态：检查发生在 radvd 已经重新拉起之后 |
| swss 重启后 STATE_DB 的 `PROCESS_HEALTH` | 1 | 本分支从上游 202605 分出的时间早于在 `swss.sh` 里清理它的回移 #28740 |
| gNMI 审计日志 | 5 | `src/sonic-gnmi` 早于写 `RPC_COMPLETION` 记录的上游 #750；rock 上，`/var/log/gnmi.log` 的 rsyslog 规则按 supervisord 的消息格式匹配，对不上 Pebble 的标签 |
| `test_po_cleanup`（rock） | 2 | teamd rock 没有让各守护进程排在 rsyslogd 之后，Pebble 并行停止 rsyslogd，teammgrd 的清理日志丢失 |
| `staticd` 的状态（rock） | 1 | rock 的服务用 `on-failure: shutdown`，Pebble 版退出监听程序不看 `auto_restart`，杀掉 zebra 会停掉整个 bgp 容器 |

分支早于上游的两组会随下一次合并上游消失；三个 rock 分组需要修改 rock 定义和 Pebble 退出监听程序。

### 7.6 单元测试

pytest 覆盖：

- 带和不带 `*` 的 `id` 匹配；
- loganalyzer 噪声过滤，包括测试自带的 `LogAnalyzerError`；
- 7.3 里的四种结论；
- 「已转为通过」和「过时」；
- 重跑之后的最终结果；
- `make_chunks.py`：除非单个文件就超过目标，否则没有测试块超过目标；每个文件恰好出现一次；自动目标让每个测试床跑两轮；
- `render_job.py`：渲染出的任务，以及每个值的校验；
- 用假的 Testflinger 命令测 `submit.sh`：正常运行、装机超过上限、排队时间不设限、处于 `running` 状态的任务、装机失败用完重试次数，以及失败的尝试在下一次提交前被取消；
- 所有脚本的 shell 语法。

## 8. 一次性准备

| # | 步骤 | 由谁做 |
|---|---|---|
| 1 | 把本地的 `ceosimage:4.32.5M-1` 推送到 `ghcr.io/canonical/sonic-ceos:4.32.5M-1`（internal） | Agent |
| 2 | 在包的设置里的「Manage Actions access」下，给 `canonical/sonic-buildimage` 设 Read 角色 | 用户（包管理员） |
| 3 | 添加仓库 secrets `TESTFLINGER_CLIENT_ID` 和 `TESTFLINGER_SECRET_KEY` | 用户（仓库管理员） |
| 4 | 在 C3 的「Customized queues」里设置 `sonic-ci` 的成员，并确认 `testflinger-cli list-agents --filter-queues sonic-ci` 列出的正好是那 10 台机器。如果不是，请认证团队同步 TOR3-DH1 | Agent 设置并检查；用户去请求同步 |

`sonic-ci` 的 10 台机器：fleetroc（20 个测试床）；alarmmonkey、alienbunny、kroop、vlacq、cajal、parakarry（各 16 个）；smilax、jasperoid、hoodin（各 13 个）。入选规则是「至少 13 个测试床」。装机可靠性不在规则里，因为失败和过慢的装机都会重试。

## 9. 验证

在 workflow 进入默认分支之前，`schedule`、`workflow_run` 和 `issue_comment` 都无法触发。合入之前，靠推送 `ci-workflow/t0-*` 分支来启动运行，该分支的提交同时删掉 `resolute-build.yml`，这样推送不会触发构建；后缀 `-run<id>` 用来指定构建。在 `sonic-ci` 的成员同步之前，这样的分支还可以把 `job_queue` 指向某一台大机器。

| 阶段 | 内容 | 验收标准 | 结果 |
|---|---|---|---|
| M1 | 在一台大机器上手动运行 `run-t0.sh`，`scope=smoke` | 每个冒烟文件都有 JUnit 结果，2 个测试床各至少跑了一块，对结果运行 `verdict.py report` 得到预期结论 | 通过：12 个通过，1 个跳过 |
| M2 | 在 `ci-workflow/t0-*` 分支上跑完整 workflow，`scope=smoke` | 提交状态、job summary、workflow artifact 和 Testflinger artifact 都出现，并且彼此一致 | 通过：run 45107247028，从推送到出报告 73 分钟 |
| M3 | 完整 workflow，`scope=full` | 在 16 个测试床的机器上 6 小时内跑完；写出第一版 `known-failures.yaml`（7.5） | 通过：run 45114609003，4 小时 28 分钟 |
| M4 | 向 `202605_resolute` 提 PR，以及合入之后 | 一次夜测、一次合入后的 `workflow_run` 运行、一次 `/test-t0` 评论触发的运行，都跑完并出报告 | 未完成 |

## 10. 风险

| 风险 | 对策 |
|---|---|
| `sonic-ci` 的成员还没同步到 agent，任务可能落到跑不完全量清单的小机器上 | 第 8 节第 4 步；请认证团队同步。开发分支可以指定某一台大机器 |
| 机器是共用的，排队时间没有上限 | `timeout-minutes: 1440` 限制了等待时间；这种情况以「Infrastructure」结束，而不是回归 |
| 部分成员装机经常失败（parakarry 50%，多数来自 kernel-team 的任务） | 每次最多 25 分钟，重试 2 次；如果我们的任务在某台机器上反复失败，就把它移出队列 |
| 令牌会到达实验室的共用机器 | 它是 `t0` job 自己的令牌：对 actions、contents 和 packages 只读，job 结束即失效；每次运行的 secret 一天后过期，并在 job 结束时删除；测试机在下载阶段之后、任何虚拟机启动之前就丢弃它 |
| PR 的镜像会在实验室硬件上运行 | 只有有写权限的用户才能触发；所有脚本都来自默认分支 |
| 升级 sonic-mgmt 会带来新的环境陷阱或新的失败 | 锁定的提交只通过 PR 修改，同一个 PR 同时更新清单，并用 `/test-t0` 验证 |
| 构建 artifact 在被测试之前过期 | `resolute-build` 将 `sonic-vs-img` 保留 30 天；artifact 不存在时会报告并停止运行 |
| vs 镜像变大 | 整条路径上没有比 artifact 本身更低的大小限制 |
