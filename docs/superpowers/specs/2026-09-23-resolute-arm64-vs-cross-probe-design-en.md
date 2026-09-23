# Resolute arm64 vs Cross-Build Probe — Design

- Date: 2026-09-23
- Working repository: `/home/sheldon-qi/sonic-buildimage-resolute` (branch `202605_resolute`, baseline `2c0e2bc031`)
- Probe worktree: `/home/sheldon-qi/sbi-arm64-probe` (separate worktree, leaves the main worktree untouched)
- Build host: Ubuntu 26.04, x86_64, 16 cores / 47 GB RAM / 162 GB free disk
- Goal: decide whether arm64 SONiC warrants acquiring a native arm64 machine — not to produce an image
- Related documents: [clean rebuild design](2026-07-21-resolute-clean-rebuild-design-en.md), [migration design](2026-07-03-sonic-202605-resolute-migration-design-en.md)
- This is the English version and the single source of truth; the Chinese version is `-zh.md`

## 1. Goal and Scope

On an amd64 host, drive a `PLATFORM=vs PLATFORM_ARCH=arm64` build through SONiC's cross-compilation path (`CROSS_BLDENV=1`) until it can go no further, then collect the **complete failure list** and classify it.

This is a scouting run, not an image delivery. The deliverable is a classified failure list and one conclusion: how necessary a native arm64 machine actually is.

**Out of scope:** fixing any package-level failure, editing the build graph to drop components, or producing `target/sonic-vs.bin`. Every repair decision waits until the classification is in.

## 2. Decision Criterion: Three Failure Classes

Each failure goes into exactly one class. The classification is what produces the conclusion.

| Class | Definition | Eliminated by a native arm64 machine? |
|---|---|---|
| **A — cross-only** | Occurs only under cross-compilation: `debian/rules` does not honour `-a arm64`, `configure` guesses the wrong host, a wheel has no aarch64 build and must compile in place, cross venv path problems | **Yes** — a native build never enters this code path |
| **B — architecture-inherent** | arm64 genuinely lacks something: upstream publishes an amd64-only image or package, a binary artifact exists only for x86_64 | **No** — the same code change is needed either way |
| **C — port assumption** | An amd64 assumption introduced by `202605_resolute` itself | **No** — this is our own debt |

Decision rule: if class A dominates, a native machine is worth acquiring, because that entire class disappears for free. If B/C dominate, the machine buys nothing that the code changes would not, so fix it in place.

## 3. Verified Baseline Facts

Every item below was measured before this design was written; none of it is inference.

| Item | Finding | Evidence |
|---|---|---|
| Kernel | linux-sonic 7.0.0-1002.2 arm64 `linux-image` / `linux-modules` / `linux-headers` are all Published | Launchpad API against the `canonical-kernel-team/bootstrap` PPA; the URLs in `rules/linux-kernel.mk` are already parameterised on `CONFIGURED_ARCH` |
| apt mirrors | Ubuntu 26.04 unified its archive — `archive.ubuntu.com` serves arm64 too, so **ports.ubuntu.com is not needed** | `dists/resolute/Release` carries `Architectures: amd64 amd64v3 arm64 armhf i386 ppc64el riscv64 s390x` |
| ONLINE_DEBs | The pool URLs hardcoded to `archive.ubuntu.com` in `rules/*.mk` resolve for arm64 as well | Range requests succeeded for the arm64 grub2-common, libnl-3-200 and sedutil debs |
| Base image | `ubuntu:resolute` includes arm64 | Docker Hub manifest list |
| grub | `rules/grub2.mk` already has an arm64 branch; `grub-efi-arm64`(`-bin`) 2.14-2ubuntu1 exist | Branch code plus pool check |
| Slave dependencies | arm64 builds exist for `qemu-system-x86`, `libboost1.83-dev`, `libthrift-0.22.0`, `golang-1.24-go`, `libwtmpdb-dev`, `python3-dacite`, `perl-modules-5.40`; the pinned `docker-ce` / `containerd.io` versions have arm64 builds | Launchpad API; `download.docker.com` `dists/resolute/stable/binary-arm64` |
| Cross toolchain | `crossbuild-essential-arm64`, `gcc-aarch64-linux-gnu` and `dpkg-cross` are all available on resolute amd64 | Launchpad API |
| Depth of cross support | 63 files consume `CROSS_BUILD_ENVIRON`, including 35 `src/*/Makefile`s, dpkg-cross configuration, the Rust cross target `aarch64-unknown-linux-gnu`, and a Python cross venv | Repository search |
| FIPS | Hard-blocked on resolute by the `$(error)` in `rules/sonic-fips.mk`, so it adds no variable here | Branch code |
| `MIRROR_SNAPSHOT` | Defaults to `n`; the snapshot path is not involved | `rules/config:337` |

Known **class B/C** items, settled before the probe starts:

- **B**: the base image of `platform/vs/docker-dash-engine/Dockerfile.j2`, `p4lang/behavioral-model:latest`, is **amd64-only** (confirmed from the manifest list), and `platform/vs/docker-dash-engine.mk` adds it to `SONIC_INSTALL_DOCKER_IMAGES` unconditionally.
- **B**: the ONIE recovery ISOs pinned in `platform/vs/onie.mk` exist only for `x86_64`, so `sonic-vs.img.gz` (the KVM image) cannot be produced for arm64; the only realistic arm64 target is `target/sonic-vs.bin`.
- **C**: `sonic-slave-resolute/Dockerfile.j2:575` installs `gcc-multilib` unconditionally, and resolute publishes no arm64 build of that package. **The cross path takes the else branch and never runs that line**, so this probe will not hit it; on the non-cross path it is a hard blocker.

## 4. Isolation

The probe runs in a separate git worktree, `/home/sheldon-qi/sbi-arm64-probe`, because:

1. `make configure` writes `.arch` and `.platform`; running in place would rewrite the main worktree's amd64 configuration.
2. `DOCKER_ROOT` is `fsroot.docker.$(BLDENV)` — the same path for both architectures, so they would overwrite each other.
3. `target/` is shared, and arm64 artifacts would mix into the existing amd64 ones.

The shared dpkg cache (`/var/cache/sonic/artifacts`, currently 14 GB) is pointed at a different directory for the duration, so arm64 artifacts cannot enter the amd64 key space.

## 5. Three Gates

Advance one gate at a time. If a gate blocks, rule on it there, record it, and do not force past it.

### 5.1 Gate 1: Environment

Install `qemu-user-static`, register binfmt, start the march dockerd. Note that **the cross path needs all of this too**: the condition at `Makefile.work:434` is `MULTIARCH_QEMU_ENVIRON` **or** `CROSS_BUILD_ENVIRON` being `y`, because the rootfs and every docker image are still arm64 containers whose dpkg/postinst scripts run under qemu-user. Cross-compilation saves compile time; it does not save this infrastructure.

The march dockerd uses `--storage-driver=vfs` (no layer sharing, disk-hungry) with data-root `/var/lib/march/docker`. Check free space before starting and watch it throughout.

Pass criterion: binfmt has an aarch64 handler registered, and the march dockerd is up with a usable socket.

### 5.2 Gate 2: Cross Slave Image

```
BLDENV=resolute CROSS_BLDENV=1 make configure PLATFORM=vs PLATFORM_ARCH=arm64
```

This produces `sonic-slave-resolute-march-arm64` (amd64 base plus the aarch64 cross toolchain). It is the first real gate — if the slave will not build, nothing downstream matters.

Anticipated risk: the cross branch of `sonic-slave-resolute/Dockerfile.j2` runs `apt-mark hold g++-10-$gcc_arch` and `gcc-10-$gcc_arch`, but resolute's default gcc is 15 and no version-10 cross packages exist. A failure here is **class C**.

Pass criterion: the image builds and `aarch64-linux-gnu-gcc --version` runs inside the container.

### 5.3 Gate 3: Full Collection

The aim is one pass that yields the complete failure list, rather than serial fail-fix-rerun discovery.

`-k` (keep-going) does not cross the container boundary: the outer make's `MAKEFLAGS` is not in the `DOCKER_RUN` `-e` list, and the container starts a fresh `$(MAKE) -f slave.mk` invocation. The approach is therefore:

1. Dry-run with `make -n` and capture the fully expanded `SONIC_BUILD_INSTRUCTION` command line from `Makefile.work:575`, including every variable it passes (`PLATFORM`, `PLATFORM_ARCH`, `CROSS_BUILD_ENVIRON`, `TARGET_BOOTLOADER`, and the rest).
2. Enter the container via `make ... sonic-slave-bash` (`Makefile.work:736`).
3. Run that same command line inside the container with `-k` inserted, targeting `target/sonic-vs.bin`.

Keep logs throughout. Build concurrency stays at the existing `SONIC_CONFIG_BUILD_JOBS` setting; the probe does not tune it.

Pass criterion: run until no new kinds of failure appear.

## 6. Zero-Code Workarounds

Code changes during the probe are expected to be zero. Two items are handled with command-line variables rather than edits:

- `TARGET_BOOTLOADER=grub` — `Makefile.work:127` assigns `uboot` for every non-amd64 arch, after which `build_debian.sh:799` looks for a `platform/vs/sonic_fit.its` that does not exist and `set -e` kills the build. A command-line variable outranks a makefile assignment, and `SONIC_BUILD_INSTRUCTION` forwards `TARGET_BOOTLOADER` into the container explicitly, so setting it once at the outermost level carries all the way through. The long-term fix is `override TARGET_BOOTLOADER=grub` in `platform/vs/rules.mk` (precedent: `platform/nvidia-bluefield/rules.mk:21`), but that comes after the probe.
- `gcc-multilib` — never executed on the cross path; nothing to do.

`docker-dash-engine` is deliberately **not** worked around, so that it shows up in the list as the class B failure it is.

## 7. Deliverables

1. The complete failure list, each entry carrying: the failing target, the essence of the error, its A/B/C class, and the basis for that classification.
2. One conclusion on how necessary a native arm64 machine is, supported by the share of class A failures.
3. If the conclusion is "a native machine is needed", the machine specification it requires (cores, memory, disk, network reachability).

## 8. Risks and Abort Conditions

- **Disk**: vfs shares no layers, so the arm64 containers and rootfs consume space fast. Stop and clean up below 30 GB free rather than running the disk to zero.
- **Shared cache contamination**: prevented by the cache isolation in section 4; if the amd64 cache turns out to have been touched, stop immediately.
- **Gate 2 blocks outright**: if the cross slave image cannot be made to build, the starting line was never reached. Conclude there — on this host the cross path is closed, leaving only a native machine or pure qemu — and do not advance to gate 3.
- **Unbounded tail**: if gate 3's failure list shows a clear fix-one-spawn-three pattern, stop collecting and conclude from the sample already gathered. The value of a probe is the judgement, not exhaustiveness.
