# Decoupling upstream deb packaging from sonic-buildimage into a Launchpad PPA — Design

**Date**: 2026-07-28
**Branches**: this design document lives on `202605_resolute_doc`; the implementation goes on a worktree branch off `202605_resolute_sheldon`
**Target distribution**: Ubuntu 26.04 `resolute` (`BLDENV=resolute`)
**Related**: the [2026-07-10 Launchpad kernel migration plan](../plans/2026-07-10-sonic-202605-resolute-launchpad-kernel-migration-plan-en.md) already switched the kernel to PPA consumption; this design reuses that same consumption model

---

## 1. Goal

Decouple "deb packaging of third-party upstream software" from the `sonic-buildimage` image build: the image build no longer compiles these packages, it fetches prebuilt artifacts from a Launchpad PPA instead. The packaging recipes (patch series, version numbers, stock source locations) stay in this repository and are the single input for generating the PPA source packages.

This iteration only builds the scaffolding and lands the first three packages end to end. It is not a full migration.

### 1.1 Non-goals

- **Not about build speed.** Measured from `target/debs/resolute/*.log` (all 57 packages were real builds, `CACHE::SAVED`): the deb stage totals 4335 s ≈ 72 minutes, of which the two categories in scope account for roughly 18 minutes (25%), and the easiest-to-move first category for just 7 minutes (10%). The remaining 75% is SONiC-original components and packages that need network access at build time, which a PPA cannot help. The speed argument does not hold, and this design does not rest on it.
- **Not decoupling the source.** `src/<pkg>/patch/series` stays in this repository. Rationale in §4.1.
- **Not touching SONiC-original components** (`swss`, `sairedis`, `sonic-gnmi`, `sonic-host-services`, …). Those belong in the tree.
- **Not upstreaming or MIR.** Whether the patches can go upstream is a separate matter, out of scope here.
- **Not touching `trixie` / `bookworm` / `bullseye`.** Every switch defaults to off; non-resolute builds behave exactly as today.

---

## 2. Scope

### 2.1 In scope (29 source trees)

**Category 1: `dget`/`wget` of a real Debian/Ubuntu source package plus SONiC patches (15)**

`bash`, `initramfs-tools`, `iproute2`, `iptables`, `isc-dhcp`, `kdump-tools`, `libteam`, `libyang3`, `lm-sensors`, `monit`, `openssh`, `redis`, `socat`, `thrift`, `mpdecimal`

Every one of these `src/<pkg>/Makefile` files follows the same shape:

```make
dget -u .../<pkg>_<ver>.dsc      # fetch the official source package
git init && stg init
stg import -s ../patch/series     # stack the SONiC patches (bash uses quilt push -a)
dpkg-buildpackage -us -uc -b      # binary only
```

**This design got this wrong initially; implementation measured it and disproved it. The corrected version follows.** The original premise was that appending the same series in the same order into `debian/patches/series` is equivalent. That holds in only one case; two rules are actually needed:

1. **Extraction must not pre-apply the patches.** `dget -u` extracts via `dpkg-source -x`, which applies all of the upstream `debian/patches` and leaves a `.pc`. It has to be `dget -d -u` (download only) plus `dpkg-source --skip-patches -x`, so the tree stays pristine and the upstream and SONiC patches sit side by side in the series **unapplied**, for the builder to apply at build time.
2. **A patch that modifies `debian/` must not go into the series.** In `3.0 (quilt)`, `debian/patches/*` are applied to the *upstream* source; the `debian/` directory itself ships in the debian tarball at its final content, and `dpkg-source` ignores changes under `debian/` when computing the automatic patch. So a patch that edits `debian/rules` and is also listed in the series gets applied a **second** time at build time, producing `Reversed (or previously applied) patch detected!`. Such patches must be **applied directly to the tree** — baking their effect into the debian tarball — and **left out of the series**.

Measured patch composition for the first three packages:

| Package | `debian/`-only patches | upstream-only patches | quilt patches shipped by the stock source |
|---|---|---|---|
| `libteam` | 0 | 14 (all) | 0 (no `debian/patches/series` at all) |
| `isc-dhcp` | 5 | 14 | 10 |
| `lm-sensors` | 3 (both) | 0 | 14 |

`libteam` happens to have no `debian/` patches and no upstream patches either, which is exactly why it went end to end first while the problem only surfaced on `isc-dhcp` — and why "start with the cleanest baseline package" was the right selection strategy: it separates defects in the scaffolding from defects specific to a package.

**Category 2: upstream tarball / git plus a SONiC-authored `debian/` (14 source trees)**

`ifupdown2`, `thrift_0_14_1`, `libyang3-py3`, `wpasupplicant`, `sonic-device-data`, `sflow/{hsflowd,psample,sflowtool}`, `tacacs/{audisp,nss,pam,bash_tacplus}`, `radius/{nss,pam}`

These need one extra step: move today's clone/download logic forward into "produce an `orig.tar.*`", then carry `debian/` over unchanged. `radius/pam` is the awkward one — it has to synthesise a single orig out of two repositories (`freeradius-server` and `pam_radius`).

### 2.2 Out of scope

| Package | Reason |
|---|---|
| `sonic-fips` | `git clone` at build time plus `curl` of prebuilt artifacts from `BUILD_PUBLIC_URL` |
| `dash-sai` | `git clone` of DASH plus `git submodule update` at build time |
| `sonic-p4rt` | Bazel, pulls a large external dependency set at build time |
| `p4lang` (pi/bmv2/p4c) | Third-party dsc from openSUSE OBS, plus a hard boost pin |
| `sonic-frr` | Clones the frr submodule and stacks 85 patches via stgit at build time. Technically feasible, but a whole tier more work — tracked as a separate second phase |
| `grpc`, `protobuf` | `ifeq ($(BLDENV),bullseye)`; not built on resolute |
| `snmpd` | `ifeq ($(BLDENV),bookworm)`; not built on resolute |
| `sonic-redfish` | `ifeq ($(BLDENV),trixie)`; not built on resolute, and clones at build time |
| SONiC-original components (28) | Their `debian/rules` runs pip/go/cargo, and they evolve in lockstep with the image |

Launchpad builders run in a clean chroot with **no network**. That is the only substantive exclusion criterion — not "does it contain binaries". Shipping prebuilt binaries inside `orig.tar.*` and having `debian/rules` install them is a legitimate shape (`sedutil` is exactly that); putting binaries in the `debian/` directory requires `debian/source/include-binaries`. What is genuinely forbidden is including a `.deb` in the upload — PPAs accept source uploads only.

---

## 3. Hard constraints established by investigation

All of the following were verified against this repository. They are design inputs, not assumptions.

### 3.1 The consumption side already has a working precedent

`rules/linux-kernel.mk` already consumes a prebuilt kernel from a Launchpad PPA (`canonical-kernel-team/bootstrap`) using exactly the machinery this design needs: `SONIC_ONLINE_DEBS`, direct `ppa.launchpadcontent.net/.../pool/main/` URLs (the `+files` URL redirects to launchpadlibrarian.net, which is unreachable from the build environment), and `_DEPENDS` for install ordering. `rules/libnl3.mk` and `rules/lldpd.mk` are de-fork precedents using the same mechanism.

### 3.2 Include order (determines where things go)

| Location | Content |
|---|---|
| `slave.mk:164-165` | `include rules/config`, `-include rules/config.user` |
| `slave.mk:289` | `include rules/functions` |
| `slave.mk:290` | `include rules/ppa-functions` (added by this design) |
| `slave.mk:299` | `include rules/*.mk` (glob) |
| `Makefile.cache:129` | `include rules/*.dep` (glob) |

Therefore: global switches go in `rules/config` (overridable from `config.user`). **No generated artifact may live under `rules/` with a `.mk` suffix**, or line 299 would include it a second time — this design produces no such artifact.

The helpers must **not** be appended to `rules/functions`, tempting though its position is. `Makefile.cache:110` lists `rules/functions` in `SONIC_COMMON_FILES_LIST`, all 267 `.dep` files fold that list into `DEP_FILES`, and `Makefile.cache:646-652` hashes every entry into `<pkg>.dep.sha` and hence into the cache filename — so touching it **invalidates the cache key of all 267 cached targets on every distro**, in direct violation of "with the switch empty, behaviour is identical to before". `Makefile.cache:70-79` already documents this as the reason `slave.mk` was kept out of that list.

Hence a new `rules/ppa-functions` (also without a `.mk` suffix, so the glob still cannot double-include it), included once at `slave.mk:290`, and deliberately **not** added to `SONIC_COMMON_FILES_LIST`.

### 3.3 An online deb's local filename may differ from its URL

The core of the online rule at `slave.mk:750-767`:

```make
$(foreach deb,$* $($*_DERIVED_DEBS), \
    curl -L -f -o $(DEBS_PATH)/$(deb) $($(deb)_CURL_OPTIONS) $($(deb)_URL) ... )
```

The on-disk name is the make target name; the URL is independent. This single fact also resolves the dbgsym extension problem (§7).

### 3.4 `add_derived_package` works in online mode

`rules/functions:89-99`:

```make
define add_derived_package
$(2)_DEPENDS += $(1)
...
$(1)_DERIVED_DEBS += $(2)
$(2)_URL = $($(1)_URL)          # line 94
...
```

Derived debs already land in `$*_DERIVED_DEBS` and get downloaded by the foreach in §3.3, so every `add_derived_package` call, `_DEPENDS`, `_RDEPENDS` and `DBG_SRC_ARCHIVE` declaration can stay untouched.

Line 94's semantics need stating precisely, because the imprecise reading is the one that bites: `$(eval $(call add_derived_package,…))` **fully expands** `$(2)_URL = $($(1)_URL)` at call time, when the main deb's `_URL` is usually still undefined. So a derived deb that never gets a later override ends up with an **empty URL (downloading nothing)**, not with the main deb's URL. The `_URL` overrides must therefore come after every `add_derived_package` call in the file, and missing one is silent. `scripts/ppa/query.mk` guards this twice: in PPA mode the deb count must equal the number of non-empty `_URL`s, and all `_URL`s must be distinct.

### 3.5 An empty SPATH in `.dep` is a known landmine

`rules/<pkg>.dep` looks like:

```make
SPATH       := $($(SOCAT)_SRC_PATH)
DEP_FILES   += $(shell git ls-files $(SPATH))
```

In PPA mode the deb name changes and `_SRC_PATH` is no longer set, so `SPATH` is empty, `git ls-files` lists the entire repository, hits symlinks/gitlinks, and `hash-object` fails (`Makefile.cache:655` — already hit on grub2/libnl3). A guard is mandatory.

### 3.6 dbgsym on Launchpad will always be `.ddeb`

`sonic-slave-resolute/Dockerfile:649` seds `/usr/share/perl5/Debian/Debhelper/Dh_Lib.pm` to change `DBGSYM_PACKAGE_TYPE` from `ddeb` back to `deb`. That patch cannot be applied on a Launchpad builder, so the artifact will always be a `.ddeb`. Within scope, 14 `rules/*.mk` files reference `-dbgsym` (`tacacs` 5 times, `iptables` 4, `libteam` and `lm-sensors` 3 each, the rest 1–2).

### 3.7 Everything SONiC does in the Makefile is lost on a PPA

**This is the single largest risk in the design.** Anything outside `dpkg-buildpackage` in `src/<pkg>/Makefile` is not part of the source package and is invisible to the Launchpad builder:

| Package | Out-of-tree action | Consequence on the builder |
|---|---|---|
| `isc-dhcp` | `export DEB_CFLAGS_MAINT_STRIP="-flto=auto -ffat-lto-objects"`, same for `DEB_LDFLAGS_MAINT_STRIP` | **Guaranteed build failure** (the LTO link error in the vendored bind 9.11) |
| `lm-sensors` | `PROG_EXTRA=sensord` | **Silently loses a binary**: no error, but `sensord` is never built — and `docker-platform-monitor` needs it. Measured a second layer: once internalised, compiling `sensord` links `-lrrd`, and the stock `debian/control` never declares `librrd-dev` — the local build only ever passed because the slave image preinstalls it (`Dockerfile.j2:372-374`). **Internalising an out-of-tree action can pull in new `debian/control` requirements.** |
| `libyang3` | `sed -i -e '/.*libxxhash.*/d' debian/control`, `dpkg-buildpackage -d` | Build-deps become unsatisfiable; `-d` has no effect on a builder |
| `bash`, `socat`, `lm-sensors`, `initramfs-tools` | `DEB_BUILD_OPTIONS=nocheck` / `-Pnocheck` | The builder will actually run the test suites |
| `socat`, `openssh`, `monit`, `libyang3` | Some patches are applied with `patch -p1 < ../patch/xxx.patch` and are **not in the series** | Easiest thing to miss when converting to quilt |
| `iproute2` | `sed -i "1s/(ver)/(ver+sonic.0)/" debian/changelog` | Superseded by this design's `dch` step |
| `bash` | `cp -a ../Files/. ./` plus `./configure` | Serves local unit tests only; does not affect the artifact |

Guiding principle: **out-of-tree actions that are functional or that fix the build must be internalised into `debian/rules`** (as a SONiC patch in `debian/patches`); those that only serve local testing can be dropped. Every package migration must walk this table item by item.

### 3.8 The slave image's global build-flag override (the image-level counterpart to §3.7, missed entirely in the first draft)

The table in §3.7 lists only what each `src/<pkg>/Makefile` does. There is one more out-of-tree action, at **image level, affecting every self-built package**: `sonic-slave-resolute/Dockerfile.j2:860` installs `sonic-slave-resolute/buildflags.conf` as `/etc/dpkg/buildflags.conf` in the container:

```
APPEND CFLAGS -std=gnu17 -Wno-error=incompatible-pointer-types -Wno-error=int-conversion -Wno-error=discarded-qualifiers
```

GCC 15 defaults to C23; this line pulls the whole build back to the gnu17 baseline and relaxes three newly-promoted error classes. **None of it travels with a source package to Launchpad**, and no such file exists on a builder — nor in the pristine `ubuntu:resolute` container `build-clean.sh` uses, which is precisely why that container surfaces the problem.

Consequence: **any package that only compiles because of this line must carry the part it actually needs in its own `debian/rules` when it moves to the PPA.** That is how `isc-dhcp` was caught — the K&R declarations left in its `dhcpv6.c` (such as `void (*ia_na_match)()`) change meaning under C23 from "unspecified parameters" to "no parameters" and fail to compile. It never showed locally because the global line had always been masking it.

When internalising, **measure the minimal set per package; do not copy the line wholesale.** `isc-dhcp` needed only `-std=gnu17` — none of the three `-Wno-error=` relaxations — which shows the global line is broader than any individual package requires. `libteam` needs none of it at all and builds in the pristine container as-is.

Every package migration must answer: **does it depend on this global override, and on which part?** The way to find out is to build it once in `build-clean.sh`'s pristine container.

### 3.9 Current state of variable exports

Most category-1 packages already `export` their version variables from `rules/<pkg>.mk` (for sub-makes); `redis` and `thrift` export nothing. The stock `.dsc` URL is currently **hardcoded inside `src/<pkg>/Makefile`**; only `iproute2` has lifted it into a variable (`IPROUTE2_DSC_URL`).

---

## 4. Design decisions

### 4.1 Packaging recipes stay in this repository; no separate packaging repo

**Rejected**: a new `sonic-packaging` monorepo, or one git repository per package.

Rationale for rejection: this project has already taken a real loss from "source split across repos causes silent divergence" — submodule branches did not follow the super-repo rebase, gitlinks kept old commits, and upstream fixes were silently dropped (the root cause behind the all-zero SAI counters). A separate packaging repo would create an isomorphic second divergence surface: the version number in `rules/<pkg>.mk` on one side, the patches on the other, with nobody noticing when a rebase onto `sonic-net/202605` desynchronises them. Keeping both in one tree means a patch and the version number that consumes it move in the same commit, and the risk disappears.

The cost is explicit: what gets decoupled is the **build**, not the **source**. `src/<pkg>/patch/` stays in the tree.

### 4.2 Control via Makefile variables, not YAML

**Rejected**: `ppa/packages.yaml` plus a generator plus a generated `.mk`.

The decisive reason: YAML would have to restate the version number, which already lives in `rules/<pkg>.mk` — and the entire argument in §4.1 exists to eliminate a second source of truth. Reviewing the fields one by one, almost all of them are derivable:

| Field | Needed? |
|---|---|
| Debian source package name | No — derive from the dsc URL basename |
| Version | No — already in `<PREFIX>_VERSION*` |
| Stock dsc URL | Yes — but using the existing naming `<PREFIX>_DSC_URL` (`iproute2` already does this) |
| Patch directory | No — find the directory containing `series` under `src/<pkg>/` |
| Apply method (stgit/quilt) | No — generating a source package does not reproduce the apply step; patches stay unapplied |
| `ddeb` marker | No — a deb name ending in `-dbgsym` is one |
| Per-package version-suffix override | Yes — but it collapses into an on-demand variable in `rules/config` plus one function |
| Candidate package set | No — passed to the script as arguments, defaulting to `SONIC_PPA_PACKAGES` |

The Makefile route also comes with three benefits for free: `rules/config.user` gives per-developer overrides (especially useful during migration, and it is already the only file this project modifies locally); `rules/*.mk` already `export`s the relevant variables for sub-makes, so a script launched from a make target reads them straight from the environment with no parsing; and `rules/config` already carries 51 `?=` switches, so the style matches.

YAML's one genuine advantage is "one file shows every package's state". That is compensated by `make ppa-manifest` — derived 100% from the `.mk` files, an **artifact** rather than a **source of truth**, and therefore incapable of drifting.

### 4.3 Dual mode, not a clean cut

Every package keeps its local self-build path, and `SONIC_PPA_PACKAGES` selects which route it takes. When a package misbehaves on the PPA, changing one variable rolls it back without blocking the whole image build, and it makes "was this regression introduced by the PPA?" bisectable. The local branches can be deleted incrementally once things are proven.

---

## 5. Architecture

```
rules/config                     global switches (overridable from config.user)
  ├─ SONIC_PPA_URL               PPA pool root URL (left empty in this phase)
  ├─ SONIC_PPA_SUFFIX            global version suffix, default +sonic1~ppa1
  ├─ SONIC_PPA_SUFFIX_<pkg>      per-package override, present only when needed
  └─ SONIC_PPA_PACKAGES          list of packages served from the PPA

rules/ppa-functions              5 helper functions (§6.2); a new file, deliberately
                                 kept out of SONIC_COMMON_FILES_LIST (see §3.2)

rules/<pkg>.mk                   1 changed line + 1 ifneq block (§6.3)
rules/<pkg>.dep                  2 inserted lines (§6.4)

scripts/ppa/query.mk             the single fact exit: includes rules/<pkg>.mk in a
                                 minimal stub context and prints mode / versions /
                                 dsc URL / patch dir / deb list as key=value. Shared
                                 by the three scripts below and by the unit tests, so
                                 rules/*.mk stays the only source for those facts.
scripts/ppa/build-source.sh      in-container: produce unsigned source packages → target/source/<pkg>/
scripts/ppa/build-clean.sh       build the source package in a throwaway
                                 ubuntu:resolute container, modelling the
                                 Launchpad builder (acceptance criterion 1)
scripts/ppa/sign-upload.sh       on the host: debsign → dput
scripts/ppa/manifest.sh          implements make ppa-manifest, prints the status table
```

Data flow:

```
rules/<pkg>.mk (version + dsc URL + patch dir)
        │
        ├──► make: decides whether this package is downloaded from the PPA or built locally
        │
        └──► build-source.sh: dget stock → copy patches into debian/patches → dch → dpkg-buildpackage -S
                        │
                        └──► host debsign + dput ──► Launchpad build ──► PPA pool
                                                                            │
                                                    SONIC_ONLINE_DEBS curl ─┘
```

---

## 6. Detailed design

### 6.1 Additions to `rules/config`

```make
# ---- Launchpad PPA consumption (resolute only) ----
# Packages served from the PPA instead of built locally. Empty = behave exactly as today.
SONIC_PPA_PACKAGES ?=
# PPA pool root URL, e.g. https://ppa.launchpadcontent.net/<owner>/<name>/ubuntu
SONIC_PPA_URL ?=
# Global default version suffix; override per package with SONIC_PPA_SUFFIX_<pkg> on re-upload
SONIC_PPA_SUFFIX ?= +sonic1~ppa1
```

With `SONIC_PPA_PACKAGES` empty every `ifneq` branch evaluates false, so non-resolute builds are bit-identical to today.

The five functions below live in a **new `rules/ppa-functions`** (included at `slave.mk:290`), not appended to `rules/functions` — see §3.2 for why.

### 6.2 The new `rules/ppa-functions`

```make
# A per-package override wins over the global default
ppa_suffix = $(or $(SONIC_PPA_SUFFIX_$(1)),$(SONIC_PPA_SUFFIX))

# Emit a suffix only when the package is in PPA mode; for inlining into version variables
ppa_ver = $(if $(filter $(1),$(SONIC_PPA_PACKAGES)),$(call ppa_suffix,$(1)))

# Debian pool second-level directory: libxxx → libx, otherwise the first letter
ppa_pool_dir = $(if $(filter lib%,$(1)),$(shell echo $(1) | cut -c1-4),$(shell echo $(1) | cut -c1))

# dbgsym is a .ddeb on a PPA; only the URL side changes — make target and on-disk name stay .deb
ppa_file = $(if $(findstring -dbgsym,$(1)),$(patsubst %.deb,%.ddeb,$(1)),$(1))
ppa_url  = $(SONIC_PPA_URL)/pool/main/$(call ppa_pool_dir,$(1))/$(1)/$(call ppa_file,$(2))
```

All five functions carry the `ppa_` prefix: make variables and functions share one global namespace, so a generic name like `pool_dir` invites a collision with something already in `rules/functions` or added later.

`ppa_pool_dir`'s `$(shell cut)` runs once per package during make's parse phase, so the cost is negligible; if it ever becomes hot it can be rewritten in pure make.

### 6.3 Shape of the `rules/<pkg>.mk` change

Constraint: **prefer pure insertions; never re-indent**. This repository is rebased onto `sonic-net/202605` repeatedly (and has already been through one upstream force-rewrite); re-indenting would turn every future upstream edit to these files into a conflict. Hence the suffix is inlined into the version variable so that every deb-name definition and every `add_derived_package` call stays literally unchanged, and an `ifneq/else/endif` is inserted only at the registration point.

Using `lm-sensors` as the example (the version line is the only modified line):

```diff
-LM_SENSORS_VERSION_FULL=$(LM_SENSORS_VERSION)-2build1
+LM_SENSORS_VERSION_STOCK=$(LM_SENSORS_VERSION)-2build1
+LM_SENSORS_VERSION_FULL=$(LM_SENSORS_VERSION_STOCK)$(call ppa_ver,lm-sensors)
+
+LM_SENSORS_DSC_URL = http://archive.ubuntu.com/ubuntu/pool/main/l/lm-sensors/lm-sensors_$(LM_SENSORS_VERSION_STOCK).dsc

 ... 7 deb definitions and add_derived_package calls, all untouched ...

-SONIC_MAKE_DEBS += $(LM_SENSORS)
+ifneq ($(filter lm-sensors,$(SONIC_PPA_PACKAGES)),)
+SONIC_ONLINE_DEBS += $(LM_SENSORS)
+$(LM_SENSORS)_URL     = $(call ppa_url,lm-sensors,$(LM_SENSORS))
+$(LM_SENSORS_DBG)_URL = $(call ppa_url,lm-sensors,$(LM_SENSORS_DBG))
+$(FANCONTROL)_URL     = $(call ppa_url,lm-sensors,$(FANCONTROL))
+$(LIBSENSORS)_URL     = $(call ppa_url,lm-sensors,$(LIBSENSORS))
+$(LIBSENSORS_DBG)_URL = $(call ppa_url,lm-sensors,$(LIBSENSORS_DBG))
+$(SENSORD)_URL        = $(call ppa_url,lm-sensors,$(SENSORD))
+$(SENSORD_DBG)_URL    = $(call ppa_url,lm-sensors,$(SENSORD_DBG))
+else
+SONIC_MAKE_DEBS += $(LM_SENSORS)
+endif
+
+export LM_SENSORS_DSC_URL
```

Key points:

- An intermediate `_VERSION_STOCK` variable is mandatory. `_DSC_URL` points at the official source package and therefore uses the **stock version** (no PPA suffix), so it cannot reuse the now-suffixed `_VERSION_FULL`; writing the `-2build1` literal directly into `_DSC_URL` would put the same literal in two places and guarantee one of them gets missed on a version bump. This is the single easiest thing to get wrong in each package's migration.
- The hardcoded `pool/main/` in `ppa_url` is correct: a PPA has only one component, `main`, regardless of whether the package sits in `main` or `universe` in the official Ubuntu archive (`monit`, for example, is in universe officially but lands in `pool/main/m/monit/` in a PPA).
- The `_URL` overrides must come after every `add_derived_package` call (§3.4). The existing layout of `lm-sensors.mk` and `libteam.mk` already satisfies this.
- `fancontrol` is an `_all.deb`; the name comes from the existing variable, so Arch: all is handled automatically.
- The local branch contains only the original `SONIC_MAKE_DEBS += ...` line. Declarations such as `_SRC_PATH` stay outside the `ifneq`, untouched — a leftover `_SRC_PATH` is harmless in PPA mode because the `.dep` guard keys off the package name rather than off whether SPATH is empty.

### 6.4 Shape of the `rules/<pkg>.dep` change

Two inserted lines, zero modified:

```diff
 SPATH       := $($(LM_SENSORS)_SRC_PATH)
 DEP_FILES   := $(SONIC_COMMON_FILES_LIST) rules/lm-sensors.mk rules/lm-sensors.dep
 DEP_FILES   += $(SONIC_COMMON_BASE_FILES_LIST)
+ifeq ($(filter lm-sensors,$(SONIC_PPA_PACKAGES)),)
 DEP_FILES   += $(shell git ls-files $(SPATH))
+endif
```

Keying off the package name rather than off `$(SPATH)` being empty is clearer and keeps the guard condition identical to the one in the `.mk`. In PPA mode the cache key degrades to the `.mk` content — which includes the version and suffix, so changing the suffix correctly invalidates the cache and triggers a fresh download.

### 6.5 Source-package generation scripts

Signing and uploading do not happen inside the container — mounting the GPG agent socket into a DinD container is expensive and fragile. The three actions are orthogonal and each runs on its own:

```
# In the container (slave-resolute already ships devscripts / quilt / stgit / python3-yaml)
scripts/ppa/build-source.sh <pkg>...
  1. dget -d -u $(<PREFIX>_DSC_URL)                 # -d downloads without extracting; -u is
                                                    #   required because the .dsc uploader's key
                                                    #   is in no available keyring on Ubuntu
     dpkg-source --skip-patches -x <dsc>            # extract applying nothing; tree stays pristine
  2. Locate the directory containing `series` under src/<pkg>/ (error out if more than one)
  3. Classify each active patch per the rules in section 2.1, from the paths on **both**
     its `---` and `+++` headers, ignoring whichever side is `/dev/null` — so a patch
     that deletes a file classifies by that file's real path:
       upstream files only -> copy into debian/patches/ and append to series (left unapplied)
       debian/ only        -> apply directly to the tree, keep it out of the series
       both                -> error out naming the patch; a human must split it
  4. Check whether any patch contains binary files; error out if so (would need
     debian/source/include-binaries — none in scope today)
  4b. Read the stock epoch from the pristine changelog, carry it into the new version,
      and cross-check the changelog version against <PREFIX>_VERSION_STOCK. Without this,
      lm-sensors (1:3.6.2-2build1) would publish an implicit-epoch-0 version that can
      never supersede the archive.
  5. dch --newversion <stock-version><suffix> --distribution resolute --force-distribution
     (--force-distribution is required: dch otherwise refuses to change the
      distribution to anything but the current one)
  6. dpkg-buildpackage -S -sa -us -uc               # or -sd, see below
  7. Emit into target/source/<pkg>/

# On the host (needs devscripts + dput; the slave image has no dput and does not need one)
scripts/ppa/sign-upload.sh [--key <KEYID>] [--upload]
  debsign -k <KEYID> target/source/*/*_source.changes
  dput ppa:<owner>/<name> target/source/*/*_source.changes
```

`-sa` (include the orig) is used only on the first upload of a given upstream version; subsequent uploads with the same orig must use `-sd`, or Launchpad rejects them over an orig checksum conflict. The script picks automatically based on whether that orig already exists in the PPA pool; **when it cannot tell it defaults to `-sa`** — a needless orig re-upload is usually harmless, whereas a first upload missing its orig is rejected outright, so `-sa` is the conservative direction.

The `-u` in `dget -u` is structurally required: on an Ubuntu slave the `.dsc` uploader's personal key is not in any available keyring, and installing `debian-keyring` does not help.

### 6.6 `make ppa-manifest`

Prints, per candidate package: name, mode (ppa/local), stock version, effective suffix, and the artifact deb **count**; the deb list requires `VERBOSE=1`, and the fetch URL is not printed (query `query.mk` directly when needed). This replaces the "single overview file" value YAML would have provided. Implemented as `scripts/ppa/manifest.sh`, invoked from a phony target in `slave.mk`, with all data coming from already-exported make variables.

---

## 7. Versioning and dbgsym

**Versioning**: `<stock-version><SONIC_PPA_SUFFIX>`, default `+sonic1~ppa1`. It sorts above stock and below the next Ubuntu revision — `1.31-1build4+sonic1~ppa1` > `1.31-1build4` but < `1.31-1build5`. When Ubuntu issues an SRU it naturally supersedes ours, which is the desired behaviour. When the same SONiC revision needs a re-upload, bump that package's suffix to `~ppa2` (`SONIC_PPA_SUFFIX_<pkg>`); an already-uploaded version number cannot be reused, Launchpad rejects it.

**dbgsym**: the artifact on a PPA is a `.ddeb` (§3.6). `ppa_file` changes only the URL side; the make target and on-disk name stay `...-dbgsym_<ver>_amd64.deb`, held up by the `curl -o` in §3.3, so nothing on the SONiC side changes.

Prerequisite: the PPA must have debug-symbol publishing enabled (a per-PPA setting, not on by default). **This is an open verification item.** If it cannot be enabled, the fallback is the pattern already in `rules/lldpd.mk` — keep the variable defined so `rules/docker-*.mk` references do not error, but leave it out of `SONIC_ONLINE_DEBS`, giving up debug symbols for those packages.

---

## 8. The first three packages

Selection criterion is **risk-dimension coverage**, not "start with the easy ones".

| Package | Risk covered | Why it has to be this one |
|---|---|---|
| **libteam** | Clean baseline | All 14 active patches are in the series (4 more are commented out), **zero out-of-tree actions**, 7 binaries (1 main + 6 derived, 3 of them dbgsym), has `_DEPENDS` ordering, has `add_derived_package`. If it fails, the pipeline itself is wrong rather than one package being special. Should be done first. |
| **isc-dhcp** | Guaranteed build failure class | Without internalising `DEB_CFLAGS_MAINT_STRIP` / `DEB_LDFLAGS_MAINT_STRIP` into `debian/rules` it cannot build. 19 patches (highest fuzz risk). A Debian source uploaded to an Ubuntu PPA. |
| **lm-sensors** | Builds fine but the artifact is wrong | `PROG_EXTRA=sensord` is a functional out-of-tree variable: losing it raises no error, `sensord` simply does not exist — and `docker-platform-monitor` needs it. This is the only silent-failure class, so it must be exercised in the first batch, and it also tests whether the acceptance criteria in §9 actually catch it. Plus 7 binaries, one of them `_all.deb`, plus nocheck. |

**`socat` is deliberately excluded from the first batch**: the sole reason it is self-built is `enable_readline`, and Debian/Ubuntu disable readline **on purpose** (GPL/OpenSSL licence incompatibility, Debian #632481). Publishing a readline-enabled socat in a public PPA means distributing a binary Debian considers undistributable. That needs a public/private PPA decision and a licensing call first, so it does not belong in the batch whose job is to prove the pipeline. Its patch is also applied with `patch -p1` outside the series, adding another conversion risk.

**`bash` is excluded from the first batch**: its distinctive risk (losing `DEB_BUILD_OPTIONS=nocheck`) is already covered by `lm-sensors`, and its other out-of-tree action, `cp -a ../Files/. ./`, only serves local unit tests and does not affect the artifact.

**The second batch should start with `libyang3`**: it has the most out-of-tree actions — `sed -i` removing the libxxhash build-dep from `debian/control`, a `patch -p1` outside the series, and `-d` to skip the build-dep check — covering all three leakage shapes at once.

---

## 9. Acceptance criteria

Each package is accepted independently; all four must pass before its migration counts as done:

1. **The source package builds in a clean environment.** Build the generated `.dsc` with `scripts/ppa/build-clean.sh` in a throwaway `ubuntu:resolute` container, depending on nothing preinstalled in the slave container. This runs locally before uploading and is what surfaces the lost out-of-tree actions from §3.7 early.

  `sbuild`/`pbuilder` are deliberately **not** used: they would mean installing four packages on the host, building a persistent `/srv/chroot` tree, running `sbuild-adduser` and logging back in — all requiring sudo — while this project's rule is that host modifications are a last resort. `ubuntu:resolute` is the slave image's own `FROM` base, already pulled by the build; `docker run --rm` starts from the pristine image every time and is therefore clean by construction; and it does **not** carry the slave's `Dh_Lib.pm` patch, so dbgsym is emitted as a real `.ddeb`, which incidentally verifies §3.6. Fidelity matches sbuild: a Launchpad builder also resolves `Build-Depends` through apt, and it is only the build itself that has no internet.
2. **Artifact file lists match.** `dpkg -c` diff between the PPA artifact and the locally built one shows identical file lists apart from version strings. This is the criterion that catches the `lm-sensors` class of silent omission.
3. **Binary package sets match.** The debs actually published by the PPA correspond exactly to the main plus derived package set declared in `rules/<pkg>.mk` — nothing missing, nothing extra.
4. **The full image builds.** With the package present in `SONIC_PPA_PACKAGES`, both the vs and broadcom targets complete.

If any criterion fails, removing the package from `SONIC_PPA_PACKAGES` rolls it back without blocking the others.

---

## 10. Known risks and open items

| Item | Status | Notes |
|---|---|---|
| PPA ownership, public vs private | **Open**, not blocking this phase | Leaving `SONIC_PPA_URL` empty is enough to build the whole scaffold and verify locally up to "the source package builds in a clean chroot". Upload and end-to-end verification need the ownership decision. A private PPA's pool requires authentication, so the `curl` side would need credentials — introducing extra design work around `_CURL_OPTIONS`. |
| dbgsym publishing switch | **To verify** | See §7. Fallback already decided. |
| `socat` readline licensing | **To decide** | See §8. |
| Patch fuzz | Known risk | `stg import` tolerates fuzz; `dpkg-source` applies patches with zero fuzz before building. Older patches may need refreshing. `isc-dhcp`'s 19 patches carry the highest risk, which is why it is in the first batch. |
| `DBG_SRC_ARCHIVE` degradation | Accepted | That mechanism archives `.c/.h` files under `src/<name>` into the debug image. In PPA mode only patches remain in that directory, so the archive will be nearly empty. Cosmetic degradation, not blocking. |
| `_DEPENDS` semantic drift | Known | In local mode `$(LIBTEAM)_DEPENDS += $(LIBNL_GENL3_DEV) ...` expresses a build dependency; in online mode `_DEPENDS` expresses `dpkg -i` ordering. Keeping the original declaration means a different but harmless semantics in PPA mode (a more conservative install order). Confirm per package that it introduces no cycle. |
| Build reproducibility | Accepted trade-off | After migration these artifacts come from an external service, so "everything is reproducible locally from source" no longer holds. That is the inherent cost of decoupling; the dual-mode switch preserves the ability to return to local builds at any time. |

---

## 11. Implementation order

1. Three variables in `rules/config`, five functions in `rules/ppa-functions`, `scripts/ppa/query.mk`, and the unit-test harness. At this point `SONIC_PPA_PACKAGES` is empty and build behaviour is unchanged.
2. Land `libteam`: change `.mk` / `.dep`, write `build-source.sh` to produce the source package, write `build-clean.sh` and use it to satisfy acceptance criterion 1. No sudo and no host modification anywhere in the sequence.
3. Land `isc-dhcp`: additionally internalise `DEB_*_MAINT_STRIP` as a patch in `debian/patches`.
4. Land `lm-sensors`: additionally internalise `PROG_EXTRA=sensord` into `debian/rules`.
5. `make ppa-manifest`.
6. Once PPA ownership is decided: sign, upload, and complete criteria 2–4.

Steps 1–5 do not depend on the PPA ownership decision and can start immediately.
