# SONiC 202605 Resolute — Super-Repo + Submodule Upload Plan (EN)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upload the resolute migration work to `canonical/` — super-repo build/docs branches + 14 submodule branches — so the team can clone and reproduce the resolute `vs` build.

**Architecture:** In-place history rewrite on the two original repos (`~/sonic-buildimage-resolute`, `~/sonic-buildimage`) via `git filter-repo --force` to scrub superpowers docs, then rebase onto sonic-net latest `202605` (`9c84048a4`), rename branches to `202605_resolute` / `202605_resolute_doc`, and push to `canonical/`. 14 submodule `build:` commits pushed as new `202605_resolute` branches (2 rebased onto their 202605 gitlink lock first; 7 existing canonical repos get direct push; 7 missing repos forked from sonic-net first). Finally rewrite `.gitmodules` to point the 14 submodules at canonical.

**Tech Stack:** git, git-filter-repo, gh CLI (authenticated as `xdqi`, canonical org member with repo-creation permission).

## Global Constraints

- **Irreversible.** `filter-repo --force` rewrites all commit hashes and removes `origin` on `~/sonic-buildimage-resolute` and `~/sonic-buildimage`. Safety tags (`pre-filter-resolute`, `pre-filter-docs`) are created first.
- **Rebase base** for both super branches = sonic-net `202605` HEAD `9c84048a4` (merge-base `77cfa809d`).
- **Branch naming:** `202605_resolute` (build, all repos) / `202605_resolute_doc` (super docs only).
- **Not committed:** `.pptx`, `.pptx.md`, `sonic.code-workspace` (gitignored).
- **2 submodules need pre-rebase** (`src/sonic-dash-ha`, `src/sonic-sairedis`) onto their 202605 gitlink locks (`dec02a5d`, `cec72ecc`) — must complete BEFORE super-repo rebase.
- **7 canonical repos exist** (push=True, divergent independent mirrors) — push new branch directly, no `--force` (new branch accepted without shared ancestry).
- **7 canonical repos missing (404)** — fork from sonic-net via `gh repo fork --org canonical` before pushing.
- **filter-repo does NOT recurse into submodules** and does NOT remap gitlink shas — 14 submodule pointers preserved as-is through the super filter.
- **Order:** §6.1 submodule rebase → §4 super build rebase → §6.2 submodule push → §7 .gitmodules rewrite → super re-push.

---

## Execution Results Overview (completed 2026-07-06)

> All 7 Tasks completed; every checkbox checked. During execution the user added 3 constraints (all satisfied): **identity rewrite** (`@local` → `Sheldon Qi <sheldon.qi@canonical.com>`), **GPG signing** (GitHub verified=true), and **submodule ff** (all 14 submodule build-commits' parent = 202605 gitlink lock). See each Task's **Result** lines.

### Final artifacts (canonical/)
| Branch | tip | Verification |
|---|---|---|
| `canonical/sonic-buildimage@202605_resolute` (build) | `c7b71c085b5e4452252f2f78fb03cdf9df167f9e` | 95 migration commits, ff from sonic-net/202605, no superpowers, .gitmodules 14→canonical, 14 gitlinks → new signed submodule shas, GitHub verified=true |
| `canonical/sonic-buildimage@202605_resolute_doc` (docs) | `99851a4e37` (after plan backfill) | 37 commits, 6 bilingual docs + 4 plans + 4 specs, 0 pptx, GitHub verified=true |
| 14 submodules `@202605_resolute` | see Task 5 table | all GitHub verified=true, ff from each 202605 gitlink lock |

### Key deviations from the original plan (user-added / discovered during execution)
1. **Identity rewrite (user-added Task 3b/4b):** Both repos + 14 submodules had local `user.*` config mis-set to `@local` (forgot to configure on the migration machine). Deleted local config + `git filter-repo --mailmap` rewrite + `git rebase --exec` GPG signing. All commit committers → `Sheldon Qi`; upstream contributor authors preserved as-is.
2. **Safety tags are NOT sufficient for rollback:** filter-repo rewrites tags and gc prunes original objects. Added out-of-repo bundle backups (`~/resolute-pre-filter-backup.bundle`, `~/doc-pre-filter-backup.bundle`) as true rollback points.
3. **Build repo merge-base is `9c84048a4`, not `77cfa809d`:** rebase `--onto sonic-net/202605 77cfa809d` replayed 11458 commits; git auto-skipped ~11364 upstream commits and applied 94 migration commits (plan expected ~66). 27 of those have upstream authors (`[submodule] Update` bump commits) — inherent to SONiC gitlink-bump commits, not a bug.
4. **`gh repo fork --remote=false` syntax unsupported** (this gh version): omitted `--remote` (default adds no remote).
5. **Submodule build-commit rewrite changed shas:** Task 6 additionally updated the 14 super-repo gitlinks to the new signed shas (original plan only rewrote .gitmodules URLs).
6. **Super-repo merge-base = sonic-net/202605 current tip `eeb4bff75c`** (upstream pushed more commits during execution, newer than the `9c84048a4` in the plan; ff YES is what matters).

### Original repo state
- `~/sonic-buildimage-resolute` → `202605_resolute` (local user.* config deleted; global `Sheldon Qi` applies)
- `~/sonic-buildimage` → `202605_resolute_doc` (same)

---

## Task 0: Preflight verification

Verify the environment and all assumptions before any irreversible action.

**Files:** none.

- [x] **Step 1: Confirm git-filter-repo is installed**

Run: `git filter-repo --version`
Expected: prints a version (e.g. `2.47.0`). If missing: `sudo apt install git-filter-repo` (passwordless sudo available).
**Result:** Missing at first check; `sudo apt-get install -y git-filter-repo` installed it; `git filter-repo --version` responds.

- [x] **Step 2: Confirm gh is authenticated to canonical**

Run: `gh auth status`
Expected: `✓ Logged in to github.com account xdqi`, token scopes include `repo` and `read:org`.
**Result:** `✓ Logged in to github.com account xdqi`, scopes `admin:public_key gist read:org repo`, ssh protocol. ✅

- [x] **Step 3: Confirm both original repos are on the expected branches**

Run: `git -C ~/sonic-buildimage-resolute branch --show-current && git -C ~/sonic-buildimage branch --show-current`
Expected:
```
resolute
202605-wip
```
**Result:** `resolute` / `202605-wip`. ✅

- [x] **Step 4: Confirm the resolute branch tip is `2d1fc1b4f` (boost 1.83 baseline)**

Run: `git -C ~/sonic-buildimage-resolute log --oneline -1 resolute`
Expected: `2d1fc1b4f build: drop boost 1.88 adaptation, revert to 1.83 baseline`
**Result:** `2d1fc1b4f build: drop boost 1.88 adaptation, revert to 1.83 baseline`. ✅

- [x] **Step 5: Confirm sonic-net 202605 HEAD is `9c84048a4`**

Run: `git -C ~/sonic-buildimage-resolute ls-remote https://github.com/sonic-net/sonic-buildimage.git refs/heads/202605`
Expected: a line starting with `9c84048a4` (first 10 chars).
**Result:** `9c84048a4240ea5d358f74b0821d2d51bba9a3b5 refs/heads/202605`. ✅

- [x] **Step 6: Confirm no uncommitted changes block the rewrite on the build repo**

Run: `git -C ~/sonic-buildimage-resolute status --short sonic-slave-resolute/Dockerfile.j2`
Expected: empty (the boost 1.83 change is already committed in `2d1fc1b4f`).
**Result:** empty (exit 0). ✅

- [x] **Step 7: Create safety tag on the build repo**

Run: `git -C ~/sonic-buildimage-resolute tag pre-filter-resolute resolute`
Expected: no output. Verify: `git -C ~/sonic-buildimage-resolute rev-parse pre-filter-resolute` → full sha of `2d1fc1b4f`.
**Result:** `pre-filter-resolute → 2d1fc1b4f7f1e8f87f3e33a26c29b4c4fc3a4f46`. ✅ **Note:** filter-repo rewrites tags, so added an out-of-repo bundle backup `~/resolute-pre-filter-backup.bundle` (62M, resolute@2d1fc1b4f complete history) as the true rollback point.

---

## Task 1: Fork the 7 missing canonical submodule repos

The 7 submodules whose canonical repos return 404 must be forked from sonic-net before push. Do this first so all 14 submodule push targets exist by Task 5.

**Files:** none (GitHub-side).

**Submodules to fork (canonical repo → sonic-net source):**
- `sonic-platform-vpp` ← `sonic-net/sonic-platform-vpp`
- `sonic-dhcp-relay` ← `sonic-net/sonic-dhcp-relay`
- `sonic-bmp` ← `sonic-net/sonic-bmp`
- `sonic-dash-ha` ← `sonic-net/sonic-dash-ha`
- `sonic-dash-api` ← `sonic-net/sonic-dash-api`
- `sonic-stp` ← `sonic-net/sonic-stp`
- `sonic-wpa-supplicant` ← `sonic-net/sonic-wpa-supplicant`

- [x] **Step 1: Fork ONE repo first as a sanity check (per R5)**

Run: `gh repo fork sonic-net/sonic-bmp --org canonical --remote=false`
Expected: a message like `Created fork canonical/sonic-bmp`. If it fails with a permission error, STOP — you lack org fork permission; ask a canonical owner to fork the 7 repos before continuing.
**Result:** `--remote=false` is unsupported in this gh version (`the --remote flag is unsupported when a repository argument is provided`). Omitted `--remote` (default adds no remote): `gh repo fork sonic-net/sonic-bmp --org canonical` → `https://github.com/canonical/sonic-bmp`. Org fork permission confirmed. ✅

- [x] **Step 2: Verify the fork exists**

Run: `gh api repos/canonical/sonic-bmp --jq '.full_name + " (fork=" + (.fork|tostring) + ")"'`
Expected: `canonical/sonic-bmp (fork=true)`.
**Result:** `canonical/sonic-bmp (fork=true)`. ✅

- [x] **Step 3: Fork the remaining 6 repos**

Run:
```
gh repo fork sonic-net/sonic-platform-vpp --org canonical --remote=false
gh repo fork sonic-net/sonic-dhcp-relay --org canonical --remote=false
gh repo fork sonic-net/sonic-dash-ha --org canonical --remote=false
gh repo fork sonic-net/sonic-dash-api --org canonical --remote=false
gh repo fork sonic-net/sonic-stp --org canonical --remote=false
gh repo fork sonic-net/sonic-wpa-supplicant --org canonical --remote=false
```
Expected: each prints `Created fork canonical/<repo>`.
**Result:** All 6 forked successfully (all with `--remote` omitted): sonic-platform-vpp/sonic-dhcp-relay/sonic-dash-ha/sonic-dash-api/sonic-stp/sonic-wpa-supplicant.

- [x] **Step 4: Verify all 7 forks exist**

Run: `for r in sonic-platform-vpp sonic-dhcp-relay sonic-bmp sonic-dash-ha sonic-dash-api sonic-stp sonic-wpa-supplicant; do gh api repos/canonical/$r --jq '"$r fork=\(.fork)"' 2>/dev/null && echo "  $r OK" || echo "  $r MISSING"; done`
Expected: each line `<repo> fork=true` then `OK`.
**Result:** All 7 `fork=true OK`. ✅

---

## Task 2: Rebase the 2 submodules whose base was bumped upstream (§6.1)

MUST complete before Task 3 (super-repo rebase). `src/sonic-dash-ha` and `src/sonic-sairedis` had their 202605 gitlink lock bumped past their build commit's parent — rebase the build commit onto the new lock.

**Files:** working dirs `~/sonic-buildimage-resolute/src/sonic-dash-ha` and `~/sonic-buildimage-resolute/src/sonic-sairedis`.

| Submodule | 202605 lock | build commit | build parent |
|---|---|---|---|
| src/sonic-dash-ha | `dec02a5d` | `b336da3` | `07201f08` |
| src/sonic-sairedis | `cec72ecc` | `68da16e5` | `9fc3fb4d` |

- [x] **Step 1: In sonic-dash-ha, fetch and verify the build commit's parent**

Run:
```
cd ~/sonic-buildimage-resolute/src/sonic-dash-ha
git fetch origin
git log --oneline -1 b336da3
git rev-parse --short b336da3^
```
Expected: last command prints `07201f08` (the build parent, which is NOT the 202605 lock `dec02a5d` — that's why rebase is needed).
**Result:** `b336da3 build: drop swss-common git source from Cargo.lock (local vendor)`, parent=`07201f0`. On `resolute` branch, origin=sonic-net, fsck clean. ✅

- [x] **Step 2: Rebase sonic-dash-ha's resolute branch onto the 202605 lock**

Run: `git rebase --onto dec02a5d 07201f08 resolute`
Expected: either a clean rebase (`Successfully rebased`, HEAD now a new commit on top of `dec02a5d`), or a conflict in `Cargo.lock` (dash-ha's build commit touches Cargo.lock for the `swss-common` local-vendor drop). If conflict: edit `Cargo.lock` to keep the resolute intent (drop `swss-common` git source), `git add Cargo.lock`, `git rebase --continue`.
**Result:** clean rebase, no conflicts (`Successfully rebased and updated refs/heads/resolute`).

- [x] **Step 3: Record the new sonic-dash-ha build commit sha**

Run: `git rev-parse HEAD`
Expected: a full 40-char sha. **Write it down** — this is the `<new-dash-ha-sha>` used in Task 3 Step 5 and Task 5. Verify it's on top of the lock: `git log --oneline dec02a5d..HEAD` → 1 commit (the rebased build commit).
**Result:** `<new-dash-ha-sha>` = `cd8f01083776ebf5ceca6185e01e9171d2be3e35` (1 commit on top of dec02a5d, build msg preserved). **Note:** after the Task 4b identity rewrite this sha becomes `1d45f96e38cb31c3d95c21ae37db8eb390601894` (amend+sign); Task 5/6 use the latter.

- [x] **Step 4: In sonic-sairedis, fetch and verify the build commit's parent**

Run:
```
cd ~/sonic-buildimage-resolute/src/sonic-sairedis
git fetch origin
git log --oneline -1 68da16e5
git rev-parse --short 68da16e5^
```
Expected: last command prints `9fc3fb4d` (build parent, NOT the 202605 lock `cec72ecc`).
**Result:** `68da16e5 build: c++17 + implicit includes + SWIG -Wno-error + bump SAI (Doxyfile AUTOLINK)`, parent=`9fc3fb4d`, fsck clean (the object corruption from memory was already fixed). ✅

- [x] **Step 5: Rebase sonic-sairedis's resolute branch onto the 202605 lock**

Run: `git rebase --onto cec72ecc 9fc3fb4d resolute`
Expected: clean rebase, or a conflict in SAI/Doxyfile (sairedis build commit touches `AUTOLINK` + SWIG flags). If conflict: keep the resolute intent (`-Wno-error` for SWIG, SAI bump), `git add`, `git rebase --continue`.
**Result:** clean rebase, no conflicts.

- [x] **Step 6: Record the new sonic-sairedis build commit sha**

Run: `git rev-parse HEAD`
Expected: full sha. **Write it down** — this is `<new-sairedis-sha>` for Task 3 Step 5 and Task 5. Verify: `git log --oneline cec72ecc..HEAD` → 1 commit.
**Result:** `<new-sairedis-sha>` = `06f83ac581af90cac43442166cc38aecc284945f` (1 commit on top of cec72ecc). **Note:** after Task 4b identity rewrite this becomes `e3109136f08355ec5dd046460d983645b21b344f`; Task 5/6 use the latter.

---

## Task 3: Super build branch — filter-repo + rebase + rename (§4)

In-place on `~/sonic-buildimage-resolute`. Scrub superpowers docs, rebase onto `9c84048a4`, rename to `202605_resolute`.

**Files:** `~/sonic-buildimage-resolute` (whole repo history), `.gitmodules` (later in Task 6).

- [x] **Step 1: Scrub superpowers docs from all history (in-place, --force)**

Run:
```
cd ~/sonic-buildimage-resolute
git filter-repo --force --path docs/superpowers --invert-paths
```
Expected: filter-repo reports the number of commits rewritten and that `origin` was removed. ~5 docs commits pruned.
**Result:** 22750 commits parsed/rewritten, origin removed, resolute tip `2d1fc1b4f` → `a4cf9d8c3` (docs/superpowers held multiple files incl. specs/plans). ✅

- [x] **Step 2: Verify the scrub worked**

Run: `git ls-tree -r resolute --name-only | grep -i superpowers`
Expected: empty output (no superpowers paths remain).
**Result:** empty (grep exit 1). ✅

- [x] **Step 3: Re-add remotes and fetch sonic-net 202605**

Run:
```
git remote add sonic-net https://github.com/sonic-net/sonic-buildimage.git
git remote add canonical  git@github.com:canonical/sonic-buildimage.git
git fetch sonic-net
```
Expected: `sonic-net/202605` fetched, points at `9c84048a4`.
**Result:** remotes added, `sonic-net/202605 = 9c84048a4 [submodule] Update sonic-dash-ha`. ✅ (non-fatal warnings from recursive submodule fetch ignored)

- [x] **Step 4: Begin the rebase onto latest 202605**

Run: `git rebase --onto sonic-net/202605 77cfa809d resolute`
Expected: replays the filtered resolute commits. Will STOP at the first gitlink conflict.
**Result:** **Key finding:** `77cfa809d` is NOT the merge-base; the real merge-base is `437419c79`, so `77cfa809d..resolute` = 11458 commits. git auto-skipped ~11364 already-applied upstream commits and applied 94 migration commits. Stopped at the gitlink conflict of `cc876215c "bump resolute submodules"` (src/sonic-dash-ha, src/sonic-sairedis UU). First 92 commits applied cleanly.

- [x] **Step 5: Resolve the sonic-dash-ha gitlink conflict**

When rebase stops on a conflict touching `src/sonic-dash-ha`:
Run: `git update-index --cacheinfo 160000 <new-dash-ha-sha> src/sonic-dash-ha && git add src/sonic-dash-ha && git rebase --continue`
(`<new-dash-ha-sha>` = the full sha recorded in Task 2 Step 3. `160000` is the gitlink mode. Do NOT use `git checkout --theirs` — that keeps the stale pre-rebase pointer.)

Expected: conflict resolved, rebase continues. May stop again at sonic-sairedis or dhcpmon.
**Result:** `git update-index --cacheinfo 160000 cd8f01083776ebf5ceca6185e01e9171d2be3e35 src/sonic-dash-ha`, UU cleared, continue.

- [x] **Step 6: Resolve the sonic-sairedis gitlink conflict**

When rebase stops on `src/sonic-sairedis`:
Run: `git update-index --cacheinfo 160000 <new-sairedis-sha> src/sonic-sairedis && git add src/sonic-sairedis && git rebase --continue`
(`<new-sairedis-sha>` from Task 2 Step 6.)

Expected: conflict resolved, rebase continues.
**Result:** `git update-index --cacheinfo 160000 06f83ac581af90cac43442166cc38aecc284945f src/sonic-sairedis`, continue → `Successfully rebased`.

- [x] **Step 7: Resolve the dhcpmon gitlink conflict (if it appears)**

If rebase stops on `src/dhcpmon` (no resolute build commit — take 202605's pointer):
Run: `git checkout --theirs src/dhcpmon && git add src/dhcpmon && git rebase --continue`
Expected: conflict resolved, rebase completes with `Successfully rebased`.
**Result:** No dhcpmon conflict appeared; rebase completed directly. Verified all 14 gitlinks match the Task 5 table (dash-ha=cd8f010, sairedis=06f83ac5, other 12 original shas).

- [x] **Step 8: Verify the rebase result**

Run:
```
git merge-base HEAD sonic-net/202605
git log --oneline sonic-net/202605..HEAD | wc -l
```
Expected: first command prints `9c84048a4...` (full sha); second prints ~66 (the filtered build commits, docs pruned).
**Result:** merge-base=`9c84048a4`, commit count=**94** (plan expected ~66; includes 27 upstream-authored `[submodule] Update` bump commits replayed — their gitlink-sha patch has no equivalent in the new base so they aren't skipped; normal). tip=`02aa417d3`.

- [x] **Step 9: Rename branch to 202605_resolute**

Run: `git branch -m resolute 202605_resolute`
Expected: no output. Verify: `git branch --show-current` → `202605_resolute`.
**Result:** renamed OK. ✅

- [x] **Step 10: Push the super build branch to canonical**

Run: `git push canonical 202605_resolute`
Expected: `* [new branch]` — branch created on `canonical/sonic-buildimage`.
**Result:** `* [new branch] 202605_resolute -> 202605_resolute`. ✅ **Note:** this was the pre-identity-rewrite first push (sha `02aa417d3`), later overwritten by a force-push of the identity-rewritten version.

- [x] **Step 11: Verify on GitHub**

Run: `gh api repos/canonical/sonic-buildimage/branches/202605_resolute --jq '.commit.sha'`
Expected: a sha matching local `git rev-parse 202605_resolute`.
**Result:** GitHub sha == local `02aa417d35...`. ✅ (final sha after identity rewrite = `c7b71c085b5e4452252f2f78fb03cdf9df167f9e`, see Task 3b/6)

---

## Task 3b: Identity rewrite + GPG signing (user-added, not in original plan)

During execution it was found that both repos' local `user.*` config was mis-set to `@local` (forgot to configure on the migration machine, AI filled in a placeholder): build repo `SONiC Build <sonic-build@local>`, docs repo `sheldon-qi <sheldon-qi@local>`. User required: all `@local` author/committer → `Sheldon Qi <sheldon.qi@canonical.com>`, and all of Sheldon's migration commits re-signed with GPG. GPG key `521ED6CE84B5C2B2BAF7AAEA90E19370EEEF6873` (UID `sheldon.qi@canonical.com`).

**Files:** author/committer identity of all commits (does NOT change tree/gitlinks/content).

- [x] **Step 1: Delete local user.* config on both repos (global Sheldon Qi applies)**
Run: `git config --unset user.name; git config --unset user.email` (both repos).
**Result:** Both repos now `Sheldon Qi <sheldon.qi@canonical.com>`, `commit.gpgsign=true`.

- [x] **Step 2: filter-repo --mailmap to rewrite identity**
Run: wrote mailmap (`sheldon-qi@local` + `sonic-build@local` → `Sheldon Qi <sheldon.qi@canonical.com>`), `git filter-repo --force --mailmap /tmp/resolute-id.mailmap`.
**Result:** Build repo 44629 commits parsed, tip `02aa417d3` → `6cbeb89356`. 0 `@local` remaining, all committers = `Sheldon Qi`, authors preserved 14 upstream contributors. 14 gitlinks unchanged (verified identical).

- [x] **Step 3: GPG-sign the 94 migration commits**
Run: `GIT_SEQUENCE_EDITOR=true GIT_EDITOR=true git rebase sonic-net/202605 --exec 'git commit --amend --no-edit --allow-empty -S --quiet'`.
**Result:** First attempt stopped on an empty commit (`7c13fdbd9 "chore: start resolute migration branch"`) with "No changes"; adding `--allow-empty` completed 188 steps (94 pick + 94 exec), all 94 commits `G`, tip `6cbeb89356` → `2f429e5ee1`. ff YES, gitlinks unchanged.

- [x] **Step 4: force-push to overwrite**
Run: `git push canonical 202605_resolute --force-with-lease`.
**Result:** `02aa417d35...2f429e5ee1 (forced update)`, GitHub `verified=true`. ✅ (final tip after Task 6's .gitmodules change = `c7b71c085b`)

---

## Task 4: Super docs branch — filter-repo + rebase + rename (§5)

In-place on `~/sonic-buildimage` (branch `202605-wip`). Commit 6 new bilingual docs, scrub 2 old single-language docs, rebase, rename to `202605_resolute_doc`.

**Files:** `~/sonic-buildimage/.gitignore`, 6 new doc files under `docs/superpowers/`.

- [x] **Step 1: Add the 6 new bilingual docs + gitignore entries (on 202605-wip)**

Run:
```
cd ~/sonic-buildimage
printf '\n# Generated/personal — not committed\nsonic.code-workspace\n*.pptx\n*.pptx.md\n' >> .gitignore
git add docs/superpowers/resolute-migration-code-review-en.md docs/superpowers/resolute-migration-code-review-zh.md docs/superpowers/resolute-modification-catalog-en.md docs/superpowers/resolute-modification-catalog-zh.md docs/superpowers/resolute-vs-migration-report-en.md docs/superpowers/resolute-vs-migration-report-zh.md .gitignore
git commit -m "docs: add resolute migration docs bilingual"
```
Expected: commit created. Verify the 6 `-en.md`/`-zh.md` files and `.gitignore` are staged; the `.pptx`/`.pptx.md`/`sonic.code-workspace` are NOT.
**Result:** commit created, 7 files / 1643 insertions (6 docs + .gitignore), pptx/workspace ignored. ✅

- [x] **Step 2: Create safety tag**

Run: `git tag pre-filter-docs 202605-wip`
Expected: no output.
**Result:** `pre-filter-docs = aaf946bfb8c75f54355c4c681aec4f762a2f3cb7`. Also added bundle backup `~/doc-pre-filter-backup.bundle` (63M) as the true rollback point.

- [x] **Step 3: Scrub the 2 old single-language docs from all history (in-place, --force)**

Run:
```
git filter-repo --force \
  --path docs/superpowers/resolute-migration-code-review.md \
  --path docs/superpowers/resolute-vs-migration-report.md \
  --invert-paths
```
Expected: filter-repo rewrites history, removes those 2 paths from every commit, prunes now-empty commits, removes `origin`.
**Result:** 22673 commits parsed/rewritten, origin removed, 3 docs-only commits pruned (12294→12291), tip `aaf946bfb` → `4480fc4ce`. ✅

- [x] **Step 4: Verify the scrub**

Run: `git ls-tree -r 202605-wip --name-only | grep -E 'resolute-migration-code-review\.md$|resolute-vs-migration-report\.md$'`
Expected: empty (the 2 old single-language paths gone). The 6 new bilingual files (with `-en`/`-zh` suffixes) remain — verify: `git ls-tree -r 202605-wip --name-only | grep superpowers` shows the 6 new files.
**Result:** 2 old paths gone (grep exit 1); 6 bilingual docs + 4 plans + 4 specs preserved. ✅

- [x] **Step 5: Re-add remotes, rename branch, rebase onto latest 202605**

Run:
```
git remote add sonic-net https://github.com/sonic-net/sonic-buildimage.git
git remote add canonical  git@github.com:canonical/sonic-buildimage.git
git fetch sonic-net
git branch -m 202605-wip 202605_resolute_doc
git rebase --onto sonic-net/202605 77cfa809d 202605_resolute_doc
```
Expected: rebase completes with ~0 conflicts (docs don't touch submodule pointers or build files).
**Result:** rebase complete (37 commits, merge-base=`9c84048a4`), no conflicts, tip `5d2d41a553`. ff YES.

- [x] **Step 6: Verify the rebase result**

Run: `git merge-base HEAD sonic-net/202605`
Expected: `9c84048a4...` (full sha).
**Result:** `9c84048a4240ea5d358f74b0821d2d51bba9a3b5`. ✅

- [x] **Step 7: Push the super docs branch to canonical**

Run: `git push canonical 202605_resolute_doc`
Expected: `* [new branch]`.
**Result:** pushed after identity rewrite (see Task 4b), `* [new branch] 202605_resolute_doc`.

- [x] **Step 8: Verify on GitHub**

Run: `gh api repos/canonical/sonic-buildimage/branches/202605_resolute_doc --jq '.commit.sha'`
Expected: sha matching local `git rev-parse 202605_resolute_doc`.
**Result:** GitHub sha == local `ec99572bc82c78972dfbfaa7bafb8d435c7b6253`, `verified=true`. ✅

---

## Task 4b: Docs repo identity rewrite + GPG signing (user-added)

Same as Task 3b. Docs repo local config `sheldon-qi <sheldon-qi@local>`; 37 migration commits (10 author + 37 committer are `@local`), all unsigned.

- [x] **Step 1: Delete local config + mailmap + signing rebase + push**
Run: same flow as Task 3b (same mailmap file, rebase `--exec` to sign 37 commits).
**Result:** tip `5d2d41a553` → mailmap `beb43c9c3a` → signed `ec99572bc`. 0 `@local`, all 37 commits `G`, ff YES, `git push canonical 202605_resolute_doc` (new branch, no force), GitHub `verified=true`. ✅

---

## Task 5: Push all 14 submodule 202605_resolute branches (§6.2)

For each of the 14 submodules: add a `canonical` remote, push the build commit (rebased sha for dash-ha/sairedis, original sha for the other 12) as a new `202605_resolute` branch. No `--force` (new branch).

**Files:** none (each submodule's remote refs).

**Submodule → repo → build commit map:**

| Submodule path | canonical repo | build commit to push |
|---|---|---|
| src/sonic-swss | sonic-swss | `6d3a46bb` |
| src/sonic-sairedis | sonic-sairedis | `<new-sairedis-sha>` (Task 2 Step 6) |
| src/sonic-swss-common | sonic-swss-common | `baf0b19` |
| src/sonic-gnmi | sonic-gnmi | `c8f96ff` |
| src/sonic-mgmt-framework | sonic-mgmt-framework | `fda49ff` |
| src/sonic-linux-kernel | sonic-linux-kernel | `c54d5e3` |
| src/sonic-mgmt-common | sonic-mgmt-common | `47995eb` |
| platform/vpp | sonic-platform-vpp | `fe8c727` |
| src/dhcprelay | sonic-dhcp-relay | `d620ecc` |
| src/sonic-bmp | sonic-bmp | `c11289b` |
| src/sonic-dash-ha | sonic-dash-ha | `<new-dash-ha-sha>` (Task 2 Step 3) |
| src/sonic-dash-api | sonic-dash-api | `43c676b` |
| src/sonic-stp | sonic-stp | `416491c` |
| src/wpasupplicant/sonic-wpa-supplicant | sonic-wpa-supplicant | `7f39eb03f` |

> **Execution deviation (Task 4b identity rewrite):** the build commit shas in the table above all changed after identity rewrite + GPG signing. The table below gives the **final signed shas** (what was actually pushed):

| Submodule path | canonical repo | original build sha | signed build sha (actually pushed) |
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

- [x] **Step 1: Add canonical remote to each of the 14 submodules**

Run (in `~/sonic-buildimage-resolute`):
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
Expected: no output (remotes added; `|| true` skips ones already existing).
**Result:** 14 canonical remotes added. ✅

- [x] **Step 2: Push the 7 existing-repo submodules (non-rebased)**

Run:
```
git -C src/sonic-swss         push canonical 6d3a46bb:refs/heads/202605_resolute
git -C src/sonic-swss-common  push canonical baf0b19:refs/heads/202605_resolute
git -C src/sonic-gnmi         push canonical c8f96ff:refs/heads/202605_resolute
git -C src/sonic-mgmt-framework push canonical fda49ff:refs/heads/202605_resolute
git -C src/sonic-linux-kernel push canonical c54d5e3:refs/heads/202605_resolute
git -C src/sonic-mgmt-common  push canonical 47995eb:refs/heads/202605_resolute
```
Expected: each prints `* [new branch]`.
**Result:** pushed using the signed shas (see table above), all 6 `* [new branch]`. (sonic-linux-kernel was detached HEAD before signing; the workflow agent used `git checkout -B resolute <sha>` to switch to the branch)

- [x] **Step 3: Push the 2 rebased submodules**

Run:
```
git -C src/sonic-sairedis push canonical <new-sairedis-sha>:refs/heads/202605_resolute
git -C src/sonic-dash-ha  push canonical <new-dash-ha-sha>:refs/heads/202605_resolute
```
(Replace `<new-sairedis-sha>` and `<new-dash-ha-sha>` with the full shas from Task 2.)
Expected: each prints `* [new branch]`.
**Result:** used signed shas (sairedis `e3109136f0`, dash-ha `1d45f96e38`), both `* [new branch]`.

- [x] **Step 4: Push the 7 forked (originally 404) submodules**

Run:
```
git -C platform/vpp                              push canonical fe8c727:refs/heads/202605_resolute
git -C src/dhcprelay                             push canonical d620ecc:refs/heads/202605_resolute
git -C src/sonic-bmp                             push canonical c11289b:refs/heads/202605_resolute
git -C src/sonic-dash-api                        push canonical 43c676b:refs/heads/202605_resolute
git -C src/sonic-stp                             push canonical 416491c:refs/heads/202605_resolute
git -C src/wpasupplicant/sonic-wpa-supplicant    push canonical 7f39eb03f:refs/heads/202605_resolute
```
(dash-ha forked in Task 1 but pushed in Step 3 above with its rebased sha.)
Expected: each prints `* [new branch]`.
**Result:** used signed shas, all `* [new branch]`. (sonic-dash-api was detached before signing; same `checkout -B resolute`)

- [x] **Step 5: Verify all 14 submodule branches exist on canonical**

Run:
```
for repo in sonic-swss sonic-sairedis sonic-swss-common sonic-gnmi sonic-mgmt-framework sonic-linux-kernel sonic-mgmt-common sonic-platform-vpp sonic-dhcp-relay sonic-bmp sonic-dash-ha sonic-dash-api sonic-stp sonic-wpa-supplicant; do
  sha=$(gh api repos/canonical/$repo/branches/202605_resolute --jq '.commit.sha' 2>/dev/null | cut -c1-10)
  echo "$repo 202605_resolute=$sha"
done
```
Expected: 14 lines, each with a non-empty sha.
**Result:** all 14 returned non-empty signed shas, and all `verified=true`. ✅

---

## Task 6: Rewrite .gitmodules + align submodule working dirs (§7)

On `~/sonic-buildimage-resolute` (now on `202605_resolute`). Point the 14 submodules at `canonical/`, align working dirs, commit, re-push.

**Files:** `~/sonic-buildimage-resolute/.gitmodules`.

**The 14 submodule paths → new canonical URLs:**
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

- [x] **Step 1: Rewrite .gitmodules URLs**

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
Expected: no output. `.gitmodules` now has 14 canonical URLs.
**Result:** 14 canonical URLs, `grep -c 'github.com:canonical' .gitmodules` = 14. ✅

- [x] **Step 2: Sync .gitmodules into .git/config**

Run: `git submodule sync`
Expected: no output (propagates URLs).
**Result:** sync complete. ✅

- [x] **Step 3: Align submodule working dirs to their gitlinks**

Run: `git submodule update --recursive --no-fetch`
Expected: submodules checked out to the commits recorded in the super-repo gitlinks. For `src/sonic-dash-ha` and `src/sonic-sairedis`, this checks out the new rebased build commits (Task 2). For the other 12, a no-op if already at the build commit.
**Result:** **Deviation:** because Task 4b's submodule build-commit identity rewrite changed the shas, the planned `submodule update` was insufficient. Used `git update-index --cacheinfo 160000 <new-signed-sha> <path>` to directly update the 14 gitlinks to the signed shas (see Task 5 table). This makes the super-repo gitlinks point at the new signed submodule commits pushed to canonical.

- [x] **Step 4: Verify git status is clean**

Run: `git status --short`
Expected: only `.gitmodules` shows as modified. No dirty submodules. If a submodule shows as dirty, re-run Step 3; if still dirty, manually `git -C <submodule> checkout <build-commit-sha-from-Task-5-map>`.
**Result:** 15 files staged (14 gitlinks + .gitmodules), other resolute submodules already aligned (status clean after commit). ✅

- [x] **Step 5: Commit the .gitmodules change**

Run:
```
git add .gitmodules
git commit -m "build: point submodules at canonical resolute branches"
```
Expected: commit created.
**Result:** `git commit -S -m "build: point submodules at canonical resolute branches (signed)"`, 15 files / 32 insertions / 24 deletions, tip `c7b71c085b`, GPG G, author/committer=`Sheldon Qi`. ff YES.

- [x] **Step 6: Re-push the super build branch (amended tip)**

Run: `git push canonical 202605_resolute --force-with-lease`
Expected: `+ <sha>...202605_resolute -> 202605_resolute (forced update)` — the `.gitmodules` commit is now the tip on canonical.
**Result:** `2f429e5ee..c7b71c085 202605_resolute -> 202605_resolute (forced update)`. ✅

- [x] **Step 7: Verify the .gitmodules on canonical**

Run: `gh api repos/canonical/sonic-buildimage/contents/.gitmodules?ref=202605_resolute --jq '.content' | base64 -d | grep -c 'github.com:canonical'`
Expected: `14` (all 14 resolute submodules point at canonical).
**Result:** `14`. ✅ GitHub sha == local `c7b71c085b5e4452252f2f78fb03cdf9df167f9e`, `verified=true`.

---

## Task 7: Final verification (§10)

Confirm the entire upload succeeded and original repos are aligned.

**Files:** none.

- [x] **Step 1: Super build branch has no superpowers docs**

Run: `git -C ~/sonic-buildimage-resolute ls-tree -r 202605_resolute --name-only | grep -i superpowers`
Expected: empty.
**Result:** empty. ✅

- [x] **Step 2: Super build sits on latest 202605**

Run: `git -C ~/sonic-buildimage-resolute merge-base 202605_resolute sonic-net/202605`
Expected: `9c84048a4` (full sha).
**Result:** merge-base = `eeb4bff75c6a02ac7aa4b3c6eea9d2653e066ea5` (upstream pushed more commits during execution, newer than the `9c84048a4` in the plan). `git merge-base --is-ancestor sonic-net/202605 202605_resolute` → **ff YES** (the key constraint holds). ✅

- [x] **Step 3: Super docs branch has the 6 bilingual docs, no .pptx**

Run: `git -C ~/sonic-buildimage ls-tree -r 202605_resolute_doc --name-only | grep superpowers`
Expected: 6 lines (3 topics × `-en.md`/`-zh.md`), no `.pptx`/`.pptx.md`.
**Result:** 6 bilingual docs (3 topics × en/zh) + 4 plans + 4 specs; pptx/pptx.md = 0. ✅

- [x] **Step 4: .gitmodules points 14 submodules at canonical**

Run: `grep -c 'github.com:canonical' ~/sonic-buildimage-resolute/.gitmodules`
Expected: `14`.
**Result:** `14`. ✅

- [x] **Step 5: All 14 submodule branches exist on canonical**

(Reuse the Task 5 Step 5 loop — all 14 should return non-empty shas.)
**Result:** all 14 returned non-empty signed shas + `verified=true`. ✅ (see Task 5 signed-sha table)

- [x] **Step 6: Original repos on the correct branches**

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
**Result:** `202605_resolute` / `202605_resolute_doc`. ✅

- [x] **Step 7: Build repo git status is clean (no dirty submodules)**

Run: `git -C ~/sonic-buildimage-resolute status --short`
Expected: empty (all submodules aligned to gitlinks per Task 6 Step 3).
**Result:** all 14 resolute submodules aligned (clean). ✅

- [x] **Step 8: Both branches visible on GitHub**

Open:
- `https://github.com/canonical/sonic-buildimage/tree/202605_resolute`
- `https://github.com/canonical/sonic-buildimage/tree/202605_resolute_doc`

Expected: both branches render with their latest commits.
**Result:** both visible on GitHub: `202605_resolute` = `c7b71c085b`, `202605_resolute_doc` = `99851a4e3` (after plan backfill), both `verified=true`. ✅

- [x] **Step 9: Record final state in memory**

Update the memory note `sonic-resolute-vs-build-success.md` (or create a new `sonic-resolute-canonical-upload.md`) recording: the 2 super branch names on canonical, the 14 submodule `202605_resolute` branches, the 2 rebased submodule shas, and the fact that original repos now sit on `202605_resolute` / `202605_resolute_doc`. This survives across sessions.
**Result:** created memory note `sonic-resolute-canonical-upload.md` (in claude memory dir `~/.claude/projects/.../memory/`) recording 2 super branches + 14 submodule signed shas + ff constraint + bundle backup locations. MEMORY.md index updated. ✅
