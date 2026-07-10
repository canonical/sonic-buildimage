# SONiC 202605 Resolute — Migrate Kernel to Launchpad linux-sonic Binaries (amd64/arm64)

- **Date:** 2026-07-10
- **Scope:** `amd64` + `arm64` only. `armhf` is out of scope (see §7).
- **Build repo:** `~/sonic-buildimage-resolute` (branch `202605_resolute`) — where the build runs.
- **Doc branch:** `~/sonic-buildimage` branch `202605_resolute_doc`.
- **Source:** Launchpad PPA `~canonical-kernel-team/+archive/ubuntu/bootstrap`, resolute series, `linux-sonic 7.0.0-1002.2`.

## 1. Goal

Replace the trixie-procured kernel (`6.12.41+deb13-sonic`) in the resolute build with the Launchpad PPA prebuilt `linux-sonic 7.0.0-1002.2` binaries, covering `amd64` and `arm64`. Mechanism: the SONiC make pipeline downloads the `.deb`s via `SONIC_ONLINE_DEBS` — no source build.

## 2. Background (verified)

### 2.1 Current trixie procurement

- Version in `rules/linux-kernel.mk:3-6`: `KERNEL_VERSION=6.12.41`, `KERNEL_ABISUFFIX=+deb13`, `KERNEL_SUBVERSION=1`, `KERNEL_FEATURESET=sonic` → ABI `6.12.41+deb13-sonic-{arch}`, package version `6.12.41-1`.
- `rules/config.user:26` sets `KERNEL_PROCURE_METHOD = download`, but no code anywhere consumes that variable (only `slave.mk:353` sets the default). `src/sonic-linux-kernel/Makefile` has only a build-from-source path (`wget` DSC + `dpkg-buildpackage`). **`download` is a dead flag**; the kernel `.deb` actually comes from the dpkg cache (`/var/cache/sonic/artifacts`).
- Packaging style: Debian — `linux-image-...-unsigned` (amd64), `linux-kbuild-6.12.41+deb13`, `linux-headers-...-common-sonic` (all, MAIN_TARGET), `linux-headers-...-sonic-{arch}`. Modules are inside the image deb; no separate `linux-modules`.

### 2.2 Launchpad linux-sonic 7.0.0-1002.2

- Version `7.0.0-1002.2`, ABI `7.0.0-1002`, flavor `sonic`, series `resolute`.
- Packaging style: Ubuntu — `linux-image-7.0.0-1002-sonic` (**no `-unsigned`**), `linux-modules-7.0.0-1002-sonic` (**separate package, image depends on it**), `linux-headers-7.0.0-1002-sonic` (arch), `linux-sonic-headers-7.0.0-1002` (common, all), `linux-buildinfo`/`linux-tools`/`linux-cloud-tools` (optional). **No `linux-kbuild`.**
- amd64 and arm64 fully cover image/modules/headers/headers-common/buildinfo/tools; cloud-tools amd64 only; armhf has headers only, no image/modules.

## 3. How SONiC consumes the kernel (design basis)

| Consumer | Mechanism | File |
|---|---|---|
| Installed into image (runtime) | `build_debian.sh` cp+install `linux-image-*` deb from `$debs_path` | `build_debian.sh:151-153` |
| Out-of-tree module build (build-time) | 60+ `platform-modules-*.mk` with `_DEPENDS += $(LINUX_HEADERS) $(LINUX_HEADERS_COMMON)`, using `/lib/modules/$(KVERSION)/build` symlink | `platform/broadcom/sai-modules.mk`, `platform/mellanox/mft.mk`, `platform/nokia-vs/platform-nokia.mk:11`, … |
| Boot paths (secure boot / initrd / FIT / DSC boot) | hardcoded `vmlinuz-${LINUX_KERNEL_VERSION}-sonic-${arch}` | `build_debian.sh:773,783-784`, `files/dsc/install_debian.j2:251-252` |

**vs platform kernel-dependency verdict:**
- `PLATFORM=vs` (`platform/vs/rules.mk`) includes no `DEPENDS LINUX_HEADERS` package → pure vs has zero kernel-build dependency.
- `nokia-vs` (`platform/nokia-vs/rules.mk` → `platform-nokia.mk:11`) builds the `nokia_7215` module, depending on headers.
- All real hardware platforms (broadcom/mellanox/barefoot/centec/…) depend on headers.

**Missing `linux-kbuild` is not a gap:** Ubuntu kernels ship the build-script tree (`scripts/`, `Kbuild`) inside the `linux-headers` package (`/usr/src/linux-headers-*/scripts/`); the `/lib/modules/$(KVERSION)/build` symlink is created by the headers package postinst and points there. trixie's `linux-kbuild` is a Debian-specific extra split that Ubuntu does not need. After the switch the `LINUX_KBUILD` variable should be removed entirely.

## 4. §1 Package name mapping (trixie → Launchpad, amd64/arm64)

| Role | trixie (current) | Launchpad linux-sonic 7.0.0-1002.2 | Action |
|---|---|---|---|
| image + vmlinuz | `linux-image-6.12.41+deb13-sonic-unsigned_6.12.41-1_{arch}.deb` | `linux-image-7.0.0-1002-sonic_7.0.0-1002.2_{arch}.deb` | rename: drop `-unsigned`, change version string |
| kernel modules `/lib/modules` | *(inside image)* | `linux-modules-7.0.0-1002-sonic_7.0.0-1002.2_{arch}.deb` | **new**: image rdepends it, must co-install |
| arch headers | `linux-headers-6.12.41+deb13-sonic_6.12.41-1_{arch}.deb` | `linux-headers-7.0.0-1002-sonic_7.0.0-1002.2_{arch}.deb` | rename |
| common headers (all, MAIN_TARGET) | `linux-headers-6.12.41+deb13-common-sonic_6.12.41-1_all.deb` | `linux-sonic-headers-7.0.0-1002_7.0.0-1002.2_all.deb` | rename: common package name changed entirely |
| kbuild | `linux-kbuild-6.12.41+deb13_6.12.41-1_{arch}.deb` | none | **remove** `LINUX_KBUILD` var + DEPENDS |
| buildinfo / tools / cloud-tools | *(none)* | present | **not introduced** (SONiC does not consume) |

**Version/ABI string:** `6.12.41+deb13` (pkg `6.12.41-1`) → `7.0.0-1002` (pkg `7.0.0-1002.2`). Note the Launchpad ABI puts `-sonic-` after `-1002`, opposite order from trixie — every `vmlinuz-${LINUX_KERNEL_VERSION}-sonic-${arch}` template string must be checked for the new order.

## 5. §2 Download implementation + file change list

### 5.1 Core decision

Reuse `slave.mk`'s `SONIC_ONLINE_DEBS` download infrastructure: define the 4 kernel debs as online debs (`curl` the `+files` URL), do not go through `sonic-linux-kernel/Makefile`'s build-from-source. This brings caching (skip if `$debs_path` hit), SBOM (ONLINE_DEB fragment), `rwcache`, and `_DEPENDS` topological install — all existing machinery.

### 5.2 Verified supports

- **URL:** `https://launchpad.net/~canonical-kernel-team/+archive/ubuntu/bootstrap/+files/<deb>` → HTTP 303 → `launchpadlibrarian.net`. `slave.mk` ONLINE_DEB uses `curl -L -f` (follows 303). `ppa.launchpadcontent.net` pool path 403 (PPA disabled) — only `+files` URL works.
- **Install order:** `slave.mk:1004` `-install` target uses `$($*_DEPENDS)` as prerequisite; ONLINE_DEB applies too (`slave.mk:767`). `modules→image`, `common→headers` order is guaranteed by existing machinery.
- **common headers** is `_all.deb`, shared by amd64/arm64.

### 5.3 Files changed (8)

1. **`rules/linux-kernel.mk`** (core, rewrite)
   - Version: `KERNEL_VERSION=7.0.0`, `KERNEL_ABISUFFIX=-1002`, `KERNEL_FEATURESET=sonic`, add `KERNEL_PKGVERSION=7.0.0-1002.2`.
   - `KVERSION_SHORT = 7.0.0-1002-sonic`, `KVERSION = 7.0.0-1002-sonic-{arch}` (formula unchanged; KVERSION is used by 60+ PLATFORM_MODULE .mk to compose deb names — must be kept).
   - 4 debs renamed to Launchpad naming (§4); delete `LINUX_KBUILD` and the `add_derived_package` chain.
   - Add `_URL = $(KERNEL_PPA_URL)/<debname>` for each, `KERNEL_PPA_URL=https://launchpad.net/~canonical-kernel-team/+archive/ubuntu/bootstrap/+files`.
   - `_DEPENDS`: `$(LINUX_IMAGE)_DEPENDS += $(LINUX_MODULES)`, `$(LINUX_HEADERS)_DEPENDS += $(LINUX_HEADERS_COMMON)`.
   - `SONIC_ONLINE_DEBS += $(LINUX_HEADERS_COMMON) $(LINUX_IMAGE) $(LINUX_MODULES) $(LINUX_HEADERS)` (replaces `SONIC_MAKE_DEBS`).

2. **`rules/linux-kernel.dep`** (simplify): drop `SMDEP_FILES` (no more source build), drop `KERNEL_PROCURE_METHOD/KERNEL_CACHE_PATH/SECURE_UPGRADE` from `DEP_FLAGS`; DEP_FILES keeps only `rules/linux-kernel.mk rules/linux-kernel.dep`.

3. **`build_debian.sh`**
   - L32: `LINUX_KERNEL_VERSION=6.12.41+deb13` → `7.0.0-1002`.
   - L151-152: add `linux-modules-7.0.0-1002-sonic-*_{arch}.deb` to cp+install list (else `/lib/modules` empty, `update-initramfs`/`modprobe` fail).
   - L773/783-784: secure boot / FIT paths use `${LINUX_KERNEL_VERSION}-sonic-${arch}`, auto-follow, no separate change.

4. **`files/dsc/install_debian.j2:251-252`** (DSC boot, arm64): `vmlinuz/initrd.img-6.12.41+deb13-sonic-arm64` → `7.0.0-1002-sonic-arm64`.

5. **`platform/nokia-vs/sonic-platform-nokia/7215-c1/scripts/nokia-7215-init.sh:183`**: `KVER=6.12.41+deb13-sonic-arm64` → `7.0.0-1002-sonic-arm64`.

6. **`platform/marvell-prestera/sonic-platform-nokia/7215-a1/scripts/nokia-7215-init.sh:14-15`**: `/lib/modules/6.12.41+deb13-sonic-arm64/` → `7.0.0-1002-sonic-arm64`.

7. **`rules/config.user:25-26`**: remove/comment `KERNEL_PROCURE_METHOD = download` (no longer goes through the Makefile, flag is dead; add a comment that the kernel now comes via `SONIC_ONLINE_DEBS` from Launchpad).

8. **`src/sonic-linux-kernel/Makefile`**: unchanged (build-from-source path retained, but no longer triggered once the kernel leaves `SONIC_MAKE_DEBS`; submodule optional).

## 6. §3 Verification plan

### A. Package-level (pre-implementation, static)
- `curl -I -L` all 4 deb `+files` URLs → 200 (confirm amd64/arm64 each present).
- Download `linux-image-7.0.0-1002-sonic` deb → `dpkg-deb -I` check `Depends: linux-modules-7.0.0-1002-sonic` (confirm `_DEPENDS` direction; flip rules if reversed).
- Download `linux-headers-7.0.0-1002-sonic` deb → confirm `/usr/src/linux-headers-7.0.0-1002-sonic/scripts/` + `Kbuild` present (headers carry the kbuild tree → no `linux-kbuild` gap).

### B. Build-level (make)
- `make configure PLATFORM=vs CONFIGURED_ARCH=amd64`: info print confirms `SONIC_ONLINE_DEBS` contains the 4 kernel debs and build-from-source is no longer triggered.
- Trigger download: `make -n target/debs/resolute/linux-image-7.0.0-1002-sonic_*.deb` dry-run confirms recipe is curl; real run confirms `$debs_path` gets all 4 debs.
- dpkg install: build log confirms `linux-modules` before `linux-image`, `linux-sonic-headers` (common) before `linux-headers` (arch).
- nokia-vs module (arm64): confirm `/lib/modules/7.0.0-1002-sonic-arm64/build` produces `nokia_7215_*.ko`.

### C. Image-level (after build_debian.sh)
- `target/sonic-vs.bin` (amd64) / arm64 artifact exists.
- Mount rootfs via qcow2 part3 `image-*/fs.squashfs` (not the intermediate `*.squashfs`); check:
  - `/boot/vmlinuz-7.0.0-1002-sonic-{arch}` present;
  - `/lib/modules/7.0.0-1002-sonic-{arch}/kernel/` has modules (modules deb installed);
  - `/boot/initrd.img-7.0.0-1002-sonic-{arch}` present (`update-initramfs` succeeded);
  - `os-release` still resolute.

### D. Runtime (boot vs)
- `sonic-vs.bin` boots to login; `uname -r` = `7.0.0-1002-sonic-{arch}`; `modprobe` key modules without error; reuse the resolute vs build success smoke test.

### Verification matrix
| Layer | amd64 | arm64 |
|---|---|---|
| A package | same | same (per-arch packages) |
| B build | vs main build | nokia-vs (has out-of-tree module, best headers test) |
| C image | sonic-vs.bin | arm64 vs artifact |
| D runtime | boot + uname | boot + uname |

## 7. Scope boundary (switchable / not)

**Switchable:** amd64, arm64 `image + modules + headers(arch) + headers-common`, version string `7.0.0-1002-sonic-{arch}`.

**Not switchable (gap):**
- **armhf:** Launchpad `linux-sonic` has no armhf image/modules (headers only). armhf hardware platforms (centec/marvell-prestera, …) use `linux-image-...-sonic-armmp` — cannot switch. Explicitly out of scope.
- cloud-tools amd64 only (vs does not use it; not a gap).

## 8. To verify during implementation (non-blocking)

1. Whether `linux-image-7.0.0-1002-sonic` deb `debian/control` `Depends` is `linux-modules-7.0.0-1002-sonic` (confirms `_DEPENDS` direction).
2. Whether `linux-headers-7.0.0-1002-sonic` deb contains `scripts/` + `Kbuild` (kbuild tree).
3. nokia-vs module build (arm64 headers usability, empirical).

## 9. Next

After design approval, proceed to `writing-plans` to produce the implementation plan (stepwise, verifiable, with rollback).
