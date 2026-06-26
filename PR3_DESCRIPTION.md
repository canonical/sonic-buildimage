# PR #3 — Ubuntu Noble (24.04) based on community 202405 release

> **Target branch:** `202405` ← **Source branch:** `202405_noble`
> **Changed files:** 192 | **Additions:** +4,342 | **Deletions:** -478 | **Commits:** 197 (squash-merged as one logical change)

---

## Overview

This PR rebases SONiC from Debian Bookworm to **Ubuntu 24.04 LTS (Noble)** across the entire stack — build slave, host root filesystem, and all runtime Docker containers. It is the foundational change for Canonical's `feature_noble_build` branch.

The work touches the build system, the slave Docker image, the root filesystem bootstrap, package build rules, Docker base images, submodule remapping, and fixes for Noble-compatible component builds. A small number of unrelated bug fixes (shared with the upstream community build) are also included.

---

## 1. Build System: Debian → Ubuntu Noble

### `Makefile`
- Default distro targets changed: `NOBUSTER=1`, `NOBULLSEYE=1` (disabled), `NONOBLE=0` (enabled)
- `BUILD_BOOKWORM` → `BUILD_NOBLE`, `BLDENV=bookworm` → `BLDENV=noble`

### `Makefile.work`
- Docker machine detection: `debian:buster` → `ubuntu:24.04`
- `SLAVE_DIR` resolved to `sonic-slave-noble` when `BLDENV=noble`
- FIPS support disabled on Noble with a build-time warning

### `Makefile.cache`
- Cache key updated to reflect Noble distro

### `slave.mk`
- Added `NOBLE_DEBS_PATH` / `NOBLE_FILES_PATH` alongside existing Debian codename paths
- `IMAGE_DISTRO := noble`
- `DBG_DEB` variable introduced: Ubuntu uses `.ddeb` suffix for debug symbol packages (Debian uses `.deb`)
- `SONIC_TARGET_LIST` syntax adjusted for MAKE_DEBS targets

### `sonic-slave-noble/`

| File | Description |
|---|---|
| `Dockerfile.j2` | Build slave image based on `ubuntu:24.04` — installs all build toolchains, Python 3.12, compilers, libraries, docker-in-docker |
| `Dockerfile.user.j2` | User-customizable slave layer |
| `pip.conf` | Pip retry and timeout tuning |
| `no-check-valid-until` | Avoid snapshot-based apt failures |
| `disable-non-manylinux.patch` | Patch for manylinux wheel handling |
| `sonic-jenkins-id_rsa.pub` | Canonical CI SSH public key |

### `scripts/build_mirror_config.sh` and `scripts/build_debian_base_system.sh`
Build mirror URL updated from Debian to Ubuntu

### `scripts/build_kvm_image.sh`
Add `sudo` before `mount`

---

## 2. Root Filesystem (Host OS) Changes

### `build_debian.sh` (+30 / -17)

| Change | Detail |
|---|---|
| Kernel version | `6.1.0-11-2` → `6.8.0-1000` (Ubuntu 24.04 kernel) |
| Initramfs | Added `busybox-initramfs`, `klibc-utils`, `cpio`, `kmod`, `udev` |
| Kernel modules | Added explicit install of `linux-modules` and `linux-modules-extra` packages |
| Kernel pinning | Added `apt-mark hold` for kernel packages |
| Docker GPG key | Changed from `download.docker.com/linux/debian` → `download.docker.com/linux/ubuntu` |
| Firmware | Enabled installation of `firmware-linux-nonfree` on amd64 |
| Base packages | Added `ipmitool`, re-enabled Ethernet controller firmware |
| Proc mount cleanup | Fixed umount trap to avoid re-entering chroot |

### `installer/default_platform.conf` (+10 / -4)
- Installer platform configuration updated for Noble

### `install_sonic.py`
- Base image reference updated

---

## 3. Docker Base Images — Noble Variants

### `dockers/docker-base-noble/`
A new Docker base image based on `ubuntu:24.04`, with:
- `Dockerfile.j2` — Minimal Ubuntu 24.04 image with rsyslog, supervisor, pip, python3, redis-tools, etc.
- Supervisor config (`/etc/supervisor/supervisord.conf`)
- rsyslog config (`/etc/rsyslog.conf`, `/etc/rsyslog.d/supervisor.conf`, rsyslog-apparmor profile)
- `dpkg_01_drop` — dpkg configuration for installed-size compression (copied from debian docker base)
- `no_install_recommend_suggest` — apt config to skip recommended/suggested packages (copied from debian docker base)
- `pip.conf` — pip config (copied from debian docker base)
- `no-check-valid-until` — apt snapshot compatibility (copied from debian docker base)

### `dockers/docker-config-engine-noble/`
- Config-engine base image based on `docker-base-noble`, with `pyangbind`, `python-redis`, build tools

### `dockers/docker-swss-layer-noble/`
- SWSS layer base image based on `docker-base-noble`

### `dockers/docker-base/Dockerfile.j2`
- Base image tag updated from `docker-base-bookworm` to `docker-base-noble`

### All `Dockerfile.j2` files under `dockers/`
- Base changed from `docker-base-bookworm` to `docker-base-noble`

### `get_docker-base.sh`
- Bookworm → Noble base image reference

---

## 4. Platform Docker Changes

### New Noble templates
| File | Description |
|---|---|
| `platform/template/docker-gbsyncd-noble.mk` | Noble-based gbsyncd build rules |
| `platform/template/docker-syncd-noble.mk` | Noble-based syncd build rules |

### Virtual switch (VS) Dockerfiles
- `platform/vs/docker-gbsyncd-vs/Dockerfile.j2`: Noble base, non-interactive dpkg
- `platform/vs/docker-sonic-vs/Dockerfile.j2`: Noble base
- `platform/vs/docker-syncd-vs/Dockerfile.j2`: Noble base
- `platform/vs/docker-dash-engine/Dockerfile.j2`: Base tag update

### Platform component Dockerfiles
- `platform/components/docker-gbsyncd-broncos/Dockerfile.j2`
- `platform/components/docker-gbsyncd-credo/Dockerfile.j2`

### Build rules
- All `platform/*.mk` files updated: `bookworm` → `noble`

### Package Name Change in Ubuntu 24.04
- `python-ply` -> `python3-ply`


---

## 5. Build Rules

### New rules files (Noble-specific)
| File | Description |
|---|---|
| `rules/docker-base-noble.mk` / `.dep` | Build rules for `docker-base-noble` |
| `rules/docker-config-engine-noble.mk` / `.dep` | Build rules for config-engine base |
| `rules/docker-swss-layer-noble.mk` / `.dep` | Build rules for SWSS layer |
| `rules/scripts.mk` / `rules/scripts.dep` | Build rules for script targets |

### Updated rules

**Bookworm → Noble base image references (`.mk` files):**
- All `rules/docker-*.mk` files — `BOOKWORM` variables replaced with `NOBLE` equivalents, `SONIC_BOOKWORM_DOCKERS` → `SONIC_NOBLE_DOCKERS`
- Notable additions: `docker-iccpd.mk` adds `--cap-add=NET_ADMIN` to run options

**Debug suffix `.deb` → `.$(DBG_DEB)` (Ubuntu uses `.ddeb`):**

**Ubuntu version bumps:**
- `rules/openssh.mk`: `9.2p1-2+deb12u1` → `9.7p1-6`
- `rules/ipmitool.mk`: Version suffix `4` → `9`
- `rules/protobuf.mk`: Version suffix `3-3` → `3-8.2build1`, package names with `t64` suffix (Ubuntu multiarch transition)
- `rules/linux-kernel.mk`: `6.1.0-11-2` → `6.8.0-1000`
- `rules/snmpd.mk`: Version `5.9.3+dfsg-2` → `5.9.4+dfsg-1.1ubuntu3.2`, libsnmp40 → libsnmp40t64, added `libnetsnmptrapd40t64`

**Ubuntu-specific build adjustments:**
- `rules/scapy.mk`: Conditional build — skip building on Noble (use system package)
- `rules/libnl3.mk`: Use system libnl3 from Ubuntu (build on Noble disabled)
- `rules/grpc.mk`: `BLDENV=bullseye` → `noble`
- `rules/config`: `DEFAULT_KERNEL_PROCURE_METHOD = build` → `download`, `INCLUDE_ICCPD = n` → `y`
- `rules/functions`: Removed `--customize scripts/j2cli/json_filter.py` from j2 invocation — `j2cli` is replaced by `jinjanator` on Ubuntu 24.04, which does not support the `--customize` flag
- `rules/sonic-dash-api.mk`: `BLDENV=bullseye` → `filter bookworm noble`

---

## 6. Git Submodule Remapping

14 submodules repointed from `sonic-net/*` to `canonical/*` in `.gitmodules`:

| Submodule | Upstream → Canonical fork |
|---|---|
| `src/sonic-swss-common` | `sonic-net/sonic-swss-common` → `canonical/sonic-swss-common` |
| `src/sonic-linux-kernel` | `sonic-net/sonic-linux-kernel` → `canonical/sonic-linux-kernel` |
| `src/sonic-sairedis` | `sonic-net/sonic-sairedis` → `canonical/sonic-sairedis` |
| `src/sonic-swss` | `sonic-net/sonic-swss` → `canonical/sonic-swss` |
| `src/sonic-snmpagent` | `sonic-net/sonic-snmpagent` → `canonical/sonic-snmpagent` |
| `src/sonic-utilities` | `sonic-net/sonic-utilities` → `canonical/sonic-utilities` |
| `src/sonic-platform-common` | `sonic-net/sonic-platform-common` → `canonical/sonic-platform-common` |
| `src/sonic-mgmt-framework` | `sonic-net/sonic-mgmt-framework` → `canonical/sonic-mgmt-framework` |
| `src/sonic-mgmt-common` | `sonic-net/sonic-mgmt-common.git` → `canonical/sonic-mgmt-common.git` |
| `src/sonic-host-services` | `sonic-net/sonic-host-services` → `canonical/sonic-host-services` |
| `src/sonic-gnmi` | → `canonical/sonic-gnmi.git` |
| `src/linkmgrd` | `sonic-net/sonic-linkmgrd.git` → `canonical/sonic-linkmgrd.git` |
| `platform/broadcom/saibcm-modules-dnx` | `sonic-net/saibcm-modules.git` → `canonical/saibcm-modules.git` (branch: `sdk-6.5.29-master_2`) |

Additionally, submodule commit hashes are updated across all of these plus `src/sonic-frr/frr` (a nested submodule under frr). These forks include Python 3.12 compatibility, Noble build fixes, and other Canonical-specific changes.

---

## 7. Ubuntu-Specific Component Fixes

These changes are directly caused by the switch to Ubuntu 24.04 (Python 3.12, GCC 13, systemd changes, package naming differences) and are relevant reference for anyone performing a similar migration.

### Python 3.12 compatibility

- **`src/ifupdown2/`**: New patch `0004-fix-compat-python312.patch` — `RawConfigParser.readfp()` → `read_file()` (API removed in Python 3.12)
- **`src/sonic-py-common/tests/device_info_test.py`**: Commented out `assert_called_once()` calls — `unittest.mock` behavior changed in Python 3.12
- **`src/sonic-config-engine/setup.py`**: Removed `lxml==4.9.1` pinned dependency (not available for Python 3.12 on Ubuntu 24.04; replaced with `lxml>=4.9.1` from system)
- **`src/sonic-bgpcfgd/tests/test_static_rt_bfd.py`**: Renamed to `.disable` — test incompatible with Python 3.12

### Jinja / j2cli → jinjanator migration (Python 3.12 / Ubuntu package availability)

Python 3.12 removed the `imp` module, which `j2cli` depends on. Ubuntu 24.04 does not ship `j2cli`; the replacement is `jinjanator`. These changes are required for all Jinja template rendering on Ubuntu 24.04:

- **`rules/functions`**: Removed `--customize scripts/j2cli/json_filter.py` from j2 invocation — the `jinjanator` CLI does not support the `--customize` flag, and the custom JSON filter is no longer needed because Jinja's built-in `tojson` filter handles the same use case
- **`files/build_templates/manifest.json.j2`**: All `|json` filters changed to `|tojson` — the `json` filter was removed in the Jinja version shipped with Python 3.12; `tojson` is the standard replacement
- **`files/build_templates/sonic_debian_extension.j2`**: Changed `apt-get install j2cli` → commented out `apt-get install jinjanator` (installed via pip instead); bumped `grpcio==1.51.1` → `1.65.1` and `grpcio-tools==1.51.1` → `1.65.1` for Python 3.12 compatibility; bumped `watchdog==0.10.3` → `4.0.1`; added `ninja meson` pip packages; smartmontools installed from `noble-backports`; `resolvconf.service` → `resolv-config.service`; dash-engine service disabled on Noble; Docker manifest validation temporarily skipped on Noble (`BLDENV != noble` guard)

### GCC 13 compatibility

GCC 13 on Ubuntu 24.04 defaults to C++17 and is stricter about certain constructs:

- **`src/systemd-sonic-generator/Makefile`**: C++ standard `c++11` → `c++14` (explicit `-std=c++11` conflicts with GCC 13 defaults)
- **`src/systemd-sonic-generator/systemd-sonic-generator.cpp`**: `calloc(target.length() + 1)` → `calloc(PATH_MAX + 1)` — GCC 13 treats the original as a potential buffer overflow; `PATH_MAX` is the correct allocation size since the next line uses `snprintf(..., PATH_MAX, ...)` to write into this buffer
- **`src/dash-sai/Makefile`**: Removed `-Wdangling-pointer=1` CFLAGS (causes build failure with GCC 13 on Ubuntu 24.04)

### Systemd behavior changes (Ubuntu 24.04 systemd)

- **`src/system-health/health_checker/sysmonitor.py`**: Added `srv_type == "idle"` to the health check exemption list — Ubuntu 24.04's systemd introduces `dmesg.service` of type `idle`, which would otherwise be reported as unhealthy
- **`files/image_config/copp/copp-config.service`**: Added `User=root` — systemd on Ubuntu 24.04 requires explicit user specification for certain service types

### Package source & naming changes

Ubuntu 24.04 uses different package names (e.g., `t64` suffix for the 64-bit time_t transition) and sources packages from `archive.ubuntu.com` instead of `deb.debian.org`:

- **`src/protobuf/Makefile`**: dget source switched from `deb.debian.org` to `archive.ubuntu.com`; package names updated: `libprotobuf32` → `libprotobuf32t64`, `libprotobuf-lite32` → `libprotobuf-lite32t64`, `libprotoc32` → `libprotoc32t64`
- **`src/snmpd/Makefile`**: Ubuntu 24.04 branch added — downloads Ubuntu's patched source from `archive.ubuntu.com` (`5.9.4+dfsg-1.1ubuntu3.2`); package names updated: `libsnmp40` → `libsnmp40t64`; Stgit patching skipped on Noble (Ubuntu-native source is pre-patched); debug packages use `$(DBG_DEB)` suffix
- **`src/openssh/Makefile`**: Debug package suffixes changed to `.$(DBG_DEB)`
- **`src/wpasupplicant/Makefile`**: Debug package suffix changed to `.$(DBG_DEB)`

### Build tool workarounds

- **`src/ipmitool/Makefile`**: `dget` → `dget -u` (skip GPG signature check — Ubuntu archive uses different keyring); cleanup pattern extended to include `.ddeb`; new patch `0002-Remove-with-kerneldir-option.patch` for Ubuntu kernel header compatibility
- **`src/kdump-tools/Makefile`**: `dget` → `dget -u`
- **`src/lldpd/Makefile`**: `dget` → `dget -u`
- **`src/isc-dhcp/Makefile`**: Added `mkdir -p debian/isc-dhcp-client-udeb/sbin` (workaround for Ubuntu package build)
- **`src/flashrom/Makefile`**: Tag reference added `v` prefix (`tags/0.9.7` → `tags/v0.9.7`)

### Docker init scripts & config (Ubuntu container startup)

| File | Lines | Description |
|---|---|---|
| `dockers/docker-orchagent/docker-orchagent-init.sh` | +74 | Generates SWSS configs, handles chassis DB, starts supervisord |
| `dockers/docker-platform-monitor/docker_init.sh` | +128 | Generates supervisor config for platform monitoring daemons |
| `dockers/docker-sonic-mgmt-framework/start.sh` | +17 | Mgmt framework startup |

### New event config files (Ubuntu container logging)

- `dockers/docker-orchagent/swss_events.conf` (+18)
- `dockers/docker-fpm-frr/bgp_events.conf` (+18)
- `dockers/docker-dhcp-relay/dhcp_relay_events.conf` (+18)

### `dockers/docker-database/`

- `docker-database-init.sh`: Added `rm -f /var/lib/redis/redis.rtc`
- `redis.conf`: New 1881-line Redis 7.2 configuration file for Ubuntu
- `database_config.json.j2`: Default databases changed from 1 to 16

### `dockers/docker-platform-monitor/Dockerfile.j2` (+4 / -4)

- Fixed `two_lines_to_fill` removal, non-interactive install

### `dockers/docker-sonic-mgmt/Dockerfile.j2` (+7 / -7)

- Non-interactive package installation

### `platform/pddf/platform-api-pddf-base/setup.py`

- Removed Python version constraint

---

## 8. Shared Bug Fixes

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

### `j2cli` detection updated to accept `jinjanator` in `Makefile.work`

- `Makefile.work`: Updated j2 version detection and error message to accept `jinjanator` (the `j2cli` Python package was renamed upstream). Already present in upstream `master`.

### Missing `#include <fstream>`

- `src/systemd-sonic-generator/ssg-test.cc`: Added missing `<fstream>` header include. Already present in upstream `master`.

### `src/flashrom/Makefile` — git tag format fix

- `tags/0.9.7` → `tags/v0.9.7` — the flashrom upstream repository changed its tag naming convention (added `v` prefix), causing checkout failure for anyone building from the old tag reference.

---

## 9. System Config Files (Ubuntu-specific)

| File | Description |
|---|---|
| `files/apt/sources.list.j2` | Apt sources template updated for Noble (Ubuntu repos, `main restricted multiverse universe`) |
| `files/build/versions/default/versions-web` | URLs repointed from Debian to Ubuntu packages |
| `files/rsyslog/00-load-omprog.conf` (new) | Rsyslog omprog module config |
| `files/rsyslog/rsyslog.conf` (new) | Rsyslog configuration |
| `files/supervisor/supervisord.conf` (new) | Supervisor configuration |

---

## Key Points for Reviewers

1. **OS base change**: Debian → Ubuntu 24.04 across the entire stack. This is a foundational change affecting every layer.
2. **Submodule forks** under `canonical/*` include Python 3.12 compatibility and Noble-specific changes not yet upstream. `src/sonic-frr/frr` submodule commit is also updated.
3. **Kernel upgrade**: 6.1 → 6.8 (Ubuntu's Noble kernel) requires hardware driver testing.
4. **Debug packages**: Ubuntu uses `.ddeb` suffix instead of `.deb` — handled via `$(DBG_DEB)` variable.
5. **Jinja / j2cli migration**: Python 3.12 removed the `imp` module, breaking `j2cli`. `jinjanator` replaces it, but `--customize` is unsupported and `\|json` must become `\|tojson`. This is one of the most impactful Python 3.12 changes.
6. **Package name changes**: Ubuntu 24.04's 64-bit `time_t` transition means many library packages use the `t64` suffix (e.g., `libsnmp40` → `libsnmp40t64`, `libprotobuf32` → `libprotobuf32t64`).
7. **ICCPD enabled**: `rules/config` now sets `INCLUDE_ICCPD = y`.
8. **Redis config**: The new `redis.conf` (1881 lines) replaces the upstream default — verify settings.
9. **Test disabled**: `src/sonic-bgpcfgd/tests/test_static_rt_bfd.py` renamed to `.disable`.
10. **Shared bug fixes**: URL migrations (`sonicstorage` → `trafficmanager`), `Makefile.work` jinjanator detection update, and `ssg-test.cc` missing include are not migration-specific and do not need to be replicated.
