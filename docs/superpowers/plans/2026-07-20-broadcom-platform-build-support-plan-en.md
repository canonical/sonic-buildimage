# Broadcom Platform Build Support Implementation Plan (resolute / TH3 / standard three-bin set)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On the `202605_resolute` branch, make `make PLATFORM=broadcom` produce the standard `sonic-broadcom.bin` (with XGS + DNX + legacy-th three syncd containers + three opennsl kmods).

**Architecture:** The closed-source side only involves libsaibcm .debs + diagnostic binaries (already de-risked: deps are all `>=` lower bounds, downloads are reachable); the core blocker is the open-source opennsl kernel modules needing realignment to the resolute `linux-sonic 7.0.0-1002-sonic` kernel. The three `saibcm-modules{,-dnx,-legacy-th}` submodules each get one quilt patch, modifying `debian/rules` ABI/path derivation + `debian/control` hardcoded Depends, leveraging the SONiC build graph's built-in `<SRC_PATH>.patch/series` quilt apply mechanism. Verification proceeds through three incremental milestones: kmod -> syncd containers -> bin.

**Tech Stack:** GNU make (quilt patch + SONiC build graph), debhelper/dpkg (opennsl kmod packaging), Docker (syncd containers), SONiC buildimage slave.mk build graph.

**Corresponding spec:** `docs/superpowers/specs/2026-07-20-broadcom-platform-build-support-design-zh.md`

**Dual-repo convention:**
- This plan document lives in the doc repo `/home/sheldon-qi/sonic-buildimage` (`202605_resolute_doc` branch)
- All code changes live in the build repo `/home/sheldon-qi/sonic-buildimage-resolute` (`202605_resolute` branch). Below, "the repo" refers to the build repo, and all paths default to relative to the build repo root.

## Global Constraints

(excerpted from spec §2-§9; implicit requirements for every task)

- Target kernel: **resolute `linux-sonic 7.0.0-1002-sonic`** (`rules/linux-kernel.mk:32`, `KVERSION=7.0.0-1002-sonic`). ABI string `7.0.0-1002-sonic` has no arch suffix.
- Kernel headers install layout (verified, confirmed via `dpkg-deb -c`):
  - arch headers dir: `/usr/src/linux-headers-7.0.0-1002-sonic/` (= KVERSION, no `-amd64`, contains Makefile/Module.symvers/scripts/build-script tree)
  - common headers dir: `/usr/src/linux-sonic-headers-7.0.0-1002/` (prefix is `linux-sonic-headers-`, not trixie's `linux-headers-...-common-sonic`)
  - arch package already ships `include/generated`, `include/config`, `arch/x86/include/generated`, `arch/x86/module.lds` (on trixie these were in common and needed symlinks; on resolute they're already in arch)
- Exported kernel variables (from `rules/linux-kernel.mk:21`, `export KVERSION_SHORT KVERSION KERNEL_VERSION KERNEL_ABISUFFIX KERNEL_FEATURESET KERNEL_PKGVERSION`): `KVERSION=7.0.0-1002-sonic`, `KERNEL_VERSION=7.0.0`, `KERNEL_ABISUFFIX=-1002`, `KERNEL_FEATURESET=sonic`.
- SAI versions unchanged: XGS `libsaibcm_15.2.0.0.0.0.3.1`, DNX `14.1.0.1.0.0.27.0`, legacy-th `13.2.1.120` (download channels confirmed HTTP 200, updated 2026-06-19, deps satisfiable).
- Three submodule gitlinks unchanged, source code untouched; only patched via `<SRC_PATH>.patch/` quilt patches (auto-applied by slave.mk:811).
- AGENTS.md: Jinja2 templates as source, don't bypass slave.mk build graph, minimal scoped changes, pinned versions not arbitrarily bumped.
- Success criteria (no hardware): full build runs through + image structure complete + syncd containers build. kmods only need to demonstrate "can compile + packaging deps correct"; runtime verification not required.
- Language convention: this plan is in Chinese with a separate English version at `2026-07-20-broadcom-platform-build-support-plan-en.md`.

## Pre-Build Conventions (common to every task)

- **Build command prefix**: All `make` commands execute at the build repo root, requiring the resolute build environment. Standard prefix (hereinafter `$MAKE`):
  ```bash
  cd /home/sheldon-qi/sonic-buildimage-resolute
  export BLDENV=resolute NORESOLUTE=0
  # PLATFORM=broadcom written into rules/config.user or passed on command line; see Task 0
  ```
- **Build is DinD (in-container) execution**: `make` launches the sonic-slave-resolute container for compilation. A single full build is very slow; each task should build minimal targets, do not run `make all`.
- **Build artifact paths**: `target/debs/resolute/<deb>`, `target/docker-*.gz`, `target/sonic-broadcom.bin`.
- **Failure investigation entry points**: When a build fails, check logs under `target/` + slave container output. If patch doesn't apply, check quilt errors; if kmod compilation fails, check the `debian/rules build-arch` section output; if apt Depends fails, check `apt install` error messages for `Depends: ... but ... is not installable`.
- **Caching**: `rules/config.user` already has SONiC version cache / docker layer cache enabled (memory record). Repeated builds will hit cache; if you changed patches, `rm -f target/debs/resolute/<corresponding-deb>` to force rebuild, or clear the corresponding entry in `target/debs/resolute/.cache/`.

---

## Task 0: Pre-Build Baseline Confirmation + Reproduce Current Failure (TDD Starting Point)

**Purpose:** Lock down the build repo in a clean state, default `PLATFORM=broadcom`, and first **prove that the current build fails** (expected failure), serving as the control baseline for subsequent fixes. No code changes, only configuration + triggering.

**Files:**
- Read: `rules/config.user` (confirm PLATFORM setting)
- (Possibly Modify): `rules/config.user` (if PLATFORM is not broadcom)

**Interfaces:**
- Produces: build repo `PLATFORM=broadcom` ready state; a "current-state failure" log (saved to `/tmp/broadcom-baseline-fail.log`), for comparison in Tasks 1-5.

- [ ] **Step 1: Confirm build repo is clean + branch is correct**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
git status
git rev-parse --abbrev-ref HEAD
```
Expected: `nothing to commit, working tree clean`; branch `202605_resolute`. If not clean, stash first or confirm irrelevant.

- [ ] **Step 2: Confirm PLATFORM=broadcom**

```bash
grep -nE "^PLATFORM|^CONFIGURED_PLATFORM" rules/config.user
```
Expected: Has `PLATFORM ?= broadcom` or `PLATFORM = broadcom`. If still `vs`, change to broadcom:
```bash
# Change the PLATFORM line in rules/config.user to broadcom
sed -i 's/^PLATFORM ?= .*/PLATFORM ?= broadcom/' rules/config.user
grep -n "^PLATFORM" rules/config.user
```
Expected: `PLATFORM ?= broadcom`.

- [ ] **Step 3: Trigger kmod build (expected failure — this is the TDD "red light")**

Build a single kmod set (XGS) minimal target:
```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
export BLDENV=resolute NORESOLUTE=0
make target/debs/resolute/opennsl-modules_15.2.0.0.0.0.0.0_amd64.deb 2>&1 | tee /tmp/broadcom-baseline-fail.log
```
Expected: **Failure**. Expected failure points (any of): `debian/rules` has `cd /usr/src/linux-headers-7.0.0-sonic-amd64` (KVER missing `-1002`, dir nonexistent) or `make -C systems/linux/user/...` can't find kernel source tree. Note the last ~30 lines of failure; after Task 1 fix, this should pass by comparison.

- [ ] **Step 4: Do not commit (no code changes in this task)**

If you want to keep the config.user PLATFORM change as the broadcom development default, you may commit it separately:
```bash
git add rules/config.user
git commit -m "build: default PLATFORM=broadcom for broadcom bring-up"
```
Otherwise don't commit; subsequent tasks will carry `PLATFORM=broadcom` on the command line. **Commit is recommended**, to avoid carrying the variable on every make command.

---

## Task 1: XGS kmod Patch (M1 Core)

**Purpose:** Create a quilt patch for the `saibcm-modules` (XGS) submodule, enabling opennsl-modules to compile against the resolute `7.0.0-1002-sonic` kernel. This is the hardest point of the entire plan; validate it independently.

**Files:**
- Create: `platform/broadcom/saibcm-modules.patch/series`
- Create: `platform/broadcom/saibcm-modules.patch/0001-resolute-kernel-abi.patch`
- Reference (do not modify): `platform/broadcom/saibcm-modules/debian/rules` (217 lines), `platform/broadcom/saibcm-modules/debian/control` (13 lines Depends)

**Interfaces:**
- Consumes: `KVERSION`/`KERNEL_VERSION`/`KERNEL_ABISUFFIX` (exported by `rules/linux-kernel.mk:21`, passed into build container by slave.mk)
- Produces: `target/debs/resolute/opennsl-modules_15.2.0.0.0.0.0.0_amd64.deb` (depends on `linux-image-7.0.0-1002-sonic`, ABI aligned to 7.0.0-1002-sonic)

**Change rationale (confirmed by measurement):**
trixie's `debian/rules:37-39`:
```make
KVER := $(word 1,$(subst -, ,$(KVERSION)))
KVER_ARCH := $(KVER)-sonic-amd64
KVER_COMMON := $(KVER)-common-sonic
```
- trixie `KVERSION=6.12.41+deb13-sonic-amd64` -> `KVER=6.12.41+deb13`, `KVER_ARCH=6.12.41+deb13-sonic-amd64` (correct), `KVER_COMMON=6.12.41+deb13-common-sonic` (correctly maps to `/usr/src/linux-headers-6.12.41+deb13-common-sonic/`)
- resolute `KVERSION=7.0.0-1002-sonic` -> `KVER=7.0.0` (WRONG: drops `-1002`), and the dir prefix + naming convention have both changed

resolute actual layout (confirmed via `dpkg-deb -c`):
- arch dir: `/usr/src/linux-headers-7.0.0-1002-sonic/` (= `$(KVERSION)`, no `-amd64`)
- common dir: `/usr/src/linux-sonic-headers-7.0.0-1002/` (prefix `linux-sonic-headers-`, = `linux-sonic-headers-$(KERNEL_VERSION)$(KERNEL_ABISUFFIX)`)

**Patch approach**: Stop using `word 1` to truncate KVERSION; directly use already-exported variables to assemble.

- [ ] **Step 1: Enter submodule directory, confirm current state of files to be modified**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute/platform/broadcom/saibcm-modules
sed -n '35,40p' debian/rules   # view KVER section
sed -n '13p' debian/control    # view Depends
```
Expected: `rules` lines 37-39 as above; `control:13` = `Depends: linux-image-6.12.41+deb13-sonic-amd64-unsigned`.

- [ ] **Step 2: Use quilt to create a new patch inside the submodule**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute/platform/broadcom/saibcm-modules
export QUILT_PATCHES=../saibcm-modules.patch
mkdir -p ../saibcm-modules.patch
quilt new 0001-resolute-kernel-abi.patch
```

- [ ] **Step 3: Add debian/rules KVER section changes to the patch**

```bash
quilt edit debian/rules
```
Change lines 37-39:
```make
KVER := $(word 1,$(subst -, ,$(KVERSION)))
KVER_ARCH := $(KVER)-sonic-amd64
KVER_COMMON := $(KVER)-common-sonic
```
to:
```make
# Resolute linux-sonic 7.0.0-1002-sonic: ABI string has no arch suffix,
# and common headers dir uses 'linux-sonic-headers-' prefix.
# Use exported KERNEL_VERSION / KERNEL_ABISUFFIX instead of parsing KVERSION.
KVER_ARCH := $(KVERSION)
KVER_COMMON := $(KERNEL_VERSION)$(KERNEL_ABISUFFIX)
```
(Delete the `KVER` line; it's no longer used. After editing, run `grep -n '\bKVER\b' debian/rules` to confirm no remaining references; if `KVER` is referenced elsewhere, keep `KVER := $(KVERSION)` for compatibility.)

- [ ] **Step 4: Fix common path prefix in debian/rules (critical)**

`debian/rules` has numerous `/usr/src/linux-headers-$(KVER_COMMON)` references pointing to the common dir, but the resolute common dir prefix is `linux-sonic-headers-` not `linux-headers-`. Change them to `/usr/src/linux-sonic-headers-$(KVER_COMMON)`:

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute/platform/broadcom/saibcm-modules
grep -n "linux-headers-\$(KVER_COMMON)" debian/rules
```
Expected: multiple occurrences (~lines 68/69/72/92/94-98/102/103/107/134/135/139, etc.). Change each `linux-headers-$(KVER_COMMON)` -> `linux-sonic-headers-$(KVER_COMMON)` one by one.

> Note: arch path `linux-headers-$(KVER_ARCH)` is **not changed** — resolute arch dir prefix is still `linux-headers-`, and `$(KVER_ARCH)` now = `7.0.0-1002-sonic`, assembling to `linux-headers-7.0.0-1002-sonic`.

- [ ] **Step 5: Leave symlink section unchanged for now (save as Step 8 failure fallback)**

trixie's `build-arch` (rules:91-98) creates symlinks in common for `include/generated`, `arch/x86/include/generated`, `arch/x86/module.lds`, `include/config`, `Module.symvers`. resolute's arch package **already ships** these (confirmed by measurement). The XGS version uses `ln -sfn`; `-f` force-overwrite will generally not error. **Leave this step unchanged for now**, keeping minimal changes. If Step 8 fails on these `ln` commands, come back and add `if [ ! -e ... ]` guards (the DNX version rules:96-106 already uses guard-style; can reference that).

- [ ] **Step 6: Add debian/control Depends change to the patch**

```bash
quilt edit debian/control
```
Change line 13:
```
Depends: linux-image-6.12.41+deb13-sonic-amd64-unsigned
```
to:
```
Depends: linux-image-7.0.0-1002-sonic
```

- [ ] **Step 7: Generate patch file + series**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute/platform/broadcom/saibcm-modules
quilt refresh
quilt pop -a
ls -la ../saibcm-modules.patch/
cat ../saibcm-modules.patch/series
```
Expected: `series` content = `0001-resolute-kernel-abi.patch`; the patch file exists under `.patch/`. After `quilt pop -a` the submodule working tree is clean (changes absorbed into the patch).

- [ ] **Step 8: Build XGS kmod, verify pass (M1 green light)**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
export BLDENV=resolute NORESOLUTE=0
rm -f target/debs/resolute/opennsl-modules_15.2.0.0.0.0.0.0_amd64.deb
make target/debs/resolute/opennsl-modules_15.2.0.0.0.0.0.0_amd64.deb 2>&1 | tee /tmp/broadcom-m1-xgs.log
```
Expected: **Success**, producing `target/debs/resolute/opennsl-modules_15.2.0.0.0.0.0.0_amd64.deb`.

Verify dependency:
```bash
dpkg-deb -I target/debs/resolute/opennsl-modules_15.2.0.0.0.0.0.0_amd64.deb | grep -i depends
```
Expected: Contains `Depends: linux-image-7.0.0-1002-sonic`.

- [ ] **Step 8b: Failure fallback (if Step 8 fails)**

- If failure is `cd /usr/src/linux-headers-7.0.0-sonic-amd64` (still old name): patch not fully applied or there are leftover references; `grep -rn "6.12.41\|\bKVER\b\|sonic-amd64" debian/` to find leftovers.
- If failure is `ln -sfn .../include/generated` (symlink): add `if [ ! -e ... ]` guards per Step 5.
- If failure is `make -C systems/linux/user/...` can't find kernel tree: check whether `/usr/src/linux-headers-7.0.0-1002-sonic` exists inside the slave container (`docker exec` into the slave container and `ls /usr/src/`).
After fixing, re-run Step 8.

- [ ] **Step 9: Commit**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
git add platform/broadcom/saibcm-modules.patch/
git commit -m "build(broadcom): opennsl kmod (XGS) patch for resolute linux-sonic 7.0.0-1002

Adapt saibcm-modules debian/rules + control to resolute kernel:
- KVER_ARCH := \$(KVERSION) (arch headers dir = 7.0.0-1002-sonic, no -amd64)
- KVER_COMMON := \$(KERNEL_VERSION)\$(KERNEL_ABISUFFIX) (common dir prefix linux-sonic-headers-)
- common path prefix linux-headers- -> linux-sonic-headers-
- control Depends: linux-image-7.0.0-1002-sonic

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```
Expected: Only `.patch/` directory committed; submodule gitlink unchanged.

---

## Task 2: DNX + legacy-th kmod Patches (M1 Complete)

**Purpose:** Replicate Task 1's patch pattern to the other two submodules. All three KVER sections (37-39) are identical, same fix approach applies; differences are in the rules symlink section style (DNX uses `rm`+`if` guards, XGS/legacy-th use `ln -sfn`).

**Files:**
- Create: `platform/broadcom/saibcm-modules-dnx.patch/{series,0001-resolute-kernel-abi.patch}`
- Create: `platform/broadcom/saibcm-modules-legacy-th.patch/{series,0001-resolute-kernel-abi.patch}`

**Interfaces:**
- Produces: `target/debs/resolute/opennsl-modules-dnx_14.1.0.1.0.0.0.0_amd64.deb`, `opennsl-modules-legacy-th_13.2.1.0_amd64.deb`

- [ ] **Step 1: DNX submodule patch (same as Task 1 Steps 2-7)**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute/platform/broadcom/saibcm-modules-dnx
export QUILT_PATCHES=../saibcm-modules-dnx.patch
mkdir -p ../saibcm-modules-dnx.patch
quilt new 0001-resolute-kernel-abi.patch
quilt edit debian/rules   # same changes as Task 1 Step 3 + Step 4
quilt edit debian/control # Depends -> linux-image-7.0.0-1002-sonic
quilt refresh
quilt pop -a
```
> The DNX rules symlink section already uses `if [ ! -e ... ]` guard style (96-106), so the symlink section basically needs no changes. But the common path prefix still needs changing (same as Step 4).

- [ ] **Step 2: Build DNX kmod**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
export BLDENV=resolute NORESOLUTE=0
rm -f target/debs/resolute/opennsl-modules-dnx_14.1.0.1.0.0.0.0_amd64.deb
make target/debs/resolute/opennsl-modules-dnx_14.1.0.1.0.0.0.0_amd64.deb 2>&1 | tee /tmp/broadcom-m1-dnx.log
```
Expected: Produces DNX kmod deb; `dpkg-deb -I` shows Depends = `linux-image-7.0.0-1002-sonic`.

- [ ] **Step 3: legacy-th submodule patch + build (same as above)**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute/platform/broadcom/saibcm-modules-legacy-th
export QUILT_PATCHES=../saibcm-modules-legacy-th.patch
mkdir -p ../saibcm-modules-legacy-th.patch
quilt new 0001-resolute-kernel-abi.patch
quilt edit debian/rules    # same changes as Task 1 Step 3 + Step 4 (XGS and legacy-th rules are isomorphic, both ln -sfn style)
quilt edit debian/control  # Depends -> linux-image-7.0.0-1002-sonic
quilt refresh
quilt pop -a

cd /home/sheldon-qi/sonic-buildimage-resolute
rm -f target/debs/resolute/opennsl-modules-legacy-th_13.2.1.0_amd64.deb
make target/debs/resolute/opennsl-modules-legacy-th_13.2.1.0_amd64.deb 2>&1 | tee /tmp/broadcom-m1-legacy.log
```
Expected: Produces legacy-th kmod deb, Depends correct.

- [ ] **Step 4: Commit (M1 complete)**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
git add platform/broadcom/saibcm-modules-dnx.patch/ platform/broadcom/saibcm-modules-legacy-th.patch/
git commit -m "build(broadcom): opennsl kmod (dnx + legacy-th) patches for resolute kernel

Same pattern as XGS: KVER_ARCH/KVER_COMMON + common path prefix + control Depends.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

**M1 milestone achieved:** All three opennsl kmod sets build successfully, ABI aligned to resolute linux-sonic 7.0.0-1002-sonic, Depends correct.

---

## Task 3: Three syncd Container Builds (M2)

**Purpose:** Build the `docker-syncd-brcm` / `-dnx` / `-legacy-th` three container images. Verify that syncd/sswsyncd can compile under GCC15/resolute, the closed-source libsaibcm .debs can be installed, and protobuf package name differences are handled.

**Files:**
- No files modified (this task is pure build verification; only add patches if protobuf/GCC issues arise)
- Pay attention to: `platform/broadcom/docker-syncd-brcm.mk`, `sswsyncd.mk`, `sai-xgs.mk`/`sai-dnx.mk`/`sai-legacy-th.mk`

**Interfaces:**
- Consumes: M1's three kmod debs, three closed-source libsaibcm .debs (downloaded)
- Produces: `target/docker-syncd-brcm.gz`, `docker-syncd-brcm-dnx.gz`, `docker-syncd-brcm-legacy-th.gz`

- [ ] **Step 1: Build closed-source SAI .deb downloads (ensure XGS/DNX/legacy-th are downloaded locally first)**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
export BLDENV=resolute NORESOLUTE=0
make target/debs/resolute/libsaibcm_15.2.0.0.0.0.3.1_amd64.deb 2>&1 | tee /tmp/broadcom-m2-sai-xgs.log
make target/debs/resolute/libsaibcm_dnx_14.1.0.1.0.0.27.0_amd64.deb 2>&1 | tee /tmp/broadcom-m2-sai-dnx.log
make target/debs/resolute/libsaibcm_13.2.1.120_amd64.deb 2>&1 | tee /tmp/broadcom-m2-sai-legacy.log
```
Expected: Three closed-source .debs downloaded to `target/debs/resolute/` (they are SONIC_ONLINE_DEBS, pure download, no compilation). Download channels confirmed reachable (HTTP 200).

- [ ] **Step 2: Handle protobuf package name difference (if installing libsaibcm reports unmet)**

If Step 1 or subsequent syncd builds fail on apt installing libsaibcm with `libprotobuf32t64` not available:
```bash
# First check whether resolute's libprotobuf32 Provides: libprotobuf32t64
docker exec sonic-slave-resolute bash -c "apt-cache show libprotobuf32 2>/dev/null | grep -i provides"
# Or check the package produced by protobuf.mk
dpkg-deb -I target/debs/resolute/libprotobuf32_*.deb 2>/dev/null | grep -iE "provides|package"
```
- If already `Provides: libprotobuf32t64` -> no action needed.
- If not -> in `rules/protobuf.mk`, add `Provides: libprotobuf32t64` to the produced `libprotobuf32` (via `_PROVIDES` variable, if the SONiC build graph supports it; otherwise use equivs to stub an empty provides package). After the change, re-run.

- [ ] **Step 3: Build docker-syncd-brcm (XGS)**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
export BLDENV=resolute NORESOLUTE=0
make target/docker-syncd-brcm.gz 2>&1 | tee /tmp/broadcom-m2-syncd-xgs.log
```
Expected: Produces `target/docker-syncd-brcm.gz`.

- [ ] **Step 3b: Failure fallback (GCC15 linking closed-source libsaibcm)**

If failure is in sswsyncd / libsaithrift-dev / syncd compilation linking closed-source libsaibcm:
- C ABI has been stable since GCC5; likely something else (shared naming, header paths).
- Examine the specific error: `undefined reference to`, `cannot find -lsaibcm`, header not found, etc. Handle per the error (may need to add `-I`/`-L` to sswsyncd build or SONiC's `*_BUILD_ENV`/`*_CFLAGS`).
- This is the point marked in spec §5 as "only verifiable by actual build"; treat per specific error.

- [ ] **Step 4: Build docker-syncd-brcm-dnx + -legacy-th**

```bash
make target/docker-syncd-brcm-dnx.gz 2>&1 | tee /tmp/broadcom-m2-syncd-dnx.log
make target/docker-syncd-brcm-legacy-th.gz 2>&1 | tee /tmp/broadcom-m2-syncd-legacy.log
```
Expected: Both container gz produced.

- [ ] **Step 5: If Step 2/3b modified protobuf.mk or other rules, commit; otherwise no commit**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
git status   # confirm whether there are rules/ changes
# If so:
git add rules/protobuf.mk  # or others
git commit -m "build(broadcom): protobuf provides libprotobuf32t64 for closed libsaibcm dep"
```

**M2 milestone achieved:** Three syncd containers built successfully, closed-source libsaibcm installed, protobuf/GCC issues handled.

---

## Task 4: sonic-broadcom.bin Image Assembly (M3, Final Goal)

**Purpose:** Assemble the standard ONIE installer `sonic-broadcom.bin`, containing three syncd containers + kmods + vendor LAZY modules.

**Files:**
- No files modified (pure build, unless one-image has resolute adaptation issues)

**Interfaces:**
- Consumes: M1 three kmods, M2 three syncd containers, three closed-source SAI, all base containers (config-engine-resolute, etc.)
- Produces: `target/sonic-broadcom.bin` <- **final deliverable**

- [ ] **Step 1: Build sonic-broadcom.bin**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
export BLDENV=resolute NORESOLUTE=0
make target/sonic-broadcom.bin 2>&1 | tee /tmp/broadcom-m3-bin.log
```
Expected: Produces `target/sonic-broadcom.bin`.

- [ ] **Step 1b: Failure fallback (one-image assembly / LAZY_BUILD_INSTALLS / RFS / installer)**

- `one-image.mk:148` `LAZY_BUILD_INSTALLS = $(BRCM_OPENNSL_KERNEL) $(BRCM_DNX_OPENNSL_KERNEL)` — ONIE bin only lazy-builds XGS+DNX two kmods (legacy-th only goes into ABOOT swi, not in ONIE bin). If this errors, verify M1 artifact paths are correct.
- RFS/installer phase failure (`build_debian.sh`): check which deb failed to install, kernel boot issues, etc. resolute's grub2/linux-sonic has been proven on VS, but broadcom image is the first run, and there may be broadcom-specific paths (e.g., `/lib/modules/$(KVER_ARCH)` symlinks created by build-arch must exist in the RFS).
- Treat per specific error; may need small patches (but keep changes minimal).

- [ ] **Step 2: Verify image structure**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
ls -la target/sonic-broadcom.bin
file target/sonic-broadcom.bin
# Check that the image contains three syncd containers (unpack with onie-image or sonic_installer)
# Quick check: image size is reasonable (broadcom bin typically ~1-2GB)
```
Expected: File exists, is ONIE installer format, size reasonable.

- [ ] **Step 3: If there are changes, commit; otherwise record final state**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
git status
# If M3 had adaptation changes:
git add -A
git commit -m "build(broadcom): sonic-broadcom.bin assembles on resolute

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

**M3 milestone achieved / Final goal complete:** `target/sonic-broadcom.bin` successfully built.

---

## Rollback and Cleanup

- If a task is thoroughly stuck and needs rollback: `git checkout -- platform/broadcom/saibcm-modules.patch/` etc. (only roll back patch directories; submodule gitlinks were never touched).
- If submodule working tree has quilt residue `.pc/`: `cd platform/broadcom/saibcm-modules && quilt pop -a; rm -rf .pc`.
- Temporary build logs are all under `/tmp/broadcom-*.log`; can be `tail`-ed at any time.

## Success Criteria (Overall)

- [ ] M1: Three `opennsl-modules*.deb` produced, Depends = `linux-image-7.0.0-1002-sonic`
- [ ] M2: Three `docker-syncd-brcm*.gz` produced
- [ ] M3: `target/sonic-broadcom.bin` produced (final goal)
