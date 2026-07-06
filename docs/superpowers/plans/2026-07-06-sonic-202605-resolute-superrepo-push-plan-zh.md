# SONiC 202605 Resolute — 超仓库 + 子模块上传计划 (ZH)

> **For agentic workers:** REQUIRED SUB-SKILL: 使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务执行本计划。步骤用 checkbox（`- [ ]`）语法跟踪。

**Goal:** 把 resolute 迁移工作上传到 `canonical/`——超仓库 build/docs 分支 + 14 个子模块分支——供团队 clone 并复现 resolute `vs` 构建。

**Architecture:** 在两个原仓库（`~/sonic-buildimage-resolute`、`~/sonic-buildimage`）上就地用 `git filter-repo --force` 清除 superpowers 文档，再 rebase 到 sonic-net 最新 `202605`（`9c84048a4`），重命名分支为 `202605_resolute` / `202605_resolute_doc`，推到 `canonical/`。14 个子模块的 `build:` 提交作为新 `202605_resolute` 分支推送（2 个先 rebase 到 202605 gitlink lock；7 个 canonical 已存在 repo 直推；7 个缺失 repo 先从 sonic-net fork）。最后改写 `.gitmodules` 把 14 个子模块指向 canonical。

**Tech Stack:** git, git-filter-repo, gh CLI（已认证为 `xdqi`，canonical org member，有建 repo 权限）。

---

## 执行结果总览（2026-07-06 完成）

> 全部 7 个 Task 完成，所有 checkbox 已勾选。用户在执行中追加 3 个约束（均已满足）：**身份重写**（`@local` → `Sheldon Qi <sheldon.qi@canonical.com>`）、**GPG 签名**（GitHub verified=true）、**子模块 ff**（14 子模块 build-commit 全部 parent = 202605 gitlink lock）。详见各 Task 的 **Result** 行。

### 最终产物（canonical/）
| 分支 | tip | 验证 |
|---|---|---|
| `canonical/sonic-buildimage@202605_resolute`（build） | `c7b71c085b5e4452252f2f78fb03cdf9df167f9e` | 95 迁移提交，ff from sonic-net/202605，无 superpowers，.gitmodules 14→canonical，14 gitlink 指向新签名子模块 sha，GitHub verified=true |
| `canonical/sonic-buildimage@202605_resolute_doc`（docs） | `ec99572bc82c78972dfbfaa7bafb8d435c7b6253` | 37 提交，6 双语 docs + 4 plans + 4 specs，0 pptx，GitHub verified=true |
| 14 子模块 `@202605_resolute` | 见 Task 5 表 | 全部 GitHub verified=true，ff from 各自 202605 gitlink lock |

### 与原计划的关键偏差（用户追加/执行中发现）
1. **身份重写（用户追加 Task 3b/4b）**：两仓库 + 14 子模块的 local `user.*` config 误设为 `@local`（迁移机器时忘配置）。删 local config + `git filter-repo --mailmap` 重写 + `git rebase --exec` GPG 签名。所有提交 committer → `Sheldon Qi`，上游贡献者 author 原样保留。
2. **安全 tag 不足以回退**：filter-repo 会重写 tag + gc 清原对象。追加仓库外 bundle 备份（`~/resolute-pre-filter-backup.bundle`、`~/doc-pre-filter-backup.bundle`）作真回退点。
3. **构建仓库 merge-base 是 `9c84048a4` 非 `77cfa809d`**：rebase `--onto sonic-net/202605 77cfa809d` 重放 11458 提交，git 自动 skip ~11364 上游、应用 94 迁移提交（计划预期 ~66）。其中 27 个上游 author 的 `[submodule] Update` bump 提交被重放——SONiC 仓库 gitlink-bump 固有特性，非 bug。
4. **`gh repo fork --remote=false` 语法不支持**（该 gh 版本）：省略 `--remote`（默认不加远端）。
5. **子模块 build-commit 重写改 sha**：Task 6 额外更新超仓库 14 gitlink 指向新签名 sha（原计划只改 .gitmodules URL）。
6. **超仓库 merge-base = sonic-net/202605 当前 tip `eeb4bff75c`**（执行时上游又推了提交，比计划写时的 `9c84048a4` 更新；ff YES 是关键）。

### 原仓库状态
- `~/sonic-buildimage-resolute` → `202605_resolute`（local user.* config 已删，全局 `Sheldon Qi` 生效）
- `~/sonic-buildimage` → `202605_resolute_doc`（同上）

---

## Global Constraints

- **不可逆。** `filter-repo --force` 重写 `~/sonic-buildimage-resolute` 和 `~/sonic-buildimage` 所有提交哈希并删除 `origin`。先打安全 tag（`pre-filter-resolute`、`pre-filter-docs`）。
- **rebase base**（两条超仓库分支）= sonic-net `202605` HEAD `9c84048a4`（merge-base `77cfa809d`）。
- **分支命名：** `202605_resolute`（构建，全部 repo）/ `202605_resolute_doc`（仅超仓库文档）。
- **不提交：** `.pptx`、`.pptx.md`、`sonic.code-workspace`（走 gitignore）。
- **2 个子模块需先 rebase**（`src/sonic-dash-ha`、`src/sonic-sairedis`）到其 202605 gitlink lock（`dec02a5d`、`cec72ecc`）——必须在超仓库 rebase 之前完成。
- **7 个 canonical repo 已存在**（push=True，分叉的独立镜像）——直推新分支，无 `--force`（新分支接受无共同祖先）。
- **7 个 canonical repo 缺失（404）**——推送前用 `gh repo fork --org canonical` 从 sonic-net fork。
- **filter-repo 不递归子模块**，不重映射 gitlink sha——超仓库 filter 后 14 个子模块指针原样保留。
- **顺序：** §6.1 子模块 rebase → §4 超仓库构建 rebase → §6.2 子模块推送 → §7 .gitmodules 改写 → 超仓库重推。

---

## Task 0: 预检验证

任何不可逆动作前，验证环境和所有假设。

**Files:** 无。

- [x] **Step 1: 确认 git-filter-repo 已装**

Run: `git filter-repo --version`
Expected: 打印版本（如 `2.47.0`）。若缺：`sudo apt install git-filter-repo`（有免密 sudo）。
**Result:** 初检时缺失，`sudo apt-get install -y git-filter-repo` 装好，`git filter-repo --version` 响应正常。

- [x] **Step 2: 确认 gh 已认证到 canonical**

Run: `gh auth status`
Expected: `✓ Logged in to github.com account xdqi`，token scopes 含 `repo` 和 `read:org`。
**Result:** `✓ Logged in to github.com account xdqi`，scopes `admin:public_key gist read:org repo`，ssh 协议。✅

- [x] **Step 3: 确认两原仓库在预期分支**

Run: `git -C ~/sonic-buildimage-resolute branch --show-current && git -C ~/sonic-buildimage branch --show-current`
Expected:
```
resolute
202605-wip
```
**Result:** `resolute` / `202605-wip`。✅

- [x] **Step 4: 确认 resolute 分支 tip 是 `2d1fc1b4f`（boost 1.83 baseline）**

Run: `git -C ~/sonic-buildimage-resolute log --oneline -1 resolute`
Expected: `2d1fc1b4f build: drop boost 1.88 adaptation, revert to 1.83 baseline`
**Result:** `2d1fc1b4f build: drop boost 1.88 adaptation, revert to 1.83 baseline`。✅

- [x] **Step 5: 确认 sonic-net 202605 HEAD 是 `9c84048a4`**

Run: `git -C ~/sonic-buildimage-resolute ls-remote https://github.com/sonic-net/sonic-buildimage.git refs/heads/202605`
Expected: 一行以 `9c84048a4` 开头（前 10 字符）。
**Result:** `9c84048a4240ea5d358f74b0821d2d51bba9a3b5 refs/heads/202605`。✅

- [x] **Step 6: 确认构建仓库无未提交改动阻塞改写**

Run: `git -C ~/sonic-buildimage-resolute status --short sonic-slave-resolute/Dockerfile.j2`
Expected: 空（boost 1.83 改动已在 `2d1fc1b4f` 提交）。
**Result:** 空（exit 0）。✅

- [x] **Step 7: 在构建仓库打安全 tag**

Run: `git -C ~/sonic-buildimage-resolute tag pre-filter-resolute resolute`
Expected: 无输出。验证：`git -C ~/sonic-buildimage-resolute rev-parse pre-filter-resolute` → `2d1fc1b4f` 的完整 sha。
**Result:** `pre-filter-resolute → 2d1fc1b4f7f1e8f87f3e33a26c29b4c4fc3a4f46`。✅ **注意**：filter-repo 会重写 tag，故追加仓库外 bundle 备份 `~/resolute-pre-filter-backup.bundle`（62M，resolute@2d1fc1b4f 完整历史）作真回退点。

---

## Task 1: Fork 7 个缺失的 canonical 子模块 repo

7 个 canonical repo 返回 404 的子模块需先从 sonic-net fork，推送前完成。先做这步，Task 5 时所有 14 个推送目标就都存在了。

**Files:** 无（GitHub 侧）。

**需 fork 的子模块（canonical repo ← sonic-net 源）：**
- `sonic-platform-vpp` ← `sonic-net/sonic-platform-vpp`
- `sonic-dhcp-relay` ← `sonic-net/sonic-dhcp-relay`
- `sonic-bmp` ← `sonic-net/sonic-bmp`
- `sonic-dash-ha` ← `sonic-net/sonic-dash-ha`
- `sonic-dash-api` ← `sonic-net/sonic-dash-api`
- `sonic-stp` ← `sonic-net/sonic-stp`
- `sonic-wpa-supplicant` ← `sonic-net/sonic-wpa-supplicant`

- [x] **Step 1: 先 fork 一个作 sanity check（按 R5）**

Run: `gh repo fork sonic-net/sonic-bmp --org canonical --remote=false`
Expected: 类似 `Created fork canonical/sonic-bmp`。若权限报错，STOP——你无 org fork 权限；请 canonical owner 先 fork 这 7 个 repo 再继续。
**Result:** `--remote=false` 在本机 gh 版本不支持（`the --remote flag is unsupported when a repository argument is provided`）。省略 `--remote`（默认不加远端）：`gh repo fork sonic-net/sonic-bmp --org canonical` → `https://github.com/canonical/sonic-bmp`。有 org fork 权限。✅

- [x] **Step 2: 验证 fork 存在**

Run: `gh api repos/canonical/sonic-bmp --jq '.full_name + " (fork=" + (.fork|tostring) + ")"'`
Expected: `canonical/sonic-bmp (fork=true)`。
**Result:** `canonical/sonic-bmp (fork=true)`。✅

- [x] **Step 3: fork 其余 6 个**

Run:
```
gh repo fork sonic-net/sonic-platform-vpp --org canonical --remote=false
gh repo fork sonic-net/sonic-dhcp-relay --org canonical --remote=false
gh repo fork sonic-net/sonic-dash-ha --org canonical --remote=false
gh repo fork sonic-net/sonic-dash-api --org canonical --remote=false
gh repo fork sonic-net/sonic-stp --org canonical --remote=false
gh repo fork sonic-net/sonic-wpa-supplicant --org canonical --remote=false
```
Expected: 每个打印 `Created fork canonical/<repo>`。
**Result:** 6 个全 fork 成功（均省略 `--remote`）：sonic-platform-vpp/sonic-dhcp-relay/sonic-dash-ha/sonic-dash-api/sonic-stp/sonic-wpa-supplicant。

- [x] **Step 4: 验证 7 个 fork 都存在**

Run: `for r in sonic-platform-vpp sonic-dhcp-relay sonic-bmp sonic-dash-ha sonic-dash-api sonic-stp sonic-wpa-supplicant; do gh api repos/canonical/$r --jq '"$r fork=\(.fork)"' 2>/dev/null && echo "  $r OK" || echo "  $r MISSING"; done`
Expected: 每行 `<repo> fork=true` 然后 `OK`。
**Result:** 7 个全 `fork=true OK`。✅

---

## Task 2: rebase 2 个 base 被上游 bump 的子模块（§6.1）

必须在 Task 3（超仓库 rebase）之前完成。`src/sonic-dash-ha` 和 `src/sonic-sairedis` 的 202605 gitlink lock 越过了其 build 提交的 parent——把 build 提交 rebase 到新 lock。

**Files:** 工作目录 `~/sonic-buildimage-resolute/src/sonic-dash-ha` 和 `~/sonic-buildimage-resolute/src/sonic-sairedis`。

| 子模块 | 202605 lock | build 提交 | build parent |
|---|---|---|---|
| src/sonic-dash-ha | `dec02a5d` | `b336da3` | `07201f08` |
| src/sonic-sairedis | `cec72ecc` | `68da16e5` | `9fc3fb4d` |

- [x] **Step 1: 在 sonic-dash-ha 里 fetch 并确认 build 提交 parent**

Run:
```
cd ~/sonic-buildimage-resolute/src/sonic-dash-ha
git fetch origin
git log --oneline -1 b336da3
git rev-parse --short b336da3^
```
Expected: 最后打印 `07201f08`（build parent，非 202605 lock `dec02a5d`——这就是要 rebase 的原因）。
**Result:** `b336da3 build: drop swss-common git source from Cargo.lock (local vendor)`，parent=`07201f0`。在 resolute 分支，origin=sonic-net，fsck 干净。✅

- [x] **Step 2: 把 sonic-dash-ha 的 resolute 分支 rebase 到 202605 lock**

Run: `git rebase --onto dec02a5d 07201f08 resolute`
Expected: 要么干净 rebase（`Successfully rebased`，HEAD 是 `dec02a5d` 之上的新提交），要么 `Cargo.lock` 冲突（dash-ha build 提交动 Cargo.lock，为 `swss-common` local-vendor drop）。若冲突：编辑 `Cargo.lock` 保留 resolute 意图（drop `swss-common` git source），`git add Cargo.lock`，`git rebase --continue`。
**Result:** 干净 rebase，无冲突（`Successfully rebased and updated refs/heads/resolute`）。

- [x] **Step 3: 记录 sonic-dash-ha 新 build 提交 sha**

Run: `git rev-parse HEAD`
Expected: 40 字符完整 sha。**记下来**——这是 Task 3 Step 5 和 Task 5 用的 `<new-dash-ha-sha>`。验证：`git log --oneline dec02a5d..HEAD` → 1 个提交（rebase 后的 build 提交）。
**Result:** `<new-dash-ha-sha>` = `cd8f01083776ebf5ceca6185e01e9171d2be3e35`（1 提交在 dec02a5d 之上，build msg 保留）。**注**：此 sha 在 Task 4b 身份重写后变为 `1d45f96e38cb31c3d95c21ae37db8eb390601894`（amend+签名），Task 5/6 用后者。

- [x] **Step 4: 在 sonic-sairedis 里 fetch 并确认 build 提交 parent**

Run:
```
cd ~/sonic-buildimage-resolute/src/sonic-sairedis
git fetch origin
git log --oneline -1 68da16e5
git rev-parse --short 68da16e5^
```
Expected: 最后打印 `9fc3fb4d`（build parent，非 202605 lock `cec72ecc`）。
**Result:** `68da16e5 build: c++17 + implicit includes + SWIG -Wno-error + bump SAI (Doxyfile AUTOLINK)`，parent=`9fc3fb4d`，fsck 干净（memory 提示的 object corruption 已修）。✅

- [x] **Step 5: 把 sonic-sairedis 的 resolute 分支 rebase 到 202605 lock**

Run: `git rebase --onto cec72ecc 9fc3fb4d resolute`
Expected: 干净 rebase，或 SAI/Doxyfile 冲突（sairedis build 提交动 `AUTOLINK` + SWIG flags）。若冲突：保留 resolute 意图（SWIG `-Wno-error`、SAI bump），`git add`，`git rebase --continue`。
**Result:** 干净 rebase，无冲突。

- [x] **Step 6: 记录 sonic-sairedis 新 build 提交 sha**

Run: `git rev-parse HEAD`
Expected: 完整 sha。**记下来**——这是 Task 3 Step 5 和 Task 5 的 `<new-sairedis-sha>`。验证：`git log --oneline cec72ecc..HEAD` → 1 个提交。
**Result:** `<new-sairedis-sha>` = `06f83ac581af90cac43442166cc38aecc284945f`（1 提交在 cec72ecc 之上）。**注**：Task 4b 身份重写后变为 `e3109136f08355ec5dd046460d983645b21b344f`，Task 5/6 用后者。

---

## Task 3: 超仓库构建分支——filter-repo + rebase + 重命名（§4）

在 `~/sonic-buildimage-resolute` 上就地。清除 superpowers 文档，rebase 到 `9c84048a4`，重命名为 `202605_resolute`。

**Files:** `~/sonic-buildimage-resolute`（整个 repo 历史），`.gitmodules`（Task 6）。

- [x] **Step 1: 清除所有历史里的 superpowers 文档（就地，--force）**

Run:
```
cd ~/sonic-buildimage-resolute
git filter-repo --force --path docs/superpowers --invert-paths
```
Expected: filter-repo 报告改写的提交数，`origin` 被删。约 5 个 docs 提交被剪枝。
**Result:** 22750 提交解析重写，origin 删除，resolute tip `2d1fc1b4f` → `a4cf9d8c3`（docs/superpowers 含 specs/plans 等多文件历史）。✅

- [x] **Step 2: 验证清除成功**

Run: `git ls-tree -r resolute --name-only | grep -i superpowers`
Expected: 空（无 superpowers 路径残留）。
**Result:** 空（grep exit 1）。✅

- [x] **Step 3: 重加远端并 fetch sonic-net 202605**

Run:
```
git remote add sonic-net https://github.com/sonic-net/sonic-buildimage.git
git remote add canonical  git@github.com:canonical/sonic-buildimage.git
git fetch sonic-net
```
Expected: `sonic-net/202605` fetch 到，指向 `9c84048a4`。
**Result:** remotes 加好，`sonic-net/202605 = 9c84048a4 [submodule] Update sonic-dash-ha`。✅（子模块递归 fetch 的非致命警告忽略）

- [x] **Step 4: 开始 rebase 到最新 202605**

Run: `git rebase --onto sonic-net/202605 77cfa809d resolute`
Expected: 重放过滤后的 resolute 提交。会在第一个 gitlink 冲突处停下。
**Result:** **关键发现**：`77cfa809d` 不是 merge-base，真实 merge-base 是 `437419c79`，故 `77cfa809d..resolute` = 11458 提交。git 自动 skip ~11364 个上游已应用提交，应用 94 个迁移提交。停在 `cc876215c "bump resolute submodules"` 的 gitlink 冲突（src/sonic-dash-ha、src/sonic-sairedis UU）。前 92 个提交干净应用。

- [x] **Step 5: 解决 sonic-dash-ha gitlink 冲突**

rebase 在 `src/sonic-dash-ha` 冲突停下时：
Run: `git update-index --cacheinfo 160000 <new-dash-ha-sha> src/sonic-dash-ha && git add src/sonic-dash-ha && git rebase --continue`
（`<new-dash-ha-sha>` = Task 2 Step 3 记的完整 sha。`160000` 是 gitlink mode。**不要**用 `git checkout --theirs`——那保留 rebase 前的陈旧指针。）

Expected: 冲突解决，rebase 继续。可能在 sonic-sairedis 或 dhcpmon 再停。
**Result:** `git update-index --cacheinfo 160000 cd8f01083776ebf5ceca6185e01e9171d2be3e35 src/sonic-dash-ha`，UU 清空，continue。

- [x] **Step 6: 解决 sonic-sairedis gitlink 冲突**

rebase 在 `src/sonic-sairedis` 停下时：
Run: `git update-index --cacheinfo 160000 <new-sairedis-sha> src/sonic-sairedis && git add src/sonic-sairedis && git rebase --continue`
（`<new-sairedis-sha>` 来自 Task 2 Step 6。）

Expected: 冲突解决，rebase 继续。
**Result:** `git update-index --cacheinfo 160000 06f83ac581af90cac43442166cc38aecc284945f src/sonic-sairedis`，continue → `Successfully rebased`。

- [x] **Step 7: 解决 dhcpmon gitlink 冲突（若出现）**

rebase 在 `src/dhcpmon` 停下时（无 resolute build 提交——取 202605 的指针）：
Run: `git checkout --theirs src/dhcpmon && git add src/dhcpmon && git rebase --continue`
Expected: 冲突解决，rebase 完成 `Successfully rebased`。
**Result:** 未出现 dhcpmon 冲突，rebase 直接完成。验证 14 gitlink 全匹配 Task 5 表（dash-ha=cd8f010、sairedis=06f83ac5、其余 12 个原 sha）。

- [x] **Step 8: 验证 rebase 结果**

Run:
```
git merge-base HEAD sonic-net/202605
git log --oneline sonic-net/202605..HEAD | wc -l
```
Expected: 第一条打印 `9c84048a4...`（完整 sha）；第二条约 66（过滤后的 build 提交，docs 已剪枝）。
**Result:** merge-base=`9c84048a4`，commit 数=**94**（计划预期 ~66 偏低；含 27 个上游 author 的 `[submodule] Update` bump 提交被重放——gitlink sha patch 在新 base 无等价物不 skip，正常）。tip=`02aa417d3`。

- [x] **Step 9: 重命名分支为 202605_resolute**

Run: `git branch -m resolute 202605_resolute`
Expected: 无输出。验证：`git branch --show-current` → `202605_resolute`。
**Result:** 重命名 OK。✅

- [x] **Step 10: 推送超仓库构建分支到 canonical**

Run: `git push canonical 202605_resolute`
Expected: `* [new branch]`——`canonical/sonic-buildimage` 上分支创建。
**Result:** `* [new branch] 202605_resolute -> 202605_resolute`。✅ **注**：此为身份重写前的首次推送（sha `02aa417d3`），后被身份重写版 force-push 覆盖。

- [x] **Step 11: 在 GitHub 验证**

Run: `gh api repos/canonical/sonic-buildimage/branches/202605_resolute --jq '.commit.sha'`
Expected: sha 与本地 `git rev-parse 202605_resolute` 一致。
**Result:** GitHub sha = 本地 `02aa417d35...`。✅（身份重写后最终 sha = `c7b71c085b5e4452252f2f78fb03cdf9df167f9e`，见 Task 3b/6）

---

## Task 3b: 身份重写 + GPG 签名（用户追加，非原计划）

执行中发现两仓库 local `user.*` config 误设为 `@local`（迁移机器时忘配置，AI 随便写的）：构建仓库 `SONiC Build <sonic-build@local>`，文档仓库 `sheldon-qi <sheldon-qi@local>`。用户要求：所有 `@local` author/committer → `Sheldon Qi <sheldon.qi@canonical.com>`，sheldon 的迁移提交都重新 GPG 签名。GPG key `521ED6CE84B5C2B2BAF7AAEA90E19370EEEF6873`（UID `sheldon.qi@canonical.com`）。

**Files:** 全部提交的 author/committer 身份（不改树/gitlink/提交内容）。

- [x] **Step 1: 删两仓库 local user.* config（全局 Sheldon Qi 生效）**
Run: `git config --unset user.name; git config --unset user.email`（两仓库）。
**Result:** 两仓库 now `Sheldon Qi <sheldon.qi@canonical.com>`，`commit.gpgsign=true`。

- [x] **Step 2: filter-repo --mailmap 重写身份**
Run: 写 mailmap（`sheldon-qi@local` + `sonic-build@local` → `Sheldon Qi <sheldon.qi@canonical.com>`），`git filter-repo --force --mailmap /tmp/resolute-id.mailmap`。
**Result:** 构建仓库 44629 提交解析，tip `02aa417d3` → `6cbeb89356`。0 `@local` 残留，committer 全 `Sheldon Qi`，author 保留 14 上游贡献者。14 gitlink 不变（验证 identical）。

- [x] **Step 3: GPG 签名 94 迁移提交**
Run: `GIT_SEQUENCE_EDITOR=true GIT_EDITOR=true git rebase sonic-net/202605 --exec 'git commit --amend --no-edit --allow-empty -S --quiet'`。
**Result:** 首次因空提交（`7c13fdbd9 "chore: start resolute migration branch"`）报 "No changes" 停下；加 `--allow-empty` 后 188 步（94 pick+94 exec）完成，94 提交全 `G`，tip `6cbeb89356` → `2f429e5ee1`。ff YES，gitlinks 不变。

- [x] **Step 4: force-push 覆盖**
Run: `git push canonical 202605_resolute --force-with-lease`。
**Result:** `02aa417d35...2f429e5ee1 (forced update)`，GitHub `verified=true`。✅（Task 6 改 .gitmodules 后最终 tip `c7b71c085b`）

---

## Task 4: 超仓库文档分支——filter-repo + rebase + 重命名（§5）

在 `~/sonic-buildimage`（分支 `202605-wip`）上就地。提交 6 个新双语文档，清除 2 个旧单语文档，rebase，重命名为 `202605_resolute_doc`。

**Files:** `~/sonic-buildimage/.gitignore`，`docs/superpowers/` 下 6 个新文档。

- [x] **Step 1: 添加 6 个新双语文档 + gitignore 条目（在 202605-wip）**

Run:
```
cd ~/sonic-buildimage
printf '\n# Generated/personal — not committed\nsonic.code-workspace\n*.pptx\n*.pptx.md\n' >> .gitignore
git add docs/superpowers/resolute-migration-code-review-en.md docs/superpowers/resolute-migration-code-review-zh.md docs/superpowers/resolute-modification-catalog-en.md docs/superpowers/resolute-modification-catalog-zh.md docs/superpowers/resolute-vs-migration-report-en.md docs/superpowers/resolute-vs-migration-report-zh.md .gitignore
git commit -m "docs: add resolute migration docs bilingual"
```
Expected: commit 创建。验证 6 个 `-en.md`/`-zh.md` 和 `.gitignore` 已 stage；`.pptx`/`.pptx.md`/`sonic.code-workspace` 未 stage。
**Result:** commit 创建，7 files / 1643 insertions（6 docs + .gitignore），pptx/workspace 已 ignore。✅

- [x] **Step 2: 打安全 tag**

Run: `git tag pre-filter-docs 202605-wip`
Expected: 无输出。
**Result:** `pre-filter-docs = aaf946bfb8c75f54355c4c681aec4f762a2f3cb7`。同样追加 bundle 备份 `~/doc-pre-filter-backup.bundle`（63M）作真回退点。

- [x] **Step 3: 清除所有历史里的 2 个旧单语文档（就地，--force）**

Run:
```
git filter-repo --force \
  --path docs/superpowers/resolute-migration-code-review.md \
  --path docs/superpowers/resolute-vs-migration-report.md \
  --invert-paths
```
Expected: filter-repo 改写历史，从每个提交移除这 2 个路径，剪枝变空提交，删除 `origin`。
**Result:** 22673 提交解析重写，origin 删除，3 个 docs-only 提交剪枝（12294→12291），tip `aaf946bfb` → `4480fc4ce`。✅

- [x] **Step 4: 验证清除**

Run: `git ls-tree -r 202605-wip --name-only | grep -E 'resolute-migration-code-review\.md$|resolute-vs-migration-report\.md$'`
Expected: 空（2 个旧单语路径消失）。6 个新双语文件（带 `-en`/`-zh` 后缀）保留——验证：`git ls-tree -r 202605-wip --name-only | grep superpowers` 显示 6 个新文件。
**Result:** 2 旧路径消失（grep exit 1）；6 双语 docs + 4 plans + 4 specs 保留。✅

- [x] **Step 5: 重加远端 + 重命名分支 + rebase 到最新 202605**

Run:
```
git remote add sonic-net https://github.com/sonic-net/sonic-buildimage.git
git remote add canonical  git@github.com:canonical/sonic-buildimage.git
git fetch sonic-net
git branch -m 202605-wip 202605_resolute_doc
git rebase --onto sonic-net/202605 77cfa809d 202605_resolute_doc
```
Expected: rebase 完成，~0 冲突（文档不碰 submodule 指针或 build 文件）。
**Result:** rebase 完成（37 提交，merge-base=`9c84048a4`），无冲突，tip `5d2d41a553`。ff YES。

- [x] **Step 6: 验证 rebase 结果**

Run: `git merge-base HEAD sonic-net/202605`
Expected: `9c84048a4...`（完整 sha）。
**Result:** `9c84048a4240ea5d358f74b0821d2d51bba9a3b5`。✅

- [x] **Step 7: 推送超仓库文档分支到 canonical**

Run: `git push canonical 202605_resolute_doc`
Expected: `* [new branch]`。
**Result:** 身份重写后推送（见 Task 4b），`* [new branch] 202605_resolute_doc`。

- [x] **Step 8: 在 GitHub 验证**

Run: `gh api repos/canonical/sonic-buildimage/branches/202605_resolute_doc --jq '.commit.sha'`
Expected: sha 与本地 `git rev-parse 202605_resolute_doc` 一致。
**Result:** GitHub sha = 本地 `ec99572bc82c78972dfbfaa7bafb8d435c7b6253`，`verified=true`。✅

---

## Task 4b: 文档仓库身份重写 + GPG 签名（用户追加）

同 Task 3b。文档仓库 local config `sheldon-qi <sheldon-qi@local>`，37 迁移提交（10 author + 37 committer 是 `@local`），全未签名。

- [x] **Step 1: 删 local config + mailmap + 签名 rebase + 推送**
Run: 同 Task 3b 流程（mailmap 同文件，rebase `--exec` 签名 37 提交）。
**Result:** tip `5d2d41a553` → mailmap `beb43c9c3a` → 签名 `ec99572bc`。0 `@local`，37 提交全 `G`，ff YES，`git push canonical 202605_resolute_doc`（新分支，非 force），GitHub `verified=true`。✅

---

## Task 5: 推送全部 14 个子模块的 202605_resolute 分支（§6.2）

对 14 个子模块的每一个：加 `canonical` 远端，把 build 提交（dash-ha/sairedis 用 rebase 后的 sha，其余 12 个用原 sha）作为新 `202605_resolute` 分支推。无 `--force`（新分支）。

**Files:** 无（各子模块的远端 ref）。

**子模块 → repo → build 提交映射：**

| 子模块路径 | canonical repo | 要推的 build 提交 |
|---|---|---|
| src/sonic-swss | sonic-swss | `6d3a46bb` |
| src/sonic-sairedis | sonic-sairedis | `<new-sairedis-sha>`（Task 2 Step 6） |
| src/sonic-swss-common | sonic-swss-common | `baf0b19` |
| src/sonic-gnmi | sonic-gnmi | `c8f96ff` |
| src/sonic-mgmt-framework | sonic-mgmt-framework | `fda49ff` |
| src/sonic-linux-kernel | sonic-linux-kernel | `c54d5e3` |
| src/sonic-mgmt-common | sonic-mgmt-common | `47995eb` |
| platform/vpp | sonic-platform-vpp | `fe8c727` |
| src/dhcprelay | sonic-dhcp-relay | `d620ecc` |
| src/sonic-bmp | sonic-bmp | `c11289b` |
| src/sonic-dash-ha | sonic-dash-ha | `<new-dash-ha-sha>`（Task 2 Step 3） |
| src/sonic-dash-api | sonic-dash-api | `43c676b` |
| src/sonic-stp | sonic-stp | `416491c` |
| src/wpasupplicant/sonic-wpa-supplicant | sonic-wpa-supplicant | `7f39eb03f` |

> **执行偏差（Task 4b 身份重写）**：表中 build 提交 sha 在身份重写 + GPG 签名后全部改变。下表为**最终签名后 sha**（实际推送用）：

| 子模块路径 | canonical repo | 原 build sha | 签名后 build sha（实际推） |
|---|---|---|---|
| src/sonic-swss | sonic-swss | `6d3a46bb` | `c7b350baddbed0872ea91e6607ad981138ceec15` |
| src/sonic-sairedis | sonic-sairedis | `06f83ac5` | `e3109136f08355ec5dd046460d983645b21b344f` |
| src/sonic-swss-common | sonic-swss-common | `baf0b19` | `21761856a70c8c2fdd9483630ab4de0676d968ad` |
| src/sonic-gnmi | sonic-gnmi | `c8f96ff` | `ac66fd09d31ae0bf1bfa3730c17d89c37f771bfc` |
| src/sonic-mgmt-framework | sonic-mgmt-framework | `fda49ff` | `e24ccb8d50e3075bf033b15a7896ece42e9644aa` |
| src/sonic-linux-kernel | sonic-linux-kernel | `c54d5e3` | `a5b3fcbfe065cd36051828ed69877fa582937b75` |
| src/sonic-mgmt-common | sonic-mgmt-common | `47995eb` | `41ecda4d88e2125e1eec1a1584e64d541ee465e3` |
| platform/vpp | sonic-platform-vpp | `fe8c727` | `1b4e0c4707b5717499792f7979451875c7f1af82` |
| src/dhcprelay | sonic-dhcp-relay | `d620ecc` | `db2e6126b2e769f2d2edb5a7b2c37c1db9fc8470` |
| src/sonic-bmp | sonic-bmp | `c11289b` | `c290326832a9f3c570fc44343abd2755bd7477c7` |
| src/sonic-dash-ha | sonic-dash-ha | `cd8f010` | `1d45f96e38cb31c3d95c21ae37db8eb390601894` |
| src/sonic-dash-api | sonic-dash-api | `43c676b` | `1bf398db578afd5c88588eca5af45381baa1b860` |
| src/sonic-stp | sonic-stp | `416491c` | `17fbe1544cc5fa09eff4209e882b7daba8e8911b` |
| src/wpasupplicant/sonic-wpa-supplicant | sonic-wpa-supplicant | `7f39eb03f` | `5badeedf2fb55ef0eacfa9b56fbbd0cb3ff6d293` |

- [x] **Step 1: 给 14 个子模块各加 canonical 远端**

Run（在 `~/sonic-buildimage-resolute`）：
```
cd ~/sonic-buildimage-resolute
for pair in \
  "src/sonic-swss:sonic-swss" \
  "src/sonic-sairedis:sonic-sairedis" \
  "src/sonic-swss-common:sonic-swss-common" \
  "src/sonic-gnmi:sonic-gnmi" \
  "src/sonic-mgmt-framework:sonic-mgmt-framework" \
  "src/sonic-linux-kernel:sonic-linux-kernel" \
  "src/sonic-mgmt-common:sonic-mgmt-common" \
  "platform/vpp:sonic-platform-vpp" \
  "src/dhcprelay:sonic-dhcp-relay" \
  "src/sonic-bmp:sonic-bmp" \
  "src/sonic-dash-ha:sonic-dash-ha" \
  "src/sonic-dash-api:sonic-dash-api" \
  "src/sonic-stp:sonic-stp" \
  "src/wpasupplicant/sonic-wpa-supplicant:sonic-wpa-supplicant"; do
  sm="${pair%%:*}"; repo="${pair##*:}"
  git -C "$sm" remote add canonical "git@github.com:canonical/${repo}.git" 2>/dev/null || true
done
```
Expected: 无输出（远端已加；`|| true` 跳过已存在的）。
**Result:** 14 canonical 远端已加。✅

- [x] **Step 2: 推送 7 个已存在 repo 的子模块（非 rebase）**

Run:
```
git -C src/sonic-swss         push canonical 6d3a46bb:refs/heads/202605_resolute
git -C src/sonic-swss-common  push canonical baf0b19:refs/heads/202605_resolute
git -C src/sonic-gnmi         push canonical c8f96ff:refs/heads/202605_resolute
git -C src/sonic-mgmt-framework push canonical fda49ff:refs/heads/202605_resolute
git -C src/sonic-linux-kernel push canonical c54d5e3:refs/heads/202605_resolute
git -C src/sonic-mgmt-common  push canonical 47995eb:refs/heads/202605_resolute
```
Expected: 每个打印 `* [new branch]`。
**Result:** 改用签名后 sha 推送（见上表），6 个全 `* [new branch]`。（sonic-linux-kernel 签名前为 detached HEAD，workflow agent 用 `git checkout -B resolute <sha>` 切到分支）

- [x] **Step 3: 推送 2 个 rebase 过的子模块**

Run:
```
git -C src/sonic-sairedis push canonical <new-sairedis-sha>:refs/heads/202605_resolute
git -C src/sonic-dash-ha  push canonical <new-dash-ha-sha>:refs/heads/202605_resolute
```
（把 `<new-sairedis-sha>` 和 `<new-dash-ha-sha>` 换成 Task 2 记的完整 sha。）
Expected: 每个打印 `* [new branch]`。
**Result:** 用签名后 sha（sairedis `e3109136f0`、dash-ha `1d45f96e38`），全 `* [new branch]`。

- [x] **Step 4: 推送 7 个 fork（原 404）的子模块**

Run:
```
git -C platform/vpp                              push canonical fe8c727:refs/heads/202605_resolute
git -C src/dhcprelay                             push canonical d620ecc:refs/heads/202605_resolute
git -C src/sonic-bmp                             push canonical c11289b:refs/heads/202605_resolute
git -C src/sonic-dash-api                        push canonical 43c676b:refs/heads/202605_resolute
git -C src/sonic-stp                             push canonical 416491c:refs/heads/202605_resolute
git -C src/wpasupplicant/sonic-wpa-supplicant    push canonical 7f39eb03f:refs/heads/202605_resolute
```
（dash-ha 在 Task 1 fork，但用其 rebase 后的 sha 在上面 Step 3 推。）
Expected: 每个打印 `* [new branch]`。
**Result:** 用签名后 sha，全 `* [new branch]`。（sonic-dash-api 签名前 detached，同样 `checkout -B resolute`）

- [x] **Step 5: 验证 14 个子模块分支都在 canonical 上**

Run:
```
for repo in sonic-swss sonic-sairedis sonic-swss-common sonic-gnmi sonic-mgmt-framework sonic-linux-kernel sonic-mgmt-common sonic-platform-vpp sonic-dhcp-relay sonic-bmp sonic-dash-ha sonic-dash-api sonic-stp sonic-wpa-supplicant; do
  sha=$(gh api repos/canonical/$repo/branches/202605_resolute --jq '.commit.sha' 2>/dev/null | cut -c1-10)
  echo "$repo 202605_resolute=$sha"
done
```
Expected: 14 行，每行 sha 非空。
**Result:** 14 个全返回非空 sha，且 `verified=true`。✅

---

## Task 6: 改写 .gitmodules + 对齐子模块工作目录（§7）

在 `~/sonic-buildimage-resolute`（已在 `202605_resolute`）上。把 14 个子模块指向 `canonical/`，对齐工作目录，提交，重推。

**Files:** `~/sonic-buildimage-resolute/.gitmodules`。

**14 个子模块路径 → 新 canonical URL：**
```
src/sonic-swss                            → git@github.com:canonical/sonic-swss.git
src/sonic-sairedis                        → git@github.com:canonical/sonic-sairedis.git
src/sonic-swss-common                     → git@github.com:canonical/sonic-swss-common.git
src/sonic-gnmi                            → git@github.com:canonical/sonic-gnmi.git
src/sonic-mgmt-framework                  → git@github.com:canonical/sonic-mgmt-framework.git
src/sonic-linux-kernel                    → git@github.com:canonical/sonic-linux-kernel.git
src/sonic-mgmt-common                     → git@github.com:canonical/sonic-mgmt-common.git
platform/vpp                              → git@github.com:canonical/sonic-platform-vpp.git
src/dhcprelay                             → git@github.com:canonical/sonic-dhcp-relay.git
src/sonic-bmp                             → git@github.com:canonical/sonic-bmp.git
src/sonic-dash-ha                         → git@github.com:canonical/sonic-dash-ha.git
src/sonic-dash-api                        → git@github.com:canonical/sonic-dash-api.git
src/sonic-stp                             → git@github.com:canonical/sonic-stp.git
src/wpasupplicant/sonic-wpa-supplicant    → git@github.com:canonical/sonic-wpa-supplicant.git
```

- [x] **Step 1: 改写 .gitmodules URL**

Run:
```
cd ~/sonic-buildimage-resolute
for pair in \
  "src/sonic-swss:sonic-swss" \
  "src/sonic-sairedis:sonic-sairedis" \
  "src/sonic-swss-common:sonic-swss-common" \
  "src/sonic-gnmi:sonic-gnmi" \
  "src/sonic-mgmt-framework:sonic-mgmt-framework" \
  "src/sonic-linux-kernel:sonic-linux-kernel" \
  "src/sonic-mgmt-common:sonic-mgmt-common" \
  "platform/vpp:sonic-platform-vpp" \
  "src/dhcprelay:sonic-dhcp-relay" \
  "src/sonic-bmp:sonic-bmp" \
  "src/sonic-dash-ha:sonic-dash-ha" \
  "src/sonic-dash-api:sonic-dash-api" \
  "src/sonic-stp:sonic-stp" \
  "src/wpasupplicant/sonic-wpa-supplicant:sonic-wpa-supplicant"; do
  sm="${pair%%:*}"; repo="${pair##*:}"
  git config -f .gitmodules "submodule.${sm}.url" "git@github.com:canonical/${repo}.git"
done
```
Expected: 无输出。`.gitmodules` 现有 14 个 canonical URL。
**Result:** 14 canonical URL，`grep -c 'github.com:canonical' .gitmodules` = 14。✅

- [x] **Step 2: 把 .gitmodules 同步进 .git/config**

Run: `git submodule sync`
Expected: 无输出（传播 URL）。
**Result:** sync 完成。✅

- [x] **Step 3: 对齐子模块工作目录到 gitlink**

Run: `git submodule update --recursive --no-fetch`
Expected: 子模块检出至超仓库 gitlink 记录的 commit。对 `src/sonic-dash-ha` 和 `src/sonic-sairedis`，检出 Task 2 的新 rebase build commit。其余 12 个若已在 build commit 则 no-op。
**Result:** **偏差**：因 Task 4b 子模块 build-commit 身份重写改变了 sha，原计划 `submodule update` 不够。改用 `git update-index --cacheinfo 160000 <new-signed-sha> <path>` 直接更新 14 个 gitlink 到签名后 sha（见 Task 5 表）。这样超仓库 gitlink 指向 canonical 上推送的新签名子模块 commit。

- [x] **Step 4: 验证 git status 干净**

Run: `git status --short`
Expected: 只有 `.gitmodules` 显示 modified。无 dirty 子模块。若子模块显示 dirty，重跑 Step 3；若仍 dirty，手动 `git -C <子模块> checkout <Task 5 映射里的 build-commit-sha>`。
**Result:** staged 15 files（14 gitlink + .gitmodules），其余 resolute 子模块已对齐（commit 后 status 干净）。✅

- [x] **Step 5: 提交 .gitmodules 改动**

Run:
```
git add .gitmodules
git commit -m "build: point submodules at canonical resolute branches"
```
Expected: commit 创建。
**Result:** `git commit -S -m "build: point submodules at canonical resolute branches (signed)"`，15 files / 32 insertions / 24 deletions，tip `c7b71c085b`，GPG G，author/committer=`Sheldon Qi`。ff YES。

- [x] **Step 6: 重推超仓库构建分支（改写后的 tip）**

Run: `git push canonical 202605_resolute --force-with-lease`
Expected: `+ <sha>...202605_resolute -> 202605_resolute (forced update)`——`.gitmodules` 提交现在是 canonical 上的 tip。
**Result:** `2f429e5ee..c7b71c085 202605_resolute -> 202605_resolute (forced update)`。✅

- [x] **Step 7: 验证 canonical 上的 .gitmodules**

Run: `gh api repos/canonical/sonic-buildimage/contents/.gitmodules?ref=202605_resolute --jq '.content' | base64 -d | grep -c 'github.com:canonical'`
Expected: `14`（14 个 resolute 子模块都指向 canonical）。
**Result:** `14`。✅ GitHub sha = 本地 `c7b71c085b5e4452252f2f78fb03cdf9df167f9e`，`verified=true`。

---

## Task 7: 最终验证（§10）

确认整个上传成功，原仓库已对齐。

**Files:** 无。

- [x] **Step 1: 超仓库构建分支无 superpowers 文档**

Run: `git -C ~/sonic-buildimage-resolute ls-tree -r 202605_resolute --name-only | grep -i superpowers`
Expected: 空。
**Result:** 空。✅

- [x] **Step 2: 超仓库构建坐在最新 202605**

Run: `git -C ~/sonic-buildimage-resolute merge-base 202605_resolute sonic-net/202605`
Expected: `9c84048a4`（完整 sha）。
**Result:** merge-base = `eeb4bff75c6a02ac7aa4b3c6eea9d2653e066ea5`（执行时上游又推提交，比计划写时 `9c84048a4` 更新）。`git merge-base --is-ancestor sonic-net/202605 202605_resolute` → **ff YES**（关键约束满足）。✅

- [x] **Step 3: 超仓库文档分支有 6 个双语文档，无 .pptx**

Run: `git -C ~/sonic-buildimage ls-tree -r 202605_resolute_doc --name-only | grep superpowers`
Expected: 6 行（3 主题 × `-en.md`/`-zh.md`），无 `.pptx`/`.pptx.md`。
**Result:** 6 双语 docs（3 主题 × en/zh）+ 4 plans + 4 specs；pptx/pptx.md = 0。✅

- [x] **Step 4: .gitmodules 指向 canonical 的有 14 个**

Run: `grep -c 'github.com:canonical' ~/sonic-buildimage-resolute/.gitmodules`
Expected: `14`。
**Result:** `14`。✅

- [x] **Step 5: 全部 14 个子模块分支在 canonical 上**

（复用 Task 5 Step 5 的循环——14 个都应返回非空 sha。）
**Result:** 14 个全返回非空签名 sha + `verified=true`。✅（见 Task 5 签名后 sha 表）

- [x] **Step 6: 原仓库在正确分支**

Run:
```
git -C ~/sonic-buildimage-resolute branch --show-current
git -C ~/sonic-buildimage branch --show-current
```
Expected:
```
202605_resolute
202605_resolute_doc
```
**Result:** `202605_resolute` / `202605_resolute_doc`。✅

- [x] **Step 7: 构建仓库 git status 干净（无 dirty 子模块）**

Run: `git -C ~/sonic-buildimage-resolute status --short`
Expected: 空（Task 6 Step 3 后所有子模块对齐 gitlink）。
**Result:** 14 resolute 子模块全对齐（clean）。✅

- [x] **Step 8: 两分支在 GitHub 可见**

打开：
- `https://github.com/canonical/sonic-buildimage/tree/202605_resolute`
- `https://github.com/canonical/sonic-buildimage/tree/202605_resolute_doc`

Expected: 两分支都渲染，显示最新提交。
**Result:** 两分支 GitHub 可见：`202605_resolute` = `c7b71c085b`、`202605_resolute_doc` = `ec99572bc8`，均 `verified=true`。✅

- [x] **Step 9: 记录最终状态到 memory**

更新 memory note `sonic-resolute-vs-build-success.md`（或新建 `sonic-resolute-canonical-upload.md`），记录：canonical 上的 2 个超仓库分支名、14 个子模块 `202605_resolute` 分支、2 个 rebase 过的子模块 sha，以及原仓库现停在 `202605_resolute` / `202605_resolute_doc` 的事实。跨 session 保留。
**Result:** 新建 memory note `sonic-resolute-canonical-upload.md`（在 claude memory 目录 `~/.claude/projects/.../memory/`），记录 2 超仓库分支 + 14 子模块签名 sha + ff 约束 + bundle 备份位置。MEMORY.md 索引已加。✅
