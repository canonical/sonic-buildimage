# SONiC 202605 Resolute — 超仓库分支上传（设计）

- **日期：** 2026-07-06
- **范围：** 仅超仓库（`sonic-buildimage`）。子模块明确推迟（§7）。
- **目标远端：** `canonical/sonic-buildimage` —— `sonic-net/sonic-buildimage` 的 GitHub fork。账号 `xdqi` 拥有 `push=True`、`admin=False`。

## 1. 目标

把当前存放在两个本地仓库的 resolute 迁移工作，作为**两条独立分支**上传到 `canonical/sonic-buildimage`，供团队查看和构建：

- **`202605-resolute`** —— 构建分支：全部 resolute build 提交，**不含任何** superpowers 文档。
- **`202605-resolute-docs`** —— 文档分支：全部迁移 design / plan / review / catalog / report 文档（双语 zh+en）。

两分支均 rebase 到**最新上游 `202605`**（`sonic-net/sonic-buildimage` HEAD `9c84048a4`）。

## 2. 当前状态（2026-07-06 已核实）

### 源仓库
| 仓库 | 分支 | 领先 merge-base | 备注 |
|---|---|---|---|
| `~/sonic-buildimage-resolute` | `resolute` | 70 个提交 | 5 个碰 `docs/superpowers/`；65 个纯 build。未提交：`Dockerfile.j2` boost 1.88→1.83（需带入）。 |
| `~/sonic-buildimage` | `202605-wip` | 7 个提交 | 全是 docs。待重组：删 2 个旧的单语文档，新增 6 个双语 `.md`（3 主题 × en/zh）。`.pptx`、`.pptx.md`、`sonic.code-workspace` 走 gitignore，不提交。 |

`resolute` 分支里已提交的 superpowers 路径（5 个文件，全在 `docs/superpowers/` 下）：
- `plans/done-bar-status.txt`、`plans/fips-status.txt`
- `specs/2026-07-05-resolute-variant-naming-design.md`、`specs/category-c-catalog-en.md`、`specs/category-c-catalog-zh.md`

这 5 个 docs 提交**散落**在 65 个 build 提交之间（如 `93f1fe2a2 docs: Goal-2 Category-C catalog` 夹在 `8f4fc81ed` 和 `5e29f4bcd` 之间）。

### 目标远端
- `canonical/sonic-buildimage`：`sonic-net/sonic-buildimage` 的 fork；有 `202605` 分支。
- `xdqi` push=True（可推分支），admin=False（不能改设置/保护规则）。
- canonical 的 `202605` HEAD = `77cfa809d`（= merge-base；canonical 落后 sonic-net 3 个提交）。
- sonic-net `202605` HEAD = `9c84048a4`。

### 上游距离
- merge-base `77cfa809d` 到 sonic-net 最新 `9c84048a4` 之间有 3 个提交，**全是自动 submodule bump**：`sonic-dash-ha`（#28234）、`dhcpmon`（#28232）、`sonic-sairedis`（#28242）。
- 上游 `202605` **不含**任何 `docs/superpowers/` 内容 → `filter-repo` 不会改动共享的 base 提交（哈希保留，merge-base 仍为 `77cfa809d`）。

## 3. 决策

| # | 决策点 | 选择 | 理由 |
|---|---|---|---|
| D1 | rebase base | sonic-net 最新 `202605`（`9c84048a4`） | 用户说"最新 202605"；3 个上游 bump 无害；2 个机械性 submodule 指针冲突可接受。 |
| D2 | docs 清理工具 | `git filter-repo --path docs/superpowers --invert-paths` | 5 个 docs 提交与 65 个 build 提交交错——交互式 rebase-drop 要编辑 70 个 todo。按路径清理是唯一干净做法，且从每个提交的树里抹掉该路径（真正的"彻底清理"）。 |
| D3 | 工作区模型 | 全新非递归 clone | `filter-repo` 拒绝非全新 clone（不加 `--force` 时），且会删 `origin`。原仓库 `~/sonic-buildimage-resolute`（16 个子模块 + 未提交的 Dockerfile 改动）不能动。 |
| D4 | `.pptx` 与 `.pptx.md` | gitignore，不提交 | 生成的演示产物；用户 2026-07-06 决定。仅提交双语 `.md` 文档。 |
| D5 | `sonic.code-workspace` | gitignore，不提交 | VSCode 个人工作区文件。 |

## 4. 分支 A —— `202605-resolute`（构建）

所有步骤在**全新 clone** 中执行；原仓库 `~/sonic-buildimage-resolute` 全程不被修改。

1. **安装 filter-repo：** `sudo apt install git-filter-repo`（Debian 包 `2.47.0-3`；有免密 sudo）。
2. **全新非递归 clone**（保留 70 个本地提交；超仓库历史重写不需要子模块检出）：
   ```
   git clone --branch resolute --no-recursive /home/sheldon-qi/sonic-buildimage-resolute /work/resolute-super
   cd /work/resolute-super
   ```
3. **从所有历史中清除 superpowers 文档：**
   ```
   git filter-repo --path docs/superpowers --invert-paths
   ```
   从每个提交的树里移除 `docs/superpowers/`；剪枝变空的约 5 个提交。base 提交（≤ merge-base `77cfa809d`）不变（上游无此路径）。`filter-repo` 默认删除 `origin` —— 符合预期。
4. **添加远端**（canonical = 推送目标；sonic-net = 拉最新 202605）：
   ```
   git remote add sonic-net https://github.com/sonic-net/sonic-buildimage.git
   git remote add canonical  git@github.com:canonical/sonic-buildimage.git
   git fetch sonic-net
   ```
5. **rebase 到最新 202605：**
   ```
   git rebase --onto sonic-net/202605 77cfa809d resolute
   ```
   - 把过滤后的 resolute 提交（`77cfa809d` 之后的）重放到 `9c84048a4` 上。
   - **预期冲突：** `sonic-dash-ha` 和 `sonic-sairedis` 的 submodule gitlink 指针（本地和上游都 bump 了）。`dhcpmon` 干净应用（resolute 没动它）。无 build 文件冲突（3 个上游提交只动 gitlink）。
   - **冲突解决：** 保留 resolute 的指针（指向本地 resolute 子模块提交）。⚠️ rebase 语义反直觉——`git rebase` 中 "ours" = 新 base（`sonic-net/202605`），"theirs" = 被重放的提交（resolute）。所以 resolute 的指针是 **"theirs"**：`git checkout --theirs <子模块路径>` 然后 `git add <子模块路径>`。
6. **重命名分支：** `git branch -m resolute 202605-resolute`
7. **推送：** `git push canonical 202605-resolute`

## 5. 分支 B —— `202605-resolute-docs`（文档）

步骤在 `~/sonic-buildimage`（分支 `202605-wip`）执行。无需 filter-repo —— 此分支就是文档的归宿。

1. **gitignore 生成/个人文件：** 在 `.gitignore` 中加入 `sonic.code-workspace`、`*.pptx`、`*.pptx.md`。
2. **提交 docs 重组：** 只 stage 2 个删除 + 6 个新双语 `.md`（3 主题 × en/zh）；提交 `docs: reorganize resolute migration docs to bilingual`。**不要** stage `.pptx`、`.pptx.md` 或 `sonic.code-workspace`。
3. **从 `202605-wip` 创建目标分支**（`202605-wip` 保持不动，作为 rebase 前的备份）：
   ```
   git checkout -b 202605-resolute-docs
   ```
4. **rebase 到最新 202605：**
   ```
   git rebase --onto origin/202605 77cfa809d 202605-resolute-docs
   ```
   主仓库 `origin` = sonic-net（SSH），已在 `9c84048a4`。预期 ~0 冲突（文档不碰 submodule 指针或 build 文件）。
5. **添加 canonical 远端并推送：**
   ```
   git remote add canonical git@github.com:canonical/sonic-buildimage.git
   git push canonical 202605-resolute-docs
   ```

## 6. 风险与缓解

- **filter-repo 重写 build 分支所有提交哈希** → 原始提交安全保存在 `~/sonic-buildimage-resolute`；全新 clone 用完即弃。
- **submodule 指针冲突（`sonic-dash-ha`、`sonic-sairedis`）** → 机械性；取 resolute 的指针（见 D2 / 步骤 5 对 rebase "theirs" 语义的提醒）。
- **canonical `admin=False`** → 不能改仓库设置或分支保护，但**能**推新分支。新分支名默认无保护规则。
- **gitlink 指向不可达的子模块提交** → 预期内。在 16 个子模块的 resolute 提交被推到某处之前（见 §7），`202605-resolute` 对同事尚不能完整 clone/构建。`git submodule update` 会对这些子模块失败；这是已知且已记录的限制。

## 7. 范围外

- **子模块**（16 个有 resolute 提交，共约 17 个提交）：推迟。用户将先评估各子模块的修改量，再决定子模块落点策略。在此之前，`202605-resolute` 的 gitlink 指向不在任何公开远端上的提交。
- **`~/sonic-buildimage-202605-clone`**：忽略。已核实与主仓库 docs 逐字节相同（其 ahead-3 提交是 `202605-wip` 里已有的重复内容）。
- **把 canonical 的 `202605` 更新到 sonic-net 最新**：未要求。两个新分支基于 sonic-net 最新，故本就携带那 3 个上游 bump。

## 8. 验证

- `git ls-tree -r 202605-resolute --name-only | grep -i superpowers` → **空**（构建分支无任何 superpowers 文档）。
- `git log --oneline 202605-resolute | grep 'docs:'` → 无提交碰 `docs/superpowers/`。
- `git merge-base 202605-resolute sonic-net/202605` → `9c84048a4`（坐在最新 202605 上）。
- `git ls-tree -r 202605-resolute-docs --name-only | grep superpowers` → 双语 `.md` 文档存在；**无** `.pptx` / `.pptx.md`。
- 两分支可见于 `github.com/canonical/sonic-buildimage/tree/202605-resolute` 和 `/tree/202605-resolute-docs`。
