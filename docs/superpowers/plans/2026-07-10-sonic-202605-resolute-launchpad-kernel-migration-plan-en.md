# Launchpad linux-sonic Kernel Migration — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the resolute build's trixie-procured kernel (`6.12.41+deb13-sonic`) with Launchpad PPA `linux-sonic 7.0.0-1002.2` prebuilt binaries (amd64/arm64).

**Architecture:** Reuse `slave.mk`'s `SONIC_ONLINE_DEBS` mechanism — `curl` the 4 kernel debs from Launchpad `+files` URLs into `$debs_path`, with `_DEPENDS` driving dpkg install order. Does not go through `sonic-linux-kernel/Makefile`'s build-from-source.

**Tech Stack:** GNU make (SONiC build system), dpkg/apt, bash (build_debian.sh), Launchpad HTTP API/`+files`.

## Global Constraints (apply to the whole plan)

- Version string: trixie `6.12.41+deb13` (pkg `6.12.41-1`) → Launchpad `7.0.0-1002` (pkg `7.0.0-1002.2`).
- New ABI string order: `7.0.0-1002-sonic-{arch}` (`-sonic-` after `-1002`).
- Launchpad PPA: `~canonical-kernel-team/+archive/ubuntu/bootstrap`, resolute series.
- Package names (amd64/arm64):
  - image: `linux-image-7.0.0-1002-sonic_7.0.0-1002.2_{arch}.deb` (**no `-unsigned`**)
  - modules: `linux-modules-7.0.0-1002-sonic_7.0.0-1002.2_{arch}.deb` (**new, image depends on it**)
  - headers(arch): `linux-headers-7.0.0-1002-sonic_7.0.0-1002.2_{arch}.deb`
  - headers(common): `linux-sonic-headers-7.0.0-1002_7.0.0-1002.2_all.deb`
  - **no `linux-kbuild`** (Ubuntu headers carry the build-script tree).
- Build repo: `~/sonic-buildimage-resolute` (branch `202605_resolute`).
- armhf out of scope (PPA has no armhf image/modules).

---

## File Structure (change map)

| File | Responsibility | Change |
|---|---|---|
| `rules/linux-kernel.mk` | version/ABI/package-name defs + online-deb declaration | **rewrite** |
| `rules/linux-kernel.dep` | dependency graph (drop source-build deps) | **simplify** |
| `rules/config.user` | local build knobs | edit L25-26 |
| `build_debian.sh` | install kernel into image + boot paths | edit L32, L151-154 |
| `files/dsc/install_debian.j2` | DSC boot (arm64) | edit L251-252 |
| `platform/nokia-vs/.../nokia-7215-init.sh` | nokia-vs module load | edit L183 |
| `platform/marvell-prestera/.../nokia-7215-init.sh` | hw-platform module load | edit L14-15 |
| `src/sonic-linux-kernel/Makefile` | build-from-source (kept, not triggered) | unchanged |

Task boundaries: each task is independently testable with its own commit. Task 0 is static verification (no build touched); Task 1-3 are the make-pipeline core; Task 4 is image install; Task 5 is hardcoded-version cleanup; Task 6 is end-to-end verification.

---

### Task 0: Static package-level verification (confirm design premises)

**Files:**
- Read: `https://launchpad.net/~canonical-kernel-team/+archive/ubuntu/bootstrap/+files/<deb>`
- Test: temporarily downloaded debs (deleted after)

**Interfaces:**
- Produces: confirms the 4 `+files` URLs are 200 for amd64/arm64; confirms image deb `Depends: linux-modules`; confirms headers deb contains `scripts/` + `Kbuild`. These validate Task 1's package names and `_DEPENDS` direction. If anything mismatches the design, **stop and report**; adjust before continuing.

- [ ] **Step 1: Verify the 4 `+files` URLs are downloadable (amd64 + arm64)**

```bash
cd /tmp
KERNEL_PPA_URL="https://launchpad.net/~canonical-kernel-team/+archive/ubuntu/bootstrap/+files"
for arch in amd64 arm64; do
  for pkg in linux-image-7.0.0-1002-sonic linux-modules-7.0.0-1002-sonic linux-headers-7.0.0-1002-sonic; do
    deb="${pkg}_7.0.0-1002.2_${arch}.deb"
    echo "== $deb =="
    curl -sIL "${KERNEL_PPA_URL}/${deb}" | grep -iE '^HTTP|content-length|location'
  done
done
# common headers (all)
deb="linux-sonic-headers-7.0.0-1002_7.0.0-1002.2_all.deb"
echo "== $deb =="; curl -sIL "${KERNEL_PPA_URL}/${deb}" | grep -iE '^HTTP|content-length|location'
```

Expected: each URL ends HTTP 200 with a content-length (303 redirect to launchpadlibrarian.net then 200).

- [ ] **Step 2: Confirm image deb `Depends` direction**

```bash
cd /tmp
KERNEL_PPA_URL="https://launchpad.net/~canonical-kernel-team/+archive/ubuntu/bootstrap/+files"
curl -sL "${KERNEL_PPA_URL}/linux-image-7.0.0-1002-sonic_7.0.0-1002.2_amd64.deb" -o /tmp/lp-image.deb
dpkg-deb -I /tmp/lp-image.deb | grep -iE 'Depends|linux-modules'
```

Expected: output contains `Depends: ... linux-modules-7.0.0-1002-sonic ...`. This confirms Task 1's `$(LINUX_IMAGE)_DEPENDS += $(LINUX_MODULES)` (install modules before image).

- [ ] **Step 3: Confirm headers deb contains the kbuild script tree**

```bash
cd /tmp
KERNEL_PPA_URL="https://launchpad.net/~canonical-kernel-team/+archive/ubuntu/bootstrap/+files"
curl -sL "${KERNEL_PPA_URL}/linux-headers-7.0.0-1002-sonic_7.0.0-1002.2_amd64.deb" -o /tmp/lp-headers.deb
dpkg-deb -c /tmp/lp-headers.deb | grep -E 'scripts/Makefile|/Kbuild$|/scripts/' | head -10
```

Expected: output contains `.../linux-headers-7.0.0-1002-sonic/scripts/Makefile.*` and `.../Kbuild`. Confirms headers carry the kbuild tree — no `linux-kbuild` gap.

- [ ] **Step 4: Clean up temp files**

```bash
rm -f /tmp/lp-image.deb /tmp/lp-headers.deb
```

- [ ] **Step 5: Record conclusions**

No commit (Task 0 touches no repo). Record Step 1-3 output into the implementation log / PR description. If any step mismatches (e.g. image does not Depend on modules, or headers lack Kbuild), **stop and report** — do not proceed to Task 1.

---

### Task 1: Rewrite `rules/linux-kernel.mk` as online debs

**Files:**
- Modify: `rules/linux-kernel.mk` (full rewrite, was 46 lines)

**Interfaces:**
- Consumes: `slave.mk`'s `SONIC_ONLINE_DEBS` mechanism (`+files` URL + `_DERIVED_DEBS` one-shot curl + `_DEPENDS` topological install).
- Produces: `KVERSION`, `KVERSION_SHORT`, `KERNEL_VERSION`, `KERNEL_ABISUFFIX`, `KERNEL_FEATURESET`, `KERNEL_PKGVERSION` (exported, used by 60+ PLATFORM_MODULE .mk to compose deb names); 4 deb vars `LINUX_IMAGE`/`LINUX_MODULES`/`LINUX_HEADERS`/`LINUX_HEADERS_COMMON` (used by `build_debian.sh` and out-of-tree module .mk).

- [ ] **Step 1: Back up and rewrite `rules/linux-kernel.mk`**

Replace the full content of `rules/linux-kernel.mk` with:

```makefile
# linux kernel package — Launchpad PPA prebuilt (linux-sonic 7.0.0-1002.2)
#
# Source: ~canonical-kernel-team/+archive/ubuntu/bootstrap (resolute series).
# Procured via SONIC_ONLINE_DEBS (curl +files URL), not built from source.
# Package style: Ubuntu (image depends on separate linux-modules; no linux-kbuild;
# build-script tree ships inside linux-headers).

KERNEL_VERSION = 7.0.0
KERNEL_ABISUFFIX = -1002
KERNEL_FEATURESET = sonic
KERNEL_PKGVERSION = 7.0.0-1002.2
# Note: KVERSION_SHORT is used by Arista
KVERSION_SHORT := $(KERNEL_VERSION)$(KERNEL_ABISUFFIX)-$(KERNEL_FEATURESET)
ifeq ($(CONFIGURED_ARCH), armhf)
# Override kernel version for ARMHF as it uses arm MP (multi-platform) for short version
KVERSION ?= $(KVERSION_SHORT)-armmp
else
KVERSION ?= $(KVERSION_SHORT)-$(CONFIGURED_ARCH)
endif

export KVERSION_SHORT KVERSION KERNEL_VERSION KERNEL_ABISUFFIX KERNEL_FEATURESET KERNEL_PKGVERSION

# Launchpad PPA binary pool (ppa.launchpadcontent.net direct 200; the +files URL's 303
# target launchpadlibrarian.net is unreachable from the build env — see Task 0).
KERNEL_PPA_URL = https://ppa.launchpadcontent.net/canonical-kernel-team/bootstrap/ubuntu/pool/main/l/linux-sonic

# common headers (architecture-independent, all) — MAIN_TARGET
LINUX_HEADERS_COMMON = linux-sonic-headers-$(KERNEL_VERSION)$(KERNEL_ABISUFFIX)_$(KERNEL_PKGVERSION)_all.deb
$(LINUX_HEADERS_COMMON)_URL = $(KERNEL_PPA_URL)/$(LINUX_HEADERS_COMMON)

# arch-specific image + modules + headers (derived from common)
LINUX_IMAGE   = linux-image-$(KVERSION)_$(KERNEL_PKGVERSION)_$(CONFIGURED_ARCH).deb
LINUX_MODULES = linux-modules-$(KVERSION)_$(KERNEL_PKGVERSION)_$(CONFIGURED_ARCH).deb
LINUX_HEADERS = linux-headers-$(KVERSION)_$(KERNEL_PKGVERSION)_$(CONFIGURED_ARCH).deb

$(LINUX_HEADERS_COMMON)_DERIVED_DEBS = $(LINUX_IMAGE) $(LINUX_MODULES) $(LINUX_HEADERS)
$(LINUX_IMAGE)_URL   = $(KERNEL_PPA_URL)/$(LINUX_IMAGE)
$(LINUX_MODULES)_URL = $(KERNEL_PPA_URL)/$(LINUX_MODULES)
$(LINUX_HEADERS)_URL = $(KERNEL_PPA_URL)/$(LINUX_HEADERS)

# Install order via _DEPENDS topological -install prerequisites (slave.mk:1004):
#   linux-modules  before  linux-image  (image Depends: linux-modules)
#   common headers before  arch headers (arch headers Depends: common)
$(LINUX_IMAGE)_DEPENDS += $(LINUX_MODULES)
$(LINUX_HEADERS)_DEPENDS += $(LINUX_HEADERS_COMMON)

SONIC_ONLINE_DEBS += $(LINUX_HEADERS_COMMON) $(LINUX_IMAGE) $(LINUX_MODULES) $(LINUX_HEADERS)
```

- [ ] **Step 2: Verify make parses (configure dry run)**

```bash
cd ~/sonic-buildimage-resolute
make configure PLATFORM=vs CONFIGURED_ARCH=amd64 2>&1 | grep -iE 'KERNEL_PROCURE_METHOD|SONIC_ONLINE_DEBS|linux-sonic|error|warning' | head -20
```

Expected: no error; `KERNEL_PROCURE_METHOD` line still prints (slave.mk default, harmless — Task 2 cleans config.user); build-from-source no longer triggered.

- [ ] **Step 3: Verify variable expansion**

```bash
cd ~/sonic-buildimage-resolute
make -n -f slave.mk print-KVERSION 2>/dev/null || \
  make configure PLATFORM=vs CONFIGURED_ARCH=arm64 -j1 2>&1 | grep -iE 'KVERSION|linux-image-7.0.0|linux-modules-7.0.0|linux-sonic-headers' | head
```

Expected: see `7.0.0-1002-sonic-amd64`/`-arm64`, `linux-image-7.0.0-1002-sonic_...`, `linux-modules-7.0.0-1002-sonic_...`, `linux-sonic-headers-7.0.0-1002_...`. If arm64 still shows amd64, check `CONFIGURED_ARCH` propagation.

- [ ] **Step 4: Trigger a real download (amd64 vs)**

```bash
cd ~/sonic-buildimage-resolute
make target/debs/resolute/linux-sonic-headers-7.0.0-1002_7.0.0-1002.2_all.deb -j1 2>&1 | tail -20
ls -la target/debs/resolute/ | grep -E 'linux-(image|modules|headers|sonic-headers)-7.0.0'
```

Expected: 4 debs land in `target/debs/resolute/`: `linux-sonic-headers-7.0.0-1002_*.deb`, `linux-image-7.0.0-1002-sonic_*.deb`, `linux-modules-7.0.0-1002-sonic_*.deb`, `linux-headers-7.0.0-1002-sonic_*.deb`. `_DERIVED_DEBS` makes one download pull main + derived.

- [ ] **Step 5: Commit**

```bash
cd ~/sonic-buildimage-resolute
git add rules/linux-kernel.mk
git commit -m "build: switch kernel to Launchpad linux-sonic via SONIC_ONLINE_DEBS

Rewrite rules/linux-kernel.mk: 6.12.41+deb13 (build-from-source) ->
linux-sonic 7.0.0-1002.2 from ~canonical-kernel-team/ubuntu/bootstrap
PPA via +files URL. Drop LINUX_KBUILD (Ubuntu headers carry the kbuild
script tree). Add LINUX_MODULES (image depends on it). common headers
renamed linux-headers-...-common-sonic -> linux-sonic-headers-...

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Simplify `rules/linux-kernel.dep` + clean `config.user`

**Files:**
- Modify: `rules/linux-kernel.dep`
- Modify: `rules/config.user:25-26`

**Interfaces:**
- Consumes: Task 1's new `LINUX_HEADERS_COMMON` var (dep file references it as cache key).
- Produces: dep file no longer depends on sonic-linux-kernel git content; config.user no longer sets the inert `KERNEL_PROCURE_METHOD`.

- [ ] **Step 1: Rewrite `rules/linux-kernel.dep`**

Replace the full content of `rules/linux-kernel.dep` with:

```makefile

DEP_FILES   := rules/linux-kernel.mk rules/linux-kernel.dep

# Kernel is now an ONLINE_DEB (curl +files URL), no source build ->
# no SMDEP_FILES (sonic-linux-kernel git content) and no build flags
# (KERNEL_PROCURE_METHOD/KERNEL_CACHE_PATH/SECURE_UPGRADE).
$(LINUX_HEADERS_COMMON)_DEP_FILES   := $(DEP_FILES)
$(LINUX_HEADERS_COMMON)_CACHE_OVERRIDE := $(SONIC_DPKG_CACHE_METHOD_OVERRIDE)
```

- [ ] **Step 2: Edit `rules/config.user` L25-26**

Replace lines 25-26 of `rules/config.user`:

```
# Kernel: download prebuilt instead of building from source (procure, ABI +deb13-sonic)
KERNEL_PROCURE_METHOD = download
```

with:

```
# Kernel: prebuilt linux-sonic 7.0.0-1002.2 from Launchpad PPA, fetched via
# SONIC_ONLINE_DEBS in rules/linux-kernel.mk (curl +files URL, no source build).
# KERNEL_PROCURE_METHOD is now inert (no consumer; kernel is an ONLINE_DEB).
```

- [ ] **Step 3: Verify configure still passes**

```bash
cd ~/sonic-buildimage-resolute
make configure PLATFORM=vs CONFIGURED_ARCH=amd64 2>&1 | grep -iE 'error|warning.*kernel|linux-sonic' | head
```

Expected: no error. `KERNEL_PROCURE_METHOD` may still print default `build` (slave.mk:353-354 fallback) — harmless; the kernel goes through ONLINE_DEBS and does not read this var.

- [ ] **Step 4: Commit**

```bash
cd ~/sonic-buildimage-resolute
git add rules/linux-kernel.dep rules/config.user
git commit -m "build: simplify kernel dep graph + drop inert KERNEL_PROCURE_METHOD

rules/linux-kernel.dep: remove SMDEP_FILES (no source build) and build
flags. config.user: KERNEL_PROCURE_METHOD had no consumer; comment it out
(kernel now an ONLINE_DEB from Launchpad).

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Verify out-of-tree module build (headers + kbuild tree)

**Files:**
- Test: any package `DEPENDS LINUX_HEADERS` (amd64: `rules/sonic-genl-packet-ko.mk`; arm64: nokia-vs `platform-nokia.mk`)

**Interfaces:**
- Consumes: Task 1-2 `LINUX_HEADERS`/`LINUX_HEADERS_COMMON` online debs (after slave.mk dpkg -i, `/lib/modules/$(KVERSION)/build` symlink is in place).
- Produces: empirical proof that Launchpad headers let an out-of-tree module build a `.ko` (confirms no kbuild gap).

- [ ] **Step 1: amd64 — build the `sonic-genl-packet-ko` module**

```bash
cd ~/sonic-buildimage-resolute
make target/debs/resolute/genl-packet-module_1.0-1_amd64.deb -j1 2>&1 | tail -25
```

Expected: build succeeds, producing `genl-packet-module_1.0-1_amd64.deb`. The log should show dpkg installing `linux-headers-7.0.0-1002-sonic` + `linux-sonic-headers-7.0.0-1002` first, then `make -C /lib/modules/7.0.0-1002-sonic-amd64/build M=... modules`.

- [ ] **Step 2: If it fails, check the `/lib/modules/.../build` symlink**

```bash
# Inside the build env (slave container) or after build:
ls -la /lib/modules/7.0.0-1002-sonic-amd64/build 2>/dev/null
ls /usr/src/linux-headers-7.0.0-1002-sonic/scripts/Makefile* 2>/dev/null
```

Expected: `build` symlink points at `/usr/src/linux-headers-7.0.0-1002-sonic`; `scripts/Makefile.*` exist. If the symlink is missing, check whether the headers deb was dpkg -i'd successfully (see the dpkg section of the build log).

- [ ] **Step 3: arm64 — build the nokia-vs module (if arm64 is available)**

```bash
cd ~/sonic-buildimage-resolute
make configure PLATFORM=nokia-vs CONFIGURED_ARCH=arm64 2>&1 | tail -3
make target/debs/resolute/nokia-7215-platform_*_arm64.deb -j1 2>&1 | tail -25
```

Expected: produces the nokia-7215 platform deb; the log shows `nokia_7215` building a `.ko` via `/lib/modules/7.0.0-1002-sonic-arm64/build`. If no arm64 host is available, skip this step and note it in the PR — amd64 Step 1-2 already proves headers work.

- [ ] **Step 4: Commit (if anything changed; usually nothing — this task is verification)**

No file change → no commit; record conclusions in the PR description.

---

### Task 4: `build_debian.sh` install modules + version string

**Files:**
- Modify: `build_debian.sh:32`
- Modify: `build_debian.sh:151-154`

**Interfaces:**
- Consumes: Task 1's `LINUX_KERNEL_VERSION` semantics (= `7.0.0-1002`, no `-sonic`; composes `vmlinuz-${LINUX_KERNEL_VERSION}-sonic-${arch}`).
- Produces: image rootfs with `vmlinuz` + `/lib/modules/.../kernel` installed (modules deb co-installed with image).

- [ ] **Step 1: Edit `build_debian.sh:32`**

Change line 32:
```
LINUX_KERNEL_VERSION=6.12.41+deb13
```
to:
```
LINUX_KERNEL_VERSION=7.0.0-1002
```

- [ ] **Step 2: Edit `build_debian.sh:151-154` (add modules to cp + install)**

Replace lines 151-154:
```
sudo cp $debs_path/initramfs-tools-core_*.deb $debs_path/initramfs-tools_*.deb $debs_path/linux-image-${LINUX_KERNEL_VERSION}-*_${CONFIGURED_ARCH}.deb $FILESYSTEM_ROOT
basename_deb_packages=$(basename -a $debs_path/initramfs-tools-core_*.deb $debs_path/initramfs-tools_*.deb $debs_path/linux-image-${LINUX_KERNEL_VERSION}-*_${CONFIGURED_ARCH}.deb | sed 's,^,./,')
sudo LANG=C DEBIAN_FRONTEND=noninteractive chroot $FILESYSTEM_ROOT apt -y install $basename_deb_packages
( cd $FILESYSTEM_ROOT; sudo rm -f $basename_deb_packages )
```

with:
```
sudo cp $debs_path/initramfs-tools-core_*.deb $debs_path/initramfs-tools_*.deb $debs_path/linux-image-${LINUX_KERNEL_VERSION}-*_${CONFIGURED_ARCH}.deb $debs_path/linux-modules-${LINUX_KERNEL_VERSION}-*_${CONFIGURED_ARCH}.deb $FILESYSTEM_ROOT
basename_deb_packages=$(basename -a $debs_path/initramfs-tools-core_*.deb $debs_path/initramfs-tools_*.deb $debs_path/linux-image-${LINUX_KERNEL_VERSION}-*_${CONFIGURED_ARCH}.deb $debs_path/linux-modules-${LINUX_KERNEL_VERSION}-*_${CONFIGURED_ARCH}.deb | sed 's,^,./,')
sudo LANG=C DEBIAN_FRONTEND=noninteractive chroot $FILESYSTEM_ROOT apt -y install $basename_deb_packages
( cd $FILESYSTEM_ROOT; sudo rm -f $basename_deb_packages )
```

- [ ] **Step 3: Verify boot paths auto-follow (no change, just confirm)**

```bash
cd ~/sonic-buildimage-resolute
grep -n 'LINUX_KERNEL_VERSION' build_debian.sh
```

Expected: L773/L783/L784 etc. use the `${LINUX_KERNEL_VERSION}-sonic-${CONFIGURED_ARCH}` template, auto-expanding to `7.0.0-1002-sonic-{arch}`. No separate change needed.

- [ ] **Step 4: Commit**

```bash
cd ~/sonic-buildimage-resolute
git add build_debian.sh
git commit -m "build: install linux-modules deb alongside image + bump version to 7.0.0-1002

build_debian.sh: LINUX_KERNEL_VERSION 6.12.41+deb13 -> 7.0.0-1002; add
linux-modules-* to cp+install list (Ubuntu-style image deb needs the
separate modules deb or /lib/modules is empty and update-initramfs fails).

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: Clean up hardcoded version strings (j2 + platform scripts)

**Files:**
- Modify: `files/dsc/install_debian.j2:251-252`
- Modify: `platform/nokia-vs/sonic-platform-nokia/7215-c1/scripts/nokia-7215-init.sh:183`
- Modify: `platform/marvell-prestera/sonic-platform-nokia/7215-a1/scripts/nokia-7215-init.sh:14-15`

**Interfaces:**
- Consumes: none (independent text replacement).
- Produces: all `6.12.41+deb13` strings updated to `7.0.0-1002`, boot/insmod paths consistent with the new kernel ABI.

- [ ] **Step 1: Edit `files/dsc/install_debian.j2:251-252`**

Change lines 251-252:
```
    kernel /$image_dir/boot/vmlinuz-6.12.41+deb13-sonic-arm64
    initrd /$image_dir/boot/initrd.img-6.12.41+deb13-sonic-arm64
```
to:
```
    kernel /$image_dir/boot/vmlinuz-7.0.0-1002-sonic-arm64
    initrd /$image_dir/boot/initrd.img-7.0.0-1002-sonic-arm64
```

- [ ] **Step 2: Edit `platform/nokia-vs/.../nokia-7215-init.sh:183`**

Change line 183:
```
KVER=6.12.41+deb13-sonic-arm64
```
to:
```
KVER=7.0.0-1002-sonic-arm64
```

- [ ] **Step 3: Edit `platform/marvell-prestera/.../nokia-7215-init.sh:14-15`**

Change lines 14-15:
```
    sudo insmod /lib/modules/6.12.41+deb13-sonic-arm64/kernel/extra/nokia_7215_ixs_a1_cpld.ko
    sudo insmod /lib/modules/6.12.41+deb13-sonic-arm64/kernel/extra/cn9130_cpu_thermal_sensor.ko
```
to:
```
    sudo insmod /lib/modules/7.0.0-1002-sonic-arm64/kernel/extra/nokia_7215_ixs_a1_cpld.ko
    sudo insmod /lib/modules/7.0.0-1002-sonic-arm64/kernel/extra/cn9130_cpu_thermal_sensor.ko
```

- [ ] **Step 4: Global check for residual `6.12.41+deb13` / `deb13-sonic` strings**

```bash
cd ~/sonic-buildimage-resolute
grep -rn -E '6\.12\.41\+deb13|deb13-sonic' --include='*.sh' --include='*.mk' --include='*.j2' --include='*.yml' --include='*.cfg' --include='*.user' . 2>/dev/null | grep -viE 'node_modules' | head
```

Expected: no output (or only build-from-source residue inside `src/sonic-linux-kernel`, which does not affect the ONLINE_DEB path). If `.sh`/`.j2` residue remains, fix it too.

- [ ] **Step 5: Commit**

```bash
cd ~/sonic-buildimage-resolute
git add files/dsc/install_debian.j2 platform/nokia-vs/sonic-platform-nokia/7215-c1/scripts/nokia-7215-init.sh platform/marvell-prestera/sonic-platform-nokia/7215-a1/scripts/nokia-7215-init.sh
git commit -m "build: update hardcoded kernel version strings to 7.0.0-1002-sonic

install_debian.j2 (DSC boot), nokia-vs + marvell-prestera nokia-7215-init.sh
(insmod paths): 6.12.41+deb13-sonic-arm64 -> 7.0.0-1002-sonic-arm64.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: End-to-end build + image/runtime verification

**Files:**
- Test: `target/sonic-vs.bin` (amd64), arm64 vs artifact

**Interfaces:**
- Consumes: all of Task 1-5.
- Produces: a bootable `sonic-vs.bin` with kernel `uname -r` = `7.0.0-1002-sonic-{arch}`.

- [ ] **Step 1: amd64 full vs build**

```bash
cd ~/sonic-buildimage-resolute
make configure PLATFORM=vs CONFIGURED_ARCH=amd64
make target/sonic-vs.bin -j$(nproc) 2>&1 | tee /tmp/vs-build.log | tail -30
```

Expected: produces `target/sonic-vs.bin`, no fatal error. The dpkg section of the log confirms `linux-modules` installs before `linux-image`, and `linux-sonic-headers`(common) before `linux-headers`(arch).

- [ ] **Step 2: Image-level verification (mount rootfs)**

```bash
cd ~/sonic-buildimage-resolute
# find the squashfs (use part3 image-*/fs.squashfs, NOT the intermediate *.squashfs)
FS=$(find target -path '*image-*/fs.squashfs' 2>/dev/null | head -1)
echo "squashfs: $FS"
sudo mkdir -p /mnt/vsroot && sudo mount -t squashfs -o loop "$FS" /mnt/vsroot
ls /mnt/vsroot/boot/vmlinuz-7.0.0-1002-sonic-amd64
ls /mnt/vsroot/lib/modules/7.0.0-1002-sonic-amd64/kernel/ | head
ls /mnt/vsroot/boot/initrd.img-7.0.0-1002-sonic-amd64
cat /mnt/vsroot/etc/os-release | grep -i pretty
sudo umount /mnt/vsroot
```

Expected: vmlinuz exists; `/lib/modules/.../kernel/` has modules (confirms modules deb installed); initrd exists (`update-initramfs` succeeded); `os-release` still resolute.

- [ ] **Step 3: Runtime verification (boot vs)**

```bash
cd ~/sonic-buildimage-resolute
# boot a vs instance from sonic-vs.bin (QEMU/KVM); after login:
#   uname -r            -> 7.0.0-1002-sonic-amd64
#   modprobe <a-module>  -> no error
#   show platform ...    -> reuse the resolute vs build success smoke test
```

Expected: `uname -r` = `7.0.0-1002-sonic-amd64`; key `modprobe` calls do not error; vs basic smoke passes (see memory/resolute-vs-build-success verification items).

- [ ] **Step 4: arm64 vs build (if arm64 is available)**

```bash
cd ~/sonic-buildimage-resolute
make configure PLATFORM=vs CONFIGURED_ARCH=arm64
make target/sonic-vs.bin -j$(nproc) 2>&1 | tee /tmp/vs-arm64-build.log | tail -30
```

Expected: arm64 artifact produced; same image-level verification (vmlinuz/modules/initrd/os-release). If no arm64 host, skip and note in the PR.

- [ ] **Step 5: Record verification conclusions + rollback plan**

No commit (verification task). Record Step 1-4 actual output into the PR description.

**Rollback plan (if end-to-end fails):**
```bash
cd ~/sonic-buildimage-resolute
git revert <Task1 commit> <Task2 commit> <Task4 commit> <Task5 commit>
# or wholesale: git reset --hard <pre-Task1-SHA>
# The old trixie kernel debs remain in the dpkg cache (/var/cache/sonic/artifacts);
# after rollback the build keeps working.
```

---

## Self-Review (plan self-check, executed)

1. **Spec coverage:** spec §1 package mapping → Task 1; §2 download impl + 8 files → Task 1-5; §3 four verification layers → Task 0 (package) + Task 3 (build-level headers) + Task 6 (image + runtime). armhf scope boundary → Global Constraints + §7. Full coverage.
2. **Placeholder scan:** no TBD/TODO; every step has real commands/code/expected output.
3. **Type/name consistency:** `LINUX_IMAGE`/`LINUX_MODULES`/`LINUX_HEADERS`/`LINUX_HEADERS_COMMON`, `KVERSION`, `KERNEL_PKGVERSION` defined in Task 1, referenced in Task 3-4 — names match. `KERNEL_PPA_URL`, `+files` path consistent throughout. Version strings `7.0.0-1002`/`7.0.0-1002.2` consistent throughout.

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-07-10-sonic-202605-resolute-launchpad-kernel-migration-plan-zh.md` + `-en.md`. Two execution options:

1. **Subagent-Driven (recommended)** — fresh subagent per task, review between tasks, fast iteration.
2. **Inline Execution** — execute tasks in this session using executing-plans, batch execution with checkpoints.

Which approach?
