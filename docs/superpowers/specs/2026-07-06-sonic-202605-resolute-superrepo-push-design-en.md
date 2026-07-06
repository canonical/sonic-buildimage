# SONiC 202605 Resolute — Super-Repository Branch Upload (Design)

- **Date:** 2026-07-06
- **Scope:** Super-repository (`sonic-buildimage`) only. Submodules explicitly deferred (§7).
- **Target remote:** `canonical/sonic-buildimage` — GitHub fork of `sonic-net/sonic-buildimage`. Account `xdqi` has `push=True`, `admin=False`.

## 1. Goal

Upload the resolute migration work currently held in two local repositories to `canonical/sonic-buildimage` as **two independent branches**, so the team can see and build from them:

- **`202605-resolute`** — the build branch: all resolute build commits, with **zero** superpowers documentation.
- **`202605-resolute-docs`** — the docs branch: all migration design / plan / review / catalog / report documentation (bilingual zh+en + PPTX).

Both branches rebased onto the **latest upstream `202605`** (`sonic-net/sonic-buildimage` HEAD `9c84048a4`).

## 2. Current state (verified 2026-07-06)

### Source repositories
| Repo | Branch | Ahead of merge-base | Notes |
|---|---|---|---|
| `~/sonic-buildimage-resolute` | `resolute` | 70 commits | 5 touch `docs/superpowers/`; 65 pure build. Uncommitted: `Dockerfile.j2` boost 1.88→1.83 (carry over). |
| `~/sonic-buildimage` | `202605-wip` | 7 commits | All docs-only. Pending reorg: delete 2 old single-language docs, add 6 bilingual `.md` (3 topics × en/zh). `.pptx`, `.pptx.md`, and `sonic.code-workspace` are gitignored, not committed. |

Superpowers paths committed in the `resolute` branch (5 files, all under `docs/superpowers/`):
- `plans/done-bar-status.txt`, `plans/fips-status.txt`
- `specs/2026-07-05-resolute-variant-naming-design.md`, `specs/category-c-catalog-en.md`, `specs/category-c-catalog-zh.md`

The 5 docs commits are **interleaved** with the 65 build commits (e.g. `93f1fe2a2 docs: Goal-2 Category-C catalog` sits between `8f4fc81ed` and `5e29f4bcd`).

### Target remote
- `canonical/sonic-buildimage`: fork of `sonic-net/sonic-buildimage`; has a `202605` branch.
- `xdqi` push=True (can push branches), admin=False (cannot change settings/protection).
- canonical's `202605` HEAD = `77cfa809d` (= the merge-base; canonical is 3 commits behind sonic-net).
- sonic-net `202605` HEAD = `9c84048a4`.

### Upstream distance
- 3 commits between merge-base `77cfa809d` and sonic-net latest `9c84048a4`, **all automated submodule bumps**: `sonic-dash-ha` (#28234), `dhcpmon` (#28232), `sonic-sairedis` (#28242).
- Upstream `202605` contains **no** `docs/superpowers/` content → `filter-repo` leaves the shared base commits untouched (hashes preserved, merge-base stays `77cfa809d`).

## 3. Decisions

| # | Decision | Choice | Rationale |
|---|---|---|---|
| D1 | Rebase base | sonic-net latest `202605` (`9c84048a4`) | User said "latest 202605"; the 3 upstream bumps are harmless; 2 mechanical submodule-pointer conflicts are acceptable. |
| D2 | Docs scrubbing tool | `git filter-repo --path docs/superpowers --invert-paths` | The 5 docs commits are interleaved with 65 build commits — interactive rebase-drop would require editing 70 todos. Path-based scrub is the only clean option, and it removes the path from every commit's tree (true "thorough cleanup"). |
| D3 | Workspace model | fresh non-recursive clone | `filter-repo` refuses non-fresh clones without `--force` and removes `origin`. The original `~/sonic-buildimage-resolute` (16 submodules + uncommitted Dockerfile change) must not be touched. |
| D4 | `.pptx` and `.pptx.md` | gitignore, not committed | Generated presentation artifacts; user decision 2026-07-06. Only the bilingual `.md` docs are committed. |
| D5 | `sonic.code-workspace` | gitignore, not committed | VSCode personal workspace file. |

## 4. Branch A — `202605-resolute` (build)

All steps run in a **fresh clone**; the original `~/sonic-buildimage-resolute` is never modified.

1. **Install filter-repo:** `sudo apt install git-filter-repo` (Debian package `2.47.0-3`; passwordless sudo available).
2. **Fresh non-recursive clone** (preserves the 70 local commits; no submodule checkout needed for a super-repo history rewrite):
   ```
   git clone --branch resolute --no-recursive /home/sheldon-qi/sonic-buildimage-resolute /work/resolute-super
   cd /work/resolute-super
   ```
3. **Scrub superpowers docs from all history:**
   ```
   git filter-repo --path docs/superpowers --invert-paths
   ```
   Removes `docs/superpowers/` from every commit's tree; prunes the ~5 commits that become empty. Base commits (≤ merge-base `77cfa809d`) are unchanged because upstream has no such path. `filter-repo` removes `origin` by default — expected.
4. **Add remotes** (canonical = push target; sonic-net = latest 202605 fetch):
   ```
   git remote add sonic-net https://github.com/sonic-net/sonic-buildimage.git
   git remote add canonical  git@github.com:canonical/sonic-buildimage.git
   git fetch sonic-net
   ```
5. **Rebase onto latest 202605:**
   ```
   git rebase --onto sonic-net/202605 77cfa809d resolute
   ```
   - Replays the filtered resolute commits (those after `77cfa809d`) onto `9c84048a4`.
   - **Expected conflicts:** submodule gitlink pointers for `sonic-dash-ha` and `sonic-sairedis` (both bumped locally in resolute AND upstream). `dhcpmon` applies cleanly (resolute doesn't touch it). No build-file conflicts (the 3 upstream commits touch only gitlinks).
   - **Conflict resolution:** keep resolute's pointer (it points to the local resolute submodule commit). ⚠️ Rebase semantics are counterintuitive — in `git rebase`, "ours" = the new base (`sonic-net/202605`), "theirs" = the commit being replayed (resolute). So resolute's pointer is **"theirs"**: `git checkout --theirs <submodule-path>` then `git add <submodule-path>`.
6. **Rename branch:** `git branch -m resolute 202605-resolute`
7. **Push:** `git push canonical 202605-resolute`

## 5. Branch B — `202605-resolute-docs` (docs)

Steps run in `~/sonic-buildimage` (branch `202605-wip`). No filter-repo needed — this branch is the home for the docs.

1. **Gitignore generated/personal files:** add to `.gitignore` — `sonic.code-workspace`, `*.pptx`, `*.pptx.md`.
2. **Commit the docs reorg:** stage the 2 deletions + the 6 new bilingual `.md` files (3 topics × en/zh) only; commit `docs: reorganize resolute migration docs to bilingual`. Do **not** stage `.pptx`, `.pptx.md`, or `sonic.code-workspace`.
3. **Create the target branch from `202605-wip`** (leaves `202605-wip` untouched as a pre-rebase backup):
   ```
   git checkout -b 202605-resolute-docs
   ```
4. **Rebase onto latest 202605:**
   ```
   git rebase --onto origin/202605 77cfa809d 202605-resolute-docs
   ```
   Primary `origin` = sonic-net (SSH), already at `9c84048a4`. Expected ~0 conflicts (docs don't touch submodule pointers or build files).
5. **Add canonical remote and push:**
   ```
   git remote add canonical git@github.com:canonical/sonic-buildimage.git
   git push canonical 202605-resolute-docs
   ```

## 6. Risks & mitigations

- **filter-repo rewrites all build-branch commit hashes** → originals are safely preserved in `~/sonic-buildimage-resolute`; the fresh clone is disposable.
- **Submodule pointer conflicts (`sonic-dash-ha`, `sonic-sairedis`)** → mechanical; take resolute's pointer (see D2/step 5 caveat on rebase "theirs" semantics).
- **canonical `admin=False`** → cannot change repo settings or branch protection, but CAN push new branches. New branch names have no protection rules by default.
- **Gitlinks point to unreachable submodule commits** → expected. `202605-resolute` is not yet fully cloneable/buildable by colleagues until the 16 submodules' resolute commits are pushed somewhere (out of scope, §7). `git submodule update` will fail for those submodules; this is a known, documented limitation.

## 7. Out of scope

- **Submodules** (16 with resolute commits, ~17 commits total): deferred. The user will assess each submodule's modification volume before deciding the submodule landing strategy. Until then, `202605-resolute` gitlinks point to commits not on any public remote.
- **`~/sonic-buildimage-202605-clone`**: ignored. Verified byte-identical to the primary docs (its ahead-3 commits are duplicates already present in `202605-wip`).
- **Updating canonical's `202605` to sonic-net latest**: not requested. The two new branches are based on sonic-net latest, so they carry the 3 upstream bumps regardless.

## 8. Verification

- `git ls-tree -r 202605-resolute --name-only | grep -i superpowers` → **empty** (build branch has zero superpowers docs).
- `git log --oneline 202605-resolute | grep 'docs:'` → no commit touches `docs/superpowers/`.
- `git merge-base 202605-resolute sonic-net/202605` → `9c84048a4` (sits on latest 202605).
- `git ls-tree -r 202605-resolute-docs --name-only | grep superpowers` → bilingual `.md` docs present; **no** `.pptx` / `.pptx.md`.
- Both branches visible at `github.com/canonical/sonic-buildimage/tree/202605-resolute` and `/tree/202605-resolute-docs`.
