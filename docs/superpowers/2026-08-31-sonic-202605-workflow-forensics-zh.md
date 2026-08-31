# sonic-net/sonic-buildimage `202605` 分支：工作流认定与「历史被重写」误判的取证

日期：2026-08-31　　上游 tip：`be4939271e761c4946afead0d78a18c33d97987a`
原始数据：[`data/2026-08-31-sonic-202605-branch-forensics/`](data/2026-08-31-sonic-202605-branch-forensics/)

---

## 一、结论

1. **`202605` 是纯线性工作流（squash-merge 为主），不是 merge 工作流。**
2. **该分支自建立以来从未被 force-push，也从未有过一次裸 `push`。** 194 次变更 100% 经 PR 落地。
3. 此前记录的「上游 force-rewrite 202605」是**误判**，且真凶已结案：
   **是我们自己在 2026-07-06 对两个本地 clone 就地跑了 `git filter-repo --force`**，
   它重写全部 commit 对象并丢弃 GPG 签名，从而造出一条与上游平行的无签名历史。
   上游侧一动没动。详见 §3.5。相关记忆已重写。

---

## 二、工作流认定

### 2.1 权威来源：GitHub Activity API

```sh
gh api --paginate -X GET 'repos/sonic-net/sonic-buildimage/activity' \
  -f ref=refs/heads/202605 -f per_page=100
```

| 项 | 值 |
|---|---|
| 记录总数 | 195 |
| 覆盖范围 | `2026-06-03T06:10:13Z branch_creation`（mssonicbld，`0000000000 → ea4acb6bc2`）→ `2026-08-31T09:13:22Z` |
| `pr_merge` | **194** |
| `branch_creation` | 1 |
| 裸 `push` | **0** |
| `force_push` | **0** |

过滤器有效性对照：同一 API 查 `canonical/sonic-buildimage` 能正常列出我们自己的 force_push 记录
（`202605_resolute_rock`、`202605_resolute_real`…），所以上面的 0 是真的 0。

**这份日志是完备的，不是抽样——已用链条连续性证明：** 把 195 条按时间排序后逐条验
`before[i] == after[i-1]`，**断点 0 处**，从 `branch_creation`（`0000000000 → ea4acb6bc2`）
一路首尾相接到 tip。再逐条验 `git merge-base --is-ancestor before after`：

| 判定 | 数量 |
|---|---|
| 快进 | **193** |
| 非快进 | **0** |
| 对象本地缺失（最新一条，快照时尚未 fetch） | 1 |
| 单次推进 1 个 commit | 183 |
| 单次推进 2 个 commit（merge commit + 侧父） | 10 |

也就是说：**`202605` 从建立至今，分支 tip 只做过快进，一次都没有回退或跳变。**
任何下游跟踪该分支的 clone，`git pull` 永远是 fast-forward，不需要 `--force`，
也不需要 `rebase --onto` 换基座。

> ⚠️ 该 API 保留窗口约 90 天。`202605` 建于 89 天前，纯属**刚好**全覆盖。换成 202511 / 202505
> 这类更老的分支，这一招只能看到被截断的窗口，不能下同样的结论。

### 2.2 历史形状

分支点 `ea4acb6bc2`（2026-06-03，`[Broadcom] Bump XGS SAI to 15.2.0 / SDK 6.5.35 (#27465)`）到 tip 共 203 个 commit：

| 落地方式 | 数量 | 特征 |
|---|---|---|
| **squash-merge** | **183** | 标题以 `(#NNNNN)` 结尾（GitHub squash 会追加 PR 号），committer = `GitHub <noreply@github.com>` |
| merge commit | 10 | `Merge pull request #290xx from mssonicbld/cherry/202605/2xxxx` |
| 侧分支带入 | 10 | 每个 merge 的第二父**恰好 1 个 commit** |

落盘的 `commits-202605-first-parent.tsv` 给出一个更强的旁证：**193 个 first-parent commit 100% 带 GPG 签名，
且 committer 100% 是 `GitHub <noreply@github.com>`**。裸推的 commit 不可能同时满足这两条，
所以「零裸推」不只是 Activity API 的说法，历史本身就自证了。

那 10 个 merge 全部发生在 **2026-08-25 13:19:11 – 13:19:41 的 30 秒内，同一人（Vaibhav Hemant Dixit）**，
对象全是 cherry-pick PR。这是一次性点错按钮（"Create a merge commit" 而非 "Squash and merge"），
不是工作流的一部分。

把窗口放宽到 2026-05-01（495 个 commit）再看：

- committer 身份：`GitHub <noreply@github.com>` **485** / `Sonic Build Admin` **10**（就是那 10 个 merge 的侧父）→ **零裸推**
- 非 merge 标题：474 个带 `(#N)`，11 个不带（10 个是 merge 侧父，1 个 `822d11c80b` 是 rebase-merge，
  GitHub 的 "Rebase and merge" 不追加 PR 号）

### 2.3 内容来源

- **173** 个 `[submodule] Update submodule X to the latest HEAD automatically (#N)` —— 子模块自动 bump bot
- **67** 个带 `Signed-off-by: Sonic Build Admin` —— cherry-pick bot 从 master 回合，
  走 `mssonicbld/cherry/202605/<master-PR#>` 分支，每个开独立 PR
- 其余为直接针对 202605 提的 PR

### 2.4 push 事件表的正确用法

数据来源：[GH Archive](https://www.gharchive.org/) 经
[BigQuery](https://console.cloud.google.com/bigquery) 公共数据集 `githubarchive.day.2026*`
查询而得，SQL 见 [`query-gharchive.sql`](data/2026-08-31-sonic-202605-branch-forensics/query-gharchive.sql)。

35 行逐行验 `git merge-base --is-ancestor before head`：**35/35 是快进，每次恰好 1 个 commit**，
与上面完全一致。

actor 分布（= 点合并按钮的人，**不是**作者；例如 `71b53c5e` 的 actor 是 StormLiangMS 而 author 是 mssonicbld）：

`mssonicbld` 23 · `vaibhavhd` 6 · `yxieca(-admin)` 4 · `yijingyan2` 1 · `StormLiangMS` 1

> ⚠️ **这份表是抽样，不是日志——而且不是 SQL 写少了。** 那条查询的时间范围
> （`0401`–`0831`）完整覆盖了 202605 的整个生命周期，`LIMIT 1000` 也远未触及，
> 结果仍只有 35 行，而真实的 tip 推进有 194 次 —— **覆盖率 18%**。
> 缺失发生在 GH Archive 所镜像的 GitHub 公开事件流本身。
>
> 与 Activity API 交叉比对的结果：
>
> - 35 行**全部**能对应到真实的 `pr_merge` 记录（精确率 100%，无幽灵行）
> - 10 次 merge commit 推进（一次 +2 commit）**一条都没被捕获**
> - 按 UTC 小时分布看不出规律（各时段都有捕获与丢失），不是定时窗口造成的
> - `payload.size` 全部为 NULL，`commit_count` 从这个来源取不到；本文的每次推进 commit 数
>   是从 git 侧 `git rev-list --count <before>..<head>` 算出来的
>
> 所以：表里大量 `before_sha` 对不上前一行 `head_sha`，原因是**缺行**而非 force-push；
> 「逐行都是快进」只能说明这些行是快进，**证明不了区间内没强推**——那要靠 Activity API。

---

## 三、「历史被重写」误判的取证

### 3.1 现象

2026-07-06 曾观察到 `sonic-net/202605...canonical:202605_resolute` 的 GitHub compare 显示 5000+ changes、
merge-base 退回 2017-10-26 `437419c79e`、双向各差约 11400 commit，当时判定为上游 force-rewrite。

### 3.2 三条证伪

**证据一 —— Activity API 里那天只有一次正常合并。**
被指控的 2026-07-05 当天记录是 `pr_merge 68e952b30f -> 9c84048a42`。`9c84048a42` 正是「新链」版本；
本地那个 `7177dca054`（parent 是 `402aa13035`）从来不是上游的东西。

**证据二 —— 分叉点恰好是「本仓库史上第一个 GPG 签名 commit 的父节点」。**

```
第一个 SIGNED commit : 961a6669f7  2017-10-27  [Broadcom]: Update Broadcom OpenNSL/SAI packages (#1090)
它的 parent          : 437419c79e  2017-10-26  ← 就是那个「神秘的 2017 分叉点」
```

这是剥签名的**数学必然结果**：剥掉 `gpgsig` → 每个签名 commit 的 SHA 改变 → 级联到 tip →
最后一个共同祖先必然正好落在第一个签名 commit 的前一个。上游强推没有理由恰好分叉在这里。

**证据三 —— 签名分布不自然。**

| 链 | 2017–2021 | 2022–2026 |
|---|---|---|
| 当前 `sonic-net/202605` | 多数 unsigned | 基本 SIGNED |
| 本地旧链 `7177dca054` | unsigned | **全程 unsigned** |

当前链是真实历史的自然混合（早年 CLI 直推不签名，2022 后 GitHub UI merge 用 web-flow key 签名）；
旧链 2017→2026 一个签名都没有——真实 GitHub 仓库长不出这种历史。

### 3.3 孪生对照（逐字节）

`git cat-file commit` 直接看原始对象，两者**唯一差异是 `gpgsig` 头**，`tree`/`parent`/`author`/
`committer`/message 全部逐字相同：

| 年代 | 无签名 SHA | 有签名 SHA | tree | GitHub 上存在? |
|---|---|---|---|---|
| 2017 | `e2a863b60a` | `961a6669f7` | 同为 `037ef2153f` | 两者**都**存在 |
| 2026 | `7177dca054` | `9c84048a42` | 同为 `1459cc1f91` | 无签名的 **404** |

2017 那对**两个都能在 GitHub 上查到**，说明剥签名的历史确实存在于 sonic-buildimage 的 fork network
里（某个 fork 曾推送过），并非我们独有的产物。而 2026 年份的无签名 commit 404，说明它们从未上过 GitHub。

### 3.4 落地方式与机制

| 观察 | 数值 |
|---|---|
| 引入时刻 | `sonic-buildimage-resolute`: pack `3293954c…` 8.3 MB @ 2026-07-06 12:44；`sonic-buildimage`: pack `cc1fba7d…` 8.8 MB @ 2026-07-06 14:05 |
| pack 对象构成 | **commit 18005 / tree 445 / blob 201** —— 几乎纯 commit 对象 |
| 本地 ref 形态 | 两个仓库都把上游全部分支作为**本地分支**持有（`201709`、`201712`、`copilot/*`、`kperumal_202411`、`pre_202211`…），reflog 全是 **0 字节、时间 2026-07-21 09:22** → 经 `packed-refs` 批量导入，无 reflog |
| remote 配置 | 两仓库**都没有 `origin`**，只有 `sonic-net` 和 `canonical` |

「pack 里几乎只有 commit 对象」正是剥签名的指纹：tree/blob 完全复用，只有 commit 对象因签名被去掉而改变 SHA。

**`git rebase` 可以排除**：rebase 会把 committer 改成本地身份，而这些无签名 commit 的 committer
仍然是 `GitHub <noreply@github.com>`。

### 3.5 结案：是 2026-07-06 我们自己跑的 `git filter-repo`

`.git/logs/HEAD` 保留了那天的全部痕迹——**206 条 reflog，执行者全部是
`Sheldon Qi <sheldon.qi@canonical.com>`**：

```
12:45:35  beb43c9c3a->b23d3e06a1  rebase (start): checkout sonic-net/202605
12:45:35  b23d3e06a1->bdc8aaf9fa  commit (amend): [sonic-buildimage]Install python ipaddress (#2681)
...
14:09:05  820fc72633->820fc72633  rebase (finish): returning to refs/heads/202605_resolute_doc
```

而当天的计划文档
[`plans/2026-07-06-sonic-202605-resolute-superrepo-push-plan-zh.md`](plans/2026-07-06-sonic-202605-resolute-superrepo-push-plan-zh.md)
把动作写得一清二楚：

> **Architecture:** 在两个原仓库（`~/sonic-buildimage-resolute`、`~/sonic-buildimage`）上
> **就地用 `git filter-repo --force`** 清除 superpowers 文档，再 rebase 到 sonic-net 最新 `202605`…
>
> **不可逆。** `filter-repo --force` 重写两个仓库**所有提交哈希**并**删除 `origin``**。

实际执行了两轮 filter-repo：`--path docs/superpowers --invert-paths`（剪文档目录）和
`--force --mailmap`（把误设的 `@local` 身份改成 `Sheldon Qi <sheldon.qi@canonical.com>`）。

**`git filter-repo` 保留 author 和 committer，但不携带 `gpgsig`**（它底层走 fast-export/fast-import，
重写后的签名本就失效）。所有观察一次性闭合：

| 观察 | filter-repo 的解释 |
|---|---|
| pack 时间 12:44 / 14:05，紧接 reflog 12:45:35 / 14:09:05 | filter-repo 先写出新对象库，随后立即 rebase |
| 18005 commit / 445 tree / 201 blob | 重写**全部** commit 对象；只剪掉一个目录，故 tree/blob 几乎不动 |
| 分叉点恰好在第一个签名 commit | 未变的 commit 重写后逐字节相同 → SHA 不变；沿时间轴第一个**发生变化**的东西就是第一个 `gpgsig` |
| committer 仍是 `GitHub <noreply@github.com>` | filter-repo 保留 committer（mailmap 只映射 `@local` 身份） |
| 两仓库都没有 `origin` | filter-repo **删除 origin**，并把 remote-tracking ref 转成本地 ref |
| 上游全部分支变成本地分支、reflog 0 字节 | 同上——`refs/remotes/origin/*` → `refs/heads/*`，经 `packed-refs` 写入 |
| 2017 无签名孪生 `e2a863b60a` 在 GitHub 上**可达** | 当天把 filter-repo 后的分支推到了 `canonical/sonic-buildimage`（`fork=true`，`parent=sonic-net/sonic-buildimage`），同一 fork network，对象至今可达 |
| 2026 无签名 tip `7177dca054`/`67a348840b` **404** | 这两个只停在本地 ref 上，从未推出去 |

所以「2026-07-06 上游 force-push 了」这个判断，**因果是反的**：那天动手的是我们自己，
被改写的是本地两个 clone，上游一动没动（当天 Activity 只有一条正常的
`pr_merge 68e952b30f -> 9c84048a42`）。

### 3.6 实务影响：无

所有工作分支的基座都在**有签名的正链**上（2026-08-17 已把 base 挪回真 merge-base `ba3fb8d5f5`）：

| 分支 | 与上游的 merge-base | 签名 |
|---|---|---|
| `202605_resolute` | `9c84048a42` (2026-07-05) | SIGNED |
| `202605_resolute_sheldon` | `ba3fb8d5f5` (2026-07-26) | SIGNED |
| `canonical/202605_resolute` | `ba3fb8d5f5` | SIGNED |
| `canonical/202605_resolute_sheldon` | `ba3fb8d5f5` | SIGNED |

无签名链只挂在几个陈旧的本地 ref 上（`refs/heads/202605`、`refs/remotes/sonicnet-202605`、
若干 `copilot/*`），不参与任何构建或推送。可以删，但没有必要——留着还能作为本文的证物。

---

## 四、方法论沉淀

1. **判 force-push 用 Activity API，不要用 push 事件表。** 事件表是抽样，只能证明「这些行是快进」。
2. **比对 commit 差异要看原始对象** `git cat-file commit <sha>`。`git log` 不显示 `gpgsig`，
   会让「只差签名」的两个 commit 看起来完全一样却 SHA 不同，极易误判为「上游重写」。
3. **看到「merge-base 退回远古 + 双向上万 commit」先别下结论。** 先检查分叉点是不是恰好落在
   某个结构性边界上（第一个签名 commit、第一个 GPG/GPGSM 变更、字符编码变更…）；
   再翻 `.git/logs/HEAD` 看那个时间点**自己**干了什么。本案就是这样结的案。
6. **`git filter-repo` 会静默丢掉 GPG 签名，并删除 `origin`、把 remote-tracking ref 转成本地 ref。**
   在有上游签名历史的仓库上就地跑 filter-repo，等于给自己造一条永远对不上上游的平行历史。
   要么在一次性的克隆里跑，要么跑完立刻重新 `fetch` 上游并以上游 ref 为准 rebase。
4. **`git verify-pack -v` 的对象类型分布能一眼看出「重放型」历史**：几乎纯 commit 对象 = 只有
   commit 头变了，tree/blob 全复用。
5. **tree-diff 为空 = 修复零风险。** `git diff OLD NEW` 无差异时，
   `git rebase --onto NEW_BASE OLD_BASE mybranch` 零冲突，验证 `git rev-list --count mybranch..NEW_BASE` 必须为 0。

---

## 五、上游是否有过说明

没有，也不需要——因为没有可说明的事件。已检索：

- `gh search issues 'force push' --repo sonic-net/sonic-buildimage` → 空
- `gh search issues 'rewrite history' --repo sonic-net/sonic-buildimage` → 空
- `sonic-net/SONiC` 中 202605 相关 issue 仅 [#2169 Container upgrades to Trixie](https://github.com/sonic-net/SONiC/issues/2169)，与此无关
- Web 检索无任何相关公告
