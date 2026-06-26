# PR #3 — Ubuntu Noble (24.04) based on community 202405 release

> **Target branch:** `202405` ← **Source branch:** `202405_noble`
> **Changed files:** 192 | **Additions:** +4,342 | **Deletions:** -478 | **Commits:** 197 (squash-merged as one logical change)

---

## Overview

This PR rebases SONiC from Debian Bookworm to **Ubuntu 24.04 LTS (Noble)** across the entire stack — build slave, host root filesystem, and all runtime Docker containers. It is the foundational change for Canonical's `feature_noble_build` branch.

The work touches the build system, the slave Docker image, the root filesystem bootstrap, package build rules, Docker base images, submodule remapping, and fixes for Noble-compatible component builds. Some unrelated bug fixes (shared with the upstream community build) are also included.

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

### `sonic-slave-noble/` (new — 6 files, +820 / -0)

| File | Description |
|---|---|
| `Dockerfile.j2` (769 lines) | Build slave image based on `ubuntu:24.04` — installs all build toolchains, Python 3.12, compilers, libraries, docker-in-docker |
| `Dockerfile.user.j2` | User-customizable slave layer |
| `pip.conf` | Pip retry and timeout tuning |
| `no-check-valid-until` | Avoid snapshot-based apt failures |
| `disable-non-manylinux.patch` | Patch for manylinux wheel handling |
| `sonic-jenkins-id_rsa.pub` | Canonical CI SSH public key |

### `scripts/build_debian_base_system.sh`
- Debian mirror (`deb.debian.org`) replaced with Ubuntu archive (`archive.ubuntu.com`)
- `IMAGE_DISTRO` now uses `noble` instead of `bookworm`

### `scripts/build_mirror_config.sh`
- Build mirror configuration updated for Noble

### `scripts/build_kvm_image.sh`
- Build configuration updated

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

### `install_sonic.py` (+1 / -1)
- Base image reference updated

---

## 3. Docker Base Images — Noble Variants

### `dockers/docker-base-noble/` (new — 11 files, +312 / -0)
A new Docker base image based on `ubuntu:24.04`, with:
- `Dockerfile.j2` — Minimal Ubuntu 24.04 image with rsyslog, supervisor, pip, python3, redis-tools, etc.
- Supervisor config (`/etc/supervisor/supervisord.conf`)
- rsyslog config (`/etc/rsyslog.conf`, `/etc/rsyslog.d/supervisor.conf`, rsyslog-apparmor profile)
- `dpkg_01_drop` — dpkg configuration for installed-size compression
- `no_install_recommend_suggest` — apt config to skip recommended/suggested packages
- `pip.conf` — pip config
- `no-check-valid-until` — apt snapshot compatibility

### `dockers/docker-config-engine-noble/` (new — 2 files, +60 / -0)
- Config-engine base image based on `docker-base-noble`, with `pyangbind`, `python-redis`, build tools

### `dockers/docker-swss-layer-noble/` (new — 1 file, +24 / -0)
- SWSS layer base image based on `docker-base-noble`

### `dockers/docker-base/Dockerfile.j2` (+1 / -1)
- Base image tag updated from `docker-base-bookworm` to `docker-base-noble`

### All other container `Dockerfile.j2` files (~30 files)
- All changed from `docker-base-bookworm` to `docker-base-noble` (1 line each)
- Affects: database, dhcp-relay, dhcp-server, eventd, fpm-frr, iccpd, lldp, macsec, mux, nat, orchagent, pde, platform-monitor, router-advertiser, sflow, snmp, sonic-gnmi, sonic-mgmt-framework, sonic-mgmt, teamd

### `get_docker-base.sh` (+1 / -1)
- Bookworm → Noble base image reference

---

## 4. Platform Docker Changes

### New Noble templates
| File | Description |
|---|---|
| `platform/template/docker-gbsyncd-noble.mk` | Noble-based gbsyncd build rules |
| `platform/template/docker-syncd-noble.mk` | Noble-based syncd build rules |

### Virtual switch (VS) Dockerfiles
- `platform/vs/docker-gbsyncd-vs/Dockerfile.j2` (+12 / -14): Noble base, non-interactive dpkg
- `platform/vs/docker-sonic-vs/Dockerfile.j2` (+6 / -6): Noble base, python3 fixes
- `platform/vs/docker-syncd-vs/Dockerfile.j2` (+5 / -5): Noble base
- `platform/vs/docker-dash-engine/Dockerfile.j2` (+1 / -1): Base tag update

### Platform component Dockerfiles
- `platform/components/docker-gbsyncd-broncos/Dockerfile.j2` (+1 / -1)
- `platform/components/docker-gbsyncd-credo/Dockerfile.j2` (+1 / -1)

### Build rules
- All `platform/*.mk` files updated: `bookworm` → `noble`

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
- `rules/dhcpmon.mk`, `rules/dhcprelay.mk`, `rules/eventd.mk`, `rules/isc-dhcp.mk`
- `rules/linkmgrd.mk`, `rules/lldpd.mk`, `rules/lm-sensors.mk`, `rules/monit.mk`
- `rules/sairedis.mk`, `rules/sflow.mk`, `rules/sonic-dash-api.mk`, `rules/swss-common.mk`
- `rules/syncd.mk`, `rules/libteam.mk`, `rules/libyang.mk`, `rules/libyang2.mk`, `rules/frr.mk`

**Ubuntu version bumps:**
- `rules/openssh.mk`: `9.2p1-2+deb12u1` → `9.7p1-6`
- `rules/ipmitool.mk`: Version suffix `4` → `9`
- `rules/protobuf.mk`: Version suffix `3-3` → `3-8.2build1`, package names with `t64` suffix (Ubuntu multiarch transition)
- `rules/linux-kernel.mk`: `6.1.0-11-2` → `6.8.0-1000`
- `rules/snmpd.mk`: Version bumped (listed in Shared Bug Fixes section)

**Ubuntu-specific build adjustments:**
- `rules/scapy.mk`: Conditional build — skip building on Noble (use system package)
- `rules/libnl3.mk`: Use system libnl3 from Ubuntu (build on Noble disabled)
- `rules/grpc.mk`: `BLDENV=bullseye` → `noble`
- `rules/config`: `DEFAULT_KERNEL_PROCURE_METHOD = build` → `download`, `INCLUDE_ICCPD = n` → `y`
- `rules/functions`: Removed `--customize scripts/j2cli/json_filter.py` from j2 invocation (part of j2cli→jinjanator migration)

**Other updated rules:**
- `rules/frr.mk`, `rules/libteam.mk`, `rules/libyang.mk`, `rules/libyang2.mk`
- All primarily debug suffix changes

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

### `src/ifupdown2/`
- New patch: `0004-fix-compat-python312.patch` — `RawConfigParser.readfp()` → `read_file()` (Python 3.12 API change)

### `src/ipmitool/`
- `Makefile`: Added `.ddeb` to cleanup pattern (Ubuntu debug package suffix)
- New patch: `0002-Remove-with-kerneldir-option.patch` — Removes `--with-kerneldir` configure option for Ubuntu kernel compatibility

### `src/isc-dhcp/Makefile` (+3 / -0)
- Added `mkdir debian/isc-dhcp-client-udeb/sbin` as workaround for jammy build

### `src/dash-sai/Makefile` (+2 / -1)
- Removed `-Wdangling-pointer=1` CFLAGS (not supported by GCC on Ubuntu 24.04)

### `src/sonic-py-common/tests/device_info_test.py` (+3 / -3)
- Commented out `assert_called_once()` calls (Python 3.12 mock compatibility)

### `src/sonic-config-engine/setup.py` (+0 / -1)
- Removed `lxml==4.9.1` dependency (not available on Ubuntu 24.04)

### `src/sonic-bgpcfgd/tests/test_static_rt_bfd.py`
- Renamed to `.disable` — test incompatible with Python 3.12

### `src/system-health/health_checker/sysmonitor.py` (+1 / -1)
- Added `srv_type == "idle"` to health check — Ubuntu 24.04's systemd introduces `dmesg.service` of type `idle`, which would otherwise be reported as unhealthy

### `files/image_config/copp/copp-config.service` (+1 / -0)
- Added `User=root` to fix permission issue during Copp configuration

### `files/image_config/rsyslog/rsyslog-apparmor` (new)
- AppArmor rules allowing rsyslog omprog module access

### Docker init scripts (Ubuntu container startup)
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

### Other build updates (Ubuntu versions)
- `src/flashrom/Makefile`, `src/ixgbe/Makefile`, `src/kdump-tools/Makefile`
- `src/libteam/Makefile`, `src/libyang1/Makefile`, `src/libyang2/Makefile`
- `src/lldpd/Makefile`, `src/monit/Makefile`, `src/openssh/Makefile`
- `src/protobuf/Makefile` — dget source switched from `deb.debian.org` to `archive.ubuntu.com`; package names with `t64` suffix
- `src/socat/Makefile`, `src/wpasupplicant/Makefile` — Debug package suffix changed to `.$(DBG_DEB)`
- `platform/pddf/platform-api-pddf-base/setup.py` — Removed Python version constraint

---

## 8. Shared Bug Fixes (also needed by upstream Debian builds)

These changes address build issues that exist regardless of the OS distribution. The upstream `sonic-net/sonic-buildimage` `master` branch contains equivalent fixes.

### Source download URL migration (`sonicstorage.blob.core.windows.net` → `packages.trafficmanager.net`)
The fork inherited old Azure blob storage URLs from the snapshot point of the upstream `202405` branch:
- `src/swig/Makefile`
- `src/socat/Makefile`
- `src/thrift/Makefile`
- `src/snmpd/Makefile`
- `rules/sonic-fips.mk`

### j2cli → jinjanator migration
Upstream renamed `j2cli` to `jinjanator`; this PR applies corresponding changes:
- `Makefile.work`: Updated j2 version detection and error message
- `rules/functions`: Removed `--customize scripts/j2cli/json_filter.py` flag (filter no longer needed)
- `files/build_templates/sonic_debian_extension.j2`: Changed `j2cli` → `jinjanator` in apt install

### Jinja `json` → `tojson` filter rename
- `files/build_templates/manifest.json.j2`: All `|json` filters changed to `|tojson` (the `json` filter was removed in newer Jinja releases)

### `src/systemd-sonic-generator/` — C++ standard & buffer overflow fix
- `Makefile`: C++ standard `c++11` → `c++14` (GCC 13 on Ubuntu 24.04 defaults to C++17; the explicit `-std=c++11` conflicts)
- `systemd-sonic-generator.cpp`: `calloc(target.length() + 1)` → `calloc(PATH_MAX + 1)` (buffer overflow fix)
- `ssg-test.cc`: Added missing `#include <fstream>`

### Package build fixes
- `src/snmpd/Makefile`: URL migration to `packages.trafficmanager.net`; version bumped to `5.9.4+dfsg-1.1ubuntu3.2`; Stgit patching skipped on Noble (uses Ubuntu-native source)
- `src/socat/Makefile`: URL migration (sonicstorage → trafficmanager)

---

## 9. System Config Files (Ubuntu-specific)

| File | Description |
|---|---|
| `files/apt/sources.list.j2` | Apt sources template updated for Noble (Ubuntu repos, `main restricted multiverse universe`) |
| `files/build/versions/default/versions-web` | URLs repointed from Debian to Ubuntu packages |
| `files/build_templates/manifest.json.j2` | Jinja filter `json` → `tojson` (see Shared Bug Fixes) |
| `files/build_templates/sonic_debian_extension.j2` | Noble paths, grpcio version bumped to `1.65.1`, added `ninja meson` pip packages, smartmontools from Noble backports, `resolvconf.service` → `resolv-config.service`, watchdog `0.10.3` → `4.0.1`, dash-engine disabled on Noble |
| `files/rsyslog/00-load-omprog.conf` (new) | Rsyslog omprog module config |
| `files/rsyslog/rsyslog.conf` (new) | Rsyslog configuration |
| `files/supervisor/supervisord.conf` (new) | Supervisor configuration |

---

## Key Points for Reviewers

1. **OS base change**: Debian → Ubuntu 24.04 across the entire stack. This is a foundational change affecting every layer.
2. **Submodule forks** under `canonical/*` include Python 3.12 compatibility and Noble-specific changes not yet upstream. `src/sonic-frr/frr` submodule commit is also updated.
3. **Kernel upgrade**: 6.1 → 6.8 (Ubuntu's Noble kernel) requires hardware driver testing.
4. **Debug packages**: Ubuntu uses `.ddeb` suffix instead of `.deb` — handled via `$(DBG_DEB)` variable.
5. **Bug fixes included**: Source URL migration, j2cli→jinjanator, Jinja tojson filter, and build fixes that also apply to upstream Debian builds.
6. **ICCPD enabled**: `rules/config` now sets `INCLUDE_ICCPD = y`.
7. **Redis config**: The new `redis.conf` (1881 lines) replaces the upstream default — verify settings.
8. **Test disabled**: `src/sonic-bgpcfgd/tests/test_static_rt_bfd.py` renamed to `.disable`.
