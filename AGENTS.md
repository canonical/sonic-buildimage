# Agent Guide — Canonical SONiC (feature_noble_build)

## Overview

This repository is a Canonical-maintained fork of the upstream community [SONiC](https://github.com/sonic-net/sonic-buildimage) network operating system build infrastructure. SONiC (Software for Open Networking in the Cloud) is an open-source NOS that runs on network switches and is built on a containerised micro-service architecture. The system produces ONIE-compatible switch installer images, as well as individual Docker (or Rock) container images for each service component.

For an introduction to SONiC itself, how to build images, supported platforms, hardware requirements, and other general information, see the upstream [`README.md`](README.md).

This document is scoped to the **feature_noble_build** branch and describes what makes this fork different from upstream `sonic-net/sonic-buildimage`.

## Branch and origin

- **Canonical repository:** `canonical/sonic-buildimage`
- **Active development branch:** `feature_noble_build`
- **Upstream source:** `sonic-net/sonic-buildimage` (Debian-based)
- **Goal:** Rebase SONiC from Debian to **Ubuntu 24.04 (“Noble Numbat”)**, while replacing or upgrading the toolchain, container build pipeline, and service manager.

### Upstream release model

The upstream `sonic-net` community releases twice a year. Each release is created by cutting a date-named branch from `master` (e.g., `202405`, `202411`, `202505`, and so on). However, these release branches are **not stabilized** — small fixes and changes continue to be committed to them after the branch point. They function more as snapshot markers than as immutable release tags.

### Fork point

The `feature_noble_build` branch was forked from the upstream `202405` release branch. The last upstream commit before forking is:

```
926d033226f93ffb7f2a79de812b72926e1560a4
```

## Major divergences from upstream

### 1. Operating system base: Debian → Ubuntu 24.04

The baseline OS for both the build slave environment and the runtime filesystem has been changed from Debian (Bullseye/Bookworm) to Ubuntu 24.04 (“Noble”). This touches:

- **Build slave:** The canonical build uses `sonic-slave-noble/` (a Docker image based on `ubuntu:24.04`). Upstream Debian-based slave directories (`sonic-slave-bullseye`, `sonic-slave-bookworm`, etc.) are present for reference but are not the active target.
- **Runtime filesystem root:** `fsroot.docker.noble/` is the default root filesystem template.

### 2. Git submodule remapping to Canonical forks

For many upstream `sonic-net/*` submodules we maintain Canonical equivalents under [`github.com/canonical/`](https://github.com/canonical/). The `.gitmodules` file has been updated so that the following submodules point to Canonical-owned repositories:

| Submodule | Original upstream | Canonical fork |
|---|---|---|
| `src/sonic-swss-common` | `sonic-net/sonic-swss-common` | `canonical/sonic-swss-common` |
| `src/sonic-linux-kernel` | `sonic-net/sonic-linux-kernel` | `canonical/sonic-linux-kernel` |
| `src/sonic-sairedis` | `sonic-net/sonic-sairedis` | `canonical/sonic-sairedis` |
| `src/sonic-swss` | `sonic-net/sonic-swss` | `canonical/sonic-swss` |
| `src/sonic-snmpagent` | `sonic-net/sonic-snmpagent` | `canonical/sonic-snmpagent` |
| `src/sonic-utilities` | `sonic-net/sonic-utilities` | `canonical/sonic-utilities` |
| `src/sonic-platform-common` | `sonic-net/sonic-platform-common` | `canonical/sonic-platform-common` |
| `src/sonic-mgmt-framework` | `sonic-net/sonic-mgmt-framework` | `canonical/sonic-mgmt-framework` |
| `src/sonic-mgmt-common` | `sonic-net/sonic-mgmt-common` | `canonical/sonic-mgmt-common.git` |
| `src/sonic-host-services` | `sonic-net/sonic-host-services` | `canonical/sonic-host-services` |
| `src/sonic-gnmi` | `sonic-net/sonic-gnmi` | `canonical/sonic-gnmi.git` |
| `src/linkmgrd` | `sonic-net/sonic-linkmgrd` | `canonical/sonic-linkmgrd.git` |
| `platform/broadcom/saibcm-modules-dnx` | `sonic-net/saibcm-modules` | `canonical/saibcm-modules.git` |

These forks are typically for Python version upgrades (e.g. Python 3.7 → 3.12), Ubuntu Noble compatibility, and other changes not accepted (or not yet accepted) upstream.

### 3. Container build: Dockerfile → Rockcraft

The biggest operational change is that the build pipeline for runtime service containers has moved from **Dockerfiles** to **Rockcraft** (Canonical’s OCI-compatible image builder).

- **Rockcraft manifests** (`rockcraft.yaml`) exist for the majority of service containers, e.g.:
  - `dockers/docker-database/rockcraft.yaml`
  - `dockers/docker-orchagent/rockcraft.yaml`
  - `dockers/docker-fpm-frr/rockcraft.yaml`
  - `dockers/docker-lldp/rockcraft.yaml`
  - `platform/broadcom/docker-syncd-brcm/rockcraft.yaml`
  - …and many more (18+ rockcraft.yaml files total).

- A dedicated build script **`build_rocks.sh`** takes compiled `.deb` packages and Python wheels from the build tree and stitches them into the rockcraft OCI containers. Each rock is tagged and saved as a `.docker.gz` archive under `target/`.

- Because rockcraft uses `base: bare` with `build-base: ubuntu@24.04` and carefully selected stage-packages (chisel slices), the resulting images are much more minimal than the legacy Dockerfile-based images.

### 4. Process management: Supervisord → Pebble

All new rock-based containers use **[Pebble](https://github.com/canonical/pebble)** (the Canonical service manager) instead of **Supervisord** to manage in-container daemon processes.

- Every container now has an init script (e.g. `rock-database-init.sh`, `rock-orchagent-init.sh`, etc.) that adds a syslog Pebble layer and starts per-service processes via `pebble start <service>`.
- Supervisor configuration files that are still used by some processes are converted to Pebble-compatible YAML layers at runtime by a utility script (`supervisord_ini_to_pebble_yml.py` in certain containers).

### 5. Device and Platform enablement

Additional switch devices and platforms have been enabled under `device/` and `platform/`:

- **New devices:** Entries under `device/` for platforms from vendors including Celestica, Accton, Delta, Quanta, Inventec, Wistron, Nokia, etc. (some carried from upstream, others added or extended in the fork).
- **Broadcom platform modules:** Enhanced support under `platform/broadcom/` (e.g. DNX module series via `saibcm-modules-dnx`).
- **Marvell** and **Nvidia Bluefield** platforms are present and buildable.

### 6. CI and Test pipeline improvements

The `.github/` directory contains new and improved CI workflows:

| Workflow | Purpose |
|---|---|
| `.github/workflows/run_testbed.yml` | Master CI workflow that triggers real-hardware testbed builds (VS and Broadcom) via Testflinger on push to `feature_noble_build` and `test/*` / `ci-workflow` branches. |
| `.github/workflows/automerge.yml` / `automerge_scan.yml` | Automated merge/scan helpers. |
| `.github/workflows/codeql-analysis.yml` | Static analysis via CodeQL. |
| `.github/workflows/semgrep.yml` | Security-focused static analysis. |
| `.github/workflows/pr_cherrypick_prestep.yml` / `pr_cherrypick_poststep.yml` | Cherry-pick automation. |

- **Testflinger integration:** The CI submits jobs to a [Testflinger](https://testflinger.canonical.com/) server (Canonical’s test orchestrator). Job templates live under `.github/testflinger/`. VS and Broadcom install/run jobs are currently defined.

### 7. Build system hardening and optimisations

- **Ubuntu APT source management:** `sonic-slave-noble/sources.list.amd64` provides the package mirrors. The Dockerfile preserves original `ubuntu.sources` files.
- **Pip retry and timeout:** `sonic-slave-noble/pip.conf` and `apt-retries-count` tune download retry behaviour for stability in CI.
- **Apt valid-until skipping:** `no-check-valid-until` is copied into the slave to avoid snapshot-based build failures.
- **Python packages:** Many dependencies are bumped to versions compatible with Python 3.12 and Noble (e.g. `grpcio==1.65.1`, `setuptools==66.1.1`, etc., installed directly in the slave Dockerfile).
- **`sonic-build-hooks`** provides version information and metadata stamping during the build, and is available as a local source under `src/sonic-build-hooks`.

### 8. Bug fixes and other changes

- **Version bumping:** Various component versions have been bumped to align with Noble-era package availability (e.g. `libthrift-0.19.0`, `libboost1.83.0`, `libpcre3`, etc.).
- **Invalid URL replacement:** Submodules with stale or obsolete URLs have been corrected in `.gitmodules` (e.g. `https://github.com/p/redis-dump-load.git` → correct or alternative source).
- **Python 3.7 → 3.12 migration:** Throughout all Canonical-forked submodules, `python3.7` references have been replaced with `python3.12`. This includes changes to `setup.py`, `Makefile`, packaging scripts, and container entrypoints.
- **`build_image.sh`** adds support for multiple ASIC KVM images (4-ASIC and 6-ASIC variants) and the `dsc` installer image type, beyond the upstream ONIE / Aboot / RAW options.

## Quick-start (Canonical variant)

```bash
git clone -b feature_noble_build git@github.com:canonical/sonic-buildimage.git
cd sonic-buildimage
git submodule update --init --recursive
make init
make configure PLATFORM=broadcom
make SONIC_BUILD_JOBS=4 target/sonic-broadcom.bin
```

For virtual switch (VS) testing:
```bash
make configure PLATFORM=vs
make SONIC_BUILD_JOBS=4 target/sonic-vs.img.gz
```

To build the new Rockcraft-based containers (after the main image is built):
```bash
./build_rocks.sh
```

## Repository layout (key additions vs upstream)

| Path | Description |
|---|---|
| `sonic-slave-noble/` | Build slave Docker image based on Ubuntu 24.04 |
| `fsroot.docker.noble/` | Noble-based runtime filesystem root template |
| `build_rocks.sh` | Script that packages all rockcraft containers from build artifacts |
| `dockers/*/rockcraft.yaml` | Rockcraft build manifests for each service container |
| `dockers/*/rock*.sh` | Pebble-based init scripts for each service container |
| `.github/workflows/` | Canonical CI pipelines (Testflinger, CodeQL, auto-merge, etc.) |
| `.github/testflinger/` | Testflinger job templates |

## Contact and contribution

- **Upstream documentation:** [`README.md`](README.md) and [`README.buildsystem.md`](README.buildsystem.md)
- **Testflinger CI status:** https://testflinger.canonical.com/queues/sonic-ci (requires Canonical VPN)
- **Branch:** `feature_noble_build`
- **Maintainers:** See [`MAINTAINERS`](MAINTAINERS)