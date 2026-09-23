# arm64 vs Cross-Build Probe Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Drive a `PLATFORM=vs PLATFORM_ARCH=arm64` build through the cross-compilation path on an amd64 host, collect the complete failure list, classify it, and decide from that whether a native arm64 machine is needed.

**Architecture:** A separate git worktree with a separate dpkg cache, advanced through three sequential gates (environment → cross slave image → full `-k` collection). No code changes: of the two known amd64 assumptions, one is bypassed with a command-line variable and the other is skipped by the cross path itself.

**Tech Stack:** The SONiC buildimage build system (`Makefile` / `Makefile.work` / `slave.mk`), the `CROSS_BLDENV=1` cross path, Docker plus `multiarch/qemu-user-static` binfmt, Ubuntu 26.04 resolute.

**Design basis:** [arm64 vs cross-build probe design](../specs/2026-09-23-resolute-arm64-vs-cross-probe-design-en.md) (this English version is the single source of truth)

## Global Constraints

- **No code changes** during the probe. Every failure is recorded, never repaired.
- Write only to `/home/sheldon-qi/sbi-arm64-probe`; the main worktree `/home/sheldon-qi/sonic-buildimage-resolute` and the shared cache `/var/cache/sonic/artifacts` must not be written to.
- `canonical/202605_resolute` is a production branch; this plan pushes no branch at all. The probe branch `probe/arm64-vs-cross` stays local.
- Stop and clean up as soon as free disk drops below 30 GB; never run the disk to zero.
- If gate 2 does not pass, **do not** enter gate 3 — conclude there.
- If gate 3 shows a fix-one-spawn-three tail, stop collecting and conclude from the sample already gathered.
- Every failure goes into exactly one class: **A cross-only** / **B architecture-inherent** / **C port assumption**.

---

### Task 1: Probe Worktree and Cache Isolation

**Files:**
- Create: `/home/sheldon-qi/sbi-arm64-probe/` (worktree on branch `probe/arm64-vs-cross`)
- Create: `/home/sheldon-qi/sbi-arm64-probe/rules/config.user` (gitignored, never committed)
- Create: `/var/cache/sonic/artifacts-arm64/` (isolated dpkg cache)

**Interfaces:**
- Consumes: nothing (first task)
- Produces: the probe worktree path `/home/sheldon-qi/sbi-arm64-probe`, where every later task runs; the disk baseline numbers recorded in the log, against which task 4's stop condition is measured.

- [ ] **Step 1: Create the worktree**

`202605_resolute` is already checked out in the main worktree, and git refuses to check out one branch in two worktrees, so create a probe branch:

```bash
git -C /home/sheldon-qi/sonic-buildimage-resolute worktree add \
  -b probe/arm64-vs-cross /home/sheldon-qi/sbi-arm64-probe 202605_resolute
```

Expected: `Preparing worktree (new branch 'probe/arm64-vs-cross')` followed by `HEAD is now at 2c0e2bc031`.

- [ ] **Step 2: Populate submodules**

The build needs submodule sources. The objects already live in the shared `.git/modules/`, so this is a local checkout with no network access.

```bash
cd /home/sheldon-qi/sbi-arm64-probe && git submodule update --init --recursive
```

Expected: a series of `Submodule path '...': checked out '<sha>'` lines, with no network errors such as `fatal: unable to access`.

- [ ] **Step 3: Verify submodule completeness**

```bash
cd /home/sheldon-qi/sbi-arm64-probe
git submodule status --recursive | wc -l
git submodule status | grep -c '^-' || true
```

Expected: the first command prints `60`; the second prints `0` (a leading `-` marks an uninitialised submodule). If the second is non-zero, list the uninitialised entries and stop — the submodule object store may be damaged, and the established remedy (deinit, remove `.git/modules/<name>`, re-clone from origin) must run first.

- [ ] **Step 4: Create the isolated dpkg cache directory**

```bash
sudo mkdir -p /var/cache/sonic/artifacts-arm64
sudo chmod 777 /var/cache/sonic/artifacts-arm64
ls -ld /var/cache/sonic/artifacts-arm64
```

Expected: `drwxrwxrwx`.

- [ ] **Step 5: Write the probe-specific config.user**

`rules/config.user` is gitignored, so a fresh worktree has none and it must be written explicitly. It differs from the main worktree's copy in exactly one line — the cache path:

```bash
cat > /home/sheldon-qi/sbi-arm64-probe/rules/config.user <<'EOF'
# Config for the arm64 cross-build probe. The only difference from the main
# worktree is the isolated dpkg cache directory.

PLATFORM ?= vs

# Pull base images straight from Docker Hub, not the Microsoft internal mirror
# (which carries no Ubuntu resolute).
DEFAULT_CONTAINER_REGISTRY =

SONIC_CONFIG_USE_CCACHE = y
BUILD_SKIP_TEST = y
SONIC_CONFIG_USE_DOCKER_CACHE = y

# Isolation: arm64 artifacts must not enter the amd64 key space.
SONIC_DPKG_CACHE_METHOD = rwcache
SONIC_DPKG_CACHE_SOURCE = /var/cache/sonic/artifacts-arm64

SONIC_VERSION_CACHE_METHOD = none
SONIC_VERSION_CACHE_SOURCE = /var/cache/sonic/artifacts-arm64/vcache
EOF
```

Note that `INCLUDE_FIPS` is deliberately **not** set here: `rules/config:381` already declares `INCLUDE_FIPS ?= n`, and `rules/config.user` is included afterwards, where `?=` is a no-op on an already-defined variable. On resolute, `INCLUDE_FIPS=y` is rejected outright by the `$(error)` in `rules/sonic-fips.mk`.

- [ ] **Step 6: Verify the cache isolation took**

```bash
grep -n "artifacts" /home/sheldon-qi/sbi-arm64-probe/rules/config.user
```

Expected: only `artifacts-arm64` appears; the bare `/var/cache/sonic/artifacts` does not. If the bare path appears, correct it and re-run this step.

- [ ] **Step 7: Record the disk baseline**

```bash
df -h / | tail -1
du -sh /var/cache/sonic/artifacts
docker system df
```

Record all three outputs in the probe log. Task 4's stop condition (below 30 GB free) is measured against this baseline.

---

### Task 2: Gate 1 — Emulation Environment

**Files:**
- Modify: the host binfmt_misc registry (kernel runtime state, not a file)
- Create: `/tmp/arm64-probe-gate1.log`

**Interfaces:**
- Consumes: task 1's worktree and disk baseline
- Produces: a working aarch64 binfmt handler, which gate 2's `--platform=linux/arm64` container builds depend on.

- [ ] **Step 1: Check prerequisites**

```bash
mount | grep -c binfmt_misc
sudo -n true && echo "sudo OK"
df --output=avail -BG / | tail -1
docker version --format '{{.Server.Version}}'
```

Expected: the first is ≥ 1 (binfmt_misc mounted); the second prints `sudo OK`; the third is ≥ 60G; the fourth prints the docker server version. If any fails, stop and resolve it rather than continuing.

- [ ] **Step 2: Register the binfmt handlers**

Use exactly the command the build system uses (`DOCKER_MULTIARCH_CHECK` at `Makefile.work:457`), so the probe and the real build do not diverge:

```bash
docker run --rm --privileged multiarch/qemu-user-static --reset -p yes --credential yes 2>&1 | tee /tmp/arm64-probe-gate1.log
```

Expected: several `Setting /usr/bin/qemu-<arch>-static as binfmt interpreter for <arch>` lines.

- [ ] **Step 3: Verify the aarch64 handler is enabled**

```bash
ls /proc/sys/fs/binfmt_misc/ | grep qemu-aarch64
head -1 /proc/sys/fs/binfmt_misc/qemu-aarch64
```

Expected: the first prints `qemu-aarch64`; the second prints `enabled`.

- [ ] **Step 4: Smoke test — actually run an arm64 container**

This is gate 1's real criterion. The previous steps only prove the registry was written; this one proves the emulation path works end to end.

```bash
docker run --rm --platform=linux/arm64 ubuntu:resolute uname -m
```

Expected: `aarch64`.

If this fails, gate 1 has not passed. The conclusion is that the environment layer itself is closed; record the error, stop the whole probe, and do not enter task 3.

- [ ] **Step 5: Record the result**

Append the output of steps 3 and 4 to `/tmp/arm64-probe-gate1.log`.

---

### Task 3: Gate 2 — Cross Slave Image

**Files:**
- Create: `/home/sheldon-qi/sbi-arm64-probe/.arch` and `.platform` (written by `slave.mk:150-151`)
- Create: `/tmp/arm64-probe-gate2.log`
- Create: docker image `sonic-slave-resolute-march-arm64-<user>`

**Interfaces:**
- Consumes: task 2's binfmt handler
- Produces: the cross slave image plus a settled `.arch=arm64` / `.platform=vs`. Task 4's build runs inside that image, and because `.arch` now exists, later make invocations need not pass `PLATFORM_ARCH` again.

- [ ] **Step 1: Run configure**

This target goes through the `%::` catch-all in `Makefile.work`, which first runs the multiarch checks, brings up the `march` dockerd (`--storage-driver=vfs`, data-root `/var/lib/march/docker`), then builds the cross slave image, and finally runs `slave.mk`'s `configure` inside the container.

```bash
cd /home/sheldon-qi/sbi-arm64-probe
BLDENV=resolute CROSS_BLDENV=1 \
  make configure PLATFORM=vs PLATFORM_ARCH=arm64 2>&1 | tee /tmp/arm64-probe-gate2.log
```

Expected: exit code 0. Expect tens of minutes, dominated by installing the cross toolchain and a large set of `-dev` packages.

- [ ] **Step 2: Confirm the cross path, not the qemu path, is in use**

```bash
grep -E "CROSS_BUILD_ENVIRON|MULTIARCH_QEMU_ENVIRON" /tmp/arm64-probe-gate2.log | head -4
```

Expected: `CROSS_BUILD_ENVIRON` is `y` and `MULTIARCH_QEMU_ENVIRON` is `n`. If they are reversed, `CROSS_BLDENV` did not take effect (see `Makefile.work:176`); stop and find out why before continuing, because otherwise the probe measures a different path.

- [ ] **Step 3: Verify the image exists**

```bash
docker images --format '{{.Repository}}:{{.Tag}}' | grep march-arm64
```

Expected: at least one line of the form `sonic-slave-resolute-march-arm64-<user>:<tag>`.

- [ ] **Step 4: Verify the cross toolchain works**

```bash
IMG=$(docker images --format '{{.Repository}}:{{.Tag}}' | grep march-arm64 | head -1)
docker run --rm "$IMG" aarch64-linux-gnu-gcc --version | head -1
```

Expected: the version line of the aarch64 cross gcc.

- [ ] **Step 5: Verify configure persisted its state**

```bash
cat /home/sheldon-qi/sbi-arm64-probe/.arch
cat /home/sheldon-qi/sbi-arm64-probe/.platform
```

Expected: `arm64` and `vs` respectively.

- [ ] **Step 6: Handling a failure**

If step 1 exits non-zero, take the first real error from the tail of the log, record it as the first entry of the failure list, and classify it. The anticipated risk is `apt-mark hold g++-10-$gcc_arch` / `gcc-10-$gcc_arch` in the cross branch of `sonic-slave-resolute/Dockerfile.j2` — resolute's default gcc is 15 and no version-10 cross packages exist, which makes it **class C**.

Per the global constraints, do **not** fix it here. A failed gate 2 ends the probe with the conclusion that the cross path is closed on this host; do not enter task 4.

---

### Task 4: Gate 3 — Full Failure Collection

**Files:**
- Create: `/tmp/arm64-probe-gate3.log` (full build log)
- Create: `/tmp/arm64-probe-failures.txt` (failing-target list)
- Modify: `/home/sheldon-qi/sbi-arm64-probe/target/` (build artifacts and per-package logs)

**Interfaces:**
- Consumes: task 3's cross slave image and its `.arch` / `.platform`
- Produces: `/tmp/arm64-probe-failures.txt`, the basis for task 5's classification; per-package detail stays in `target/<pkg>.log`.

- [ ] **Step 1: Start the collection build**

Two variables carry this step, both from the design document:

- `TARGET_BOOTLOADER=grub` overrides the `uboot` default that `Makefile.work:127` assigns to every non-amd64 arch. Without it, `build_debian.sh:799` looks for a `platform/vs/sonic_fit.its` that does not exist and `set -e` ends the build. A command-line variable outranks a makefile assignment, and `SONIC_BUILD_INSTRUCTION` forwards this variable into the container explicitly.
- `SONIC_BUILD_VARS="-k"` delivers keep-going to the in-container make. `MAKEFLAGS` is not in the `DOCKER_RUN` `-e` list and therefore cannot cross the boundary; but `Makefile:15` folds `SONIC_BUILD_VARS` into `SONIC_OVERRIDE_BUILD_VARS`, which `Makefile.work:673` splices onto the tail of the in-container make command line, and GNU make accepts flags anywhere on a command line.

```bash
cd /home/sheldon-qi/sbi-arm64-probe
BLDENV=resolute CROSS_BLDENV=1 \
  make TARGET_BOOTLOADER=grub SONIC_BUILD_VARS="-k" target/sonic-vs.bin 2>&1 \
  | tee /tmp/arm64-probe-gate3.log
```

Expected: the build advances, continues past multiple failures (keep-going in effect), and finally exits non-zero. Expect hours.

- [ ] **Step 2: Confirm keep-going actually took effect**

```bash
grep -c "not remade because of errors" /tmp/arm64-probe-gate3.log
```

Expected: ≥ 1. If it is 0 and the build stopped at the first error, `-k` did not arrive; return to step 1 and check the `SONIC_BUILD_VARS` spelling. Do not work around it by hand-reconstructing the command line — that introduces variable drift.

- [ ] **Step 3: Check disk headroom and cache contamination**

Run periodically during the build, or immediately after it ends:

```bash
df --output=avail -BG / | tail -1
find /var/cache/sonic/artifacts -maxdepth 1 -newermt '-2 hours' | head
du -sh /var/cache/sonic/artifacts-arm64
```

If the first drops below 30G, interrupt the build at once and clean `/var/lib/march/docker` (vfs shares no layers and is the main consumer), per the global constraints.

The second **must produce no output**: the shared amd64 cache should receive no writes at all during the probe. Any output means isolation failed — most likely `config.user` was not read, or was overwritten — so interrupt the build immediately and find out why before deciding whether to restart. Continuing would contaminate the main build's cache key space.

The third is recorded only, to show the probe's own cache growth.

- [ ] **Step 4: Extract the failure list**

`-k` prints the targets it could not complete at the end, and that is the authoritative list:

```bash
grep -E "^make.*\*\*\*|not remade because of errors" /tmp/arm64-probe-gate3.log \
  | tee /tmp/arm64-probe-failures.txt
wc -l /tmp/arm64-probe-failures.txt
```

Expected: several lines, plus the recorded total.

- [ ] **Step 5: Find the root cause of each failure**

The per-package logs under `target/` read far better than the console output:

```bash
ls -t /home/sheldon-qi/sbi-arm64-probe/target/*.log | head -20
```

For each failing target in the list, read the last 40 lines of the matching `target/<pkg>.log` and distil a one-sentence root cause. Record them all in `/tmp/arm64-probe-failures.txt`.

- [ ] **Step 6: Check the long-tail stop condition**

If step 5 shows a fix-one-spawn-three chain (many failures that are each other's prerequisites, or that share one root cause), stop collecting and conclude from the sample already gathered. The value of a probe is the judgement, not exhaustiveness.

---

### Task 5: Classification and Conclusion Report

**Files:**
- Create: `/home/sheldon-qi/sonic-buildimage/docs/superpowers/2026-09-23-resolute-arm64-cross-probe-report-zh.md`
- Create: `/home/sheldon-qi/sonic-buildimage/docs/superpowers/2026-09-23-resolute-arm64-cross-probe-report-en.md`

**Interfaces:**
- Consumes: `/tmp/arm64-probe-failures.txt` and the individual `target/<pkg>.log` files
- Produces: the probe's final deliverable — a classified failure list and the verdict on whether a native arm64 machine is needed.

- [ ] **Step 1: Classify every entry**

For each failure, assign A / B / C and state the basis:

- **A cross-only** — occurs only under cross-compilation. Basis: the error involves `debian/rules` not honouring `-a arm64`, `configure` guessing the wrong host triplet, a wheel with no prebuilt aarch64 artifact failing to compile in place, or a broken cross venv path. **A native arm64 machine erases this class.**
- **B architecture-inherent** — arm64 genuinely lacks something. Basis: upstream publishes the image or package for amd64 only. Known members: `p4lang/behavioral-model:latest` is amd64-only, and the ONIE recovery ISOs in `platform/vs/onie.mk` exist only for x86_64.
- **C port assumption** — an amd64 assumption introduced by `202605_resolute` itself. Known member: `gcc-multilib` at `sonic-slave-resolute/Dockerfile.j2:575` (not executed on the cross path, so this probe does not hit it).

- [ ] **Step 2: Compute the shares and draw the conclusion**

Apply the design document's decision rule: if class A dominates, a native machine is worth acquiring because that whole class disappears for free; if B/C dominate, the machine buys nothing the code changes would not, so fix it in place.

- [ ] **Step 3: Write the report (both languages)**

The report belongs in the `docs/superpowers/` root, alongside the existing validation reports (for example `2026-07-26-dut02-s5232f-validation-report-{zh,en}.md`). The two files carry fully corresponding content; neither is a summary of the other. Each contains:

1. Which gate the probe actually reached, elapsed time, resources consumed
2. The complete failure table: failing target / essence of the error / A, B or C / basis for the classification
3. The share of each class
4. The verdict on how necessary a native arm64 machine is
5. If the verdict is that one is needed, the machine specification it requires (cores, memory, disk, network reachability)

Do not write a revision history of the document itself.

- [ ] **Step 4: Commit the report**

The documentation repository is `/home/sheldon-qi/sonic-buildimage` (branch `202605_resolute_doc`), a different checkout from the build repository. Use `git -C` explicitly, or the commit may land in the wrong repository:

```bash
git -C /home/sheldon-qi/sonic-buildimage add \
  docs/superpowers/2026-09-23-resolute-arm64-cross-probe-report-zh.md \
  docs/superpowers/2026-09-23-resolute-arm64-cross-probe-report-en.md
git -C /home/sheldon-qi/sonic-buildimage commit -m "docs(resolute): report the arm64 vs cross-build probe results"
git -C /home/sheldon-qi/sonic-buildimage log -1 --format='%h %G? %s'
```

Expected: the last command prints a `G` (good signature). That repository already has `commit.gpgsign=true`.

- [ ] **Step 5: Report the resources held**

Once the verdict exists, report what the probe is still holding:

```bash
df -h / | tail -1
docker images --format '{{.Repository}}:{{.Tag}}' | grep march-arm64
```

Whether to keep the probe worktree, the `probe/arm64-vs-cross` branch, `/var/cache/sonic/artifacts-arm64` and the march dockerd data directory depends on whether arm64 work continues. That call belongs to a person; this step reports the usage and deletes nothing on its own.
