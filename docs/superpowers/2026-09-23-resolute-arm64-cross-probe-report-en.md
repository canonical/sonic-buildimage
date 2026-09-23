# arm64 vs on 202605_resolute: cross-build probe report

- Date: 2026-09-23
- Repository: `/home/sheldon-qi/sonic-buildimage-resolute`, branch `202605_resolute`, baseline `2c0e2bc031`
- Probe worktree: `/home/sheldon-qi/sbi-arm64-probe`, local branch `probe/arm64-vs-cross`, all changes uncommitted
- Build host: Ubuntu 26.04, x86_64, 16 cores / 47 GB RAM
- Design and plan: [probe design](specs/2026-09-23-resolute-arm64-vs-cross-probe-design-en.md), [probe plan](plans/2026-09-23-resolute-arm64-vs-cross-probe-en.md)
- This is the English version and the single source of truth; the Chinese version is `-zh.md`

## 0. Question and bottom line

The question was not "can an arm64 vs image be built" but **"does arm64 SONiC justify a native arm64 build machine?"**. The probe drove `PLATFORM=vs PLATFORM_ARCH=arm64` through SONiC's cross-compilation path (`CROSS_BLDENV=1`) on an amd64 host until it stalled, and classified every failure by one criterion: would a native arm64 build eliminate it?

**Bottom line: yes, get a native arm64 machine.**

- The probe found **21 failures in SONiC itself. 19 of them exist only because of cross-compilation** and vanish on a native machine. The other 2 are architecture-inherent and need code changes whichever way you build, but both are small.
- Nobody maintains the cross path upstream, and it does not work on any current release: it holds `gcc-10` packages, installs `python3-distutils`, runs `rustup` before its environment is set, and passes `--platform` through an `ARG`. None of that has built on a modern distribution for years. Making it work would mean maintaining our own fork of SONiC's cross infrastructure.
- Past the frontier the probe reached, a static scan finds **at least 8 more cross-only build-dependency gaps and one structural Python conflict**, and none of them has reached the Docker layer yet. The failures surface one per pass, with no end in sight.
- Speed is a secondary argument: building the arm64 rootfs alone took 47 minutes, almost all of it under qemu (`mkinitramfs` spawns one emulated process per shell call). A native build runs that step at full speed.

What the probe did **not** verify is whether a native build actually reaches a `.bin`. §6 lists what the native path is expected to need, but no native run backs it.

## 1. How far it got

| Gate | Result |
|---|---|
| 1 Emulation environment | Passed. An `aarch64` handler is registered and an arm64 container runs. |
| 2 Cross slave image | Passed after 8 full attempts and 3 shadow builds: `sonic-slave-resolute-march-arm64` (16.8 GB), `aarch64-linux-gnu-gcc` 15.2.0. It took 5 code deviations, 1 emulator swap and 1 missing configuration item. |
| 3 Full collection (`-k`) | Reached the dependency frontier in 4 passes: **78 debs (31 of them compiled arm64 binaries), 6 wheels, the full arm64 rootfs (`rfs.squashfs`, 733 MB, kernel `7.0.0-1002-sonic`) and 2 Docker images** were built. It took 2 code deviations. The next layer showed a fix-one-reveal-the-next pattern, so collection stopped under the plan's long-tail rule and the rest was enumerated statically. |

In gate 3, a single cross-only failure blocks the whole Docker layer. `libswsscommon` depends on `python3-libyang` (arm64), which cannot be installed into the slave's amd64 Python (§3.2, G3-8). The chain runs swss-common → python3-swsscommon → every SONiC Python wheel → `docker-config-engine` → **every SONiC container except `docker-base` and `docker-dash-engine`**.

## 2. Classification

| Class | Meaning | Count |
|---|---|---|
| **A** | Cross-only; a native build eliminates it | **19** |
| **B** | Architecture-inherent; needs a code change either way | **2** |
| **Q** | Emulator defect (qemu version) | 1 |
| **E** | Environment of this host | 3 |

Source (upstream bit-rot, resolute port, Ubuntu packaging) and class are separate dimensions. Several class A items originate in the resolute port, but they only bite on the cross path.

## 3. Findings

### 3.1 Gate 2: cross slave image (`sonic-slave-resolute/Dockerfile.j2`)

| # | Failure | Source | Class |
|---|---|---|---|
| G2-1 | `apt-mark hold g++-10-$gcc_arch` / `gcc-10-…`: no such package | Upstream. The same lines sit in the trixie, bookworm and bullseye slaves, and gcc-10 ships on no current release. | A |
| G2-2 | `python3-distutils`, `libpython2.7-dev`, `libbind-export-dev`, `libiptc0` do not exist | Upstream. All four are absent from Debian trixie too. | A |
| G2-3 | `python3.13` / `python3.13-dev` do not exist (resolute ships 3.14) | Resolute port (present on trixie) | A |
| G2-4 | `libcurl4-openssl-dev` amd64 and arm64 conflict on `/usr/bin/curl-config` | Ubuntu packaging. The two copies at the same version differ in one place: `curl-config --configure` embeds `--package-metadata` carrying `"architecture":"amd64"` vs `"arm64"`. Debian's two copies are byte-identical. Worth a Launchpad bug. | A |
| G2-5 | `apt install python-is-python3` refuses: Unmet dependencies | Upstream. The preceding `dpkg --force-all` of arm64 `python3.14-dev` and `libgirepository1.0-dev` leaves broken dependencies, and apt will not act on a broken system. | A |
| G2-6 | `rustup target add aarch64-unknown-linux-gnu`: no default toolchain | Upstream. The step runs before `ENV RUSTUP_HOME`, so rustup looks in `/root/.rustup`. | A |
| G2-7 | `docker run`: Duplicate mount point `/var/lib/docker` | Upstream configuration. Cross/qemu builds need `SONIC_SLAVE_DOCKER_DRIVER=vfs`, which upstream CI sets (`.azure-pipelines/azure-pipelines-build.yml:49-50`) and the README never mentions. | A |
| Q-1 | Random SIGSEGV of arm64 Python 3.14: pip build-deps "0 lines of output", py3compile `status code -11` | `multiarch/qemu-user-static` 7.2.0, hard-coded at `Makefile.work:457` (image 2023-01, project unmaintained) | Q |

**Q-1 A/B test.** 16 parallel workers ran `python3.14 -c "import importlib.util, json, email, asyncio"` 40 times each, on the same image layer:

| qemu | Runs | Segfaults |
|---|---|---|
| multiarch 7.2.0 (hard-coded by SONiC) | 2560 | **7** (~1/366) |
| tonistiigi/binfmt `qemu-v9.2.2` | 3840 | **0** |

60-run serial loops pass on both versions; the crash needs concurrency. If both versions crashed at the same rate, the chance that all 7 crashes fall on the 7.2.0 share is about 0.16%. **The flakiness is a defect of the old qemu, not a property of emulation.** After the swap, the 100-step slave build ran through in one pass.

### 3.2 Gate 3: package and image build

| # | Target | Root cause | Class |
|---|---|---|---|
| G3-1 | bash | The build-time tool `mkbuiltins.c` is compiled with `aarch64-linux-gnu-gcc` and trips over GCC 15's C23 default: `'bool' cannot be defined via 'typedef'`. The same source builds on resolute amd64, and Ubuntu builds bash arm64 natively. | A |
| G3-2 | hsflowd | host-sflow bakes `-std=gnu99` into `$(CC)`. The native compile line reads `gcc -std=gnu99 …`; the cross CC override drops the flag, so GCC 15 falls back to C23 and `typedef uint32_t bool;` fails. | A |
| G3-3 | sflowtool | configure runs the host `gcc` with arm64 `dpkg-buildflags` (`-mbranch-protection=standard`), which that gcc rejects as an unrecognized option | A |
| G3-4 | monit | `patch/cross-compile-changes.patch` is applied only on the cross path and no longer applies to Ubuntu monit 5.35.2-3. The port switched the source from Debian but never refreshed this patch. | A |
| G3-5 | lldpd | Build-dependency `libsnmp-dev` (arm64) is missing. Since trixie, snmpd comes from the distribution (`rules/snmpd.mk:5`), and the cross slave's `:arm64` list never gained it. | A |
| G3-6 | libdashapi | Build-dependency `libprotobuf-dev (>= 3.21.12)` (arm64) is missing | A |
| G3-7 | libnexthopgroup | `Build-Depends: python3` has no `:any`, so the cross build demands arm64 Python | A |
| G3-8 | python3-libyang (arm64) install | Depends on `python3 (>= 3.14~)` for arm64, and the slave's Python is amd64. **This one blocks the whole Docker layer (§1).** | A |
| G3-9 | systemd-sonic-generator | `aarch64 ld: cannot find -lboost_system`. The cross `:arm64` list installs unversioned `libboost-*-dev`, which resolves to resolute's default 1.90 (verified: `libboost-filesystem1.90-dev:arm64`), and Boost 1.89 dropped the `boost_system` stub library. The port pinned the native list to 1.83 but not the cross list. | A |
| G3-10 | sonic-platform-vs | "binary build with no binary artifacts found". Upstream hard-codes `sonic-platform-vs_…_amd64.deb`, `Architecture: amd64` and platform `x86_64-kvm_x86_64-r0`: **upstream designed vs for x86_64 KVM only.** A native build fails the same way. | **B** |
| G3-11 | docker-base-resolute | `ARG BASE=--platform=linux/arm64 ubuntu:resolute` + `FROM $BASE` → BuildKit: "failed to parse stage name". BuildKit does not expand a flag from an `ARG` into `FROM`, and the Dockerfile needs BuildKit (`RUN --mount=type=bind,from=base`). The trixie and bookworm templates are identical. | A |
| G3-12 | docker-base-resolute (after the fix) | Built, but **mislabeled**: the content is genuine aarch64 (`/usr/bin/bash` e_machine `b700`) while the image config says `architecture=amd64`, because the final `FROM scratch` stage has no platform. Derived images inherit the label. | A |
| G3-13 | docker-dash-engine | **Silent wrong-architecture artifact.** The build succeeds, but its base `p4lang/behavioral-model:latest` exists only for amd64. The log fetches `noble/multiverse amd64 Packages` and the image config says `architecture=amd64`. The arm64 build raises no error and would ship it into `sonic-vs.bin`, where it dies with exec format error on the device. | **B** |
| G3-14 | libswsscommon | Build-dependency `libhiredis-dev` (arm64) is missing | A |

### 3.3 The frontier the probe did not cross (static scan)

Every build pass revealed one more missing cross build-dependency, so the probe stopped iterating and ran `dpkg-checkbuilddeps -a arm64 -Pcross,nocheck` over all 70 in-tree `debian/control` files inside the cross slave. That is the same check `dpkg-buildpackage` runs. 25 of the 70 have gaps. Excluding dependencies SONiC builds itself (satisfied by `-install` during the real build) and packages outside the `sonic-vs.bin` closure (gobgp/`dh-systemd`, ptf/`python-all`, freeradius, frr's gcc-plugins, trixie-only redfish) leaves:

- **Distribution arm64 dev packages missing from the cross list**: `libhiredis-dev`, `libprotobuf-dev`, `libprotobuf-c-dev`, `libsnmp-dev`, `libxxhash-dev`, `liblua5.1-0`, `libboost-serialization1.83-dev` (plus `libjsoncpp-dev`, needed only by redfish)
- **Structural conflict**: `Build-Depends: python3 / python3-all / python3-all-dev` without `:any` demands arm64 Python, and frr's `python3-dev:native` goes unmet because the cross slave `--force-all`-installs `python3-dev:arm64` over the amd64 one. The cross slave fights itself over which architecture's Python it holds.

The mechanism: the cross slave's `:arm64` package list is a **second, hand-maintained copy of the build-dependency set**. Upstream moved snmpd, hiredis and protobuf to distribution packages and never updated it. A native build draws its build dependencies from the one list amd64 builds also use, and that list stays current.

### 3.4 Environment of this host (not SONiC, not arm64)

| # | Symptom | Cause |
|---|---|---|
| E-1 | rootfs `apt-get update` → `https://mirrors.tuna.tsinghua.edu.cn/...` certificate verify failed | `/etc/hosts` maps `ports.ubuntu.com` and `archive.ubuntu.com` to the local mirror `192.168.10.32`, which answers `ports` requests with a 302 to tuna over HTTPS, and a fresh minbase rootfs has no `ca-certificates` yet. Worked around with `MIRROR_URLS=http://archive.ubuntu.com/ubuntu/`. |
| E-2 | One wget in debootstrap stalled for 15 minutes at 0 bytes | Transient hang of the local mirror. wget's default read timeout is 900 s; it retried and recovered. |
| E-3 | BuildKit: `lookup auth.docker.io on 10.211.55.1:53: i/o timeout` | Transient DNS timeout. The registry token is fetched by the client session inside the slave container, so the lookup uses the container's DNS. |

E-1 also exposed a real inconsistency. For arm64, `scripts/build_debian_base_system.sh` points debootstrap at `archive.ubuntu.com`, while `scripts/build_mirror_config.sh` writes `ports.ubuntu.com`. Ubuntu 26.04 unified its archive (the `Architectures:` line of `dists/resolute/Release` includes arm64), so `archive.ubuntu.com` alone is enough.

## 4. Time and resources

| Stage | Duration | Note |
|---|---|---|
| Cross slave image (final full build) | ~40 min | 11:32–12:12Z; each `configure` rebuilds from step 6, because `sonic-build-hooks` regenerates `buildinfo` every run |
| Gate 3 pass 1 | 24 min | Package layer |
| Gate 3 pass 2 | 49 min | The arm64 rootfs alone took 46m51s, almost all of it under qemu (`mkinitramfs` spawns one emulated process per shell call) |
| Gate 3 pass 3 | 13 min | `docker-base` under qemu |
| Gate 3 pass 4 | 4 min | Up to the libswsscommon build-dependency |

Free disk went from 161 GB to 72 GB. The march dockerd uses `--storage-driver=vfs`, which shares no layers: 2.9 GB of images took 26 GB on disk (~9×), and `/var/lib/march/docker` reached 35 GB. The slave image is 16.8 GB. Over the whole probe the amd64 shared dpkg cache received 0 writes.

## 5. If you stay on the cross path

Before any SONiC fixes, three things are prerequisites:

1. **Replace qemu 7.2.0.** Register `tonistiigi/binfmt:qemu-v9.2.2` and pass `DOCKER_MULTIARCH_CHECK=true` on the make command line; otherwise every make run re-registers 7.2.0 (`Makefile.work:702`).
2. **Set `SONIC_SLAVE_DOCKER_DRIVER = vfs`**, or `docker run` fails on the duplicate mount.
3. **Budget for vfs.** Plan on at least 150 GB free; the probe used 89 GB without reaching the Docker layer.

After that come the 19 class A items (9 of them already worked around in the probe, §7, one of those — G3-8 — only by forcing the install), the ≥8 dependency gaps in §3.3, and the Python dual-architecture conflict. The Python conflict is a design problem rather than a missing package: the cross slave has to hold amd64 Python to run build tools and arm64 Python headers and extensions to link against, and Debian packaging will not co-install `python3-dev` for both.

## 6. What the native path is expected to need (unverified)

Measured before the probe and not exercised by it:

- `sonic-slave-resolute/Dockerfile.j2:575` installs `gcc-multilib` unconditionally, and resolute publishes no arm64 build of it. Only the native path runs that line. (Class C: a resolute port assumption.)
- `Makefile.work:127` assigns `TARGET_BOOTLOADER=uboot` to every non-amd64 arch. Without an `override TARGET_BOOTLOADER=grub` in `platform/vs/rules.mk` (precedent: `platform/nvidia-bluefield/rules.mk:21`), `build_debian.sh:799` looks for a `platform/vs/sonic_fit.its` that does not exist.
- G3-10 (vs platform package is amd64-only) and G3-13 (dash-engine base is amd64-only).
- `sonic-vs.img.gz` stays unreachable: the ONIE recovery ISOs in `platform/vs/onie.mk` exist only for x86_64. The realistic arm64 target is `target/sonic-vs.bin`.

Evidence that architecture-level compile problems are rare: of the 78 debs, 31 arm64 binary packages (about 18 source packages, in C, Go — sonic-mgmt-framework/common — and Rust — sonic-nettools) were actually compiled for aarch64, all cleanly; the rest were downloaded (kernel, libnl, grub, …) or arch:all. No failure in this probe was an arm64 code problem.

**Machine requirements**: 16+ cores, 48 GB+ RAM, 200 GB+ disk. A native build needs neither vfs nor the march dockerd. It needs reachability to `archive.ubuntu.com` / `ports.ubuntu.com`, `ppa.launchpadcontent.net` (the linux-sonic kernel; the arm64 debs are published), Docker Hub, GitHub, PyPI and `download.docker.com`, and it needs the host fixes the amd64 build already relies on (AppArmor `gs` override, `ip_tables` module).

## 7. Probe changes and state

All in `/home/sheldon-qi/sbi-arm64-probe`, uncommitted. The full diff is in [data/2026-09-23-arm64-cross-probe-deviations.patch](data/2026-09-23-arm64-cross-probe-deviations.patch).

| # | File | Change | Resolves |
|---|---|---|---|
| 1 | `sonic-slave-resolute/Dockerfile.j2` | Remove the `g++-10` / `gcc-10` holds | G2-1 |
| 2 | same | `python3.13` → `python3.14` (×2); drop `python3-distutils`, `libpython2.7-dev`, `libbind-export-dev`, `libiptc0` | G2-2, G2-3 |
| 3 | same | `dpkg` `path-exclude=/usr/bin/curl-config` around the one install RUN | G2-4 |
| 4 | same | `python-is-python3` via `apt-get download` + `dpkg -i` | G2-5 |
| 5 | same | `RUSTUP_HOME=$RUST_ROOT` before `rustup target add` | G2-6 |
| 6 | host binfmt (runtime state) | aarch64 handler → `tonistiigi/binfmt:qemu-v9.2.2`, plus `DOCKER_MULTIARCH_CHECK=true` | Q-1 |
| 7 | `dockers/docker-base-resolute/Dockerfile.j2` | `--platform` moved from `ARG BASE` into `FROM` (arm64 cross branch only) | G3-11 |
| 8 | `slave.mk:1018` | `--force-depends` when installing `python3-libyang_*` on the cross path | G3-8 |

`rules/config.user` (gitignored) additionally holds: the isolated dpkg cache `/var/cache/sonic/artifacts-arm64`, `SONIC_SLAVE_DOCKER_DRIVER = vfs`, and `DOCKER_BUILDER_USER_MOUNT` with four mounts. The mounts exist only because the probe runs from a linked worktree: its `.git` points into the main repository, which the slave container does not mount, and submodule gitfiles are relative while the build mounts the tree at `/sonic`. A normal clone needs none of this. The probe also unset `core.worktree` in the 60 probe-private submodule repositories.

Build command for gate 3:

```bash
cd /home/sheldon-qi/sbi-arm64-probe
BLDENV=resolute CROSS_BLDENV=1 make TARGET_BOOTLOADER=grub \
  SONIC_BUILD_VARS="-k MIRROR_URLS=http://archive.ubuntu.com/ubuntu/ MIRROR_SECURITY_URLS=http://archive.ubuntu.com/ubuntu/" \
  DOCKER_MULTIARCH_CHECK=true target/sonic-vs.bin
```

`SONIC_BUILD_VARS` is the only channel into the in-container make: `Makefile:15` folds it into `SONIC_OVERRIDE_BUILD_VARS`, which `Makefile.work:673` appends to the in-container command line. Passing `MIRROR_URLS` this way rather than in `config.user` keeps it out of the slave image's content-hash tag, so the slave is not rebuilt.

Logs are in `probe-logs/` under the probe worktree (every gate log, the progress ledger, the `dpkg-checkbuilddeps` output and the qemu stress script); per-package logs are under `target/`.

Two things the probe found in the main repository, outside the probe itself:

- 15 submodules have `.gitmodules` pointing at `canonical` while the `submodule.<name>.url` cached in `.git/config` still points at `sonic-net`. Any new worktree or clone breaks on submodule init (sonic-gnmi: `not our ref`). The fix is `git submodule sync --recursive`, not yet run.
- On this host `find` is `bfs`, which rejects `-newermt '-2 hours'`; the plan's contamination check needs ISO timestamps.
