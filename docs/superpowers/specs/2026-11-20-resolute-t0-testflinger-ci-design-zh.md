# `202605_resolute` 在 Testflinger 上自动跑 sonic-mgmt t0 —— 设计

- 日期：2026-11-20
- 仓库：`canonical/sonic-buildimage` `202605_resolute`，存放 workflow、Testflinger 测试脚本和已知失败清单
- 测试代码：`canonical/sonic-mgmt` 的锁定 commit，初始锁在 `a88d1d5f93`（PR 栈 #5–#9 的顶端）
- 被测镜像：`resolute-build` workflow 产出的 rock 版 vs 镜像（artifact `sonic-vs-img`）
- 以英文版为准；本中文版（`-zh.md`）是翻译

## 1. 目标与范围

在 Testflinger 的机器上，对 `resolute-build` 产出的 vs 镜像跑上游 KVM t0 PR checker 的测试列表，全程不需要人工操作。触发时机有三个：每晚定时、每次 push 或打 tag 后构建成功、在 PR 评论里手动要求。每次测试都对照一份经过审查的已知失败清单，报告有没有回归。

**范围内：**

1. 一个 GitHub Actions workflow：选出要测的构建，提交一个 Testflinger job，等它结束，判定结果并汇报。
2. Testflinger job，以及在分到的机器上运行的测试脚本：搭宿主机环境、建测试床、跑测试、打包结果。
3. 判定逻辑和已知失败清单。
4. 一次性准备：Testflinger 队列、cEOS 镜像、各项凭据。

**范围外：** Dockerfile（supervisord）版镜像（CI 只构建 rock 版）；t0 以外的拓扑（dualtor、t0-2vlans、t0-sonic、t1-lag）；arm64；broadcom 镜像和物理 DUT；修改 `resolute-build.yml`；上游化。

## 2. 决定

| 事项 | 决定 |
|---|---|
| 每次测试的规模 | 一台 Testflinger 机器、rock 版 vs 镜像、上游 t0 checker 全量列表。列表由锁定 commit 的 sonic-mgmt 里的 `get_test_scripts.py` 生成（`a88d1d5f93` 下为 392 个文件） |
| 镜像来源 | 最近一次成功构建的 `sonic-vs-img` artifact，不重新构建 |
| 触发方式 | 每晚定时；push 到 `202605_resolute` 或打 `v*` tag 后 `resolute-build` 成功；PR 评论 `/test-t0`；手动 dispatch |
| 谁能用评论触发 | 对本仓库有 `write`、`maintain` 或 `admin` 权限的用户 |
| 判定标准 | 仓库内维护已知失败清单；失败的文件重跑一次；只要有清单没覆盖的失败，结果就是红 |
| 放在哪里 | 全部放在 `canonical/sonic-buildimage`，sonic-mgmt 的锁定 commit 也在这里 |
| Runner | 一个跑在 `self-hosted-linux-amd64-noble-private-endpoint-small` 上的 job，从提交一直等到出报告 |
| 机器 | Testflinger 队列 `sonic-ci-large` |
| cEOS | `ghcr.io/canonical/sonic-ceos:4.32.5M-1`，可见性 internal。它就是 sonic-mgmt 自己从 cEOS tarball 构建出来的 `ceosimage:4.32.5M-1` 镜像；sonic-mgmt 在本地找到这个标签的镜像后，会跳过自己的 cEOS 准备流程。测试机用只有 `read:packages` 权限的 classic PAT 拉取，PAT 存在 Testflinger secret 里 |
| 日志 | 全部结果和日志用 zstd 压缩，经 Testflinger artifacts 取回 |
| 分块用的耗时数据 | 取最近一次 nightly 的 artifact，不提交进仓库 |

## 3. 已验证的事实

| 事实 | 依据 |
|---|---|
| 392 个文件的列表每个镜像要 40.7 个测试床·小时；旧的 271 个文件的列表要 33.7 | 2026-11-19 rock 版测试 JUnit 中各文件耗时的总和（比旧列表多出的 125 个文件合计 7.0 小时） |
| 本仓库可以使用 small runner | run 44701651973：runner 为 `private-endpoint-amd64-noble-small-*`，属于 "canonical self-hosted runners" 组；2 vCPU、7 GB 内存、19 GB 磁盘，Ubuntu 24.04，自带 `snap`、`docker`、`jq`、`yq`；能访问 Testflinger API 和 GitHub。从排队到开始用了 9 分钟 |
| 自建 runner 上单个 job 最长可跑 5 天；`timeout-minutes` 默认 360，必须调大 | GitHub Actions 用量限制 |
| `canonical/testflinger` 的 submit action 在 `poll: true` 时：setup 或 provision 失败会取消并重新提交（最多 `retries` 次），之后跟踪测试阶段；workflow run 被取消时会取消 Testflinger job | `canonical/testflinger` 的 `.github/actions/submit/action.yaml` |
| `sonic-ci-large` 里各 agent 的 `global_timeout` 为 43200 秒，`output_timeout` 为 8000 秒 | `canonical/testflinger-agent-charm-configs` 中各 agent 的 `testflinger-agent.conf` |
| agent 把 `artifacts/` 目录打成一个 tarball 上传；服务端默认单次请求上限 500 MB | agent 的 `save_artifacts`；服务端的 `MAX_BODY_SIZE` |
| 一个镜像的全部结果（389 个文件的 JUnit 和日志）共 1198 MB，`zstd -19` 后 17 MB | 2026-11-19 的 rock 版结果 |
| 组织成员推送镜像会创建 internal 的 GHCR 包；匿名拉取被拒；带 token 能拉；GHCR 不接受 fine-grained PAT | 探测包 `ghcr.io/canonical/sonic-ci-probe`（测完已删除）；GitHub 文档 |
| 分到的测试机上：嵌套 KVM 已开启；MAAS 配好了 apt 代理 `http://10.239.8.11:8000/`；GitHub、download.docker.com、azurecr.io、ghcr.io、PyPI、Testflinger 都能直连；从 GitHub 下载约 5.9 MB/s | 2026-11-20 在 romano 上的探测 job |
| 在 C3 "Customized queues" 里添加的队列，要等认证团队的机器人同步 `testflinger-agent-charm-configs` 后才会到达 agent，而这个同步没有固定周期 | `server-cert/data-tor3-dh1` 的提交历史 |
| 事件 payload 里的 `author_association` 会把组织私密成员显示为 `CONTRIBUTOR` | 本仓库 4 个活跃成员中有 3 个是私密成员 |
| 在 docker-sonic-mgmt 镜像里执行 `get_test_scripts.py --features "" --location <tests>`，得到的 `t0_checker` 列表就是那 392 个文件 | 在 `a88d1d5f93` 下执行，与 2026-11-19 的列表比对一致 |
| sonic-mgmt 发现本地已有 `ceosimage:4.32.5M-1` 标签的镜像时，会跳过 cEOS 的下载、导入和构建 | `ansible/roles/vm_set/tasks/add_ceos_list.yml` |
| 在 sonic-buildimage PR #30 合入之前，每次测试都会有几十个 loganalyzer teardown 错误，匹配到的唯一一行是 `nss_tacplus: /etc/tacplus_nss.conf fopen failed`，而且每次落在不同的用例上 | 2026-11-19 有 36 个；PR #30 仍未合入 |
| JUnit 用例的 `classname` 形如 `tests.<用点分隔的模块路径>[.<类名>]`；`run_tests.sh -m individual` 为每个测试文件单独写一个 JUnit 文件，路径与测试文件相同 | 2026-11-19 的结果 |

## 4. 架构

```
触发（schedule / workflow_run / issue_comment / workflow_dispatch）
  │
  ▼
resolute-t0.yml，small runner 上的一个 job，超时 1440 分钟
  1. 确定要测的构建 →（commit，构建 run id）；评论触发时校验权限
  2. 把 commit 状态 "resolute-t0" 设为 pending
  3. 下载 sonic-vs-img → 发布为 release 附件
  4. 打包测试脚本、已知失败清单、durations.json 和 sonic-mgmt 锁定版本
  5. canonical/testflinger submit action（poll: true，retries: 2）──► Testflinger
                                                                        │
     分到的机器，队列 sonic-ci-large，Ubuntu 26.04 ◄────────────────────┘
       宿主机环境 → LXD 虚拟机中的测试床 → 分块跑 t0 → 重跑 → results.tar.zst
                                                                        │
  6. 下载 Testflinger artifacts ◄───────────────────────────────────────┘
  7. 对照 known-failures.yaml 判定
  8. job summary、workflow artifact、commit 状态、PR 置顶评论
```

信任边界：在测试机上执行的所有脚本都来自默认分支（测试开始时 `202605_resolute` 的 HEAD），因为 `schedule`、`workflow_run`、`issue_comment` 三种触发都使用默认分支上的 workflow 文件。来自被测 commit 的只有两样：vs 镜像，以及作为数据的 `known-failures.yaml`。通过评论触发要求有写权限。

## 5. Workflow `.github/workflows/resolute-t0.yml`

### 5.1 确定要测的构建

| 触发 | 条件 | 被测构建 |
|---|---|---|
| `schedule` | 每天 15:00 UTC | `202605_resolute` 上事件为 `push` 的最近一次成功的 `resolute-build` run |
| `workflow_run` | `resolute-build` 以 `success` 结束，事件为 `push`，分支为 `202605_resolute` 或 `v*` tag | 触发它的那次 run |
| `issue_comment` | PR 上的评论，正文以 `/test-t0` 开头 | head SHA 等于该 PR head SHA 的最近一次成功的 `resolute-build` run |
| `workflow_dispatch` | 手动；输入 `run_id`（一次 `resolute-build` run）；输入 `scope`，取值 `full` 或 `smoke` | 指定的 run |
| `push` | 名为 `ci-workflow/t0-*` 的分支，仅供开发使用。固定为 `smoke`，不写 commit 状态，已知失败清单取自所推送的 commit | `202605_resolute` 上事件为 `push` 的最近一次成功的 `resolute-build` run |

评论触发时，先调用 `GET /repos/{repo}/collaborators/{user}/permission`，结果不是 `admin`、`maintain` 或 `write` 就停止。然后给评论加一个"eyes"表情。如果该 head SHA 没有成功的构建，或者它的 artifact 已过期（7 天），就在 PR 里回复说明并停止。

### 5.2 步骤

1. 确定要测的构建（5.1），输出 commit SHA 和构建 run id。
2. 把 commit 状态 `resolute-t0` 设为 `pending`，链接指向本次 run。
3. 从构建 run 下载 `sonic-vs-img`。把 `sonic-vs-<sha12>.img.gz` 及其 `.sha256` 上传到预发布 release `t0-images`，镜像附件只保留最新的 10 个，其余删除。
4. 从最近一次成功的定时 run 的 artifact 中取 `durations.json`。取不到就让分块脚本用默认值。
5. 生成 `t0-harness.tar.gz`，内容包括：默认分支上 `.github/testflinger/t0/` 目录的内容、被测 commit 中的 `known-failures.yaml`、`durations.json`。
6. 动用机器之前，先跑测试脚本中 Python 代码的单元测试（7.6）。
7. 渲染 Testflinger job 文件（6.1），用锁定到某个 commit 的 `canonical/testflinger/.github/actions/submit` 提交：`poll: true`，`retries: 2`，`attachments-relative-to` 设为工作目录，client id 和 secret 取自仓库 secret。
8. 下载 Testflinger artifacts（`testflinger-cli artifacts <job>`）；测试阶段失败也照样下载。
9. 执行判定（7.3），写 job summary。
10. 上传 workflow artifact `resolute-t0-<sha12>-<attempt>`（结果、`summary.json`、`durations.json`），保留 30 天。
11. 设置最终的 commit 状态。评论触发时，在 PR 里新建或更新那条带 `<!-- resolute-t0 -->` 标记的评论。

job 设置：`timeout-minutes: 1440`；并发组 `resolute-t0-<sha>`，`cancel-in-progress: false`；权限为 `contents: write`（release 附件）、`statuses: write`、`pull-requests: write`、`issues: write`（表情和评论）、`actions: read`（读取其他 run 的 artifact）。job 超时时，最后一步会取消 Testflinger job，并报告为 `error`（基础设施问题）。

## 6. Testflinger job 和测试脚本

### 6.1 job 文件

```yaml
job_queue: sonic-ci-large
global_timeout: 43200
output_timeout: 7200
tags: [sonic-buildimage-t0, "sha:<sha12>", "gh-run:<run id>"]
provision_data:
  distro: resolute
test_data:
  attachments:
    - local: t0-harness.tar.gz
  secrets:
    GHCR_TOKEN: sonic-buildimage/ghcr-read-token
  test_cmds: |
    <agent 端脚本，见 6.2>
```

### 6.2 agent 端（`test_cmds`）

agent 端只做最少的事：

1. 把附件复制到测试机（`ubuntu@$DEVICE_IP`，`BatchMode=yes`）。
2. 在测试机上以脱离会话的方式（`setsid nohup`）启动 `run-t0.sh`，传入镜像 URL、它的 SHA-256 和测试范围。`GHCR_TOKEN` 经 SSH 会话的 stdin 进入这个后台进程的环境变量，不出现在任何命令行上。这样即使 SSH 连接中断，测试也不会停。
3. 每分钟取一次测试机上 `progress.log` 新增的行并打印出来，直到测试脚本写出 `EXIT` 文件。
4. 不管退出码是多少，都把 `results.tar.zst`、`run-meta.json` 和测试脚本日志复制到 `artifacts/`。

### 6.3 测试机上的脚本（`run-t0.sh`）

1. **搭宿主机环境。** 以下修正来自 2026-11-10/11-19 的几次测试：
   - 每个 LXD 虚拟机的根文件系统做 growpart；
   - 在 `DOCKER-USER` 链放行 `lxdbr0`；
   - 沿用 MAAS 配好的 apt 代理，并复制进各虚拟机；
   - 从 download.docker.com 安装 docker-ce；
   - openvswitch-switch 首次安装后先 `reset-failed` 再重启；
   - add-topo 之前先拉好 `publicmirror.azurecr.io/debian:trixie`；
   - 在虚拟机里关掉 `apt-daily*` 和 `unattended-upgrades`；
   - 机器有 200 GB 以上的空闲 SSD 时，用它们组一个 zfs 池放虚拟机；没有就放在系统 SSD 上的 LXD `default` 目录池里；机械盘一律不用。
2. **定规模。** 测试床数 T = min(⌊(内存 GiB − 16) / 18⌋, ⌊线程数 / 8⌋, ⌊存储池可用 GB / 40⌋)。每个虚拟机分 ⌊线程数 / T⌋ 个 vCPU、18 GiB 内存、140 GiB 稀疏磁盘。`scope=smoke` 时 T 最多为 2。T 会打印出来，也记进 `run-meta.json`。
3. **准备测试材料。**
   - 从 release 下载 vs 镜像并校验 SHA-256。
   - 用 `GHCR_TOKEN` `docker pull` cEOS 镜像。docker 配置目录放在 `/dev/shm` 里，拉完立即删除，所以 token 不落盘，也不进任何虚拟机。把镜像打上 `ceosimage:4.32.5M-1` 标签，导出到虚拟机只读挂载的共享目录。
   - 把锁定 commit 的 sonic-mgmt 以 GitHub tarball 形式下载到共享目录，再用 `configure_sonic_mgmt.py` 做上游 KVM 测试床文档要求的配置：VM 宿主机的用户名和密码、`ansible_python_interpreter`、被 git 忽略的 `ansible/password.txt`。虚拟机用 `cp -a` 复制这棵目录树，软链接全部保留。
4. **测试列表。** 在 docker-sonic-mgmt 镜像里、锁定 commit 下运行 `get_test_scripts.py --features ""`，取其中的 `t0_checker` 列表。`scope=smoke` 时改用 `smoke.txt`：4 个短文件，pretest 和 posttest 由 `run_tests.sh` 自动加上。
5. **分块。** 根据 `durations.json` 把文件打包成每块约 50 分钟的块，先放耗时长的；没有记录的文件按 480 秒估算。`scope=smoke` 时每个文件单独一块。所有块放进一个共享队列，每个测试床通过原子 rename 领取下一块。
6. **执行。** 每个测试床先做一次 add-topo 和 deploy-mg，然后用 `run_tests.sh -m individual` 跑领到的块。每跑完一块，用 `verdict.py rerun-files` 列出有失败或错误、且不在已知失败清单里的文件；测试床先用 deploy-mg 恢复 DUT 配置，再把这些文件重跑一次。用例的最终结果以最后一次运行为准，首次结果保留下来写进报告。如果某个测试床在跑一块的中途挂掉，这一块会退回队列，但只退一次。
7. **时间保护。** 测试脚本启动 10.5 小时后不再派发新块，从未开始的文件记为"未执行"。
8. **进度。** 每 5 分钟往 `progress.log` 追加一行：待领、在跑、已完成的块数，以及已结束的测试床数。agent 会把这些行打印出来，这同时防止触发 `output_timeout`。
9. **输出。**
   - `results.tar.zst`：按测试床和块组织的全部 JUnit 文件和日志，以及每块的开始、结束时间；
   - `run-meta.json`：机器名、T、镜像 SHA-256、sonic-mgmt commit、测试范围、完整文件列表、各阶段耗时、是否触发了时间保护、测试脚本的退出码。

解析 JUnit 的是 runner，不是测试机：`verdict.py report` 生成 `summary.json`（结论和每个用例的结果）和 `durations.json`（本次每个文件的耗时）。

### 6.4 文件布局

```
.github/workflows/resolute-t0.yml
.github/testflinger/t0/
  job.yaml.in            job 模板（6.1）
  render_job.py          渲染 job.yaml.in
  agent.sh               agent 端（6.2）
  run-t0.sh              测试机入口（6.3）
  host-setup.sh          宿主机修正、存储池、定规模
  configure_sonic_mgmt.py  sonic-mgmt 目录树的测试床配置
  tb-run.sh              每个测试床的工作循环：add-topo、deploy-mg、领块、重跑
  make_chunks.py         分块
  verdict.py             重跑选择、判定和报告渲染（7）
  tests/                 各 Python 文件的 pytest 单元测试
  known-failures.yaml    经过审查的已知失败（7.1）
  sonic-mgmt.ref         锁定的 canonical/sonic-mgmt commit SHA
  smoke.txt              冒烟列表
```

## 7. 判定和汇报

### 7.1 `known-failures.yaml`

```yaml
known:
  - id: "snmp/test_snmp_v2mib.py::test_snmp_v2mib[vlab-01]"
    kind: fail
    reason: "sysDescr names Debian; product issue, see sonic-mgmt PR #4"
  - id: "generic_hash/test_generic_hash.py::*"
    kind: flaky
    reason: "Random parameter sets; the same cases are unstable on upstream vs"
loganalyzer_noise:
  - pattern: 'nss_tacplus: (/etc/tacplus_nss\.conf fopen failed|bad config or server line)'
    reason: "AppArmor stops unix_chkpwd reading tacplus_nss.conf; fixed by sonic-buildimage PR #30"
```

- `id`：相对 `tests/` 的 pytest 节点 ID，由 JUnit 文件路径、类名和测试名拼成。`*` 匹配任意文本；其他字符（包括 `[` 和 `]`）都只匹配自身。
- `kind`：`fail`（测试失败）、`error`（setup 或 teardown 出错）或 `flaky`（任何结果都接受，通过了也不提示）。
- `reason`：必填，用英文写。
- `loganalyzer_noise`：针对 syslog 行的正则表达式。loganalyzer 引起的 teardown 错误，如果它匹配到的行全部命中这些规则，就忽略这个错误；只要有一行不命中，错误就保留。
- 对清单的任何修改都必须走 PR。

### 7.2 每个用例的归类

最终结果是失败或错误的用例，如果有一条 `id` 匹配的条目，且其 `kind` 相同或为 `flaky`，就算**已覆盖**；否则就是**新失败**。清单条目还会被归入另外两组：

- **已通过**：`kind` 为 `fail` 或 `error` 的条目，其 `id` 至少匹配到一个用例，且匹配到的用例全部通过；
- **已失效**：`id` 没有匹配到任何用例、但其文件部分匹配到了本次跑过的某个文件的条目。文件不在本次列表里的条目（例如 `scope=smoke` 时）不报告。

### 7.3 一次测试的结论

| 条件 | commit 状态 | summary 标题 |
|---|---|---|
| 至少有一个新失败或新错误 | `failure` | Regressions（回归） |
| 没有新失败，但有文件未执行 | `error` | Incomplete（不完整） |
| 装机重试后仍失败、job 超时、没有拿回 `run-meta.json`，或测试脚本以非零退出 | `error` | Infrastructure（基础设施问题） |
| 其他情况 | `success` | Pass（通过） |

"已通过"和"已失效"的条目不影响结论，只是列出来，方便清理清单。

### 7.4 报告内容

job summary 和 PR 评论包含：

- 结论，以及通过、跳过、失败、错误、未执行的总数；
- 新失败：每条附报错的第一行和对应的日志文件名；
- 已覆盖的失败（折叠显示）；
- "已通过"和"已失效"的条目；
- 只在重跑时才通过的用例；
- 测试环境：机器名、测试床数、镜像 commit、sonic-mgmt commit、各阶段耗时。

### 7.5 清单的第一版

第一版清单由 M3 全量测试（第 9 节）生成。与 2026-11-19 的 rock 版结果（sonic-mgmt `a88d1d5f93`、镜像 `7a081af43c` 下：1219 通过 / 2654 跳过 / 31 失败 / 17 setup 错误）相比，每一处差异都要写明原因，否则在提交清单之前修好。

### 7.6 单元测试

用 pytest 加小的 JUnit 样例覆盖：

- `id` 匹配，带 `*` 和不带 `*` 的情况；
- 7.3 中的四种结论；
- "已通过"和"已失效"；
- 重跑之后的最终结果；
- `make_chunks.py`：除非单个文件本身就超长，否则任何一块都不超过目标时长；每个文件恰好出现一次。

## 8. 一次性准备

| # | 步骤 | 负责人 |
|---|---|---|
| 1 | 把本地的 `ceosimage:4.32.5M-1` 推到 `ghcr.io/canonical/sonic-ceos:4.32.5M-1`（internal） | Agent |
| 2 | 生成只勾 `read:packages`、有效期一年的 classic PAT，并实测能用它 `docker pull` | 用户生成，Agent 验证 |
| 3 | 用 CI client id 把 PAT 写入 Testflinger secret `sonic-buildimage/ghcr-read-token` | Agent |
| 4 | 添加仓库 secret `TESTFLINGER_CLIENT_ID` 和 `TESTFLINGER_SECRET_KEY` | 用户（需要仓库管理员权限） |
| 5 | 确认 `testflinger-cli list-agents --filter-queues sonic-ci-large` 能列出这 10 台机器；不能的话，请认证团队同步一次 TOR3-DH1 | Agent 检查，用户去找人 |

`sonic-ci-large` 的 10 台机器：fleetroc（20 个测试床）；alarmmonkey、alienbunny、kroop、vlacq、cajal、parakarry（各 16）；smilax、jasperoid、hoodin（各 13）。入选标准是"至少能起 13 个测试床"。装机成功率不作为标准，因为 submit action 会重试装机。

## 9. 验证

workflow 进入默认分支之前，`schedule`、`workflow_run`、`issue_comment` 这三种触发都不会生效。合入前的测试改用 push 到 `ci-workflow/*` 分支来触发；这个分支的提交同时删除 `resolute-build.yml`，以免 push 顺带启动构建。

| 阶段 | 内容 | 通过标准 |
|---|---|---|
| M1 | 在一台 `sonic-ci-large` 机器上手动执行 `run-t0.sh`，`scope=smoke` | 每个冒烟文件都有 JUnit 结果，2 个测试床各自至少跑了一块，对结果执行 `verdict.py report` 得到预期的结论 |
| M2 | 在 `ci-workflow/*` 分支上跑完整 workflow，`scope=smoke` | commit 状态、job summary、workflow artifact、Testflinger artifact 都出现，且彼此一致 |
| M3 | 完整 workflow，`scope=full` | 在 16 个测试床的机器上 6 小时内跑完；写出第一版 `known-failures.yaml`（7.5） |
| M4 | 向 `202605_resolute` 提 PR，合入后验证 | 一次 nightly、一次合入后的 `workflow_run`、一次 `/test-t0` 评论触发，各自完整跑完并出报告 |

## 10. 风险

| 风险 | 应对 |
|---|---|
| `sonic-ci-large` 队列还没同步到 agent | 第 8 节第 5 步在 M1 之前检查；请认证团队同步 |
| canonical 组织禁用 classic PAT | 第 8 节第 2 步就能发现；改用机器人账号或 GitHub App |
| 机器是共享的，排队时间没有上限 | `timeout-minutes: 1440` 封顶；超时记为"基础设施问题"，不算回归 |
| 部分机器装机经常失败（parakarry 50%，大多来自 kernel-team 的 job） | `retries: 2`；如果我们自己的 job 也反复失败，就把它移出队列 |
| 升级 sonic-mgmt 带来新的环境坑或新的失败 | 锁定版本只能经 PR 修改，同一个 PR 里同步更新清单，并用 `/test-t0` 验证 |
| PR 构建的镜像会跑在 lab 硬件上 | 只有有写权限的用户能触发；GHCR token 只在虚拟机启动前由宿主机使用，从不进入虚拟机 |
| PAT 属于个人 | GitHub 会在过期前提醒；有机器人账号后迁移过去 |
| small runner 的容量或启动延迟 | 实测约 9 分钟；整个 job 没有比 24 小时更紧的时限 |
