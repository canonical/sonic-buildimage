# SONiC 202605 → Ubuntu Resolute Migration Implementation Plan (English)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** In `~/sonic-buildimage-resolute`, migrate the SONiC 202605 build chain from Debian trixie to Ubuntu resolute (26.04), vs-targeted, done-bar = vs image boots in KVM + SONiC smoke passes.

**Architecture:** Add resolute as a new BLDENV (Approach A), default and only-enabled in the dedicated repo. 5 phases: slave → host OS → container base → vs containers → assemble+boot. All `rules/*.mk` source-builds kept as-is. trixie path retained as control.

**Tech Stack:** GNU Make, Jinja2 (j2), Docker, debootstrap, apt, KVM/libvirt.

## Global Constraints

- Ubuntu **must** be 26.04 / resolute. Any fallback swaps implementation within the resolute ecosystem — never reverts to pre-26.04.
- Kernel ABI suffix `+deb13-sonic` and version `6.12.41+deb13` are **unchanged** (procure prebuilt kernel).
- k8s/cri (cri-dockerd, kubelet, kubeadm, kubectl, kubernetes-cni, cri-tools) is **skipped** on resolute — backlog.
- FIPS: first-choice reuses the trixie FIPS Go binary; fallback `INCLUDE_FIPS=n` with Ubuntu official resolute golang-go + openssl.
- Docker version: if resolute lacks `docker-ce 5:28.5.2`, use the Docker Inc. version currently available on the resolute suite, **pinned to the exact version string** (no `stable` meta-package, no latest).
- Working dir: all paths relative to `~/sonic-buildimage-resolute`.
- A Chinese version of this plan exists at `*-zh.md`.

---

## File Structure

**Create:**
- `sonic-slave-resolute/Dockerfile.j2` (from `sonic-slave-trixie/Dockerfile.j2`) — slave build container
- `sonic-slave-resolute/docker.sources` — docker apt source inside slave
- `sonic-slave-resolute/pip.conf`, `sonic-jenkins-id_rsa.pub`, etc. (copied from trixie)
- `dockers/docker-base-resolute/Dockerfile.j2` (from `dockers/docker-base-bookworm/Dockerfile.j2`) — container base layer
- `rules/docker-base-resolute.mk` (from `rules/docker-base-bookworm.mk`) — base container build rule
- `rules/config.user` — repo-local build config (INCLUDE_FIPS, etc.)

**Modify:**
- `Makefile` — add `NORESOLUTE`, default catch-all → `BLDENV=resolute`, disable bookworm/trixie
- `Makefile.work:132` — add resolute branch to `SLAVE_DIR`
- `slave.mk:73` — `IMAGE_DISTRO := resolute`
- `slave.mk:78` — add `resolute` to ENABLE_PY2 filter
- `scripts/build_mirror_config.sh` — Ubuntu mirror default URLs
- `files/apt/sources.list.j2` — resolute suite/components branch
- `build_debian.sh:30-32` — docker/containerd version + kernel version
- `build_debian.sh:233` — docker apt source
- `build_debian.sh:277-279` — skip cri-dockerd
- `scripts/build_debian_base_system.sh:30,40,46,82` — debootstrap resolute + cache path
- `rules/linux-kernel.mk` — procure prebuilt (no source build)

---

### Task 1: Initialize ~/sonic-buildimage-resolute repo

**Files:**
- Create: `~/sonic-buildimage-resolute/` (whole repo)

**Interfaces:**
- Produces: a clean git worktree on branch `resolute`; all later Tasks happen here.

- [ ] **Step 1: Local reference clone**

```bash
cd ~
git clone --reference ~/sonic-buildimage -b 202605 https://github.com/sonic-net/sonic-buildimage.git ~/sonic-buildimage-resolute
cd ~/sonic-buildimage-resolute
```

Expected: clone completes fast (local object sharing).

- [ ] **Step 2: Initialize submodules**

```bash
cd ~/sonic-buildimage-resolute
make -C . 2>/dev/null; true   # confirm .gitmodules before submodule init
git submodule update --init --recursive --reference ~/sonic-buildimage 2>&1 | tail -5
```

Expected: submodules checked out (may take time; --reference reuses local objects).

- [ ] **Step 3: Create resolute branch and set git identity**

```bash
cd ~/sonic-buildimage-resolute
git config user.email "sheldon-qi@local"
git config user.name "sheldon-qi"
git checkout -b resolute
```

Expected: on branch `resolute`.

- [ ] **Step 4: Verify clean baseline**

```bash
cd ~/sonic-buildimage-resolute
git status --short | head
git log --oneline -1
```

Expected: `git status` empty (or only untracked); HEAD at 202605 latest commit.

- [ ] **Step 5: Commit (empty, just to anchor the branch)**

```bash
cd ~/sonic-buildimage-resolute
git commit --allow-empty -m "chore: start resolute migration branch"
```

---

### Task 2: Phase 0 spike a — confirm Docker resolute version string

**Files:**
- None; conclusion feeds Task 3's config.user.

**Interfaces:**
- Produces: exact `DOCKER_VERSION` / `CONTAINERD_IO_VERSION` strings for Task 7 (slave) and Task 9 (host OS).

- [ ] **Step 1: Query Docker's apt repo for available docker-ce on resolute suite**

```bash
docker run --rm ubuntu:resolute bash -c '
  apt-get update -qq &&
  apt-get install -y -qq ca-certificates curl gnupg >/dev/null &&
  install -m 0755 -d /etc/apt/keyrings &&
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg &&
  chmod a+r /etc/apt/keyrings/docker.gpg &&
  echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu resolute stable" > /etc/apt/sources.list.d/docker.list &&
  apt-get update -qq &&
  apt-cache policy docker-ce containerd.io | head -30
'
```

Expected: lists resolute-suite docker-ce candidate version.

- [ ] **Step 2: Determine version string**

If `5:28.5.2-1~ubuntu.26.04~resolute` (or Docker's resolute naming) exists → pin that.
If 5:28.5.2 absent but another docker-ce present → pin the **currently available** exact string (with epoch and `~ubuntu...~resolute` suffix).

Record, e.g.:
```
DOCKER_VERSION=5:28.5.2-1~ubuntu.26.04~resolute   # or actual
CONTAINERD_IO_VERSION=1.7.28-2~ubuntu.26.04~resolute
```

- [ ] **Step 3: If Docker has no resolute suite at all**

If `apt-cache policy` shows no resolute candidate → check whether Docker uses another suite name (noble-compat, or resolute not yet online). If still none → per R1 fallback: use Ubuntu's official `docker.io` package (`apt-cache policy docker.io`), pin its exact version. This step changes **no files** — only records the conclusion for config.user.

---

### Task 3: Phase 0 spike b — confirm prebuilt SONiC kernel .deb path

**Files:**
- None; conclusion feeds Task 10.

**Interfaces:**
- Produces: download path template for 202605 prebuilt kernel .deb on BUILD_PUBLIC_URL.

- [ ] **Step 1: Check BUILD_PUBLIC_URL default**

```bash
cd ~/sonic-buildimage-resolute
grep -nE 'BUILD_PUBLIC_URL' rules/config | head
```

Expected: `BUILD_PUBLIC_URL ?= https://packages.trafficmanager.net/public`.

- [ ] **Step 2: Probe kernel prebuilt .deb path**

```bash
BASE=https://packages.trafficmanager.net/public
for p in linux-image-6.12.41+deb13-sonic linux-headers-6.12.41+deb13-sonic linux-kbuild-6.12.41+deb13; do
  echo "== $p =="
  curl -sI "$BASE/.../$p" 2>/dev/null | head -1   # path needs confirmation against actual dir structure
done
```

Expected: find an HTTP 200 .deb path template, or confirm none exists.

- [ ] **Step 3: Determine fallback**

If a prebuilt path is found → record it; Task 10 uses procure.
If none → record "fallback: source-build linux-kernel.mk on resolute (`+resolute` ABI)"; Task 10 takes the source-build path.

---

### Task 4: Phase 0 spike c — confirm debootstrap resolute availability

**Files:**
- None; conclusion feeds Task 11.

**Interfaces:**
- Produces: whether debootstrap resolute works + keyring path.

- [ ] **Step 1: Check debootstrap for a resolute script**

```bash
ls /usr/share/debootstrap/scripts/ | grep -iE 'resolute|noble' || echo "no resolute script"
```

Expected: a `resolute` script (or symlink).

- [ ] **Step 2: Try debootstrap resolute (sandbox)**

```bash
sudo debootstrap --variant=minbase --arch=amd64 resolute /tmp/debootstrap-test-resolute http://archive.ubuntu.com/ubuntu/ 2>&1 | tail -15
```

Expected: success (or a keyring error → Step 3).

- [ ] **Step 3: If keyring missing**

```bash
sudo apt-get install -y ubuntu-keyring 2>/dev/null || \
  curl -fsSL https://archive.ubuntu.com/ubuntu/project/ubuntu-archive-keyring.gpg | sudo tee /usr/share/keyrings/ubuntu-archive-keyring.gpg
sudo rm -rf /tmp/debootstrap-test-resolute
sudo debootstrap --no-check-gpg --variant=minbase --arch=amd64 resolute /tmp/debootstrap-test-resolute http://archive.ubuntu.com/ubuntu/ 2>&1 | tail -5
```

Expected: rootfs generated; `/tmp/debootstrap-test-resolute/etc/os-release` shows Ubuntu 26.04.

- [ ] **Step 4: Clean up sandbox**

```bash
sudo rm -rf /tmp/debootstrap-test-resolute
```

---

### Task 5: Makefile — add NORESOLUTE and set as default

**Files:**
- Modify: `Makefile:7-9` (NO* flags)
- Modify: `Makefile:38-44` (BUILD_* block)
- Modify: `Makefile:65-68` (catch-all default)

**Interfaces:**
- Produces: default `make` → `BLDENV=resolute`; bookworm/trixie disabled by default.

- [ ] **Step 1: Add NORESOLUTE flag, disable bookworm/trixie**

Change:
```makefile
NOBOOKWORM ?= 0
NOTRIXIE ?= 0
```
to:
```makefile
NOBOOKWORM ?= 1
NOTRIXIE ?= 1
NORESOLUTE ?= 0
```

- [ ] **Step 2: Add BUILD_RESOLUTE flag**

After the `BUILD_TRIXIE` block add:
```makefile
ifeq ($(NORESOLUTE),0)
BUILD_RESOLUTE=1
endif
```

- [ ] **Step 3: Change catch-all default to resolute**

Change:
```makefile
ifeq ($(NOTRIXIE), 0)
	$(MAKE_WITH_RETRY) BLDENV=trixie -f Makefile.work $@
endif

	BLDENV=bookworm $(MAKE) -f Makefile.work docker-cleanup
```
to:
```makefile
ifeq ($(NORESOLUTE), 0)
	$(MAKE_WITH_RETRY) BLDENV=resolute -f Makefile.work $@
endif

	BLDENV=resolute $(MAKE) -f Makefile.work docker-cleanup
```

- [ ] **Step 4: Add resolute to bottom dispatch block (if BUILD_TRIXIE dispatch exists)**

Locate the `$(if $(BUILD_TRIXIE),BLDENV=trixie ...)` line, add after:
```makefile
	$(if $(BUILD_RESOLUTE),BLDENV=resolute $(MAKE) -f Makefile.work $@,)
```

- [ ] **Step 5: Verify make parses**

```bash
cd ~/sonic-buildimage-resolute
make -n sonic-slave-build 2>&1 | grep -iE 'BLDENV=resolute|BLDENV=trixie' | head
```
Expected: `BLDENV=resolute` appears; no trixie default dispatch.

- [ ] **Step 6: Commit**

```bash
git add Makefile
git commit -m "build: add NORESOLUTE, default BLDENV to resolute"
```

---

### Task 6: Makefile.work + slave.mk — SLAVE_DIR and IMAGE_DISTRO

**Files:**
- Modify: `Makefile.work:132` (SLAVE_DIR branch)
- Modify: `slave.mk:73` (IMAGE_DISTRO)
- Modify: `slave.mk:78` (ENABLE_PY2 filter)

**Interfaces:**
- Produces: `BLDENV=resolute` → `SLAVE_DIR=sonic-slave-resolute`; `IMAGE_DISTRO=resolute`.

- [ ] **Step 1: Add resolute branch to SLAVE_DIR**

In `Makefile.work`, before:
```makefile
ifeq ($(BLDENV), trixie)
SLAVE_DIR = sonic-slave-trixie
```
insert:
```makefile
ifeq ($(BLDENV), resolute)
SLAVE_DIR = sonic-slave-resolute
else ifeq ($(BLDENV), trixie)
SLAVE_DIR = sonic-slave-trixie
```

- [ ] **Step 2: Change IMAGE_DISTRO to resolute**

Change `slave.mk:73`:
```makefile
IMAGE_DISTRO := trixie
```
to:
```makefile
IMAGE_DISTRO := resolute
```

- [ ] **Step 3: Add resolute to ENABLE_PY2 filter**

Change `slave.mk:78`:
```makefile
ifneq ($(filter bullseye bookworm trixie,$(BLDENV)),)
```
to:
```makefile
ifneq ($(filter bullseye bookworm trixie resolute,$(BLDENV)),)
```

- [ ] **Step 4: Verify**

```bash
cd ~/sonic-buildimage-resolute
grep -n 'resolute' Makefile.work slave.mk | head
```
Expected: resolute branch/assignment present.

- [ ] **Step 5: Commit**

```bash
git add Makefile.work slave.mk
git commit -m "build: map BLDENV=resolute to sonic-slave-resolute, IMAGE_DISTRO=resolute"
```

---

### Task 7: Create sonic-slave-resolute/ (FROM ubuntu:resolute + docker source)

**Files:**
- Create: `sonic-slave-resolute/Dockerfile.j2` (from `sonic-slave-trixie/Dockerfile.j2`)
- Create: `sonic-slave-resolute/docker.sources` (from `sonic-slave-trixie/docker.sources`)
- Copy: `sonic-slave-resolute/pip.conf`, `sonic-jenkins-id_rsa.pub`, etc.

**Interfaces:**
- Consumes: DOCKER_VERSION string from Task 2.
- Produces: `sonic-slave-resolute/Dockerfile.j2` with `FROM ubuntu:resolute`.

- [ ] **Step 1: Copy trixie slave dir to resolute**

```bash
cd ~/sonic-buildimage-resolute
cp -a sonic-slave-trixie sonic-slave-resolute
ls sonic-slave-resolute/
```

- [ ] **Step 2: Dockerfile.j2 base image to ubuntu:resolute**

In `sonic-slave-resolute/Dockerfile.j2`, change all `debian:trixie` to `ubuntu:resolute`:
```bash
sed -i 's|debian:trixie|ubuntu:resolute|g' sonic-slave-resolute/Dockerfile.j2
grep -n 'FROM' sonic-slave-resolute/Dockerfile.j2 | head
```
Expected: `FROM {{ prefix }}ubuntu:resolute`.

- [ ] **Step 3: docker.sources to ubuntu**

In `sonic-slave-resolute/docker.sources`, change `https://download.docker.com/linux/debian` to `https://download.docker.com/linux/ubuntu`:
```bash
sed -i 's|download.docker.com/linux/debian|download.docker.com/linux/ubuntu|' sonic-slave-resolute/docker.sources
cat sonic-slave-resolute/docker.sources
```

- [ ] **Step 4: Pin docker version string (use Task 2 conclusion)**

Edit `sonic-slave-resolute/Dockerfile.j2` around line 674, replace:
```
docker-ce=5:28.5.2-1~debian.13~trixie docker-ce-cli=5:28.5.2-1~debian.13~trixie containerd.io=1.7.28-2~debian.13~trixie docker-buildx-plugin=0.26.1-1~debian.13~trixie docker-compose-plugin=2.39.1-1~debian.13~trixie
```
with the resolute strings from Task 2 (fill actual):
```
docker-ce=<DOCKER_VERSION> docker-ce-cli=<DOCKER_VERSION> containerd.io=<CONTAINERD_IO_VERSION> docker-buildx-plugin=<actual-resolute-version> docker-compose-plugin=<actual-resolute-version>
```

- [ ] **Step 5: FIPS Go fetch path stays trixie (unchanged)**

Confirm `BUILD_PUBLIC_URL }}/fips/trixie/` in `sonic-slave-resolute/Dockerfile.j2` is **unchanged**:
```bash
grep -n 'fips/trixie' sonic-slave-resolute/Dockerfile.j2
```
Expected: path still present (reuse trixie FIPS binary, per FIPS design).

- [ ] **Step 6: Commit**

```bash
git add sonic-slave-resolute
git commit -m "build: add sonic-slave-resolute (FROM ubuntu:resolute, ubuntu docker repo)"
```

---

### Task 8: apt source generator + sources.list.j2 — Ubuntu mirror/components

**Files:**
- Modify: `scripts/build_mirror_config.sh` (default mirror URLs)
- Modify: `files/apt/sources.list.j2` (resolute branch)

**Interfaces:**
- Produces: `build_mirror_config.sh` generates Ubuntu sources.list for resolute; `sources.list.j2` supports resolute components.

- [ ] **Step 1: build_mirror_config.sh default mirror to Ubuntu (resolute)**

In `scripts/build_mirror_config.sh`, after the default URL block:
```bash
DEFAULT_MIRROR_URLS=http://debian-archive.trafficmanager.net/debian/
DEFAULT_MIRROR_SECURITY_URLS=http://debian-archive.trafficmanager.net/debian-security/
```
add:
```bash
if [ "$DISTRIBUTION" == "resolute" ]; then
    DEFAULT_MIRROR_URLS=http://archive.ubuntu.com/ubuntu/
    DEFAULT_MIRROR_SECURITY_URLS=http://security.ubuntu.com/ubuntu/
fi
```
(armhf/arm64 use `ports.ubuntu.com` — add a resolute+arm branch mirroring the existing armhf logic.)

- [ ] **Step 2: sources.list.j2 add resolute components branch**

Change the opening of `files/apt/sources.list.j2`:
```jinja
{% if DISTRIBUTION == 'bookworm' or DISTRIBUTION == 'trixie' -%}
{%- set nonfree_component='non-free-firmware' -%}
{%- else -%}
{%- set nonfree_component='non-free' -%}
{%- endif %}
```
to:
```jinja
{% if DISTRIBUTION == 'resolute' -%}
{%- set components='main universe multiverse restricted' -%}
{%- set nonfree_component='' -%}
{%- elif DISTRIBUTION == 'bookworm' or DISTRIBUTION == 'trixie' -%}
{%- set components='main contrib non-free-firmware' -%}
{%- set nonfree_component='non-free-firmware' -%}
{%- else -%}
{%- set components='main contrib non-free' -%}
{%- set nonfree_component='non-free' -%}
{%- endif %}
```
and replace `main contrib {{ nonfree_component }}` in the template body with `{{ components }}`. Security suite uses `resolute-security` (covered by the generic `-security` branch — confirm resolute hits the else branch using `{{ DISTRIBUTION }}-security`).

- [ ] **Step 3: Commit**

```bash
git add scripts/build_mirror_config.sh files/apt/sources.list.j2
git commit -m "build: apt source generator + template support Ubuntu resolute"
```

---

### Task 9: build_debian.sh — docker version + apt source + kernel version

**Files:**
- Modify: `build_debian.sh:30-32` (version strings)
- Modify: `build_debian.sh:233` (docker apt source)

**Interfaces:**
- Consumes: DOCKER_VERSION from Task 2; kernel procure conclusion from Task 3.
- Produces: host OS uses resolute docker version + ubuntu docker source; kernel version unchanged.

- [ ] **Step 1: docker/containerd version to resolute**

Change `build_debian.sh:30-31`:
```bash
DOCKER_VERSION=5:28.5.2-1~debian.13~$IMAGE_DISTRO
CONTAINERD_IO_VERSION=1.7.28-2~debian.13~$IMAGE_DISTRO
```
to (use Task 2 actual strings, replace `~debian.13~` with `~ubuntu.26.04~`):
```bash
DOCKER_VERSION=5:28.5.2-1~ubuntu.26.04~$IMAGE_DISTRO
CONTAINERD_IO_VERSION=1.7.28-2~ubuntu.26.04~$IMAGE_DISTRO
```

- [ ] **Step 2: Kernel version line unchanged (confirm)**

`build_debian.sh:32` `LINUX_KERNEL_VERSION=6.12.41+deb13` **stays unchanged**:
```bash
grep -n 'LINUX_KERNEL_VERSION=' build_debian.sh
```
Expected: `6.12.41+deb13` (prebuilt procure, ABI unchanged).

- [ ] **Step 3: docker apt source to ubuntu**

Change `build_debian.sh:233`:
```bash
deb [arch=$CONFIGURED_ARCH] https://download.docker.com/linux/debian $IMAGE_DISTRO stable
```
to:
```bash
deb [arch=$CONFIGURED_ARCH] https://download.docker.com/linux/ubuntu $IMAGE_DISTRO stable
```

- [ ] **Step 4: Commit**

```bash
git add build_debian.sh
git commit -m "build: host OS docker version + apt repo on ubuntu resolute"
```

---

### Task 10: Kernel — procure prebuilt (Task 3 path) or fallback source-build

**Files:**
- Modify: `rules/linux-kernel.mk` (per Task 3: procure or source-build)

**Interfaces:**
- Consumes: kernel path conclusion from Task 3.
- Produces: kernel .deb via procure (no source build), or source-build on resolute.

- [ ] **Step 1: Branch on Task 3 conclusion**

**If Task 3 found a prebuilt path** → at the top of `rules/linux-kernel.mk`, switch the source build to download of ready .debs (follow the existing `$(BUILD_PUBLIC_URL)` download pattern used in other rules, e.g. `wget` + `dpkg -i`). Specifically, change `$(LINUX_KERNEL)_SRC_PATH = $(SRC_PATH)/sonic-linux-kernel` source-build to a procure target downloading `linux-image-6.12.41+deb13-sonic_*_amd64.deb`, etc.

**If Task 3 found no prebuilt** → keep source-build, but confirm it builds on the resolute slave (`KERNEL_ABISUFFIX=+deb13` unchanged, or `+resolute` if preferred). This plan defaults to procure; fallback per spec R2.

- [ ] **Step 2: Verify kernel .deb obtainable**

```bash
cd ~/sonic-buildimage-resolute
make -n linux-kernel 2>&1 | grep -iE 'wget|dpkg|buildpackage' | head
```
Expected: procure path shows wget/dpkg, or source path shows buildpackage.

- [ ] **Step 3: Commit**

```bash
git add rules/linux-kernel.mk
git commit -m "build: procure prebuilt SONiC kernel .deb for resolute (ABI +deb13-sonic unchanged)"
```

---

### Task 11: build_debian_base_system.sh — debootstrap resolute + cache path

**Files:**
- Modify: `scripts/build_debian_base_system.sh:30` (mirror URL)
- Modify: `scripts/build_debian_base_system.sh:82` (apt-list cache path)

**Interfaces:**
- Consumes: debootstrap/keyring conclusion from Task 4.
- Produces: rootfs debootstrap resolute from Ubuntu mirror.

- [ ] **Step 1: mirror URL to Ubuntu**

Change `scripts/build_debian_base_system.sh:30`:
```bash
MIRROR_URL=http://deb.debian.org/debian
```
to (for resolute):
```bash
MIRROR_URL=http://archive.ubuntu.com/ubuntu
```

- [ ] **Step 2: apt-list cache path to Ubuntu**

Change `scripts/build_debian_base_system.sh:82`:
```bash
APTDEBIAN="$APTLIST/deb.debian.org_debian_dists_${DISTRO}_main_binary-${CONFIGURED_ARCH}_Packages"
```
to:
```bash
APTDEBIAN="$APTLIST/archive.ubuntu.com_ubuntu_dists_${DISTRO}_main_binary-${CONFIGURED_ARCH}_Packages"
```

- [ ] **Step 3: If Task 4 needs keyring, add debootstrap keyring/gpg args**

If Task 4 Step 3 required `--no-check-gpg` or a keyring, at the debootstrap call in `scripts/build_debian_base_system.sh` add:
```bash
--no-check-gpg   # or --keyring=/usr/share/keyrings/ubuntu-archive-keyring.gpg
```
(only if Task 4 confirmed it's needed).

- [ ] **Step 4: Commit**

```bash
git add scripts/build_debian_base_system.sh
git commit -m "build: debootstrap resolute from Ubuntu mirror, fix apt-list cache path"
```

---

### Task 12: build_debian.sh — skip k8s/cri

**Files:**
- Modify: `build_debian.sh:242-280` (k8s/cri install block)

**Interfaces:**
- Produces: vs build skips cri-dockerd/kubelet/kubeadm/kubectl/kubernetes-cni/cri-tools.

- [ ] **Step 1: Locate k8s/cri block**

```bash
cd ~/sonic-buildimage-resolute
sed -n '240,285p' build_debian.sh
```
Confirm the range of cri-dockerd, kubelet, etc. install blocks.

- [ ] **Step 2: Guard k8s/cri to skip on resolute**

Wrap the k8s/cri install block in a condition (preserve logic for backlog restore):
```bash
if [ "$IMAGE_DISTRO" != "resolute" ]; then
    # ... original cri-dockerd / kubelet / kubeadm / kubectl / kubernetes-cni / cri-tools install ...
fi
```
Confirm the `cri-dockerd_...debian-${IMAGE_DISTRO}_amd64.deb` line (`build_debian.sh:278`) is inside the guard.

- [ ] **Step 3: Verify guard**

```bash
grep -n 'IMAGE_DISTRO.*resolute' build_debian.sh | head
```
Expected: k8s/cri block wrapped by `!= resolute`.

- [ ] **Step 4: Commit**

```bash
git add build_debian.sh
git commit -m "build: skip k8s/cri on resolute (vs stage), backlog"
```

---

### Task 13: rules/config.user — FIPS and build config

**Files:**
- Create: `rules/config.user`

**Interfaces:**
- Produces: local build config (INCLUDE_FIPS, PLATFORM=vs, etc.).

- [ ] **Step 1: Write config.user**

```bash
cat > rules/config.user <<'EOF'
# resolute migration local config
INCLUDE_FIPS ?= y
PLATFORM ?= vs
EOF
```

- [ ] **Step 2: If Task 7/Phase 1 FIPS binary install fails, switch fallback**

(This step runs during Phase 1 only if FIPS Go won't install):
```bash
sed -i 's/INCLUDE_FIPS ?= y/INCLUDE_FIPS ?= n/' rules/config.user
```

- [ ] **Step 3: Commit**

```bash
git add rules/config.user
git commit -m "build: local config.user for resolute vs (FIPS=y default, fallback n)"
```

---

### Task 14: Phase 1 verify — sonic-slave-resolute build

**Files:**
- None; execute build verification.

**Interfaces:**
- Consumes: Tasks 5–8, 13.
- Produces: Phase 1 exit conclusion (slave image works + FIPS decision).

- [ ] **Step 1: Build sonic-slave-resolute**

```bash
cd ~/sonic-buildimage-resolute
make sonic-slave-build BLDENV=resolute 2>&1 | tee /tmp/slave-build-resolute.log | tail -30
```
Expected: build succeeds, produces sonic-slave-resolute image. If FIPS Go install fails (glibc/ABI conflict) → apply Task 13 Step 2 fallback (`INCLUDE_FIPS=n`) and retry.

- [ ] **Step 2: Verify image OS**

```bash
docker run --rm sonic-slave-resolute bash -c "cat /etc/os-release | head -3"
```
Expected: `Ubuntu 26.04...` / `resolute`.

- [ ] **Step 3: Verify representative source-build inside slave**

```bash
cd ~/sonic-buildimage-resolute
make -C target/linux/libswsscommon BLDENV=resolute 2>&1 | tail -10 || \
  make libswsscommon BLDENV=resolute 2>&1 | tail -10
```
Expected: libswsscommon .deb produced (or the equivalent make target succeeds).

- [ ] **Step 4: Record FIPS conclusion**

Confirm which FIPS path is active (on reuse-trixie-binary / fallback off), record:
```bash
echo "FIPS status: <on/off> on $(date)" >> docs/superpowers/plans/fips-status.txt
```

- [ ] **Step 5: Commit (if config.user changed for fallback)**

```bash
git add rules/config.user docs/superpowers/plans/fips-status.txt 2>/dev/null
git commit -m "build: phase 1 verified, FIPS status recorded" || echo "nothing to commit"
```

---

### Task 15: Phase 2 verify — vs host OS image

**Files:**
- None; execute build verification.

**Interfaces:**
- Consumes: Tasks 9–13.
- Produces: Phase 2 exit conclusion (vs image file + rootfs resolute).

- [ ] **Step 1: Build vs image**

```bash
cd ~/sonic-buildimage-resolute
make PLATFORM=vs BLDENV=resolute one-image 2>&1 | tee /tmp/vs-image-resolute.log | tail -30
```
Expected: produces a vs image file (e.g. `target/sonic-vs.bin`). If kernel procure fails → apply Task 10 fallback (source-build).

- [ ] **Step 2: Verify rootfs is resolute**

```bash
mkdir -p /tmp/vs-rootfs-check
# example: if squashfs, unsquashfs then inspect
sudo unsquashfs -d /tmp/vs-rootfs-check/rootfs target/sonic-vs.squashfs 2>/dev/null && \
  cat /tmp/vs-rootfs-check/rootfs/etc/os-release | head -3
```
Expected: `Ubuntu 26.04`.

- [ ] **Step 3: Verify docker/kernel/apt source config**

```bash
cat /tmp/vs-rootfs-check/rootfs/etc/apt/sources.list | head
ls /tmp/vs-rootfs-check/rootfs/boot/vmlinuz-* 2>/dev/null
```
Expected: apt sources point to archive.ubuntu.com; kernel `vmlinuz-6.12.41+deb13-sonic-*`.

- [ ] **Step 4: Clean up**

```bash
sudo rm -rf /tmp/vs-rootfs-check
```

---

### Task 16: Phase 3 — docker-base-resolute container base image

**Files:**
- Create: `dockers/docker-base-resolute/Dockerfile.j2` (from `dockers/docker-base-bookworm/Dockerfile.j2`)
- Create: `rules/docker-base-resolute.mk` (from `rules/docker-base-bookworm.mk`)

**Interfaces:**
- Produces: `docker-base-resolute.gz` with `FROM ubuntu:resolute`.

- [ ] **Step 1: Copy bookworm base to resolute**

```bash
cd ~/sonic-buildimage-resolute
cp -a dockers/docker-base-bookworm dockers/docker-base-resolute
cp rules/docker-base-bookworm.mk rules/docker-base-resolute.mk
```

- [ ] **Step 2: Dockerfile.j2 base to ubuntu:resolute**

In `dockers/docker-base-resolute/Dockerfile.j2` change `debian:bookworm` to `ubuntu:resolute`:
```bash
sed -i 's|debian:bookworm|ubuntu:resolute|g' dockers/docker-base-resolute/Dockerfile.j2
grep -n 'ARG BASE' dockers/docker-base-resolute/Dockerfile.j2 | head
```

- [ ] **Step 3: docker-base-resolute.mk rename symbols**

In `rules/docker-base-resolute.mk` replace `BOOKWORM`/`bookworm` with `RESOLUTE`/`resolute`, and `SONIC_BOOKWORM_DOCKERS` → `SONIC_RESOLUTE_DOCKERS`:
```bash
sed -i 's/BOOKWORM/RESOLUTE/g; s/bookworm/resolute/g' rules/docker-base-resolute.mk
grep -n 'RESOLUTE\|resolute' rules/docker-base-resolute.mk | head
```

- [ ] **Step 4: Build base image**

```bash
make docker-base-resolute BLDENV=resolute 2>&1 | tail -15
```
Expected: produces `docker-base-resolute.gz`.

- [ ] **Step 5: Verify**

```bash
docker run --rm $(docker load -i target/docker-base-resolute.gz 2>&1 | sed 's/.*: //') bash -c "cat /etc/os-release | head -2"
```
Expected: `Ubuntu 26.04`.

- [ ] **Step 6: Commit**

```bash
git add dockers/docker-base-resolute rules/docker-base-resolute.mk
git commit -m "build: add docker-base-resolute (FROM ubuntu:resolute)"
```

---

### Task 17: Phase 4 — vs container service images switch to resolute base

**Files:**
- Modify: vs-related `dockers/docker-sonic-vs/Dockerfile.j2`, `dockers/docker-syncd-vs/Dockerfile.j2`, `dockers/docker-gbsyncd-vs/Dockerfile.j2`, etc.
- Modify: corresponding `rules/*-vs.mk` to wire `SONIC_RESOLUTE_DOCKERS`

**Interfaces:**
- Consumes: docker-base-resolute from Task 16.
- Produces: vs container images based on docker-base-resolute.

- [ ] **Step 1: List vs-related containers**

```bash
cd ~/sonic-buildimage-resolute
ls platform/vs/*.mk
grep -rlE 'docker-base-bookworm|DOCKER_BASE_BOOKWORM' platform/vs dockers 2>/dev/null | head
```

- [ ] **Step 2: Switch each vs Dockerfile.j2 base to resolute**

For each vs container Dockerfile.j2, change `FROM ...docker-base-bookworm` / `ARG BASE=...bookworm` to `docker-base-resolute`:
```bash
sed -i 's|docker-base-bookworm|docker-base-resolute|g; s|debian:bookworm|ubuntu:resolute|g' \
  dockers/docker-sonic-vs/Dockerfile.j2 \
  platform/vs/docker-syncd-vs/Dockerfile.j2 \
  platform/vs/docker-gbsyncd-vs/Dockerfile.j2 2>/dev/null
```
(Confirm actual FROM/ARG wording per file; adjust as needed.)

- [ ] **Step 3: Wire rules into SONIC_RESOLUTE_DOCKERS**

In vs-related `rules/*.mk` / `platform/vs/*.mk`, change `SONIC_BOOKWORM_DOCKERS +=` to `SONIC_RESOLUTE_DOCKERS +=`, or add a resolute branch:
```bash
grep -rl 'SONIC_BOOKWORM_DOCKERS' platform/vs rules | xargs sed -i 's/SONIC_BOOKWORM_DOCKERS/SONIC_RESOLUTE_DOCKERS/g'
```

- [ ] **Step 4: Build vs container images**

```bash
make docker-sonic-vs BLDENV=resolute 2>&1 | tail -15
make docker-syncd-vs BLDENV=resolute 2>&1 | tail -15
```
Expected: each vs container image builds.

- [ ] **Step 5: Commit**

```bash
git add dockers platform/vs rules
git commit -m "build: vs containers switch to docker-base-resolute"
```

---

### Task 18: Phase 5 — vs image assembly + KVM boot + smoke (done-bar)

**Files:**
- None; execute final verification.

**Interfaces:**
- Consumes: Tasks 14–17.
- Produces: done-bar conclusion (vs boots + smoke passes).

- [ ] **Step 1: Assemble vs image**

```bash
cd ~/sonic-buildimage-resolute
make PLATFORM=vs BLDENV=resolute 2>&1 | tee /tmp/vs-final-resolute.log | tail -30
```
Expected: produces a bootable vs image (`.bin` / `.img`).

- [ ] **Step 2: Boot vs in KVM**

Following `platform/vs/README.vsvm.md`, boot the vs image with libvirt/kvm:
```bash
sudo virsh create platform/vs/sonic.xml 2>/dev/null || \
  echo "Follow README.vsvm.md to start the vs VM"
```
Expected: VM boots to the SONiC login prompt.

- [ ] **Step 3: SONiC smoke**

Log in to the vs VM and run:
```bash
config load_minigraph -y
show version
show ip intf
docker ps
```
Expected: `config load_minigraph` succeeds; `show version` output normal (distro reflects resolute); `show ip intf` normal; syncd/swss/bgpp containers healthy (Up) via `docker ps`.

- [ ] **Step 4: trixie-vs control**

Build and boot trixie-vs on the `BLDENV=trixie` path, repeat Step 3, compare output consistency:
```bash
make PLATFORM=vs BLDENV=trixie ...   # control build
```
Expected: resolute-vs and trixie-vs smoke behavior consistent.

- [ ] **Step 5: Record conclusion**

```bash
echo "vs done-bar (KVM boot + smoke): PASS on resolute, $(date)" >> docs/superpowers/plans/done-bar-status.txt
git add docs/superpowers/plans/done-bar-status.txt
git commit -m "test: vs resolute boot+smoke done-bar passed"
```

---

### Task 19: Goal-2 research deliverable (parallel track, non-blocking)

**Files:**
- Create: `docs/superpowers/specs/category-c-catalog-zh.md`
- Create: `docs/superpowers/specs/category-c-catalog-en.md`

**Interfaces:**
- Produces: Category-C package verdict table (no source-build changes).

- [ ] **Step 1: Generate catalog template**

For each Category-C package (bash, iproute2, libnl3, libyang3, thrift, lldpd, openssh, monit, lm-sensors, ifupdown2, initramfs-tools, grub2, kdump-tools, redis, swig), check `rules/<pkg>.mk` patch reason + `src/<pkg>/patch/` + resolute apt version:

```bash
cd ~/sonic-buildimage-resolute
for pkg in bash iproute2 libnl3 libyang3 thrift lldpd openssh monit lm-sensors ifupdown2 initramfs-tools grub2 kdump-tools redis swig; do
  echo "=== $pkg ==="
  ls rules/$pkg.mk src/$pkg/patch/ 2>/dev/null | head
done
docker run --rm ubuntu:resolute bash -c "apt-cache policy $pkg 2>/dev/null | head -3" < /dev/null
```

- [ ] **Step 2: Fill verdict table (zh+en)**

One row per package: name | current patch reason | resolute apt version | verdict (safe-to-swap / needs-patch-port / keep-source-build). Write to `docs/superpowers/specs/category-c-catalog-zh.md` and `-en.md`.

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/specs/category-c-catalog-*.md
git commit -m "docs: Goal-2 Category-C package swap catalog (zh+en)"
```
