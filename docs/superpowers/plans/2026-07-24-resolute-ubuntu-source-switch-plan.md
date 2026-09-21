# Ubuntu Source-Base Switch — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Switch 14 SONiC self-built packages from Debian/non-distro source to Ubuntu 26.04 source packages, re-applying SONiC functional patches on top.

**Architecture:** Track A (9 packages) first — 6 true-dget packages change URL + version + keep stg, 3 non-dget packages rewrite to dget + quilt. Track C (5 packages) second — extract patches from non-distro sources, write dget Makefiles; sedutil gets full de-fork (libnl3 pattern) IF Ubuntu packages it. Validation: per-package Gate 1 (single-pkg build), per-track Gate 2 (full clean VS+Broadcom build), per-track Gate 3 (VS KVM boot).

**Tech Stack:** Bash, Make, dget, quilt, stg, dpkg-buildpackage, Docker (sg docker), KVM (testbed-cli.sh)

## Global Constraints

- **NO push to remote** — all commits stay local until explicitly authorized
- One git commit per package: `de-fork <pkg>: switch source to Ubuntu`
- Track A must be fully validated (all 9 packages + Gate 2 + Gate 3) before starting Track C
- Fix-loop policy: build failure → locate root cause → commit fix → `make reset` → rebuild from scratch (per clean-rebuild spec Section 7.2)
- `dget -u` is mandatory for all Ubuntu dget operations (see [[sonic-resolute-dget-u-necessity]])
- Patch evaluation: use shared methodology (Section 4 of spec)
- Working repo: `/home/sheldon-qi/sonic-buildimage-resolute`, branch `202605_resolute`
- All 6 Track A true-dget packages use the **same pattern**: `dget` → `git init` + `git add -f *` + `git commit` → `stg init` + `stg import -s ../patch/series` → `dpkg-buildpackage`. This pattern is preserved throughout — only the URL and version change.

---

## Phase 0: Environment Setup

### Task 0.1: Verify build environment

- [ ] Confirm docker group access:
```bash
sg docker -c 'docker ps' | head -2
```
Expected: shows running containers (or empty, no permission error)

- [ ] Confirm host fixes in place:
```bash
lsmod | grep ip_tables && cat /etc/apparmor.d/local/gs
```
Expected: ip_tables module loaded AND AppArmor gs override exists

- [ ] Confirm passwordless sudo:
```bash
sudo -n true
```
Expected: exit 0, no password prompt

- [ ] Confirm git clean:
```bash
cd /home/sheldon-qi/sonic-buildimage-resolute && git status --short
```
Expected: clean (no output). If dirty, stash or commit first.

### Task 0.2: Record pre-switch baseline

- [ ] Record current git HEAD for rollback:
```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
git rev-parse HEAD > /tmp/ubuntu-switch-baseline-commit.txt
cat /tmp/ubuntu-switch-baseline-commit.txt
```

- [ ] Record current .deb versions for rollback reference:
```bash
for pkg in isc-dhcp kdump-tools libteam lm-sensors lldpd openssh \
           initramfs-tools monit rasdaemon; do
  ls -lh target/debs/resolute/${pkg}* 2>/dev/null || echo "$pkg: not yet built"
done
for pkg in flashrom frr libpam-radius-auth sedutil wpasupplicant; do
  ls -lh target/debs/resolute/${pkg}* 2>/dev/null || echo "$pkg: not yet built"
done
```

---

## Phase 1: Track A — 6 True-dget Packages (URL + Version Change)

These 6 packages all use the **identical pattern**: `dget` from Debian → `git init` + `git add -f *` + `git commit` → `stg init` → `stg import -s ../patch/series` → `dpkg-buildpackage`. The only changes needed are the dget URL and version variables. The stg mechanism is preserved as-is.

### Task A.1: isc-dhcp — dget URL + version switch

**Files:**
- Modify: `src/isc-dhcp/Makefile:13` (dget URL)
- Modify: `rules/isc-dhcp.mk:1-2` (version variables)

**Current state:** 18 stg patches. Also has LTO disabled (`DEB_CFLAGS_MAINT_STRIP`, `DEB_LDFLAGS_MAINT_STRIP` — same pattern as sonic-frr). Keep these LTO flags.

**Version scheme:** `ISC_DHCP_VERSION = 4.4.3-P1`, `ISC_DHCP_VERSION_FULL = ${ISC_DHCP_VERSION}-2`

**Pre-flight:**

- [ ] Check Ubuntu source version:
```bash
apt-cache showsrc isc-dhcp 2>/dev/null | grep ^Version | head -3
```
Expected: shows Ubuntu 26.04 version (e.g., `4.4.3-P1-2ubuntu1` or similar).

- [ ] Check Ubuntu pool directory:
```bash
apt-cache showsrc isc-dhcp 2>/dev/null | grep ^Directory | head -1
# Should be something like: pool/main/i/isc-dhcp/
```

**Edit `src/isc-dhcp/Makefile`:**

- [ ] Change dget URL on line 13:

Old:
```makefile
	dget -u http://deb.debian.org/debian/pool/main/i/isc-dhcp/isc-dhcp_$(ISC_DHCP_VERSION_FULL).dsc
```

New:
```makefile
	dget -u http://archive.ubuntu.com/ubuntu/pool/main/i/isc-dhcp/isc-dhcp_$(ISC_DHCP_VERSION_FULL).dsc
```

- [ ] The rest of the Makefile stays unchanged: `git init`, `git add -f *`, `git commit`, `stg init`, `stg import -s ../patch/series`, LTO disable flags, `dpkg-buildpackage`.

**Edit `rules/isc-dhcp.mk`:**

- [ ] Update version variables (lines 1-2) to match Ubuntu. Example if Ubuntu version is `4.4.3-P1-2ubuntu1`:

```makefile
ISC_DHCP_VERSION = 4.4.3-P1
ISC_DHCP_VERSION_FULL = ${ISC_DHCP_VERSION}-2ubuntu1
```

Note: `ISC_DHCP_VERSION` is the upstream part (before the final hyphen); `ISC_DHCP_VERSION_FULL` adds the Debian/Ubuntu revision. The split matters because the dget extracts to `isc-dhcp-$(ISC_DHCP_VERSION)` directory (Makefile line 10: `rm -rf ./isc-dhcp-$(ISC_DHCP_VERSION)`). Verify the Ubuntu .dsc extracts to the same directory name.

**Patch evaluation:**

- [ ] 18 patches in `src/isc-dhcp/patch/series`. After first Gate 1 build attempt, stg will report which patches fail to apply. For each failure, triage per spec Section 4 methodology.

**Gate 1:**

- [ ] Build the single package:
```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
sg docker -c 'make target/debs/resolute/isc-dhcp-relay_$(ISC_DHCP_VERSION_FULL)_amd64.deb'
```

- [ ] Verify output:
```bash
ls -lh target/debs/resolute/isc-dhcp-relay_*.deb target/debs/resolute/isc-dhcp-relay-dbgsym_*.deb
dpkg-deb -c target/debs/resolute/isc-dhcp-relay_*.deb | head -20
```

**Commit:**

- [ ] Commit the source switch:
```bash
git add src/isc-dhcp/Makefile rules/isc-dhcp.mk
git add src/isc-dhcp/patch/ 2>/dev/null || true
git commit -m "de-fork isc-dhcp: switch source from Debian to Ubuntu"
```

---

### Task A.2: kdump-tools — dget URL + version switch

**Files:**
- Modify: `src/kdump-tools/Makefile:12` (dget URL)
- Modify: `rules/kdump-tools.mk:3` (version variable)

**Current state:** 4 stg patches. Uses single version variable `KDUMP_TOOLS_VERSION` (not `_FULL`). Has unused `KDUMP_TOOLS_VERSION_BASE` export — leave as-is (harmless dead code).

**Version scheme:** `KDUMP_TOOLS_VERSION = 1.10.7`

**Pre-flight:**

- [ ] Check Ubuntu source version:
```bash
apt-cache showsrc kdump-tools 2>/dev/null | grep ^Version | head -3
```
Note: kdump-tools uses `$(KDUMP_TOOLS_VERSION)` directly in both the dget URL and the `rm -rf` glob (line 9: `rm -rf ./kdump-tools-$(KDUMP_TOOLS_VERSION)*`). The Ubuntu version must match the .dsc filename exactly (e.g., `1.10.7ubuntu1`).

**Edit `src/kdump-tools/Makefile`:**

- [ ] Change dget URL on line 12:

Old:
```makefile
	dget -u https://deb.debian.org/debian/pool/main/k/kdump-tools/kdump-tools_$(KDUMP_TOOLS_VERSION).dsc
```

New:
```makefile
	dget -u http://archive.ubuntu.com/ubuntu/pool/main/k/kdump-tools/kdump-tools_$(KDUMP_TOOLS_VERSION).dsc
```

Note: also changes `https` → `http` (Debian uses https, Ubuntu archive uses http).

**Edit `rules/kdump-tools.mk`:**

- [ ] Update version (line 3). Example if Ubuntu version is `1.10.7ubuntu1`:

```makefile
KDUMP_TOOLS_VERSION = 1.10.7ubuntu1
```

**Patch evaluation:**

- [ ] 4 patches in `src/kdump-tools/patch/series`. Triage per methodology.

**Gate 1:**

- [ ] Build and verify:
```bash
sg docker -c 'make target/debs/resolute/kdump-tools_$(KDUMP_TOOLS_VERSION)_amd64.deb'
ls -lh target/debs/resolute/kdump-tools_*.deb
```

**Commit:**

- [ ] `git add src/kdump-tools/Makefile rules/kdump-tools.mk src/kdump-tools/patch/` then `git commit -m "de-fork kdump-tools: switch source from Debian to Ubuntu"`

---

### Task A.3: libteam — dget URL + version switch

**Files:**
- Modify: `src/libteam/Makefile:18` (dget URL)
- Modify: `rules/libteam.mk:1-2` (version variables)

**Current state:** 18 stg patches. 6 derived targets (libteam-dev, libteamdctl0, libteam-utils, + 3 dbgsym). Uses `:=` (immediate expansion) for version variables.

**Version scheme:** `LIBTEAM_VERSION := 1.31`, `LIBTEAM_VERSION_FULL := $(LIBTEAM_VERSION)-1`

**Pre-flight:**

- [ ] Check Ubuntu source version:
```bash
apt-cache showsrc libteam 2>/dev/null | grep ^Version | head -3
```

**Edit `src/libteam/Makefile`:**

- [ ] Change dget URL on line 18:

Old:
```makefile
	dget -u https://deb.debian.org/debian/pool/main/libt/libteam/libteam_$(LIBTEAM_VERSION_FULL).dsc
```

New:
```makefile
	dget -u http://archive.ubuntu.com/ubuntu/pool/main/libt/libteam/libteam_$(LIBTEAM_VERSION_FULL).dsc
```

**Edit `rules/libteam.mk`:**

- [ ] Update versions. Maintain `:=` style. Example if Ubuntu version is `1.31-1ubuntu1`:

```makefile
LIBTEAM_VERSION := 1.31
LIBTEAM_VERSION_FULL := $(LIBTEAM_VERSION)-1ubuntu1
```

Note: directory extract uses `libteam-$(LIBTEAM_VERSION)` (line 15). Make sure Ubuntu's .dsc extracts the same way.

**Patch evaluation:**

- [ ] 18 patches. Triage per methodology.

**Gate 1:**

- [ ] Build and verify:
```bash
sg docker -c 'make target/debs/resolute/libteam5_$(LIBTEAM_VERSION_FULL)_amd64.deb'
ls -lh target/debs/resolute/libteam*_*.deb
# Expected: 7 .deb files (main + 6 derived)
```

**Commit:**

- [ ] `git add src/libteam/Makefile rules/libteam.mk src/libteam/patch/` then `git commit -m "de-fork libteam: switch source from Debian to Ubuntu"`

---

### Task A.4: lm-sensors — dget URL + version switch

**Files:**
- Modify: `src/lm-sensors/Makefile:16` (dget URL)
- Modify: `rules/lm-sensors.mk:1-7` (version variables)

**Current state:** 2 stg patches. Uses split version scheme (MAJOR/MINOR/PATCH + LIBSENSORS_VERSION for SO name). dget from `http://deb.debian.org` (http, not https — only package using plain http). Has `DEB_BUILD_OPTIONS=nocheck PROG_EXTRA=sensord` for native build and `PROG_EXTRA=sensord` (without nocheck) for cross-build.

**Version scheme:** `LM_SENSORS_VERSION=3.6.0`, `LM_SENSORS_VERSION_FULL=3.6.0-7.1`, `LIBSENSORS_VERSION=5`

**Pre-flight:**

- [ ] Check Ubuntu source version:
```bash
apt-cache showsrc lm-sensors 2>/dev/null | grep ^Version | head -3
```
Ubuntu 26.04 likely has `1:3.6.2-2build1` or similar with epoch `1:`.

- [ ] Check if Ubuntu provides sensord:
```bash
apt-cache show sensord 2>/dev/null | grep ^Package
```
If sensord is already a separate binary package in Ubuntu, the 2 SONiC patches (which enable sensord build) may be droppable.

- [ ] Check SO version of libsensors:
```bash
apt-cache show libsensors5 2>/dev/null | grep ^Version
# Also try libsensors4 or libsensors6
```

**Edit `src/lm-sensors/Makefile`:**

- [ ] Change dget URL on line 16:

Old:
```makefile
	dget -u http://deb.debian.org/debian/pool/main/l/lm-sensors/lm-sensors_$(LM_SENSORS_VERSION_FULL).dsc
```

New:
```makefile
	dget -u http://archive.ubuntu.com/ubuntu/pool/main/l/lm-sensors/lm-sensors_$(LM_SENSORS_VERSION_FULL).dsc
```

- [ ] Keep `git init` + `stg` pattern unchanged. Keep `PROG_EXTRA=sensord` and `DEB_BUILD_OPTIONS=nocheck` unchanged.

**Edit `rules/lm-sensors.mk`:**

- [ ] Update version variables. Example if Ubuntu version is `1:3.6.2-2build1`:

```makefile
LM_SENSORS_MAJOR_VERSION = 3
LM_SENSORS_MINOR_VERSION = 6
LM_SENSORS_PATCH_VERSION = 2
LIBSENSORS_VERSION = 5
LM_SENSORS_VERSION=$(LM_SENSORS_MAJOR_VERSION).$(LM_SENSORS_MINOR_VERSION).$(LM_SENSORS_PATCH_VERSION)
LM_SENSORS_VERSION_FULL=$(LM_SENSORS_VERSION)-2build1
```

⚠️ **Epoch warning:** If Ubuntu has epoch `1:`, the dget URL uses the version WITHOUT the epoch (e.g., `lm-sensors_3.6.2-2build1.dsc`), but the .deb filename and directory name use the version WITH the epoch. Check the actual .dsc filename:
```bash
apt-cache showsrc lm-sensors 2>/dev/null | grep -E '^Directory'
# Look at the .dsc filename in the pool directory
```
If the .dsc filename omits the epoch, `LM_SENSORS_VERSION_FULL` should also omit it. The epoch only appears in the .deb filename, which is handled by dpkg-buildpackage automatically.

**Patch evaluation:**

- [ ] 2 patches (enabling sensord daemon build). If Ubuntu already provides `sensord` as a separate binary, both patches may DROP entirely. Try without patches first; if sensord is already built by Ubuntu, no patches needed.

**Gate 1:**

- [ ] Build and verify:
```bash
sg docker -c 'make target/debs/resolute/lm-sensors_$(LM_SENSORS_VERSION_FULL)_amd64.deb'
ls -lh target/debs/resolute/lm-sensors*_*.deb target/debs/resolute/sensord*_*.deb target/debs/resolute/libsensors*_*.deb
```

**Commit:**

- [ ] `git add src/lm-sensors/Makefile rules/lm-sensors.mk src/lm-sensors/patch/` then `git commit -m "de-fork lm-sensors: switch source from Debian to Ubuntu"`

---

### Task A.5: lldpd — dget URL + version switch

**Files:**
- Modify: `src/lldpd/Makefile:8` (LLDP_URL variable)
- Modify: `rules/lldpd.mk:1-3` (version variables)

**Current state:** 3 stg patches. Uses `BUILD_PUBLIC_URL` (= `https://packages.trafficmanager.net/public`) as the URL base, with separate DSC_FILE/ORIG_FILE/DEBIAN_FILE variables. Has env vars `with_netlink_receive_bufsize=2*1024*1024` and `with_netlink_max_receive_bufsize=4*1024*1024` for `dpkg-buildpackage`.

**Version scheme:** `LLDPD_VERSION = 1.0.16`, `LLDPD_VERSION_SUFFIX = 1+deb12u1`, `LLDPD_VERSION_FULL = $(LLDPD_VERSION)-$(LLDPD_VERSION_SUFFIX)` → resolves to `1.0.16-1+deb12u1`

**Pre-flight:**

- [ ] Check Ubuntu source version:
```bash
apt-cache showsrc lldpd 2>/dev/null | grep ^Version | head -3
```

**Edit `src/lldpd/Makefile`:**

- [ ] Change the LLDP_URL variable on line 8:

Old:
```makefile
LLDP_URL = $(BUILD_PUBLIC_URL)/debian/pool/main/l/lldpd
```

New:
```makefile
LLDP_URL = http://archive.ubuntu.com/ubuntu/pool/main/l/lldpd
```

- [ ] The DSC_FILE, ORIG_FILE, DEBIAN_FILE, and DSC_FILE_URL/ORIG_FILE_URL/DEBIAN_FILE_URL variables stay unchanged — they compose from LLDP_URL.
- [ ] `dget -u $(DSC_FILE_URL)` on line 23 stays unchanged.
- [ ] Keep `git init` + `stg` pattern and env vars unchanged.

**Edit `rules/lldpd.mk`:**

- [ ] Update version variables. If Ubuntu has a clean version (no `+deb12u1`-style suffix), simplify:

Old:
```makefile
LLDPD_VERSION = 1.0.16
LLDPD_VERSION_SUFFIX = 1+deb12u1
LLDPD_VERSION_FULL = $(LLDPD_VERSION)-$(LLDPD_VERSION_SUFFIX)
```

New (example if Ubuntu version is `1.0.18-1ubuntu1`):
```makefile
LLDPD_VERSION = 1.0.18
LLDPD_VERSION_FULL = $(LLDPD_VERSION)-1ubuntu1
```

Check if `LLDPD_VERSION_SUFFIX` is used elsewhere:
```bash
grep -r 'LLDPD_VERSION_SUFFIX' rules/ 2>/dev/null
```
If only used in `rules/lldpd.mk`, remove the variable. If used elsewhere (e.g., in other .mk or .j2 files), keep a simplified version.

**Patch evaluation:**

- [ ] 3 patches in `src/lldpd/patch/series`. The audit says one (socket separation) may be upstreamed in lldpd 1.0.18+. Triage per methodology.

**Gate 1:**

- [ ] Build with SONiC-specific env vars preserved:
```bash
sg docker -c 'make target/debs/resolute/lldpd_$(LLDPD_VERSION_FULL)_amd64.deb'
ls -lh target/debs/resolute/lldpd*_*.deb
```

**Commit:**

- [ ] `git add src/lldpd/Makefile rules/lldpd.mk src/lldpd/patch/` then `git commit -m "de-fork lldpd: switch source from Debian to Ubuntu"`

---

### Task A.6: openssh — dget URL + version switch

**Files:**
- Modify: `src/openssh/Makefile:17` (dget URL)
- Modify: `rules/openssh.mk:1-2` (version variables)

**Current state:** 4 stg patches + 1 separate cross-compile patch (`patch -p1 < ../patch/cross-compile-changes.patch` on line 31, only when `CROSS_BUILD_ENVIRON=y`). 5 derived targets (openssh-client, openssh-sftp-server, + 3 dbgsym).

**Version scheme:** `OPENSSH_VERSION := 10.0p1`, `OPENSSH_VERSION_FULL := $(OPENSSH_VERSION)-7`

**Pre-flight:**

- [ ] Check Ubuntu source version:
```bash
apt-cache showsrc openssh 2>/dev/null | grep ^Version | head -3
```
Ubuntu 26.04 likely has `10.2p1-1ubuntu1` or similar.

**Edit `src/openssh/Makefile`:**

- [ ] Change dget URL on line 17:

Old:
```makefile
	dget -u https://deb.debian.org/debian/pool/main/o/openssh/openssh_$(OPENSSH_VERSION_FULL).dsc
```

New:
```makefile
	dget -u http://archive.ubuntu.com/ubuntu/pool/main/o/openssh/openssh_$(OPENSSH_VERSION_FULL).dsc
```

- [ ] Keep `git init` + `stg` pattern unchanged. Keep cross-compile guard (`ifeq ($(CROSS_BUILD_ENVIRON), y)`) unchanged.

**Edit `rules/openssh.mk`:**

- [ ] Update versions. Example if Ubuntu version is `10.2p1-1ubuntu1`:

```makefile
OPENSSH_VERSION := 10.2p1
OPENSSH_VERSION_FULL := $(OPENSSH_VERSION)-1ubuntu1
```

Note: directory extract uses `openssh-$(OPENSSH_VERSION)` (line 14). Verify Ubuntu's .dsc extracts to the same directory name.

**Patch evaluation:**

- [ ] 4 patches in `src/openssh/patch/series` + 1 cross-compile patch. For the 4 stg patches:
  1. Remote auth info export — SONiC-specific, likely needs adaptation
  2. Session env — SONiC-specific
  3. Revert ClientAliveCountMax — evaluate against Ubuntu version
  4. Fourth patch — evaluate

The cross-compile patch is only used when `CROSS_BUILD_ENVIRON=y` — leave the ifeq block intact, do NOT add to stg series.

**Gate 1:**

- [ ] Build and verify:
```bash
sg docker -c 'make target/debs/resolute/openssh-server_$(OPENSSH_VERSION_FULL)_amd64.deb'
ls -lh target/debs/resolute/openssh*_*.deb
# Expected: 6 .deb files (server + client + sftp-server + 3 dbgsym)
```

**Commit:**

- [ ] `git add src/openssh/Makefile rules/openssh.mk src/openssh/patch/` then `git commit -m "de-fork openssh: switch source from Debian to Ubuntu"`

---

## Phase 2: Track A — 3 Pseudo Packages (Non-dget → dget Rewrite)

These 3 packages do NOT use dget as their source-acquisition mechanism. They need a full Makefile rewrite to the dget + quilt pattern, plus converting their patches to quilt format.

### Task A.7: initramfs-tools — tarball + sha256 → dget + quilt

**Files:**
- Rewrite: `src/initramfs-tools/Makefile` (tarball + sha256 + QUILT_PATCHES=.. → dget + quilt)
- Modify: `rules/initramfs-tools.mk:1` (version variable)
- Reorganize: `src/initramfs-tools/*.patch` + `src/initramfs-tools/series` → `src/initramfs-tools/patch/`

**Current state:** Downloads a pinned tarball from `salsa.debian.org/kernel-team/initramfs-tools/-/archive/v0.142/` with SHA256 verification. 2 patches + `series` file directly in `src/initramfs-tools/` (not in a `patch/` subdirectory). Uses `QUILT_PATCHES=.. quilt push -a` (quilt reads series from parent directory). This is already quilt, not stg — only the source acquisition needs changing.

**Version scheme:** `INITRAMFS_TOOLS_VERSION = 0.142` (single variable, no `_FULL` suffix)

**Pre-flight:**

- [ ] Check Ubuntu source version:
```bash
apt-cache showsrc initramfs-tools 2>/dev/null | grep ^Version | head -3
```

- [ ] Check Ubuntu pool path (should be `pool/main/i/initramfs-tools/`):
```bash
apt-cache showsrc initramfs-tools 2>/dev/null | grep ^Directory | head -1
```

**Reorganize patches:**

- [ ] Move patches into a `patch/` subdirectory for standard quilt layout:
```bash
cd src/initramfs-tools
mkdir -p patch
mv loopback-file-offset-support.patch patch/
mv loopback-file-system-support.patch patch/
mv series patch/
# Verify
ls patch/
cat patch/series
```

**Rewrite `src/initramfs-tools/Makefile`:**

- [ ] Replace the entire file. Remove tarball URL, SHA256, wget, tar, mv steps. Add dget. Keep quilt (not stg — this package already uses quilt).

```makefile
.ONESHELL:
SHELL = /bin/bash
.SHELLFLAGS += -e

MAIN_TARGET = initramfs-tools_$(INITRAMFS_TOOLS_VERSION)_all.deb
DERIVED_TARGETS = initramfs-tools-core_$(INITRAMFS_TOOLS_VERSION)_all.deb

$(addprefix $(DEST)/, $(MAIN_TARGET)): $(DEST)/% :
	# Remove any stale files
	rm -rf ./initramfs-tools-*

	# Get initramfs-tools from Ubuntu
	dget -u http://archive.ubuntu.com/ubuntu/pool/main/i/initramfs-tools/initramfs-tools_$(INITRAMFS_TOOLS_VERSION).dsc

	# Apply patches
	pushd initramfs-tools-*
	QUILT_PATCHES=../patch quilt push -a

	# Build the package
	rm -f debian/*.debhelper.log
ifeq ($(CROSS_BUILD_ENVIRON), y)
	dpkg-buildpackage -rfakeroot -b -us -uc -a$(CONFIGURED_ARCH) -Pcross,nocheck -j$(SONIC_CONFIG_MAKE_JOBS) --admindir $(SONIC_DPKG_ADMINDIR)
else
	dpkg-buildpackage -rfakeroot -b -us -uc -j$(SONIC_CONFIG_MAKE_JOBS) --admindir $(SONIC_DPKG_ADMINDIR)
endif
	popd

	mv $(DERIVED_TARGETS) $* $(DEST)/

$(addprefix $(DEST)/, $(DERIVED_TARGETS)): $(DEST)/% : $(DEST)/$(MAIN_TARGET)
```

Key changes from old:
- Remove `INITRAMFS_TOOLS_TARBALL_URL` and `INITRAMFS_TOOLS_TARBALL_SHA256` variables
- Remove `wget`, `sha256sum -c`, `tar xzf`, `mv`, `rm -f ...tar.gz` steps
- Add `dget -u` step
- Change `pushd ./initramfs-tools` → `pushd initramfs-tools-*` (dget extracts differently)
- Keep `QUILT_PATCHES=../patch quilt push -a` (patches now in `patch/` subdir)
- Keep `rm -f debian/*.debhelper.log` and cross-compile guard

**Edit `rules/initramfs-tools.mk`:**

- [ ] Update version. Example if Ubuntu version is `0.142ubuntu1`:

```makefile
INITRAMFS_TOOLS_VERSION = 0.142ubuntu1
```

**Patch evaluation:**

- [ ] 2 patches (loopback file offset support + loopback file system support). Both are SONiC-specific (for ONIE/SONiC installer). They're unlikely to be upstreamed. Try to apply via quilt — if they fail, manually adapt.

**Gate 1:**

- [ ] Build and verify:
```bash
sg docker -c 'make target/debs/resolute/initramfs-tools_$(INITRAMFS_TOOLS_VERSION)_all.deb'
ls -lh target/debs/resolute/initramfs-tools*_*.deb
```

**Commit:**

- [ ] `git add src/initramfs-tools/Makefile src/initramfs-tools/patch/ rules/initramfs-tools.mk` then `git commit -m "de-fork initramfs-tools: switch source from Debian to Ubuntu (tarball→dget)"`

---

### Task A.8: monit — git clone + stg → dget + quilt

**Files:**
- Rewrite: `src/monit/Makefile` (git clone + stg → dget + quilt)
- Modify: `rules/monit.mk:1` (version variable)
- Reorganize: `src/monit/patch/series` (remove commented-out entries for quilt)

**Current state:** `git clone https://salsa.debian.org/debian/monit.git` → `git reset --hard debian/1%<version>` → `stg init` → `stg import -s ../patch/series` → (if cross) `patch -p1 < ../patch/cross-compile-changes.patch` → `dpkg-buildpackage`.

The stg series has 3 entries but only 1 is active (0002-change_monit_alert_log_error.patch). 0001 (MemAvailable) and 0003 (yacc header fix) are commented out — they were disabled during the resolute port (functionality upstreamed). Plus 1 cross-compile-changes.patch applied separately outside stg.

**Version scheme:** `MONIT_VERSION = 5.34.3-1` (single variable)

**Pre-flight:**

- [ ] Check Ubuntu source version:
```bash
apt-cache showsrc monit 2>/dev/null | grep ^Version | head -3
```

**Prepare quilt series:**

- [ ] Create a clean quilt series from the active stg patches only. The old series has commented-out entries — quilt doesn't support `#` comments in series files the same way, so create a clean one:
```bash
cd src/monit
# Create clean series with only active patches (exclude commented-out and cross-compile)
echo "0002-change_monit_alert_log_error.patch" > patch/series.quilt
# Keep the original series as backup
cp patch/series patch/series.stg.bak
mv patch/series.quilt patch/series
cat patch/series
```

**Rewrite `src/monit/Makefile`:**

- [ ] Replace the entire file:

```makefile
.ONESHELL:
SHELL = /bin/bash
.SHELLFLAGS += -e

MAIN_TARGET = monit_$(MONIT_VERSION)_$(CONFIGURED_ARCH).deb
DERIVED_TARGETS = monit-dbgsym_$(MONIT_VERSION)_$(CONFIGURED_ARCH).deb

$(addprefix $(DEST)/, $(MAIN_TARGET)): $(DEST)/% :
	# Remove any stale files
	rm -rf ./monit-*

	# Get monit from Ubuntu
	dget -u http://archive.ubuntu.com/ubuntu/pool/main/m/monit/monit_$(MONIT_VERSION).dsc

	# Apply patches
	pushd monit-*
	quilt push -a

ifeq ($(CROSS_BUILD_ENVIRON), y)
	patch -p1 < ../patch/cross-compile-changes.patch
	dpkg-buildpackage -rfakeroot -b -us -uc --host-arch $(CONFIGURED_ARCH) -Pcross,nocheck -j$(SONIC_CONFIG_MAKE_JOBS) --admindir $(SONIC_DPKG_ADMINDIR)
else
	dpkg-buildpackage -rfakeroot -b -us -uc -j$(SONIC_CONFIG_MAKE_JOBS) --admindir $(SONIC_DPKG_ADMINDIR)
endif
	popd

	mv $(DERIVED_TARGETS) $* $(DEST)/

$(addprefix $(DEST)/, $(DERIVED_TARGETS)): $(DEST)/% : $(DEST)/$(MAIN_TARGET)
```

Key changes:
- Remove `git clone https://salsa.debian.org/debian/monit.git`
- Remove `git reset --hard debian/1\%$(MONIT_VERSION)` (the `1%` tag prefix was a Debian-specific convention)
- Add `dget -u` step
- Change `stg init` + `stg import -s ../patch/series` → `quilt push -a`
- `pushd ./monit` → `pushd monit-*`
- Cross-compile patch stays separate (outside quilt series), only applied when `CROSS_BUILD_ENVIRON=y`

**Edit `rules/monit.mk`:**

- [ ] Update version. Example if Ubuntu version is `5.34.3-1ubuntu1`:

```makefile
MONIT_VERSION = 5.34.3-1ubuntu1
```

**Patch evaluation:**

- [ ] Only 1 active stg patch (0002: change monit alert log error). The 2 commented-out patches (0001 MemAvailable, 0003 yacc header) are already upstreamed — keep them commented out as reference but do NOT add to quilt series.
- [ ] 0002 (alert log severity change) is SONiC-specific. Try to apply via quilt against Ubuntu source.
- [ ] Cross-compile-changes.patch: only used for cross-builds, keep as-is.

**Gate 1:**

- [ ] Build and verify:
```bash
sg docker -c 'make target/debs/resolute/monit_$(MONIT_VERSION)_amd64.deb'
ls -lh target/debs/resolute/monit*_*.deb
```

**Commit:**

- [ ] `git add src/monit/Makefile src/monit/patch/ rules/monit.mk` then `git commit -m "de-fork monit: switch source from Debian to Ubuntu (git clone→dget)"`

---

### Task A.9: rasdaemon — git clone + git apply → dget + quilt

**Files:**
- Rewrite: `src/rasdaemon/Makefile` (git clone + git apply → dget + quilt)
- Modify: `rules/rasdaemon.mk:1` (version variable)
- Reorganize: `src/rasdaemon/*.patch` → `src/rasdaemon/patch/`

**Current state:** `git clone https://salsa.debian.org/tai271828/rasdaemon.git` → `git checkout <commit>` → `git apply ../0001-....patch` → `git apply ../0002-....patch` → `dpkg-buildpackage`. No stg, no quilt — raw git apply. 2 patches + no series file.

**Version scheme:** `RASDAEMON_VERSION = 0.6.8-1` (single variable)

**Pre-flight:**

- [ ] Check Ubuntu source version:
```bash
apt-cache showsrc rasdaemon 2>/dev/null | grep ^Version | head -3
```

**Convert patches to quilt format:**

- [ ] Move patches to standard `patch/` directory and create series:
```bash
cd src/rasdaemon
mkdir -p patch
mv 0001-Check-CPUs-online-not-configured.patch patch/
mv 0002-Keep-one-address-in-Maintainer-field.patch patch/
echo "0001-Check-CPUs-online-not-configured.patch" > patch/series
echo "0002-Keep-one-address-in-Maintainer-field.patch" >> patch/series
cat patch/series
```

**Rewrite `src/rasdaemon/Makefile`:**

- [ ] Replace the entire file:

```makefile
.ONESHELL:
SHELL = /bin/bash
.SHELLFLAGS += -e

MAIN_TARGET = rasdaemon_$(RASDAEMON_VERSION)_$(CONFIGURED_ARCH).deb
DERIVED_TARGETS = rasdaemon-dbgsym_$(RASDAEMON_VERSION)_$(CONFIGURED_ARCH).deb

$(addprefix $(DEST)/, $(MAIN_TARGET)): $(DEST)/% :
	# Remove any stale files
	rm -rf ./rasdaemon-*

	# Get rasdaemon from Ubuntu
	dget -u http://archive.ubuntu.com/ubuntu/pool/main/r/rasdaemon/rasdaemon_$(RASDAEMON_VERSION).dsc

	# Apply patches
	pushd rasdaemon-*
	quilt push -a

ifeq ($(CROSS_BUILD_ENVIRON), y)
	dpkg-buildpackage -rfakeroot -b -us -uc -a$(CONFIGURED_ARCH) -Pcross,nocheck -j$(SONIC_CONFIG_MAKE_JOBS) --admindir $(SONIC_DPKG_ADMINDIR)
else
	dpkg-buildpackage -rfakeroot -b -us -uc -j$(SONIC_CONFIG_MAKE_JOBS) --admindir $(SONIC_DPKG_ADMINDIR)
endif
	popd

	mv $(DERIVED_TARGETS) $* $(DEST)/

$(addprefix $(DEST)/, $(DERIVED_TARGETS)): $(DEST)/% : $(DEST)/$(MAIN_TARGET)
```

Key changes:
- Remove `RASDAEMON_COMMIT` variable, `git clone`, `git checkout` steps
- Add `dget -u` step
- Convert `git apply ../0001-....patch` + `git apply ../0002-....patch` → `quilt push -a`
- `pushd ./rasdaemon` → `pushd rasdaemon-*`

**Edit `rules/rasdaemon.mk`:**

- [ ] Update version. Example if Ubuntu version is `0.6.8-1ubuntu1`:

```makefile
RASDAEMON_VERSION = 0.6.8-1ubuntu1
```

**Patch evaluation:**

- [ ] 2 patches:
  1. CPU online check — likely upstreamed in newer rasdaemon → try applying; if fails, DROP
  2. Maintainer field fix — packaging-only → almost certainly DROP (Ubuntu has its own maintainer)

If both patches drop, the quilt series is empty and `quilt push -a` is a no-op. The Makefile still works correctly.

**Gate 1:**

- [ ] Build and verify:
```bash
sg docker -c 'make target/debs/resolute/rasdaemon_$(RASDAEMON_VERSION)_amd64.deb'
ls -lh target/debs/resolute/rasdaemon*_*.deb
```

**Commit:**

- [ ] `git add src/rasdaemon/Makefile src/rasdaemon/patch/ rules/rasdaemon.mk` then `git commit -m "de-fork rasdaemon: switch source from Debian to Ubuntu (git clone→dget)"`

---

### Task A.G2: Track A Gate 2 — Full clean dual-platform build

**Pre-build:**

- [ ] All 9 Track A commits are in git history:
```bash
git log --oneline | head -10
```
- [ ] `git status --short` is clean
- [ ] Run `make reset` to clear build artifacts:
```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
make BLDENV=resolute UNATTENDED=y reset
```

**VS Build:**

- [ ] Build VS image:
```bash
sg docker -c 'make PLATFORM=vs configure'
sg docker -c 'make PLATFORM=vs target/sonic-vs.img.gz' > target/build-vs-tracka.log 2>&1
```

- [ ] Monitor progress (in another terminal):
```bash
tail -f target/build-vs-tracka.log
```

- [ ] Verify VS build:
```bash
echo "Exit code: $?"
grep -i 'error' target/build-vs-tracka.log | grep -v '^#' | grep -v 'dh_strip.*error' | head -20
ls -lh target/sonic-vs.img.gz
```

**If build fails:** follow fix-loop policy:
1. Locate root cause from build log
2. Fix the issue (edit Makefile, rules, or patches)
3. Commit the fix
4. `make BLDENV=resolute UNATTENDED=y reset`
5. Rebuild from scratch

**Broadcom Build (after VS passes):**

- [ ] Build Broadcom image:
```bash
sg docker -c 'make PLATFORM=broadcom configure'
sg docker -c 'make PLATFORM=broadcom target/sonic-broadcom.bin' > target/build-broadcom-tracka.log 2>&1
```

- [ ] Verify Broadcom build:
```bash
echo "Exit code: $?"
grep -i 'error' target/build-broadcom-tracka.log | grep -v '^#' | head -20
ls -lh target/sonic-broadcom.bin
```

### Task A.G3: Track A Gate 3 — VS KVM boot verification

- [ ] Deploy VS testbed:
```bash
testbed-cli.sh add-topo vmsk <ptf-id>
testbed-cli.sh deploy-mg vmsk <ptf-id>
```
Note: replace `<ptf-id>` with actual PTF container ID from `docker ps | grep ptf`.

- [ ] SSH into VS and verify:
```bash
ssh admin@<vs-ip>
show version
# Expected: shows SONiC version, Ubuntu 26.04
```

- [ ] Check relevant services:
```bash
# Inside VS:
show services
# Check containers relevant to switched packages:
# - docker-dhcp-relay (isc-dhcp consumer)
# - docker-teamd (libteam consumer)
# - docker-platform-monitor (lm-sensors consumer)
# - lldp (lldpd consumer)
docker ps
```

- [ ] Check system health:
```bash
systemctl --failed
# Expected: no failed services
```

---

## Phase 3: Track C — Non-Distro → Ubuntu dget (5 packages)

Track C packages don't use dget at all. Each needs a different conversion strategy based on its current source mechanism. sedutil is the simplest (full de-fork, IF Ubuntu packages it). sonic-frr is the hardest (86 patches, proprietary FPM protocol).

### Task C.1: flashrom — git clone + stg → dget + quilt

**Files:**
- Rewrite: `src/flashrom/Makefile` (git clone + git checkout tag + stg → dget + quilt)
- Modify: `rules/flashrom.mk:1` (version variable)
- Reorganize: `src/flashrom/patch/` (stg→quilt series if patches survive)

**Current state:** `git clone https://github.com/flashrom/flashrom.git` → `git checkout -b flashrom-src v0.9.7` → `stg init` → `stg import -s ../patch/series` → `dpkg-buildpackage`. 3 patches. No cross-compile guard.

**Version scheme:** `FLASHROM_VERSION_FULL = 0.9.7` (git tag, not Debian/Ubuntu version scheme)

**⚠️ Risk: HIGH.** 7-year version gap (0.9.7 → Ubuntu likely 1.6.x). All 3 patches are for Intel Rangeley/Denverton CPU flash support — likely upstreamed in the intervening ~15 releases.

**Pre-flight:**

- [ ] Check Ubuntu source version:
```bash
apt-cache showsrc flashrom 2>/dev/null | grep ^Version | head -3
```

- [ ] Check Ubuntu binary packages:
```bash
apt-cache show flashrom 2>/dev/null | grep ^Version | head -3
```

**Extract and evaluate patches:**

- [ ] The 3 patches in `src/flashrom/patch/` target flashrom v0.9.7. Given the 7-year gap to Ubuntu's version (likely 1.6.x), test if any still apply:
```bash
# After dget pulls the Ubuntu source:
cd src/flashrom
# Try applying each patch
quilt push -a
# Or manually test:
patch --dry-run -p1 < patch/0001-*.patch
```
Most likely outcome: all 3 patches DROP (upstreamed or obsolete). If so, the quilt series is empty.

**Rewrite `src/flashrom/Makefile`:**

- [ ] Replace with dget + quilt pattern:

```makefile
.ONESHELL:
SHELL = /bin/bash
.SHELLFLAGS += -e

MAIN_TARGET = flashrom_$(FLASHROM_VERSION)_$(CONFIGURED_ARCH).deb
DERIVED_TARGETS = flashrom-dbgsym_$(FLASHROM_VERSION)_$(CONFIGURED_ARCH).deb

$(addprefix $(DEST)/, $(MAIN_TARGET)): $(DEST)/% :
	# Remove any stale files
	rm -rf ./flashrom-*

	# Get flashrom from Ubuntu
	dget -u http://archive.ubuntu.com/ubuntu/pool/main/f/flashrom/flashrom_$(FLASHROM_VERSION).dsc

	# Apply patches (may be empty if all patches dropped)
	quilt push -a

	pushd flashrom-*
	dpkg-buildpackage -rfakeroot -b -us -uc -j$(SONIC_CONFIG_MAKE_JOBS) --admindir $(SONIC_DPKG_ADMINDIR)
	popd

	mv $(DERIVED_TARGETS) $* $(DEST)/

$(addprefix $(DEST)/, $(DERIVED_TARGETS)): $(DEST)/% : $(DEST)/$(MAIN_TARGET)
```

Note: the old Makefile has no cross-compile guard — the new one follows the same pattern (native only, no `CROSS_BUILD_ENVIRON` check).

**Edit `rules/flashrom.mk`:**

- [ ] Update version from git-tag scheme to Ubuntu version scheme. Current uses `FLASHROM_VERSION_FULL` (no separate `_VERSION`). Check if the variable name needs to change:
```bash
grep -r 'FLASHROM_VERSION' rules/ --include='*.mk'
```

If only `FLASHROM_VERSION_FULL` is used, change to `FLASHROM_VERSION` (matching the dget Makefile convention). Example if Ubuntu version is `1.6.0-2ubuntu1`:

```makefile
FLASHROM_VERSION = 1.6.0-2ubuntu1
```

Also check if `FLASHROM_VERSION_FULL` is referenced in any .j2 or other files:
```bash
grep -r 'FLASHROM_VERSION_FULL' rules/ platform/ dockers/ --include='*.mk' --include='*.j2'
```

**Gate 1:**

- [ ] Build and verify:
```bash
sg docker -c 'make target/debs/resolute/flashrom_$(FLASHROM_VERSION)_amd64.deb'
ls -lh target/debs/resolute/flashrom*_*.deb
```

**Commit:**

- [ ] `git add src/flashrom/Makefile src/flashrom/patch/ rules/flashrom.mk` then `git commit -m "de-fork flashrom: switch source to Ubuntu dget"`

---

### Task C.2: sonic-frr — local submodule + stg → dget + quilt

**Files:**
- Rewrite: `src/sonic-frr/Makefile` (submodule-based + stg → dget + quilt)
- Modify: `rules/frr.mk` (version variables — note the rules file is `frr.mk`, not `sonic-frr.mk`)
- Reorganize: `src/sonic-frr/patch/` (stg→quilt series — 86 patches)

**Current state** (most complex package in the entire build):

1. **Source:** Local `frr/` git submodule at `src/sonic-frr/frr/`, locked to upstream tag `frr-10.5.4` with 86 stg patches applied on top.
2. **Patch management:** Hashes `patch/series` + all `patch/*.patch` files into `.sonic-frr-patch-<branch>.sha1` to detect changes and skip rebuild when unchanged.
3. **Custom code:** Copies `dplane_fpm_sonic/dplane_fpm_sonic.c` into `zebra/` directory — this is a SONiC-proprietary FPM (Forwarding Plane Manager) plugin for communicating with the ASIC.
4. **Changelog generation:** Uses `gbp dch --ignore-branch --new-version=$(FRR_VERSION)-sonic-$(FRR_SUBVERSION) --dch-opt="--force-bad-version" --commit --git-author` to generate the Debian changelog.
5. **LTO disabled:** `DEB_CFLAGS_MAINT_STRIP="-flto=auto -ffat-lto-objects"`, `DEB_LDFLAGS_MAINT_STRIP="-flto=auto -ffat-lto-objects"`.
6. **Build profiles:** `FRR_BUILD_PROFILES="pkg.frr.nortrlib"`, optionally `pkg.frr.tcmalloc` if `ENABLE_FRR_TCMALLOC=y`.
7. **4 derived targets:** frr-pythontools, frr-dbgsym, frr-snmp, frr-snmp-dbgsym.

**Version scheme** (from `rules/frr.mk`):
```makefile
FRR_VERSION = 10.5.4
FRR_SUBVERSION = 0
FRR_TAG = frr-$(FRR_VERSION)
```
.deb named: `frr_$(FRR_VERSION)-sonic-$(FRR_SUBVERSION)_$(CONFIGURED_ARCH).deb` → `frr_10.5.4-sonic-0_amd64.deb`

**⚠️ Risk: HIGHEST in entire plan.** 86 patches, SONiC-proprietary FPM protocol, complex build orchestration. This package alone may take 1-2 days of focused work.

**Pre-flight:**

- [ ] Check Ubuntu FRR source version:
```bash
apt-cache showsrc frr 2>/dev/null | grep ^Version | head -3
```
Note: Ubuntu packages FRR as `frr` (not `sonic-frr`). The Ubuntu version may be different from the upstream FRR tag SONiC uses.

**Extract patches from stg stack:**

- [ ] The 86 stg patches are in `src/sonic-frr/patch/`. Export them for quilt:
```bash
cd src/sonic-frr
# The patch files are already in patch/ directory as .patch files
# The series file lists them in order
wc -l patch/series  # should be 86
# Convert stg series to quilt series (stg series format is compatible with quilt)
# Create a backup
cp patch/series patch/series.stg.bak
```

**Rewrite `src/sonic-frr/Makefile`:**

The new Makefile must replace the submodule-based workflow with dget while preserving:
- The FPM dplane module copy (`dplane_fpm_sonic.c` → `zebra/`)
- LTO disable flags
- FRR_BUILD_PROFILES
- gbp dch changelog generation (if still needed — Ubuntu's source already has a changelog)
- Cross-compile guard
- The `.sonic-frr-patch-*.sha1` caching (optional — can be dropped for simplicity, replaced by Make's own dependency tracking)

```makefile
.ONESHELL:
SHELL = /bin/bash
.SHELLFLAGS += -e

MAIN_TARGET = $(FRR)
DERIVED_TARGET = $(FRR_PYTHONTOOLS) $(FRR_DBG) $(FRR_SNMP) $(FRR_SNMP_DBG)
DPLANE_FPM_SONIC_MODULE = dplane_fpm_sonic/dplane_fpm_sonic.c

# DEBEMAIL required by gbp dch
export DEBEMAIL := sonicproject@googlegroups.com

$(addprefix $(DEST)/, $(MAIN_TARGET)): $(DEST)/% :
	# Remove any stale files
	rm -rf ./frr-*

	# Get FRR from Ubuntu
	dget -u http://archive.ubuntu.com/ubuntu/pool/main/f/frr/frr_$(FRR_UBUNTU_VERSION).dsc

	# Apply SONiC patches on top of Ubuntu FRR
	pushd frr-*
	quilt push -a

	# Copy the sonic dplane module source file
	cp ../$(DPLANE_FPM_SONIC_MODULE) zebra/

	# Generate changelog entry for SONiC build
	gbp dch --ignore-branch --new-version=$(FRR_VERSION)-sonic-$(FRR_SUBVERSION) --dch-opt="--force-bad-version" --commit --git-author

	# Clean artifacts from previous run
	fakeroot debian/rules clean
	rm -rf build/

	# Build the package
	FRR_BUILD_PROFILES="pkg.frr.nortrlib"
ifeq ($(ENABLE_FRR_TCMALLOC), y)
	FRR_BUILD_PROFILES="$${FRR_BUILD_PROFILES},pkg.frr.tcmalloc"
endif

ifeq ($(CROSS_BUILD_ENVIRON), y)
	FRR_BUILD_PROFILES="$${FRR_BUILD_PROFILES},cross,nocheck"
	CFLAGS="-I $$CROSS_PERL_CORE_PATH" dpkg-buildpackage -rfakeroot -b -d -us -uc -P$${FRR_BUILD_PROFILES} -a$(CONFIGURED_ARCH) -j$(SONIC_CONFIG_MAKE_JOBS) --admindir $(SONIC_DPKG_ADMINDIR)
else
	# Disable LTO for this package (LTO + _FORTIFY_SOURCE=3 breaks link)
	export DEB_CFLAGS_MAINT_STRIP="-flto=auto -ffat-lto-objects"
	export DEB_LDFLAGS_MAINT_STRIP="-flto=auto -ffat-lto-objects"
	dpkg-buildpackage -rfakeroot -b -us -uc -P$${FRR_BUILD_PROFILES} -j$(SONIC_CONFIG_MAKE_JOBS) --admindir $(SONIC_DPKG_ADMINDIR)
endif
	popd

	mv $(DERIVED_TARGET) $* $(DEST)/

$(addprefix $(DEST)/, $(DERIVED_TARGET)): $(DEST)/% : $(DEST)/$(MAIN_TARGET)
```

Key changes from old:
- Remove submodule `pushd ./frr` — dget replaces the submodule
- Remove `git fetch origin tag`, `git checkout -B build-...`, `stg branch --create`, `stg import` — replaced by `quilt push -a`
- Remove `.sonic-frr-patch-*.sha1` caching logic — the Makefile's own dependency tracking handles rebuild decisions (simpler, and dget always pulls fresh source anyway)
- `pushd ./frr` → `pushd frr-*`
- Keep `dplane_fpm_sonic.c` copy, `gbp dch`, `fakeroot debian/rules clean`, `rm -rf build/`, LTO disable, FRR_BUILD_PROFILES, cross-compile guard — all unchanged

**Edit `rules/frr.mk`:**

- [ ] Add `FRR_UBUNTU_VERSION` variable for the dget URL (the Ubuntu version string). The existing `FRR_VERSION` + `FRR_SUBVERSION` determine the SONiC .deb name and must be preserved for consumer compatibility.

Example if Ubuntu FRR version is `10.5.4-1ubuntu1`:
```makefile
FRR_UBUNTU_VERSION = 10.5.4-1ubuntu1
```

Keep `FRR_VERSION = 10.5.4` and `FRR_SUBVERSION = 0` unchanged — they define the SONiC-specific version suffix.

**Patch evaluation:**

- [ ] With 86 patches, expect ~30-50 to fail against Ubuntu's FRR source. Triage categories:
  - **FPM dplane patches (~12):** SONiC-proprietary protocol for communicating with the ASIC forwarding plane. MUST keep. Will need adaptation.
  - **EVPN Multihoming patches (~10):** SONiC-specific EVPN features. MUST keep. Will need adaptation.
  - **General FRR improvements:** May be upstreamed in Ubuntu's FRR version → DROP if the code is already present.
  - **Packaging patches:** Ubuntu has its own packaging → DROP.
  - **Compiler/portability fixes:** Likely obsolete on resolute/GCC15 → DROP.

**Gate 1:**

- [ ] Build:
```bash
sg docker -c 'make target/debs/resolute/frr_$(FRR_VERSION)-sonic-$(FRR_SUBVERSION)_amd64.deb'
ls -lh target/debs/resolute/frr*_*.deb
# Expected: 5 .deb files (main + 4 derived)
```

**Commit:**

- [ ] `git add src/sonic-frr/Makefile src/sonic-frr/patch/ rules/frr.mk` then `git commit -m "de-fork sonic-frr: switch source to Ubuntu dget"`

---

### Task C.3: radius/pam — git clone two-stage → dget + quilt

**Files:**
- Rewrite: `src/radius/pam/Makefile` (git clone FreeRADIUS + git clone pam_radius → dget freeradius + quilt)
- Modify: `rules/radius.mk:1` (PAM_RADIUS_VERSION — note the rules file is `radius.mk`)
- Preserve: `src/radius/pam/debian/` (local debian/ packaging directory)
- Reorganize: `src/radius/pam/freeradius/patches/` → `src/radius/pam/patch/`

**Current state:** Complex two-stage build:
1. **Stage 1:** `git clone https://github.com/FreeRADIUS/freeradius-server.git` → `git checkout 5f715dba` → apply 4 raw patches + copy config.sub/guess → `./configure --disable-static --enable-libtool-lock` → `make`
2. **Stage 2:** `git clone https://github.com/FreeRADIUS/pam_radius.git` → `git checkout 149c25df` → `cp -r ../debian .` → `dpkg-buildpackage -nc` (the `-nc` flag means "no clean" — it reuses Stage 1's build artifacts)

4 FreeRADIUS patches in `src/radius/pam/freeradius/patches/` (raw patch -p1, no stg/quilt) + 4 pam_radius patches in `src/radius/pam/debian/patches/` (quilt series inside the local debian/ dir).

**⚠️ Note:** `src/radius/pam/` is the correct path. The spec incorrectly says `src/libpam-radius-auth/`. Also, `src/radius/nss/` builds `libnss-radius` separately — it is NOT part of this task (Track D? Verify).

**Version scheme:** `PAM_RADIUS_VERSION = 1.4.1-1`

**Pre-flight:**

- [ ] Check Ubuntu FreeRADIUS source:
```bash
apt-cache showsrc freeradius 2>/dev/null | grep ^Version | head -3
```

- [ ] Check if `libpam-radius-auth` exists as a stock Ubuntu package:
```bash
apt-cache show libpam-radius-auth 2>/dev/null | head -10
```

- [ ] If `libpam-radius-auth` IS a stock Ubuntu package → follow libnl3 pattern (SONIC_MAKE_DEBS → SONIC_ONLINE_DEBS). This is the best outcome.
- [ ] If it is NOT → proceed with the dget rewrite below.

**Approach A (if stock Ubuntu package exists — preferred):**

- [ ] Change `rules/radius.mk`:
```makefile
# Replace SONIC_MAKE_DEBS with SONIC_ONLINE_DEBS for libpam-radius-auth
LIBPAM_RADIUS_POOL_URL = http://archive.ubuntu.com/ubuntu/pool/main/f/freeradius
$(LIBPAM_RADIUS)_URL = $(LIBPAM_RADIUS_POOL_URL)/$(LIBPAM_RADIUS)
SONIC_ONLINE_DEBS += $(LIBPAM_RADIUS)  # was SONIC_MAKE_DEBS
```
- [ ] Create `rules/radius.dep` with empty SPATH guard (same as libnl3 pattern)
- [ ] Leave `src/radius/pam/Makefile` as dead code

**Approach B (if NOT a stock package — dget rewrite):**

The challenge: SONiC doesn't build the full FreeRADIUS server — it only builds the `pam_radius` module against a locally-compiled FreeRADIUS. Ubuntu's `freeradius` source package builds the full server. The new Makefile must:
1. dget Ubuntu's freeradius source
2. Apply the 4 FreeRADIUS patches (now as quilt)
3. Build FreeRADIUS (to get libraries that pam_radius links against)
4. Extract the pam_radius source (from Ubuntu's freeradius source, or from a separate source)
5. Apply the 4 pam_radius patches (from `debian/patches/`)
6. Build pam_radius with `dpkg-buildpackage -nc`

This is too complex for a generic dget skeleton. **See execution note below.**

```makefile
.ONESHELL:
SHELL = /bin/bash
.SHELLFLAGS += -e

MAIN_TARGET = libpam-radius-auth_$(PAM_RADIUS_VERSION)_$(CONFIGURED_ARCH).deb
DERIVED_TARGETS = libpam-radius-auth-dbgsym_$(PAM_RADIUS_VERSION)_$(CONFIGURED_ARCH).deb

$(addprefix $(DEST)/, $(MAIN_TARGET)): $(DEST)/% :
	rm -rf ./freeradius-* ./pam_radius

	# Get FreeRADIUS source from Ubuntu
	dget -u http://archive.ubuntu.com/ubuntu/pool/main/f/freeradius/freeradius_$(FREERADIUS_UBUNTU_VERSION).dsc

	# Apply SONiC patches to FreeRADIUS
	pushd freeradius-*
	quilt push -a

	# Build FreeRADIUS (pam_radius needs its libraries)
	./configure --disable-static --enable-libtool-lock
	make
	popd

	# Build pam_radius
	# NOTE: pam_radius source may be inside freeradius source or separate.
	# Check Ubuntu's freeradius source package structure.
	# For now, assume pam_radius source is in freeradius-*/src/modules/rlm_pam/
	# (This needs verification against actual Ubuntu freeradius source.)
	cp -r debian pam_radius/debian/
	pushd pam_radius
	dpkg-buildpackage -rfakeroot -b -us -uc -nc -j$(SONIC_CONFIG_MAKE_JOBS) --admindir $(SONIC_DPKG_ADMINDIR)
	popd

	mv $(DERIVED_TARGETS) $* $(DEST)/

$(addprefix $(DEST)/, $(DERIVED_TARGETS)): $(DEST)/% : $(DEST)/$(MAIN_TARGET)
```

**⚠️ Approach B has significant unknowns.** The exact Ubuntu freeradius source structure, pam_radius location within it, and build integration must be verified at execution time. **Prefer Approach A if at all possible.**

**Edit `rules/radius.mk`:**

- [ ] Update version. Example if Ubuntu version is `1.4.1-1ubuntu1`:

```makefile
PAM_RADIUS_VERSION = 1.4.1-1ubuntu1
```

**Patch evaluation** (if Approach B):

- [ ] 4 FreeRADIUS patches: configure fix, 2007-04-06 compatibility, deprecated OpenSSL 1.0 API, libltdl config.sub. These are old compatibility patches — likely DROP on Ubuntu 26.04 (GCC15, OpenSSL 3.x, modern autotools).
- [ ] 4 pam_radius patches (in `debian/patches/`): CHAP support, PEAP-MSCHAPv2 support, NAS IP address config, BlastRADIUS fix. These are feature patches — evaluate against Ubuntu's pam_radius version.
- [ ] config.sub + config.guess files in `freeradius/patches/`: these update autotools for newer architectures. Ubuntu 26.04 source likely already has current versions → DROP.

**Gate 1:**

- [ ] Build and verify (Approach A or B):
```bash
sg docker -c 'make target/debs/resolute/libpam-radius-auth_$(PAM_RADIUS_VERSION)_amd64.deb'
ls -lh target/debs/resolute/libpam-radius-auth*_*.deb
```

**Commit:**

- [ ] `git add src/radius/pam/Makefile src/radius/pam/patch/ rules/radius.mk` then `git commit -m "de-fork libpam-radius-auth: switch source to Ubuntu"`

---

### Task C.4: sedutil — full de-fork (libnl3 pattern)

**Files:**
- Modify: `rules/sedutil.mk` (SONIC_MAKE_DEBS → SONIC_ONLINE_DEBS)
- Create: `rules/sedutil.dep` (empty SPATH guard)
- Do NOT modify: `src/sedutil/` (leave as dead code)

**Current state:** Downloads a pre-built binary (`sedutil-cli`) from GitHub releases, wraps it in a .deb with `dpkg-deb --build`. No source compilation, no patches. SONiC packages as `sedutil_1.15-5ad84d8_amd64.deb`.

**Version scheme:** `SEDUTIL_VERSION = 1.15-5ad84d8` (git describe format, not a distro version)

**⚠️ CRITICAL RISK:** `apt-cache showsrc sedutil` returned nothing on the resolute host. sedutil may NOT exist as an Ubuntu package at all. If Ubuntu doesn't package sedutil, the libnl3 pattern (SONIC_ONLINE_DEBS) is not feasible — there's no stock .deb to use.

**Pre-flight (MANDATORY — do not skip):**

- [ ] Verify Ubuntu availability:
```bash
apt-cache showsrc sedutil 2>/dev/null | grep ^Version | head -3
apt-cache show sedutil 2>/dev/null | grep ^Version | head -3
apt-cache show sedutil-cli 2>/dev/null | grep ^Version | head -3
apt-cache search sedutil 2>/dev/null
```
If ALL return nothing → sedutil is NOT in Ubuntu → **skip this task, mark as Track D (can't switch).**

- [ ] If sedutil IS available, check binary package name:
```bash
apt-cache show sedutil 2>/dev/null | grep ^Package
# Or: apt-cache show sedutil-cli 2>/dev/null | grep ^Package
```

**Approach (only if sedutil exists in Ubuntu):**

**Edit `rules/sedutil.mk`:**

- [ ] Change from SONIC_MAKE_DEBS to SONIC_ONLINE_DEBS:

Old pattern:
```makefile
SEDUTIL_GITHUB_URL = https://github.com/ChubbyAnt/sedutil
SEDUTIL_VERSION = 1.15-5ad84d8
SEDUTIL = sedutil_$(SEDUTIL_VERSION)_$(CONFIGURED_ARCH).deb
$(SEDUTIL)_SRC_PATH = $(SRC_PATH)/sedutil
SONIC_MAKE_DEBS += $(SEDUTIL)
```

New pattern (follow libnl3 exactly):
```makefile
SEDUTIL_VERSION = <UBUNTU_VERSION>
SEDUTIL = <binary-pkg-name>_$(SEDUTIL_VERSION)_$(CONFIGURED_ARCH).deb

SEDUTIL_POOL_URL = http://archive.ubuntu.com/ubuntu/pool/universe/s/sedutil
$(SEDUTIL)_URL = $(SEDUTIL_POOL_URL)/$(SEDUTIL)

SONIC_ONLINE_DEBS += $(SEDUTIL)
```

Note: the `_URL` is required for SONIC_ONLINE_DEBS — Makefile.cache uses it to download the .deb directly. The pool path may be `pool/universe/` or `pool/multiverse/` — check `apt-cache showsrc` output.

**Create `rules/sedutil.dep`:**

- [ ] Empty SPATH guard:
```makefile
# resolute: sedutil is an ONLINE_DEB with no in-repo source to hash,
# so no SPATH / git ls-files.
```

**Verify consumer alignment:**

- [ ] Check which docker images/packages consume sedutil:
```bash
grep -r 'sedutil' dockers/ platform/ rules/ --include='*.mk' --include='*.j2' --include='Dockerfile*' | grep -v 'src/sedutil'
```
If consumers reference `sedutil-cli` but Ubuntu's package is named `sedutil`, update consumer references.

**Gate 1:**

- [ ] Build:
```bash
sg docker -c 'make target/debs/resolute/sedutil_$(SEDUTIL_VERSION)_amd64.deb'
ls -lh target/debs/resolute/sedutil*_*.deb
```

**Commit (if sedutil exists in Ubuntu):**

- [ ] `git add rules/sedutil.mk rules/sedutil.dep` then `git commit -m "de-fork sedutil: switch from binary repackage to stock Ubuntu (online deb)"`

---

### Task C.5: wpasupplicant — local submodule → dget + quilt

**Files:**
- Rewrite: `src/wpasupplicant/Makefile` (submodule dpkg-buildpackage → dget + quilt)
- Modify: `rules/wpasupplicant.mk:1` (version variable)
- Extract: patches from `sonic-wpa-supplicant/` submodule differences vs upstream

**Current state:** The simplest Track C package structurally — just runs `dpkg-buildpackage` inside the `sonic-wpa-supplicant/` submodule. The submodule is a Canonical fork at `src/wpasupplicant/sonic-wpa-supplicant/` (branch `heads/resolute`, commit `15d4afa849e3`). All SONiC modifications are embedded in the submodule's source and its `debian/` packaging — there are no separate patch files in the Makefile.

**Version scheme:** `WPASUPPLICANT_VERSION = 2.9.0-14`

**Pre-flight:**

- [ ] Check Ubuntu source:
```bash
apt-cache showsrc wpa 2>/dev/null | grep ^Version | head -3
```
Note: Ubuntu packages wpa_supplicant from source package `wpa` (which also builds hostapd). The SONiC package name is `wpasupplicant`.

- [ ] Check Ubuntu binary packages:
```bash
apt-cache show wpasupplicant 2>/dev/null | grep ^Version | head -3
apt-cache show hostapd 2>/dev/null | grep ^Version | head -3
```

**Extract SONiC modifications as patches:**

- [ ] Compare the submodule against its upstream base to extract patches:
```bash
cd src/wpasupplicant/sonic-wpa-supplicant
# Find the upstream base (check debian/changelog or git log for the fork point)
git log --oneline | head -20
# Identify the upstream version it was forked from
git tag | head -10
# Extract patches from the fork point
git format-patch <upstream-tag> -o ../../patches-extracted/
```

- [ ] Alternatively, if the submodule's `debian/` directory contains the packaging changes in `debian/patches/`:
```bash
ls sonic-wpa-supplicant/debian/patches/ 2>/dev/null
```
If patches already exist there, just copy them to `src/wpasupplicant/patch/`.

- [ ] If the submodule doesn't have a clean upstream baseline (it's a Canonical fork with accumulated changes), the extraction is manual:
  1. Clone upstream wpa_supplicant at the matching version
  2. `diff -ruN` between upstream and SONiC fork
  3. Split the diff into logical patches
  4. Create quilt series

**Rewrite `src/wpasupplicant/Makefile`:**

- [ ] Replace submodule-based build with dget + quilt:

```makefile
.ONESHELL:
SHELL = /bin/bash
.SHELLFLAGS += -e

MAIN_TARGET = wpasupplicant_$(WPASUPPLICANT_VERSION)_$(CONFIGURED_ARCH).deb
DERIVED_TARGETS = wpasupplicant-dbgsym_$(WPASUPPLICANT_VERSION)_$(CONFIGURED_ARCH).deb

$(addprefix $(DEST)/, $(MAIN_TARGET)): $(DEST)/% :
	# Remove any stale files
	rm -rf ./wpa-*

	# Get wpa_supplicant source from Ubuntu
	dget -u http://archive.ubuntu.com/ubuntu/pool/main/w/wpa/wpa_$(WPA_UBUNTU_VERSION).dsc

	# Apply SONiC patches
	pushd wpa-*
	quilt push -a

	# Build with SONiC-specific config
ifeq ($(CROSS_BUILD_ENVIRON), y)
	dpkg-buildpackage -rfakeroot -b -us -uc -a$(CONFIGURED_ARCH) -Pcross,nocheck -j$(SONIC_CONFIG_MAKE_JOBS) --admindir $(SONIC_DPKG_ADMINDIR)
else
	dpkg-buildpackage -rfakeroot -b -us -uc -j$(SONIC_CONFIG_MAKE_JOBS) --admindir $(SONIC_DPKG_ADMINDIR)
endif
	popd

	mv $(DERIVED_TARGETS) $* $(DEST)/

$(addprefix $(DEST)/, $(DERIVED_TARGETS)): $(DEST)/% : $(DEST)/$(MAIN_TARGET)
```

Key changes:
- Remove `pushd ./sonic-wpa-supplicant` — replaced by dget
- Add `dget -u` step
- `pushd ./sonic-wpa-supplicant` → `pushd wpa-*`

**Edit `rules/wpasupplicant.mk`:**

- [ ] Update version. Example if Ubuntu version is `2.10-2ubuntu1`:

```makefile
WPASUPPLICANT_VERSION = 2.10-2ubuntu1
WPA_UBUNTU_VERSION = 2.10-2ubuntu1
```

Note: `WPA_UBUNTU_VERSION` is used in the dget URL (Ubuntu source package name is `wpa`). `WPASUPPLICANT_VERSION` is used in the .deb filename (SONiC package name is `wpasupplicant`). They may differ if SONiC adds a suffix.

**⚠️ Risk: MEDIUM.** wpasupplicant is a SONiC fork with 802.1X/EAPOL customizations. The key challenge is extracting clean patches from the submodule and verifying they apply to Ubuntu's wpa source. The submodule's changes may include debian/ packaging changes that should be DROPped (Ubuntu has its own packaging).

**Gate 1:**

- [ ] Build:
```bash
sg docker -c 'make target/debs/resolute/wpasupplicant_$(WPASUPPLICANT_VERSION)_amd64.deb'
ls -lh target/debs/resolute/wpasupplicant*_*.deb
```

**Commit:**

- [ ] `git add src/wpasupplicant/Makefile src/wpasupplicant/patch/ rules/wpasupplicant.mk` then `git commit -m "de-fork wpasupplicant: switch source to Ubuntu dget"`

---

### Task C.G2: Track C Gate 2 — Full clean dual-platform build

Same procedure as Task A.G2, but after all Track C packages are committed.

- [ ] All Track C commits are in git history:
```bash
git log --oneline | head -10
```
- [ ] `git status --short` is clean
- [ ] Run `make reset` to clear build artifacts

**VS Build:**

- [ ] Build VS image:
```bash
sg docker -c 'make PLATFORM=vs configure'
sg docker -c 'make PLATFORM=vs target/sonic-vs.img.gz' > target/build-vs-trackc.log 2>&1
```

- [ ] Verify VS build:
```bash
echo "Exit code: $?"
grep -i 'error' target/build-vs-trackc.log | grep -v '^#' | grep -v 'dh_strip.*error' | head -20
ls -lh target/sonic-vs.img.gz
```

**Broadcom Build (after VS passes):**

- [ ] Build Broadcom image:
```bash
sg docker -c 'make PLATFORM=broadcom configure'
sg docker -c 'make PLATFORM=broadcom target/sonic-broadcom.bin' > target/build-broadcom-trackc.log 2>&1
```

- [ ] Verify Broadcom build:
```bash
echo "Exit code: $?"
grep -i 'error' target/build-broadcom-trackc.log | grep -v '^#' | head -20
ls -lh target/sonic-broadcom.bin
```

**Fix-loop policy applies** (same as Task A.G2).

### Task C.G3: Track C Gate 3 — VS KVM boot verification

Same procedure as Task A.G3. Verify the VS instance boots and shows Ubuntu 26.04.

---

## Phase 4: Wrap-up

### Task 4.1: Final verification checklist

- [ ] All switched packages committed (up to 14 depending on sedutil/radius outcomes)
- [ ] VS image builds and boots
- [ ] Broadcom image builds
- [ ] `git log --oneline | head -20` shows all de-fork commits
- [ ] `git status` is clean

### Task 4.2: Record final state

- [ ] Record final git HEAD and commit list:
```bash
git rev-parse HEAD > /tmp/ubuntu-switch-final-commit.txt
git log --oneline $(cat /tmp/ubuntu-switch-baseline-commit.txt)..HEAD > /tmp/ubuntu-switch-commits.txt
cat /tmp/ubuntu-switch-commits.txt
```

### Task 4.3: Generate .deb diff summary

- [ ] Compare .deb files before/after:
```bash
for pkg in isc-dhcp kdump-tools libteam lm-sensors lldpd openssh \
           initramfs-tools monit rasdaemon flashrom frr \
           libpam-radius-auth sedutil wpasupplicant; do
  echo "=== $pkg ==="
  ls -lh target/debs/resolute/${pkg}*_*.deb 2>/dev/null | awk '{print $5, $NF}' || echo "  not found"
done
```

---

## Package Reference Table

| # | Package | Track | Mechanism | Patches | Mechanism Change | Risk |
|---|---|---|---|---|---|---|
| A.1 | isc-dhcp | A-true | dget + git init + stg | 18 | URL + version only | LOW |
| A.2 | kdump-tools | A-true | dget + git init + stg | 4 | URL + version only | LOW |
| A.3 | libteam | A-true | dget + git init + stg | 18 | URL + version only | MEDIUM |
| A.4 | lm-sensors | A-true | dget + git init + stg | 2 | URL + version only | LOW |
| A.5 | lldpd | A-true | dget + git init + stg | 3 | URL + version only | LOW |
| A.6 | openssh | A-true | dget + git init + stg | 4 (+1 cross) | URL + version only | MEDIUM |
| A.7 | initramfs-tools | A-pseudo | tarball + sha256 + quilt | 2 | tarball→dget, patch dir reorg | MEDIUM |
| A.8 | monit | A-pseudo | git clone + stg | 1 (+1 cross) | git clone→dget, stg→quilt | MEDIUM |
| A.9 | rasdaemon | A-pseudo | git clone + git apply | 2 | git clone→dget, git apply→quilt | LOW |
| C.1 | flashrom | C | git clone + git checkout tag + stg | 3 | full rewrite to dget+quilt | **HIGH** |
| C.2 | sonic-frr | C | submodule + stg + gbp dch | 86 | full rewrite to dget+quilt | **HIGHEST** |
| C.3 | radius/pam | C | git clone two-stage | 4+4 | rewrite to dget (or stock deb) | MEDIUM |
| C.4 | sedutil | C | wget binary + dpkg-deb --build | 0 | full de-fork (online deb) | **LOWEST** (if in Ubuntu) |
| C.5 | wpasupplicant | C | submodule + dpkg-buildpackage | embedded | extract patches, dget+quilt | MEDIUM |

## Risk Summary

| Package | Risk | Key Concern |
|---|---|---|
| isc-dhcp | LOW | 18 patches but most are SONiC-specific DHCP relay features |
| kdump-tools | LOW | 4 patches, simple kdump configuration |
| libteam | MEDIUM | 18 patches, teamd is critical for LAG — failures block networking |
| lm-sensors | LOW | 2 patches may both DROP if Ubuntu has sensord |
| lldpd | LOW | 3 patches, one likely upstreamed in 1.0.18+ |
| openssh | MEDIUM | 4 functional patches, SSH security model sensitive to version skew |
| initramfs-tools | MEDIUM | 2 SONiC-specific patches for ONIE installer, unlikely upstreamed |
| monit | MEDIUM | Only 1 active patch, but stg→quilt conversion + cross-compile patch handling |
| rasdaemon | LOW | 2 patches likely both DROP (CPU check upstreamed, maintainer fix irrelevant) |
| flashrom | **HIGH** | 7-year version gap (0.9.7→1.6.x), patches likely obsolete |
| sonic-frr | **HIGHEST** | 86 patches, SONiC-proprietary FPM, 1-2 days for triage alone |
| radius/pam | MEDIUM | Two-stage build complex; may become simple if stock deb exists |
| sedutil | **LOWEST** (or N/A) | May not exist in Ubuntu at all → becomes Track D |
| wpasupplicant | MEDIUM | SONiC 802.1X/EAPOL fork, patch extraction is the hard part |

## Estimated Time

| Phase | Packages | Est. Time |
|---|---|---|
| Track A true-dget (URL + version change) | 6 (A.1-A.6) | ~1-2 hours each including Gate 1 |
| Track A pseudo (Makefile rewrite) | 3 (A.7-A.9) | ~2-4 hours each |
| Track A Gate 2 (VS+Broadcom build) | — | ~4-6 hours (background) |
| Track A Gate 3 (KVM boot) | — | ~0.5 hours |
| Track C extract + rewrite | 4 (C.1-C.3, C.5) | ~4-8 hours each (C.2=1-2 days) |
| Track C sedutil de-fork | 1 (C.4) | ~0.5 hours (if in Ubuntu) |
| Track C Gate 2 (VS+Broadcom build) | — | ~4-6 hours (background) |
| Track C Gate 3 (KVM boot) | — | ~0.5 hours |
| **Total (optimistic)** | — | **~3-5 days** |
| **Total (pessimistic, with fix-loops)** | — | **~1-2 weeks** |