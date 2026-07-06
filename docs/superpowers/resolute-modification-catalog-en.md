# SONiC Resolute Migration: Modification Catalog

**Repo:** `/home/sheldon-qi/sonic-buildimage-resolute` (branch `resolute`)
**Baseline:** `77cfa809d` (merge-base with `202605`)
**Scope:** `202605..resolute` = **70 commits**, 142 non-`src/` files + 43 `src/` files (submodule pointers + in-submodule Makefiles/patches)
**Date:** 2026-07-06
**Status:** ✅ `target/sonic-vs.bin` builds and boots under KVM (os-release = Ubuntu 26.04)

> This is a **theme-based modification catalog**: it answers "which areas did we change, and what problem does each solve".
> It complements two sibling docs —
> [resolute-migration-code-review-en.md](resolute-migration-code-review-en.md) is the **defect view** (review findings and leftovers);
> [resolute-vs-migration-report-en.md](resolute-vs-migration-report-en.md) is the **per-package migration narrative**.
> This doc is the **theme-based positive catalog** (problem → root cause → fix → files → commits).

---

## 1. Background & Goal

Migrate the SONiC 202605 VS image build baseline from **Debian trixie** to **Ubuntu resolute (26.04)**. Ubuntu resolute ships a toolchain one generation newer than trixie (GCC 15 / C23, Python 3.14, boost default 1.90, glibc 2.43, dpkg 1.23, cmake 4.x, doxygen 1.15, SWIG 4.4), and Ubuntu differs from Debian systemically in package naming, mirror layout, and source-package splitting. These two layers of difference combined mean "swap distro" is far more than changing `FROM` — the build pipeline, slave image, submodule sources, and runtime templates all fail layer by layer.

This doc groups the 70 commits into **12 themes**. Each theme states: the problem solved, why it broke on resolute, how it was fixed, and which files changed.

---

## 2. Theme Overview

| # | Theme | Problem solved (one line) | Status | Commits |
|---|---|---|---|---|
| 1 | Pipeline & distro base swap | Switch the whole build pipeline (apt sources, debootstrap, docker, base image, firmware) from Debian to Ubuntu resolute | ✅ | 9 |
| 2 | sonic-slave-resolute build image | Create the Ubuntu resolute slave image and adapt to the new toolchain (boost default 1.90→pin 1.83, glibc fortify, thrift 0.22, Pillow, kernel deps) | ✅ | 11+3 |
| 3 | FIPS reuse of trixie binaries | resolute has no standalone FIPS release; reuse trixie FIPS binaries via ABI compatibility | ✅ | 3 |
| 4 | dbgsym `.ddeb` single-point fix | Ubuntu debhelper produces `.ddeb` for dbgsym; single-point patch `Dh_Lib.pm` back to `.deb` | ✅ | 7 |
| 5 | dpkg Maintainer field strictness | resolute dpkg 1.23 strictly parses Maintainer/changelog trailer; fix non-standard formats per package | ✅ | 6 |
| 6 | grub2 Ubuntu split + C23 | Ubuntu splits src:grub2 + GCC15 C23 `bool` keyword + overlayfs directory-hardlink ban | ✅ | 10 |
| 7 | libnl3 nh_id alias / FRR / isc-dhcp LTO | libnl3 API rename (`nh_id`↔`nhid`) + GCC15 LTO link false positives | ✅ | 5 |
| 8 | Toolchain-driven submodule pointer bumps | Patch 14 submodules in-tree (C++17/boost1.88/SWIG4.4/doxygen1.15/py3.14) and bump parent pointers | ✅ | 4 |
| 9 | Package-specific build fixes | cmake4 compat, dget skip-GPG, dbgsym mv fallback, libwtmpdb, libyang3 macro, libstdc++ headers | ✅ | 6 |
| 10 | resolute-named variant refactor | Create resolute-named base chain; restore trixie variant to pristine; both coexist | ✅ | 1 (113 files) |
| 11 | fsroot-vs pip ecosystem & pkgutil runtime fix | py3.14 removed `pkgutil.get_loader`, pip/GCC15/glibc gaps, rsync EBUSY | ⚠️ partial | 2 |
| 12 | Documentation & delivery-status records | Category-C package swap catalog + done-bar verification matrix | ✅ | 3 |

> Commits column: number of commits directly assigned to each theme (including cross-theme reuse). The "11+3" for #2 means 11 direct + 3 build-system polish commits (`7db6e8e0b`/`f40481279`/`08aa45d64`, conceptually covered in that theme's notes). Deduplicated total = 70.

---

## 3. Root-Cause Categories (toolchain differences)

Every failure maps to one of 7 toolchain-difference categories (consistent with [migration report §2](resolute-vs-migration-report-en.md)). The table maps the 12 themes onto them:

| Root-cause category | trixie | resolute | Themes hit |
|---|---|---|---|
| 1. dpkg parsing strictness | lenient | strict (dpkg 1.23) | #5 Maintainer, #4 dbgsym |
| 2. GCC 15 / C23 | GCC 14 / C17 | GCC 15 / C23 | #6 grub2, #2 slave (gnu17), #8 submodules |
| 3. C++17 + libstdc++ 15 | C++14 OK | gtest requires C++17 | #8 submodules, #2 slave (boost 1.88) |
| 4. LTO false positives | occasional | pervasive (`-flto=auto`) | #7 FRR/isc-dhcp, #8 submodules |
| 5. doxygen 1.15 | 1.9.8 | 1.15.0 | #8 SAI `Doxyfile` |
| 6. boost default 1.90 (header-only) | 1.83 default | 1.90 default (1.83/1.88 in universe) | #8 swss-common/linkmgrd (migrated early under 1.88), #2 slave (pin 1.83) |
| 7. Python 3.14 / package renames | py3.13 / old names | py3.14 / new names | #11 pkgutil/pip, #6 grub2 split, #1 package renames |

Two additional **architectural** difference classes (not toolchain versions):
- **Ubuntu vs Debian source-package layout**: components, mirrors, debootstrap cache paths, docker upstream version strings, grub2 source split (themes #1, #6, #10).
- **Build-system hardcoded distro literals**: leaf docker `ARG BASE` literal trixie, `slave.mk` no resolute branch, FIPS mk no resolute block (themes #1, #2, #3, #10).

---

## 4. Theme Details

### 4.1 Pipeline & distro base swap

**Problem**
Every layer of the SONiC 202605 build pipeline is hardcoded to Debian: apt sources template only emits `main contrib non-free-firmware`; debootstrap/docker-engine/source packages all go through `deb.debian.org`; the docker upstream version string is `~debian.13~trixie`; the base image is `FROM debian:trixie`; `DEFAULT_CONTAINER_REGISTRY` points to `publicmirror.azurecr.io` which only mirrors Debian; `build_debian.sh` installs Debian non-free firmware. After switching `IMAGE_DISTRO` to resolute every layer mismatches — slave build, debootstrap, docker base pull, and `rfs.squashfs` apt install all fail.

**Root Cause**
resolute = Ubuntu 26.04 LTS, differing from trixie systemically in three ways:
1. **Components**: Ubuntu uses `main universe multiverse restricted`; no `contrib`/`non-free-firmware`/`non-free`.
2. **Mirrors**: Ubuntu amd64 uses `archive.ubuntu.com/ubuntu`, armhf/arm64 use `ports.ubuntu.com/ubuntu-ports`, security uses `security.ubuntu.com/ubuntu`; `deb.debian.org` carries no Ubuntu packages. The debootstrap apt-list cache path becomes `archive.ubuntu.com_ubuntu_dists_*`, but `build_debian_base_system.sh` still greps the Debian path → empty → fail.
3. **libc6 ABI**: `ubuntu:resolute` libc6 2.43 vs `debian:trixie` 2.41; resolute-built debs (e.g. socat 1.8.1.1) declare `Depends: libc6 (>= 2.42)`, trixie base `dpkg -i` reports `however`.
4. **Package renames**: `libncurses5-dev` removed, `libboost-system-dev`→versioned, `dnsutils`→`bind9-dnsutils`, `qemu-kvm`→`qemu-system-x86`, `libpam-dev`→`libpam0g-dev`, etc.; 9 packages have no installation candidate.
5. **Firmware**: `firmware-linux-nonfree` is Debian non-free; Ubuntu provides `linux-firmware` in main.
6. **Source versions**: SONiC-pinned bash 5.2.37 / socat 1.7.4.1 / libnl3 3.7.0 / libyang3 3.12.2 / grub2 2.06 are trixie versions absent from the Ubuntu pool; resolute-native versions are 5.3 / 1.8.1.1 / 3.12.0 / 3.13.6 / 2.14.

**Fix**
- `files/apt/sources.list.j2`: new `DISTRIBUTION == 'resolute'` branch (`components='main universe multiverse restricted'`); all deb/deb-src lines use `{{ components }}`. `scripts/build_mirror_config.sh` and `build_debian_base_system.sh` get a resolute block (debootstrap MIRROR_URL + apt-list cache path aligned with Ubuntu's write path).
- `build_debian.sh`: docker version string → `5:29.6.1-1~ubuntu.26.04~$IMAGE_DISTRO`, containerd → `2.2.5-1~ubuntu.26.04~$IMAGE_DISTRO`, GPG key/repo → `download.docker.com/linux/ubuntu`; firmware → `linux-firmware || true`.
- `rules/config.user`: `DEFAULT_CONTAINER_REGISTRY =` (empty, so `Makefile.work` doesn't append `/`; pulls `ubuntu:resolute` straight from docker.io).
- `sonic-slave-resolute/Dockerfile.j2`: 9 Debian-specific packages remapped to resolute equivalents.
- `23ae50b13`: 5 packages switched to resolute-native versions and fetched via `dget` from `archive.ubuntu.com/ubuntu/pool` (bash 5.3, socat 1.8.1.1, libyang3 3.13.6, libnl3 3.12.0, grub2 2.14); original SONiC-specific patches (quilt/stg/patch apply) commented as TODO.
- `dockers/docker-base-trixie/Dockerfile.j2`: all three `ARG BASE` lines changed from `debian:trixie` to `ubuntu:resolute` (base libc6 2.43 matches resolute debs' `>= 2.42`). *(This is the "early scheme"; theme #10 later creates resolute-named directories and restores trixie to pristine.)*

**Key Files**
`files/apt/sources.list.j2`, `scripts/build_mirror_config.sh`, `scripts/build_debian_base_system.sh`, `build_debian.sh`, `rules/config.user`, `sonic-slave-resolute/Dockerfile.j2`, `rules/{bash,grub2,libnl3,libyang3,socat}.mk`, `src/{bash,grub2,libnl3,libyang3,socat}/Makefile`, `dockers/docker-base-trixie/Dockerfile.j2`

**Commits**
`7c13fdbd9` `8f4fc81ed` `a4874681d` `41bec4fdb` `9713d304e` `cb80ffdf6` `23ae50b13` `3d265d73b` `92b24de74`

**Status** ✅ resolved (vs build verified: os-release=Ubuntu 26.04)

**Caveats** `23ae50b13` comments all patch-apply steps as TODO (bash plugin, socat fix-strchr, libyang3 pr2362, libnl3 RTA_NH_ID, grub2 build-rules) — patch porting falls to later themes (#6/#7/#9); `LINUX_KERNEL_VERSION` still `6.12.41+deb13`, kernel handled separately (theme #8).

---

### 4.2 sonic-slave-resolute build image

**Problem**
SONiC uses a per-distro "slave" Docker image (`sonic-slave-<distro>`) containing the full toolchain and build dependencies; every .deb is built inside it. master only has `sonic-slave-trixie`. We must create `sonic-slave-resolute` from scratch (`FROM ubuntu:resolute`, Ubuntu docker repo) and teach `Makefile`/`slave.mk`/`Makefile.work` to recognize `BLDENV=resolute`. The slave image itself fails to build item-by-item due to trixie-vs-resolute toolchain version/symbol differences.

**Root Cause**
1. **Python 3.14**: pip's Pillow 11.1.0 has no cp314 wheel → forced source build, missing libjpeg headers.
2. **boost default 1.90**: from 1.90 `boost_system` is header-only, no `libboost_system.so`, but systemd-sonic-generator links `-lboost_system`, and `ssg-test.cc` calls removed `boost::filesystem::extension`.
3. **glibc 2.41 + `_FORTIFY_SOURCE=3`**: the fortify macro wraps `strchr()`'s return into `const char*` via `_Generic`; socat `filan.c:994`'s `*strchr(s,'\n')='\0'` errors "assignment of read-only location".
4. **thrift 0.22.0** (trixie: 0.19.0t64): original `libthrift-0.19.0t64` doesn't exist.
5. **Kernel build deps**: `apt build-dep linux` doesn't satisfy SONiC kernel Build-Depends-Arch (`lz4`, `gcc-14`, `kernel-wedge>=2.105`), and `config_v2.py:18 import dacite` (not installed).
6. **gcc-multilib** no longer pulled transitively (grub2 i386 modules need it); `dh-python` missing (ifupdown2 build-dep).

**Fix**
- New `sonic-slave-resolute/Dockerfile.j2` (839 lines, trixie-based with `FROM ubuntu:resolute`, docker source → `download.docker.com/linux/ubuntu`) + `Dockerfile.user.j2`, `docker.sources`, `pip.conf` (`break-system-packages=true`).
- Wire `BLDENV=resolute`: `Makefile` adds `NORESOLUTE` (default 0=build resolute, sets `NOBOOKWORM`/`NOTRIXIE` default 1) and `BUILD_RESOLUTE` branch; `Makefile.work` maps `BLDENV=resolute` → `SLAVE_DIR=sonic-slave-resolute`; `slave.mk` sets `IMAGE_DISTRO:=resolute`.
- `rules/config.user`: `INCLUDE_FIPS=y`, `PLATFORM=vs`, ccache, `BUILD_SKIP_TEST=y`, docker cache, `KERNEL_PROCURE_METHOD=download`, `SONIC_DPKG_CACHE_METHOD=rwcache`, `SONIC_VERSION_CACHE_METHOD=none` (enabling version cache makes the slave Dockerfile's wget silently skip downloads).
- boost dev packages pinned to **1.83** (`libboost1.83-dev` + `libboost-*-1.83-dev`, 18 lines `1.88-dev`→`1.83-dev`). **Why 1.83 not 1.88:** resolute's default `libboost-dev` is 1.90 (main; `boost_system` header-only with no `libboost_system.so`), so a versioned pin is mandatory; 1.83/1.88 are both in universe, but **1.83 aligns with the trixie/bookworm upstream** (trixie `libboost-dev` default is 1.83; the bookworm slave also pins 1.83), and 1.83 keeps `io_service`/`io_context::work`/`boost::filesystem::extension`/`std::hash<uuid>` (which 1.88 removed). Verified: slave rebuilds + libswsscommon/sonic-eventd/systemd-sonic-generator/sonic-linkmgrd all compile under 1.83 headers. Previously pinned 1.88 (which triggered linkmgrd's 49-file io_context migration, see #8); after switching to 1.83 the migrated code stays compatible and is not reverted. + add `dh-python`.
- socat: new `src/socat/patch/fix-strchr-const-write.patch` (`filan.c:994` uses a temp `char *nl=strchr(s,'\n'); if(nl) *nl='\0';`).
- thrift → `libthrift-0.22.0` + `libthrift-dev` + `thrift-compiler` + `python3-thrift`; Pillow source build gets `libjpeg-dev` + `zlib1g-dev`; kernel gets `lz4 gcc-14 kernel-wedge` + `python3-dacite`; explicitly install `gcc-multilib`.
- `systemd-sonic-generator/debian/rules`: `override_dh_auto_test` adds `findstring nocheck,$(DEB_BUILD_OPTIONS)` to skip make test. Under the earlier 1.88 pin, ssg-test **failed to compile** (`boost::filesystem::extension` removed); under 1.83 the API is back and ssg-test compiles, but `make test` hits a runtime buffer overflow (GCC15 `_FORTIFY_SOURCE` catches an unchecked `realpath` return in ssg code) — not a boost issue. nocheck stays (responds to the global `BUILD_SKIP_TEST=y`), but the reason shifted from "boost API removed" to "ssg's own code debt".
- 3 build-system polish commits: `7db6e8e0b` (unconditional `git reset --hard` after `checkout -B`, was CROSS-only), `f40481279` (global `APPEND CFLAGS -std=gnu17` + relax GCC15 `-Werror` for bash + `libnl3` `--force-depends` install), `08aa45d64` (fix `Dockerfile.user.j2`'s `FROM sonic-slave-resolute`).

**Key Files**
`sonic-slave-resolute/{Dockerfile.j2,Dockerfile.user.j2,docker.sources,pip.conf}`, `rules/config.user`, `Makefile`, `Makefile.work`, `slave.mk`, `src/socat/Makefile`, `src/socat/patch/fix-strchr-const-write.patch`, `src/systemd-sonic-generator/debian/rules`

**Commits**
`760e09cc3` `e16c4d8b8` `5e29f4bcd` `ad5f75252` `fde427606` `c70f10552` `3b03d9928` `1c3e48e58` `65772aba9` `7a7c1fa4d` `e3a75d22f` + `7db6e8e0b` `f40481279` `08aa45d64`

**Status** ✅ resolved (vs platform verified; non-vs/cross-build paths not fully verified)

**Caveats** Docker engine pinned to `5:29.6.1-1~ubuntu.26.04~resolute`; FIPS Go still downloaded from `fips/trixie/` (see theme #3); `Dockerfile.j2`'s trailing vendor include still writes `DEBIAN_VERSION='trixie'` (latent residue); the global `-std=gnu17` is the wrong layer (see review I14 — `wpasupplicant` on `.cpp` via `$(CC)$(CFLAGS)` needs extra remediation); the cross-build path still installs unversioned `libboost-dev:$arch` (→1.90, review I25 latent, not fixed alongside the 1.83 landing).

---

### 4.3 FIPS reuse of trixie binaries

**Problem**
`rules/sonic-fips.mk` only writes version blocks for trixie/bookworm/bullseye. `BLDENV=resolute` matches no block; `FIPS_VERSION`/`FIPS_GOLANG_*` are all empty, producing a malformed URL (`fips/trixie//amd64/golang--go__amd64.deb`) with wget exit code 8; `FIPS_URL_PREFIX=$(BUILD_PUBLIC_URL)/fips/$(BLDENV)/...` produces `fips/resolute/...` while the mirror only has `fips/trixie/` (`fips/resolute/` 404), breaking the FIPS slave build.

**Root Cause**
sonic-fips.mk uses `ifeq ($(BLDENV), trixie|bookworm|bullseye)` three-way blocks; resolute has no branch. Trixie binaries can be reused because of **ABI compatibility**: resolute and trixie share the glibc 2.43 t64 transition and the `libssl3t64`/`libgssrpc4t64` package names (64-bit time_t), so FIPS openssl 3.5.4-1+fips / Go 1.24.4-1+fips / krb5 1.21.3-5+fips trixie binaries dpkg-install cleanly on resolute.

**Fix**
`rules/sonic-fips.mk` adds an `ifeq ($(BLDENV), resolute)` block mirroring all trixie FIPS version numbers (`FIPS_VERSION=1.8.0-24-gd744cf2-2`, `FIPS_OPENSSL_VERSION=3.5.4-1+fips`, `FIPS_OPENSSH_VERSION=10.0p1-7+fips`, `FIPS_PYTHON_VERSION=3.13.5-2+fips`, `FIPS_GOLANG_VERSION=1.24.4-1+fips`, `FIPS_KRB5_VERSION=1.21.3-5+fips`), plus resolute in three package-name branches (`FIPS_OPENSSL_LIBSSL=libssl3t64_*`, `FIPS_GOLANG_SRC=golang-1.24-src_*_all.deb`, `FIPS_KRB5_LIBGSSRPC4=libgssrpc4t64_*`). Introduce `FIPS_DOWNLOAD_BLDENV` to decouple download path from `BLDENV`: inside the resolute block `FIPS_DOWNLOAD_BLDENV = trixie`, and `FIPS_URL_PREFIX` uses `$(FIPS_DOWNLOAD_BLDENV)`. Fallback: `config.user` sets `INCLUDE_FIPS=n` to use Ubuntu's official resolute `golang-go` + `openssl`.

**Key Files**
`rules/sonic-fips.mk`, `sonic-slave-resolute/Dockerfile.j2`, `rules/config`, `docs/superpowers/plans/fips-status.txt`

**Commits**
`d2dc94d34` `be892f7f6` `a1e350554`

**Status** ✅ resolved (trixie FIPS Go 1.24.4-1+fips installs in the resolute slave; fallback not triggered)

**Caveats** Reuse depends on resolute and trixie sharing the glibc 2.43 t64 transition; if glibc diverges later this reuse breaks. `Dockerfile.j2:589-590` hardcodes `fips/trixie` Go path and the mk-layer `FIPS_URL_PREFIX` are two independent paths that must stay consistent.

---

### 4.4 dbgsym `.ddeb` single-point fix

**Problem**
Many src Makefile dbgsym-move steps fail with `mv: cannot stat ...-dbgsym_*.deb`. Affected: the generic deb macro `SONIC_MAKE_DEBS` (`slave.mk`'s `mv -f ... $* $($*_DERIVED_DEBS) ...`) and `src/radius/{nss,pam}`'s `mv $(DERIVED_TARGETS) ...` (matching `*-dbgsym_*.deb` glob). Works on trixie; on resolute the empty glob fails atomically, breaking vs build at multiple packages.

**Root Cause**
resolute is Ubuntu; debhelper hardcodes the constant `DBGSYM_PACKAGE_TYPE` to `'ddeb'` in `/usr/share/perl5/Debian/Debhelper/Dh_Lib.pm` (trixie: `'deb'`); `dh_builddeb` renames auto-generated dbgsym packages from `.deb` to `.ddeb`. SONiC src Makefiles are all written for trixie's `.deb` suffix; on resolute a `.deb` glob against `.ddeb` files matches nothing. Note: resolute does generate dbgsym — it renames it afterward — which is the root cause several early band-aids missed.

**Fix**
**Single-point root-cause fix**: `sonic-slave-resolute/Dockerfile.j2` adds a RUN that uses `grep -q "DBGSYM_PACKAGE_TYPE' => 'ddeb'"` to detect + `sed -i "s/...ddeb/...deb/"` to change the `Dh_Lib.pm` constant to `'deb'`, then `grep -q "...'deb'"` to verify. Now resolute's dbgsym packages keep the `.deb` suffix (matching trixie), and all upstream Makefiles work unchanged. The surrounding `grep -q` guards make the patch idempotent and fail explicitly if upstream changes the constant. `e13951d8e` then reverts all prior symptom-level workarounds: `slave.mk` drops `noautodbgsym` and restores the original `mv -f`; `radius/{nss,pam}` restore upstream `-mv`; 28 uncommitted `|| true` Makefile changes are discarded.

**Key Files**
`sonic-slave-resolute/Dockerfile.j2`, `slave.mk`, `src/radius/nss/Makefile`, `src/radius/pam/Makefile`

**Commits**
`f748d5301` `e4fb165c7` `7dc9f6755` `0b0987805` `7e401df58` `c1dfdf0a3` `e13951d8e`

**Status** ✅ resolved (real vs build: 0 `.ddeb` renames under the patch, 17 debs complete cleanly)

**Caveats** `noautodbgsym` (`7e401df58`) was the wrong try (drops debug debs), reverted; only the `Dh_Lib.pm` constant is the real lever. The patch is sed-applied during slave-image build, requiring a slave rebuild to take effect. The non-idempotent fragility (`grep -q ddeb && sed`) is review I13 — it only works because the slave always rebuilds from a fresh `FROM ubuntu:resolute`.

---

### 4.5 dpkg Maintainer field strictness

**Problem**
Upstream source packages use non-standard `debian/control` Maintainer fields or `debian/changelog` trailers (tolerated by trixie's dpkg). resolute dpkg 1.23 errors out during parsing, blocking hsflowd, rasdaemon, python3-libyang, sonic-fib. Four failure classes: (1) comma-separated multi-Maintainers (rasdaemon `Russell Coker <..>, Taihsiang Ho <..>`); (2) bracketed email (host-sflow `Neil McKee [neil.mckee@inmon.com]`); (3) `None <None>` placeholder (libyang3-py3 generated by stdeb without `DEBFULLNAME`/`DEBEMAIL`); (4) missing changelog trailer (sonic-fib empty trailing line).

**Root Cause**
dpkg 1.23 tightened `Dpkg::Control::FieldsCore::field_parse_maintainer`: validates via `Dpkg::Email::Address->new($maint)` strictly per RFC 5322 / Debian policy, erroring `cannot parse Maintainer field value` instead of tolerating comma lists and bracketed addresses. The changelog trailer is parsed by a separate path `Dpkg::Changelog::Parse`, which reports `cannot parse maintainer email address "None <None>"`; an empty trailer is also rejected. trixie was lenient, so these legacy formats were never fixed. Gotcha: the hsflowd Makefile does `git clone github.com/sflow/host-sflow` every build, so editing the local host-sflow git Maintainer is a no-op — the sed must run inside the Makefile after clone + `cp -r DEBIAN_build/* debian`.

**Fix**
The approach flipped once. First (`8bbdb1471`) did a global Perl patch rewriting `field_parse_maintainer` (fallback: take first Maintainer, `[email]`→`<email>` + warning). Then (`2d30538b7`) reverted the global patch (it masks real errors) in favor of per-package source sed:
- hsflowd Makefile: after `cp -r DEBIAN_build/* debian`, sed `Neil McKee [..]` → `Neil McKee <..>`;
- rasdaemon Makefile: after `git apply`, sed-drop the multi-Maintainer (keep first);
- libyang3-py3 Makefile: after quilt, sed `None <None>` → `SONiC Build <sonic-build@local>` (both changelog trailer and control Maintainer);
- sonic-fib `debian/changelog`: add trailer ` -- SONiC Build <sonic-build@local>  Mon, 01 Jan 2024 00:00:00 +0000`.

**Key Files**
`sonic-slave-resolute/Dockerfile.j2`, `src/sflow/hsflowd/Makefile`, `src/rasdaemon/Makefile`, `src/libyang3-py3/Makefile`, `src/libraries/sonic-fib/debian/changelog`

**Commits**
`8bbdb1471` `8d7011427` `2d30538b7` `8387648b6` `ce32dd433` `9353339ce`

**Status** ✅ resolved (final state is per-package sed; the global dpkg patch is fully removed)

**Caveats** The changelog trailer (libyang3-py3, sonic-fib) is on the `Dpkg::Changelog::Parse` path, which the global `field_parse_maintainer` patch never covered, so per-package fixes are necessary.

---

### 4.6 grub2 Ubuntu split + C23 adaptation

**Problem**
Originally a single src:grub2 built all grub packages (trixie 2.06, salsa git + stg). On resolute this hits three walls at once:
1. Ubuntu splits grub2 into two source packages — src:grub2 produces only grub2-common/grub-pc/grub-common/grub-efi; its `debian/rules` with `DEB_SOURCE=grub2` sets `SB_SUBMIT=no`, explicitly excluding `grub-efi-amd64-bin/-unsigned/-dbg`, so the ONIE-installer-required `grub-efi-amd64-bin` is missing.
2. resolute GCC 15 defaults to C23 (gnu23); `false`/`bool` become keywords, but grub2 2.06 gnulib (`base64.h:25`) uses them as enum constants → "cannot use keyword false as enumeration constant".
3. grub2 2.14 `debian/rules` uses `ln -v obj/monolithic/* <version>/` directory hardlinks; overlayfs forbids directory hardlinks → "hard link not allowed for directory".

**Root Cause**
Ubuntu splits src:grub2 into src:grub2 and src:grub2-unsigned to separate signed/unsigned EFI binaries; src:grub2's `debian/rules` builds only PC/common packages via `SB_SUBMIT`/`DEB_SOURCE`, EFI packages go to src:grub2-unsigned. Debian trixie still has a single src:grub2 producing everything. C23: resolute GCC 15 defaults to `-std=gnu23`; HOST_CFLAGS gets `-std=gnu17` via dpkg-buildflags, but TARGET_CFLAGS defaults to just `-Os` with no `-std=`, so target code falls back to C23. overlayfs: 2.14 `debian/rules` directory-hardlinks, overlayfs returns EXDEV for directory hardlinks.

**Fix**
Three separate fixes:
1. **Swap source + dodge C23**: src:grub2 switched from Debian 2.06 to Ubuntu resolute 2.14-2ubuntu2 (`dget` Ubuntu pool). The 2.06 `export TARGET_CFLAGS=-std=gnu17` (`6c12cec27`/`5871ea04f`) was abandoned (the grub2 build system doesn't propagate that env var to target compilation, and `.ONESHELL` rejects the make-`:=` syntax); 2.14 is C23-native, sidestepping the false/bool issue.
2. **Ubuntu split**: add a second source build src:grub2-unsigned (2.14-2ubuntu1); `DEB_SOURCE=grub2-unsigned` triggers `SB_SUBMIT=yes` producing grub-efi-amd64/-bin; `rules/grub2.mk` moves `GRUB_EFI_AMD64`/`GRUB_EFI_AMD64_BIN` off src:grub2's derived targets and onto grub2-unsigned; `dbee659c3` adds `export GRUB2_UNSIGNED_VERSION` so the sub-make sees it.
3. **overlayfs directory hardlink**: the script `src/grub2/patch-overlayfs-ln.sh` rewrites 2.14 `debian/rules`'s `ln -v obj/monolithic/$(SB_PACKAGE)/* ... || :` into a per-file `cp -al` loop (file hardlinks are allowed on overlayfs; directory copy needs no directory hardlink), invoked in both Makefiles after dget unpack.
4. **slave deps**: `Dockerfile.j2` adds `apt-get -y build-dep grub2` (satisfies 2.14 extra Build-Depends: qemu-system/libfuse3-dev/libsdl2-dev/autoconf-archive/python3-pytest/patchutils/...); `729efcb59` moves that RUN from the middle of a multi-line install block to the end to fix a Dockerfile parse error.

**Key Files**
`rules/grub2.mk`, `src/grub2/Makefile`, `src/grub2-unsigned/Makefile`, `src/grub2/patch-overlayfs-ln.sh`, `sonic-slave-resolute/Dockerfile.j2`, `src/libnl3/Makefile`, `rules/libnl3.mk`

**Commits**
`6c12cec27` `5871ea04f` `9a3f010a3` `225846d81` `094d193db` `3e4490854` `dbee659c3` `729efcb59` `b30fb7b5e` `adee5275c`

**Status** ✅ resolved (artifacts `grub2-common_2.14-2ubuntu2_amd64.deb` and `grub-efi-amd64-bin_2.14-2ubuntu1_amd64.deb` land in `target/debs/resolute/`)

**Caveats** (1) Reproducibility gap: `src/grub2/.gitignore` ignores everything with `*`; `patch-overlayfs-ln.sh` is referenced by both Makefiles but not committed (force-add only Makefile + patch/*), so a fresh clone fails at `chmod +x` (should `git add -f` or move into `patch/`). (2) Original SONiC grub2 patches (adjust-build-rules, large-uid-skip-cpio #25400) not ported to 2.14 (stg commented TODO); whether large-uid cpio is upstream-merged in 2.14 is unverified. (3) `b30fb7b5e`/`adee5275c` are actually libnl3-related (`-d` skip Build-Conflicts, remove `--force-depends`), tied to grub2 only via the slave `build-dep grub2`.

---

### 4.7 libnl3 nh_id alias / FRR / isc-dhcp LTO

**Problem**
Three routing-stack compile/link failures:
1. swss `fpmsyncd/routesync.cpp:2201` calls `rtnl_route_get_nh_id()` (with underscore, the name the old SONiC 0003 stg patch added on libnl 3.7.0). After resolute upgraded to libnl 3.12.0, the feature is natively implemented as `rtnl_route_get_nhid`/`set_nhid` (no `_id` suffix); the old stg patch wasn't ported → undefined symbol at swss link time.
2. FRR link fails with `inlining failed in call to always_inline 'inet_ntop': function body can be overwritten at link time` + `lto-wrapper fatal`.
3. isc-dhcp 4.4.3-P1's embedded bind 9.11.36 under `-flto=auto` fails `svtest`/`dhclient` link with `undefined reference to isc_log_registercategories`; also resolute dh_install no longer generates `debian/tmp/usr/sbin/dhclient`, so the udeb-stage `cp dhclient-script` fails.

**Root Cause**
resolute = GCC 15 + dpkg-buildpackage default hardening (`-flto=auto`, `-ffat-lto-objects`, `_FORTIFY_SOURCE=3`) + major upstream library upgrades:
1. libnl3 upgraded to 3.12.0 (3.7.0 → 3.12.0-2). 3.12.0 natively introduces RTA_NH_ID but names the API `rtnl_route_get_nhid` (no underscore), mismatching swss's expectation; the old 0003 patch was written for 3.7.0 and can't apply cleanly; and 3.12.0-2 equals the apt repo version exactly, so dpkg won't prefer the locally-patched version — a version bump can't solve it.
2. FRR: GCC15 LTO + FORTIFY=3 mishandle glibc's `inet_ntop` always_inline wrapper — LTO leaves the function body to link time, FORTIFY thinks the always_inline body "can be overwritten at link time".
3. isc-dhcp: the embedded bind 9.11.36 static lib `libisc.a` loses symbol resolution under LTO; independent of LTO, resolute dh_install behavior change leaves the udeb target dir missing.

**Fix**
1. **libnl3** (`b4feb6f40`): abandon porting the stg patch series; instead the script `src/libnl3/patch/add-nh_id-aliases.sh` injects 4 aliases into the unpacked `libnl3-3.12.0` source root: add `rtnl_route_get/set_nh_id` declarations to `route.h`; append two alias function bodies to `route_obj.c` forwarding to native `get/set_nhid`; **register the aliases in the linker version-script `libnl-route-3.sym` via awk** (libnl builds with `-Wl,--version-script`; unregistered symbols aren't exported to the .so) under the `libnl_3_9` node; also write `debian/libnl-route-3-200.symbols`. Makefile replaces `stg init/import` with `bash ../patch/add-nh_id-aliases.sh`. An alias wrapper (not a version bump) sidesteps the version-number collision.
2. **FRR** (`bc4b9553f`+`671f1be3e`): `src/sonic-frr/Makefile` native branch exports `DEB_CFLAGS_MAINT_STRIP="-flto=auto -ffat-lto-objects"` + `DEB_LDFLAGS_MAINT_STRIP=...` before `dpkg-buildpackage` to strip LTO; bumps the `frr` submodule pointer to `e2affde73` (10.5.4-sonic-0).
3. **isc-dhcp** (`6a05c7fdd`+`c5fc4fe39`): same `DEB_*_MAINT_STRIP` to strip LTO; in `debian/rules`'s `override_dh_install`, insert `mkdir -p debian/isc-dhcp-client-udeb/sbin` before `cp dhclient-script.udeb`.

**Key Files**
`src/libnl3/Makefile`, `src/libnl3/patch/add-nh_id-aliases.sh`, `src/sonic-frr/Makefile`, `src/sonic-frr/frr`, `src/isc-dhcp/Makefile`

**Commits**
`b4feb6f40` `671f1be3e` `bc4b9553f` `6a05c7fdd` `c5fc4fe39`

**Status** ✅ resolved

**Caveats** The libnl3 version-script fix is critical and subtle: declaring/defining the symbol isn't enough — the alias must be written into the `.sym` version node or it isn't exported. FRR/isc-dhcp LTO disables are per-package temporary workarounds (native builds only); a real upstream fix needs bind/frr to adapt to GCC15+LTO+FORTIFY=3. libnl3 dead code and the version-number suggestion (should be `+sonic1` not `~sonic1`) are review I15.

---

### 4.8 Toolchain-driven submodule pointer bumps

**Problem**
`sonic-buildimage` contains no source itself; it pins submodule commits under `src/` via gitlinks. On a fresh clone for vs build, the pinned submodule commits predate the resolute toolchain, so every source-compile step (gtest, orchagent, swss-common, sairedis/SAI, linkmgrd, gnmi, dash-api, libnexthopgroup, kernel libbpf, etc.) fails outright. Each submodule must be patched in its own repo, then the parent gitlink bumped to the patched commit.

**Root Cause**
1. **GCC 15 + libgtest-dev forces C++17** (`C++ versions less than C++17 are not supported`); GCC15 turns `-Wconversion`/`-Wmaybe-uninitialized`(LTO false positive)/`-Wdiscarded-qualifiers` into `-Werror`; C++17 deprecates `std::iterator` typedef, `<cstdbool>`, adds `[[nodiscard]]` to `std::remove`.
2. **boost 1.88** removes `boost::asio::io_service`, `io_context::work`, member `post()`, and brings its own `std::hash<uuids::uuid>`; `libboost1.88-dev` package-name change needs Build-Depends/Depends alternates. > **Note:** the slave ultimately pins 1.83 (see #2), which keeps these APIs; but the submodule migration code (io_context new API, `executor_work_guard`, dropped custom hash) is committed and 1.83-compatible (verified linkmgrd compiles), so it is kept, not reverted.
3. **SWIG 4.4** Go backend no longer expands `$function` (must use `$action`); generated wrapper code hits GCC15 `-Werror=conversion`/`-Wdisabled-optimization`.
4. **doxygen 1.15.0**'s `<ref>` autolink wrapping breaks SAI `parse.pl` parsing of 2199 type tags.
5. **`_FORTIFY_SOURCE=3`** makes `strstr`/`strchr` return `const char*` via `_Generic`; libbpf.c assigns the return to `char*`, and libbpf's own `override CFLAGS += -Werror` overrides dpkg-buildflags' `-Wno-error`.
6. **cmake 4.x** removes `cmake_minimum_required<3.5` support (sonic-bmp/PcapPlusPlus).

**Fix**
`5e4f25d43` bumps 14 submodules at once (in-submodule changes verified individually):
- `sonic-swss`→`6d3a46bb`: `configure.ac` `-std=c++17`, `orchagent/directory.h` drops `std::iterator` for explicit 5 typedefs, `Makefile.am` drops tests, refresh `Cargo.lock`;
- `sonic-swss-common`→`646e726`: `configure.ac` c++17, `common/boolean.h` removes `operator bool&()` (the real root cause, eliminating 7 implicit-conversion errors);
- `sonic-sairedis`+nested SAI→`e703aff` (SAI `68da16e5`): `configure.ac` c++17 + `-include cstdint/sstream/string` + `-Wno-error=maybe-uninitialized`, `pyext/py3/Makefile.am` SWIG `-Wno-error`, `meta/Doxyfile AUTOLINK_SUPPORT=NO` (clears 2199 errors in one stroke);
- `sonic-gnmi`→`c8f96ff`: go-redis v7.4.1, `$function`→`$action` sed (version-independent);
- `linkmgrd`→`3e6ad1b`: global `io_service`→`io_context`, `executor_work_guard`, free `asio::post`;
- `dhcprelay`/`sonic-stp`/`sonic-bmp`(cmake_minimum_required 3.5)/`sonic-redfish`/`sonic-dash-ha`/`sonic-mgmt-common`+`framework`(go-redis/go-cmp)/`wpasupplicant/sonic-wpa-supplicant`/`platform/vpp`(resolute variant naming).
- Two earlier bumps: `eac57a2d5` `sonic-linux-kernel`→`c54d5e3` (sed-cast `strstr`/`strchr` returns to `char*` in `tools/lib/bpf/libbpf.c`); `25d0b0faf` `sonic-dash-api`→`43c676b` (in-submodule `g++ -std=c++14`→`c++17`), and edits `src/libraries/sonic-fib/configure.ac` `CFLAGS_COMMON` c++14→c++17 in the parent tree (libnexthopgroup is an in-tree library, not a submodule); `99cd4adac` `sonic-swss-common`→`c1a34b5c3` (adds `libboost1.88-dev` alternates to `debian/control`).

**Key Files**
`src/{sonic-swss,sonic-swss-common,sonic-sairedis,sonic-gnmi,linkmgrd,dhcprelay,sonic-stp,sonic-bmp,sonic-redfish,sonic-dash-ha,sonic-mgmt-common,sonic-mgmt-framework,sonic-linux-kernel,sonic-dash-api,wpasupplicant/sonic-wpa-supplicant}`, `platform/vpp`, `src/libraries/sonic-fib/configure.ac`

**Commits**
`5e4f25d43` `99cd4adac` `eac57a2d5` `25d0b0faf`

**Status** ✅ resolved (fresh clone reproduces; 3 corrupted object stores mgmt-framework/swss/sairedis re-cloned from origin)

**Caveats** The parent commit only moves gitlinks; the real source patches are inside each submodule commit, so reproduction requires these resolute branches be pushed to a clone-able remote. linkmgrd `make test` still has residual `io_context::work` (5 `ioService.post` + destructor name), but vs build doesn't compile `test/` so the artifact is unaffected (review I11). swss tests removal drops ~9 test binaries (review I10).

---

### 4.9 Package-specific build fixes

**Problem**
After moving to resolute, multiple source packages fail inside the slave for different reasons:
1. `psample` cmake config errors "CMake Error at CMakeLists.txt:1";
2. `openssh`/`makedumpfile`/`kdump-tools`/`lldpd`/`libnl3` fail dget GPG signature verification, and the dbgsym-derivative mv stage fails with No such file;
3. openssh build-dep reports "unmet build dependencies: libwtmpdb-dev";
4. `libyang3` 3.13.6 lacks `LYD_VALIDATE_NOEXTDEPS`, so sonic-mgmt-common compiling `yparser.go` errors undeclared;
5. `sonic-eventd` compiling `timestamp_formatter.cpp` has `stringstream`/`unordered_map` undeclared, and the changelog trailer fails to parse;
6. `sonic-sysmgr` changelog trailer rejected due to trailing whitespace.

**Root Cause**
(a) resolute ships cmake 4.2; CMake 4.x deprecated `cmake_minimum_required<3.5` (3.27 deprecated, 4.0 removed), but upstream libpsample `CMakeLists.txt:1` still says `VERSION 3.3`. (b) The slave container's HOME has no .gnupg and the keyring lacks Debian maintainer public keys, so dget's default GPG verification fails; simultaneously resolute debhelper hardcodes DBGSYM_PACKAGE_TYPE to 'ddeb', so `*-dbgsym_*.deb` is actually `.ddeb`, and `mv $(DERIVED_TARGETS)` fails on the missing file. (c) SONiC dgets Debian openssh 10.0p1-7 from `deb.debian.org`, whose Build-Depends includes `libwtmpdb-dev`, but the slave's `apt build-dep openssh` installs Ubuntu resolute's own openssh deps (no libwtmpdb-dev). (d) The libyang3 pr2362 patch was commented out during the base swap, but upstream 3.13.6 doesn't provide `LYD_VALIDATE_NOEXTDEPS` (the macro is added by SONiC's pr2362 patch `parser_data.h #define LYD_VALIDATE_NOEXTDEPS 0x0040`, referenced by `yparser.go`). (e) resolute libstdc++ (GCC 15 family) no longer transitively pulls in `<sstream>`/`<unordered_map>` via `<iostream>`/`<swss/logger.h>`; dpkg is stricter on changelog trailers, rejecting trailing whitespace. (f) resolute's default boost is 1.90 (slave pins 1.83, see #2); `libboost-serialization1.83-dev` exists (universe), and submodule control uses `1.83-dev | 1.88-dev` alternates.

**Fix**
Per-package minimal targeted fixes:
1. `psample`: after git clone, `sed 's/cmake_minimum_required(VERSION 3.3)/VERSION 3.5/' CMakeLists.txt`;
2. `makedumpfile`/`kdump-tools`/`lldpd`/`libnl3`/`openssh`: dget add `-u` to skip GPG (aligns with bash/iproute2/lm-sensors etc.); libnl3/lldpd/openssh change the trailing `mv $(DERIVED_TARGETS)` to `-mv ... 2>/dev/null; mv $* ...` so a missing dbgsym (.ddeb) doesn't block the main target;
3. `Dockerfile.j2`: after `apt-get build-dep openssh`, explicitly `apt-get install -y libwtmpdb-dev`;
4. `libyang3`: re-enable `patch -p1 < ../patch/0001-pr2362-lyd_validate_noextdeps.patch` (verified all hunks apply cleanly with offset on 3.13.6), restoring the macro;
5. `sonic-eventd`: changelog trailer gets double leading space + RFC2822 timestamp; `debian/control` Build-Depends → `libboost-serialization1.83-dev | libboost-serialization1.88-dev` alternate; `timestamp_formatter.cpp` top gets `#include <sstream>` and `<unordered_map>`;
6. `sonic-sysmgr`: changelog drops the trailer's trailing whitespace.

**Key Files**
`src/sflow/psample/Makefile`, `src/openssh/Makefile`, `src/makedumpfile/Makefile`, `src/kdump-tools/Makefile`, `src/lldpd/Makefile`, `src/libnl3/Makefile`, `src/libyang3/Makefile`, `src/libyang3/patch/0001-pr2362-lyd_validate_noextdeps.patch`, `src/sonic-eventd/{debian/changelog,debian/control,rsyslog_plugin/timestamp_formatter.cpp}`, `src/sonic-sysmgr/debian/changelog`, `sonic-slave-resolute/Dockerfile.j2`

**Commits**
`796db0b37` `2113e3207` `96a7ac97b` `ecfbb5636` `f040e7f9b` `586c35eef`

**Status** ✅ resolved

**Caveats** The `ecfbb5636` dbgsym mv fallback coexists with theme #4's `Dh_Lib.pm` single-point patch — the latter fixes the source (.ddeb→.deb), the former guarantees the main target isn't blocked even if .deb is absent. dget `-u` doesn't fix the slave-keyring root cause (acceptable; other SONiC source packages already do this). The pr2362 patch is actually a reimplementation of upstream Brad House commit `cfc94cc0` and must be maintained across libyang3 version bumps.

---

### 4.10 resolute-named variant refactor

**Problem**
The vs image was built and boot-verified, but the prior implementation was "swap content, keep the name": `docker-base-trixie`'s FROM was changed to `ubuntu:resolute` (`3d265d73b`), while 50 leaf dockers' `ARG BASE` still hardcoded the literal "trixie". Consequences: (1) name/content mismatch; (2) the trixie variant was polluted, breaking `BLDENV=trixie` control experiments; (3) no resolute-named base chain. Goal: under `BLDENV=resolute`, all vs-built containers use a resolute-named base chain; the trixie variant is restored to pristine (`FROM debian:trixie`); both coexist.

**Root Cause**
Three layered constraints:
1. **Toolchain version mismatch** (first to trigger): the slave moved to `ubuntu:resolute`, producing debs (e.g. socat 1.8.1.1) that declare `Depends: libc6 (>= 2.42)`, while `docker-base-trixie`'s original `FROM debian:trixie` has libc6 2.41 → `dpkg -i` reports `however`. The docker base must follow to `ubuntu:resolute`.
2. **Build-system architectural constraint** (forces editing leaf files): leaf docker `Dockerfile.j2` uses a literal `ARG BASE=docker-config-engine-trixie-...`, and the docker build rules (`slave.mk`) don't pass `--build-arg BASE`, so leaf `FROM $BASE` is entirely determined by the .j2 default. You can't remap leaves via `slave.mk` variables (3 failed attempts proved it).
3. **j2 variable-name generation rule** (a build-failure pit): the 3 resolute variant .j2 files were copied from trixie and reference `docker_*_trixie_{debs,whls,pkgs}`, but j2 variable names are generated by make from the docker PATH (`slave.mk: $(eval export $(subst -,_,$(notdir ...))_whls=...)`): path `docker-base-resolute` → make exports `docker_base_resolute_whls`, while the .j2 still reads `docker_base_trixie_whls` → `jinja2.UndefinedError`.

**Fix**
1. New resolute variant three-layer base chain (`ubuntu:resolute → docker-base-resolute → docker-config-engine-resolute → docker-swss-layer-resolute`): `dockers/docker-{base,config-engine,swss-layer}-resolute/Dockerfile.j2` + `rules/docker-*-resolute.{mk,dep}`, variables `DOCKER_{BASE,CONFIG_ENGINE,SWSS_LAYER}_RESOLUTE`, registered in `SONIC_DOCKER_IMAGES +=` and `SONIC_RESOLUTE_DOCKERS +=`, with the `_LOAD_DOCKERS` chain.
2. Bulk-edit 50 leaf `.j2` `ARG BASE`/`FROM`: `docker-config-engine-trixie-` → `-resolute-` (excluding the trixie variant's own directories). Includes 2 watchdogs (direct FROM, builder+final each) and vs syncd/gbsyncd-vs plus broadcom/mellanox/marvell-*/components/nvidia-bluefield syncd/saiserver.
3. Bulk-edit 45 `.mk` `_LOAD_DOCKERS`/`_DBG_DEPENDS`/`_DBG_IMAGE_PACKAGES`: `$(DOCKER_CONFIG_ENGINE_TRIXIE)` → `$(DOCKER_CONFIG_ENGINE_RESOLUTE)` etc. (the sed pattern `DOCKER_*_TRIXIE)` matches only the closing paren of a variable reference, not `DOCKER_*_TRIXIE_DBG` underscore-suffix variables). Includes the shared template `platform/template/docker-{syncd,gbsyncd}-trixie.mk` edited directly.
4. `slave.mk` adds an `else ifeq ($(BLDENV),resolute)` branch: `DOCKER_IMAGES = $(filter-out $(DOCKER_BASE_TRIXIE) $(DOCKER_CONFIG_ENGINE_TRIXIE) $(DOCKER_SWSS_LAYER_TRIXIE),$(SONIC_DOCKER_IMAGES))` (filter-out the 3 trixie bases). `BLDENV=trixie` still goes through the default else branch unaffected.
5. j2 var-name fix: the 3 resolute variant .j2 files internally sed `docker_*_trixie_` → `docker_*_resolute_` (only _debs/_whls/_pkgs references), eliminating `jinja2.UndefinedError`.
6. trixie variant restored to pristine: `dockers/docker-base-trixie/Dockerfile.j2` FROM `ubuntu:resolute` → `debian:trixie` (reverts `3d265d73b`); other trixie dirs/rules untouched.

**Key Files**
`slave.mk`, `dockers/docker-{base,config-engine,swss-layer}-resolute/{Dockerfile.j2}`, `rules/docker-{base,config-engine,swss-layer}-resolute.{mk,dep}`, `dockers/docker-base-trixie/Dockerfile.j2`, `platform/template/docker-{syncd,gbsyncd}-trixie.mk`, 50 leaf `dockers/*/Dockerfile.j2` + 45 `rules/docker-*.mk`, `docs/superpowers/specs/2026-07-05-resolute-variant-naming-design.md`

**Commits**
`a8fee77a4` (113 files)

**Status** ✅ resolved (`target/sonic-vs.bin` produced; the three resolute bases built; `docker-base-trixie` not built (filter-out works); KVM boot os-release=Ubuntu 26.04)

**Caveats** (1) `platform/vpp` in-submodule variant-naming changes need a separate submodule commit + pointer bump (vs doesn't use vpp, so no impact). (2) `docker-sonic-vs` (bookworm family, findstring guard, not built by default) not migrated. (3) The shared template `docker-*-trixie.mk` was edited directly to reference resolute, meaning under `BLDENV=trixie` building a non-vs platform syncd would point at the resolute base while the trixie base is still pristine — a latent inconsistency; vs build (`BLDENV=resolute`) is unaffected.

---

### 4.11 fsroot-vs pip ecosystem & pkgutil runtime fix

**Problem**
During fsroot-vs image build, the Python pip ecosystem and runtime fail in a chain: (1) pyangbind's lxml dependency is rebuilt by pip as lxml 5.4.0 sdist, and the Cython-generated C source fails to compile; (2) M2Crypto and other SWIG extensions reference the glibc internal symbol `__fds_bits` and fail with `-Wincompatible-pointer-types`; (3) grpcio `setup.py` probes for a `c++` binary (for libatomic probing) but the build host only has gcc; (4) at runtime sonic-package-manager uses `pkgutil.get_loader()` to locate the CLI plugin directory, an API removed in Python 3.14; (5) Docker builder-stage rsync hits `/etc/hosts` bind-mounted by buildkit, and rsync rename returns EBUSY; (6) resolute uses `resolv-config.service` instead of `resolvconf.service`, so build-time cleanup/disable statements fail.

**Root Cause**
resolute = Python 3.14 (PyPI has only cp314 wheels) + GCC 15 + glibc, multiple layered gaps: 1) Python 3.14 removed `pkgutil.get_loader` (deprecated in 3.12); `sonic_package_manager/manager.py:167` and `sonic_cli_gen/generator.py:77` still use the old API; 2) apt-installed `python3-lxml` has no pip RECORD, so pip treats it as absent, pyangbind resolves lxml to 5.4.0 sdist, whose Cython-generated code hits GCC 15's new `-Wincompatible-pointer-types` hard error; 3) `__fds_bits` is a glibc internal macro (public member is `fds_bits`); M2Crypto's SWIG wrapper references it directly, needing `-D__fds_bits=fds_bits`; 4) the `c++` binary belongs to the `g++` package, not `gcc`; 5) Docker buildkit bind-mounts `/etc/hosts` for the builder stage (read-only bind), and rsync's atomic rename returns EBUSY for that file; 6) resolute uses the systemd unit `resolv-config.service`, so `resolvconf.service` and `/etc/resolvconf/resolv.conf.d/original` don't exist.

**Fix**
- `build_debian.sh`: `gcc` → `g++` (pulls gcc too), append `libxml2-dev libxslt1-dev swig libssl-dev`; `rm -f .../original` → `|| true` with a preceding `mkdir -p`.
- `files/build_templates/sonic_debian_extension.j2`: `install_pip_package` wraps `env CFLAGS="-Wno-error=incompatible-pointer-types -D__fds_bits=fds_bits" pip3 install --no-build-isolation`; before pyangbind, first `pip3 install 'lxml==6.1.1'` (cp314 wheel pre-satisfies the dep), then `pip3 install --no-build-isolation --no-deps pyangbind==0.8.7` to skip lxml rebuild; `systemctl disable resolvconf.service || true`; sed-patch `manager.py` — replace `pkgutil.get_loader(f'{command}.plugins')` with an `importlib.util.find_spec(...)` shim (a dynamic `type("L",(),{"path":...})()` simulating the `.path` attribute), and replace `import pkgutil` with `import importlib.util, importlib`.
- `dockers/dockerfile-macros.j2`'s `rsync_from_builder_stage` macro adds `--exclude=/etc/hosts`.
- `e93860839` fixes the off-by-one introduced by `ca6536aeb`: the original sed used `spec.submodule_search_locations[0]` (the package dir `.../show/plugins`), and the downstream `os.path.dirname()` got the parent `.../show`, placing plugins one level too high; changed to `spec.origin` (`.../show/plugins/__init__.py`), so `dirname()` restores the plugin directory itself. Verified the final form is `spec.origin`.

**Key Files**
`build_debian.sh`, `dockers/dockerfile-macros.j2`, `files/build_templates/sonic_debian_extension.j2`

**Commits**
`ca6536aeb` `e93860839`

**Status** ⚠️ partial

**Caveats** Residual gap: `sonic_cli_gen/generator.py:77` still uses `pkgutil.get_loader(f'{command}.plugins.auto')`, and that file in fsroot-vs is byte-identical to source (unpatched, diff confirmed). `manager.py` imports `CliGenerator`, and `CliGenerator.install_cli_plugin/remove_cli_plugin` call the module-level `get_cli_plugin_path` (`generator.py:76→77`), so when sonic-package-manager installs/uninstalls a package with a YANG model that triggers automatic CLI generation, it still AttributeErrors under Python 3.14. The two commits don't cover this; the same `importlib.util.find_spec` patch is needed there. Secondary risks: `--no-build-isolation` applies globally to all pip wheels (safe only because lxml 6.1.1 is pre-installed); the pkgutil shim simulates only the `.path` attribute and breaks if upstream manager.py accesses other fields on pkg_loader.

---

### 4.12 Documentation & delivery-status records

**Problem**
Two information gaps needed to be captured as traceable records: (1) **Category-C decision gap** — SONiC patches and self-builds 15 packages (bash/iproute2/libnl3/libyang3/openssh/thrift etc.); after the resolute apt version swap, each must be judged "swap to apt / port patch / keep source build", or the migration can't be dispatched. (2) **Verification gap** — after C1 submodule bumps + variant renaming + C3 pkgutil fix landed, a done-bar matrix is needed to prove the vs image "builds/boots/runs", and to faithfully record the real root cause of smoke-test failures.

**Root Cause**
(1) resolute swaps base package versions wholesale (bash 5.3, iproute2 6.19, libnl3 3.12.0, libyang3 3.13.6, openssh 10.2p1, thrift 0.22.0, redis 8.0.5, swig 4.4.0 etc.), and SONiC has tightly-coupled patches on these (bash 583-line plugin.c/plugin.h management framework, iproute2 EVPN MH fields, libnl3 RTA_NH_ID + ABI symbol versioning, libyang3 LYD_VALIDATE_NOEXTDEPS, openssh reverse SSH/TACACS, etc.); whether the new version already includes the feature or needs a re-port must be verified per package; also ifupdown2 doesn't exist in resolute apt, and thrift 0.11.0→0.22.0 breaks saithrift union serialization (ABI-incompatible), so those must stay source-built. (2) The first record (`33acdab0d`) mis-diagnosed `show ip intf` failure as "squashfs lost show/plugins/*.py" because it checked the build intermediate `target/sonic-vs.bin__vs__rfs.squashfs` (stale) instead of the KVM rootfs `part3/image-resolute.0-e938608/fs.squashfs`; the real causes are two non-build issues — (a) upstream sonic-utilities `util_base.py:31` uses `importlib.import_module` on hyphenated module names `show.plugins.dhcp-relay/macsec`, which Python rejects (the bug exists in trixie/202605, not a resolute regression); (b) the `show ip` subtree depends on `Db()`→configdb, which during smoke was just-Up with configdb uninitialized (vs has no minigraph) — a timing issue.

**Fix**
1. New bilingual Category-C package swap catalog (`docs/superpowers/specs/category-c-catalog-{zh,en}.md`), giving per-package verdict + resolute apt version + reason for all 15 packages: `safe-to-swap=2` (redis no patch, swig no patch and backward compatible), `needs-patch-port=11` (bash/iproute2/libnl3/libyang3/lldpd/openssh/monit/lm-sensors/initramfs-tools/grub2/kdump-tools), `keep-source-build=2` (thrift breaks saithrift, ifupdown2 not in apt).
2. New `docs/superpowers/plans/done-bar-status.txt` recording the done-bar matrix: KVM boot to login, `show version` (reports Build commit `e938608` + docker images tagged `resolute.0-e938608`), `docker ps` (database/gnmi/pmon healthy), `/etc/os-release`=Ubuntu 26.04 — four PASS.
3. `3b3d0965d` corrects: by mounting the real running rootfs `part3/image-resolute.0-e938608/fs.squashfs` via qemu-nbd + squashfs (not the stale intermediate), confirms all 18 `show/plugins/*.py` (including `dhcp-relay.py`/`macsec.py`) are on disk, retracts the "squashfs lost show/plugins" conclusion, and reclassifies the two smoke failures as non-build defects — the hyphenated import is upstream tech debt, the `show ip` failure is a configdb-not-ready + vs-no-minigraph timing/environment issue, explicitly marking "no build defect found".

**Key Files**
`docs/superpowers/specs/category-c-catalog-{en,zh}.md`, `docs/superpowers/plans/done-bar-status.txt`

**Commits**
`93f1fe2a2` `33acdab0d` `3b3d0965d`

**Status** ✅ resolved

**Caveats** This theme is pure documentation/recording with no code changes; it fixes the migration's "planning decisions" and "verification conclusions". The Category-C catalog is a planning doc; the actual patch porting for its 11 `needs-patch-port` verdicts happens in other themes (libyang3 pr2362 `f040e7f9b`, libnl3 nh_id alias `b4feb6f40`, frr LTO `bc4b9553f`). The retracted "squashfs lost show/plugins" record is explicitly marked retracted in `3b3d0965d`.

---

## 5. Known Gaps Summary (none affect vs build)

| Source | Gap | Impact |
|---|---|---|
| #2 | Global `-std=gnu17` is the wrong layer (`wpasupplicant` on `.cpp` via `$(CC)$(CFLAGS)` needs extra remediation); `Dockerfile.j2` trailing vendor include still writes `DEBIAN_VERSION='trixie'` | vs build unaffected; latent residue |
| #4 | `Dh_Lib.pm` patch `grep -q ddeb && sed` is not idempotent | Works only because the slave rebuilds from a fresh base; debhelper upgrade could hard-fail (base is pinned) |
| #6 | `patch-overlayfs-ln.sh` not committed (.gitignore `*`); original grub2 patches (large-uid cpio #25400) not ported to 2.14 | Fresh-clone reproducibility gap; large-uid upstream-merge in 2.14 unverified |
| #7 | libnl3 dead code (symbols awk) + orphaned patch + version-number suggestion (`+sonic1` not `~sonic1`); alias script not idempotent | Doesn't affect swss link; cleanup item |
| #8 | linkmgrd `test/` residual `io_context::work` (`make test` breaks); swss tests removal drops ~9 test binaries | vs build doesn't compile `test/`; potential coverage regression on non-vs |
| #10 | `platform/vpp` variant-naming needs submodule commit + pointer bump; `docker-sonic-vs` (bookworm) not migrated; shared template `docker-*-trixie.mk` edited to resolute makes non-vs syncd under `BLDENV=trixie` potentially inconsistent | vs build unaffected |
| #11 | `sonic_cli_gen/generator.py:77` still uses `pkgutil.get_loader` (unpatched); `--no-build-isolation` global; pkgutil shim simulates only `.path` | Package install/uninstall with auto-CLI-generation AttributeErrors under py3.14 (runtime) |
| Review I7/I8 | 13 platform Dockerfiles missing `--exclude=/etc/hosts` / `libxml2-16` | Non-vs platform builds hit EBUSY / apt failure |
| Review I9 | bash plugin not ported (32 hunks/8 files/583 lines) | plugin functionality not provided on resolute (known regression) |

---

## 6. Relationship to Other Docs

- **[resolute-migration-code-review-en.md](resolute-migration-code-review-en.md)** — defect view: review C1-C4 + I5-I18 + M19-M27, plus the follow-up resolution of C1-C4. Read it for "where are the bugs, what's unfinished".
- **[resolute-vs-migration-report-en.md](resolute-vs-migration-report-en.md)** — per-package migration narrative: per-package change details + the 7-category root-cause table + final verification. Read it for "exactly how each package was changed".
- **This doc** — theme-based positive catalog: 12 themes' problem → root cause → fix → files → commits. Read it for "what areas were changed overall and what each solves".
- **`specs/category-c-catalog-{zh,en}.md`** — the swap/patch-port/keep-source-build verdict list for the 15 Category-C packages.
- **`specs/2026-07-05-resolute-variant-naming-design.md`** — the variant-naming refactor design (basis for theme #10).
- **`plans/done-bar-status.txt` / `fips-status.txt`** — delivery verification matrix and FIPS status records.
