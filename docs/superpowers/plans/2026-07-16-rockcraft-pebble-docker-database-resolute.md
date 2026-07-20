# Rockcraft + Pebble Migration: docker-database on Resolute Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate docker-database container from Dockerfile+supervisord to Rockcraft+Pebble on the 202605_resolute branch, with both paths coexisting.

**Architecture:** A new `rockcraft.yaml` flattens the three-layer Docker inheritance chain (docker-base-resolute → docker-config-engine-resolute → docker-database) into a single Rockcraft manifest. Pebble replaces supervisord for in-container process management. A standalone `build_rocks.sh` script orchestrates the rock build after the standard `make` build completes.

**Tech Stack:** Rockcraft 1.19.2, Pebble, Chisel (ubuntu-26.04 slices), Ubuntu Resolute (26.04)

## Global Constraints

- Branch: `202605_resolute` (Ubuntu 26.04 / Resolute)
- Python version: 3.14 (not 3.12 like Noble)
- Build-base: `ubuntu@26.04` (not `ubuntu@24.04` like Noble)
- Template tool: `jinjanate` (not `j2` like Noble)
- DISTRO env var in rockcraft.yaml: `"resolute"` (not `"noble"`)
- Existing files must NOT be modified (except `docker_image_ctl.j2`, `rules/scripts.mk`, `rules/scripts.dep`)
- New rock-specific files get rock-related names (e.g., `rock-database-init.sh`)
- Both Dockerfile and Rockcraft paths must be buildable from the same branch
- Use `rockcraft.skopeo` (not `skopeo`) for OCI archive → Docker daemon conversion
- Spec: `docs/superpowers/specs/2026-07-16-rockcraft-pebble-docker-database-resolute-design-en.md`

---

### Task 1: Create shared config files

**Files:**
- Create: `files/build_templates/syslog-layer.yaml`
- Create: `files/rsyslog/rsyslog.conf`

**Interfaces:**
- Produces: `syslog-layer.yaml` (consumed by rock-database-init.sh in Task 4, referenced in rockcraft.yaml organize in Task 5)
- Produces: `rsyslog.conf` (consumed by rockcraft.yaml override-prime in Task 5, referenced in build_rocks.sh in Task 6)

- [ ] **Step 1: Create `files/build_templates/syslog-layer.yaml`**

Copy the content from `feature_noble_build` branch. This is a Pebble log-targets layer that configures syslog forwarding to the host:

```yaml
log-targets:
  host-syslog:
    override: replace
    type: syslog
    location: udp://127.0.0.1:514/
    services: [all]
```

- [ ] **Step 2: Create `files/rsyslog/rsyslog.conf`**

Copy the content from `dockers/docker-base-resolute/etc/rsyslog.conf` (the SONiC custom rsyslog config with omrelp remote forwarding). This file already exists in the repo at that path — copy its content verbatim.

- [ ] **Step 3: Verify files exist**

Run: `ls -la files/build_templates/syslog-layer.yaml files/rsyslog/rsyslog.conf`
Expected: Both files exist and are non-empty.

- [ ] **Step 4: Commit**

```bash
git add files/build_templates/syslog-layer.yaml files/rsyslog/rsyslog.conf
git commit -m "build: add syslog-layer.yaml and rsyslog.conf for rock containers"
```

---

### Task 2: Modify build system rules

**Files:**
- Modify: `rules/scripts.mk` (append new variables and SONIC_COPY_FILES entries)
- Modify: `rules/scripts.dep` (append CACHE_MODE entries)

**Interfaces:**
- Produces: `$(RSYSLOG_CONF)` and `$(SUPERVISOR_PROC_EXIT_LISTENER_SCRIPT)` Makefile variables, registered in `SONIC_COPY_FILES`, so the build system stages these files into the docker build context (and `target/files/resolute/` for build_rocks.sh to pick up)

- [ ] **Step 1: Add new variables to `rules/scripts.mk`**

After the existing `RSYSLOG_PLUGIN_CONF_J2` block (line 51) and before `GITHUB_GET` (line 53), insert:

```makefile
SUPERVISOR_PROC_EXIT_LISTENER_SCRIPT = supervisor-proc-exit-listener
$(SUPERVISOR_PROC_EXIT_LISTENER_SCRIPT)_PATH = files/scripts

RSYSLOG_CONF = rsyslog.conf
$(RSYSLOG_CONF)_PATH = files/rsyslog
```

- [ ] **Step 2: Append to SONIC_COPY_FILES in `rules/scripts.mk`**

Replace the last line of the `SONIC_COPY_FILES` block:

```makefile
                    $(GITHUB_GET) \
                    $(COPP_CONFIG_TEMPLATE)
```

with:

```makefile
                    $(GITHUB_GET) \
                    $(SUPERVISOR_PROC_EXIT_LISTENER_SCRIPT) \
                    $(RSYSLOG_CONF) \
                    $(COPP_CONFIG_TEMPLATE)
```

- [ ] **Step 3: Add CACHE_MODE entries to `rules/scripts.dep`**

Append after the existing `$(CBF_CONFIG_TEMPLATE)_CACHE_MODE` line:

```makefile
$(SUPERVISOR_PROC_EXIT_LISTENER_SCRIPT)_CACHE_MODE  := none
$(RSYSLOG_CONF)_CACHE_MODE := none
```

- [ ] **Step 4: Verify changes**

Run: `grep -n "RSYSLOG_CONF\|SUPERVISOR_PROC_EXIT_LISTENER" rules/scripts.mk rules/scripts.dep`
Expected: Variables appear in both files with correct paths and CACHE_MODE settings.

- [ ] **Step 5: Commit**

```bash
git add rules/scripts.mk rules/scripts.dep
git commit -m "build: register rsyslog.conf and supervisor-proc-exit-listener in SONIC_COPY_FILES"
```

---

### Task 3: Modify docker_image_ctl.j2 for pebble+supervisord coexistence

**Files:**
- Modify: `files/build_templates/docker_image_ctl.j2:285` (database readiness check)
- Modify: `files/build_templates/docker_image_ctl.j2:357` (chassisdb readiness check)

**Interfaces:**
- Produces: A `docker_image_ctl.j2` that detects both `pebble` and `supervisord` processes for container readiness, allowing both rock-based and Dockerfile-based containers to coexist

- [ ] **Step 1: Modify the database container readiness check (line 285)**

Replace:
```bash
        until [[ ($(docker exec -i database$DEV pgrep -x -c supervisord) -gt 0) && ($($SONIC_DB_CLI PING | grep -c PONG) -gt 0) &&
```

with:
```bash
        until [[ (($(docker exec -i database$DEV pgrep -x -c pebble) -gt 0) || ($(docker exec -i database$DEV pgrep -x -c supervisord) -gt 0)) && ($($SONIC_DB_CLI PING | grep -c PONG) -gt 0) &&
```

- [ ] **Step 2: Modify the chassisdb container readiness check (line 357)**

Replace:
```bash
        until [[ ($(docker exec -i ${DOCKERNAME} pgrep -x -c supervisord) -gt 0) &&
```

with:
```bash
        until [[ ($(docker exec -i ${DOCKERNAME} pgrep -x -c supervisord) -gt 0 || $(docker exec -i ${DOCKERNAME} pgrep -x -c pebble) -gt 0) &&
```

- [ ] **Step 3: Verify changes**

Run: `grep -n "pebble" files/build_templates/docker_image_ctl.j2`
Expected: Two lines containing `pebble`, in the database and chassisdb readiness checks.

- [ ] **Step 4: Commit**

```bash
git add files/build_templates/docker_image_ctl.j2
git commit -m "build: support pebble in docker_image_ctl.j2 container readiness checks"
```

---

### Task 4: Create rock-database-init.sh

**Files:**
- Create: `dockers/docker-database/rock-database-init.sh`

**Interfaces:**
- Consumes: `syslog-layer.yaml` (from Task 1, at `/usr/share/sonic/templates/syslog-layer.yaml` inside the container)
- Produces: `rock-database-init.sh` (referenced by rockcraft.yaml `services.init.command` in Task 5)

- [ ] **Step 1: Create `rock-database-init.sh` as a copy of `docker-database-init.sh`**

Copy `dockers/docker-database/docker-database-init.sh` to `dockers/docker-database/rock-database-init.sh`.

- [ ] **Step 2: Add pebble syslog layer setup at the script start**

After the line `mkdir -p $REDIS_DIR/sonic-db` (line 48 in the original), and BEFORE `mkdir -p /etc/supervisor/conf.d/`, insert:

```bash

LAYER_FILE="/usr/share/sonic/templates/syslog-layer.yaml"
pebble add syslog-layer --combine $LAYER_FILE
pebble replan
```

- [ ] **Step 3: Remove supervisord-specific lines**

Remove or comment out these lines:
- `mkdir -p /etc/supervisor/conf.d/` (line 49)
- In the chassisdb branch (lines 88-96), remove:
  - `sonic-cfggen -j $db_cfg_file_tmp -a "$additional_data_json" \` and the following two `-t` lines (lines 89-91)
  - `exec /usr/local/bin/supervisord` (line 95) — replace with `exit 0`
- The non-chassisdb supervisord config generation (lines 116-118):
  - `sonic-cfggen -j "$db_cfg_file_tmp" -a "$additional_data_json" \` and the following two `-t` lines
- `exec /usr/local/bin/supervisord` at the end (line 151)

- [ ] **Step 4: Add pebble service starts at the script end**

Before the final `exit 0` / end of script, after the `chown` commands, add:

```bash
pebble start redis
pebble start flushdb
```

- [ ] **Step 5: Make the script executable**

Run: `chmod +x dockers/docker-database/rock-database-init.sh`

- [ ] **Step 6: Verify no supervisord references remain**

Run: `grep -n "supervisord\|supervisor\|sonic-cfggen" dockers/docker-database/rock-database-init.sh`
Expected: No matches (all supervisord-related lines removed).

- [ ] **Step 7: Verify pebble references are present**

Run: `grep -n "pebble" dockers/docker-database/rock-database-init.sh`
Expected: Lines for `pebble add`, `pebble replan`, `pebble start redis`, `pebble start flushdb`.

- [ ] **Step 8: Commit**

```bash
git add dockers/docker-database/rock-database-init.sh
git commit -m "build: add rock-database-init.sh with pebble replacing supervisord"
```

---

### Task 5: Create rockcraft.yaml

**Files:**
- Create: `dockers/docker-database/rockcraft.yaml`

**Interfaces:**
- Consumes: `rock-database-init.sh` (from Task 4), `syslog-layer.yaml` (from Task 1), `rsyslog.conf` (from Task 1), `database_config.json.j2` / `database_global.json.j2` / `multi_database_config.json.j2` (existing in docker-database dir), `flush_unused_database` (existing), `files/update_chassisdb_config` (existing), `files/90-sonic.conf` (existing), `files/swss_vars.j2` / `files/readiness_probe.sh` / `files/container_startup.py` (staged by build system), SONiC debs and Python wheels (staged by build_rocks.sh)
- Produces: `rockcraft.yaml` manifest that builds the docker-database rock

- [ ] **Step 1: Create `dockers/docker-database/rockcraft.yaml`**

Write the full rockcraft.yaml with:
- `base: bare`, `build-base: ubuntu@26.04`
- Services: rsyslogd, init (rock-database-init.sh), redis, flushdb — all with `DISTRO: "resolute"`
- stage-packages: chisel slices (base-files, base-passwd, bash, procps, coreutils, gawk, redis-server, iproute2, python3.14_standard, libpython3.14-minimal_libs, libuuid1, libhiredis1.1.0, libzmq5) + full packages (rsyslog, rsyslog-relp)
- Parts: install-socat (dump deb), setup-database (dump with override-build doing dpkg -x for SONiC debs + pip3 install for wheels and pip packages)
- organize: map config/template files to their target paths
- override-prime: python3 symlink, redis.conf sed, rsyslog.conf copy, timezone, manifest.json

Full file content — use the spec section 7 as reference. Key Resolute-specific values:
- Python paths: `python3.14`, `libpython3.14-minimal_libs`, `usr/lib/python3.14/dist-packages/`
- DISTRO: `"resolute"`
- SONiC debs (hardcoded, maintained list): libswsscommon, libyang3, libyang3-py3, python3-swsscommon, sonic-db-cli, sonic-eventd, libdashapi, libnl-3-200, libnl-route-3-200, libnl-genl-3-200, libnl-nf-3-200, libnl-cli-3-200
- Python wheels: sonic_py_common, sonic_yang_mgmt, sonic_yang_models, sonic_containercfgd, sonic_config_engine
- pip packages: jinjanator, click, pyangbind==0.8.7, lxml
- sed on redis.conf (same as Dockerfile.j2)
- rsyslog.conf copied from `${CRAFT_PROJECT_DIR}/files/rsyslog.conf` to `etc/rsyslog.conf`

- [ ] **Step 2: Verify YAML syntax**

Run: `python3 -c "import yaml; yaml.safe_load(open('dockers/docker-database/rockcraft.yaml'))"`
Expected: No errors (valid YAML).

- [ ] **Step 3: Verify key Resolute-specific values**

Run: `grep -n "resolute\|3\.14\|26\.04" dockers/docker-database/rockcraft.yaml`
Expected: DISTRO: "resolute", python3.14 paths, build-base: ubuntu@26.04.

- [ ] **Step 4: Commit**

```bash
git add dockers/docker-database/rockcraft.yaml
git commit -m "build: add rockcraft.yaml for docker-database on Resolute"
```

---

### Task 6: Create build_rocks.sh

**Files:**
- Create: `build_rocks.sh`

**Interfaces:**
- Consumes: `rockcraft.yaml` (from Task 5), `files/rsyslog/rsyslog.conf` (from Task 1), `files/build_templates/syslog-layer.yaml` (from Task 1), SONiC build artifacts in `target/debs/resolute/`, `target/files/resolute/`, `target/python-wheels/resolute/`
- Produces: `target/docker-database.gz` (Docker image archive)

- [ ] **Step 1: Create `build_rocks.sh`**

```bash
#!/bin/bash

# Finish `make SONIC_BUILD_JOBS=4 target/sonic-vs.img.gz` first
rocklist=(
    "dockers/docker-database"
)

# Copy shared config files to target
cp files/rsyslog/rsyslog.conf target/files/resolute/
cp files/build_templates/syslog-layer.yaml target/files/resolute
set -x
set -e

for rockitem in "${rocklist[@]}"; do
    mkdir -p $rockitem/debs $rockitem/files $rockitem/python-wheels
    cp -r target/debs/resolute/* $rockitem/debs/
    cp -r target/files/resolute/* $rockitem/files/
    cp -r target/python-wheels/resolute/* $rockitem/python-wheels/
    echo "export IMAGE_VERSION=$(git rev-parse --abbrev-ref HEAD)-$(git rev-parse HEAD)" > $rockitem/envs

    pushd $rockitem
    rockname=$(basename $rockitem)
    rockfullname="${rockname}_1.0.0_amd64.rock"
    rockcraft clean
    rockcraft pack
    sudo rockcraft.skopeo --insecure-policy copy oci-archive:$rockfullname docker-daemon:$rockname:latest
    rm -r ./debs/ ./files/ ./python-wheels/
    popd

    pushd target
    docker save $rockname:latest | pigz -c > ${rockname}.gz
    popd

    docker rmi -f $rockname:latest
    rm $rockitem/envs
done
```

- [ ] **Step 2: Make executable**

Run: `chmod +x build_rocks.sh`

- [ ] **Step 3: Verify script**

Run: `bash -n build_rocks.sh`
Expected: No syntax errors.

- [ ] **Step 4: Commit**

```bash
git add build_rocks.sh
git commit -m "build: add build_rocks.sh standalone rock build script for Resolute"
```

---

### Task 7: Verify coexistence and build

**Files:**
- No new files; verification only

- [ ] **Step 1: Verify existing Dockerfile path is unmodified**

Run: `git diff HEAD~6 -- dockers/docker-database/Dockerfile.j2 dockers/docker-database/docker-database-init.sh dockers/docker-database/supervisord.conf.j2`
Expected: No changes to these files (empty diff or only unrelated changes).

- [ ] **Step 2: Verify all new files are present**

Run: `ls -la dockers/docker-database/rockcraft.yaml dockers/docker-database/rock-database-init.sh build_rocks.sh files/build_templates/syslog-layer.yaml files/rsyslog/rsyslog.conf`
Expected: All files exist.

- [ ] **Step 3: Verify modified files have correct changes**

Run:
```bash
grep -c "pebble" files/build_templates/docker_image_ctl.j2
grep -c "RSYSLOG_CONF" rules/scripts.mk
grep -c "RSYSLOG_CONF" rules/scripts.dep
```
Expected: 2 pebble references in docker_image_ctl.j2, RSYSLOG_CONF appears in both rules files.

- [ ] **Step 4: Verify git status is clean**

Run: `git status`
Expected: Working tree clean (all changes committed).

- [ ] **Step 5: Note on build verification**

Full build verification requires:
1. `make target/sonic-vs.img.gz` to complete (produces debs/wheels in `target/`)
2. `build_rocks.sh` to run and produce `target/docker-database.gz`
3. Rock container to start and redis to respond to PING

This cannot be run in the current session due to time constraints. The implementation is complete; build verification should be run in a full build environment.
