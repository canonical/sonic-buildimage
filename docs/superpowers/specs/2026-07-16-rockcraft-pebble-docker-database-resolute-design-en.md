# Rockcraft + Pebble Migration for docker-database on Ubuntu Resolute

**Date:** 2026-07-16 (updated 2026-07-20)
**Branch:** `202605_resolute_rock` → PR #5
**Scope:** `dockers/docker-database` container only (VS/single-ASIC)
**Reference:** `feature_noble_build` branch (Noble implementation), PR #4 (AI-generated, for reference only)

## 1. Goal

Migrate the `docker-database` container's packaging from Dockerfile to Rockcraft and its in-container process manager from supervisord to Pebble, on the `202605_resolute` branch (Ubuntu 26.04).

Both the existing Dockerfile path and the new Rockcraft path must coexist in the same branch. Other containers will be migrated later.

## 2. Scope Constraints

- **VS/single-ASIC only** — the initial rock only starts a single Redis instance via a static pebble service. Multi-ASIC and VoQ chassis dynamic instance generation is deferred.
- **Only docker-database** — other containers are out of scope.
- **202605_resolute is WIP** — we build on the current state of the migration, which is not yet fully complete.

## 3. Key Noble vs Resolute Differences

| Aspect | Noble (feature_noble_build) | Resolute (202605_resolute) |
|--------|-----|----------|
| Python version | 3.12 | 3.14 |
| Build-base | `ubuntu@24.04` | `ubuntu@26.04` |
| Template tool | `j2` | `jinjanate` |
| docker-database-init.sh | Simple (j2, no multi-database) | Advanced (jinjanate, BMP_DB_PORT, multi-database, is_protected_mode) |
| Dockerfile.j2 | Single stage | Multi-stage (rsync_from_builder_stage, multi_database_config.json.j2, INCLUDE_SYSTEM_EVENTD) |
| Docker layer chain | Flattened in rockcraft.yaml | Same need — 3 layers must be flattened |
| rules/scripts.mk | Removed entries (CONTAINER_CHECKER etc.) | Still has them — must only ADD, not remove |
| rsyslog forwarding | omfwd (UDP 514) | omrelp (TCP 2514, reliable) |

## 4. Architecture

### 4.1 Coexistence Principle

- Existing files (`Dockerfile.j2`, `docker-database-init.sh`, `supervisord.conf.j2`, etc.) are **not modified**.
- New rock-specific files are created as copies with rock-related names.
- The only shared file directly modified is `files/build_templates/docker_image_ctl.j2` (to support both pebble and supervisord container readiness checks).
- Both Dockerfile-based and Rockcraft-based containers must be buildable from the same branch.

### 4.2 Build Flow

```
make target/sonic-vs.img.gz       (original Dockerfile path, unchanged)
        |
        v
build_rocks.sh                   (new standalone script, run manually)
  |- Copy debs/wheels/files from target/ into dockers/docker-database/
  |- rockcraft pack               -> .rock OCI archive
  |- rockcraft.skopeo copy        -> docker daemon
  |- docker save | pigz            -> target/docker-database.gz
```

### 4.3 Container Process Management (Pebble)

```
Pebble daemon
  |- rsyslogd service (startup: enabled)
  |- init service (rock-database-init.sh, startup: enabled)
  |    |- source /usr/share/sonic/scripts/envs
  |    |- pebble add syslog-layer --combine
  |    |- pebble replan
  |    |- generate database_config.json (jinjanate)
  |    |- pebble start redis
  |    `- pebble start flushdb
  |- redis service (startup: enabled, started by init)
  `- flushdb service (on-success: ignore)
```

## 5. Docker Layer Chain Analysis

Rockcraft `base: bare` does not support image layers. The `docker-database` Dockerfile inherits from `docker-config-engine-resolute`, which inherits from `docker-base-resolute`. All three layers must be flattened into a single `rockcraft.yaml`.

### 5.1 Layer 1: docker-base-resolute (FROM ubuntu:resolute)

**apt packages (runtime):**
- curl, less, perl, procps, python3, python3-pip, python3-setuptools, python3-wheel, vim-tiny, redis-tools, libdaemon0, libdbus-1-3, libjansson4, iproute2, net-tools, jq, libzmq5, libwrap0, libatomic1
- rsyslog, rsyslog-relp (remote syslog forwarding via omrelp)

**pip packages:**
- `jinjanator` — needed (rock-database-init.sh uses it for template rendering)
- `supervisord-dependent-startup==1.4.0` — **not needed** (pebble replaces supervisord)

**SONiC debs:**
- `socat` — dpkg -x

**Config files:**
- `etc/rsyslog.conf` — needed (SONiC custom rsyslog config with omrelp forwarding). Referenced via `RSYSLOG_CONF` variable pointing to `dockers/docker-base-resolute/etc/`.
- `etc/rsyslog.d/supervisor.conf` — **not needed** (monitors supervisord.log)
- `etc/supervisor/supervisord.conf` — **not needed** (pebble replaces supervisord)
- `pip.conf` — needed (pip install in rock build)
- `dpkg_01_drop` — **not needed** (base: bare doesn't use dpkg install flow)
- `sources.list` — **not needed** (base: bare has no apt)

### 5.2 Layer 2: docker-config-engine-resolute (FROM docker-base-resolute)

**apt packages:**
- `apt-utils, build-essential, python3-dev` — **not needed** (build-time only, purged in Dockerfile)
- `python3-cffi` — **not needed** (database container runtime never imports libyang3-py3 or cffi; swsscommon is a C++ extension, not a cffi binding)
- `python3-redis` — needed (sonic-db-cli runtime dependency)
- `python3-yaml` — needed (config engine runtime dependency)

**pip packages:**
- `pyangbind==0.8.7` (then uninstall enum34) — needed (runtime yang model processing)

**SONiC debs:**
- `libswsscommon` — dpkg -x
- `libyang3` — dpkg -x
- `libyang3-py3` (actual package: `python3-libyang`) — dpkg -x
- `python3-swsscommon` — dpkg -x
- `sonic-db-cli` — dpkg -x
- `sonic-eventd` — dpkg -x
- `sonic-supervisord-utilities-rs` — **not needed** (supervisord related)

**Python wheels:**
- `sonic_py_common` — pip install
- `sonic_yang_mgmt` — pip install
- `sonic_yang_models` — pip install
- `sonic_containercfgd` — pip install
- `sonic_config_engine` — pip install
- `sonic_supervisord_utilities` — **not needed** (supervisord related)

**Files:**
- `files/swss_vars.j2` → `/usr/share/sonic/templates/` — needed
- `files/readiness_probe.sh` → `/usr/bin/` — needed
- `files/container_startup.py` → `/usr/share/sonic/scripts/` — needed
- `$(SWSS_VARS_TEMPLATE)` — needed (registered in SONIC_COPY_FILES)
- `$(RSYSLOG_PLUGIN_CONF_J2)` — included (registered in SONIC_COPY_FILES)
- `$(RSYSLOG_CONF)` — needed (registered in SONIC_COPY_FILES, registered in `docker-config-engine-resolute.mk`)
- `$(RSYSLOG_PEBBLE_LAYER)` — needed (registered in SONIC_COPY_FILES, registered in `docker-config-engine-resolute.mk`)
- `$(SONIC_CTRMGRD)` container script / health probe / startup script — **needed** (host-side container management)

### 5.3 Layer 3: docker-database (FROM docker-config-engine-resolute)

**apt packages:**
- `redis-tools` — already in layer 1
- `redis-server` — needed

**pip packages:**
- `click` — needed

**SONiC debs:**
- `libswsscommon` — dpkg -x (duplicate with layer 2, deduplicate)
- `sonic-db-cli` — dpkg -x (duplicate with layer 2, deduplicate)
- `libdashapi` — dpkg -x

**Files:**
- `supervisord.conf.j2` — **not needed** (pebble replaces supervisord)
- `critical_processes.j2` — **not needed** (pebble ignores critical processes for now)
- `docker-database-init.sh` — **not needed** (replaced by `rock-database-init.sh`)
- `database_config.json.j2` → `/usr/share/sonic/templates/` — needed
- `database_global.json.j2` → `/usr/share/sonic/templates/` — needed
- `multi_database_config.json.j2` → `/usr/share/sonic/templates/` — needed
- `files/90-sonic.conf` → `/usr/lib/sysctl.d/` — needed
- `files/update_chassisdb_config` → `/usr/local/bin/` — needed
- `flush_unused_database` → `/usr/local/bin/` — needed
- `redis-cli` → `/usr/bin/redis-cli` — needed (BASE_IMAGE_FILES)

## 6. New Files

### 6.1 In `dockers/docker-database/`

| File | Description |
|------|-------------|
| `rockcraft.yaml` | Rockcraft manifest (see section 7) |
| `rock-database-init.sh` | Copy of Resolute `docker-database-init.sh` with supervisord replaced by pebble (see section 8) |

### 6.2 In repository root

| File | Description |
|------|-------------|
| `build_rocks.sh` | Standalone build script (see section 9) |
| `files/rsyslog/syslog-layer.yaml` | Pebble syslog layer template (copied from Noble, content unchanged) |

Note: `rsyslog.conf` is NOT a new file — it already exists at `dockers/docker-base-resolute/etc/rsyslog.conf` and is referenced via the `RSYSLOG_CONF` Makefile variable.

## 7. rockcraft.yaml Design

```yaml
name: docker-database
summary: SONiC database container
description: A Chiselled rock for SONiC database container
version: "1.0.0"

base: bare
build-base: ubuntu@26.04
license: Apache-2.0

platforms:
  amd64:

services:
  rsyslogd:
    command: /usr/sbin/rsyslogd -n -iNONE
    override: replace
    startup: enabled
  init:
    command: rock-database-init.sh
    override: replace
    startup: enabled
    on-success: ignore
    environment:
      DEBIAN_FRONTEND: "noninteractive"
      IMAGENAME: "docker-database"
      DISTRO: "resolute"
  redis:
    command: bash -c "{ [[ -s /var/lib/redis/dump.rdb ]] || rm -f /var/lib/redis/dump.rdb; } && mkdir -p /var/lib/redis && exec /usr/bin/redis-server /etc/redis/redis.conf --bind 127.0.0.1 --port 6379 --unixsocket /var/run/redis/redis.sock --pidfile /var/run/redis/redis.pid --dir /var/lib/redis"
    override: replace
    environment:
      DEBIAN_FRONTEND: "noninteractive"
      IMAGENAME: "docker-database"
      DISTRO: "resolute"
  flushdb:
    command: bash -c "sleep 300 && /usr/local/bin/flush_unused_database"
    override: replace
    on-success: ignore
    on-failure: ignore
    environment:
      DEBIAN_FRONTEND: "noninteractive"
      IMAGENAME: "docker-database"
      DISTRO: "resolute"
```

### 7.1 parts

**Part: install-rsyslog** (full packages without chisel slices)
- plugin: nil
- stage-packages: rsyslog, rsyslog-relp, libpython3.14-stdlib, libpython3.14-minimal, libpython3.14, libboost-serialization1.83.0, libxxhash0

**Part: setup-database** (chisel slices + dump plugin)
- plugin: dump
- source: `.`
- override-build:
  - `craftctl default`
  - `dpkg -x` for SONiC built debs (hardcoded list, must be maintained when dependencies change): socat, libswsscommon, libyang3, python3-libyang, python3-swsscommon, sonic-db-cli, sonic-eventd, libdashapi, libnl-3-200, libnl-route-3-200, libnl-genl-3-200, libnl-nf-3-200, libnl-cli-3-200
  - `pip3 install` for Python wheels: sonic_py_common, sonic_yang_mgmt, sonic_yang_models, sonic_containercfgd, sonic_config_engine
  - `pip3 install` for pip packages: jinjanator, click, pyangbind==0.8.7, lxml
  - `rm -rf` to clean up deb/wheel source files from install tree (preserve `files/` for organize)
- organize:
  - `database_config.json.j2` → `usr/share/sonic/templates/`
  - `database_global.json.j2` → `usr/share/sonic/templates/`
  - `envs` → `usr/share/sonic/scripts/envs`
  - `multi_database_config.json.j2` → `usr/share/sonic/templates/`
  - `files/syslog-layer.yaml` → `usr/share/sonic/templates/`
  - `rock-database-init.sh` → `usr/local/bin/`
  - `files/container_startup.py` → `usr/share/sonic/scripts/`
  - `files/readiness_probe.sh` → `usr/bin/`
  - `files/swss_vars.j2` → `usr/share/sonic/templates/`
  - `files/90-sonic.conf` → `usr/lib/sysctl.d/`
  - `files/update_chassisdb_config` → `usr/local/bin/`
  - `flush_unused_database` → `usr/local/bin/`
- stage: filter list excluding `usr/share/doc`, `usr/share/doc-base`, `usr/share/man`
- stage-packages (chisel slices): base-files_release-info, base-files_home, base-files_tmp, base-passwd_data, bash_bins, procps_bins, coreutils_bins, gawk_bins, redis-server_bins, iproute2_bins, python3.14_standard, libuuid1_libs, libhiredis1.1.0_libs, libzmq5_libs

**override-prime:**
1. `ln -sf /usr/bin/gawk usr/bin/awk`
2. `ln -sf /usr/bin/python3.14 usr/bin/python3`
3. `mv usr/lib/python3.14/dist-packages/bin/* usr/bin/`
4. Copy timezone data from build-base (`/etc/timezone`, `/etc/localtime`)
5. `chmod +x usr/local/bin/update_chassisdb_config`
6. Copy rsyslog.conf to `etc/rsyslog.conf` (must be done in override-prime, not organize, to avoid being overwritten by stage-package rsyslog's default config)
7. Apply sed modifications to chisel-provided `/etc/redis/redis.conf` (identical to Dockerfile.j2 sed)
8. Copy `manifest.json` to root

### 7.2 stage-packages split

Rockcraft does not allow mixing chisel slices and full packages in the same `stage-packages` list. They are split into two parts:
- `install-rsyslog` part: full packages (rsyslog, rsyslog-relp, libpython3.14-stdlib, libpython3.14-minimal, libpython3.14, libboost-serialization1.83.0, libxxhash0)
- `setup-database` part: chisel slices only

### 7.3 Python wheel install path

`usr/lib/python3.14/dist-packages/` (Noble uses 3.12).

## 8. rock-database-init.sh Design

Copy of the Resolute `docker-database-init.sh` with the following changes:

**Added (at script start):**
- `source /usr/share/sonic/scripts/envs` — source environment variables generated by build_rocks.sh
- Pebble syslog layer setup:
```bash
LAYER_FILE="/usr/share/sonic/templates/syslog-layer.yaml"
pebble add syslog-layer --combine $LAYER_FILE
pebble replan
```

**Removed (supervisord logic):**
- `mkdir -p /etc/supervisor/conf.d/`
- `sonic-cfggen -t supervisord.conf.j2,/etc/supervisor/conf.d/supervisord.conf`
- `sonic-cfggen -t critical_processes.j2,/etc/supervisor/critical_processes`
- `exec /usr/local/bin/supervisord`
- `is_protected_mode` / `additional_data_json` jq logic (only used for supervisord config generation)

**Added (pebble logic, at script end):**
```bash
pebble start redis
pebble start flushdb
```

**Preserved (Resolute-specific logic):**
- `export BMP_DB_PORT=6400`
- `enable_multidb` detection + `multi_database_config.json.j2` rendering via `jinjanate`
- `DATABASE_TYPE` checks (chassisdb branch preserved but not triggered in VS)
- timezone setup

## 9. build_rocks.sh Design

Standalone script:

```bash
#!/bin/bash
rocklist=(
    "dockers/docker-database"
)
set -x
set -e

for rockitem in "${rocklist[@]}"; do
    mkdir -p $rockitem/debs $rockitem/files $rockitem/python-wheels
    cp -r target/debs/resolute/*.deb $rockitem/debs/
    cp -r target/files/resolute/* $rockitem/files/
    cp -r target/python-wheels/resolute/*.whl $rockitem/python-wheels/
    echo "export IMAGE_VERSION=$(git rev-parse --abbrev-ref HEAD)-$(git rev-parse HEAD)" > $rockitem/envs

    pushd $rockitem
    rockname=$(basename $rockitem)
    rockfullname="${rockname}_1.0.0_amd64.rock"
    rockcraft clean
    rockcraft pack
    sudo rockcraft.skopeo --insecure-policy copy oci-archive:$rockfullname docker-daemon:$rockname:latest
    rm -r ./debs/ ./files/ ./python-wheels/ envs ${rockfullname}
    popd

    pushd target
    docker save $rockname:latest | pigz -c > ${rockname}.gz
    popd

    docker rmi -f $rockname:latest
done
```

Key points:
- Only copies `.deb` and `.whl` files (not all files in target/debs)
- `rsyslog.conf` and `syslog-layer.yaml` are already in `target/files/resolute/` via `SONIC_COPY_FILES` registration
- Generates `envs` file with IMAGE_VERSION, sourced by `rock-database-init.sh` inside the container

## 10. Existing Files to Modify

### 10.1 `files/build_templates/docker_image_ctl.j2`

Modify container readiness checks to support both pebble and supervisord. Replace `pgrep -x -c supervisord` with OR logic:
```bash
(($(docker exec -i ... pgrep -x -c pebble) -gt 0) || ($(docker exec -i ... pgrep -x -c supervisord) -gt 0))
```

### 10.2 `rules/scripts.mk`

Add new variables (only for resolute build environment):
```makefile
ifeq ($(BLDENV), resolute)
    RSYSLOG_CONF = rsyslog.conf
    $(RSYSLOG_CONF)_PATH = dockers/docker-base-resolute/etc/

    RSYSLOG_PEBBLE_LAYER = syslog-layer.yaml
    $(RSYSLOG_PEBBLE_LAYER)_PATH = files/rsyslog/
endif
```

Append to `SONIC_COPY_FILES`:
```makefile
                    $(RSYSLOG_CONF) \
                    $(RSYSLOG_PEBBLE_LAYER) \
```

### 10.3 `rules/scripts.dep`

Append:
```makefile
$(RSYSLOG_CONF)_CACHE_MODE  := none
$(RSYSLOG_PEBBLE_LAYER)_CACHE_MODE := none
```

### 10.4 `rules/docker-config-engine-resolute.mk`

Add `$(RSYSLOG_CONF)` and `$(RSYSLOG_PEBBLE_LAYER)` to `$(DOCKER_CONFIG_ENGINE_RESOLUTE)_FILES` so they are staged into the build tree.

### 10.5 `.gitignore`

Add entries for rockcraft build artifacts:
- `dockers/*/debs/`, `dockers/*/files/`, `dockers/*/python-wheels/`, `dockers/*/envs`, `dockers/*/*.rock`
- `installer/platforms/`
- `*service`, `justfile`

## 11. Runtime Dependencies Discovered During Testing

The following packages were found to be missing at runtime and added to `install-rsyslog` stage-packages:
- `libpython3.14` — provides `libpython3.14.so.1.0` (needed by swsscommon Python bindings)
- `libpython3.14-stdlib` — Python standard library
- `libpython3.14-minimal` — minimal Python runtime
- `libboost-serialization1.83.0` — needed by libswsscommon
- `libxxhash0` — needed by libyang3

The `redis` user/group is not created by chisel slices (no postinst). It is added via `override-prime` in rockcraft.yaml:
```bash
echo 'redis:x:999:999::/var/lib/redis:/usr/sbin/nologin' >> etc/passwd
echo 'redis:x:999:' >> etc/group
```

## 12. Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Rockcraft 26.04 build-base unsupported | Blocker | Verified working |
| Missing chisel slices at build time | Some packages may fail | Add to stage-packages without slice (works, verified) or use full package |
| Resolute migration incomplete | Build failures from unrelated issues | Build and test incrementally |
| pebble not supporting critical processes | Container may not restart on critical failure | Accepted for VS scope; future work |
| Multi-ASIC/VoQ not supported by static pebble services | Rock only works for single-ASIC | Accepted scope; future work with dynamic pebble layers |
| Build-environment not set up (LXD, rockcraft) | Can't build rocks | LXD initialized; rockcraft 1.19.2 installed |
| rockcraft not available inside sonic-slave container | Can't integrate into Makefile build graph | Accepted; build_rocks.sh runs on host after make completes |
| Hardcoded deb filenames in rockcraft.yaml | Breaks when package versions change | Must be maintained manually when dependencies change |

## 13. Verification

1. `make target/sonic-vs.img.gz` still works (Dockerfile path unchanged)
2. `build_rocks.sh` produces `target/docker-database.gz`
3. Rock-based database container starts and redis responds to PING
4. `docker_image_ctl.j2` correctly detects both pebble and supervisord containers
5. No ImportError or missing shared library errors in `pebble logs`
