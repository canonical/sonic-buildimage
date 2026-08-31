# sonic-net/sonic-buildimage `202605`: workflow determination, and forensics on a false "history was rewritten" call

Date: 2026-08-31 · Upstream tip: `be4939271e761c4946afead0d78a18c33d97987a`
Raw data: [`data/2026-08-31-sonic-202605-branch-forensics/`](data/2026-08-31-sonic-202605-branch-forensics/)

---

## 1. Conclusions

1. **`202605` runs a strictly linear workflow (predominantly squash-merge), not a merge workflow.**
2. **The branch has never been force-pushed, and has never received a single bare `push`.**
   All 194 changes landed through pull requests.
3. The previously recorded claim that "upstream force-rewrote 202605" is **wrong**, and the culprit
   is now identified: **we ran `git filter-repo --force` in place on both local clones on
   2026-07-06**. It rewrites every commit object and drops GPG signatures, producing a
   signature-stripped history running parallel to upstream's. Nothing happened upstream. See §3.5.
   The corresponding memory has been rewritten.

---

## 2. Determining the workflow

### 2.1 Authoritative source: the GitHub Activity API

```sh
gh api --paginate -X GET 'repos/sonic-net/sonic-buildimage/activity' \
  -f ref=refs/heads/202605 -f per_page=100
```

| Item | Value |
|---|---|
| Total records | 195 |
| Coverage | `2026-06-03T06:10:13Z branch_creation` (mssonicbld, `0000000000 → ea4acb6bc2`) → `2026-08-31T09:13:22Z` |
| `pr_merge` | **194** |
| `branch_creation` | 1 |
| Bare `push` | **0** |
| `force_push` | **0** |

Filter sanity check: the same API against `canonical/sonic-buildimage` does list our own force
pushes (`202605_resolute_rock`, `202605_resolute_real`, …), so the zeros above are real zeros.

**This log is complete, not a sample — proven by chain continuity:** sorting the 195 records by
timestamp and checking `before[i] == after[i-1]` yields **zero gaps**, linking end-to-end from
`branch_creation` (`0000000000 → ea4acb6bc2`) all the way to the tip. Checking each record with
`git merge-base --is-ancestor before after`:

| Verdict | Count |
|---|---|
| Fast-forward | **193** |
| Non-fast-forward | **0** |
| Object missing locally (the newest record, not yet fetched at snapshot time) | 1 |
| Advanced by 1 commit | 183 |
| Advanced by 2 commits (merge commit + side parent) | 10 |

In other words: **since its creation, the `202605` tip has only ever moved forward — never once
rewound or jumped.** Any downstream clone tracking this branch will always `git pull` as a
fast-forward; no `--force`, no `rebase --onto` onto a new base.

> ⚠️ This API retains roughly 90 days. `202605` was created 89 days before this snapshot, so the
> window happens to cover the branch's entire life. For older branches (202511, 202505) the same
> query only returns a truncated window and cannot support the same conclusion.

### 2.2 Shape of the history

From the branch point `ea4acb6bc2` (2026-06-03, `[Broadcom] Bump XGS SAI to 15.2.0 / SDK 6.5.35 (#27465)`)
to the tip: 203 commits.

| Landing method | Count | Signature |
|---|---|---|
| **squash-merge** | **183** | Subject ends in `(#NNNNN)` (GitHub squash appends the PR number); committer = `GitHub <noreply@github.com>` |
| merge commit | 10 | `Merge pull request #290xx from mssonicbld/cherry/202605/2xxxx` |
| brought in by side branches | 10 | each merge's second parent holds **exactly one** commit |

The saved `commits-202605-first-parent.tsv` supplies a stronger corroboration: **all 193 first-parent
commits are GPG-signed, and all 193 have committer `GitHub <noreply@github.com>`**. A bare-pushed
commit could satisfy neither condition, so "zero bare pushes" is not merely an Activity API claim —
the history proves it on its own.

All ten merges happened **within 30 seconds — 2026-08-25 13:19:11 to 13:19:41 — by one person
(Vaibhav Hemant Dixit)**, all on cherry-pick PRs. That is a one-off case of clicking
"Create a merge commit" instead of "Squash and merge", not part of the workflow.

Widening the window to 2026-05-01 (495 commits):

- Committer identity: `GitHub <noreply@github.com>` **485** / `Sonic Build Admin` **10** (the side
  parents of those merges) → **zero bare pushes**
- Non-merge subjects: 474 carry `(#N)`, 11 do not (10 are merge side-parents; one, `822d11c80b`,
  is a rebase-merge — GitHub's "Rebase and merge" does not append the PR number)

### 2.3 Where the content comes from

- **173** × `[submodule] Update submodule X to the latest HEAD automatically (#N)` — the submodule
  auto-bump bot
- **67** carry `Signed-off-by: Sonic Build Admin` — the cherry-pick bot backporting from master via
  `mssonicbld/cherry/202605/<master-PR#>` branches, each opened as its own PR
- The remainder are PRs filed directly against 202605

### 2.4 How to read the push-event table correctly

Provenance: [GH Archive](https://www.gharchive.org/) queried through
[BigQuery](https://console.cloud.google.com/bigquery), public dataset `githubarchive.day.2026*`;
the SQL is preserved in
[`query-gharchive.sql`](data/2026-08-31-sonic-202605-branch-forensics/query-gharchive.sql).

Each of the 35 rows was checked with `git merge-base --is-ancestor before head`:
**35/35 fast-forward, exactly one commit each** — fully consistent with the above.

Actor distribution (= who clicked merge, **not** the author; e.g. `71b53c5e`'s actor is
StormLiangMS while its author is mssonicbld):

`mssonicbld` 23 · `vaibhavhd` 6 · `yxieca(-admin)` 4 · `yijingyan2` 1 · `StormLiangMS` 1

> ⚠️ **That table is a sample, not a log — and the query is not at fault.** Its date range
> (`0401`–`0831`) fully covers the life of 202605 and its `LIMIT 1000` was never approached, yet it
> returns 35 rows against 194 real tip advances — **18% coverage**. The loss is in GitHub's public
> event firehose that GH Archive mirrors.
>
> Cross-check against the Activity API:
>
> - All 35 rows map to real `pr_merge` records (100% precision, zero phantom rows)
> - **None** of the 10 merge-commit advances (+2 commits each) were captured
> - No pattern by UTC hour — every hour shows both captured and dropped events, so it is not a
>   scheduling-window artifact
> - `payload.size` is NULL on every row, so `commit_count` is unusable from this source; the
>   per-push commit counts in this document came from `git rev-list --count <before>..<head>`
>
> Therefore: the many places where `before_sha` fails to match the previous row's `head_sha` are
> **missing rows**, not force pushes. "Every row is a fast-forward" only proves those rows were
> fast-forwards; it **cannot** prove no force push occurred — only the Activity API can.

---

## 3. Forensics on the false "history was rewritten" call

### 3.1 The symptom

On 2026-07-06, the GitHub compare `sonic-net/202605...canonical:202605_resolute` showed 5000+
changes, a merge-base reaching back to 2017-10-26 `437419c79e`, and ~11,400 commits of divergence
in each direction. This was recorded as an upstream force-rewrite.

### 3.2 Three disproofs

**Disproof 1 — the Activity API shows one ordinary merge that day.**
The record for the accused date, 2026-07-05, is `pr_merge 68e952b30f -> 9c84048a42`. `9c84048a42`
is the "new chain" version; the local `7177dca054` (parent `402aa13035`) was never upstream's.

**Disproof 2 — the divergence point is exactly the parent of the repo's first-ever signed commit.**

```
First SIGNED commit : 961a6669f7  2017-10-27  [Broadcom]: Update Broadcom OpenNSL/SAI packages (#1090)
Its parent          : 437419c79e  2017-10-26  ← the "mysterious 2017 divergence point"
```

That is the **mathematically necessary** result of stripping signatures: remove `gpgsig` → every
signed commit's SHA changes → the change cascades to the tip → the last common ancestor must be
precisely the commit before the first signed one. An upstream force push has no reason to diverge
exactly there.

**Disproof 3 — the signature distribution is unnatural.**

| Chain | 2017–2021 | 2022–2026 |
|---|---|---|
| Current `sonic-net/202605` | mostly unsigned | mostly SIGNED |
| Local old chain `7177dca054` | unsigned | **unsigned throughout** |

The current chain is the natural mix of a real repository (early years pushed from the CLI without
signing; from 2022 on, GitHub UI merges are signed with the web-flow key). The old chain has not a
single signature from 2017 to 2026 — no real GitHub repository grows a history like that.

### 3.3 Twin comparison (byte level)

Reading raw objects with `git cat-file commit`, the **only** difference is the `gpgsig` header;
`tree` / `parent` / `author` / `committer` / message are byte-identical.

| Era | Stripped SHA | Signed SHA | tree | Exists on GitHub? |
|---|---|---|---|---|
| 2017 | `e2a863b60a` | `961a6669f7` | both `037ef2153f` | **both** exist |
| 2026 | `7177dca054` | `9c84048a42` | both `1459cc1f91` | stripped one **404s** |

Both 2017 twins resolve on GitHub, which means the stripped history does exist somewhere in the
sonic-buildimage fork network (some fork pushed it at some point) — it is not something unique to
us. The 2026-era stripped commits 404, so those were never on GitHub at all.

### 3.4 How it arrived, and the mechanism

| Observation | Value |
|---|---|
| Arrival time | `sonic-buildimage-resolute`: pack `3293954c…` 8.3 MB @ 2026-07-06 12:44; `sonic-buildimage`: pack `cc1fba7d…` 8.8 MB @ 2026-07-06 14:05 |
| Pack object mix | **commit 18005 / tree 445 / blob 201** — almost purely commit objects |
| Local ref shape | Both clones hold every upstream branch as a **local** branch (`201709`, `201712`, `copilot/*`, `kperumal_202411`, `pre_202211`, …), with reflogs that are **0 bytes, dated 2026-07-21 09:22** → bulk-imported via `packed-refs`, no reflog |
| Remote config | Neither clone has an `origin`; only `sonic-net` and `canonical` |

"A pack that is almost entirely commit objects" is the fingerprint of signature stripping: trees and
blobs are reused verbatim, and only the commit objects change SHA because the signature was removed.

**`git rebase` is ruled out**: rebase rewrites the committer to the local identity, whereas these
unsigned commits still carry committer `GitHub <noreply@github.com>`.

### 3.5 Case closed: we ran `git filter-repo` ourselves on 2026-07-06

`.git/logs/HEAD` preserved the whole day — **206 reflog entries, every one performed by
`Sheldon Qi <sheldon.qi@canonical.com>`**:

```
12:45:35  beb43c9c3a->b23d3e06a1  rebase (start): checkout sonic-net/202605
12:45:35  b23d3e06a1->bdc8aaf9fa  commit (amend): [sonic-buildimage]Install python ipaddress (#2681)
...
14:09:05  820fc72633->820fc72633  rebase (finish): returning to refs/heads/202605_resolute_doc
```

And that day's plan document,
[`plans/2026-07-06-sonic-202605-resolute-superrepo-push-plan-en.md`](plans/2026-07-06-sonic-202605-resolute-superrepo-push-plan-en.md),
spells the action out:

> **Architecture:** **In-place history rewrite** on the two original repos
> (`~/sonic-buildimage-resolute`, `~/sonic-buildimage`) **via `git filter-repo --force`** to scrub
> superpowers docs, then rebase onto sonic-net latest `202605`…
>
> **Irreversible.** `filter-repo --force` rewrites **all commit hashes** in both repos and
> **deletes `origin`**.

Two filter-repo passes actually ran: `--path docs/superpowers --invert-paths` (prune the docs
directory) and `--force --mailmap` (remap the mistakenly-configured `@local` identities to
`Sheldon Qi <sheldon.qi@canonical.com>`).

**`git filter-repo` preserves author and committer but does not carry `gpgsig` through** (it is
built on fast-export/fast-import, and a rewritten commit's signature would be invalid anyway).
Every observation closes at once:

| Observation | Explained by filter-repo |
|---|---|
| Packs at 12:44 / 14:05, immediately followed by reflog at 12:45:35 / 14:09:05 | filter-repo writes the new object store, then the rebase starts |
| 18005 commits / 445 trees / 201 blobs | **every** commit object rewritten; only one directory pruned, so trees/blobs barely move |
| Divergence lands exactly on the first signed commit | unchanged commits rewrite byte-identically → same SHA; the first thing that actually *changes* along the timeline is the first `gpgsig` |
| Committer still `GitHub <noreply@github.com>` | filter-repo preserves committer (the mailmap only remapped `@local` identities) |
| Neither repo has an `origin` | filter-repo **deletes origin** and converts remote-tracking refs into local refs |
| All upstream branches present as local branches, 0-byte reflogs | same — `refs/remotes/origin/*` → `refs/heads/*`, written via `packed-refs` |
| The 2017 stripped twin `e2a863b60a` **resolves** on GitHub | the filtered branches were pushed that day to `canonical/sonic-buildimage` (`fork=true`, `parent=sonic-net/sonic-buildimage`) — same fork network, so the object is still reachable |
| The 2026 stripped tips `7177dca054` / `67a348840b` **404** | those only ever existed on local refs and were never pushed anywhere |

So the "upstream force-pushed on 2026-07-06" reading had the causality backwards: we were the ones
who rewrote history, and only in two local clones. Upstream did nothing that day beyond one
ordinary `pr_merge 68e952b30f -> 9c84048a42`.

### 3.6 Practical impact: none

Every working branch is based on the **signed** chain (the base was moved back to the true
merge-base `ba3fb8d5f5` on 2026-08-17):

| Branch | merge-base with upstream | Signature |
|---|---|---|
| `202605_resolute` | `9c84048a42` (2026-07-05) | SIGNED |
| `202605_resolute_sheldon` | `ba3fb8d5f5` (2026-07-26) | SIGNED |
| `canonical/202605_resolute` | `ba3fb8d5f5` | SIGNED |
| `canonical/202605_resolute_sheldon` | `ba3fb8d5f5` | SIGNED |

The unsigned chain hangs off a few stale local refs only (`refs/heads/202605`,
`refs/remotes/sonicnet-202605`, some `copilot/*`) and participates in no build or push. They can be
deleted, but there is no need — keeping them preserves the evidence behind this document.

---

## 4. Method notes worth keeping

1. **Use the Activity API to judge force pushes, not a push-event table.** The table is a sample;
   it can only prove that the sampled rows were fast-forwards.
2. **Compare commits at the raw-object level** with `git cat-file commit <sha>`. `git log` does not
   show `gpgsig`, so two commits differing only by a signature look identical while having different
   SHAs — the perfect setup for misreading it as "upstream rewrote history".
3. **"merge-base falls back to antiquity + tens of thousands of commits diverged" is not a
   conclusion.** First check whether the divergence point lands exactly on a structural boundary
   (the first signed commit, a GPG/GPGSM change, an encoding change, …); then read
   `.git/logs/HEAD` for what **you** did at that timestamp. That is how this case was closed.
6. **`git filter-repo` silently drops GPG signatures, deletes `origin`, and turns remote-tracking
   refs into local branches.** Running it in place on a repo whose upstream history is signed
   manufactures a parallel history that can never line up with upstream again. Either run it in a
   throwaway clone, or immediately re-`fetch` upstream afterwards and rebase onto the upstream ref.
4. **`git verify-pack -v` object-type distribution reveals a replayed history at a glance**: almost
   purely commit objects means only the commit headers changed and all trees/blobs were reused.
5. **An empty tree-diff means the fix is risk-free.** When `git diff OLD NEW` is empty,
   `git rebase --onto NEW_BASE OLD_BASE mybranch` is conflict-free; verify with
   `git rev-list --count mybranch..NEW_BASE` == 0.

---

## 5. Did upstream ever say anything?

No — and there was nothing to say, because no such event occurred. Searched:

- `gh search issues 'force push' --repo sonic-net/sonic-buildimage` → empty
- `gh search issues 'rewrite history' --repo sonic-net/sonic-buildimage` → empty
- The only 202605-related issue in `sonic-net/SONiC` is
  [#2169 Container upgrades to Trixie](https://github.com/sonic-net/SONiC/issues/2169), unrelated
- Web search surfaced no announcement of any kind
