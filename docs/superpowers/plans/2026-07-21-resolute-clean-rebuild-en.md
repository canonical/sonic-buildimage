# Resolute Fully-Clean From-Scratch Build — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** In `/home/sheldon-qi/sonic-buildimage-resolute`, perform one fully-clean end-to-end from-scratch build: clean all accumulated build artifacts (keeping only git-tracked config, host fixes, and upstream base images), then build `sonic-vs.img.gz` from scratch, and on success build `sonic-broadcom.bin` from scratch.

**Architecture:** Use the SONiC official `make reset` for repo-level deep clean (preserves all tracked files, wipes fsroot*/target/src extractions and resets submodules), plus explicit docker and shared-cache cleanup, then two backgrounded `make` builds with log capture and periodic polling. The broadcom platform's 22 fix commits are already on `canonical/202605_resolute` (pushed), so the broadcom rebuild is expected to be clean — no new fixes unless a fresh drift surfaces.

**Tech Stack:** SONiC buildimage Makefile.work/slave.mk, Docker CE 29.6.1 (default DinD `--privileged`), `sg docker` for non-login-shell docker access, AppArmor `gs` override + `ip_tables` host modules as prerequisites.

## Global Constraints

- Build repo: `/home/sheldon-qi/sonic-buildimage-resolute`, branch `202605_resolute`.
- Doc repo: `/home/sheldon-qi/sonic-buildimage`, branch `202605_resolute_doc` (the resolute build branch has no `docs/` per AGENTS.md).
- Build host: Ubuntu 26.04 (ext4 root, kernel 7.0.0-27, docker-ce 29.6.1, default DinD `--privileged`).
- Docker commands run via `sg docker -c '...'` (non-login shell needs this to access the docker group).
- Git timing: ALL commits during this work stay local (do not push) until both vs and broadcom builds pass; then push all at once (per spec 7.3).
- Submodule fix gitlink rule (spec 7.2): a submodule fix must bump the parent gitlink locally (`git add <sub>` in parent) or `make reset`'s `git submodule update --init` checks out the old gitlink and discards the fix.
- AGENTS.md Editing Rules govern any source/rule fix: minimal scope, patch files (not direct edits to external sources), preserve pins.
- Submodule commits push to `canonical/<sub>:202605_resolute` only — never `sonic-net/` (upstream, not ours to write).
- Bilingual deliverables: every doc this plan produces is two files (`-en.md` + `-zh.md`), English the source of truth.
- Host fixes must be in place before any build: AppArmor `gs` local override (`/etc/apparmor.d/local/gs`) and `ip_tables` module (`lsmod | grep ip_tables`).
- Memory refs: [[sonic-build-restore]], [[sonic-build-caches]], [[sonic-resolute-broadcom-build-success]], [[sonic-resolute-submodule-object-store-corruption]].

## File Structure

| File / Artifact | Responsibility | Create/Modify |
|---|---|---|
| `docs/superpowers/plans/2026-07-21-resolute-clean-rebuild-{en,zh}.md` | this plan | Create (doc repo) |
| `docs/superpowers/specs/2026-07-21-resolute-clean-rebuild-design-{en,zh}.md` | the spec this plan implements | Already created |
| `target/build-vs.log` | vs build stdout/stderr (backgrounded) | Create (build repo, reset clears) |
| `target/build-broadcom.log` | broadcom build stdout/stderr (backgrounded) | Create (build repo) |
| `target/sonic-vs.img.gz` | vs build output (~2G) | Create (build repo) |
| `target/sonic-broadcom.bin` | broadcom build output (~2.3G ONIE installer) | Create (build repo) |
| Docker images / `fsroot*` / `target/` / `/var/cache/sonic/artifacts` | cleaned, not committed artifacts | Remove |
| Source/rule files (`rules/*.mk`, `*.j2`, submodule sources) | modified ONLY if a build error requires it (fix-loop, Task 6) | Modify only on error |

No buildimage source files are modified by this plan unless a build error genuinely requires it (Task 6 fix-loop). All cleanup targets are build artifacts, never committed.

---

## Task 1: Pre-flight safety checks (hard gate before deleting anything)

**Files:**
- None modified; read-only verification in `/home/sheldon-qi/sonic-buildimage-resolute` and on the host.

**Interfaces:**
- Consumes: the resolute build repo at branch `202605_resolute`, the host's AppArmor + `ip_tables` state.
- Produces: a confirmed-clean git worktree, intact submodule object store, reachable gitlinks, in-place host fixes, passwordless sudo — all gates passed before Task 2 runs.

- [ ] **Step 1: Confirm git worktree has no uncommitted tracked changes that `reset --hard` would discard**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
git status -s | grep -vE '^\?\?|^ M src/' || echo "CLEAN (only untracked src/ extractions or fsroot)"
```
Expected: `CLEAN (...)` or lines that are only untracked `src/*/` extractions / fsroot (rebuildable). If any tracked file shows as modified (` M` on a non-src path), STOP — resolve it (stash or commit) before proceeding, because `make reset` will discard it.

- [ ] **Step 2: Dry-run `git clean` to preview what will be deleted (catch any wanted file caught by the sweep)**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
git clean -xfdf -n > /tmp/clean-preview.txt
wc -l /tmp/clean-preview.txt        # how many files would be removed
# review the full list (do NOT truncate — the point is to catch a wanted file anywhere in the list)
less /tmp/clean-preview.txt         # or: grep for anything you want to keep, e.g. grep -vE '^(target/|src/|\.pytest_cache)'
```
Expected: a file count (can be hundreds/thousands — target/ + extracted `src/*/` + `.pytest_cache`). Review the full list in `less` (or `grep -v` the obviously-rebuildable prefixes to surface anything unusual). If an unwanted-deletion candidate appears (a file you actually want to keep that isn't a rebuildable artifact), note it and resolve before Task 2. Do NOT use `head` here — truncating the list defeats the gate's purpose.

- [ ] **Step 3: Check submodule object-store health (use full `git submodule status` for a fast check; fsck only the anomalous ones)**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
# git submodule status walks all submodules (incl. nested) and is fast; a broken submodule shows an anomaly or errors
git submodule status --recursive 2>&1 | tee /tmp/submod-status.txt
echo "--- anomalous lines (errors beyond space/- prefix) ---"
grep -iE 'error|fatal|missing|not a git repo|no such' /tmp/submod-status.txt || echo "all submodules OK"
# ONLY if the grep above hits a submodule, run fsck on THAT one to locate:
# cd <that-submodule> && git fsck --no-dangling 2>&1 | tail -5
```
Expected: `git submodule status --recursive` lists every submodule with its commit SHA (space prefix = initialized, `-` prefix = not initialized, which is fine — Task 2 re-inits). The grep should print `all submodules OK` (no error/fatal/missing). If a submodule hits `missing blob` etc., STOP and fix THAT ONE submodule via deinit + re-clone per [[sonic-resolute-submodule-object-store-corruption]] before continuing. Do NOT run a full `foreach fsck` (many submodules → slow, and `submodule status` already surfaces breakage fast).

- [ ] **Step 4: Confirm submodule gitlinks are reachable (Canonical-modified submodules pushed)**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
# list submodules whose URL points at canonical (these carry Canonical commits that must be on canonical/<sub>:202605_resolute)
git config -f .gitmodules --get-regexp 'submodule.*.url' | grep -i canonical
```
Expected: the list of submodules Canonical has forked. For each, the gitlink commit (from `git submodule status`) must exist on `canonical/<sub>:202605_resolute`. (Broadcom's 22 fix commits are already pushed — per [[sonic-resolute-broadcom-build-success]] — so these are expected reachable.) If any is local-only, it must be pushed to `canonical/<sub>:202605_resolute` before Task 2's `git submodule update --init` can resolve it.

- [ ] **Step 5: Confirm host fixes are in place (AppArmor gs + ip_tables module)**

```bash
ls /etc/apparmor.d/local/gs && echo "gs override present" || echo "GS OVERRIDE MISSING — bash.pdf build will fail"
lsmod | grep -q ip_tables && echo "ip_tables loaded" || echo "IP_TABLES MISSING — iptables-legacy in DinD will fail"
```
Expected: `gs override present` AND `ip_tables loaded`. If either is MISSING, restore it first (AppArmor: write `/etc/apparmor.d/local/gs` with `owner file rw /sonic/**,` and `owner file rw /var/*/**,`, then `sudo apparmor_parser -r /etc/apparmor.d/gs`; ip_tables: `echo ip_tables | sudo tee /etc/modules-load.d/ip_tables.conf && sudo modprobe ip_tables`) before proceeding.

- [ ] **Step 6: Confirm passwordless sudo (needed by `make reset`'s `sudo rm -rf fsroot*`)**

```bash
sudo -n true && echo "passwordless sudo OK" || echo "NEEDS passwordless sudo"
```
Expected: `passwordless sudo OK`. If not, configure NOPASSWD for the build user before proceeding.

- [ ] **Step 7: Commit the plan doc (local only, no push — per 7.3)**

```bash
cd /home/sheldon-qi/sonic-buildimage
git add docs/superpowers/plans/2026-07-21-resolute-clean-rebuild-en.md docs/superpowers/plans/2026-07-21-resolute-clean-rebuild-zh.md
git commit -m "docs: resolute fully-clean from-scratch build plan (zh + en)"
```
Expected: commit created on `202605_resolute_doc`. Do NOT push yet (push happens in Task 7 after both builds pass).

---

## Task 2: Official `make reset` (repo-level deep clean)

**Files:**
- Remove (root-owned): `fsroot.docker.resolute/` (~68G), `fsroot-broadcom/`, `fsroot-broadcom-dnx/`, `fsroot-broadcom-legacy-th/`, `fsroot-vs/`.
- Remove: `target/` (incl. `target/ccache/`, `target/vcache/`), extracted `src/*/` version dirs, `.pytest_cache/`.
- Preserve: all git-tracked files (`rules/config.user`, `AGENTS.md`, `.gitmodules`, source, git history).

**Interfaces:**
- Consumes: Task 1's passed gates (clean git, intact submodules, passwordless sudo).
- Produces: a reset repo worktree with no build artifacts and submodules re-initialized at their gitlink commits.

- [ ] **Step 1: Run the official reset (UNATTENDED so it skips the y/N prompt)**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
make BLDENV=resolute UNATTENDED=y reset 2>&1 | tail -40
```
Expected: `Reset complete!`. The target does `sudo rm -rf fsroot*` → `git clean -xfdf` → `git reset --hard` → `git submodule foreach` clean+reset+remote update → `git submodule update --init --recursive`. This is the slow part (re-init of submodules).

- [ ] **Step 2: Remove root-owned large files the `fsroot*` glob does not match (fallback)**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
sudo rm -f dockerfs.tar.gz fs.squashfs fs.zip
sudo rm -rf fsroot*            # fallback in case the reset's sudo glob missed any
ls -la | grep -E 'fsroot|\.tar\.gz|\.squashfs|\.zip'   # expect NO output
```
Expected: no output from the `ls | grep` (all root-owned large files gone). If anything remains, remove it explicitly.

- [ ] **Step 3: Verify tracked config survived the reset**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
git status -s | grep -E 'config.user|AGENTS.md|gitmodules' && echo "UNEXPECTED change to tracked config" || echo "tracked config intact"
test -f rules/config.user && head -1 rules/config.user
```
Expected: `tracked config intact` and `rules/config.user` still present (first line is a comment). `rules/config.user` is git-tracked, so `reset --hard` restored it to its committed state — it must still be here.

- [ ] **Step 4: Verify target/ and fsroot* are gone**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
du -sh target/ fsroot* 2>/dev/null || echo "target/ and fsroot* absent (good)"
```
Expected: `target/ and fsroot* absent (good)` (the `du` errors because they no longer exist).

---

## Task 3: Docker cleanup (testbed containers + SONiC build images, preserve upstream base images)

**Files:**
- Remove (containers, 10): `ptf_vms6-1`, `sonic-mgmt`, `ceos_vms6-1_VM0100..0103`, `net_vms6-1_VM0100..0103`.
- Remove (images, 16): all `sonic-slave-*` (11: resolute×3, trixie×4, bookworm×4), `docker-sonic-mgmt`, `docker-ptf` (local), `docker-database`, `docker-macsec`, `docker-dhcp-relay`.
- Preserve (upstream base images): `ubuntu:*`, `debian:*`, `ceosimage:*`, `multiarch/qemu-user-static`, `alpine`, `p4lang/*`, `publicmirror.azurecr.io/debian:*`, `sonicdev-microsoft.azurecr.io:443/docker-ptf`.

**Interfaces:**
- Consumes: Task 2's reset repo (no longer references these containers/images during build).
- Produces: a docker daemon holding only upstream base images + build cache/dangling cleared, freeing ~98G.

- [ ] **Step 1: Stop and remove the 10 testbed containers**

```bash
sg docker -c 'docker rm -f \
  ptf_vms6-1 sonic-mgmt \
  ceos_vms6-1_VM0100 ceos_vms6-1_VM0101 ceos_vms6-1_VM0102 ceos_vms6-1_VM0103 \
  net_vms6-1_VM0100 net_vms6-1_VM0101 net_vms6-1_VM0102 net_vms6-1_VM0103' 2>&1 | tail -15
```
Expected: each container name printed (removed). If a name is already gone, docker prints it with a "No such container" note — acceptable.

- [ ] **Step 2: Remove the 16 SONiC build-output images (slaves + local testbed + build runtime)**

```bash
sg docker -c 'docker rmi -f \
  sonic-slave-resolute-sheldon-qi:d4568f6ea37 \
  sonic-slave-resolute:eee7031281d tmp-sonic-slave-resolute:eee7031281d \
  sonic-slave-trixie:0a98d89ae3c tmp-sonic-slave-trixie:0a98d89ae3c \
  sonic-slave-trixie-sheldon-qi:92fdf9e0a2c sonic-slave-trixie-sheldon-qi:3bf70d08d22 \
  sonic-slave-bookworm:edc8bd76260 tmp-sonic-slave-bookworm:edc8bd76260 \
  sonic-slave-bookworm-sheldon-qi:82749adf7f6 sonic-slave-bookworm-sheldon-qi:db5f4be378a \
  docker-sonic-mgmt:latest docker-ptf:latest \
  docker-database:latest docker-macsec:latest docker-dhcp-relay:latest' 2>&1 | tail -20
```
Expected: each image's SHA printed (untagged/deleted). Some may share layers; docker handles dedup. If an image is already gone, a "No such image" note appears — acceptable.

- [ ] **Step 3: Clear build cache and dangling images**

```bash
sg docker -c 'docker builder prune -af' 2>&1 | tail -3
sg docker -c 'docker image prune -f' 2>&1 | tail -3
```
Expected: `Total reclaimed space:` lines with non-trivial bytes (build cache ~16G). Dangling image count may be 0 if Step 2 already cleared them.

- [ ] **Step 4: Verify only upstream base images remain**

```bash
sg docker -c 'docker images' 2>&1 | grep -E 'sonic-slave|docker-(sonic-mgmt|ptf|database|macsec|dhcp)' && echo "UNEXPECTED build image still present" || echo "build images cleared"
sg docker -c 'docker images' 2>&1 | grep -ciE 'ubuntu|debian|ceos|multiarch|alpine|p4lang'
```
Expected: `build images cleared` (first grep empty) and a non-zero count (second grep) confirming upstream base images (ubuntu/debian/ceos/etc.) are preserved.

- [ ] **Step 5: Confirm disk reclaimed**

```bash
df -h / | tail -1
sg docker -c 'docker system df' 2>&1 | head -6
```
Expected: noticeably more free space than before Task 2/3 (combined ~114G freed across fsroot/target/docker/artifacts). `docker system df` Images size now reflects only base images.

---

## Task 4: Clear shared dpkg cache and finalize cleanup verification

**Files:**
- Remove: `/var/cache/sonic/artifacts/*` (~16G dpkg + version cache).
- Preserve: `/var/cache/sonic/artifacts/` directory itself, recreated with `root:root` + `777` so the build can rewrite it.

**Interfaces:**
- Consumes: Tasks 2–3 (repo + docker cleaned).
- Produces: an empty shared cache dir with correct perms; the cleanup phase (spec §4) is fully complete and verified before builds begin.

- [ ] **Step 1: Clear the shared dpkg cache**

```bash
sudo rm -rf /var/cache/sonic/artifacts/*
sudo chown root:root /var/cache/sonic/artifacts
sudo chmod 777 /var/cache/sonic/artifacts
ls -ld /var/cache/sonic/artifacts
```
Expected: `drwxrwxrwx ... root root ... /var/cache/sonic/artifacts` — directory present, empty, world-writable so the DinD build can repopulate it. (This also drops the sibling trixie clone's dpkg cache — it repopulates on its next build, costing time once, no breakage.)

- [ ] **Step 2: Final cleanup verification (spec §4e)**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
echo "--- repo artifacts ---"
du -sh target/ fsroot* 2>/dev/null || echo "target/ and fsroot* absent"
echo "--- docker build images ---"
sg docker -c 'docker images' 2>/dev/null | grep -E 'sonic-slave|docker-(sonic-mgmt|ptf|database|macsec|dhcp)' || echo "no SONiC build images"
echo "--- shared cache ---"
sudo find /var/cache/sonic/artifacts -type f 2>/dev/null | wc -l   # expect 0
echo "--- disk ---"
df -h / | tail -1
```
Expected: `target/ and fsroot* absent`; `no SONiC build images`; file count `0`; and free space reflecting the full ~114G reclaimed. If any check fails, revisit Task 2/3/4-step-1 before building.

- [ ] **Step 3: Re-confirm host fixes survived (they are host-side, unaffected by cleanup, but the build depends on them)**

```bash
lsmod | grep -q ip_tables && echo "ip_tables loaded" || echo "ip_tables MISSING"
test -f /etc/apparmor.d/local/gs && echo "gs override present" || echo "gs override MISSING"
```
Expected: `ip_tables loaded` AND `gs override present`. (These are host-side; Task 1 Step 5 already confirmed them — this is a cheap re-check right before the build starts.)

---

## Task 5: Build sonic-vs.img.gz from scratch (background + polling)

**Files:**
- Create: `target/build-vs.log`, `target/sonic-vs.img.gz` (~2G) in the build repo.

**Interfaces:**
- Consumes: Tasks 1–4 (clean repo, docker, cache; host fixes in place).
- Produces: `target/sonic-vs.img.gz` and a build log; on success, the prerequisite for Task 6's broadcom build. On a build error requiring a fix, hand off to the fix-loop (Task 7) instead of broadcom.

- [ ] **Step 1: init + configure vs**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
sg docker -c 'make init' 2>&1 | tail -10
sg docker -c 'make PLATFORM=vs configure' 2>&1 | tail -10
```
Expected: `make init` re-initializes submodules (already done by reset, but harmless/cheap); `make configure` writes platform config. Both exit 0.

- [ ] **Step 2: Launch the vs build in the background, capturing the log**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
mkdir -p target
sg docker -c 'make PLATFORM=vs target/sonic-vs.img.gz' > target/build-vs.log 2>&1 &
echo "vs build PID: $!"
```
Expected: a backgrounded shell job; `target/build-vs.log` begins receiving output. Note the PID for later `kill` if needed.

- [ ] **Step 3: Poll the build log periodically (slave derivation + full recompile is slow)**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
tail -15 target/build-vs.log
echo "--- still running? ---"
jobs -l 2>/dev/null; ps aux | grep -c '[m]ake.*sonic-vs'
```
Expected: log shows progress (slave image build, then package/docker builds). Repeat this step every ~10–20 min until the job completes. The build is done when `jobs -l` shows it as `Done` or the process count drops to 0.

- [ ] **Step 4: On completion, verify success**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
ls -lh target/sonic-vs.img.gz 2>/dev/null && echo "vs image present" || echo "vs image MISSING"
tail -20 target/build-vs.log | grep -iE 'error|fail' && echo "BUILD HAD ERRORS" || echo "log tail clean"
```
Expected: `vs image present` with `target/sonic-vs.img.gz` ~2G, and `log tail clean` (no ERROR/FAIL in the last 20 lines). If errors appear, do NOT proceed to broadcom — go to the Fix-Loop sub-flow (it returns here on success, then you continue to Task 6).

- [ ] **Step 5: (Optional, quick sanity) confirm the vs image is Ubuntu 26.04 resolute**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
# the .img.gz is a gzipped raw image; mount the root partition read-only to read os-release
TMP=$(mktemp -d); gunzip -c target/sonic-vs.img.gz > "$TMP/vs.img" 2>/dev/null
sudo mkdir -p /mnt/vs-check; sudo losetup -fP "$TMP/vs.img" -o $(sudo fdisk -l "$TMP/vs.img" | awk 'NR>1 && $2=="*"{$1=""} /Linux/{print $2; exit}' | tr -d '*') 2>/dev/null
# simpler: skip losetup, just confirm the file exists and size — full os-release check is optional
ls -lh target/sonic-vs.img.gz
rm -rf "$TMP"
```
Expected: `target/sonic-vs.img.gz` ~2G. The os-release check is optional machinery; the authoritative confirmation is the broadcom-vs migration report's prior validation that resolute vs boots Ubuntu 26.04. Keep this step light — the image existing + clean log is sufficient to proceed.

---

## Task 6: Build sonic-broadcom.bin from scratch (background + polling)

**Files:**
- Create: `target/build-broadcom.log`, `target/sonic-broadcom.bin` (~2.3G ONIE installer) in the build repo.

**Interfaces:**
- Consumes: Task 5's successful vs build (confirms the slave image + toolchain derive cleanly end-to-end).
- Produces: `target/sonic-broadcom.bin`. Broadcom's 22 fix commits are already on `canonical/202605_resolute` (pushed, per [[sonic-resolute-broadcom-build-success]]), so this rebuild is expected to be clean — no new fixes unless a fresh Linux-7.0 API drift surfaces. If an error requires a fix, go to the fix-loop (Task 7) before this task's Step 4.

- [ ] **Step 1: Confirm the exact broadcom make target before building**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
# the broadcom design doc specifies TH3 / standard bin; confirm the target name
grep -rn 'sonic-broadcom' Makefile.work slave.mk 2>/dev/null | grep -iE 'target|\.bin' | head -10
# also cross-check the broadcom build-success memory and the broadcom design doc
```
Expected: the make target line for `sonic-broadcom.bin` (or the platform's standard bin target) is found. If the prior successful build used a different target (e.g. a TH3-specific bin), use that exact target/flags. Record the confirmed target here: `____________`.

- [ ] **Step 2: Configure broadcom**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
sg docker -c 'make PLATFORM=broadcom configure' 2>&1 | tail -10
```
Expected: exits 0, writes broadcom platform config. (`make init` already ran in Task 5; submodules are initialized.)

- [ ] **Step 3: Launch the broadcom build in the background, capturing the log**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
mkdir -p target
# use the exact target confirmed in Step 1 (default shown; replace if Step 1 found otherwise)
sg docker -c 'make PLATFORM=broadcom target/sonic-broadcom.bin' > target/build-broadcom.log 2>&1 &
echo "broadcom build PID: $!"
```
Expected: backgrounded job; `target/build-broadcom.log` begins receiving output. Broadcom is the slowest build (opennsl kmod + 18 vendor submodule rebuilds), so expect a long run.

- [ ] **Step 4: Poll the broadcom build log periodically**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
tail -15 target/build-broadcom.log
echo "--- still running? ---"
jobs -l 2>/dev/null; ps aux | grep -c '[m]ake.*sonic-broadcom'
```
Expected: log shows progress (slave reuse, then opennsl/vendor kmod + syncd + image assembly). Repeat every ~10–20 min. Done when the job shows `Done` or process count 0.

- [ ] **Step 5: On completion, verify success**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
ls -lh target/sonic-broadcom.bin 2>/dev/null && echo "broadcom image present" || echo "broadcom image MISSING"
tail -20 target/build-broadcom.log | grep -iE 'error|fail' && echo "BUILD HAD ERRORS" || echo "log tail clean"
```
Expected: `broadcom image present` with `target/sonic-broadcom.bin` ~2.3G, and `log tail clean`. If errors appear, go to the Fix-Loop sub-flow (it returns here on success, then you continue to Task 7). If clean, both builds are validated and Task 7's push can proceed.

---

## Fix-Loop (sub-flow, insertable at any build error — NOT a linear Task 7)

**What this is:** A fix-loop is a branch-and-return sub-flow, not a sequential task on the main path. The main path is linear: Task 1 → 2 → 3 → 4 → 5 (vs) → 6 (broadcom) → 7 (push). A fix-loop **interrupts** Task 5 or Task 6 when a build error genuinely requires a source/rule fix, runs its 4 steps, then **explicitly returns to the interrupted build task** to continue the main path. It can fire in the vs stage (Task 5) or the broadcom stage (Task 6) — wherever an error needs a fix.

**Files:**
- Modify (only on error, parent repo): `rules/*.mk`, `*.j2` templates, Dockerfiles, etc. — on `202605_resolute`.
- Modify (only on error, submodule): submodule sources on the submodule's `202605_resolute` branch + parent gitlink bump.

**Interfaces:**
- Consumes: a build error from Task 5 (vs) or Task 6 (broadcom).
- Produces: a committed fix + a full re-clean + a from-scratch rebuild of the failed target; on success, control returns to the task that was interrupted.

**Trigger point:** Any step in Task 5 Step 4 or Task 6 Step 5 that prints `BUILD HAD ERRORS`. (Transient/flaky errors that do NOT need a fix — just rerun the build, no fix-loop.)

- [ ] **FL-1: Locate the root cause via systematic-debugging; write the fix per AGENTS.md Editing Rules**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
# inspect the failing log section for the real error (not the symptom)
tail -60 target/build-vs.log   # or target/build-broadcom.log — whichever failed
```
Expected: the actual error (compile/link/test/package failure) is identified. The fix follows AGENTS.md Editing Rules: minimal scope, patch file (not direct edit to external submodule source), preserve pins. If the "fix" is not genuinely needed (transient/flaky), skip the fix-loop and just rerun the build.

- [ ] **FL-2: Commit the fix (parent repo OR submodule + gitlink bump)**

```bash
# CASE A — parent-repo fix (rules/*.mk, *.j2, Dockerfile, etc.):
cd /home/sheldon-qi/sonic-buildimage-resolute
git add <changed-files>
git commit -m "fix: <concise description>"

# CASE B — submodule fix (the submodule's 202605_resolute branch):
cd /home/sheldon-qi/sonic-buildimage-resolute/<submodule>
git add <changed-files>
git commit -m "fix: <concise description>"
cd /home/sheldon-qi/sonic-buildimage-resolute
git add <submodule>          # bump the parent gitlink to the new submodule commit
git commit -m "fix: bump <submodule> gitlink for <description>"
```
Expected: commit(s) created locally. For CASE B, BOTH the submodule commit AND the parent gitlink bump must land — `make reset`'s `git submodule update --init` otherwise checks out the old gitlink and discards the submodule fix (spec 7.1/7.2). Do NOT push yet (timing per 7.3; reachable from local `.git` without push).

- [ ] **FL-3: Re-run the FULL cleanup (spec §4, all of 4a–4e) — do not skip docker (4c)**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
# 4a: reset
make BLDENV=resolute UNATTENDED=y reset 2>&1 | tail -15
# 4b: root-owned residuals
sudo rm -f dockerfs.tar.gz fs.squashfs fs.zip; sudo rm -rf fsroot*
# 4c: docker cleanup (NON-SKIPPABLE — a stale slave image would hide a Dockerfile/submodule fix)
sg docker -c 'docker rmi -f $(sg docker -c "docker images -q sonic-slave-resolute* tmp-sonic-slave-resolute* sonic-slave-resolute-sheldon-qi*" 2>/dev/null) 2>/dev/null; docker builder prune -af; docker image prune -f' 2>&1 | tail -5
# 4d: shared dpkg cache
sudo rm -rf /var/cache/sonic/artifacts/*; sudo chmod 777 /var/cache/sonic/artifacts
```
Expected: reset + residuals + docker + cache all re-cleared. Step 4c is non-skippable: if the fix touched the slave Dockerfile or a submodule feeding the slave, the stale slave image must be removed or it will not re-derive and the fix will not take effect (spec 7.2 step 3).

- [ ] **FL-4: Rebuild the failed target from scratch, then RETURN to the main path**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
# rerun the build that failed — re-init/configure first since reset cleared target/
sg docker -c 'make init'
sg docker -c 'make PLATFORM=<vs|broadcom> configure'         # whichever failed
sg docker -c 'make PLATFORM=<vs|broadcom> <target/sonic-vs.img.gz|target/sonic-broadcom.bin>' > target/build-<platform>.log 2>&1 &
```
Expected: backgrounded rebuild with a fresh log. Poll it (Task 5 Step 3 / Task 6 Step 4) until done, then re-verify (Task 5 Step 4 / Task 6 Step 5).

**Return point (explicit — this is what makes the loop close):**
- If the fix-loop fired in the **vs stage (Task 5)** and the rebuild now passes verification → **return to Task 5 Step 5** (vs sanity), then continue to **Task 6** (broadcom build) as normal. If broadcom later errors, a new fix-loop fires there.
- If the fix-loop fired in the **broadcom stage (Task 6)** and the rebuild now passes verification → **return to Task 6 Step 5** (broadcom verify), then continue to **Task 7** (final push) as normal.
- If the rebuild **fails again** → repeat the fix-loop from FL-1 (new root cause). The loop only exits when the interrupted build passes its verification step. Do NOT proceed to the next task or to push until the interrupted build is green.

---

## Task 7: Final push (always, once vs AND broadcom both pass)

**Files:**
- Push: local commits accumulated during this work — doc branch (spec + plan), and any fix commits + gitlink bumps from fix-loop CASE A/B (if any ran) on the build repo + submodules.

**Interfaces:**
- Consumes: a passing vs build (Task 5) AND a passing broadcom build (Task 6) — neither still inside a fix-loop.
- Produces: all local commits pushed to canonical remotes; both git repos in sync.

- [ ] **Step 1: Push the doc branch (spec + plan)**

```bash
cd /home/sheldon-qi/sonic-buildimage
git log --oneline origin/202605_resolute_doc..HEAD   # preview local commits to push
git push origin 202605_resolute_doc
```
Expected: spec + plan commits (the spec-phase commits + the plan commit) pushed to `canonical/sonic-buildimage:202605_resolute_doc`. Verify: `git status` shows in sync with origin.

- [ ] **Step 2: Push submodule fix commits (if any fix-loop CASE B ran) to canonical — never sonic-net**

```bash
# only if a fix-loop ran CASE B — for each modified submodule:
cd /home/sheldon-qi/sonic-buildimage-resolute/<submodule>
git remote -v | grep canonical    # confirm canonical remote exists
git push canonical 202605_resolute
cd /home/sheldon-qi/sonic-buildimage-resolute
```
Expected: each modified submodule's local commits pushed to `canonical/<sub>:202605_resolute`. NEVER push to `sonic-net/` (upstream, not ours to write — AGENTS.md Submodules).

- [ ] **Step 3: Push the parent build repo (fix commits + gitlink bumps, if any fix-loop ran)**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
git log --oneline origin/202605_resolute..HEAD   # preview local commits (empty if no fixes needed)
git push origin 202605_resolute
```
Expected: if fix-loops created parent-repo fix commits (CASE A) or gitlink bumps (CASE B), they push to `canonical/sonic-buildimage:202605_resolute`. If no fixes were needed (both builds clean from the start), this push is a no-op (`Everything up-to-date`).

- [ ] **Step 4: Final verification — both images present and both logs clean**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
ls -lh target/sonic-vs.img.gz target/sonic-broadcom.bin
tail -5 target/build-vs.log | grep -iE 'error|fail' && echo "vs log has errors" || echo "vs log clean"
tail -5 target/build-broadcom.log | grep -iE 'error|fail' && echo "broadcom log has errors" || echo "broadcom log clean"
cd /home/sheldon-qi/sonic-buildimage && git status -s | head    # doc repo clean (pushed)
cd /home/sheldon-qi/sonic-buildimage-resolute && git status -s | head   # build repo: only build artifacts (untracked)
```
Expected: both images present (vs ~2G, broadcom ~2.3G); both logs clean; both git repos in sync with their canonical remotes (build repo may show untracked build artifacts in `target/`, which is expected and never committed).

---

## Done

Both `target/sonic-vs.img.gz` and `target/sonic-broadcom.bin` built from a fully-clean state, all local commits pushed to canonical remotes, and the resolute build chain verified end-to-end reproducible.
