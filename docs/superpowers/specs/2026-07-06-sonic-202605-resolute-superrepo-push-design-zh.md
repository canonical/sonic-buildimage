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
| `~/sonic-buildimage` | `202605-wip` | 7 个提交（+1 spec） | 全是 docs。2 个旧单语文档待 filter-repo 清除（§5）；6 个新双语 `.md`（3 主题 × en/zh）待提交。`.pptx`、`.pptx.md`、`sonic.code-workspace` 走 gitignore，不提交。 |

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
- `gh repo fork --org canonical` —— xdqi 有 org 级建 repo 权限（用户已确认），所以 7 个缺失 repo fork 到 canonical 预期能成。

## 3. 决策

| # | 决策点 | 选择 | 理由 |
|---|---|---|---|
| D1 | rebase base（超仓库） | sonic-net 最新 `202605`（`9c84048a4`） | 用户说"最新 202605"；该 tree 的 gitlink 定义了子模块 base lock（D9）。3 个上游 bump 无害；2 个 gitlink 冲突（`sonic-dash-ha`、`sonic-sairedis`）通过在超仓库 rebase **之前**把这些子模块 rebase 到各自 lock（§6.1）解决——而非接受陈旧指针。 |
| D2 | docs 清理工具 | `git filter-repo --path docs/superpowers --invert-paths` | 5 个 docs 提交与 66 个 build 提交交错；按路径清理是唯一干净做法；从每个提交的树里抹掉该路径。 |
| D3 | 超仓库工作区模型 | 原仓库就地改造（`--force`） | 用户要原仓库对齐 canonical 且 filter 只做一次。直接在 `~/sonic-buildimage-resolute` 和 `~/sonic-buildimage` 上 `filter-repo --force` 改写 + 重命名分支为 `202605_resolute` / `202605_resolute_doc`。不可逆；先打安全 tag。无 fresh clone，无"旧历史保留"分裂。 |
| D10 | 原仓库终态 | 对齐 canonical | 执行后两原仓库停在和 canonical 同名的分支（`202605_resolute` / `202605_resolute_doc`）；子模块工作目录检出至 gitlink（§7 步骤 3）。以后提交直接推，不再 re-filter。 |
| D4 | `.pptx`/`.pptx.md` | gitignore，不提交 | 生成产物；用户 2026-07-06 决定。仅提交双语 `.md`。 |
| D5 | `sonic.code-workspace` | gitignore，不提交 | VSCode 个人工作区文件。 |
| D6 | 分支命名 | `202605_resolute`（构建，全部 repo）/ `202605_resolute_doc`（仅超仓库文档） | 用户规则：`sonic-*` repo 用 `202605_resolute{,_doc}`；子模块仅构建。 |
| D7 | 子模块 repo | 7 个已存在 canonical（直推）+ 7 个从 sonic-net fork | 用户："fork 不是 create"。fork 带上 sonic-net 历史，gitlink 祖先链完整。 |
| D8 | 子模块推送 | 新分支 `202605_resolute`，无 `--force` | 已验证：分叉 repo 上接受无共同祖先的新分支 ref。 |
| D9 | 子模块 base | 把每个 `build:` 提交 rebase 到 sonic-net `202605`（`9c84048a4`）gitlink 锁定的 commit 上 | 超仓库 `202605` 的 tree 锁定了每个子模块期望的 base commit。14 个里有 12 个已坐在 lock 上（build parent == lock）；2 个（`sonic-dash-ha`、`sonic-sairedis`）base 被上游 bump 了 → 必须把 `build:` 提交 rebase 到新 lock。这也干净地解决了超仓库 rebase 的 gitlink 冲突（新 build commit，非陈旧指针）。 |

## 4. 超仓库构建分支 —— `202605_resolute`（原仓库就地改造）

直接在 `~/sonic-buildimage-resolute` 上操作（无 fresh clone）。原 `resolute` 分支被改造成 `202605_resolute`，使仓库推送后对齐 canonical。filter-repo 此处只跑**一次**；以后 build 提交直接落在 `202605_resolute` 上，不再 re-filter。

⚠️ **不可逆历史改写。** 全部 71 个 resolute 提交哈希改变。旧 `resolute` 分支名消失（重命名）。`filter-repo --force` 删除 `origin`；远端在步骤 4 重加。备份：改写前先打 tag（`git tag pre-filter-resolute resolute`）；canonical 推上去的分支是此后持久副本。

1. **安装 filter-repo：** `sudo apt install git-filter-repo`（Debian `2.47.0-3`；有免密 sudo）。
2. **可选安全 tag：** `git tag pre-filter-resolute resolute`
3. **从所有历史清除 superpowers 文档（就地，`--force`）：**
   ```
   cd ~/sonic-buildimage-resolute
   git filter-repo --force --path docs/superpowers --invert-paths
   ```
   从每个提交的树里移除 `docs/superpowers/`；剪枝变空的约 5 个提交。filter-repo **不**递归子模块工作目录，**不**重映射 gitlink sha——14 个子模块指针原样保留。base 提交不变（上游 202605 无此路径）。`origin` 远端被 filter-repo 删除。
4. **重加远端**（sonic-net = 拉最新 202605；canonical = 推送目标）并 fetch：
   ```
   git remote add sonic-net https://github.com/sonic-net/sonic-buildimage.git
   git remote add canonical  git@github.com:canonical/sonic-buildimage.git
   git fetch sonic-net
   ```
5. **先 rebase 子模块 `build:` 提交（§6.1 前置），再 rebase 超仓库到最新 202605：**
   - §6.1 必须先于本步骤——超仓库 rebase 的 gitlink 冲突靠指向 rebase 后的 build commit 解决。
   ```
   git rebase --onto sonic-net/202605 77cfa809d resolute
   ```
   - 把过滤后的 resolute 提交重放到 `9c84048a4` 上。
   - **预期冲突：** `sonic-dash-ha` 和 `sonic-sairedis` 的 gitlink 指针（本地和上游都 bump 了）。`dhcpmon` 干净。无 build 文件冲突。
   - **解决：** 把 gitlink 设为 §6.1 rebase 后的新 build commit sha：`git update-index --cacheinfo 160000 <新build-sha> <子模块路径>` 然后 `git add <子模块路径>` 继续。（**不要**用 `checkout --theirs`——那保留 rebase 前的陈旧指针。）对 `dhcpmon`（无 resolute build 提交），取 202605 的指针：`git checkout --theirs src/dhcpmon`。
6. **重命名分支：** `git branch -m resolute 202605_resolute`
7. **对齐子模块工作目录到新 gitlink**（见 §7）——使 `git status` 干净。
8. **推送：** `git push canonical 202605_resolute`

## 5. 超仓库文档分支 —— `202605_resolute_doc`（原仓库就地改造）

直接在 `~/sonic-buildimage` 上操作（分支 `202605-wip`）。filter-repo 把 2 个旧单语文档从历史抹掉；分支重命名为 `202605_resolute_doc`。filter-repo 跑一次。

⚠️ **不可逆历史改写** `~/sonic-buildimage`。同 §4 注意事项。可选安全 tag：`git tag pre-filter-docs 202605-wip`。

1. **提交 6 个新双语文档（在 `202605-wip`）：** 在 `.gitignore` 中加入 `sonic.code-workspace`、`*.pptx`、`*.pptx.md`；只 stage 6 个新 `-en.md`/`-zh.md`（3 主题 × en/zh）；提交 `docs: add resolute migration docs bilingual`。**不要** stage 2 个删除、`.pptx`/`.pptx.md`、`sonic.code-workspace`。
2. **可选安全 tag：** `git tag pre-filter-docs 202605-wip`
3. **从所有历史清除 2 个旧单语文档（就地，`--force`）：**
   ```
   cd ~/sonic-buildimage
   git filter-repo --force \
     --path docs/superpowers/resolute-migration-code-review.md \
     --path docs/superpowers/resolute-vs-migration-report.md \
     --invert-paths
   ```
   从每个提交的树里移除这 2 个路径；剪枝变空的提交。步骤 1 新增的 6 个双语文档（不同路径）不受影响。`origin` 被 filter-repo 删除。
4. **重加远端 + 重命名分支 + rebase 到最新 202605：**
   ```
   git remote add sonic-net https://github.com/sonic-net/sonic-buildimage.git
   git remote add canonical  git@github.com:canonical/sonic-buildimage.git
   git fetch sonic-net
   git branch -m 202605-wip 202605_resolute_doc
   git rebase --onto sonic-net/202605 77cfa809d 202605_resolute_doc
   ```
   预期 ~0 冲突（文档不碰 submodule 指针或 build 文件）。
5. **推送：** `git push canonical 202605_resolute_doc`

## 6. 子模块分支 —— `202605_resolute`（×14）

**顺序：** 子模块 rebase（§6.1）发生在超仓库 rebase（§4 步骤 5）**之前**，因为超仓库 gitlink 冲突解决需要 rebase 后的 build-commit sha。

### 6.1 rebase 2 个 base 被上游 bump 的子模块

仅 `sonic-dash-ha` 和 `sonic-sairedis`——其 `build:` 提交的 parent **不是** 202605 gitlink lock（上游 bump 越过了它）：

| 子模块 | 202605 lock | build 提交 | build parent |
|---|---|---|---|
| src/sonic-dash-ha | `dec02a5d` | `b336da3` | `07201f08` |
| src/sonic-sairedis | `cec72ecc` | `68da16e5` | `9fc3fb4d` |

在每个子模块工作目录下：
```
git fetch origin
git checkout resolute            # 或 build commit
git rebase --onto <202605-lock> <build-parent> resolute
# 例 dash-ha:  git rebase --onto dec02a5d 07201f08 resolute
```
- 在新 base 上解决 `build:` 提交里的冲突（dash-ha 的 Cargo.lock；sairedis 的 SAI/Doxyfile）。
- 记录**新 rebase 后的 build-commit sha**——超仓库 gitlink（§4 步骤 5）和下面的推送用这个新 sha。
- 其余 12 个子模块已坐在 202605 lock 上（build parent == lock）——不 rebase，直接推现有 build 提交。

### 6.2 推送每个子模块的 `202605_resolute` 分支

对 14 个子模块的每一个，在其工作目录 `~/sonic-buildimage-resolute/<子模块>` 下：

1. **添加 canonical 远端**（SSH）：
   ```
   git remote add canonical git@github.com:canonical/<repo>.git
   ```
   - 7 个已存在 repo：远端立即可用（push=True）。
   - 7 个缺失 repo：**先 fork**——`gh repo fork sonic-net/<repo> --org canonical --remote=false`（然后手动加 canonical 远端）。xdqi 有 org 级建 repo 权限（已确认），fork 到 org 预期能成；仍先试一个。
2. **推送构建分支**（不 `--force`；新分支）：
   ```
   git push canonical <build-commit-sha>:refs/heads/202605_resolute
   ```
   2 个 rebase 过的子模块，`<build-commit-sha>` = §6.1 的新 sha。其余 12 个用现有 build 提交 sha。git 接受无共同祖先的新分支 ref（§2 已验证）。

### 子模块 repo → build 提交映射
| canonical repo | build 提交 | rebase? |
|---|---|---|
| canonical/sonic-swss | `6d3a46bb` | 否 |
| canonical/sonic-sairedis | （§6.1 rebase 到 `cec72ecc` 后的新 sha） | **是** |
| canonical/sonic-swss-common | `baf0b19` | 否 |
| canonical/sonic-gnmi | `c8f96ff` | 否 |
| canonical/sonic-mgmt-framework | `fda49ff` | 否 |
| canonical/sonic-linux-kernel | `c54d5e3` | 否 |
| canonical/sonic-mgmt-common | `47995eb` | 否 |
| canonical/sonic-platform-vpp（fork） | `fe8c727` | 否 |
| canonical/sonic-dhcp-relay（fork） | `d620ecc` | 否 |
| canonical/sonic-bmp（fork） | `c11289b` | 否 |
| canonical/sonic-dash-ha（fork） | （§6.1 rebase 到 `dec02a5d` 后的新 sha） | **是** |
| canonical/sonic-dash-api（fork） | `43c676b` | 否 |
| canonical/sonic-stp（fork） | `416491c` | 否 |
| canonical/sonic-wpa-supplicant（fork） | `7f39eb03f` | 否 |

## 7. `.gitmodules` URL 改写 + 子模块工作目录对齐

子模块分支推上去后（§6.2），超仓库构建分支 `202605_resolute` 必须把 gitlink 指向 canonical，而非 sonic-net。**就地**在 `~/sonic-buildimage-resolute`（§4 步骤 6 后已在 `202605_resolute`）上做，§4 步骤 5 rebase 之后：

1. **改写 `.gitmodules`**——对 14 个子模块，把 `url = https://github.com/sonic-net/<repo>.git` 改为 `git@github.com:canonical/<repo>.git`。用 `git config -f .gitmodules submodule.<path>.url <new>`（或 sed）。
2. **同步 config：** `git submodule sync`（把 `.gitmodules` URL 传播到 `.git/config`）。
3. **对齐子模块工作目录到新 gitlink**——§4 rebase 后，gitlink 可能指向工作目录未检出的 commit（尤其 2 个 rebase 过的子模块）。把每个子模块 checkout 到其记录的 gitlink：
   ```
   git submodule update --recursive --no-fetch   # 用本地子模块 commit
   ```
   对 2 个 rebase 过的子模块（dash-ha、sairedis），这会检出 rebase 后的新 build commit。其余 12 个若已在 build commit 上则 no-op。这使 `git status` 干净——**回答"原仓库能回到正确分支吗"**：能，`~/sonic-buildimage-resolute` 最终停在 `202605_resolute`，所有子模块对齐其 gitlink。
4. **提交 `.gitmodules` 改动：**
   ```
   git commit -am "build: point submodules at canonical resolute branches"
   ```
5. **重新推送超仓库构建分支：** `git push canonical 202605_resolute --force-with-lease`（force-with-lease 因为这改写了刚推上去的 tip）。

⚠️ 其他子模块（无 resolute 提交）仍指向 sonic-net——只有 14 个有 build 提交的迁到 canonical。

### 原仓库最终状态
| 仓库 | 执行后分支 | HEAD 对齐 |
|---|---|---|
| `~/sonic-buildimage-resolute` | `202605_resolute`（从 `resolute` 重命名） | canonical `202605_resolute`，子模块检出至 gitlink |
| `~/sonic-buildimage` | `202605_resolute_doc`（从 `202605-wip` 重命名） | canonical `202605_resolute_doc` |
| 14 个子模块工作目录 | 在各自 build commit 上（2 个 rebase 过，12 个原样） | canonical `<repo>` `202605_resolute` |

两个原仓库现在和 canonical 同分支名——以后提交直接推，不再 re-filter。

## 8. 风险与缓解

- **R1 ⚠️ 不可逆就地历史改写** —— `filter-repo --force` 直接改写 `~/sonic-buildimage-resolute` 和 `~/sonic-buildimage`，永久改变所有提交哈希并删除 `origin`。缓解：改写前可选安全 tag（`pre-filter-resolute`、`pre-filter-docs`）；canonical 推上去的分支成为持久副本。**filter-repo 每个 repo 只跑一次**——以后提交落在重命名后的分支上，直接推，不再 re-filter。
- **R2 gitlink 冲突（`sonic-dash-ha`、`sonic-sairedis`）** → 通过在超仓库 rebase **之前**把各子模块 `build:` 提交 rebase 到其 202605 gitlink lock（§6.1）来解决；超仓库 gitlink 随后指向新 rebase 后的 build commit（§4 步骤 5）。`dhcpmon`（无 resolute build 提交）取 202605 的指针。
- **R3 canonical `admin=False`** → 不能改设置/保护，但能推新分支。新分支名默认无保护规则。
- **R4 `.gitmodules` 改写改写超仓库 tip** → 重新推送用 `--force-with-lease`；只影响超仓库构建分支，且只一次。
- **R5 fork 到 org** —— xdqi 有 org 级建 repo 权限（用户已确认），所以 7 个缺失 repo 的 `gh repo fork --org canonical` 预期能成。仍先试一个 fork 作 sanity check。
- **R6 已存在的 7 个 canonical repo 是分叉的** → 它们陈旧的 `master`/`202012` 等分支不受影响。只新增 `202605_resolute` 分支。同事 fetch 子模块时拿到 resolute 提交 + 其完整 sonic-net 祖先（在新分支上完整可达）。
- **R7 子模块 rebase 冲突** —— 把 `b336da3`（dash-ha，Cargo.lock）和 `68da16e5`（sairedis，SAI/Doxyfile）rebase 到新 202605 lock 可能遇冲突；两者都小（1 和 3 文件）。按 build 提交意图解决；rebase 后的结果即推送内容。
- **R8 rebase 后子模块工作目录错位** —— 超仓库 gitlink 指向新 commit，但工作目录滞后。由 §7 步骤 3 `git submodule update --recursive --no-fetch` 缓解；推送前验证 `git status` 干净。

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
- **原仓库对齐：** `~/sonic-buildimage-resolute` HEAD 在 `202605_resolute`，`~/sonic-buildimage` HEAD 在 `202605_resolute_doc`；`git -C ~/sonic-buildimage-resolute status` 干净（§7 步骤 3 后无 dirty 子模块）。
- 分支可见于 `github.com/canonical/sonic-buildimage/tree/202605_resolute`、`/tree/202605_resolute_doc`，及各 `canonical/<子模块>/tree/202605_resolute`。
