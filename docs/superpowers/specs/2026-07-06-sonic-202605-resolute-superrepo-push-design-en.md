# SONiC 202605 Resolute — Branch Upload Design (Super + Submodules)

- **Date:** 2026-07-06
- **Scope:** Super-repository (`sonic-buildimage`) + 14 submodules with resolute `build:` commits.
- **Target org:** `canonical/` on GitHub. Account `xdqi` = canonical org member (active), token scopes `repo` + `read:org` (no `admin:org`).

## 1. Goal

Upload the resolute migration work — both the super-repository and the submodules — to `canonical/` so the team can clone and reproduce the resolute `vs` build.

### Branch naming (user decision 2026-07-06)
| Repo class | Build branch | Docs branch |
|---|---|---|
| `sonic-*` repos (all 14 submodules + super) | `202605_resolute` | (none) |
| Super-repo `sonic-buildimage` (also `sonic-*`) | `202605_resolute` | `202605_resolute_doc` |

Submodules get **only the build branch** — their `build:` commits contain no superpowers docs, so no `_doc` variant. The `sonic_202605_resolute` rule (non-`sonic-*` repos) is unused here: all 14 submodule canonical repo names begin with `sonic-`.

### What gets uploaded
- **Super build branch `202605_resolute`** — all resolute build commits, with **zero** superpowers docs (scrubbed via `filter-repo`).
- **Super docs branch `202605_resolute_doc`** — migration design / plan / review / catalog / report docs (bilingual `.md` only; no `.pptx`/`.pptx.md`).
- **14 submodule `202605_resolute` branches** — each submodule's resolute `build:` commit(s).

Both super branches rebased onto **latest upstream `202605`** (`sonic-net/sonic-buildimage` HEAD `9c84048a4`).

## 2. Current state (verified 2026-07-06)

### Super-repository sources
| Repo | Branch | Ahead of merge-base | Notes |
|---|---|---|---|
| `~/sonic-buildimage-resolute` | `resolute` | **71 commits** | 5 touch `docs/superpowers/`; 66 pure build. Latest commit `2d1fc1b4f` drops boost 1.88 adaptation → boost 1.83 baseline. Dockerfile.j2 change **already committed**. |
| `~/sonic-buildimage` | `202605-wip` | 7 commits (+1 spec) | All docs-only. Pending reorg: delete 2 old single-language docs, add 6 bilingual `.md` (3 topics × en/zh). `.pptx`, `.pptx.md`, `sonic.code-workspace` gitignored, not committed. |

Superpowers paths committed in the `resolute` branch (5 files, all under `docs/superpowers/`):
- `plans/done-bar-status.txt`, `plans/fips-status.txt`
- `specs/2026-07-05-resolute-variant-naming-design.md`, `specs/category-c-catalog-en.md`, `specs/category-c-catalog-zh.md`

The 5 docs commits are **interleaved** with the 66 build commits — path-based scrub is required (interactive rebase-drop would mean editing 71 todos).

### Super upstream distance
- merge-base `77cfa809d`; sonic-net `202605` HEAD `9c84048a4`; **3 commits between**, all automated submodule bumps: `sonic-dash-ha` (#28234), `dhcpmon` (#28232), `sonic-sairedis` (#28242).
- Upstream `202605` has **no** `docs/superpowers/` content → `filter-repo` leaves base commits untouched, merge-base hash preserved.
- canonical's `202605` HEAD = `77cfa809d` (= merge-base; canonical is 3 commits behind sonic-net). New branches base on sonic-net latest regardless.

### Submodules (14 with resolute `build:` commits, after boost 1.83 revert)
Boost 1.88→1.83 revert commit `2d1fc1b4f` dropped the linkmgrd `io_service→io_context` migration (49 files) and sonic-redfish/libboost1.88 alternates — **linkmgrd and sonic-redfish now have 0 build commits**, leaving 14:

| Submodule | canonical repo | build commits | True delta (build commits only) | canonical status |
|---|---|---|---|---|
| src/sonic-swss | sonic-swss | 1 | 4 files +11/-6 | exists, push=True, **independent (non-fork)** |
| src/sonic-sairedis | sonic-sairedis | 1 | 3 files +8/-3 | exists, push=True, **independent** |
| src/sonic-swss-common | sonic-swss-common | 1 | 2 files +15/-7 | exists, push=True, **independent** |
| src/sonic-gnmi | sonic-gnmi | 1 | 3 files +26/-5 | exists, push=True, **independent** |
| src/sonic-mgmt-framework | sonic-mgmt-framework | 1 | 2 files +31/-11 | exists, push=True, **independent** |
| src/sonic-linux-kernel | sonic-linux-kernel | 1 | 1 file +9/-1 | exists, push=True, **independent** |
| src/sonic-mgmt-common | sonic-mgmt-common | 1 | 1 file +2/-0 | exists, push=True, **independent** |
| platform/vpp | sonic-platform-vpp | 1 | 4 files +4/-4 | **404 — fork from sonic-net** |
| src/dhcprelay | sonic-dhcp-relay | 1 | 3 files +3/-3 | **404 — fork** |
| src/sonic-bmp | sonic-bmp | 1 | 2 files +1/-1 | **404 — fork** |
| src/sonic-dash-ha | sonic-dash-ha | 1 | 1 file +0/-2 | **404 — fork** |
| src/sonic-dash-api | sonic-dash-api | 1 | 1 file +2/-2 | **404 — fork** |
| src/sonic-stp | sonic-stp | 1 | 2 files +7/-2 | **404 — fork** |
| src/wpasupplicant/sonic-wpa-supplicant | sonic-wpa-supplicant | 1 | 1 file +7/-2 | **404 — fork** |

- **7 existing** canonical repos are all `fork=false`, `parent=null` — independent mirrors created 2024, **divergent from sonic-net** (no shared recent ancestry; canonical master ≠ sonic-net master). They have stale `202012/202305/202405` branches.
- **7 missing (404)** — sonic-net upstream exists and is non-fork (valid fork source).
- `xdqi` push=False on sonic-net upstream for all 14 → cannot push resolute branches to sonic-net.

### Push mechanics (verified)
- **Pushing a NEW branch (`202605_resolute`) to a divergent canonical repo does NOT require `--force`** — git accepts a new branch ref even without shared ancestry, as long as the pushed commits are complete/reachable. Dry-run confirmed on sonic-mgmt-common: `* [new branch] 47995eb -> 202605_resolute`.
- `gh repo fork --org canonical` requires org-level permission; `xdqi` is `role=member` (not owner) with `repo`+`read:org` scopes (no `admin:org`). **Forking to canonical may be blocked** — must test one before relying on it (§6 risk R5).

## 3. Decisions

| # | Decision | Choice | Rationale |
|---|---|---|---|
| D1 | Rebase base (super) | sonic-net latest `202605` (`9c84048a4`) | User said "latest 202605"; 3 upstream bumps harmless; 2 mechanical gitlink conflicts. |
| D2 | Docs scrubbing tool | `git filter-repo --path docs/superpowers --invert-paths` | 5 docs commits interleaved with 66 build commits; path scrub is the only clean option; removes path from every commit's tree. |
| D3 | Super workspace model | fresh non-recursive clone | `filter-repo` refuses non-fresh clones without `--force` and removes `origin`; original `~/sonic-buildimage-resolute` (16 submodules + boost work) must not be touched. |
| D4 | `.pptx`/`.pptx.md` | gitignore, not committed | Generated artifacts; user decision 2026-07-06. Only bilingual `.md` committed. |
| D5 | `sonic.code-workspace` | gitignore, not committed | VSCode personal workspace file. |
| D6 | Branch naming | `202605_resolute` (build, all repos) / `202605_resolute_doc` (super docs only) | User rule: `sonic-*` repos use `202605_resolute{,_doc}`; submodules get build-only. |
| D7 | Submodule repos | 7 existing canonical (push direct) + 7 forked-from-sonic-net | User: "fork, not create". Forks carry sonic-net history so gitlink ancestry is complete. |
| D8 | Submodule push | new `202605_resolute` branch, no `--force` | Verified: new branch ref accepted on divergent repo without shared ancestry. |
| D9 | Submodule base | no rebase — push resolute commit directly on its sonic-net master parent | Submodule resolute commits sit directly on sonic-net `master`; canonical repos are divergent/empty so rebase adds nothing. The build commit + its sonic-net ancestry is what colleagues need. |

## 4. Super build branch — `202605_resolute`

All steps in a **fresh clone**; original `~/sonic-buildimage-resolute` never modified.

1. **Install filter-repo:** `sudo apt install git-filter-repo` (Debian `2.47.0-3`; passwordless sudo available).
2. **Fresh non-recursive clone:**
   ```
   git clone --branch resolute --no-recursive /home/sheldon-qi/sonic-buildimage-resolute /work/resolute-super
   cd /work/resolute-super
   ```
3. **Scrub superpowers docs from all history:**
   ```
   git filter-repo --path docs/superpowers --invert-paths
   ```
   Removes `docs/superpowers/` from every commit's tree; prunes the ~5 commits that become empty. Base commits unchanged (upstream has no such path). `filter-repo` removes `origin` — expected.
4. **Add remotes** (sonic-net = latest 202605; canonical = push target):
   ```
   git remote add sonic-net https://github.com/sonic-net/sonic-buildimage.git
   git remote add canonical  git@github.com:canonical/sonic-buildimage.git
   git fetch sonic-net
   ```
5. **Rebase onto latest 202605:**
   ```
   git rebase --onto sonic-net/202605 77cfa809d resolute
   ```
   - Replays filtered resolute commits onto `9c84048a4`.
   - **Expected conflicts:** `sonic-dash-ha` and `sonic-sairedis` gitlink pointers (bumped locally AND upstream). `dhcpmon` clean. No build-file conflicts.
   - **Resolution:** keep resolute's pointer. ⚠️ Rebase "theirs" = the replayed commit (resolute): `git checkout --theirs <submodule>` then `git add <submodule>`.
6. **Rename branch:** `git branch -m resolute 202605_resolute`
7. **Push:** `git push canonical 202605_resolute`

## 5. Super docs branch — `202605_resolute_doc`

Steps in `~/sonic-buildimage` (branch `202605-wip`). No filter-repo.

1. **Gitignore:** add `sonic.code-workspace`, `*.pptx`, `*.pptx.md` to `.gitignore`.
2. **Commit docs reorg:** stage 2 deletions + 6 new bilingual `.md` only; commit `docs: reorganize resolute migration docs to bilingual`. Do **not** stage `.pptx`/`.pptx.md`/`sonic.code-workspace`.
3. **Create target branch** (leaves `202605-wip` as pre-rebase backup):
   ```
   git checkout -b 202605_resolute_doc
   ```
4. **Rebase onto latest 202605:**
   ```
   git rebase --onto origin/202605 77cfa809d 202605_resolute_doc
   ```
   Primary `origin` = sonic-net (SSH), already at `9c84048a4`. Expected ~0 conflicts.
5. **Add canonical remote and push:**
   ```
   git remote add canonical git@github.com:canonical/sonic-buildimage.git
   git push canonical 202605_resolute_doc
   ```

## 6. Submodule branches — `202605_resolute` (×14)

For **each** of the 14 submodules, in its working dir under `~/sonic-buildimage-resolute/<submodule>`:

1. **Add canonical remote** (SSH):
   ```
   git remote add canonical git@github.com:canonical/<repo>.git
   ```
   - 7 existing repos: remote works immediately (push=True).
   - 7 missing repos: **fork first** — `gh repo fork sonic-net/<repo> --org canonical --remote=false` (then add the canonical remote manually). ⚠️ R5: verify `xdqi` can fork-to-org before batch.
2. **Push the build branch** (no rebase, no force):
   ```
   git push canonical <build-commit-sha>:refs/heads/202605_resolute
   ```
   Pushes the resolute build commit (on its sonic-net master parent) as a new branch. Git accepts new branch refs without shared ancestry (verified §2).

### Submodule repo → build commit map
| canonical repo | build commit (short) |
|---|---|
| canonical/sonic-swss | `6d3a46bb` |
| canonical/sonic-sairedis | `68da16e5` |
| canonical/sonic-swss-common | `baf0b19` |
| canonical/sonic-gnmi | `c8f96ff` |
| canonical/sonic-mgmt-framework | `fda49ff` |
| canonical/sonic-linux-kernel | `c54d5e3` |
| canonical/sonic-mgmt-common | `47995eb` |
| canonical/sonic-platform-vpp (fork) | `fe8c727` |
| canonical/sonic-dhcp-relay (fork) | `d620ecc` |
| canonical/sonic-bmp (fork) | `c11289b` |
| canonical/sonic-dash-ha (fork) | `b336da3` |
| canonical/sonic-dash-api (fork) | `43c676b` |
| canonical/sonic-stp (fork) | `416491c` |
| canonical/sonic-wpa-supplicant (fork) | `7f39eb03f` |

## 7. `.gitmodules` URL rewrite

After submodule branches are pushed, the super build branch `202605_resolute` must point its gitlinks at canonical, not sonic-net. In the fresh super clone (§4), **after step 5 rebase**:

1. **Rewrite `.gitmodules`** — for each of the 14 submodules, change `url = https://github.com/sonic-net/<repo>.git` → `git@github.com:canonical/<repo>.git`. Use `git config -f .gitmodules submodule.<path>.url <new>` (or sed).
2. **Sync config:** `git submodule sync` (propagates `.gitmodules` URLs to `.git/config`).
3. **Commit:** `git commit -am "build: point submodules at canonical resolute branches"`.
4. **Re-push super build branch:** `git push canonical 202605_resolute --force-with-lease` (force-with-lease because this amends the just-pushed tip).

⚠️ The other submodules (no resolute commit) keep pointing at sonic-net — only the 14 with build commits move to canonical.

## 8. Risks & mitigations

- **R1 filter-repo rewrites all build-branch hashes** → originals safe in `~/sonic-buildimage-resolute`; fresh clone disposable.
- **R2 gitlink conflicts (`sonic-dash-ha`, `sonic-sairedis`)** → mechanical; take resolute's pointer (§4 step 5 caveat).
- **R3 canonical `admin=False`** → can't change settings/protection, but can push new branches. New branch names have no protection by default.
- **R4 `.gitmodules` rewrite amends super tip** → use `--force-with-lease` on re-push; only the super build branch is affected, and only once.
- **R5 ⚠️ Fork-to-org may be blocked** — `xdqi` is canonical `member` (not owner), token lacks `admin:org`. `gh repo fork --org canonical` may fail. **Mitigation:** test ONE fork first; if blocked, request a canonical owner perform the 7 forks, or fall back to `gh repo create canonical/<repo> --source sonic-net/<repo> --fork` (same org-permission requirement) or push the 7 to `xdqi/` temporarily. This is the single biggest unverified execution risk.
- **R6 Existing 7 canonical repos are divergent** → their stale `master`/`202012`/etc. branches remain untouched. Only a new `202605_resolute` branch is added. Colleagues fetching the submodule get the resolute commit + its full sonic-net ancestry (complete on the new branch).

## 9. Out of scope

- **`~/sonic-buildimage-202605-clone`**: ignored. Verified byte-identical to primary docs (ahead-3 are duplicates in `202605-wip`).
- **Updating canonical's existing `202605`/`master`**: not requested. New branches are additive.
- **sonic-frr, supervisor, platform vendor SDKs** (saibcm/mrvl/mellanox etc.): not your resolute work; untouched.
- **Pushing resolute submodule commits back to sonic-net upstream**: out of scope (would be PRs, separate effort).

## 10. Verification

- Super build: `git ls-tree -r 202605_resolute --name-only | grep -i superpowers` → **empty**.
- Super build: `git merge-base 202605_resolute sonic-net/202605` → `9c84048a4`.
- Super docs: `git ls-tree -r 202605_resolute_doc --name-only | grep superpowers` → bilingual `.md` present; **no** `.pptx`/`.pptx.md`.
- Super `.gitmodules`: all 14 resolute submodules point at `canonical/`; others still `sonic-net/`.
- Each of 14 submodules: `git ls-remote canonical refs/heads/202605_resolute` → non-empty, sha matches build commit.
- Branches visible at `github.com/canonical/sonic-buildimage/tree/202605_resolute`, `/tree/202605_resolute_doc`, and each `canonical/<submodule>/tree/202605_resolute`.
