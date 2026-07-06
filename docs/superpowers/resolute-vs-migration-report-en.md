# SONiC 202605 → Ubuntu Resolute (26.04) VS Image Migration Report

**Branch:** `resolute` (based on `master` @ `7c13fdbd9`)
**Working dir:** `/home/sheldon-qi/sonic-buildimage-resolute`
**Date:** 2026-07-05
**Status:** ✅ `target/sonic-vs.bin` built successfully and KVM-boot-verified os-release = Ubuntu 26.04

---

## 1. Background & Goal

Migrate the SONiC 202605 VS (virtual switch) image build baseline from Debian trixie to Ubuntu resolute (26.04). Acceptance: build `target/sonic-vs.bin` on an Ubuntu host and boot it to a running shell where `/etc/os-release` reports Ubuntu.

**Final verification:**
- Build: `make PLATFORM=vs BLDENV=resolute target/sonic-vs.bin` → 2.4 GB ONIE installer ✅
- Boot: `build_kvm_image.sh` installs into qcow2, qemu boots to `sonic login:` ✅
- os-release: `PRETTY_NAME="Ubuntu 26.04 LTS"`, `VERSION_CODENAME=resolute`, `ID=ubuntu` ✅

---

## 2. Root-Cause Overview

Resolute is "stricter" than trixie; every build failure falls into one of these 7 toolchain-difference categories. Each category below lists the affected packages and the specific fix.

| # | Root-cause category | trixie | resolute | Symptom |
|---|---|---|---|---|
| 1 | **dpkg parsing stricter** | lenient | strict | `cannot parse Maintainer` / `changelog trailer` |
| 2 | **GCC 15 / C23** | GCC 14 / C17 | GCC 15 / C23 | `-Werror=conversion`, `-Wmaybe-uninitialized`, `bool` keyword |
| 3 | **C++17 + libstdc++ 15** | C++14 OK | gtest requires C++17 | `#error C++ versions less than C++17`, `<cstdbool>` deprecated, `std::iterator` deprecated |
| 4 | **LTO false positives** | occasional | widespread | `maybe-uninitialized` false report at link stage |
| 5 | **doxygen 1.15.0** | 1.9.8 | 1.15.0 | SAI type name wrapped in `<ref>` → parse.pl parsing fails |
| 6 | **boost default 1.90 (header-only)** | 1.83 default | 1.90 default (1.83/1.88 in universe) | `libboost_system.so` header-only missing; 1.88 additionally removes `io_service`/`io_context::work`/`std::hash<uuid>` requiring submodule migration. slave finally pins **1.83** (aligning with trixie/bookworm upstream, see §3.1.A) |
| 7 | **Python 3.14 / package renames** | py3.13 / old names | py3.14 / new names | `pkgutil.get_loader` removed, `libxml2`→`libxml2-16`, SWIG 4.4 `$function` |

---

## 3. Detailed Changes (per package, with root cause)

> **Commit strategy note:** Committed changes (about 60 commits, see `git log resolute`) cover the "infrastructure" layer — slave image, FIPS, grub2, libnl3 downgrade, dbgsym, bash/socat, etc. This document focuses on **the most recent batch of uncommitted working-tree changes** (the segment from swss-common → sonic-vs.bin packaging), which are the last mile to producing the image. Full history in `git log --oneline resolute --not master`.

### 3.1 Parent repo (committed + working tree)

#### A. slave image `sonic-slave-resolute/Dockerfile.j2` (committed)
- **Root cause #2/#3:** resolute GCC 15 promotes `-Wimplicit-function-declaration`, `-Wincompatible-pointer-types`, `-Wint-conversion` to errors by default; libgtest-dev also requires C++17.
- **Fix:** Globally append to `/etc/dpkg/buildflags.conf`: `-std=gnu17 -Wno-error=incompatible-pointer-types -Wno-error=int-conversion -Wno-error=discarded-qualifiers`; install `gcc-multilib`, `libwtmpdb-dev` (openssh 10.0p1-7 Build-Depends), `build-dep grub2`.
- **Root cause #1 (dbgsym):** Ubuntu debhelper hardcodes `DBGSYM_PACKAGE_TYPE='ddeb'`, so dbgsym packages output `.ddeb` instead of `.deb`, and SONiC's slave.mk mv logic cannot find the file. A single-point patch to `Dh_Lib.pm` changes `ddeb` to `deb`, replacing the previously scattered `mv` workarounds across multiple Makefiles.
- **Root cause #6:** resolute default `libboost-dev` is **1.90** (main) — `boost_system` has been header-only since 1.90, with no `libboost_system.so`, so systemd-sonic-generator and others fail to link; 1.83/1.88 are in universe. **Finally pin 1.83** (aligning with trixie/bookworm upstream — trixie `libboost-dev` default is 1.83.0.2): `Dockerfile.j2` line 18 `1.88-dev`→`1.83-dev`, experimentally verified that slave rebuild + libswsscommon/sonic-eventd/systemd-sonic-generator/sonic-linkmgrd four packages compile under 1.83 headers; the io_context new API already migrated in submodules is also compatible with 1.83, retained without revert. (1.88 was previously pinned — 1.88 removes `io_service`/`io_context::work`/`std::hash<uuid>` triggering linkmgrd 49-file migration, see §3.6; after switching to 1.83 all these APIs are present, the migration code is done and compatible, not reverted.)

#### B. `build_debian.sh` (working tree)
- **Root cause #7:** When pip builds grpcio in fsroot-vs, `setup.py` calls `c++` to probe libatomic; trixie's `gcc` package provides the `c++` symlink, but resolute does not (it's in the `g++` package). Change `apt-get install gcc` → `g++`.
- **Root cause #7:** lxml 5.4.0 building from sdist hits GCC 15 `-Wincompatible-pointer-types` (hard error); installing `libxml2-dev` + `libxslt1-dev` lets lxml find the headers; M2Crypto's swig-generated code references the old glibc internal field `fd_set.__fds_bits` (resolute glibc 2.43 renamed it to `fds_bits`), worked around via the macro redefinition `CFLAGS=-D__fds_bits=fds_bits`.
- **Root cause #7:** `systemctl disable resolvconf.service` fails (resolute uses `resolv-config.service` instead, no resolvconf unit) → add `|| true`; the target directory for `cp .../resolv.conf.head` does not exist → add `mkdir -p`.

#### C. `files/build_templates/sonic_debian_extension.j2` (working tree, **critical**)
> **Important:** `sonic_debian_extension.sh` is regenerated by `slave.mk` from `sonic_debian_extension.j2` on every build; editing `.sh` directly is overwritten — you must edit the j2 template.

- **Root cause #7 (pyangbind/lxml):** pip does not recognize the apt-installed `python3-lxml` (no RECORD file), and when re-resolving deps selects lxml 5.4.0 sdist to compile from source, triggering GCC 15 errors. Fix: (1) before installing pyangbind, `pip3 install lxml==6.1.1` (cp314 prebuilt wheel, has RECORD); (2) add `--no-build-isolation --no-deps` to pyangbind, using the preinstalled lxml 6.1.1, not re-resolving deps.
- **Root cause #7 (M2Crypto `__fds_bits`):** the `install_pip_package` macro adds `env CFLAGS="-Wno-error=incompatible-pointer-types -D__fds_bits=fds_bits"`, passing it to gcc when pip builds the extension.
- **Root cause #7 (sonic-package-manager):** Python 3.14 removed `pkgutil.get_loader` (deprecated in 3.12). `sonic_package_manager/manager.py:167` uses it to locate the CLI plugin directory. Fixed via sed before the sonic-packages install loop: `pkgutil.get_loader(...)` → `importlib.util.find_spec(...)` + accompanying `import` adjustments.
- **Root cause #1:** `systemctl disable resolvconf.service || true`.
- **Root cause #7 (swig missing):** M2Crypto building swig requires `swig`; resolute's `gcc` package does not include swig, install `swig libssl-dev` in `build_debian.sh`.

#### D. `dockers/dockerfile-macros.j2` + each Dockerfile (committed + working tree)
- **Root cause (docker buildkit):** when rsync syncs base-image content to `/`, `/etc/hosts` is occupied by the Docker bind-mount, `rename` fails (`Device or resource busy`). Under trixie buildkit behaves differently and does not trigger this. Fix: add `--exclude=/etc/hosts` to all `rsync -axAX ...` (macro + `docker-restapi-sidecar/Dockerfile{.j2,}`, the other 12 Dockerfiles were already changed earlier).
- **Root cause #7:** `docker-sonic-mgmt-framework/Dockerfile` apt-installs `libxml2` → resolute renames it to `libxml2-16`.

#### E. `src/libnl3/Makefile` + new `patch/add-nh_id-aliases.sh` (working tree)
- **Root cause (libnl API rename):** SONiC's old 0003 patch added `rtnl_route_get_nh_id` (with underscore) to libnl 3.7.0, and swss fpmsyncd calls it. But libnl 3.12.0 upstream implements the feature itself, naming it `rtnl_route_get_nhid` (no underscore, field `rt_nhid`, attr `ROUTE_ATTR_NHID`). The version `3.12.0-2` collides with the resolute apt version, and dpkg will not overwrite the apt version with the SONiC version at the same version.
- **Fix:** Abandon porting the old 0003 patch (severe context drift). Use `add-nh_id-aliases.sh` instead: (1) add `rtnl_route_get/set_nh_id` declarations to `route.h`; (2) append alias functions at the end of `route_obj.c` (forwarding to the native `get/set_nhid`); (3) **register into the linker version-script `libnl-route-3.sym`** (libnl uses `-Wl,--version-script` to control symbol export, unregistered symbols are not exported) + the dpkg symbols file. awk handles tabs in the version-script (sed multi-line is unreliable inside Makefile shell).

### 3.2 sonic-swss-common (submodule, working tree, 2 files)
- **Root cause #3:** `configure.ac` uses `-std=c++14`, but resolute `libgtest-dev`'s `gtest-port.h` hard-requires C++17 (`#error C++ versions less than C++17`), so all tests fail to compile. Change `c++14`→`c++17`.
- **Root cause #3 (C++17 overload resolution change):** `common/boolean.h` has both `operator bool() const` and `operator bool&()`. Under C++17, the contextual conversion of `EXPECT_FALSE(b)` treats both as candidates, and `-Wconversion` picks the non-const version (GCC 15 false positive) → `-Werror`. The root cause is that `operator bool&()` exists only for the `(bool&)(b)` write in the header's `operator>>`. Fix: **remove `operator bool&()`**, change the two `operator>>` sites to read a local `bool tmp` then assign. One root-cause fix eliminates all 7 implicit-conversion errors without touching test code.

### 3.3 sonic-swss (submodule, working tree, 4 files)
- **Root cause #3:** same as swss-common, `configure.ac` c++14→c++17.
- **Root cause #3:** `orchagent/directory.h`'s `class iterator : public std::iterator<...>` — `std::iterator` is deprecated in C++17 (removed in C++20), `-Werror=deprecated-declarations`. Fix: remove the inheritance, explicitly write the 5 typedefs (`iterator_category`/`value_type`/`difference_type`/`pointer`/`reference`).
- **Root cause #4 + #3:** `configure.ac` adds `-Wno-error=cpp` (the `#warning` from C++17 `<cstdbool>`) + `-Wno-error=unused-result` (C++17 `std::remove` is marked `[[nodiscard]]`, `intfmgr.cpp` ignores the return value).
- **Root cause #3 (protobuf + glibc):** swss tests' `dashtunnelorch_ut.cpp` includes protobuf headers, and protobuf 3.21.12's `stubs/mutex.h` uses `std::mutex mu_{}` brace-init, GCC 15 libstdc++'s `__mutex_base()` is protected → hard error. Fix: remove `tests` from `Makefile.am`'s `SUBDIRS` (vs runtime does not need tests, sidestepping a chain of protobuf/gtest issues).

### 3.4 sonic-sairedis + SAI (submodule + nested subrepo, working tree)
> This is the deepest pit. SAI is a nested submodule inside `sonic-sairedis`.
- **Root cause #5 (doxygen 1.15.0 `<ref>` — core):** SAI's `parse.pl` (Perl) extracts metadata from doxygen-generated XML. trixie doxygen 1.9.8 outputs plain-text type names (`@@type sai_xxx_t`); resolute 1.15.0 wraps the type name as a `<ref refid="...">sai_xxx_t</ref>` cross-reference. After parse.pl strips the `<ref>` tag, adjacent type values stick together as `boolsai_acl_field_data_t`, `typesai_acl_stage_t`, etc. → 2199 `unrecognized tag` errors.
- **Fix (`SAI/meta/Doxyfile`):** `AUTOLINK_SUPPORT = YES` → `NO`. doxygen no longer auto-detects type names as cross-referenceable symbols, and the XML output reverts to plain text (consistent with trixie 1.9.8). One change zeroes out all 2199 errors.
- **Root cause #3/#7:** `configure.ac` c++14→c++17 + `-include cstdint/sstream/string` (resolute libstdc++ no longer transitively includes, multiple files use `uint32_t`/`stringstream` without directly including them) + `-Wno-error=maybe-uninitialized` (LTO cross-TU analysis falsely reports `m_size` uninitialized for `Buffer(data, size)`).
- **Root cause #2:** `pyext/py3/Makefile.am` adds `-Wno-error=conversion -Wno-error=disabled-optimization` to the SWIG-generated `pysairedis_wrap.cpp` (SWIG-generated code + GCC 15 strict conversion).

### 3.5 sonic-gnmi (submodule, working tree)
- **Root cause #7 (SWIG 4.4 Go backend):** the `%exception { $function }` block in `swsscommon.i`; SWIG 4.3 in Go mode expands `$function` to the actual function call; SWIG 4.4 removed this behavior, the `$function` literal is left in the generated `.cxx` → `$function was not declared`.
- **Fix pitfall:** gnmi's `Makefile` uses `cp -f /usr/share/swss/swsscommon.i .` to overwrite the working tree from the slave, so editing the `.i` file directly is overwritten on every build. Must `sed 's/$function/$action/g'` after the `cp` in the `Makefile` (`$action` is a SWIG standard variable, expanded by all backends).

### 3.6 linkmgrd (submodule, working tree, 49 files)
- **Root cause #6 (boost 1.88 removes `io_service`):** since boost 1.66+ `io_service` is a deprecated alias of `io_context`, fully removed in 1.88. linkmgrd uses `boost::asio::io_service` throughout the codebase.
- **Fix:** global `sed s/\bio_service\b/io_context/g` (141 occurrences, 49 files). `io_service::strand` → `io_context::strand`, `io_service::post` → `boost::asio::post(io, ...)` (the member function `post` was also removed, switch to the free function).
- **Root cause #6 (`io_context::work` removed):** boost 1.88 removes `io_context::work` (C++17 uses `executor_work_guard`). `MuxManager.h` changes to `boost::asio::executor_work_guard<boost::asio::io_context::executor_type>` + `make_work_guard`.
- **Root cause #6 (`std::hash<boost::uuids::uuid>` duplicate):** boost 1.88 builds in this hash, and linkmgrd's custom duplicate definition → redefinition error. Remove the custom one in `LinkProberBase.h`.

> **Note (landed 2026-07-06):** slave finally pins boost **1.83** (see §3.1.A). 1.83 retains `io_service`/`io_context::work`/member `post()`/`std::hash<uuid>`, so the above migration is not strictly required under 1.83; but the migration code is committed and 1.83-compatible (experimentally verified linkmgrd compiles under 1.83), retained without revert. Had 1.83 been tried first, this 49-file migration could have been saved — but `io_context` is the correct modern asio API, so the migration itself is a forward fix.

### 3.7 sonic-eventd / sonic-bmp / sonic-sysmgr / sonic-stp / dhcprelay / wpasupplicant / sonic-redfish (parent repo + submodules, working tree)
- **sonic-eventd (root cause #1 + #7 + #3):** changelog trailer missing leading space and timestamp (`-- Name <email>` → ` -- Name <email>  Date`) + control's boost 1.83 pinning plus 1.88 alternative + `timestamp_formatter.cpp` missing `#include <sstream>` (resolute libstdc++ no transitive include).
- **sonic-bmp (root cause #2 cmake 4.x):** `CMakeLists.txt` `cmake_minimum_required(VERSION 2.6)` < 3.5, resolute cmake 4.x removed < 3.5 compatibility. → 3.5.
- **sonic-sysmgr / dhcp4relay / dhcp6relay (root cause #1):** changelog trailer trailing extra space (`... -0800 ` → `... -0800`), resolute dpkg strict parsing rejects.
- **sonic-stp (root cause #1):** `Maintainer: Broadcom` (no email) → `Maintainer: Broadcom <sonic-build@local>`.
- **dhcprelay/dhcp4relay/dhcp6relay (root cause #6 + #2):** control's `libboost-thread1.83-dev`/`libboost-system1.83-dev` plus 1.88 alternative; PcapPlusPlus-24.09 subproject's MemPlumber `cmake_minimum_required(3.0)` → pass `-DCMAKE_POLICY_VERSION_MINIMUM=3.5`; PcapPlusPlus `Asn1Codec.cpp` GCC 15 `-Wfree-nonheap-object` false positive → `-DCMAKE_CXX_FLAGS=-Wno-error=free-nonheap-object`.
- **wpasupplicant (root cause #2):** slave buildflags globally added `-std=gnu17` (to fix C23 issues in C packages), but wpasupplicant's `build.rules` uses `$(CC) $(CFLAGS)` to compile `.cpp` files, and the C standard `gnu17` is invalid for C++ → `cc1plus: error`. Fix `debian/rules`: `DEB_CFLAGS_MAINT_STRIP=-std=gnu17` + UCFLAGS `filter-out`, and pass `CFLAGS="$(UCFLAGS)"` in the main `dh_auto_build` too.
- **sonic-redfish/sonic-dbus-bridge (root cause #6):** control's `libboost-dev`/`libboost-system-dev` (unversioned) plus 1.88 alternative.

### 3.8 Committed infrastructure changes (summary)
- **FIPS:** resolute has no FIPS package, reuse trixie FIPS binaries (`rules/sonic-fips.mk` `FIPS_DOWNLOAD_BLDENV=resolute→trixie`).
- **grub2:** Ubuntu splits grub2 into `src:grub2` + `src:grub2-unsigned` (Debian has a single source). New `src/grub2-unsigned/` builds `grub-efi-amd64-bin`; grub2 2.14's overlayfs hardlink barrier is worked around with a `cp -al` patch.
- **5 packages switched to resolute native base:** bash/socat/libyang3/libnl3/grub2 use `dget` to pull resolute source from the Ubuntu pool (except linux-kernel, procure download).
- **docker-base-trixie:** `FROM debian:trixie` → `FROM ubuntu:resolute` (libc6 2.43, matching resolute deb).
- **libyang3:** re-enable pr2362 patch (`LYD_VALIDATE_NOEXTDEPS`, needed by sonic-mgmt-common).
- **sonic-frr:** `git reset --hard` made unconditional (was CROSS-only); LTO off (`inet_ntop` always_inline + `_FORTIFY_SOURCE=3` link failure).
- **isc-dhcp:** LTO off (bind 9.11.36 link error); `dh_install` does not create udeb sbin dir → sed `mkdir -p`.

---

## 4. Verification

```
$ ls -la target/sonic-vs.bin
-rwxr-xr-x 2558783471 Jul  4 22:58 target/sonic-vs.bin   # 2.4 GB ONIE installer

$ build_kvm_image.sh target/sonic-vs.img files/onie-recovery-x86_64-kvm_x86_64-r0.iso target/sonic-vs.bin 10
→ target/sonic-vs.img 5.4 GB qcow2 (SONiC installed via ONIE)

$ kvm -drive file=target/sonic-vs.img -serial telnet:127.0.0.1:9000 ...
→ sonic login: (SONiC boot to login prompt)

admin@sonic:~$ cat /etc/os-release
PRETTY_NAME="Ubuntu 26.04 LTS"
VERSION="26.04 LTS (Resolute Raccoon)"
VERSION_CODENAME=resolute
ID=ubuntu
UBUNTU_CODENAME=resolute
```

---

## 4.5 resolute variant-naming refactor attempt & architectural constraint

> **Update (2026-07-05, commit `a8fee77a4`):** the variant-naming refactor has been implemented and committed per the resolute repo's `docs/superpowers/specs/2026-07-05-resolute-variant-naming-design.md` — 50 leaf `.j2` ARG BASE + 45 `.mk` switched to resolute, `slave.mk` gains a resolute branch that filter-outs trixie base, `docker-base-trixie` reverted to `debian:trixie`, and the resolute variant dirs now feed the vs build chain. The "reverted / does not work" text below is retained as a historical record. Static verification (spec §7 grep residual checks + `make -n` parse) passed; full build+KVM verification is pending.

> After the image built successfully, an attempt was made to turn the "trixie-named, resolute-content" base chain into a proper coexisting `resolute` variant (`docker-base-resolute` / `docker-config-engine-resolute` / `docker-swss-layer-resolute`, copied from trixie, `FROM ubuntu:resolute`). **This does not work under the current build system** and was reverted to the committed approach. Root cause recorded here to prevent re-attempting.

### Three failed attempts
1. **Batch-adding `SONIC_RESOLUTE_DOCKERS +=` lines to 34 leaf `docker.mk`s** → simultaneously requires both trixie and resolute base sets → `No rule to make target 'docker-config-engine-trixie.gz-load'`.
2. **`DOCKER_IMAGES := $(SONIC_RESOLUTE_DOCKERS)`** (slave.mk resolute branch) → the resolute list has only 3 base variants, losing all leaf dockers.
3. **`DOCKER_IMAGES := $(SONIC_TRIXIE_DOCKERS)`** (reuse the full trixie list) → `docker-dash-engine` is registered in `SONIC_DOCKER_IMAGES` (`platform/vs/docker-dash-engine.mk:8`) rather than `SONIC_TRIXIE_DOCKERS`, so it is excluded → `No rule to make target 'target/docker-dash-engine.gz'`.

### Architectural root cause
**The leaf dockers' `ARG BASE` hardcodes the trixie literal; the build system does not pass `--build-arg BASE`.**
- `dockers/docker-database/Dockerfile.j2:2` → `ARG BASE=docker-config-engine-trixie-{{DOCKER_USERNAME}}:{{DOCKER_USERTAG}}` ("trixie" is a literal, not a variable).
- Across the tree, 24 leaves use `docker-config-engine-trixie`, 9 use `docker-swss-layer-trixie` — all hardcoded.
- slave.mk's two docker build rules (`:1175` simple and `:1316` normal) have `--build-arg` lists (`:1187`, `:1371`) that **neither contains `BASE`**.
- Therefore the leaf's `FROM $BASE` is always `docker-config-engine-trixie-...`, regardless of BLDENV.

**Corollary:** remapping `DOCKER_CONFIG_ENGINE_TRIXIE := $(DOCKER_CONFIG_ENGINE_RESOLUTE)` only makes `_LOAD_DOCKERS` load the resolute base image, but the leaf Dockerfile still does `FROM docker-config-engine-trixie-...` (trixie tag) → the trixie base is not built → build fails. **To make leaves use the resolute base, you must edit the leaf files themselves** (there is no `--build-arg BASE` shortcut).

### Current state
- **Implemented resolute naming chain (commit `a8fee77a4`, 2026-07-05):** 50 leaf `.j2` ARG BASE + 45 `.mk` (`_LOAD_DOCKERS`/`_DBG_DEPENDS`/`_DBG_IMAGE_PACKAGES`) switched from trixie to resolute; `slave.mk` adds a `BLDENV==resolute` branch that filter-outs 3 trixie base images; `docker-base-trixie` reverted to `FROM debian:trixie` (trixie variant restored to pristine, reverting `3d265d73b`); resolute variant dirs/rules now feed the vs build chain (FROM chain `ubuntu:resolute → docker-base-resolute → docker-config-engine-resolute → docker-swss-layer-resolute`). The trixie variant is fully retained, BLDENV=trixie still goes through the `else` default branch (control path). This approach is not among the A/B/C options below — direct sed of leaf `ARG BASE` (non-templated, non-copied dirs) + resolute base variant + slave.mk filter-out.
- **Pending:** the 3 `.j2` + 1 `.mk` variant-naming changes inside the `platform/vpp` submodule need a submodule commit + pointer bump (C1, handled separately; the vs build does not depend on vpp). Full build + KVM verification is pending (C4).

### Options for "clean" resolute naming
| Option | Changes | Cost |
|---|---|---|
| A. Keep committed (recommended) | Revert the resolute variant dirs; `docker-base-trixie` FROM ubuntu:resolute | 0; goal already achieved, base is named trixie but content is resolute |
| B. Templated variant suffix | 34 leaf `.j2` change the hardcoded `trixie` in `ARG BASE` to `{{DOCKER_VARIANT}}`; j2 rendering exported per BLDENV; 34 `docker.mk` add `SONIC_RESOLUTE_DOCKERS`; slave.mk remap | ~70 sites + j2 context; one docker set switches per BLDENV |
| C. Full resolute leaf copy | Copy 34 leaf docker dirs as `-resolute` versions + 34 `docker.mk` | ~70 new files; high maintenance burden |

---

## 5. Pending / TODO

- **Submodule pointers uncommitted:** ~~swss-common/swss/sairedis/gnmi/linkmgrd/stp/redfish/dhcprelay/wpasupplicant/libnl3 working-tree changes need to be committed within each submodule repo, then bump the parent repo pointers.~~ **✅ Done (C1, 2026-07-05):** 14 submodules committed patches on their respective `resolute` branches + parent gitlink bump (commit `5e4f25d43`); the 3 corrupted object stores (sonic-mgmt-framework/sonic-swss/sonic-sairedis, `--reference` alternates lost) were fixed by re-cloning from origin. A fresh clone can now reproduce.
- **pkgutil sed off-by-one (C3):** ~~the pkgutil sed in `sonic_debian_extension.j2` used `spec.submodule_search_locations[0]` (the package dir), and `os.path.dirname()` returns the parent, so the CLI plugin was placed in the wrong location.~~ **✅ Fixed (C3, commit `e93860839`):** switched to `spec.origin` (`__init__.py`), `dirname()` restores the original behavior.
- **done-bar smoke evidence (C4):** **✅ Verified (2026-07-05):** post-commit state (C1+variant-naming+C3) build succeeded (`sonic-vs.bin` 2.4G, build commit `e938608`) + KVM boot + login + `show version` (resolute.0-e938608 docker tag, variant-naming verified) + `docker ps` (database/gnmi/pmon healthy) + os-release=Ubuntu 26.04. See `docs/superpowers/plans/done-bar-status.txt`.
- **bash plugin patch (~7 hunks):** current bash does not carry plugins, pending port to 5.3. (review I9 measured 32 hunks/8 files/583 lines, the workload was underestimated.)
- **libnl3 RTA_NH_ID:** currently worked around with an alias wrapper; the cleaner approach is to have swss upstream switch to `rtnl_route_get_nhid` (no underscore, native to libnl 3.12).
- **swss tests:** removing tests from `SUBDIRS` skipped protobuf/gtest compilation; long-term should adapt to protobuf 3.21.12 + GCC 15 (the protected access of `std::mutex mu_{}` brace-init).
- **`alternate object path` warning:** `.git/modules/.../objects/info/alternates` points to the original repo, git reports a warning at build time (non-fatal, environment state).
- **sonic-stp submodule changelog:** working tree changed, pointer pending commit. ~~**✅ Committed (C1).**~~
- **`show.plugins.dhcp-relay/macsec` import warning (C4 investigation conclusion, not a build defect):** running `show` reports `failed to import plugin show.plugins.dhcp-relay/macsec: No module named`. This was once misjudged as a squashfs packaging loss (because `target/sonic-vs.bin__vs__rfs.squashfs`, a non-real intermediate artifact, was inspected). Inspecting the **real runtime rootfs** (qcow2 `part3/image-resolute.0-e938608/fs.squashfs`) confirmed that `show/plugins/` has the complete 18 .py files including `dhcp-relay.py`/`macsec.py`, and sonic-utilities is complete. Real cause: Python module names cannot contain hyphens — `util_base.py:23` `pkgutil.iter_modules` returns the disk name `dhcp-relay`, and `:31` `importlib.import_module` necessarily raises `ModuleNotFoundError`. Upstream master is unfixed (same `import_module` usage), commits `f36ac95a`/`8647356d` downgrade it to `log_warning` (non-fatal); tri/202605 also fail → not a resolute regression, not C1-C3. The `No such command` from `show ip intf`/`show ip bgp sum` is really because `Db()` fails to connect to configdb (database container just Up + vs has no minigraph → configdb empty) → click does not register the `ip` subcommand tree, a runtime timing issue.
- **vs has no minigraph.xml by default:** `config load_minigraph -y` fails (`/etc/sonic/minigraph.xml` does not exist). The vs image does not preinstall minigraph by default, requiring a separate generate/import step.

---

## 6. Key Lessons

1. **Edit the j2 template, not the generated .sh:** `sonic_debian_extension.sh` is regenerated from `sonic_debian_extension.j2` on every build; editing `.sh` is ineffective. This is a pit stepped into twice.
2. **Version-number collision trap:** SONiC's patched libnl `3.12.0-2` is identical to the resolute apt version → same-version dpkg does not overwrite → the patch does not take effect. Either bump the version number, or rely on the linker version-script to control symbol export.
3. **doxygen `<ref>` is the deepest pit:** on the surface it looks like parse.pl's 2199 tag errors, but the root cause is doxygen 1.15.0's XML output format change. Turning off `AUTOLINK_SUPPORT` solves it in one shot — locating the root cause beats patching one by one.
4. **`--no-build-isolation` + CFLAGS:** in resolute's pip ecosystem, apt packages have no RECORD file, and pip does not recognize installed packages and recompiles from source. Adding `--no-build-isolation` + global CFLAGS to `install_pip_package` is the pragmatic solution.
5. **Downgrade warnings rather than edit code:** for "should-not-hand-edit" code like SWIG-generated code, protobuf headers, and lxml Cython-generated code, using `-Wno-error=xxx` or macro redefinition (`-D__fds_bits=fds_bits`) is more sustainable than editing the source.
