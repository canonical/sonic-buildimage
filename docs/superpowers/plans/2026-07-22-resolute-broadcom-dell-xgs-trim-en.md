# Resolute Broadcom → dell/XGS-only Trim — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Scope the resolute Broadcom platform to dell (all XGS) — drop DNX/Jericho + legacy-Tomahawk kmods and the 17 non-dell vendor kmod overlays — landing it as one additive commit on `202605_resolute_sheldon` and a matching 2-commit rewrite of review-stack `pr08`.

**Architecture:** Git surgery, not app code. Target A (`202605_resolute_sheldon`, main build tree `/home/sheldon-qi/sonic-buildimage-resolute`) gets one trim commit on top. Target B (`202605_resolute_pr08`, worktree `/home/sheldon-qi/sonic-buildimage-resolute-reorg`) is rebuilt from `pr07` + 2 commits whose broadcom subtree is checked out from the trimmed sheldon, so the two trees differ only by `rules/config.user`. Spec: `docs/superpowers/specs/2026-07-22-resolute-broadcom-dell-xgs-trim-en.md`.

**Tech Stack:** git (worktrees, `checkout <ref> -- path`, `rm`, `commit -S`), quilt 0.69, SONiC `slave.mk` build (`make -f Makefile.work`, `BLDENV=resolute`), GPG signing.

## Global Constraints

- **No push, no PR.** Everything stays local until the user reviews. (spec §8)
- **GPG-sign every commit** (`commit.gpgsign=true` already; identity `Sheldon Qi <sheldon.qi@canonical.com>`). Trailer: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
- **Stage only explicit `platform/broadcom/…` paths. Never `git add -A`/`git add .`** — the main tree carries unrelated build artifacts, `rules/config.user`, and dirty submodule gitlinks (e.g. frr) that must NOT enter any commit. (spec §5.1)
- **`rules/config.user` must never be committed.**
- **Do not touch `AGENTS.md`.**
- **Mechanism rule (spec §3.4):** `saibcm-modules` is a submodule → keep its `.patch/` overlay. `dell`/`sswsyncd` are in-tree → edit source directly (no overlay). Fetched sources (bash/socat/grub) unchanged.
- **End invariant:** `git diff 202605_resolute_pr08 202605_resolute_sheldon` prints only `rules/config.user`.

---

### Task 1: Preflight — backups + clean-index guarantee

**Files:** none modified (safety only).

**Interfaces:**
- Produces: backup refs `202605_resolute_sheldon_pretrim`, `202605_resolute_pr08_pretrim`; recorded tips for rollback.

- [ ] **Step 1: Record current tips and confirm branches**

Run:
```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
git rev-parse --abbrev-ref HEAD                 # expect: 202605_resolute_sheldon
git rev-parse --short 202605_resolute_sheldon
git -C /home/sheldon-qi/sonic-buildimage-resolute-reorg rev-parse --abbrev-ref HEAD
git rev-parse --short 202605_resolute_pr07 202605_resolute_pr08
```
Expected: main tree on `202605_resolute_sheldon` (tip `d6cde25d1e` or later); `pr07`/`pr08` exist.

- [ ] **Step 2: Create backup branches (rollback anchors)**

Run:
```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
git branch -f 202605_resolute_sheldon_pretrim 202605_resolute_sheldon
git branch -f 202605_resolute_pr08_pretrim   202605_resolute_pr08
git rev-parse --short 202605_resolute_sheldon_pretrim 202605_resolute_pr08_pretrim
```
Expected: two backup refs print SHAs. (Local `202605_resolute` @ `aa7fc4f76d` remains an additional backup.)

- [ ] **Step 3: Guarantee a clean index on the main tree**

Run:
```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
git reset -q                       # unstage anything pre-staged; does NOT touch working tree
git diff --cached --name-only      # MUST be empty
```
Expected: `git diff --cached --name-only` prints nothing. If it prints anything, stop and investigate — Task 2 assumes the index starts empty so only our explicit adds are committed.

- [ ] **Step 4: Confirm upstream ref + quilt are available**

Run:
```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
git rev-parse --verify sonic-net/202605 >/dev/null && echo "sonic-net/202605 OK"
command -v quilt && quilt --version
```
Expected: `sonic-net/202605 OK` and `quilt` `0.69`.

*(No commit — preflight only.)*

---

### Task 2: Target A — trim commit on `202605_resolute_sheldon`

**Files (all under `platform/broadcom/`):**
- Overwrite: `rules.mk`
- Modify: `sai-modules.mk`, `one-image.mk`
- Edit in-tree source: `sonic-platform-modules-dell/**` (apply overlay in place)
- Delete: `sonic-platform-modules-dell.patch/`, `saibcm-modules-dnx.patch/`, `saibcm-modules-legacy-th.patch/`, and 17 `sonic-platform-modules-{accton,alphanetworks,arista,cel,delta,ingrasys,inventec,juniper,micas,mitac,nexthop,nokia,quanta,ragile,ruijie,tencent,ufispace}.patch/`
- Revert to upstream: `docker-pde.mk`, `docker-saiserver-brcm.mk`, `docker-syncd-brcm-dnx.mk`, `docker-syncd-brcm-legacy-th.mk`, `docker-syncd-brcm-dnx/Dockerfile.j2`, `docker-syncd-brcm-legacy-th/Dockerfile.j2`, `docker-saiserver-brcm/Dockerfile.j2`
- Untouched (kept resolute deltas): `saibcm-modules.patch/`, `sswsyncd/debian/rules`, `docker-syncd-brcm/Dockerfile.j2`

**Interfaces:**
- Consumes: backup refs + clean index from Task 1.
- Produces: `202605_resolute_sheldon` advanced by one commit whose broadcom subtree is dell/XGS-only. Later tasks (`pr08`) check out `platform/broadcom/**` from this tip.

- [ ] **Step 1: Delete the dropped overlays (dnx, legacy-th, 17 non-dell vendors)**

Run:
```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
git rm -r --quiet \
  platform/broadcom/saibcm-modules-dnx.patch \
  platform/broadcom/saibcm-modules-legacy-th.patch \
  platform/broadcom/sonic-platform-modules-accton.patch \
  platform/broadcom/sonic-platform-modules-alphanetworks.patch \
  platform/broadcom/sonic-platform-modules-arista.patch \
  platform/broadcom/sonic-platform-modules-cel.patch \
  platform/broadcom/sonic-platform-modules-delta.patch \
  platform/broadcom/sonic-platform-modules-ingrasys.patch \
  platform/broadcom/sonic-platform-modules-inventec.patch \
  platform/broadcom/sonic-platform-modules-juniper.patch \
  platform/broadcom/sonic-platform-modules-micas.patch \
  platform/broadcom/sonic-platform-modules-mitac.patch \
  platform/broadcom/sonic-platform-modules-nexthop.patch \
  platform/broadcom/sonic-platform-modules-nokia.patch \
  platform/broadcom/sonic-platform-modules-quanta.patch \
  platform/broadcom/sonic-platform-modules-ragile.patch \
  platform/broadcom/sonic-platform-modules-ruijie.patch \
  platform/broadcom/sonic-platform-modules-tencent.patch \
  platform/broadcom/sonic-platform-modules-ufispace.patch
echo "deleted overlays: $(git diff --cached --name-only | grep -cE '\.patch/series$') series files"
```
Expected: `19` series files staged for deletion.

- [ ] **Step 2: Revert the 4 docker `.mk` + 3 Dockerfile.j2 to upstream**

Run:
```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
git checkout sonic-net/202605 -- \
  platform/broadcom/docker-pde.mk \
  platform/broadcom/docker-saiserver-brcm.mk \
  platform/broadcom/docker-syncd-brcm-dnx.mk \
  platform/broadcom/docker-syncd-brcm-legacy-th.mk \
  platform/broadcom/docker-syncd-brcm-dnx/Dockerfile.j2 \
  platform/broadcom/docker-syncd-brcm-legacy-th/Dockerfile.j2 \
  platform/broadcom/docker-saiserver-brcm/Dockerfile.j2
git diff --cached --name-only | grep -E 'docker-(pde|saiserver-brcm|syncd-brcm-dnx|syncd-brcm-legacy-th)'
```
Expected: the 4 `.mk` + 3 `Dockerfile.j2` appear as staged (reverted to upstream content).

- [ ] **Step 3: Overwrite `rules.mk` with the dell/XGS-only include list**

Write `platform/broadcom/rules.mk` with EXACTLY this content:
```makefile
include $(PLATFORM_PATH)/sai-modules.mk
include $(PLATFORM_PATH)/sai-xgs.mk
# resolute: DNX/Jericho + legacy-Tomahawk SAI dropped (no dell platform uses them)
#include $(PLATFORM_PATH)/sai-dnx.mk
#include $(PLATFORM_PATH)/sai-legacy-th.mk
include $(PLATFORM_PATH)/sswsyncd.mk
# resolute: dell is the only validated platform on Ubuntu 26.04; other vendor kmods disabled
#include $(PLATFORM_PATH)/platform-modules-nokia.mk
include $(PLATFORM_PATH)/platform-modules-dell.mk
#include $(PLATFORM_PATH)/platform-modules-arista.mk
#include $(PLATFORM_PATH)/platform-modules-nexthop.mk
#include $(PLATFORM_PATH)/platform-modules-ingrasys.mk
#include $(PLATFORM_PATH)/platform-modules-accton.mk
#include $(PLATFORM_PATH)/platform-modules-alphanetworks.mk
#include $(PLATFORM_PATH)/platform-modules-inventec.mk
#include $(PLATFORM_PATH)/platform-modules-cel.mk
#include $(PLATFORM_PATH)/platform-modules-delta.mk
#include $(PLATFORM_PATH)/platform-modules-quanta.mk
##include $(PLATFORM_PATH)/platform-modules-mitac.mk
#include $(PLATFORM_PATH)/platform-modules-juniper.mk
#include $(PLATFORM_PATH)/platform-modules-brcm-xlr-gts.mk
#include $(PLATFORM_PATH)/platform-modules-ruijie.mk
#include $(PLATFORM_PATH)/platform-modules-ragile.mk
#include $(PLATFORM_PATH)/platform-modules-supermicro.mk
#include $(PLATFORM_PATH)/platform-modules-tencent.mk
#include $(PLATFORM_PATH)/platform-modules-ufispace.mk
#include $(PLATFORM_PATH)/platform-modules-micas.mk
include $(PLATFORM_PATH)/docker-syncd-brcm.mk
# resolute: rpc/saiserver/dnx/legacy-th syncd containers dropped (test-only or non-XGS)
#include $(PLATFORM_PATH)/docker-syncd-brcm-rpc.mk
#include $(PLATFORM_PATH)/docker-saiserver-brcm.mk
#include $(PLATFORM_PATH)/docker-syncd-brcm-legacy-th.mk
#include $(PLATFORM_PATH)/docker-syncd-brcm-legacy-th-rpc.mk
ifeq ($(INCLUDE_PDE), y)
include $(PLATFORM_PATH)/docker-pde.mk
include $(PLATFORM_PATH)/sonic-pde-tests.mk
endif
include $(PLATFORM_PATH)/one-image.mk
include $(PLATFORM_PATH)/raw-image.mk
# resolute: one-aboot (Arista Aboot image) dropped — not dell; re-pulls dropped machines via DEPENDENT_MACHINE
#include $(PLATFORM_PATH)/one-aboot.mk
include $(PLATFORM_PATH)/libsaithrift-dev.mk
#include $(PLATFORM_PATH)/docker-syncd-brcm-dnx.mk
#include $(PLATFORM_PATH)/docker-syncd-brcm-dnx-rpc.mk
ifeq ($(INCLUDE_GBSYNCD), y)
include $(PLATFORM_PATH)/../components/docker-gbsyncd-credo.mk
include $(PLATFORM_PATH)/../components/docker-gbsyncd-broncos.mk
include $(PLATFORM_PATH)/../components/docker-gbsyncd-agera2.mk
include $(PLATFORM_PATH)/../components/docker-gbsyncd-milleniob.mk
endif

BCMCMD = bcmcmd
$(BCMCMD)_URL = "$(BUILD_PUBLIC_URL)/20190307/bcmcmd"

DSSERVE = dsserve
$(DSSERVE)_URL = "$(BUILD_PUBLIC_URL)/20190307/dsserve"

SONIC_ONLINE_FILES += $(BCMCMD) $(DSSERVE)

SONIC_ALL += $(SONIC_ONE_IMAGE) \
             $(DOCKER_FPM)

# Inject brcm sai into syncd
$(SYNCD)_DEPENDS += $(BRCM_XGS_SAI) $(BRCM_XGS_SAI_DEV)
$(SYNCD)_UNINSTALLS += $(BRCM_XGS_SAI_DEV) $(BRCM_XGS_SAI)

ifeq ($(ENABLE_SYNCD_RPC),y)
# Remove the libthrift_0.11.0 dependency injected by rules/syncd.mk
$(SYNCD)_DEPENDS := $(filter-out $(LIBTHRIFT_DEV),$($(SYNCD)_DEPENDS))
$(SYNCD)_DEPENDS += $(LIBSAITHRIFT_DEV)
endif
```

- [ ] **Step 4: Edit `sai-modules.mk` — XGS kmod only**

In `platform/broadcom/sai-modules.mk`, replace the entire body with EXACTLY:
```makefile
# Broadcom SAI modules
# resolute: XGS kmod only — DNX/Jericho and legacy-Tomahawk kmods dropped
# (no dell platform uses them; see rules.mk).

BRCM_OPENNSL_KERNEL_VERSION = 15.2.0.0.0.0.0.0
BRCM_OPENNSL_KERNEL = opennsl-modules_$(BRCM_OPENNSL_KERNEL_VERSION)_amd64.deb
$(BRCM_OPENNSL_KERNEL)_SRC_PATH = $(PLATFORM_PATH)/saibcm-modules
$(BRCM_OPENNSL_KERNEL)_DEPENDS += $(LINUX_HEADERS) $(LINUX_HEADERS_COMMON)
$(BRCM_OPENNSL_KERNEL)_BUILD_ENV += PKG_NAME=$(BRCM_OPENNSL_KERNEL)
$(BRCM_OPENNSL_KERNEL)_MACHINE = broadcom
SONIC_DPKG_DEBS += $(BRCM_OPENNSL_KERNEL)
```
(This deletes the former lines 11–31: the `BRCM_DNX_OPENNSL_KERNEL` and `BRCM_LEGACY_TH_OPENNSL_KERNEL` blocks.)

- [ ] **Step 5: Edit `one-image.mk` — sever DNX/legacy-TH**

Two edits in `platform/broadcom/one-image.mk`:

Edit 1 — replace this line:
```makefile
$(SONIC_ONE_IMAGE)_DEPENDENT_MACHINE = broadcom-dnx broadcom-legacy-th
```
with:
```makefile
# resolute: XGS-only image — DNX/Jericho + legacy-Tomahawk machine variants dropped
$(SONIC_ONE_IMAGE)_DEPENDENT_MACHINE =
```

Edit 2 — replace this line:
```makefile
$(SONIC_ONE_IMAGE)_LAZY_BUILD_INSTALLS = $(BRCM_OPENNSL_KERNEL) $(BRCM_DNX_OPENNSL_KERNEL)
```
with:
```makefile
$(SONIC_ONE_IMAGE)_LAZY_BUILD_INSTALLS = $(BRCM_OPENNSL_KERNEL)
```

- [ ] **Step 6: Stage the 3 edited `.mk`**

Run:
```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
git add platform/broadcom/rules.mk platform/broadcom/sai-modules.mk platform/broadcom/one-image.mk
```

- [ ] **Step 7: Apply the dell overlay into the in-tree source, then delete the overlay**

Run:
```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
( cd platform/broadcom/sonic-platform-modules-dell \
    && QUILT_PATCHES=../sonic-platform-modules-dell.patch quilt push -a \
    && rm -rf .pc )
git rm -r --quiet platform/broadcom/sonic-platform-modules-dell.patch
git add platform/broadcom/sonic-platform-modules-dell
```
Expected: quilt prints `Applying patch 0001…`, `0002…`, `0003…`, then `Now at patch …0003…`. No `.rej` files.

- [ ] **Step 8: Verify the dell source now carries the 3 API fixes (the "test")**

Run:
```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
echo "-- gpio .set int (expect 1) --"; git diff --cached -- platform/broadcom/sonic-platform-modules-dell | grep -c '^+static int fpga_gpio_set'
echo "-- bin_attribute const (expect 4) --"; git diff --cached -- platform/broadcom/sonic-platform-modules-dell | grep -c '^+.*const struct bin_attribute \*bin_attr'
echo "-- irq_find_mapping (expect 1) --"; git diff --cached -- platform/broadcom/sonic-platform-modules-dell | grep -c '^+.*irq_find_mapping('
echo "-- control retarget (expect >=1) --"; git diff --cached -- platform/broadcom/sonic-platform-modules-dell/debian/control | grep -c 'linux-sonic-headers-7.0.0-1002'
echo "-- no stray .rej/.pc --"; git status --porcelain platform/broadcom/sonic-platform-modules-dell | grep -E '\.rej|\.pc' || echo "clean"
```
Expected: `1`, `4`, `1`, `>=1`, `clean`.

- [ ] **Step 9: Safety gate — confirm ONLY broadcom paths are staged**

Run:
```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
git diff --cached --name-only | grep -v '^platform/broadcom/' && echo "!!! NON-BROADCOM STAGED — STOP" || echo "OK: only platform/broadcom staged"
git diff --cached --name-only | grep -c 'config.user' | grep -qx 0 && echo "OK: no config.user" || echo "!!! config.user staged — STOP"
```
Expected: `OK: only platform/broadcom staged` and `OK: no config.user`. If either fails, `git reset` and investigate.

- [ ] **Step 10: Commit (GPG-signed)**

Run:
```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
git commit -S -F - <<'EOF'
build(broadcom): scope resolute broadcom to dell/XGS — drop DNX/legacy-TH + non-dell vendor kmods

resolute validates only the dell platform family on Ubuntu 26.04, and all
dell platforms are XGS (TD/TH). The unified sonic-broadcom.bin otherwise
bundles DNX/Jericho and legacy-Tomahawk kmods (via one-image DEPENDENT_MACHINE
and the sai-modules.mk kmod defs) that no dell platform uses at runtime, plus
17 non-dell vendor kmod overlays that are unvalidated on 7.0 (10 already
disabled in rules.mk).

- rules.mk: dell/XGS-only include list (DNX/legacy-TH SAI, rpc/saiserver,
  aboot, and non-dell vendors commented out; SONIC_ONE_ABOOT_IMAGE dropped
  from SONIC_ALL).
- sai-modules.mk: XGS kmod only (DNX + legacy-TH kmod defs removed).
- one-image.mk: DEPENDENT_MACHINE emptied; LAZY_BUILD_INSTALLS -> XGS only.
- dell kmod Linux-7.0 fixes applied directly to the in-tree source
  (gpio .set void->int, sysfs bin_attribute const .read x4, irq_linear_revmap
  -> irq_find_mapping, debian/control kernel dep retarget); overlay removed.
- saibcm-modules stays a submodule + .patch overlay (kept).
- Dropped overlays (dnx, legacy-th, 17 vendors) removed; the 4 now-unused
  docker .mk + 3 Dockerfile.j2 reverted to upstream.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
git log -1 --format='%h %G? %s'
```
Expected: one line, `%G?` = `G` (good signature), subject as above. Record this SHA as `SHELDON_TRIM`.

---

### Task 3: Verify the trimmed sheldon build graph + kmod/deb builds

**Files:** none (verification). Runs in the main tree with the resolute slave image.

**Interfaces:**
- Consumes: `202605_resolute_sheldon` @ `SHELDON_TRIM`.
- Produces: confidence that the trim leaves a buildable XGS/dell graph (gate before touching `pr08`).

- [ ] **Step 1: Structural — no DNX/legacy-TH/non-dell targets in the dep graph**

Run:
```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
BLDENV=resolute make -f Makefile.work target/sonic-broadcom.bin SONIC_CONFIG_PRINT_DEPENDENCIES=y 2>&1 | tee /tmp/brcm_deps.txt | tail -5
echo "-- dnx/legacy-th targets (expect 0) --"; grep -cE 'opennsl-modules-(dnx|legacy-th)|broadcom-(dnx|legacy-th)|libsaibcm_(dnx|13\.2)' /tmp/brcm_deps.txt
echo "-- non-dell vendor module debs (expect 0) --"; grep -cE 'platform-modules-(accton|arista|nokia|cel|nexthop|ufispace|micas|quanta|ingrasys)' /tmp/brcm_deps.txt
```
Expected: both counts `0`. (If the print target errors before emitting deps, fall back to Step 2/3 as the gate and note it.)

- [ ] **Step 2: Build the XGS kmod deb (dell's kernel modules base)**

Run:
```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
BLDENV=resolute make -f Makefile.work target/debs/resolute/opennsl-modules_15.2.0.0.0.0.0.0_amd64.deb 2>&1 | tail -15
ls -l target/debs/resolute/opennsl-modules_15.2.0.0.0.0.0.0_amd64.deb
```
Expected: `[ finished ] … opennsl-modules_…deb` and the file exists.

- [ ] **Step 3: Build two dell platform-module debs (proves the in-tree dell source compiles on 7.0, all 3 fixes)**

Run:
```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
BLDENV=resolute make -f Makefile.work target/debs/resolute/platform-modules-z9332f_1.1_amd64.deb 2>&1 | tail -20
BLDENV=resolute make -f Makefile.work target/debs/resolute/platform-modules-z9864f_1.1_amd64.deb 2>&1 | tail -20
ls -l target/debs/resolute/platform-modules-z9332f_1.1_amd64.deb target/debs/resolute/platform-modules-z9864f_1.1_amd64.deb
```
Expected: both builds finish and both debs exist. Coverage: `z9332f` exercises the bin_attribute-const (`mc24lc64t.c`) and irq_find_mapping (`cls-i2c-mux-pca954x.c`) fixes; `z9864f` exercises the gpio `.set` void→int fix (`fpga_gpio.c`).

- [ ] **Step 4 (optional): Full image**

Run:
```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
BLDENV=resolute make -f Makefile.work target/sonic-broadcom.bin 2>&1 | tail -25
ls -l target/sonic-broadcom.bin
```
Expected: ONIE installer produced. Long-running; skip if Steps 1–3 pass and time is short.

*(No commit — verification only.)*

---

### Task 4: Target B — sync-rewrite `pr08` = `pr07` + 2 commits

**Files (in worktree `/home/sheldon-qi/sonic-buildimage-resolute-reorg`):** rebuilds branch `202605_resolute_pr08`. Broadcom files checked out from `202605_resolute_sheldon` @ `SHELDON_TRIM`.

**Interfaces:**
- Consumes: trimmed `202605_resolute_sheldon`; existing `202605_resolute_pr07`.
- Produces: `202605_resolute_pr08` whose tree == trimmed sheldon minus `rules/config.user`.

- [ ] **Step 1: Clean worktree + reset pr08 back to pr07**

Run:
```bash
cd /home/sheldon-qi/sonic-buildimage-resolute-reorg
git status --porcelain | head        # expect empty (worktree clean)
git checkout -q 202605_resolute_pr08
git rev-parse --short HEAD            # matches 202605_resolute_pr08_pretrim
git reset -q --hard 202605_resolute_pr07
git rev-parse --short HEAD 202605_resolute_pr07   # now equal
```
Expected: worktree clean; after reset, `pr08` == `pr07`. (Old tip preserved as `202605_resolute_pr08_pretrim` + reflog.)

- [ ] **Step 2: Commit 1 — core XGS wiring + kmod + sswsyncd + syncd docker**

Run:
```bash
cd /home/sheldon-qi/sonic-buildimage-resolute-reorg
git checkout 202605_resolute_sheldon -- \
  platform/broadcom/rules.mk \
  platform/broadcom/sai-modules.mk \
  platform/broadcom/one-image.mk \
  platform/broadcom/saibcm-modules.patch \
  platform/broadcom/sswsyncd \
  platform/broadcom/docker-syncd-brcm
git diff --cached --name-only | grep -v '^platform/broadcom/' && echo "!!! STOP" || echo "OK: only broadcom staged"
git commit -S -F - <<'EOF'
build(broadcom): saibcm-modules XGS Linux 7.0 kmod series + dell-only build wiring

XGS-only broadcom build wiring for Ubuntu 26.04 (Linux 7.0): rules.mk scoped
to dell/XGS, sai-modules.mk XGS kmod only, one-image.mk DEPENDENT_MACHINE
emptied. saibcm-modules (submodule) carries its Linux-7.0 kmod fixes as a
.patch/ overlay; sswsyncd debian/rules and the docker-syncd-brcm base image
retargeted to resolute.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
git log -1 --format='%h %G? %s'
```
Expected: `OK: only broadcom staged`; signed commit (`%G?`=`G`).

- [ ] **Step 3: Commit 2 — dell in-tree source (direct edit, no overlay)**

Run:
```bash
cd /home/sheldon-qi/sonic-buildimage-resolute-reorg
git checkout 202605_resolute_sheldon -- platform/broadcom/sonic-platform-modules-dell
git diff --cached --name-only | grep -v '^platform/broadcom/sonic-platform-modules-dell/' && echo "!!! STOP" || echo "OK: only dell source staged"
git commit -S -F - <<'EOF'
build(broadcom): dell platform kmods Linux 7.0 API-drift fixes (in-tree)

dell driver source edited in-tree (not a .patch overlay, per the in-tree
source convention): gpio_chip .set void->int (z9864f/fpga_gpio.c), sysfs
bin_attribute const .read x4 (mc24lc64t.c), irq_linear_revmap -> irq_find_mapping
(z9332f/cls-i2c-mux-pca954x.c), and debian/control kernel dep retarget to
linux-sonic 7.0.0-1002. See spec §9 for the kernel-version root cause.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
git log -1 --format='%h %G? %s'
```
Expected: `OK: only dell source staged`; signed commit.

- [ ] **Step 4: Verify broadcom subtrees are identical to sheldon (the "test")**

Run:
```bash
cd /home/sheldon-qi/sonic-buildimage-resolute-reorg
git diff --name-only 202605_resolute_pr08 202605_resolute_sheldon -- platform/broadcom | tee /tmp/brcm_delta.txt
echo "broadcom delta lines (expect 0): $(wc -l < /tmp/brcm_delta.txt)"
```
Expected: `0` — the broadcom subtree of `pr08` now matches trimmed sheldon exactly.

---

### Task 5: Final consistency check + report

**Files:** none. Confirms the end invariant; no push.

- [ ] **Step 1: Whole-tree invariant — pr08 vs sheldon differ only by config.user**

Run:
```bash
cd /home/sheldon-qi/sonic-buildimage-resolute-reorg
git diff --name-only 202605_resolute_pr08 202605_resolute_sheldon | tee /tmp/final_delta.txt
echo "-- non-config.user differences (expect none) --"
grep -v '^rules/config.user$' /tmp/final_delta.txt && echo "!!! UNEXPECTED DIFF — investigate" || echo "OK: only rules/config.user differs"
```
Expected: `OK: only rules/config.user differs`.

- [ ] **Step 2: Signatures + commit shape**

Run:
```bash
cd /home/sheldon-qi/sonic-buildimage-resolute-reorg
echo "-- pr08 = pr07 + 2 signed commits --"
git log --format='%h %G? %s' 202605_resolute_pr07..202605_resolute_pr08
cd /home/sheldon-qi/sonic-buildimage-resolute
echo "-- sheldon +1 signed commit --"
git log --format='%h %G? %s' 202605_resolute_sheldon_pretrim..202605_resolute_sheldon
```
Expected: pr08 shows 2 commits (both `%G?`=`G`); sheldon shows 1 commit (`%G?`=`G`).

- [ ] **Step 3: Report — do NOT push**

Summarize to the user: sheldon trim SHA, pr08 two SHAs, verification results (dep graph clean, XGS kmod + z9332f deb built, invariant holds). State explicitly that nothing was pushed and backups (`*_pretrim`, local `202605_resolute`) exist. Await review before any push.

*(No commit.)*

---

## Rollback

- Undo sheldon trim: `cd /home/sheldon-qi/sonic-buildimage-resolute && git reset --hard 202605_resolute_sheldon_pretrim`
- Undo pr08 rewrite: `cd /home/sheldon-qi/sonic-buildimage-resolute-reorg && git reset --hard 202605_resolute_pr08_pretrim`
- Deeper backup: local branch `202605_resolute` @ `aa7fc4f76d`.
- The dell overlay content is preserved in git history (backup refs) if the direct-edit approach needs reverting.

## Notes / gotchas

- **Never `git add -A`.** The main tree has dirty submodule gitlinks (frr is expected-dirty) and `rules/config.user`; only explicit `platform/broadcom/**` paths go in.
- `git checkout <ref> -- <path>` both reverts the working tree and stages it — no separate `git add` needed for Steps in Task 2.2 / Task 4.
- The quilt apply in Task 2.7 must produce zero `.rej`; if it fuzzes/rejects, the pristine dell source drifted — stop and re-decode the hunks.
- Build steps run in the main tree, which prints a non-fatal `unable to normalize alternate object path …/.git/objects` warning during docker build — ignore it (known, harmless; it only drops the image git label).
