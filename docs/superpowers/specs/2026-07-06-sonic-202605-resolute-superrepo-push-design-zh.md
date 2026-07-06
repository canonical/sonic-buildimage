# SONiC 202605 Resolute — 分支上传设计（超仓库 + 子模块）

- **日期：** 2026-07-06
- **范围：** 超仓库（`sonic-buildimage`）+ 14 个有 resolute `build:` 提交的子模块。
- **目标组织：** GitHub `canonical/`。账号 `xdqi` = canonical org member（active），token scopes `repo` + `read:org`（无 `admin:org`）。

## 1. 目标

把 resolute 迁移工作——超仓库和子模块——上传到 `canonical/`，供团队 clone 并复现 resolute `vs` 构建。

### 分支命名（用户 2026-07-06 决定）
| Repo 类别 | 构建分支 | 文档分支 |
|---|---|---|
| `sonic-*` repo（全部 14 子模块 + 超仓库） | `202605_resolute` | （无） |
| 超仓库 `sonic-buildimage`（也是 `sonic-*`） | `202605_resolute` | `202605_resolute_doc` |

子模块**只推构建分支**——其 `build:` 提交不含 superpowers docs，无 `_doc` 变体。`sonic_202605_resolute` 规则（非 `sonic-*` repo）此处不触发：14 个子模块的 canonical repo 名全以 `sonic-` 开头。

### 上传内容
- **超仓库构建分支 `202605_resolute`** —— 全部 resolute build 提交，**不含任何** superpowers docs（`filter-repo` 清除）。
- **超仓库文档分支 `202605_resolute_doc`** —— 迁移 design / plan / review / catalog / report 文档（仅双语 `.md`；不含 `.pptx`/`.pptx.md`）。
- **14 个子模块的 `202605_resolute` 分支** —— 各子模块的 resolute `build:` 提交。

两条超仓库分支均 rebase 到**最新上游 `202605`**（`sonic-net/sonic-buildimage` HEAD `9c84048a4`）。

## 2. 当前状态（2026-07-06 已核实）

### 超仓库源
| 仓库 | 分支 | 领先 merge-base | 备注 |
|---|---|---|---|
| `~/sonic-buildimage-resolute` | `resolute` | **71 个提交** | 5 个碰 `docs/superpowers/`；66 个纯 build。最新提交 `2d1fc1b4f` drop boost 1.88 适配 → boost 1.83 baseline。Dockerfile.j2 改动**已提交**。 |
| `~/sonic-buildimage` | `202605-wip` | 7 个提交（+1 spec） | 全是 docs。待重组：删 2 个旧的单语文档，新增 6 个双语 `.md`（3 主题 × en/zh）。`.pptx`、`.pptx.md`、`sonic.code-workspace` 走 gitignore，不提交。 |

`resolute` 分支里已提交的 superpowers 路径（5 个文件，全在 `docs/superpowers/` 下）：
- `plans/done-bar-status.txt`、`plans/fips-status.txt`
- `specs/2026-07-05-resolute-variant-naming-design.md`、`specs/category-c-catalog-en.md`、`specs/category-c-catalog-zh.md`

5 个 docs 提交与 66 个 build 提交**交错**——必须按路径清理（交互式 rebase-drop 要编辑 71 个 todo）。

### 超仓库上游距离
- merge-base `77cfa809d`；sonic-net `202605` HEAD `9c84048a4`；中间 **3 个提交**，全是自动 submodule bump：`sonic-dash-ha`（#28234）、`dhcpmon`（#28232）、`sonic-sairedis`（#28242）。
- 上游 `202605` **不含** `docs/superpowers/` 内容 → `filter-repo` 不动 base 提交，merge-base 哈希保留。
- canonical 的 `202605` HEAD = `77cfa809d`（= merge-base；canonical 落后 sonic-net 3 个提交）。新分支基于 sonic-net 最新，不受影响。

### 子模块（boost 1.83 revert 后，14 个有 resolute `build:` 提交）
boost 1.88→1.83 的 revert 提交 `2d1fc1b4f` drop 了 linkmgrd 的 `io_service→io_context` 迁移（49 文件）和 sonic-redfish 的 libboost1.88 alternates——**linkmgrd 和 sonic-redfish 现为 0 个 build 提交**，剩 14 个：

| 子模块 | canonical repo | build 提交 | 真实改动（仅 build 提交） | canonical 状态 |
|---|---|---|---|---|
| src/sonic-swss | sonic-swss | 1 | 4 文件 +11/-6 | 存在，push=True，**独立（非 fork）** |
| src/sonic-sairedis | sonic-sairedis | 1 | 3 文件 +8/-3 | 存在，push=True，**独立** |
| src/sonic-swss-common | sonic-swss-common | 1 | 2 文件 +15/-7 | 存在，push=True，**独立** |
| src/sonic-gnmi | sonic-gnmi | 1 | 3 文件 +26/-5 | 存在，push=True，**独立** |
| src/sonic-mgmt-framework | sonic-mgmt-framework | 1 | 2 文件 +31/-11 | 存在，push=True，**独立** |
| src/sonic-linux-kernel | sonic-linux-kernel | 1 | 1 文件 +9/-1 | 存在，push=True，**独立** |
| src/sonic-mgmt-common | sonic-mgmt-common | 1 | 1 文件 +2/-0 | 存在，push=True，**独立** |
| platform/vpp | sonic-platform-vpp | 1 | 4 文件 +4/-4 | **404 — 从 sonic-net fork** |
| src/dhcprelay | sonic-dhcp-relay | 1 | 3 文件 +3/-3 | **404 — fork** |
| src/sonic-bmp | sonic-bmp | 1 | 2 文件 +1/-1 | **404 — fork** |
| src/sonic-dash-ha | sonic-dash-ha | 1 | 1 文件 +0/-2 | **404 — fork** |
| src/sonic-dash-api | sonic-dash-api | 1 | 1 文件 +2/-2 | **404 — fork** |
| src/sonic-stp | sonic-stp | 1 | 2 文件 +7/-2 | **404 — fork** |
| src/wpasupplicant/sonic-wpa-supplicant | sonic-wpa-supplicant | 1 | 1 文件 +7/-2 | **404 — fork** |

- **7 个已存在**的 canonical repo 全是 `fork=false`、`parent=null`——2024 年手动建的**独立镜像**，与 sonic-net **分叉**（无近期共同祖先；canonical master ≠ sonic-net master）。它们有陈旧的 `202012/202305/202405` 分支。
- **7 个缺失（404）**——sonic-net 上游存在且非 fork（合法 fork 源）。
- `xdqi` 对全部 14 个 sonic-net 上游 push=False → 不能把 resolute 分支推到 sonic-net。

### 推送机制（已验证）
- **向分叉的 canonical repo 推新分支（`202605_resolute`）不需要 `--force`**——git 接受无共同祖先的新分支 ref，只要推送的 commit 完整可达。在 sonic-mgmt-common 上 dry-run 确认：`* [new branch] 47995eb -> 202605_resolute`。
- `gh repo fork --org canonical` 需要 org 级权限；`xdqi` 是 `role=member`（非 owner），scopes `repo`+`read:org`（无 `admin:org`）。**fork 到 canonical 可能被拒**——必须先试一个再依赖（§8 风险 R5）。

## 3. 决策

| # | 决策点 | 选择 | 理由 |
|---|---|---|---|
| D1 | rebase base（超仓库） | sonic-net 最新 `202605`（`9c84048a4`） | 用户说"最新 202605"；3 个上游 bump 无害；2 个机械性 gitlink 冲突。 |
| D2 | docs 清理工具 | `git filter-repo --path docs/superpowers --invert-paths` | 5 个 docs 提交与 66 个 build 提交交错；按路径清理是唯一干净做法；从每个提交的树里抹掉该路径。 |
| D3 | 超仓库工作区模型 | 全新非递归 clone | `filter-repo` 拒绝非全新 clone（不加 `--force`），且删 `origin`；原仓库 `~/sonic-buildimage-resolute`（16 子模块 + boost 工作）不能动。 |
| D4 | `.pptx`/`.pptx.md` | gitignore，不提交 | 生成产物；用户 2026-07-06 决定。仅提交双语 `.md`。 |
| D5 | `sonic.code-workspace` | gitignore，不提交 | VSCode 个人工作区文件。 |
| D6 | 分支命名 | `202605_resolute`（构建，全部 repo）/ `202605_resolute_doc`（仅超仓库文档） | 用户规则：`sonic-*` repo 用 `202605_resolute{,_doc}`；子模块仅构建。 |
| D7 | 子模块 repo | 7 个已存在 canonical（直推）+ 7 个从 sonic-net fork | 用户："fork 不是 create"。fork 带上 sonic-net 历史，gitlink 祖先链完整。 |
| D8 | 子模块推送 | 新分支 `202605_resolute`，无 `--force` | 已验证：分叉 repo 上接受无共同祖先的新分支 ref。 |
| D9 | 子模块 base | 不 rebase——直接推 resolute 提交（在其 sonic-net master parent 上） | 子模块 resolute 提交直接坐在 sonic-net `master` 上；canonical repo 分叉/空，rebase 无意义。同事需要的是 build 提交 + 其 sonic-net 祖先。 |

## 4. 超仓库构建分支 —— `202605_resolute`

所有步骤在**全新 clone** 中执行；原仓库 `~/sonic-buildimage-resolute` 全程不动。

1. **安装 filter-repo：** `sudo apt install git-filter-repo`（Debian `2.47.0-3`；有免密 sudo）。
2. **全新非递归 clone：**
   ```
   git clone --branch resolute --no-recursive /home/sheldon-qi/sonic-buildimage-resolute /work/resolute-super
   cd /work/resolute-super
   ```
3. **从所有历史清除 superpowers 文档：**
   ```
   git filter-repo --path docs/superpowers --invert-paths
   ```
   从每个提交的树里移除 `docs/superpowers/`；剪枝变空的约 5 个提交。base 提交不变（上游无此路径）。`filter-repo` 默认删 `origin`——符合预期。
4. **添加远端**（sonic-net = 拉最新 202605；canonical = 推送目标）：
   ```
   git remote add sonic-net https://github.com/sonic-net/sonic-buildimage.git
   git remote add canonical  git@github.com:canonical/sonic-buildimage.git
   git fetch sonic-net
   ```
5. **rebase 到最新 202605：**
   ```
   git rebase --onto sonic-net/202605 77cfa809d resolute
   ```
   - 把过滤后的 resolute 提交重放到 `9c84048a4` 上。
   - **预期冲突：** `sonic-dash-ha` 和 `sonic-sairedis` 的 gitlink 指针（本地和上游都 bump 了）。`dhcpmon` 干净。无 build 文件冲突。
   - **解决：** 保留 resolute 的指针。⚠️ rebase "theirs" = 被重放的提交（resolute）：`git checkout --theirs <子模块>` 然后 `git add <子模块>`。
6. **重命名分支：** `git branch -m resolute 202605_resolute`
7. **推送：** `git push canonical 202605_resolute`

## 5. 超仓库文档分支 —— `202605_resolute_doc`

步骤在 `~/sonic-buildimage`（分支 `202605-wip`）执行。无需 filter-repo。

1. **gitignore：** 在 `.gitignore` 中加入 `sonic.code-workspace`、`*.pptx`、`*.pptx.md`。
2. **提交 docs 重组：** 只 stage 2 个删除 + 6 个新双语 `.md`；提交 `docs: reorganize resolute migration docs to bilingual`。**不要** stage `.pptx`/`.pptx.md`/`sonic.code-workspace`。
3. **创建目标分支**（`202605-wip` 保持不动，作为 rebase 前备份）：
   ```
   git checkout -b 202605_resolute_doc
   ```
4. **rebase 到最新 202605：**
   ```
   git rebase --onto origin/202605 77cfa809d 202605_resolute_doc
   ```
   主仓库 `origin` = sonic-net（SSH），已在 `9c84048a4`。预期 ~0 冲突。
5. **添加 canonical 远端并推送：**
   ```
   git remote add canonical git@github.com:canonical/sonic-buildimage.git
   git push canonical 202605_resolute_doc
   ```

## 6. 子模块分支 —— `202605_resolute`（×14）

对 14 个子模块的每一个，在其工作目录 `~/sonic-buildimage-resolute/<子模块>` 下：

1. **添加 canonical 远端**（SSH）：
   ```
   git remote add canonical git@github.com:canonical/<repo>.git
   ```
   - 7 个已存在 repo：远端立即可用（push=True）。
   - 7 个缺失 repo：**先 fork**——`gh repo fork sonic-net/<repo> --org canonical --remote=false`（然后手动加 canonical 远端）。⚠️ R5：批量前先验证 `xdqi` 能 fork 到 org。
2. **推送构建分支**（不 rebase，不 force）：
   ```
   git push canonical <build-commit-sha>:refs/heads/202605_resolute
   ```
   把 resolute build 提交（在其 sonic-net master parent 上）作为新分支推上去。git 接受无共同祖先的新分支 ref（§2 已验证）。

### 子模块 repo → build 提交映射
| canonical repo | build 提交（短） |
|---|---|
| canonical/sonic-swss | `6d3a46bb` |
| canonical/sonic-sairedis | `68da16e5` |
| canonical/sonic-swss-common | `baf0b19` |
| canonical/sonic-gnmi | `c8f96ff` |
| canonical/sonic-mgmt-framework | `fda49ff` |
| canonical/sonic-linux-kernel | `c54d5e3` |
| canonical/sonic-mgmt-common | `47995eb` |
| canonical/sonic-platform-vpp（fork） | `fe8c727` |
| canonical/sonic-dhcp-relay（fork） | `d620ecc` |
| canonical/sonic-bmp（fork） | `c11289b` |
| canonical/sonic-dash-ha（fork） | `b336da3` |
| canonical/sonic-dash-api（fork） | `43c676b` |
| canonical/sonic-stp（fork） | `416491c` |
| canonical/sonic-wpa-supplicant（fork） | `7f39eb03f` |

## 7. `.gitmodules` URL 改写

子模块分支推上去后，超仓库构建分支 `202605_resolute` 必须把 gitlink 指向 canonical，而非 sonic-net。在全新超仓库 clone（§4）里，**步骤 5 rebase 之后**：

1. **改写 `.gitmodules`**——对 14 个子模块，把 `url = https://github.com/sonic-net/<repo>.git` 改为 `git@github.com:canonical/<repo>.git`。用 `git config -f .gitmodules submodule.<path>.url <new>`（或 sed）。
2. **同步 config：** `git submodule sync`（把 `.gitmodules` URL 传播到 `.git/config`）。
3. **提交：** `git commit -am "build: point submodules at canonical resolute branches"`。
4. **重新推送超仓库构建分支：** `git push canonical 202605_resolute --force-with-lease`（force-with-lease 因为这改写了刚推上去的 tip）。

⚠️ 其他子模块（无 resolute 提交）仍指向 sonic-net——只有 14 个有 build 提交的迁到 canonical。

## 8. 风险与缓解

- **R1 filter-repo 重写构建分支所有哈希** → 原始提交安全保存在 `~/sonic-buildimage-resolute`；全新 clone 用完即弃。
- **R2 gitlink 冲突（`sonic-dash-ha`、`sonic-sairedis`）** → 机械性；取 resolute 指针（§4 步骤 5 提醒）。
- **R3 canonical `admin=False`** → 不能改设置/保护，但能推新分支。新分支名默认无保护规则。
- **R4 `.gitmodules` 改写改写超仓库 tip** → 重新推送用 `--force-with-lease`；只影响超仓库构建分支，且只一次。
- **R5 ⚠️ fork 到 org 可能被拒**——`xdqi` 是 canonical `member`（非 owner），token 无 `admin:org`。`gh repo fork --org canonical` 可能失败。**缓解：** 先试一个 fork；若被拒，请 canonical owner 执行这 7 个 fork，或退而求其次用 `gh repo create canonical/<repo> --source sonic-net/<repo> --fork`（同样需要 org 权限）或暂时推到 `xdqi/`。这是最大的未验证执行风险。
- **R6 已存在的 7 个 canonical repo 是分叉的** → 它们陈旧的 `master`/`202012` 等分支不受影响。只新增 `202605_resolute` 分支。同事 fetch 子模块时拿到 resolute 提交 + 其完整 sonic-net 祖先（在新分支上完整可达）。

## 9. 范围外

- **`~/sonic-buildimage-202605-clone`**：忽略。已核实与主仓库 docs 逐字节相同（ahead-3 是 `202605-wip` 里的重复内容）。
- **更新 canonical 现有的 `202605`/`master`**：未要求。新分支是叠加。
- **sonic-frr、supervisor、platform vendor SDK**（saibcm/mrvl/mellanox 等）：非你的 resolute 工作；不动。
- **把 resolute 子模块提交推回 sonic-net 上游**：范围外（属于 PR，另行处理）。

## 10. 验证

- 超仓库构建：`git ls-tree -r 202605_resolute --name-only | grep -i superpowers` → **空**。
- 超仓库构建：`git merge-base 202605_resolute sonic-net/202605` → `9c84048a4`。
- 超仓库文档：`git ls-tree -r 202605_resolute_doc --name-only | grep superpowers` → 双语 `.md` 存在；**无** `.pptx`/`.pptx.md`。
- 超仓库 `.gitmodules`：14 个 resolute 子模块指向 `canonical/`；其余仍 `sonic-net/`。
- 14 个子模块各：`git ls-remote canonical refs/heads/202605_resolute` → 非空，sha 与 build 提交一致。
- 分支可见于 `github.com/canonical/sonic-buildimage/tree/202605_resolute`、`/tree/202605_resolute_doc`，及各 `canonical/<子模块>/tree/202605_resolute`。
