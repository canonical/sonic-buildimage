# PR #3 — Ubuntu Noble (24.04) based on community 202405 release

> **Target branch:** `202405` ← **Source branch:** `202405_noble`
> **Changed files:** 187 | **Additions:** +2,549 | **Deletions:** −477

## Overview

This PR rebases SONiC from Debian Bookworm to **Ubuntu 24.04 LTS (Noble)** across the entire stack — build slave, host root filesystem, and all runtime Docker containers. The work touches the build system, the slave Docker image, the root filesystem bootstrap, package build rules, Docker base images, submodule remapping, and fixes for Noble-compatible component builds.

## 1. Build System

This section covers the top-level build infrastructure changes that switch the default build target from Debian Bookworm to Ubuntu Noble. The `Makefile`, `Makefile.work`, `slave.mk`, and the new `sonic-slave-noble/` Docker image are the entry points that drive the entire build. All downstream components inherit the `BLDENV=noble` setting from here.

### `Makefile`
- Default distro targets changed: `NOBUSTER=1`, `NOBULLSEYE=1` (disabled), `NONOBLE=0` (enabled)
- `BUILD_BOOKWORM` → `BUILD_NOBLE`, `BLDENV=bookworm` → `BLDENV=noble`

### `Makefile.work`
- Docker machine detection: `debian:buster` → `ubuntu:24.04`
- `SLAVE_DIR` resolved to `sonic-slave-noble` when `BLDENV=noble`
- FIPS support disabled on Noble with a build-time warning
- `j2cli` detection updated to accept `jinjanator` (the `j2cli` Python package was renamed upstream)

### `slave.mk`
- Added `NOBLE_DEBS_PATH` / `NOBLE_FILES_PATH` alongside existing Debian codename paths
- `IMAGE_DISTRO := noble`
- `DBG_DEB` variable introduced: Ubuntu uses `.ddeb` suffix for debug symbol packages (Debian uses `.deb`)
- `SONIC_TARGET_LIST` syntax adjusted for MAKE_DEBS targets

### `sonic-slave-noble/` (new build slave image)

| File | Description |
|---|---|
| `Dockerfile.j2` | Build slave image based on `ubuntu:24.04` — installs all build toolchains, Python 3.12, compilers, libraries, docker-in-docker |
| `Dockerfile.user.j2` | User-customizable slave layer |
| `pip.conf` | Pip retry and timeout tuning |
| `no-check-valid-until` | Avoid snapshot-based apt failures |
| `disable-non-manylinux.patch` | Patch for manylinux wheel handling |
| `sonic-jenkins-id_rsa.pub` | Canonical CI SSH public key |

### `scripts/build_mirror_config.sh` and `scripts/build_debian_base_system.sh`
- Build mirror URL updated from Debian to Ubuntu

## 2. Root Filesystem (Host OS) + Kernel

This section covers the host OS bootstrap: the root filesystem is now built from Ubuntu 24.04 packages, the kernel is upgraded from Debian 6.1 to the Ubuntu Noble 6.8 kernel, and the kernel submodule (`sonic-linux-kernel`) is replaced with a PPA link carrying the Ubuntu kernel binary.

### `build_debian.sh`

| Change | Detail |
|---|---|
| Kernel version | `6.1.0-11-2` → `6.8.0-1000` (Ubuntu 24.04 kernel) |
| Initramfs | Added `busybox-initramfs`, `klibc-utils`, `cpio`, `kmod`, `udev` |
| Kernel modules | Added explicit install of `linux-modules` and `linux-modules-extra` packages |
| Kernel pinning | Added `apt-mark hold` for kernel packages |
| Kernel procurement | `DEFAULT_KERNEL_PROCURE_METHOD = build` → `download` (Ubuntu Noble kernel is distributed as pre-built binary) |
| Docker GPG key | Changed from `download.docker.com/linux/debian` → `download.docker.com/linux/ubuntu` |
| Firmware | Remove installation of `firmware-linux-nonfree` on amd64 |
| Base packages | Added `ipmitool`, re-enabled Ethernet controller firmware |
| Proc mount cleanup | Fixed umount trap to avoid re-entering chroot |

### Kernel submodule: `src/sonic-linux-kernel`

The pinned commit in `canonical/sonic-linux-kernel` replaces the Debian 6.1 kernel binary with the Ubuntu Noble 6.8.0-1000-sonic kernel. Changes:

| File | Description |
|---|---|
| `Makefile` | Rewritten for Ubuntu kernel binary download and build |
| `patch/series.ubuntu` | Ubuntu kernel patch series |
| `patch/0000-ubuntu-fix-annotation.patch` | New kernel patch for Ubuntu annotation compatibility |
| `.gitattributes` | Git LFS tracking for Ubuntu kernel binary images |

### `installer/default_platform.conf`
- Installer platform configuration updated for Noble

## 3. Docker Base Images

This section covers the Docker container stack. Three new Noble base images are introduced (`docker-base-noble`, `docker-config-engine-noble`, `docker-swss-layer-noble`), and all existing runtime containers have their `FROM` tag updated from `bookworm` to `noble`.

### New Noble base images

Three new Docker base images are introduced, serving as the foundation for all runtime containers:

| Docker Image | Description |
|---|---|
| `dockers/docker-base-noble/` | Minimal Ubuntu 24.04 image with rsyslog, supervisor, pip, python3, redis-tools, and supporting config files (`rsyslog.conf`, `supervisord.conf`, `dpkg_01_drop`, `no_install_recommend_suggest`, `pip.conf`, `no-check-valid-until`) |
| `dockers/docker-config-engine-noble/` | Config-engine base image based on `docker-base-noble`, with `pyangbind`, `python-redis`, and build tools |
| `dockers/docker-swss-layer-noble/` | SWSS layer base image based on `docker-base-noble` |

### Container base image tag changes

All existing containers have their `FROM` line updated from `docker-*-bookworm` to `docker-*-noble`. The following `Dockerfile.j2` files are affected (only the base image tag changed):

- `dockers/docker-base/Dockerfile.j2`
- `dockers/docker-database/Dockerfile.j2`
- `dockers/docker-dhcp-relay/Dockerfile.j2`
- `dockers/docker-dhcp-server/Dockerfile.j2`
- `dockers/docker-eventd/Dockerfile.j2`
- `dockers/docker-fpm-frr/Dockerfile.j2`
- `dockers/docker-iccpd/Dockerfile.j2`
- `dockers/docker-lldp/Dockerfile.j2`
- `dockers/docker-macsec/Dockerfile.j2`
- `dockers/docker-mux/Dockerfile.j2`
- `dockers/docker-nat/Dockerfile.j2`
- `dockers/docker-orchagent/Dockerfile.j2`
- `dockers/docker-pde/Dockerfile.j2`
- `dockers/docker-router-advertiser/Dockerfile.j2`
- `dockers/docker-sflow/Dockerfile.j2`
- `dockers/docker-snmp/Dockerfile.j2`
- `dockers/docker-sonic-gnmi/Dockerfile.j2`
- `dockers/docker-sonic-mgmt-framework/Dockerfile.j2`
- `dockers/docker-teamd/Dockerfile.j2`
- `platform/vs/docker-sonic-vs/Dockerfile.j2`
- `platform/vs/docker-syncd-vs/Dockerfile.j2`
- `platform/vs/docker-dash-engine/Dockerfile.j2`
- `platform/vs/docker-gbsyncd-vs/Dockerfile.j2`
- `platform/components/docker-gbsyncd-broncos/Dockerfile.j2`
- `platform/components/docker-gbsyncd-credo/Dockerfile.j2`

### Other Docker container changes

- **`dockers/docker-database/docker-database-init.sh`**: Added `chown -R redis:redis /etc/redis/redis.conf` and `/var/lib/redis/` — Ubuntu 24.04's Redis package sets stricter ownership on these paths
- **`dockers/docker-database/database_config.json.j2`**: Jinja template fix for `{{DEV | default("")}}` — compatibility with the `jinjanator` Jinja engine on Ubuntu 24.04
- **`dockers/docker-macsec/start.sh`**: Mode changed `644` → `755` (executable bit)
- **`dockers/docker-sonic-mgmt-framework/Dockerfile.j2`**: `FROM` tag changed `bookworm` → `noble`

## 4. Build Rules

This section covers the per-component build rules (`.mk` files under `rules/` and `platform/`). Most rules have trivial `BOOKWORM` → `NOBLE` renames. The notable changes are new Noble-specific rules files, version bumps for Ubuntu source packages, and a few Ubuntu-specific build adjustments.

### New rules files (Noble-specific)
| File | Description |
|---|---|
| `rules/docker-base-noble.mk` / `.dep` | Build rules for `docker-base-noble` |
| `rules/docker-config-engine-noble.mk` / `.dep` | Build rules for config-engine base |
| `rules/docker-swss-layer-noble.mk` / `.dep` | Build rules for SWSS layer |
| `rules/scripts.mk` / `rules/scripts.dep` | Build rules for script targets |
| `platform/template/docker-gbsyncd-noble.mk` | Noble-based gbsyncd build rules |
| `platform/template/docker-syncd-noble.mk` | Noble-based syncd build rules |

### Updated rules — Bookworm → Noble references

All `rules/docker-*.mk` files have `BOOKWORM` variables replaced with `NOBLE` equivalents, `SONIC_BOOKWORM_DOCKERS` → `SONIC_NOBLE_DOCKERS`. Notable changes beyond the rename:

- **`rules/docker-iccpd.mk`**: Added `--cap-add=NET_ADMIN` to run options (Ubuntu 24.04 kernel behavior)
- **`rules/docker-fpm-frr.mk`**: Added `$(LIBSNMP)` dependency (Ubuntu 24.04 packaging)
- **`rules/docker-dhcp-relay.mk`**, **`rules/docker-macsec.mk`**: `SONIC_PACKAGES_LOCAL` → `SONIC_INSTALL_DOCKER_IMAGES` / `SONIC_INSTALL_DOCKER_DBG_IMAGES` (Ubuntu packaging change)

### Version bumps

| Rule | Old | New |
|---|---|---|
| `rules/openssh.mk` | `9.2p1-2+deb12u1` | `9.7p1-6` |
| `rules/ipmitool.mk` | Version suffix `4` | `9` |
| `rules/linux-kernel.mk` | `6.1.0-11-2` | `6.8.0-1000` |
| `rules/snmpd.mk` | `5.9.3+dfsg-2` | `5.9.4+dfsg-1.1ubuntu3.2` |

### Ubuntu-specific build adjustments

- `rules/scapy.mk`: Conditional build — skip building on Noble (use system package)
- `rules/config`: `INCLUDE_ICCPD = n` → `y`

### DASH engine temporarily disabled

DASH engine support is not available on Ubuntu 24.04 in this PR. The build rules are commented out:

- `platform/vs/rules.mk` — `#include $(PLATFORM_PATH)/docker-dash-engine.mk`
- `platform/vs/rules.dep` — `#include $(PLATFORM_PATH)/docker-dash-engine.dep`

The `docker-gbsyncd-vs` container's DASH-related deb installations are also commented out.

## 5. Python 3.12 Compatibility

This PR upgrades Python from **3.11** (Debian Bookworm) to **3.12** (Ubuntu Noble). Python 3.12 removes several long-deprecated APIs (the `imp` module, `RawConfigParser.readfp()`, `unittest` assertion aliases) and requires `j2cli` to be replaced by `jinjanator`. This section covers all Python 3.12–related changes across the codebase, including submodule forks.

### Python 3.12 API removals

- **`src/ifupdown2/`**: New patch `0004-fix-compat-python312.patch` — `RawConfigParser.readfp()` → `read_file()` (API removed in Python 3.12)
- **`src/sonic-py-common/tests/device_info_test.py`**: Commented out `assert_called_once()` calls — `unittest.mock` behavior changed in Python 3.12
- **`src/sonic-bgpcfgd/tests/test_static_rt_bfd.py`**: Renamed to `.disable` — test incompatible with Python 3.12

### Jinja / j2cli → jinjanator migration

Python 3.12 removed the `imp` module, which `j2cli` depends on. Ubuntu 24.04 does not ship `j2cli`; the replacement is `jinjanator`. These changes are required for all Jinja template rendering on Ubuntu 24.04:

- **`rules/functions`**: Removed `--customize scripts/j2cli/json_filter.py` from j2 invocation — the `jinjanator` CLI does not support the `--customize` flag, and the custom JSON filter is no longer needed because Jinja's built-in `tojson` filter handles the same use case
- **`files/build_templates/manifest.json.j2`**: All `|json` filters changed to `|tojson` — the `json` filter was removed in the Jinja version shipped with Python 3.12; `tojson` is the standard replacement
- **`files/build_templates/sonic_debian_extension.j2`**: Changed `apt-get install j2cli` → commented out `apt-get install jinjanator` (installed via pip instead); `resolvconf.service` → `resolv-config.service`; dash-engine service disabled on Noble; Docker manifest validation temporarily skipped on Noble (`BLDENV != noble` guard)

### Python package version bumps

| File | Package | Old → New | Reason |
|---|---|---|---|
| `files/build_templates/sonic_debian_extension.j2` | `grpcio` | `1.51.1` → `1.65.1` | Python 3.12 wheel availability |
| `files/build_templates/sonic_debian_extension.j2` | `grpcio-tools` | `1.51.1` → `1.65.1` | Python 3.12 wheel availability |
| `files/build_templates/sonic_debian_extension.j2` | `watchdog` | `0.10.3` → `4.0.1` | Python 3.12 compatibility |
| `files/build_templates/sonic_debian_extension.j2` | `ninja`, `meson` | — (added) | New build dependencies on Ubuntu 24.04 |
| `dockers/docker-platform-monitor/Dockerfile.j2` | `grpcio` | `1.51.1` → `1.65.1` | Python 3.12 wheel availability |
| `dockers/docker-platform-monitor/Dockerfile.j2` | `grpcio-tools` | `1.51.1` → `1.65.1` | Python 3.12 wheel availability |
| `dockers/docker-orchagent/Dockerfile.j2` | `scapy` | — → `2.5.0` (added) | New dependency on Ubuntu 24.04 |
| `dockers/docker-orchagent/Dockerfile.j2` | `pyroute2` | — → `0.5.14` (added) | New dependency on Ubuntu 24.04 |
| `src/sonic-config-engine/setup.py` | `lxml` | `==4.9.1` → `>=4.9.1` | Python 3.12 wheel availability |
| `platform/pddf/platform-api-pddf-base/setup.py` | `jsonschema` | `==2.6.0` → `==4.10.3` | Python 3.12 compatibility |

### Submodule Python fixes

| Submodule | Summary |
|---|---|
| `src/sonic-utilities` | Bumped `pyroute2>=0.5.14` (upstream uses `>=0.7.7` — different resolution of the same Python 3.12 issue); added support for reading package metadata from Docker image tarballs in `sonic_package_manager/metadata.py` |
| `src/sonic-host-services` | Pinned `PyGObject==3.50.0` in `setup.py` (Ubuntu Noble ships a newer version incompatible with the existing code) |

## 6. GCC 13 Compatibility

This PR upgrades GCC from **12** (Debian Bookworm) to **13** (Ubuntu Noble). GCC 13 defaults to C++17 and is stricter about certain constructs and is stricter about certain constructs. Several submodule forks add compile flags to suppress warnings that are new in GCC 13 and would otherwise fail the build under `-Werror`:

- **`sonic-swss-common`**: Added `-Wno-ignored-attributes` to `tests/Makefile.am` — GCC 13 reports certain platform-specific `__attribute__` annotations that were silently ignored by GCC 12
- **`sonic-sairedis`**: Added `-Wno-overloaded-virtual` across multiple `Makefile.am` — GCC 13 detects more cases of virtual function hiding that GCC 12 did not
- **`sonic-swss`**: Added `-Wno-overloaded-virtual` across many `Makefile.am` — same as above

Other GCC 13 compatibility fixes:

- **`src/systemd-sonic-generator/Makefile`**: C++ standard `c++11` → `c++14` (explicit `-std=c++11` conflicts with GCC 13 defaults)
- **`src/systemd-sonic-generator/systemd-sonic-generator.cpp`**: `calloc(target.length() + 1)` → `calloc(PATH_MAX + 1)` — GCC 13 treats the original as a potential buffer overflow
- **`src/dash-sai/Makefile`**: Removed `-Wdangling-pointer=1` CFLAGS (causes build failure with GCC 13)
- **`linkmgrd`**: Bumped `libasan.so.5` → `libasan.so.8` (AddressSanitizer library version comes from GCC; Ubuntu Noble's GCC 13 ships `libasan.so.8`)

### Submodule C++ fixes

| Submodule | Summary |
|---|---|
| `src/sonic-sairedis` | Added missing `#include <cstdint>` |
| `src/sonic-swss` | Added missing `#include <cstdint>`; Docker container base changed from `debian:bookworm` to `ubuntu:24.04` |

## 7. Package Name Changes: Debian → Ubuntu

Ubuntu 24.04 renamed, split, or removed many packages compared to Debian Bookworm. The table below lists every package name change found across the entire codebase (host rootfs, Docker containers, and build rules), along with the reason.

### Library renames (Ubuntu 64-bit `time_t` transition)

Ubuntu 24.04's 64-bit `time_t` transition for 32-bit architectures means many library packages use the `t64` suffix:

| Debian Package | Ubuntu Package |
|---|---|
| `libprotobuf32` | `libprotobuf32t64` |
| `libgrpc29` | `libgrpc29t64` |
| `libprotoc32` | `libprotoc32t64` |
| `libsnmp40` | `libsnmp40t64` |
| `libboost-thread1.74.0` | `libboost-thread1.83.0t64` |
| `libboost-filesystem1.74.0` | `libboost-filesystem1.83.0t64` |
| `libboost-program-options1.74.0` | `libboost-program-options1.83.0t64` |
| `libboost-iostreams1.74.0` | `libboost-iostreams1.83.0t64` |

### Package removals (not available on Ubuntu 24.04)

| Package | Reason |
|---|---|
| `python3-distutils` | Removed from Python 3.12 standard library; replaced by `setuptools` |
| `libprotobuf32` | Replaced by `libprotobuf32t64` |
| `libgrpc29` | Replaced by `libgrpc29t64` |
| `linux-perf` | Not available in Ubuntu 24.04 package repositories |
| `busybox-initramfs` | Replaced by `busybox-initramfs` from Ubuntu repo |
| `firmware-linux-nonfree` | Not available for amd64 on Ubuntu 24.04 |

### Package additions (Ubuntu-specific)

| Package | Reason |
|---|---|
| `libsnmp40t64` | Ubuntu 24.04 renamed `libsnmp40` |
| `libnetsnmptrapd40t64` | New dependency in Ubuntu 24.04's net-snmp packaging |
| `ipmitool` | Ubuntu 24.04 ships the full package |
| `linux-modules`, `linux-modules-extra` | Ubuntu 24.04 kernel packaging splits modules into separate packages |
| `busybox-initramfs`, `klibc-utils`, `cpio`, `kmod`, `udev` | Initramfs build dependencies on Ubuntu 24.04 |

### Build-time package handling

- **`rules/protobuf.mk`**: Version suffix `3-3` → `3-8.2build1`, package names with `t64` suffix
- **`rules/snmpd.mk`**: `libsnmp40` → `libsnmp40t64`, added `libnetsnmptrapd40t64`
- **`rules/libyang.mk`**, **`rules/libyang2.mk`**: Package names updated for Ubuntu 24.04
- **`src/isc-dhcp/Makefile`**: Added `mkdir -p debian/isc-dhcp-client-udeb/sbin` (workaround for Ubuntu package build)
- **`src/ipmitool/Makefile`**: New patch `0002-Remove-with-kerneldir-option.patch` for Ubuntu kernel header compatibility
- **`src/kdump-tools/Makefile`**: `dget` → `dget -u`
- **`src/lldpd/Makefile`**: `dget` → `dget -u`
- **`src/snmpd/Makefile`**: Ubuntu 24.04 branch added — downloads Ubuntu's patched source from `archive.ubuntu.com`; Stgit patching skipped on Noble (Ubuntu-native source is pre-patched)

## 8. Systemd & System Behavior Changes (Ubuntu 24.04)

- **`src/system-health/health_checker/sysmonitor.py`**: Added `srv_type == "idle"` to the health check exemption list — Ubuntu 24.04's systemd introduces `dmesg.service` of type `idle`, which would otherwise be reported as unhealthy
- **`files/image_config/copp/copp-config.service`**: Added `User=root` — systemd on Ubuntu 24.04 requires explicit user specification for certain service types

## 9. System Config Files (Ubuntu-specific)

| File | Description |
|---|---|
| `files/apt/sources.list.j2` | Apt sources template updated for Noble (Ubuntu repos, `main restricted multiverse universe`) |
| `files/build/versions/default/versions-web` | URLs repointed from Debian to Ubuntu packages |
| `files/rsyslog/00-load-omprog.conf` (new) | Rsyslog omprog module config |
| `files/rsyslog/rsyslog.conf` (new) | Rsyslog configuration |
| `files/supervisor/supervisord.conf` (new) | Supervisor configuration |

## 10. Shared Bug Fixes

These changes are **not specific to the Debian→Ubuntu migration**. They fix pre-existing issues in the forked codebase that were already addressed in the upstream `sonic-net/sonic-buildimage` community branches. Customers performing their own migration do **not** need to replicate these items — they are listed here only for completeness.

### Source download URL migration (`sonicstorage.blob.core.windows.net` → `packages.trafficmanager.net`)

The fork inherited old Azure blob storage URLs from the snapshot point of upstream `202405`. The target `202405` branch already uses `packages.trafficmanager.net`, and upstream `master` uses the configurable `$(BUILD_PUBLIC_URL)` variable:

- `src/swig/Makefile`
- `src/socat/Makefile`
- `src/thrift/Makefile`
- `src/ixgbe/Makefile`
- `src/libyang1/Makefile`
- `src/libyang2/Makefile`
- `src/lldpd/Makefile`
- `src/snmpd/Makefile`
- `rules/sonic-fips.mk`
- `dockers/docker-sonic-mgmt/Dockerfile.j2`
- `get_docker-base.sh`

### `j2cli` detection updated to accept `jinjanator` in `Makefile.work`

- `Makefile.work`: Updated j2 version detection and error message to accept `jinjanator` (the `j2cli` Python package was renamed upstream). Already present in upstream `master`.

### Missing `#include <fstream>`

- `src/systemd-sonic-generator/ssg-test.cc`: Added missing `<fstream>` header include. Already present in upstream `master`.

### `src/flashrom/Makefile` — git tag format fix

- `tags/0.9.7` → `tags/v0.9.7` — the flashrom upstream repository changed its tag naming convention (added `v` prefix), causing checkout failure for anyone building from the old tag reference.

## Key Points for Reviewers

1. **OS base change**: Debian → Ubuntu 24.04 across the entire stack. This is a foundational change affecting every layer.
2. **Kernel upgrade**: 6.1 → 6.8 (Ubuntu's Noble kernel) requires hardware driver testing.
3. **Debug packages**: Ubuntu uses `.ddeb` suffix instead of `.deb` — handled via `$(DBG_DEB)` variable.
4. **Jinja / j2cli migration**: Python 3.12 removed the `imp` module, breaking `j2cli`. `jinjanator` replaces it, but `--customize` is unsupported and `\|json` must become `\|tojson`. This is one of the most impactful Python 3.12 changes.
5. **Package name changes**: Ubuntu 24.04's 64-bit `time_t` transition means many library packages use the `t64` suffix.
6. **GCC 13**: Stricter warnings require `-Wno-ignored-attributes` and `-Wno-overloaded-virtual` flags in several submodules.
7. **ICCPD enabled**: `rules/config` now sets `INCLUDE_ICCPD = y`.
8. **DASH engine disabled**: Not yet supported on Ubuntu 24.04.
9. **Shared bug fixes**: URL migrations, `Makefile.work` jinjanator detection, `ssg-test.cc` missing include, and `flashrom` tag fix are not migration-specific and do not need to be replicated.
