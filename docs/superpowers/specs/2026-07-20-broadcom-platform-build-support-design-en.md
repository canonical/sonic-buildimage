# Design: Broadcom Platform Build Support on Resolute

- Date: 2026-07-20
- Repo: `canonical/sonic-buildimage` branch `202605_resolute`
- Author: Sheldon Qi
- Status: Design approved, pending implementation plan

## 1. Background & Motivation

The `202605_resolute` branch migrated SONiC from Debian Trixie to Ubuntu Resolute (26.04); the VS platform (`sonic-vs.bin`) builds successfully. But the Broadcom platform has **never been built** on resolute — `target/` contains no broadcom artifacts.

Resolute applied only one mechanical rename commit to `platform/broadcom/` (`b85dee25a7`: `DOCKER_CONFIG_ENGINE_TRIXIE` → `..._RESOLUTE`, Dockerfile.j2 `FROM ...trixie` → `...resolute`). **SAI versions and opennsl kernel module logic were left untouched.** The real resolute adaptation lives in `rules/` (linux-sonic kernel, grub2, FIPS, iproute2).

The user's goal is to support the Broadcom platform (TH3 / XGS family) and produce a standard `sonic-broadcom.bin`.

## 2. Goals & Scope

### 2.1 Goal

On branch `202605_resolute`, make `make PLATFORM=broadcom` produce a standard `sonic-broadcom.bin` containing:
- Three syncd containers (`docker-syncd-brcm` / `-dnx` / `-legacy-th`)
- Three opennsl kernel modules (`opennsl-modules` / `-dnx` / `-legacy-th`)
- Three closed-source SAI .debs (XGS `15.2.0.0.0.0.3.1` / DNX `14.1.0.1.0.0.27.0` / legacy-th `13.2.1.120`)
- libsaithrift-dev, sswsyncd, and supporting components

### 2.2 TH3 Placement

TH3 belongs to the XGS family, using:
- SAI: `platform/broadcom/sai-xgs.mk` (libsaibcm v15.2.0, branch `SAI_15.2.0_GA`)
- syncd container: `platform/broadcom/docker-syncd-brcm.mk` (`MACHINE=broadcom`)
- kernel module: `platform/broadcom/sai-modules.mk` → `opennsl-modules` (v15.2.0.0.0.0.0.0)
- device config: `device/broadcom/x86_64-broadcom_common/x86_64-broadcom_b98/` (b98 = TH3)

Because the standard `sonic-broadcom.bin` packs all three syncd variants via `one-image.mk:5` `DEPENDENT_MACHINE = broadcom-dnx broadcom-legacy-th`, even though only TH3 is needed, the DNX 14.1 and legacy-th 13.2 chains must also pass. **The user chose to produce the standard three-variant bin directly.**

### 2.3 Success Criteria (No Hardware)

The user currently has **no real Broadcom hardware**. Success criteria:
- Build runs end-to-end with no errors
- Image structure is complete (`sonic-broadcom.bin` generated, ONIE installer layout correct)
- Three syncd containers build successfully

The opennsl kmod only needs to prove it **"can compile against resolute kernel headers + package into a .deb with correct dependencies"** — runtime verification of module loading / ASIC connection is not required.

## 3. Architecture: Open-source Self-built Chain Around Closed-source Blobs

### 3.1 Closed vs Open Source Distribution

| Component | Form | Version | Open? |
|---|---|---|---|
| **libsaibcm (SAI impl)** | prebuilt .deb download | XGS 15.2 / DNX 14.1 / legacy-th 13.2 | ❌ closed blob |
| **bcmcmd / bcmsh / bcm_common** | binary download | fixed `20190307` | ❌ closed |
| opennsl kernel module | submodule source build | 15.2 / 14.1 / 13.2.1 | ✅ open, modifiable (github.com/sonic-net/saibcm-modules) |
| syncd | sonic-sairedis source build | — | ✅ open |
| sswsyncd (bcmcmd/dsserve C++) | in-tree source build | — | ✅ open |
| docker images / device config | templates + source | — | ✅ open |

**Core fact: only libsaibcm .deb + diagnostic binaries are closed; everything else is open-source self-buildable.** Version binding of closed blobs is covered in §3.2.

### 3.2 Version Binding of Closed Components

1. **[Hard] kmod version ↔ SAI version must pair as a set**: XGS SAI 15.2 only pairs with opennsl kmod 15.2; DNX 14.1 with 14.1; legacy-th 13.2.1 with 13.2.1. Userspace SAI and the kernel module share a private ABI and cannot be mixed across versions. → three-variant bin must pull three kmods.
2. **[Hard] kmod must compile against the exact running kernel**: the resolute kernel is `linux-sonic 7.0.0-1002-sonic` (trixie was `6.12.41+deb13-sonic-amd64`). The kmod's `debian/rules` ABI derivation logic + `debian/control` Depends are based on the trixie kernel name; when the kernel changes, it must be recompiled + its packaging metadata updated. → **the core blocker of this design**.
3. **[Soft, de-risked] closed .deb glibc dependencies**: libsaibcm declares `Depends: libc6 (>= 2.38), libgcc-s1 (>= 3.4), libstdc++6 (>= 14), libprotobuf32t64 (>= 3.21.12), libyaml-0-2, lz4`, all `>=` lower bounds, all satisfied by resolute (Ubuntu 26.04, glibc 2.43, libstdc++6 ≥ 15). Evidence: downloaded the XGS .deb and ran `dpkg-deb -I` on the control; download endpoint returned HTTP 200 (last-modified 2026-06-19).
4. **[Soft, known small point] protobuf package name mismatch**: libsaibcm declares `libprotobuf32t64` (trixie time64 naming), but resolute's `rules/protobuf.mk:12` produces `libprotobuf32` (no `t64`). At build time, verify whether resolute's `libprotobuf32` `Provides: libprotobuf32t64`; if not, use equivs to provide a provides shim or `--ignore-deps`. **Does not block this design; deferred to build-time handling.**
5. **[Soft, only verifiable by actual build] GCC15 linking against closed libsaibcm**: sswsyncd / libsaithrift-dev / syncd's BCM-specific code links against closed libsaibcm (built with old GCC) from a GCC15 (resolute) linking side. C ABI has been stable since GCC5, likely OK; C++ boundaries may have corner cases. Only verifiable by actual build; serves as a build-time failure fallback point.

### 3.3 Build Artifact Structure

```
sonic-broadcom.bin (ONIE installer)
├── 3 syncd containers (docker-syncd-brcm / -dnx / -legacy-th)   ← open self-built
│   ├── syncd (sonic-sairedis source build)                         ← open
│   ├── libsaibcm .deb (XGS15.2/DNX14.1/legacy13.2)                ← closed blob download
│   └── sswsyncd (bcmcmd/dsserve C++ source)                        ← open self-built
├── 3 opennsl kmods (saibcm-modules{,-dnx,-legacy-th})             ← open submodule + patch self-built
│   └── must align to resolute linux-sonic 7.0.0-1002-sonic kernel   ← ★hard blocker, design core
├── libsaithrift-dev (bound to closed SAI)                           ← open self-built
└── vendor platform-modules (22, LAZY_INSTALLS, runtime per-model)   ← does not block generic bin
```

## 4. Core Change: opennsl kmod Adaptation (Option A — quilt patches)

### 4.1 Option Selection

All three `saibcm-modules{,-dnx,-legacy-th}` are git submodules (`.gitmodules` points to `github.com/sonic-net/saibcm-modules.git`). AGENTS.md requires "do not directly modify source code downloaded from external projects; add a patch file and apply it explicitly from the relevant build rule."

**Selected: Option A — quilt patch files.** Rationale:
- The SONiC build graph `slave.mk:811` already auto-applies `<SRC_PATH>.patch/series` via quilt — no new mechanism
- Fully AGENTS.md-compliant; does not touch gitlinks
- resolute-specific changes isolated in patch files; minimal upstream merge conflicts
- kmod adaptation is inherently "local porting for the resolute kernel version" — not worth promoting into the submodule mainline (Option B is over-engineering); Option C (env var override) has hard flaws against `:=` immediate assignment and static `control` files

Rejected Option B (in-submodule commit + gitlink advance): high effort (3 submodule resolute branches + gitlink reachability maintenance), and long-term branch divergence from upstream trixie naming.
Rejected Option C (build rule env var override + sed): `debian/rules`'s `KVER := $(word 1,...)` is immediate assignment, env var override is unreliable; `debian/control` is a static file, sed is unreviewable and brittle.

### 4.2 Patch Organization

The three submodule source trees have different versions/branches; their `debian/rules`/`control` contents differ. **One patch per submodule:**

```
platform/broadcom/saibcm-modules.patch/series
platform/broadcom/saibcm-modules.patch/0001-resolute-kernel-abi.patch          # XGS
platform/broadcom/saibcm-modules-dnx.patch/series
platform/broadcom/saibcm-modules-dnx.patch/0001-resolute-kernel-abi.patch      # DNX
platform/broadcom/saibcm-modules-legacy-th.patch/series
platform/broadcom/saibcm-modules-legacy-th.patch/0001-resolute-kernel-abi.patch # legacy-th
```

### 4.3 Change Contents

#### (a) `debian/rules` — ABI Derivation Logic

**Current** (saibcm-modules/debian/rules:50-52):
```make
KVER := $(word 1,$(subst -, ,$(KVERSION)))
KVER_ARCH := $(KVER)-sonic-amd64
KVER_COMMON := $(KVER)-common-sonic
```

**Problem**:
- trixie `KVERSION=6.12.41+deb13-sonic-amd64` → `word 1` = `6.12.41+deb13` (version and debian suffix separated by `+`, not lost) → `KVER_ARCH=6.12.41+deb13-sonic-amd64` ✅
- resolute `KVERSION=7.0.0-1002-sonic` → `subst -` → `7.0.0 1002 sonic`, `word 1` = `7.0.0` (**loses `-1002`**) → `KVER_ARCH=7.0.0-sonic-amd64` ❌ cannot find headers dir (actual is `7.0.0-1002-sonic-amd64`)

**Fix**: make `KVER` retain everything up to `-sonic`, i.e. `7.0.0-1002`. Set `KVER_ARCH=7.0.0-1002-sonic-amd64` and adjust `KVER_COMMON` accordingly.

**Also to verify** (may go in the same patch or a separate one):
- The common headers package name corresponding to `KVER_COMMON`: resolute uses `linux-sonic-headers-7.0.0-1002` (prefix `linux-sonic-headers-`, not trixie's `linux-headers-...-common-sonic`). The cluster of `sudo ln -sfn /usr/src/linux-headers-$(KVER_COMMON)/...` symlinks in `build-arch` must adapt to resolute's Ubuntu-style (build-script-tree-in-headers structure).
- Actual patch content is generated against the checked-out submodule source.

#### (b) `debian/control` — Depends

All three control:13 hardcode:
```
Depends: linux-image-6.12.41+deb13-sonic-amd64-unsigned
```
Change to (hardcoded resolute package name, no arch suffix):
```
Depends: linux-image-7.0.0-1002-sonic
```
The resolute kernel package name is defined in `rules/linux-kernel.mk:32` `LINUX_IMAGE = linux-image-$(KVERSION)_...` where `KVERSION=7.0.0-1002-sonic`.

## 5. Known Small Points (Build-time Handling)

| Point | Handling | When |
|---|---|---|
| libprotobuf32t64 vs libprotobuf32 package name | At build time verify whether resolute's `libprotobuf32` `Provides: libprotobuf32t64`; if not, equivs provides shim or `--ignore-deps` | M2 (when syncd installs closed .deb) |
| GCC15 linking closed libsaibcm to build sswsyncd/libsaithrift-dev | C ABI stable since GCC5, verify by actual build; handle specific errors if they arise | M2 |

## 6. Verification Milestones (Three-step Progressive)

| Milestone | make target | Proves | Failure fallback |
|---|---|---|---|
| **M1: three kmods** | `target/debs/broadcom/opennsl-modules*.deb` (incl. -dnx / -legacy-th) | kmods compile against resolute linux-sonic 7.0.0-1002 headers; patch ABI derivation + control Depends fix is correct | patch ABI derivation / symlinks / Depends |
| **M2: three syncd containers** | `target/docker-syncd-brcm*.gz` etc. | syncd / sswsyncd compile; libsaibcm .deb installs; protobuf name mismatch handled | GCC15 linking, protobuf provides shim |
| **M3: sonic-broadcom.bin** | `target/sonic-broadcom.bin` | image assembly; three syncd + kmod packaging; ONIE installer structure complete | one-image LAZY_BUILD_INSTALLS, image layout |

## 7. Out of Scope (YAGNI)

- No arm64 broadcom (`device/arista/arm64-arista_goldfinch-r0` has a device dir but no image build path; not a target)
- No PDE (`INCLUDE_PDE=y`) / saiserver / rpc variants (not pulled by default; require explicit opt-in)
- No ABOOT swi (`sonic-aboot-broadcom.swi`) resolute adaptation, unless M3 reveals it's needed after the ONIE bin passes (M3 target is only `sonic-broadcom.bin`)
- No rewriting vendor platform-modules (LAZY_INSTALLS; do not block generic bin)
- No changes to SAI versions / URLs (confirmed: 2026-06-19 update, endpoint reachable, deps satisfiable)
- No gitlink changes, no submodule source changes (via patch)

## 8. AGENTS.md Compliance

- kmod changes via patch files (not direct submodule source edits)
- No gitlink changes
- Jinja2 templates treated as source; generated files untouched
- Does not bypass the slave.mk build graph (uses `make` targets)
- Minimal scoped change; no unrelated formatting / dependency upgrades

## 9. Risk Register

| # | Risk | Status | Mitigation |
|---|---|---|---|
| 1 | opennsl kmod `debian/control` hardcodes trixie kernel name; apt Depends unsatisfiable | **confirmed** | patch Depends to `linux-image-7.0.0-1002-sonic` (§4.3b) |
| 2 | opennsl kmod `debian/rules` ABI derivation loses `-1002`, mismatch with actual kernel ABI | **confirmed** | patch KVER parsing (§4.3a) |
| 3 | closed SAI .deb glibc deps on Ubuntu 26.04 | **de-risked (no issue)** | `dpkg-deb -I` verified; all deps are `>=` lower bounds |
| 4 | libprotobuf32t64 vs libprotobuf32 package name | **confirmed (small)** | build-time verify + optional equivs (§5) |
| 5 | GCC15 linking closed libsaibcm to build sswsyncd/libsaithrift-dev | speculative (build-only) | M2 verification; C ABI stable, likely OK |
| 6 | build-arch symlink assumptions not fit for resolute Ubuntu-style headers structure | speculative | M1 verification; extend patch as needed |
| 7 | Broadcom image zero build verification on resolute | **confirmed** | this design's three-milestone progressive verification |

## 10. Next

After this design is approved, transition to `superpowers:writing-plans` to generate a detailed implementation plan, executed progressively M1 → M2 → M3.
