# SONiC 202605_resolute Formalization Reorg — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Every commit is GPG-signed; history rewrite only after the developer signs off on this plan.

**Goal:** Reconstruct the messy `202605_resolute` build branch as a clean, reviewable commit history on a new branch `202605_resolute_clean`, based on pristine upstream `sonic-net/202605`, organized into PR-sized units, ready to formalize.

**Architecture:** File-group *replay*, not commit rebase. Start a fresh branch from `sonic-net/202605@fe5ae5db`; for each PR unit, bring the *final tree state* of that group of files from `202605_resolute` (`git checkout 202605_resolute -- <files>`) and make GPG-signed commit(s). The build-env / docker layer variants use a **fork(verbatim trixie copy) → adapt** two-commit pattern so reviewers see the real ~176-line delta, not ~1.2K "new" lines. Submodules keep the **15 MUST-FORK** canonical gitlinks and **de-fork** `sonic-linux-kernel` + `dhcpmon` to upstream. `rules/config.user` is never included. **Broadcom is the last PR.** The final tree is asserted against the tested resolute tip (minus intentional deltas) and a smoke build gates completion.

**Tech Stack:** git (+ GPG signing), SONiC make build (`BLDENV=resolute`), bash.

## Execution status (updated after reviewer feedback)

The stack was built and pushed (no PRs opened), then rebuilt after review found Resolute-added build-time `sed`/`awk` source mutations. The final implementation now follows each package's native SONiC patch flow:

- Parent packages: isc-dhcp / libyang-python / libnl3 / hsflowd use their existing STGit/quilt series; rasdaemon extends its existing `git apply` convention; psample (no pre-existing series) uses one explicit local patch. Existing upstream hsflowd `_VERSION_` substitution is intentionally preserved.
- `sonic-sairedis`: nested upstream SAI Doxyfile mutation is a sairedis-owned DEP-3 patch with conditional apply + clean restore; SAI stays at upstream v1.18.1.
- `sonic-swss-common`: `$function`→`$action` is fixed directly at the owned interface source; `sonic-gnmi` consumes it without `sed`.
- Exact-source `--fuzz=0` + byte-equivalence checks pass; swss-common and GNMI clean-cache builds pass; all parent Makefiles parse with recipe tabs intact.

Final pushed stack tips (all GPG-signed; `pr01` unchanged):

| Branch | Tip |
|---|---|
| `202605_resolute_pr01` | `f2ddaacca0` |
| `202605_resolute_pr02` | `da20fea22f` |
| `202605_resolute_pr03` | `32bf0d29d7` |
| `202605_resolute_pr04` | `fa536c2703` |
| `202605_resolute_pr05` | `5de7afbc84` |
| `202605_resolute_pr06` | `fccea22c77` |
| `202605_resolute_pr07` | `7d8b3a230f` |
| `202605_resolute_pr08` | `082e13c744` |


## Global Constraints

- **Base:** `sonic-net/202605` @ `fe5ae5db34` (fetch fresh each run). NEVER push to `sonic-net`.
- **Canonical change set base (manifest):** the resolute fork point `67a348840b`. `git diff --name-only 67a348840b 202605_resolute` = 315 files = exactly Canonical's changes.
- **GPG sign every commit:** `commit.gpgsign=true` already set; key `521ED6CE84B5C2B2BAF7AAEA90E19370EEEF6873`; author/committer `Sheldon Qi <sheldon.qi@canonical.com>`. Use `git commit -S` explicitly.
- **Co-author trailer on every commit:** `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
- **Canonical submodule commits** live only on `canonical/<sub>:202605_resolute`; the 15 MUST-FORK gitlinks already exist there and are reachable (verified). No submodule rebase is required — we keep the existing (tested) fork commits.
- **`.gitmodules`:** URLs `https` (never ssh); edit each `[submodule "<name>"]` section in place; every section keeps `path =`.
- **`rules/config.user` must never appear** in any commit of `202605_resolute_clean` (it is `.gitignore:8`-covered host-local config).
- **Broadcom** (`platform/broadcom/**`) is the FINAL PR.
- **Staging discipline:** stage only intended paths; NEVER `git add -A` at repo root (the worktree holds ~88 build-artifact entries).
- **Repo:** all work in `/home/sheldon-qi/sonic-buildimage-resolute`. The plan doc lives in the main repo on `202605_resolute_doc`.
- **Non-destructive:** `202605_resolute` is not modified; the clean history is a NEW branch. Nothing is pushed until the developer decides.
- **Shell non-persistence:** shell functions/vars do NOT survive between separate command runs. The on-disk `/tmp/reso_buckets.txt` and `/tmp/fork_map.txt` (Task 0) DO persist. At the start of each task's shell, re-define the helper: `files() { grep "^$1"$'\t' /tmp/reso_buckets.txt | cut -f2; }`.

## Intentional deltas vs the tested `202605_resolute` tip (expected in the final assertion)

Because the base is *current* upstream (fe5ae5db, ~17 days ahead of the fork point) and we drop 3 things, `git diff 202605_resolute_clean 202605_resolute` is expected to show ONLY:
1. `rules/config.user` — present on resolute, absent on clean (dropped).
2. `src/dhcpmon`, `src/sonic-linux-kernel` — clean points at upstream; resolute at (older upstream / dead canonical fork).
3. The ~9 upstream-advanced files resolute never touched (`.azure-pipelines/...UpgrateVersion.yml`, `dockers/docker-ptf/Dockerfile.j2`, `platform/broadcom/sonic-platform-modules-arista` gitlink, `src/sonic-frr/patch/0115-*`, `0116-*`, `series`, `src/sonic-platform-common` gitlink, `src/sonic-yang-mgmt/sonic_yang_ext.py`, `.../test_sonic_yang.py`) — clean carries upstream's newer version; resolute the older.

Any file outside this list appearing in that diff is a BUG in the reorg — investigate before finalizing.

---

## Branch model — stacked per-PR branches

Produce a STACK of branches, one per PR, each based on the previous — NOT a single branch:

`sonic-net/202605` → `202605_resolute_pr01` → `202605_resolute_pr02` → … → `202605_resolute_pr08`

- Task 0 creates `202605_resolute_pr01` from `sonic-net/202605`; PR-1's commits land on it.
- Each later Task N (N≥2) BEGINS with `git checkout -b 202605_resolute_pr0N` from the current tip (= the previous PR's branch), then makes that PR's commit(s).
- PR N's reviewable diff = `git diff 202605_resolute_pr0(N-1) 202605_resolute_pr0N` (pr01 diffs against `sonic-net/202605`).
- Top of stack `202605_resolute_pr08` holds the complete history. **Wherever this document says `202605_resolute_clean`, read the top-of-stack branch `202605_resolute_pr08`.**
- PR→branch→task: pr01=Task1 build-env; pr02=Task2 submodules; pr03=Task3 kernel; pr04=Task4 common dockers; **pr05=Task5 src pkgs (incl. the bash 5.3 plugin port `4174a0650e` + socat `5b94e4511a`)**; pr06=Task6 grub2 (`2db1d3f95d`); pr07=Task7 other platforms; pr08=Task8 Broadcom (last).
- Nothing is pushed and no PR is opened until the developer explicitly authorizes it.

---

## Task 0: Preparation — fetch base, create branch, generate manifests

**Files:**
- Create (scratch): `/tmp/reso_manifest.txt`, `/tmp/reso_buckets.txt`, `/tmp/fork_map.txt`
- Branch: `202605_resolute_clean`

- [ ] **Step 1: Fetch base + verify tips**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
git fetch sonic-net 202605
test "$(git rev-parse sonic-net/202605)" = "fe5ae5db34"$(git rev-parse sonic-net/202605 | cut -c11-) && echo OK  # informational
git rev-parse --short sonic-net/202605 202605_resolute   # expect fe5ae5db34 / 4174a0650e
```
Expected: `sonic-net/202605` = `fe5ae5db34`, `202605_resolute` = `4174a0650e` (Phase A socat/grub/bash already committed).

- [ ] **Step 2: Generate the Canonical change-set manifest (315 files)**

```bash
git diff --name-only 67a348840b 202605_resolute | sort > /tmp/reso_manifest.txt
wc -l /tmp/reso_manifest.txt   # expect 315
```

- [ ] **Step 3: Bucket every manifest file into a PR group** (broadcom last)

```bash
awk '{
  f=$0
  if (f==".gitmodules") g="G09_submodules";
  else if (f=="src/sonic-linux-kernel"||f=="src/dhcpmon") g="G00_deforkskip";
  else if (f=="src/wpasupplicant/sonic-wpa-supplicant") g="G09_submodules";
  else if (f ~ /^src\/[^\/]+$/) g="G09_submodules";
  else if (f=="platform/vpp") g="G09_submodules";
  else if (f=="src/sonic-linux-kernel") g="G03_kernel";
  else if (f=="AGENTS.md") g="G01_build_env";
  else if (f ~ /^sonic-slave-resolute\//) g="G01_build_env";
  else if (f=="Makefile"||f=="Makefile.work"||f=="build_debian.sh"||f=="build_image.sh"||f=="slave.mk"||f=="rules/config.user"||f=="installer/default_platform.conf") g="G01_build_env";
  else if (f ~ /^scripts\/build_/) g="G01_build_env";
  else if (f ~ /^files\/(apt|build_templates|dsc)\//) g="G01_build_env";      # PR-7 folded into PR-1
  else if (f ~ /^dockers\/docker-(base|config-engine|swss-layer)-resolute\//) g="G02_variants";
  else if (f ~ /^rules\/docker-.*-resolute\./) g="G02_variants";
  else if (f ~ /^dockers\/.*Dockerfile\.j2$/||f ~ /^dockers\/dockerfile-macros/||f ~ /^dockers\/docker-database\/database_config/) g="G04_common_dockers";
  else if (f ~ /^rules\/docker-/) g="G04_common_dockers";
  else if (f ~ /^rules\/linux-kernel/) g="G03_kernel";
  else if (f ~ /^platform\/broadcom\//) g="G09z_broadcom";
  else if (f ~ /^platform\//) g="G07_other_platforms";
  else if (f ~ /grub2/) g="G06_grub2";
  else if (f ~ /^rules\/sonic-fips/) g="G05_src_pkgs";
  else if (f ~ /^rules\//) g="G05_src_pkgs";
  else if (f ~ /^src\//) g="G05_src_pkgs";
  else g="G99_UNASSIGNED";
  print g"\t"f
}' /tmp/reso_manifest.txt | sort > /tmp/reso_buckets.txt
echo "UNASSIGNED (must be 0):"; grep -c '^G99' /tmp/reso_buckets.txt
cut -f1 /tmp/reso_buckets.txt | sort | uniq -c
```
Expected: `UNASSIGNED = 0`. A helper: `files() { grep "^$1"$'\t' /tmp/reso_buckets.txt | cut -f2; }`.

- [ ] **Step 4: Generate the fork→trixie counterpart map (for PR-1 seed)**

```bash
: > /tmp/fork_map.txt
for f in $(files G02_variants) $(grep -E '^G01_build_env\t(sonic-slave-resolute/)' /tmp/reso_buckets.txt | cut -f2); do
  case "$f" in
    sonic-slave-resolute/*)                cp="sonic-slave-trixie/${f#sonic-slave-resolute/}";;
    dockers/docker-base-resolute/*)        cp="dockers/docker-base-trixie/${f#dockers/docker-base-resolute/}";;
    dockers/docker-config-engine-resolute/*) cp="dockers/docker-config-engine-trixie/${f#dockers/docker-config-engine-resolute/}";;
    dockers/docker-swss-layer-resolute/*)  cp="dockers/docker-swss-layer-trixie/${f#dockers/docker-swss-layer-resolute/}";;
    rules/docker-base-resolute.*)          cp="rules/docker-base-trixie.${f##*.}";;
    rules/docker-config-engine-resolute.*) cp="rules/docker-config-engine-trixie.${f##*.}";;
    rules/docker-swss-layer-resolute.*)    cp="rules/docker-swss-layer-trixie.${f##*.}";;
    *) cp="";;
  esac
  # keep only pairs whose trixie counterpart exists on the base
  [ -n "$cp" ] && git cat-file -e "sonic-net/202605:$cp" 2>/dev/null && printf '%s\t%s\n' "$f" "$cp" >> /tmp/fork_map.txt
done
wc -l /tmp/fork_map.txt   # copy-derived variant files (expect ~20-24)
```

- [ ] **Step 5: Create the clean branch from base**

```bash
git checkout -b 202605_resolute_pr01 sonic-net/202605
git submodule sync >/dev/null 2>&1 || true
```
Expected: on `202605_resolute_pr01` (base of the stack), tree == `sonic-net/202605`.

---

## Task 1 (PR-1): Resolute build environment + docker layer variants + rootfs image assembly

**Goal:** the Ubuntu 26.04 builder image, the three resolute docker layer images, the BLDENV wiring, and the target-rootfs apt/extension config — as a `fork(verbatim) → adapt` pair so the review surface is the ~176-line delta, not ~1.2K new lines.

**Files:** groups `G01_build_env` + `G02_variants` (excluding `rules/config.user`). Copy-derived files listed in `/tmp/fork_map.txt`.

**Interfaces — Produces:** `sonic-slave-resolute/` builder image; `docker-{base,config-engine,swss-layer}-resolute` layer images + their `rules/*.mk,.dep`; `BLDENV=resolute` wired into `Makefile`/`Makefile.work`/`slave.mk`. Consumed by PR-4 (service dockers FROM these), PR-7, PR-9.

- [ ] **Step 1: Seed commit — resolute variants as verbatim trixie copies**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
while IFS=$'\t' read -r reso trixie; do
  mkdir -p "$(dirname "$reso")"
  git show "sonic-net/202605:$trixie" > "$reso"
done < /tmp/fork_map.txt
git add -- $(cut -f1 /tmp/fork_map.txt)
git commit -S -F - <<'EOF'
build(resolute): fork trixie build env + layer images -> resolute (verbatim copy)

Seed sonic-slave-resolute/ and docker-{base,config-engine,swss-layer}-resolute
with content byte-identical to their sonic-slave-trixie / docker-*-trixie
counterparts at this base, so the following commit's diff is the Ubuntu-26.04
adaptation only. Verify triviality:
  git show -C -C HEAD   # renders each file as a copy from trixie

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
```

- [ ] **Step 2: Verify the seed is a pure copy of trixie**

```bash
while IFS=$'\t' read -r reso trixie; do
  diff <(git show "sonic-net/202605:$trixie") "$reso" >/dev/null || echo "NOT-IDENTICAL: $reso"
done < /tmp/fork_map.txt
echo "seed check done (no NOT-IDENTICAL lines = pass)"
```
Expected: no output lines → every seeded file equals its trixie counterpart.

- [ ] **Step 3: Adapt commit — bring resolute's real content + new files + wiring (drop config.user)**

```bash
FILES=$( (files G01_build_env; files G02_variants) | grep -v '^rules/config.user$' | sort -u )
git checkout 202605_resolute -- $FILES
git add -- $FILES
git status --short -- rules/config.user   # MUST be empty (never staged)
git commit -S -F - <<'EOF'
build(resolute): adapt build env + layer images to Ubuntu 26.04

Wire BLDENV=resolute into the top-level dispatch and slave.mk build graph; add
the Ubuntu 26.04 sonic-slave-resolute builder and the base/config-engine/
swss-layer resolute docker layer images; retarget the target rootfs apt
sources (one-line /etc/apt/sources.list; deb822 not used, matching Noble +
debootstrap 1.0.142) and the sonic_debian_extension / DSC install hooks.
rules/config.user (host-local, .gitignore-covered) is intentionally excluded.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
```

- [ ] **Step 4: Verify PR-1 tree matches resolute for all PR-1 files except config.user**

```bash
for f in $FILES; do
  git diff --quiet 202605_resolute -- "$f" || echo "MISMATCH: $f"
done
echo "PR-1 content check done (no MISMATCH = pass)"
git cat-file -e HEAD:rules/config.user 2>/dev/null && echo "BUG: config.user present" || echo "config.user absent OK"
```
Expected: no `MISMATCH`, `config.user absent OK`.

---

## Task 2 (PR-2): Submodule pointers — 15 MUST-FORK, de-fork linux-kernel + dhcpmon

**Goal:** retarget the 15 MUST-FORK submodules to their Canonical forks (URL + gitlink) and keep `sonic-linux-kernel` + `dhcpmon` on upstream. Foundational: lands early because later PRs build these submodules into debs.

**Files:** `.gitmodules` + the 15 MUST-FORK gitlinks (`src/sonic-swss-common`, `src/sonic-swss`, `src/sonic-sairedis`, `src/sonic-snmpagent`, `src/sonic-utilities`, `src/sonic-mgmt-framework`, `src/sonic-mgmt-common`, `src/wpasupplicant/sonic-wpa-supplicant`, `src/dhcprelay`, `src/sonic-gnmi`, `src/sonic-bmp`, `src/sonic-dash-api`, `src/sonic-dash-ha`, `src/sonic-stp`, `platform/vpp`). NOT changed: `src/sonic-linux-kernel`, `src/dhcpmon` (left at base = upstream).

**Interfaces — Produces:** parent gitlinks pointing at `canonical/<sub>:202605_resolute` tips (state-2, reachable). Consumed by every build PR.

- [ ] **Step 1: Bring the 15 MUST-FORK gitlinks from resolute**

```bash
MUST_FORK="src/sonic-swss-common src/sonic-swss src/sonic-sairedis src/sonic-snmpagent src/sonic-utilities src/sonic-mgmt-framework src/sonic-mgmt-common src/wpasupplicant/sonic-wpa-supplicant src/dhcprelay src/sonic-gnmi src/sonic-bmp src/sonic-dash-api src/sonic-dash-ha src/sonic-stp platform/vpp"
git checkout 202605_resolute -- $MUST_FORK
```

- [ ] **Step 2: Bring resolute's .gitmodules, then de-fork linux-kernel in place**

```bash
git checkout 202605_resolute -- .gitmodules
# revert ONLY sonic-linux-kernel URL back to upstream (dhcpmon is already sonic-net in resolute's .gitmodules)
git config -f .gitmodules submodule.sonic-linux-kernel.url https://github.com/sonic-net/sonic-linux-kernel
grep -n 'sonic-linux-kernel' -A2 .gitmodules   # confirm sonic-net URL, path= intact
```
Expected: `sonic-linux-kernel` URL = `https://github.com/sonic-net/sonic-linux-kernel`, `dhcpmon` = sonic-net. `src/sonic-linux-kernel` and `src/dhcpmon` gitlinks remain at the base (upstream) value — do NOT `git checkout 202605_resolute` for them.

- [ ] **Step 3: Reachability + hygiene assertions before commit**

```bash
# .gitmodules hygiene
test "$(grep -cE 'url *= *(ssh://|git@)' .gitmodules)" = 0 && echo "https OK"
s=$(grep -c '^\[submodule' .gitmodules); p=$(grep -cE '^\s*path *=' .gitmodules); test "$s" = "$p" && echo "path= OK ($s)"
# every MUST-FORK gitlink is reachable on its canonical remote
for m in $MUST_FORK; do
  sha=$(git ls-tree HEAD "$m" | awk '{print $3}')
  url=$(git config -f .gitmodules --get "submodule.$(basename "$m").url" 2>/dev/null || git config -f .gitmodules --get-regexp 'url' | grep -i "$(basename "$m")" | awk '{print $2}')
  git ls-remote "$url" | grep -q "$sha" && echo "REACHABLE $m" || echo "UNREACHABLE(exact-tip? try refspec) $m $sha $url"
done
```
Expected: `https OK`, `path= OK (52)`, and every MUST-FORK `REACHABLE` (if an exact-tip grep misses due to GitHub ref truncation, re-check `git ls-remote <url> refs/heads/202605_resolute`). Do NOT commit until all reachable.

- [ ] **Step 4: Commit the submodule PR (atomic)**

```bash
git add -- .gitmodules $MUST_FORK
git commit -S -F - <<'EOF'
build(resolute): retarget submodules to Canonical forks; keep kernel+dhcpmon upstream

Point 15 build-consumed submodules at canonical/<sub>:202605_resolute (each
carries a required, upstream-absent resolute toolchain fix: C++17, py3.14,
cmake>=3.5, go-redis, SWIG 4.4, dpkg-strict metadata). .gitmodules URLs are
https and edited in place. sonic-linux-kernel is de-forked (kernel is procured
prebuilt from the Launchpad PPA; the submodule is not built) and dhcpmon stays
upstream (unchanged by Canonical). All 15 fork gitlinks verified reachable on
their canonical remote.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
```

- [ ] **Step 5: (execution-time, REMOTE-DESTRUCTIVE — needs explicit developer go) delete abandoned canonical fork branches**

The de-forked submodules (`sonic-linux-kernel`; `dhcpmon` if it ever had one) abandon their `canonical/<sub>:202605_resolute` fork branch. Once the stack supersedes `202605_resolute`, delete each fork branch (local + remote). This is REMOTE-DESTRUCTIVE and also makes the OLD `202605_resolute` parent's linux-kernel gitlink unreachable on canonical — do it ONLY after the developer confirms the old branch is superseded.

```bash
# detect
for sub in sonic-linux-kernel sonic-dhcpmon; do
  git ls-remote https://github.com/canonical/$sub refs/heads/202605_resolute 2>/dev/null | grep -q . \
    && echo "EXISTS: canonical/$sub:202605_resolute (deletion candidate)" \
    || echo "none:   canonical/$sub:202605_resolute"
done
# delete ONLY after developer go:
#   git push git@github.com:canonical/sonic-linux-kernel.git --delete 202605_resolute
#   git -C src/sonic-linux-kernel branch -D 202605_resolute 2>/dev/null || true
```

---

## Task 3 (PR-3): Kernel procurement (Launchpad PPA) + rootfs ABI

**Files:** `G03_kernel` minus `src/sonic-linux-kernel` (that gitlink stays upstream, handled by exclusion): `rules/linux-kernel.mk`, `rules/linux-kernel.dep`.

- [ ] **Step 1: Bring kernel rules (not the submodule gitlink)**

```bash
KFILES=$(files G03_kernel | grep -v '^src/sonic-linux-kernel$')
git checkout 202605_resolute -- $KFILES
git add -- $KFILES
git commit -S -F - <<'EOF'
build(resolute): procure linux-sonic 7.0.0-1002 kernel from Launchpad PPA

Fetch the prebuilt linux-sonic 7.0.0-1002 image/modules/headers debs via
SONIC_ONLINE_DEBS from the canonical-kernel-team PPA instead of building the
kernel from source; drop the now-inert source-build path.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
```

- [ ] **Step 2: Verify**

```bash
for f in $KFILES; do git diff --quiet 202605_resolute -- "$f" || echo "MISMATCH $f"; done; echo done
```
Expected: no MISMATCH.

---

## Task 4 (PR-4): Common service dockers → resolute base

**Files:** `G04_common_dockers` (the ~59 `dockers/*/Dockerfile.j2` + `rules/docker-*.mk` trixie→resolute base renames + a few runtime fixes).

- [ ] **Step 1: Bring + commit**

```bash
DFILES=$(files G04_common_dockers)
git checkout 202605_resolute -- $DFILES
git add -- $DFILES
git commit -S -F - <<'EOF'
build(resolute): rebase common service dockers onto resolute layer images

Retarget the shared service-docker Dockerfile.j2 base images and their
rules/docker-*.mk from the trixie layer images to the resolute ones, plus the
resolute runtime fixes (rsync /etc/hosts exclude, teamd iproute2, libxml2-16,
database DEV default).

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
```

- [ ] **Step 2: Verify** — `for f in $DFILES; do git diff --quiet 202605_resolute -- "$f" || echo "MISMATCH $f"; done; echo done` → no MISMATCH.

---

## Task 5 (PR-5): src package build fixes (includes Phase A socat + bash)

**Files:** `G05_src_pkgs` (rules/*.mk for src pkgs + `src/**` non-submodule sources: bash, socat, libnl3, libyang3(+py3), isc-dhcp, kdump-tools, makedumpfile, openssh, lldpd, radius, rasdaemon, sflow, systemd-sonic-generator, sonic-fib, sonic-eventd, sonic-fips, etc.). This group already contains the Phase A `socat` (5b94e4511a) and `bash` (4174a0650e) content because `202605_resolute` holds it.

- [ ] **Step 1: Bring + commit**

```bash
SFILES=$(files G05_src_pkgs)
git checkout 202605_resolute -- $SFILES
git add -- $SFILES
git commit -S -F - <<'EOF'
build(resolute): src package build fixes for the Ubuntu 26.04 toolchain

Rebuild core libs and tools from Ubuntu source with GCC15/LTO/cmake4/dpkg-1.23
compat: bash (plugin patch ported to 5.3, restores bash-tacplus), socat
(enable_readline), libnl3, libyang3(+py3), isc-dhcp, openssh, lldpd, radius,
rasdaemon, sflow, systemd-sonic-generator, sonic-fib, and dget-based source
fetch with dbgsym tolerance; FIPS reuses trixie binaries (INCLUDE_FIPS-gated).

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
```
*Optional finer split (reviewer preference): core-libs / dget-fetch / toolchain-compat / FIPS as separate commits — split `$SFILES` accordingly.*

- [ ] **Step 2: Verify** — `for f in $SFILES; do git diff --quiet 202605_resolute -- "$f" || echo "MISMATCH $f"; done; echo done` → no MISMATCH.

---

## Task 6 (PR-6): grub2 (Ubuntu split; includes Phase A grub fix)

**Files:** `G06_grub2` — `rules/grub2.mk`, `src/grub2/**`, `src/grub2-unsigned/**` (contains the Phase A dead-`patch-overlayfs-ln.sh` removal, 2db1d3f95d).

- [ ] **Step 1: Bring + commit**

```bash
GFILES=$(files G06_grub2)
git checkout 202605_resolute -- $GFILES
git add -- $GFILES
git commit -S -F - <<'EOF'
build(resolute): split grub2 into src:grub2 + src:grub2-unsigned for Ubuntu

Ubuntu splits grub-efi-amd64(-bin) into src:grub2-unsigned; build both from the
Ubuntu pool via dget. The harmless 'ln: hard link not allowed for directory'
staging warning does not affect the produced .debs and needs no patch (the lost
patch-overlayfs-ln.sh call is removed).

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
```

- [ ] **Step 2: Verify** — `for f in $GFILES; do git diff --quiet 202605_resolute -- "$f" || echo "MISMATCH $f"; done; echo done` → no MISMATCH.

---

## Task 7 (PR-7): Other (non-Broadcom) platforms

**Files:** `G07_other_platforms` — `platform/{components,marvell-prestera,marvell-teralynx,mellanox,nokia-vs,nvidia-bluefield,pddf,template,vpp,vs}/…` (trixie→resolute docker base renames + nokia init + pddf gpio Linux-7.0 fix). NOTE: only `platform/vs/**` is exercised by the tested vs build; Marvell/Mellanox/NVIDIA are rebased-but-unbuilt in this migration.

- [ ] **Step 1: Bring + commit**

```bash
PFILES=$(files G07_other_platforms)
git checkout 202605_resolute -- $PFILES
git add -- $PFILES
git commit -S -F - <<'EOF'
build(resolute): rebase non-broadcom platform dockers onto resolute base

Retarget syncd/gbsyncd/saiserver docker variants for vs (tested), Marvell
Prestera/Teralynx, Mellanox/NVIDIA-BlueField and gearbox platforms onto the
resolute config-engine layer, plus nokia 7215 init and the pddf multifpgapci
gpio Linux-7.0 API fix. Non-vs vendors are rebased for consistency but were not
built in this migration.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
```
*Optional split: `platform/vs/**` (tested) as its own commit vs the other-vendor renames (unverified). vpp retain-vs-drop is an open decision (default: retain).* 

- [ ] **Step 2: Verify** — `for f in $PFILES; do git diff --quiet 202605_resolute -- "$f" || echo "MISMATCH $f"; done; echo done` → no MISMATCH.

---

## Task 8 (PR-8, LAST): Broadcom platform (Linux 7.0 kmod adaptation)

**Files:** `G09z_broadcom` — all of `platform/broadcom/**` (129 files, ~9.3K lines: `saibcm-modules{,-dnx,-legacy-th}.patch/**`, `sswsyncd`, `rules.mk`, `docker-syncd-brcm*`, `docker-saiserver-brcm*`, `docker-pde`, and 18 `sonic-platform-modules-*.patch/**`).

**Granularity (default; the one part flagged for final review):** 3 commits for saibcm (by source tree) + 1 docker-variant commit + 18 per-vendor kmod commits, OR collapse to fewer. Default below = per-vendor for the 18 (reviewer-friendly for 7.9K lines), saibcm as 1 commit.

- [ ] **Step 1: Broadcom docker variants + saibcm + sswsyncd**

```bash
BRD_CORE=$(files G09z_broadcom | grep -E '^platform/broadcom/(saibcm-modules|sswsyncd|rules\.mk|docker-syncd-brcm|docker-saiserver-brcm|docker-pde)')
git checkout 202605_resolute -- $BRD_CORE
git add -- $BRD_CORE
git commit -S -F - <<'EOF'
build(broadcom): saibcm-modules Linux 7.0 kmod patch series + docker variants

saibcm-modules{,-dnx,-legacy-th} Linux 7.0 kmod compat patch series (kernel
ABI, kbuild, from_timer, MODULE_IMPORT_NS, etc.), sswsyncd C++ buildflags, and
retarget the broadcom syncd/saiserver/pde docker variants to the resolute
config-engine layer.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
```

- [ ] **Step 2: Per-vendor kmod patch commits (18)**

```bash
for v in accton alphanetworks arista cel dell delta ingrasys inventec juniper micas mitac nexthop nokia quanta ragile ruijie tencent ufispace; do
  VF=$(files G09z_broadcom | grep -E "^platform/broadcom/sonic-platform-modules-$v\.patch/")
  [ -z "$VF" ] && continue
  git checkout 202605_resolute -- $VF
  git add -- $VF
  git commit -S -F - <<EOF
build(broadcom): $v platform kmods Linux 7.0 API-drift patch series

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
done
```

- [ ] **Step 3: Verify all broadcom files landed**

```bash
for f in $(files G09z_broadcom); do git diff --quiet 202605_resolute -- "$f" || echo "MISMATCH $f"; done; echo done
```
Expected: no MISMATCH.

---

## Task 9: Final verification + smoke build (gate)

- [ ] **Step 1: Full-tree assertion vs the tested resolute tip**

```bash
git diff --name-only 202605_resolute_clean 202605_resolute | sort > /tmp/clean_vs_reso.txt
cat /tmp/clean_vs_reso.txt
```
Expected: ONLY the intentional deltas listed in "Intentional deltas" above — `rules/config.user`, `src/dhcpmon`, `src/sonic-linux-kernel`, and the ~9 upstream-advanced files. **Anything else = a reorg bug; fix before proceeding.**

- [ ] **Step 2: Commit count / structure sanity**

```bash
git log --oneline sonic-net/202605..202605_resolute_clean | cat
git log --format='%G?' sonic-net/202605..202605_resolute_clean | sort | uniq -c   # all 'G'
```
Expected: ~10 PR-unit commits (+18 broadcom = ~28 total), every one GPG `G`.

- [ ] **Step 3: config.user really gone from all commits**

```bash
git log -p sonic-net/202605..202605_resolute_clean -- rules/config.user | head   # expect EMPTY
```
Expected: empty (never introduced).

- [ ] **Step 4: Smoke build** (absorbs 17 days of upstream on the ~9 files — must re-verify)

```bash
flock /tmp/sonic-pkgbuild.lock make BLDENV=resolute SONIC_DPKG_CACHE_METHOD=none target/sonic-vs.bin 2>&1 | tail -40
ls -la target/sonic-vs.bin
```
Expected: `target/sonic-vs.bin` builds. (For a faster gate, first build a representative package set touched by the ~9 upstream deltas, e.g. `target/debs/resolute/sonic-frr_*` given the two new frr patches, before the full image.)

- [ ] **Step 5: Handoff — do NOT push**

Report the branch, commit list, the `git diff` assertion result, and the smoke-build result to the developer. Pushing / force-pushing / PR creation is a separate, developer-authorized step (delivery decision was: local clean branch, push later).

---

## Self-Review

- **Spec coverage:** every one of the 315 manifest files maps to exactly one PR group (Task 0 Step 3 asserts `UNASSIGNED = 0`); Tasks 1–8 each `git checkout` their group and Task 9 asserts the total tree. Phase A fixes (socat/grub/bash) ride in PR-5/PR-6 via the resolute tree state. `config.user` handled by exclusion (no removal commit needed).
- **Base-shift risk:** the ~9 upstream-advanced files are intentionally taken at the upstream (base) version; Task 9 Step 1 whitelists exactly them, and Step 4 smoke-builds to catch any interaction (esp. the two new frr patches + arista/platform-common gitlinks).
- **Submodule compliance:** Task 2 asserts https + path= + per-fork reachability BEFORE committing; de-fork of linux-kernel/dhcpmon is by exclusion + one in-place URL edit; no rebase (existing fork commits reused). No push to sonic-net anywhere.
- **Decided:** vpp is RETAINED (kept as a MUST-FORK submodule in PR-2). Broadcom ships as ONE giant PR (`pr08`, 19 commits, ~9.3K lines) for now; splitting it into stacked sub-PRs is deferred to a later pass. bash is NOT split out — it rides in PR-5 (`pr05`).
