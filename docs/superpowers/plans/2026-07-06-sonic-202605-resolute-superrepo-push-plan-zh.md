# SONiC 202605 Resolute — 超仓库 + 子模块上传计划 (ZH)

> **For agentic workers:** REQUIRED SUB-SKILL: 使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务执行本计划。步骤用 checkbox（`- [ ]`）语法跟踪。

**Goal:** 把 resolute 迁移工作上传到 `canonical/`——超仓库 build/docs 分支 + 14 个子模块分支——供团队 clone 并复现 resolute `vs` 构建。

**Architecture:** 在两个原仓库（`~/sonic-buildimage-resolute`、`~/sonic-buildimage`）上就地用 `git filter-repo --force` 清除 superpowers 文档，再 rebase 到 sonic-net 最新 `202605`（`9c84048a4`），重命名分支为 `202605_resolute` / `202605_resolute_doc`，推到 `canonical/`。14 个子模块的 `build:` 提交作为新 `202605_resolute` 分支推送（2 个先 rebase 到 202605 gitlink lock；7 个 canonical 已存在 repo 直推；7 个缺失 repo 先从 sonic-net fork）。最后改写 `.gitmodules` 把 14 个子模块指向 canonical。

**Tech Stack:** git, git-filter-repo, gh CLI（已认证为 `xdqi`，canonical org member，有建 repo 权限）。

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

- [ ] **Step 1: 确认 git-filter-repo 已装**

Run: `git filter-repo --version`
Expected: 打印版本（如 `2.47.0`）。若缺：`sudo apt install git-filter-repo`（有免密 sudo）。

- [ ] **Step 2: 确认 gh 已认证到 canonical**

Run: `gh auth status`
Expected: `✓ Logged in to github.com account xdqi`，token scopes 含 `repo` 和 `read:org`。

- [ ] **Step 3: 确认两原仓库在预期分支**

Run: `git -C ~/sonic-buildimage-resolute branch --show-current && git -C ~/sonic-buildimage branch --show-current`
Expected:
```
resolute
202605-wip
```

- [ ] **Step 4: 确认 resolute 分支 tip 是 `2d1fc1b4f`（boost 1.83 baseline）**

Run: `git -C ~/sonic-buildimage-resolute log --oneline -1 resolute`
Expected: `2d1fc1b4f build: drop boost 1.88 adaptation, revert to 1.83 baseline`

- [ ] **Step 5: 确认 sonic-net 202605 HEAD 是 `9c84048a4`**

Run: `git -C ~/sonic-buildimage-resolute ls-remote https://github.com/sonic-net/sonic-buildimage.git refs/heads/202605`
Expected: 一行以 `9c84048a4` 开头（前 10 字符）。

- [ ] **Step 6: 确认构建仓库无未提交改动阻塞改写**

Run: `git -C ~/sonic-buildimage-resolute status --short sonic-slave-resolute/Dockerfile.j2`
Expected: 空（boost 1.83 改动已在 `2d1fc1b4f` 提交）。

- [ ] **Step 7: 在构建仓库打安全 tag**

Run: `git -C ~/sonic-buildimage-resolute tag pre-filter-resolute resolute`
Expected: 无输出。验证：`git -C ~/sonic-buildimage-resolute rev-parse pre-filter-resolute` → `2d1fc1b4f` 的完整 sha。

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

- [ ] **Step 1: 先 fork 一个作 sanity check（按 R5）**

Run: `gh repo fork sonic-net/sonic-bmp --org canonical --remote=false`
Expected: 类似 `Created fork canonical/sonic-bmp`。若权限报错，STOP——你无 org fork 权限；请 canonical owner 先 fork 这 7 个 repo 再继续。

- [ ] **Step 2: 验证 fork 存在**

Run: `gh api repos/canonical/sonic-bmp --jq '.full_name + " (fork=" + (.fork|tostring) + ")"'`
Expected: `canonical/sonic-bmp (fork=true)`。

- [ ] **Step 3: fork 其余 6 个**

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

- [ ] **Step 4: 验证 7 个 fork 都存在**

Run: `for r in sonic-platform-vpp sonic-dhcp-relay sonic-bmp sonic-dash-ha sonic-dash-api sonic-stp sonic-wpa-supplicant; do gh api repos/canonical/$r --jq '"$r fork=\(.fork)"' 2>/dev/null && echo "  $r OK" || echo "  $r MISSING"; done`
Expected: 每行 `<repo> fork=true` 然后 `OK`。

---

## Task 2: rebase 2 个 base 被上游 bump 的子模块（§6.1）

必须在 Task 3（超仓库 rebase）之前完成。`src/sonic-dash-ha` 和 `src/sonic-sairedis` 的 202605 gitlink lock 越过了其 build 提交的 parent——把 build 提交 rebase 到新 lock。

**Files:** 工作目录 `~/sonic-buildimage-resolute/src/sonic-dash-ha` 和 `~/sonic-buildimage-resolute/src/sonic-sairedis`。

| 子模块 | 202605 lock | build 提交 | build parent |
|---|---|---|---|
| src/sonic-dash-ha | `dec02a5d` | `b336da3` | `07201f08` |
| src/sonic-sairedis | `cec72ecc` | `68da16e5` | `9fc3fb4d` |

- [ ] **Step 1: 在 sonic-dash-ha 里 fetch 并确认 build 提交 parent**

Run:
```
cd ~/sonic-buildimage-resolute/src/sonic-dash-ha
git fetch origin
git log --oneline -1 b336da3
git rev-parse --short b336da3^
```
Expected: 最后打印 `07201f08`（build parent，非 202605 lock `dec02a5d`——这就是要 rebase 的原因）。

- [ ] **Step 2: 把 sonic-dash-ha 的 resolute 分支 rebase 到 202605 lock**

Run: `git rebase --onto dec02a5d 07201f08 resolute`
Expected: 要么干净 rebase（`Successfully rebased`，HEAD 是 `dec02a5d` 之上的新提交），要么 `Cargo.lock` 冲突（dash-ha build 提交动 Cargo.lock，为 `swss-common` local-vendor drop）。若冲突：编辑 `Cargo.lock` 保留 resolute 意图（drop `swss-common` git source），`git add Cargo.lock`，`git rebase --continue`。

- [ ] **Step 3: 记录 sonic-dash-ha 新 build 提交 sha**

Run: `git rev-parse HEAD`
Expected: 40 字符完整 sha。**记下来**——这是 Task 3 Step 5 和 Task 5 用的 `<new-dash-ha-sha>`。验证：`git log --oneline dec02a5d..HEAD` → 1 个提交（rebase 后的 build 提交）。

- [ ] **Step 4: 在 sonic-sairedis 里 fetch 并确认 build 提交 parent**

Run:
```
cd ~/sonic-buildimage-resolute/src/sonic-sairedis
git fetch origin
git log --oneline -1 68da16e5
git rev-parse --short 68da16e5^
```
Expected: 最后打印 `9fc3fb4d`（build parent，非 202605 lock `cec72ecc`）。

- [ ] **Step 5: 把 sonic-sairedis 的 resolute 分支 rebase 到 202605 lock**

Run: `git rebase --onto cec72ecc 9fc3fb4d resolute`
Expected: 干净 rebase，或 SAI/Doxyfile 冲突（sairedis build 提交动 `AUTOLINK` + SWIG flags）。若冲突：保留 resolute 意图（SWIG `-Wno-error`、SAI bump），`git add`，`git rebase --continue`。

- [ ] **Step 6: 记录 sonic-sairedis 新 build 提交 sha**

Run: `git rev-parse HEAD`
Expected: 完整 sha。**记下来**——这是 Task 3 Step 5 和 Task 5 的 `<new-sairedis-sha>`。验证：`git log --oneline cec72ecc..HEAD` → 1 个提交。

---

## Task 3: 超仓库构建分支——filter-repo + rebase + 重命名（§4）

在 `~/sonic-buildimage-resolute` 上就地。清除 superpowers 文档，rebase 到 `9c84048a4`，重命名为 `202605_resolute`。

**Files:** `~/sonic-buildimage-resolute`（整个 repo 历史），`.gitmodules`（Task 6）。

- [ ] **Step 1: 清除所有历史里的 superpowers 文档（就地，--force）**

Run:
```
cd ~/sonic-buildimage-resolute
git filter-repo --force --path docs/superpowers --invert-paths
```
Expected: filter-repo 报告改写的提交数，`origin` 被删。约 5 个 docs 提交被剪枝。

- [ ] **Step 2: 验证清除成功**

Run: `git ls-tree -r resolute --name-only | grep -i superpowers`
Expected: 空（无 superpowers 路径残留）。

- [ ] **Step 3: 重加远端并 fetch sonic-net 202605**

Run:
```
git remote add sonic-net https://github.com/sonic-net/sonic-buildimage.git
git remote add canonical  git@github.com:canonical/sonic-buildimage.git
git fetch sonic-net
```
Expected: `sonic-net/202605` fetch 到，指向 `9c84048a4`。

- [ ] **Step 4: 开始 rebase 到最新 202605**

Run: `git rebase --onto sonic-net/202605 77cfa809d resolute`
Expected: 重放过滤后的 resolute 提交。会在第一个 gitlink 冲突处停下。

- [ ] **Step 5: 解决 sonic-dash-ha gitlink 冲突**

rebase 在 `src/sonic-dash-ha` 冲突停下时：
Run: `git update-index --cacheinfo 160000 <new-dash-ha-sha> src/sonic-dash-ha && git add src/sonic-dash-ha && git rebase --continue`
（`<new-dash-ha-sha>` = Task 2 Step 3 记的完整 sha。`160000` 是 gitlink mode。**不要**用 `git checkout --theirs`——那保留 rebase 前的陈旧指针。）

Expected: 冲突解决，rebase 继续。可能在 sonic-sairedis 或 dhcpmon 再停。

- [ ] **Step 6: 解决 sonic-sairedis gitlink 冲突**

rebase 在 `src/sonic-sairedis` 停下时：
Run: `git update-index --cacheinfo 160000 <new-sairedis-sha> src/sonic-sairedis && git add src/sonic-sairedis && git rebase --continue`
（`<new-sairedis-sha>` 来自 Task 2 Step 6。）

Expected: 冲突解决，rebase 继续。

- [ ] **Step 7: 解决 dhcpmon gitlink 冲突（若出现）**

rebase 在 `src/dhcpmon` 停下时（无 resolute build 提交——取 202605 的指针）：
Run: `git checkout --theirs src/dhcpmon && git add src/dhcpmon && git rebase --continue`
Expected: 冲突解决，rebase 完成 `Successfully rebased`。

- [ ] **Step 8: 验证 rebase 结果**

Run:
```
git merge-base HEAD sonic-net/202605
git log --oneline sonic-net/202605..HEAD | wc -l
```
Expected: 第一条打印 `9c84048a4...`（完整 sha）；第二条约 66（过滤后的 build 提交，docs 已剪枝）。

- [ ] **Step 9: 重命名分支为 202605_resolute**

Run: `git branch -m resolute 202605_resolute`
Expected: 无输出。验证：`git branch --show-current` → `202605_resolute`。

- [ ] **Step 10: 推送超仓库构建分支到 canonical**

Run: `git push canonical 202605_resolute`
Expected: `* [new branch]`——`canonical/sonic-buildimage` 上分支创建。

- [ ] **Step 11: 在 GitHub 验证**

Run: `gh api repos/canonical/sonic-buildimage/branches/202605_resolute --jq '.commit.sha'`
Expected: sha 与本地 `git rev-parse 202605_resolute` 一致。

---

## Task 4: 超仓库文档分支——filter-repo + rebase + 重命名（§5）

在 `~/sonic-buildimage`（分支 `202605-wip`）上就地。提交 6 个新双语文档，清除 2 个旧单语文档，rebase，重命名为 `202605_resolute_doc`。

**Files:** `~/sonic-buildimage/.gitignore`，`docs/superpowers/` 下 6 个新文档。

- [ ] **Step 1: 添加 6 个新双语文档 + gitignore 条目（在 202605-wip）**

Run:
```
cd ~/sonic-buildimage
printf '\n# Generated/personal — not committed\nsonic.code-workspace\n*.pptx\n*.pptx.md\n' >> .gitignore
git add docs/superpowers/resolute-migration-code-review-en.md docs/superpowers/resolute-migration-code-review-zh.md docs/superpowers/resolute-modification-catalog-en.md docs/superpowers/resolute-modification-catalog-zh.md docs/superpowers/resolute-vs-migration-report-en.md docs/superpowers/resolute-vs-migration-report-zh.md .gitignore
git commit -m "docs: add resolute migration docs bilingual"
```
Expected: commit 创建。验证 6 个 `-en.md`/`-zh.md` 和 `.gitignore` 已 stage；`.pptx`/`.pptx.md`/`sonic.code-workspace` 未 stage。

- [ ] **Step 2: 打安全 tag**

Run: `git tag pre-filter-docs 202605-wip`
Expected: 无输出。

- [ ] **Step 3: 清除所有历史里的 2 个旧单语文档（就地，--force）**

Run:
```
git filter-repo --force \
  --path docs/superpowers/resolute-migration-code-review.md \
  --path docs/superpowers/resolute-vs-migration-report.md \
  --invert-paths
```
Expected: filter-repo 改写历史，从每个提交移除这 2 个路径，剪枝变空提交，删除 `origin`。

- [ ] **Step 4: 验证清除**

Run: `git ls-tree -r 202605-wip --name-only | grep -E 'resolute-migration-code-review\.md$|resolute-vs-migration-report\.md$'`
Expected: 空（2 个旧单语路径消失）。6 个新双语文件（带 `-en`/`-zh` 后缀）保留——验证：`git ls-tree -r 202605-wip --name-only | grep superpowers` 显示 6 个新文件。

- [ ] **Step 5: 重加远端 + 重命名分支 + rebase 到最新 202605**

Run:
```
git remote add sonic-net https://github.com/sonic-net/sonic-buildimage.git
git remote add canonical  git@github.com:canonical/sonic-buildimage.git
git fetch sonic-net
git branch -m 202605-wip 202605_resolute_doc
git rebase --onto sonic-net/202605 77cfa809d 202605_resolute_doc
```
Expected: rebase 完成，~0 冲突（文档不碰 submodule 指针或 build 文件）。

- [ ] **Step 6: 验证 rebase 结果**

Run: `git merge-base HEAD sonic-net/202605`
Expected: `9c84048a4...`（完整 sha）。

- [ ] **Step 7: 推送超仓库文档分支到 canonical**

Run: `git push canonical 202605_resolute_doc`
Expected: `* [new branch]`。

- [ ] **Step 8: 在 GitHub 验证**

Run: `gh api repos/canonical/sonic-buildimage/branches/202605_resolute_doc --jq '.commit.sha'`
Expected: sha 与本地 `git rev-parse 202605_resolute_doc` 一致。

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

- [ ] **Step 1: 给 14 个子模块各加 canonical 远端**

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

- [ ] **Step 2: 推送 7 个已存在 repo 的子模块（非 rebase）**

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

- [ ] **Step 3: 推送 2 个 rebase 过的子模块**

Run:
```
git -C src/sonic-sairedis push canonical <new-sairedis-sha>:refs/heads/202605_resolute
git -C src/sonic-dash-ha  push canonical <new-dash-ha-sha>:refs/heads/202605_resolute
```
（把 `<new-sairedis-sha>` 和 `<new-dash-ha-sha>` 换成 Task 2 记的完整 sha。）
Expected: 每个打印 `* [new branch]`。

- [ ] **Step 4: 推送 7 个 fork（原 404）的子模块**

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

- [ ] **Step 5: 验证 14 个子模块分支都在 canonical 上**

Run:
```
for repo in sonic-swss sonic-sairedis sonic-swss-common sonic-gnmi sonic-mgmt-framework sonic-linux-kernel sonic-mgmt-common sonic-platform-vpp sonic-dhcp-relay sonic-bmp sonic-dash-ha sonic-dash-api sonic-stp sonic-wpa-supplicant; do
  sha=$(gh api repos/canonical/$repo/branches/202605_resolute --jq '.commit.sha' 2>/dev/null | cut -c1-10)
  echo "$repo 202605_resolute=$sha"
done
```
Expected: 14 行，每行 sha 非空。

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

- [ ] **Step 1: 改写 .gitmodules URL**

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

- [ ] **Step 2: 把 .gitmodules 同步进 .git/config**

Run: `git submodule sync`
Expected: 无输出（传播 URL）。

- [ ] **Step 3: 对齐子模块工作目录到 gitlink**

Run: `git submodule update --recursive --no-fetch`
Expected: 子模块检出至超仓库 gitlink 记录的 commit。对 `src/sonic-dash-ha` 和 `src/sonic-sairedis`，检出 Task 2 的新 rebase build commit。其余 12 个若已在 build commit 则 no-op。

- [ ] **Step 4: 验证 git status 干净**

Run: `git status --short`
Expected: 只有 `.gitmodules` 显示 modified。无 dirty 子模块。若子模块显示 dirty，重跑 Step 3；若仍 dirty，手动 `git -C <子模块> checkout <Task 5 映射里的 build-commit-sha>`。

- [ ] **Step 5: 提交 .gitmodules 改动**

Run:
```
git add .gitmodules
git commit -m "build: point submodules at canonical resolute branches"
```
Expected: commit 创建。

- [ ] **Step 6: 重推超仓库构建分支（改写后的 tip）**

Run: `git push canonical 202605_resolute --force-with-lease`
Expected: `+ <sha>...202605_resolute -> 202605_resolute (forced update)`——`.gitmodules` 提交现在是 canonical 上的 tip。

- [ ] **Step 7: 验证 canonical 上的 .gitmodules**

Run: `gh api repos/canonical/sonic-buildimage/contents/.gitmodules?ref=202605_resolute --jq '.content' | base64 -d | grep -c 'github.com:canonical'`
Expected: `14`（14 个 resolute 子模块都指向 canonical）。

---

## Task 7: 最终验证（§10）

确认整个上传成功，原仓库已对齐。

**Files:** 无。

- [ ] **Step 1: 超仓库构建分支无 superpowers 文档**

Run: `git -C ~/sonic-buildimage-resolute ls-tree -r 202605_resolute --name-only | grep -i superpowers`
Expected: 空。

- [ ] **Step 2: 超仓库构建坐在最新 202605**

Run: `git -C ~/sonic-buildimage-resolute merge-base 202605_resolute sonic-net/202605`
Expected: `9c84048a4`（完整 sha）。

- [ ] **Step 3: 超仓库文档分支有 6 个双语文档，无 .pptx**

Run: `git -C ~/sonic-buildimage ls-tree -r 202605_resolute_doc --name-only | grep superpowers`
Expected: 6 行（3 主题 × `-en.md`/`-zh.md`），无 `.pptx`/`.pptx.md`。

- [ ] **Step 4: .gitmodules 指向 canonical 的有 14 个**

Run: `grep -c 'github.com:canonical' ~/sonic-buildimage-resolute/.gitmodules`
Expected: `14`。

- [ ] **Step 5: 全部 14 个子模块分支在 canonical 上**

（复用 Task 5 Step 5 的循环——14 个都应返回非空 sha。）

- [ ] **Step 6: 原仓库在正确分支**

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

- [ ] **Step 7: 构建仓库 git status 干净（无 dirty 子模块）**

Run: `git -C ~/sonic-buildimage-resolute status --short`
Expected: 空（Task 6 Step 3 后所有子模块对齐 gitlink）。

- [ ] **Step 8: 两分支在 GitHub 可见**

打开：
- `https://github.com/canonical/sonic-buildimage/tree/202605_resolute`
- `https://github.com/canonical/sonic-buildimage/tree/202605_resolute_doc`

Expected: 两分支都渲染，显示最新提交。

- [ ] **Step 9: 记录最终状态到 memory**

更新 memory note `sonic-resolute-vs-build-success.md`（或新建 `sonic-resolute-canonical-upload.md`），记录：canonical 上的 2 个超仓库分支名、14 个子模块 `202605_resolute` 分支、2 个 rebase 过的子模块 sha，以及原仓库现停在 `202605_resolute` / `202605_resolute_doc` 的事实。跨 session 保留。
