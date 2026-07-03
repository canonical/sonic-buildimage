# SONiC 202605 → Ubuntu Resolute Migration Design (English)

- **Date:** 2026-07-03
- **Repo:** new `~/sonic-buildimage-resolute` (based on upstream `202605`)
- **Target platform:** `vs` (virtual switch, software SAI, no vendor SDK binaries)
- **Constraint:** Ubuntu **must** be 26.04 / resolute — no fallback to an earlier release. Any fallback swaps implementation *within* the resolute ecosystem, never reverts to pre-26.04.

## 1. Goals

1. **Source-swap primary (Goal 1):** Switch the SONiC build chain from Debian trixie to Ubuntu resolute using Ubuntu's same-named packages. All `rules/*.mk` source-builds kept as-is.
2. **Non-apt-package research (Goal 2):** Deliverable = research catalog of Category-C packages (bash, iproute2, libnl3, libyang3, thrift, lldpd, openssh, monit, lm-sensors, ifupdown2, initramfs-tools, grub2, kdump-tools, redis, swig, …) with per-package verdict (safe-to-swap / needs-patch-port / keep-source-build). **No source-builds changed in this migration.**
3. **Order: host before containers** — sequenced into 5 phases: slave → host OS → container base → vs containers → assemble+boot.
4. **vs first:** done-bar = vs image boots in KVM + SONiC smoke passes.

## 2. Approach

**Approach A — add resolute as a new BLDENV**, set as **default and only enabled BLDENV** in the dedicated repo (disable bookworm/trixie).

Rationale: mirrors how SONiC itself added trixie; diffable and reversible; trixie path retained as control; matches "almost just a source swap". Rejected: Approach B (minimal overlay, semantically muddy, leaves hardcoded `~debian.13~trixie` strings) and Approach C (distro-family abstraction, over-engineered for a vs experiment).

## 3. Source-swap pivot table

| # | File | Debian (trixie) | resolute |
|---|------|-----------------|----------|
| **Build-system wiring** | | | |
| 1 | [Makefile](Makefile) | `NOTRIXIE?=0`, catch-all → `BLDENV=trixie` | add `NORESOLUTE?=0`; default catch-all → `BLDENV=resolute`; set `NOBOOKWORM=1 NOTRIXIE=1` |
| 2 | [Makefile.work:132](Makefile.work#L132) | `ifeq($(BLDENV),trixie) SLAVE_DIR=sonic-slave-trixie` | add `else ifeq($(BLDENV),resolute) SLAVE_DIR=sonic-slave-resolute` |
| 3 | [slave.mk:73](slave.mk#L73) | `IMAGE_DISTRO := trixie` | `IMAGE_DISTRO := resolute` |
| 4 | [slave.mk](slave.mk) ENABLE_PY2 filter | `bullseye bookworm trixie` | add `resolute` |
| **apt source generator (shared by slave + host OS)** | | | |
| 5 | [build_mirror_config.sh](scripts/build_mirror_config.sh) | `...debian-archive.../debian/` | Ubuntu mirrors: `archive.ubuntu.com/ubuntu/` (amd64), `ports.ubuntu.com/` (arm) |
| 6 | [files/apt/sources.list.j2](files/apt/sources.list.j2) | suites `trixie`/`-updates`/`-security`; components `main contrib non-free-firmware` | suites `resolute`/`-updates`/`-security`; components `main universe multiverse restricted`; security via `archive.ubuntu.com`; trim `deb-src` where needed |
| **Slave container** | | | |
| 7 | [sonic-slave-trixie/Dockerfile.j2](sonic-slave-trixie/Dockerfile.j2) → new `sonic-slave-resolute/` | `FROM debian:trixie` | `FROM ubuntu:resolute` |
| 8 | sonic-slave `docker.sources` | `download.docker.com/linux/debian` | `download.docker.com/linux/ubuntu` |
| 9 | sonic-slave pinned docker | `docker-ce=5:28.5.2-1~debian.13~trixie` | resolute suite (per Phase 0 spike a) |
| **Host OS image** | | | |
| 10 | [build_debian.sh:30-31](build_debian.sh#L30) | `~debian.13~$IMAGE_DISTRO` | `~ubuntu.26.04~$IMAGE_DISTRO` (per spike a) |
| 11 | [build_debian.sh:32](build_debian.sh#L32) + [linux-kernel.mk:4](rules/linux-kernel.mk#L4) | `LINUX_KERNEL_VERSION=6.12.41+deb13`, `KERNEL_ABISUFFIX=+deb13` | **unchanged** (procure prebuilt kernel, keep `+deb13-sonic` ABI) |
| 12 | [build_debian.sh:233](build_debian.sh#L233) | `download.docker.com/linux/debian $IMAGE_DISTRO stable` | `download.docker.com/linux/ubuntu resolute stable` |
| 13 | [build_debian_base_system.sh:30,40,46](scripts/build_debian_base_system.sh#L30) | `debootstrap ... $IMAGE_DISTRO ... http://deb.debian.org/debian` | debootstrap `resolute` from Ubuntu mirror (needs Ubuntu keyring + resolute script) |
| 14 | [build_debian.sh:278](build_debian.sh#L278) | `cri-dockerd_...debian-${IMAGE_DISTRO}_amd64.deb` | **skip** (k8s/cri backlog) |
| 15 | [build_debian_base_system.sh:82](scripts/build_debian_base_system.sh#L82) | `deb.debian.org_debian_dists_...` cache path | Ubuntu mirror path `archive.ubuntu.com_ubuntu_dists_...` |
| **Container base image** | | | |
| 16 | [dockers/docker-base-bookworm/Dockerfile.j2](dockers/docker-base-bookworm/Dockerfile.j2) → new `docker-base-resolute/` | `ARG BASE=...debian:bookworm` | `...ubuntu:resolute` |
| 17 | new `rules/docker-base-resolute.mk` | `SONIC_TRIXIE_DOCKERS` | `SONIC_RESOLUTE_DOCKERS` |

## 4. Phasing (5 phases, each a hard gate)

### Phase 0 — repo init & resolute BLDENV wiring (no build)
- `git clone --reference ~/sonic-buildimage` (branch `202605`) → `~/sonic-buildimage-resolute`; init submodules; branch `resolute`.
- Add `BLDENV=resolute` plumbing: [Makefile](Makefile), [Makefile.work](Makefile.work) `SLAVE_DIR` branch, [slave.mk:73](slave.mk#L73), ENABLE_PY2 filter.
- Day-0 spikes (parallel, non-blocking):
  - (a) Confirm Docker publishes a resolute `docker-ce 5:28.5.2` build + exact version string. **If Docker has not published that version for resolute: use the Docker Inc. docker-ce version currently available on the resolute suite, but pin the exact version string** (no `stable` meta-package, no latest). containerd pinned likewise.
  - (b) Confirm `BUILD_PUBLIC_URL` hosts prebuilt SONiC kernel .debs for 202605 + path.
  - (c) debootstrap resolute availability + Ubuntu keyring.
- **Exit:** `make` parses, `BLDENV=resolute` selected, no source fetched.

### Phase 1 — sonic-slave-resolute (build container, the "host" layer)
- New `sonic-slave-resolute/` (from `sonic-slave-trixie/`): `FROM ubuntu:resolute`, Ubuntu apt sources, `docker.sources` → `download.docker.com/linux/ubuntu`, pinned docker per spike a.
- Resolve apt-name deltas: trixie→resolute renamed/removed packages (`libgoogle-perftools4t64`, `librrd8t64`, `libcurl4t64`, `python3.13`→resolute python, `libthrift-0.19.0t64`, `libgrpc++1`, …) mapped per-package.
- **FIPS:** first-choice = pull trixie FIPS Go as-is from `BUILD_PUBLIC_URL/fips/trixie/` into resolute slave; **fallback (on glibc/ABI conflict) = `INCLUDE_FIPS=n`, use Ubuntu official resolute golang-go + openssl** (still resolute, marked tech debt).
- **Exit:** `make sonic-slave-build BLDENV=resolute` produces sonic-slave-resolute image; `docker run` shows `/etc/os-release` = Ubuntu 26.04; a representative source-build (e.g. libswsscommon) succeeds; FIPS decision set (on / fallback-off).

### Phase 2 — SONiC host OS image (build_debian.sh)
- [build_debian.sh:30-31](build_debian.sh#L30) docker/containerd version `~ubuntu.26.04~resolute` (spike a).
- [build_debian.sh:233](build_debian.sh#L233) docker apt repo → `linux/ubuntu resolute`.
- **Kernel: procure prebuilt SONiC kernel .debs** (spike b), keep `6.12.41+deb13-sonic` ABI unchanged; do not source-build [rules/linux-kernel.mk](rules/linux-kernel.mk). Fallback = source-build on resolute with resolute toolchain (`+resolute` ABI).
- [build_debian_base_system.sh](scripts/build_debian_base_system.sh) debootstrap `resolute` from Ubuntu mirror.
- **Skip k8s/cri** (cri-dockerd/kubelet/kubeadm/kubectl/kubernetes-cni/cri-tools conditionally skipped) → backlog.
- apt source generator reuses Phase 1's Ubuntu mirror + sources.list.j2.
- **Exit:** `make ... one-image PLATFORM=vs BLDENV=resolute` produces a vs image file; rootfs `/etc/os-release` = Ubuntu 26.04.

### Phase 3 — container base image
- New `dockers/docker-base-resolute/Dockerfile.j2` (`FROM ubuntu:resolute`), `rules/docker-base-resolute.mk`, `SONIC_RESOLUTE_DOCKERS`.
- **Exit:** `docker-base-resolute.gz` builds; `docker run` shows `/etc/os-release` = Ubuntu 26.04; base layer apt sources/components correct.

### Phase 4 — vs container service images
- Switch vs-relevant container Dockerfile.j2 bases to `docker-base-resolute`: docker-sonic-vs, docker-syncd-vs, docker-gbsyncd-vs, docker-router-advertiser, docker-dhcp-relay, docker-config-engine-resolute, etc.
- Wire each `rules/*-vs.mk` / `docker-*-resolute.mk` into `SONIC_RESOLUTE_DOCKERS`.
- **Exit:** all vs-relevant container images build; `docker run` each container starts.

### Phase 5 — vs image assembly + KVM boot + smoke (done-bar)
- `make ... one-image PLATFORM=vs BLDENV=resolute` produces vs image.
- KVM boot + SONiC smoke: `config load_minigraph -y`, `show version`, `show ip intf`, syncd/swss/bgpp containers healthy via `docker ps`.
- trixie-vs as control, behavior consistent.

## 5. Goal-2 research deliverable (parallel track, does not block Phases 0–5)

- Artifact: `docs/.../category-c-catalog-zh.md` + `-en.md`.
- One row per package: name, current patch reason, resolute apt version, verdict (safe-to-swap / needs-patch-port / keep-source-build).
- No source-builds changed.
- Findings from background recon (Categories A/B/D/E non-substitutable; Category C is the realistic migration target; grpc/protobuf `ifeq($(BLDENV),bookworm)` guard is SONiC's existing "drop source-build when distro catches up" template).

## 6. FIPS

- `INCLUDE_FIPS` stays `=y`.
- sonic-slave-resolute's FIPS Go fetch `wget .../fips/trixie/...` keeps `trixie` in the path (BUILD_PUBLIC_URL has no resolute dir); pull trixie golang-go.deb + src.deb as-is.
- **First-choice:** trixie FIPS Go installs into resolute slave, builds + Go binaries run → proceed, mark tech debt.
- **Fallback (ABI conflict):** `INCLUDE_FIPS=n`, switch to Ubuntu official resolute golang-go + standard openssl (still resolute, no version revert). FIPS compliance deferred to backlog.
- FIPS decision (on / fallback-off) must be locked before Phase 1 exit.

## 7. Risk register

| # | Risk | Trigger | Mitigation / fallback (all within resolute) |
|---|------|---------|---------------------------------------------|
| R1 | Docker hasn't published a resolute `docker-ce 5:28.5.2`, version string absent | Phase 0 spike a | **Use the Docker Inc. docker-ce version currently available on the resolute suite, pinned to the exact version string** (no version revert, no meta-package, no latest); containerd likewise |
| R2 | BUILD_PUBLIC_URL has no prebuilt SONiC kernel .deb | Phase 0 spike b | Source-build on resolute with resolute toolchain (`+resolute` ABI) |
| R3 | debootstrap has no resolute script / missing keyring | Phase 2 | Manually import Ubuntu keyring + `--no-check-gpg`; or use Ubuntu cloud image `ubuntu:resolute` as base instead of debootstrap (still resolute) |
| R4 | cri-dockerd has no resolute build, k8s section fails | Phase 2 | **Decision: conditionally skip k8s/cri for vs stage**; backlog |
| R5 | trixie FIPS Go `.deb` has glibc/ABI conflict on resolute | Phase 1 | **Fallback: `INCLUDE_FIPS=n`**, use Ubuntu official resolute golang-go + openssl; mark tech debt |
| R6 | apt-name migration fails (`t64` suffix packages renamed/absent) | Phase 1 | Map each to resolute name; if absent, assess if still needed; add to Goal-2 catalog |
| R7 | `python3.13`/`python3-distutils`/`python3-pip` are a different version on resolute | Phase 1 | Align to resolute python version, update [sonic-slave-resolute](sonic-slave-trixie/Dockerfile.j2#L69) `python3.13` strings |
| R8 | Ubuntu has no `non-free-firmware` equivalent | Phase 2/3 | vs needs no vendor firmware; absence non-blocking; record affected packages |
| R9 | debootstrap apt-list cache path hardcoded `deb.debian.org_debian_dists_` | Phase 2 | Change to `archive.ubuntu.com_ubuntu_dists_` |
| R10 | sources.list.j2 Ubuntu suite semantics differ (security mirror, partial deb-src) | Phase 1/2 | Add resolute branch: security via `archive.ubuntu.com`, components `main universe multiverse restricted` |

## 8. Verification

- **Control:** keep `BLDENV=trixie` path usable throughout; trixie-vs is the expected-output baseline. On resolute-vs issues, reproduce/compare on trixie-vs first to distinguish "resolute regression" vs "environment issue".
- **Phase 1:** `make sonic-slave-build BLDENV=resolute` succeeds; `docker run` `/etc/os-release` = Ubuntu 26.04; representative source-build passes; FIPS decision locked.
- **Phase 2:** `make ... one-image PLATFORM=vs BLDENV=resolute` produces image; rootfs `/etc/os-release` = Ubuntu 26.04; docker/kernel/apt sources all resolute.
- **Phase 3:** `docker-base-resolute.gz` builds; `docker run` `/etc/os-release` = Ubuntu 26.04.
- **Phase 4:** all vs container images build; `docker run` each container starts.
- **Phase 5:** KVM boots; smoke passes (`config load_minigraph -y`, `show version`, `show ip intf`, containers healthy); consistent with trixie-vs control.

## 9. Backlog (post-vs)
- FIPS-compliant toolchain (resolute Go + openssl FIPS).
- k8s/cri on resolute (cri-dockerd alternative or Ubuntu-native path).
- Actually swap the needs-patch-port / safe-to-swap packages from Goal-2 catalog (following the grpc/protobuf template).
