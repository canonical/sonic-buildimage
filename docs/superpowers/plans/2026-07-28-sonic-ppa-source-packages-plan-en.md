# PPA Source-Package Scaffolding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the dual-mode scaffolding inside `sonic-buildimage` — packaging recipes stay in the tree, prebuilt artifacts come from a Launchpad PPA — and take the first three packages (`libteam` / `isc-dhcp` / `lm-sensors`) as far as "the source package builds in a clean chroot".

**Architecture:** Three switches in `rules/config` decide per package whether it comes from the PPA or is built locally. Four functions in `rules/functions` centralise the version-suffix and pool-URL derivation. Each `rules/<pkg>.mk` gets a pure-insertion mode branch. `scripts/ppa/query.mk` includes `rules/<pkg>.mk` in a minimal stub context and prints key=value, making it the single fact source for both the scripts and the tests. Source packages are generated unsigned inside the slave container; signing and uploading happen on the host.

**Tech Stack:** GNU Make (conditionals, `$(call)` functions), Bash, `devscripts` (`dget` / `dch` / `debsign` / `dpkg-buildpackage -S`), quilt patch format, a throwaway `ubuntu:resolute` docker container (the clean build environment), `dput`. On the host side only the already-installed `debsign` and `dput` are used — **no sudo and no host modification anywhere**.

**Design document:** [2026-07-28 PPA source-package design](../specs/2026-07-28-sonic-ppa-source-packages-design-en.md)

**Workspace:** the implementation happens on a worktree branch off `202605_resolute_sheldon` (create it with superpowers:using-git-worktrees at execution time). This plan document itself lives on `202605_resolute_doc`.

---

## Global Constraints

- **Only affects `BLDENV=resolute`.** `SONIC_PPA_PACKAGES` defaults to empty; while empty, build behaviour is identical to before this mechanism existed. Nothing about `trixie` / `bookworm` / `bullseye` changes.
- **Pure insertions preferred; never re-indent.** This repository is rebased onto `sonic-net/202605` repeatedly (and has already been through one upstream force-rewrite). When editing `rules/*.mk`, `rules/*.dep` or `src/*/Makefile`, only insert new lines and modify the lines that genuinely must change; never indent existing lines just to nest them inside an `ifneq` block.
- **Exactly two new variables per package**: `<PREFIX>_VERSION_STOCK` (upstream version without the PPA suffix) and `<PREFIX>_DSC_URL` (official `.dsc` location). `<PREFIX>` is the package directory name through `tr 'a-z-' 'A-Z_'`: `libteam`→`LIBTEAM`, `isc-dhcp`→`ISC_DHCP`, `lm-sensors`→`LM_SENSORS`. Both must be `export`ed.
- **`ppa_*` functions must not be used in `rules/sonic-fips.mk`.** `rules/functions` is only included from `slave.mk:289`, while `Makefile.work:155` includes `rules/sonic-fips.mk` in a host-side context that does **not** have `rules/functions`. This batch does not touch that file, but later batches must respect it.
- **Version** = `<stock version><suffix>`, suffix defaulting to `+sonic1~ppa1`. A re-upload of the same revision bumps one package via `SONIC_PPA_SUFFIX_<pkg>` to `~ppa2`. An already-uploaded version number cannot be reused; Launchpad rejects it.
- **Signing and uploading happen on the host only.** Everything produced in the container is unsigned (`-us -uc`).
- **dbgsym**: `.ddeb` on the URL side, `.deb` for the make target and on-disk name. This works because `slave.mk:761` is `curl -L -f -o <local name> <URL>`, which allows the two to differ.
- **Commits must be GPG-signed** (this repo has `commit.gpgsign=true`), and each commit message ends with `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`.
- **`scripts/ppa/query.mk` must not include `slave.mk`.** It has to run in a bare checkout with no docker and no prior `make configure`.

---

## File Structure

| File | Responsibility |
|---|---|
| `rules/config` | The three global switches (`SONIC_PPA_PACKAGES` / `SONIC_PPA_URL` / `SONIC_PPA_SUFFIX`). Modified, not created. |
| `rules/functions` | The four `ppa_*` derivation functions. Modified, not created. |
| `scripts/ppa/query.mk` | **The single fact exit**: includes `rules/<pkg>.mk` in a stub context and prints mode, versions, dsc URL, patch dir and deb list as key=value. Shared by three scripts and two test suites. |
| `scripts/ppa/build-source.sh` | In-container: `dget` stock → patches into `debian/patches` → `dch` → `dpkg-buildpackage -S` → `target/source/<pkg>/`. |
| `scripts/ppa/build-clean.sh` | Build the source package in a throwaway `ubuntu:resolute` container, modelling the Launchpad builder. Used for acceptance criterion 1. |
| `scripts/ppa/sign-upload.sh` | On the host: `debsign` plus optional `dput`. |
| `scripts/ppa/manifest.sh` | Implements `make ppa-manifest`; prints the status table. |
| `scripts/ppa/tests/functions_test.mk` | Unit tests for the four `ppa_*` functions (10 cases). |
| `scripts/ppa/tests/rules_test.mk` | Dual-mode unit tests for `rules/<pkg>.mk` (registration lists and URLs in each mode). |
| `scripts/ppa/tests/run-tests.sh` | Runs the two `.mk` suites; non-zero exit means failure. |
| `rules/{libteam,isc-dhcp,lm-sensors}.mk` | Two new variables plus one `ifneq/else/endif` registration branch each. |
| `rules/{libteam,isc-dhcp,lm-sensors}.dep` | A two-line `ifeq/endif` guard each. |
| `src/{libteam,isc-dhcp,lm-sensors}/Makefile` | `dget` switches to `$(<PREFIX>_DSC_URL)`, removing the hardcoded URL. |
| `src/isc-dhcp/patch/0019-resolute-disable-lto.patch` | Internalises `DEB_*_MAINT_STRIP` into `debian/rules`. |
| `src/lm-sensors/patch/0003-build-sensord-via-prog-extra.patch` | Internalises `PROG_EXTRA=sensord` into `debian/rules`. |
| `slave.mk` | One `ppa-manifest` phony target. |

---

## Task 1: The make layer (switches, functions, query.mk, test harness)

**Files:**
- Modify: `rules/config` (append at end of file)
- Modify: `rules/functions` (append at end of file)
- Create: `scripts/ppa/query.mk`
- Create: `scripts/ppa/tests/functions_test.mk`
- Create: `scripts/ppa/tests/run-tests.sh`

**Interfaces:**
- Produces (later tasks depend on these):
  - `$(call ppa_suffix,<pkg>)` → suffix string, e.g. `+sonic1~ppa1`
  - `$(call ppa_ver,<pkg>)` → the suffix when that package is in PPA mode, empty string otherwise
  - `$(call ppa_pool_dir,<src-name>)` → pool second-level directory, e.g. `libt` / `l`
  - `$(call ppa_file,<deb-name>)` → dbgsym names become `.ddeb`, everything else unchanged
  - `$(call ppa_url,<src-name>,<deb-name>)` → full download URL
  - `make -s -f scripts/ppa/query.mk PKG=<pkg>` → prints nine lines: `PKG=` `MODE=` `STOCK_VERSION=` `DSC_URL=` `SUFFIX=` `PATCH_DIR=` `MAIN_DEB=` `DERIVED_DEBS=` `SOURCE=`
  - Variables `SONIC_PPA_PACKAGES` / `SONIC_PPA_URL` / `SONIC_PPA_SUFFIX` / `SONIC_PPA_SUFFIX_<pkg>`

- [ ] **Step 1: Write the failing unit tests**

Create `scripts/ppa/tests/functions_test.mk`:

```make
# Unit tests for the ppa_* helper functions. Does not include slave.mk — only
# rules/functions — so this runs instantly in a bare checkout.
# Usage: make -s -f scripts/ppa/tests/functions_test.mk

SONIC_PPA_URL              := https://ppa.launchpadcontent.net/o/n/ubuntu
SONIC_PPA_SUFFIX           := +sonic1~ppa1
SONIC_PPA_SUFFIX_lm-sensors := +sonic1~ppa2
SONIC_PPA_PACKAGES         := libteam lm-sensors

include rules/functions

FAILURES :=

# assert <name>,<actual>,<expected>
define assert
$(if $(filter-out x$(3),x$(2)),\
  $(warning FAIL $(1): got "$(2)" want "$(3)")$(eval FAILURES += $(1)),\
  $(info ok   $(1)))
endef

$(call assert,ppa_ver-on,$(call ppa_ver,libteam),+sonic1~ppa1)
$(call assert,ppa_ver-off,$(call ppa_ver,isc-dhcp),)
$(call assert,ppa_suffix-global,$(call ppa_suffix,libteam),+sonic1~ppa1)
$(call assert,ppa_suffix-override,$(call ppa_suffix,lm-sensors),+sonic1~ppa2)
$(call assert,pool_dir-lib,$(call ppa_pool_dir,libteam),libt)
$(call assert,pool_dir-plain,$(call ppa_pool_dir,lm-sensors),l)
$(call assert,pool_dir-hyphen,$(call ppa_pool_dir,isc-dhcp),i)
$(call assert,ppa_file-plain,$(call ppa_file,libteam5_1.31-1build4_amd64.deb),libteam5_1.31-1build4_amd64.deb)
$(call assert,ppa_file-dbgsym,$(call ppa_file,libteam5-dbgsym_1.31-1build4_amd64.deb),libteam5-dbgsym_1.31-1build4_amd64.ddeb)
$(call assert,ppa_url-dbgsym,$(call ppa_url,libteam,libteam5-dbgsym_1.31-1build4_amd64.deb),https://ppa.launchpadcontent.net/o/n/ubuntu/pool/main/libt/libteam/libteam5-dbgsym_1.31-1build4_amd64.ddeb)
$(call assert,ppa_url-all-deb,$(call ppa_url,lm-sensors,fancontrol_3.6.2-2build1+sonic1~ppa2_all.deb),https://ppa.launchpadcontent.net/o/n/ubuntu/pool/main/l/lm-sensors/fancontrol_3.6.2-2build1+sonic1~ppa2_all.deb)

.PHONY: default
default:
ifneq ($(strip $(FAILURES)),)
	@echo "FAILED: $(FAILURES)"; exit 1
else
	@echo "functions_test: all assertions passed"
endif
```

Create `scripts/ppa/tests/run-tests.sh` (`chmod +x`):

```bash
#!/bin/bash
# Run every make-layer unit test for the PPA scaffolding. Must run from the
# repository root.
set -euo pipefail

cd "$(dirname "$0")/../../.."

rc=0
for t in scripts/ppa/tests/*_test.mk; do
    echo "== $t"
    make -s -f "$t" || rc=1
done

if [ "$rc" -ne 0 ]; then
    echo "PPA make-layer tests FAILED"
    exit 1
fi
echo "PPA make-layer tests passed"
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
chmod +x scripts/ppa/tests/run-tests.sh
./scripts/ppa/tests/run-tests.sh
```

Expected: exit code 1, with `FAIL` lines because the `ppa_*` functions do not exist yet so every `$(call ...)` expands to an empty string. You should see `FAIL ppa_ver-on: got "" want "+sonic1~ppa1"` and similar, ending with `FAILED: ...`. (`ppa_ver-off` will pass by accident — its expected value is the empty string.)

- [ ] **Step 3: Append the three switches to the end of `rules/config`**

```make

# ---- Launchpad PPA consumption (resolute only) ----

# SONIC_PPA_PACKAGES - packages fetched as prebuilt debs from the PPA instead
# of built locally, listed by their directory name under src/, space separated.
# Empty means everything is built locally and behaviour is identical to before
# this mechanism existed. Override in rules/config.user to flip one package
# back to a local build on a single machine.
SONIC_PPA_PACKAGES ?=

# SONIC_PPA_URL - the PPA's pool root URL. Must use ppa.launchpadcontent.net
# directly: the +files form redirects to launchpadlibrarian.net, which is
# unreachable from the build environment.
# e.g. https://ppa.launchpadcontent.net/<owner>/<name>/ubuntu
SONIC_PPA_URL ?=

# SONIC_PPA_SUFFIX - the SONiC revision suffix appended to the upstream
# version. It sorts above the stock version and below the next Ubuntu
# revision, so an Ubuntu SRU naturally supersedes ours. To re-upload the same
# revision, override one package with SONIC_PPA_SUFFIX_<pkg>, e.g.
#   SONIC_PPA_SUFFIX_libteam ?= +sonic1~ppa2
SONIC_PPA_SUFFIX ?= +sonic1~ppa1
```

- [ ] **Step 4: Append the four functions to the end of `rules/functions`**

```make

# ---- Launchpad PPA helpers ----
#
# NOTE: this file is only included from slave.mk:289. Makefile.work:155
# includes rules/sonic-fips.mk in a host-side context without this file, so
# the functions below must not be used there.

# ppa_suffix <pkg> — a per-package override wins over the global default
ppa_suffix = $(or $(SONIC_PPA_SUFFIX_$(1)),$(SONIC_PPA_SUFFIX))

# ppa_ver <pkg> — the suffix when the package is in PPA mode, empty otherwise.
# Inlined into <PREFIX>_VERSION_FULL so no deb-name definition needs a branch.
ppa_ver = $(if $(filter $(1),$(SONIC_PPA_PACKAGES)),$(call ppa_suffix,$(1)))

# ppa_pool_dir <source-name> — Debian pool second level: libxxx → libx,
# otherwise the first letter
ppa_pool_dir = $(if $(filter lib%,$(1)),$(shell echo $(1) | cut -c1-4),$(shell echo $(1) | cut -c1))

# ppa_file <deb-name> — dbgsym is published as .ddeb on a PPA (the Dh_Lib.pm
# patch in the slave image cannot be applied on a Launchpad builder). Only the
# URL side changes; the make target and on-disk name stay .deb, held up by the
# curl -o in slave.mk:761.
ppa_file = $(if $(findstring -dbgsym,$(1)),$(patsubst %.deb,%.ddeb,$(1)),$(1))

# ppa_url <source-name>,<deb-name> — a PPA has only one component, main,
# regardless of whether the package is in main or universe in the official
# Ubuntu archive (monit is in universe officially but lands in
# pool/main/m/monit/ in a PPA).
ppa_url = $(SONIC_PPA_URL)/pool/main/$(call ppa_pool_dir,$(1))/$(1)/$(call ppa_file,$(2))
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
./scripts/ppa/tests/run-tests.sh
```

Expected: exit code 0, eleven lines of output — ten `ok   ...` plus `functions_test: all assertions passed`.

- [ ] **Step 6: Create `scripts/ppa/query.mk`**

```make
# Includes rules/<pkg>.mk in a minimal stub context and prints the PPA facts as
# key=value. scripts/ppa/*.sh and scripts/ppa/tests/* both read this, so
# rules/*.mk stays the only place those facts are written and no parallel
# manifest is needed.
#
# Usage: make -s -f scripts/ppa/query.mk PKG=libteam
#
# Deliberately does not include slave.mk — this has to run in a bare checkout
# with no docker and no prior 'make configure'.

PKG ?=
ifeq ($(PKG),)
$(error PKG is required, e.g. make -s -f scripts/ppa/query.mk PKG=libteam)
endif

# The minimal context rules/<pkg>.mk expects
CONFIGURED_ARCH    ?= amd64
SRC_PATH           := src
SONIC_MAKE_DEBS    :=
SONIC_ONLINE_DEBS  :=
SONIC_DERIVED_DEBS :=

include rules/config
-include rules/config.user
include rules/functions
include rules/$(PKG).mk

# Package directory name → make variable prefix
PREFIX     := $(shell echo $(PKG) | tr 'a-z-' 'A-Z_')

# The main deb is read back out of whichever registration list is non-empty.
# That avoids needing a rule for "what is the main deb variable called" —
# isc-dhcp's is ISC_DHCP_RELAY, which is not the PREFIX.
MAIN_DEB   := $(strip $(SONIC_MAKE_DEBS) $(SONIC_ONLINE_DEBS))
MODE       := $(if $(filter $(PKG),$(SONIC_PPA_PACKAGES)),ppa,local)

# The patch directory containing a series file. More than one is ambiguous —
# error out rather than guess.
PATCH_DIRS := $(patsubst %/series,%,$(wildcard src/$(PKG)/*/series))

ifneq ($(words $(MAIN_DEB)),1)
$(error $(PKG): expected exactly 1 main deb, got "$(MAIN_DEB)")
endif
ifneq ($(words $(PATCH_DIRS)),1)
$(error $(PKG): expected exactly 1 patch dir containing a series file, got "$(PATCH_DIRS)")
endif

.PHONY: default
default:
	@echo 'PKG=$(PKG)'
	@echo 'MODE=$(MODE)'
	@echo 'STOCK_VERSION=$($(PREFIX)_VERSION_STOCK)'
	@echo 'DSC_URL=$($(PREFIX)_DSC_URL)'
	@echo 'SUFFIX=$(call ppa_suffix,$(PKG))'
	@echo 'PATCH_DIR=$(PATCH_DIRS)'
	@echo 'MAIN_DEB=$(MAIN_DEB)'
	@echo 'DERIVED_DEBS=$(SONIC_DERIVED_DEBS)'
	@echo 'SOURCE=$(firstword $(subst _, ,$(notdir $($(PREFIX)_DSC_URL))))'
```

- [ ] **Step 7: Verify query.mk runs for all three packages**

```bash
for p in libteam isc-dhcp lm-sensors; do echo "--- $p"; make -s -f scripts/ppa/query.mk PKG=$p; done
```

Expected (this task has not yet added `_VERSION_STOCK` / `_DSC_URL` to the packages, so those lines are empty — that is correct at this point):

```
--- libteam
PKG=libteam
MODE=local
STOCK_VERSION=
DSC_URL=
SUFFIX=+sonic1~ppa1
PATCH_DIR=src/libteam/patch
MAIN_DEB=libteam5_1.31-1build4_amd64.deb
DERIVED_DEBS=libteam5-dbgsym_1.31-1build4_amd64.deb libteam-dev_1.31-1build4_amd64.deb libteamdctl0_1.31-1build4_amd64.deb libteamdctl0-dbgsym_1.31-1build4_amd64.deb libteam-utils_1.31-1build4_amd64.deb libteam-utils-dbgsym_1.31-1build4_amd64.deb
SOURCE=
--- isc-dhcp
...
MAIN_DEB=isc-dhcp-relay_4.4.3-P1-2_amd64.deb
DERIVED_DEBS=isc-dhcp-relay-dbgsym_4.4.3-P1-2_amd64.deb
...
--- lm-sensors
...
MAIN_DEB=lm-sensors_3.6.2-2build1_amd64.deb
DERIVED_DEBS=lm-sensors-dbgsym_3.6.2-2build1_amd64.deb fancontrol_3.6.2-2build1_all.deb libsensors5_3.6.2-2build1_amd64.deb libsensors5-dbgsym_3.6.2-2build1_amd64.deb sensord_3.6.2-2build1_amd64.deb sensord-dbgsym_3.6.2-2build1_amd64.deb
```

All three must exit 0, with exactly one `MAIN_DEB` and exactly one `PATCH_DIR`.

- [ ] **Step 8: Confirm the defaults do not change build behaviour**

```bash
grep -cE '^SONIC_PPA_(PACKAGES|URL|SUFFIX) \?=' rules/config
make -s -f scripts/ppa/query.mk PKG=libteam | grep '^MODE='
```

Expected: `grep -c` prints exactly `3` (the three switch assignments); `MODE=local`. Because `SONIC_PPA_PACKAGES` is empty, `SONIC_MAKE_DEBS` still registers libteam and the build path is unchanged.

- [ ] **Step 9: Commit**

```bash
git add rules/config rules/functions scripts/ppa/query.mk scripts/ppa/tests/
git commit -m "build(ppa): add the make layer for PPA-vs-local package selection

Three switches in rules/config (SONIC_PPA_PACKAGES / _URL / _SUFFIX, all
inert when the package list is empty) and four helper functions in
rules/functions that centralise the version-suffix and pool-URL derivation.

scripts/ppa/query.mk includes rules/<pkg>.mk in a minimal stub context and
prints the PPA facts as key=value, so the scripts and the tests read them
from rules/*.mk rather than from a parallel manifest. It deliberately does
not include slave.mk: it has to run in a bare checkout with no docker and
no 'make configure'.

The main deb is read back out of whichever registration list is non-empty
instead of from a per-package variable name, because those names do not
follow a rule (isc-dhcp's is ISC_DHCP_RELAY, not ISC_DHCP).

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Wire libteam (dual mode plus rules unit tests)

`libteam` is the clean baseline: all 14 active patches are in the series and `src/libteam/Makefile` does **nothing** outside `dget` and `dpkg-buildpackage`. A failure here means the scaffolding is wrong, so it goes first.

**Files:**
- Modify: `rules/libteam.mk`
- Modify: `rules/libteam.dep`
- Modify: `src/libteam/Makefile:18`
- Create: `scripts/ppa/tests/rules_test.mk`

**Interfaces:**
- Consumes: `ppa_ver` / `ppa_url` / `SONIC_PPA_*` / `query.mk` from Task 1
- Produces: `LIBTEAM_VERSION_STOCK` = `1.31-1build4`, `LIBTEAM_DSC_URL`; and the `rules/<pkg>.mk` edit shape that Tasks 4 and 5 copy

- [ ] **Step 1: Write the failing unit tests**

Create `scripts/ppa/tests/rules_test.mk`:

```make
# Dual-mode unit tests for rules/<pkg>.mk: verify that depending on whether
# SONIC_PPA_PACKAGES lists the package, it registers into the right list, deb
# names carry the suffix, and each deb's _URL is correct.
# Usage: make -s -f scripts/ppa/tests/rules_test.mk

CONFIGURED_ARCH    := amd64
SRC_PATH           := src
SONIC_MAKE_DEBS    :=
SONIC_ONLINE_DEBS  :=
SONIC_DERIVED_DEBS :=

SONIC_PPA_URL      := https://ppa.launchpadcontent.net/o/n/ubuntu
SONIC_PPA_SUFFIX   := +sonic1~ppa1
# Only libteam is flipped to PPA mode here, to prove the switch is per package
SONIC_PPA_PACKAGES := libteam

include rules/functions
include rules/libteam.mk

FAILURES :=

define assert
$(if $(filter-out x$(3),x$(2)),\
  $(warning FAIL $(1): got "$(2)" want "$(3)")$(eval FAILURES += $(1)),\
  $(info ok   $(1)))
endef

# PPA mode: registers into ONLINE rather than MAKE, and the deb name carries
# the suffix
$(call assert,libteam-online,$(SONIC_ONLINE_DEBS),libteam5_1.31-1build4+sonic1~ppa1_amd64.deb)
$(call assert,libteam-not-make,$(SONIC_MAKE_DEBS),)
$(call assert,libteam-main-name,$(LIBTEAM),libteam5_1.31-1build4+sonic1~ppa1_amd64.deb)
$(call assert,libteam-stock-ver,$(LIBTEAM_VERSION_STOCK),1.31-1build4)

# The derived package count is unchanged (1 main + 6 derived)
$(call assert,libteam-derived-count,$(words $(SONIC_DERIVED_DEBS)),6)

# Main package URL
$(call assert,libteam-main-url,$($(LIBTEAM)_URL),https://ppa.launchpadcontent.net/o/n/ubuntu/pool/main/libt/libteam/libteam5_1.31-1build4+sonic1~ppa1_amd64.deb)

# Each dbgsym derived deb must have its URL overridden to its own address with
# a .ddeb extension (add_derived_package makes it inherit the main deb's URL
# by default — rules/functions:94)
$(call assert,libteam-dbg-url,$($(LIBTEAM_DBG)_URL),https://ppa.launchpadcontent.net/o/n/ubuntu/pool/main/libt/libteam/libteam5-dbgsym_1.31-1build4+sonic1~ppa1_amd64.ddeb)

# A non-dbgsym derived deb keeps .deb
$(call assert,libteam-dev-url,$($(LIBTEAM_DEV)_URL),https://ppa.launchpadcontent.net/o/n/ubuntu/pool/main/libt/libteam/libteam-dev_1.31-1build4+sonic1~ppa1_amd64.deb)

# The dsc URL uses the stock version and must never carry the PPA suffix
$(call assert,libteam-dsc-url,$(LIBTEAM_DSC_URL),http://archive.ubuntu.com/ubuntu/pool/main/libt/libteam/libteam_1.31-1build4.dsc)

.PHONY: default
default:
ifneq ($(strip $(FAILURES)),)
	@echo "FAILED: $(FAILURES)"; exit 1
else
	@echo "rules_test: all assertions passed"
endif
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
./scripts/ppa/tests/run-tests.sh
```

Expected: `functions_test` passes, `rules_test` fails with exit code 1. You should see `FAIL libteam-online: got "" want "libteam5_1.31-1build4+sonic1~ppa1_amd64.deb"`, `FAIL libteam-not-make: got "libteam5_1.31-1build4_amd64.deb" want ""`, `FAIL libteam-stock-ver: got "" want "1.31-1build4"` and others.

- [ ] **Step 3: Edit `rules/libteam.mk`**

Exactly one line changes (the version line); everything else is an insertion. Afterwards the top of the file and the registration point should read:

```make
# libteam packages

LIBTEAM_VERSION := 1.31
LIBTEAM_VERSION_STOCK := $(LIBTEAM_VERSION)-1build4
LIBTEAM_VERSION_FULL := $(LIBTEAM_VERSION_STOCK)$(call ppa_ver,libteam)

LIBTEAM_DSC_URL := http://archive.ubuntu.com/ubuntu/pool/main/libt/libteam/libteam_$(LIBTEAM_VERSION_STOCK).dsc

export LIBTEAM_VERSION
export LIBTEAM_VERSION_FULL
export LIBTEAM_VERSION_STOCK
export LIBTEAM_DSC_URL

LIBTEAM = libteam5_$(LIBTEAM_VERSION_FULL)_$(CONFIGURED_ARCH).deb
$(LIBTEAM)_SRC_PATH = $(SRC_PATH)/libteam
$(LIBTEAM)_DEPENDS += $(LIBNL_GENL3_DEV) $(LIBNL_CLI_DEV)
```

That is: the original `LIBTEAM_VERSION_FULL := $(LIBTEAM_VERSION)-1build4` line becomes the two lines above (`_VERSION_STOCK` plus the suffix-inlined `_VERSION_FULL`), and `LIBTEAM_DSC_URL` plus two new `export` lines are inserted. **Leave the existing `SONIC_MAKE_DEBS += $(LIBTEAM)` line where it is for now** (it sits after `$(LIBTEAM)_DEPENDS`).

Then replace that registration line. From:

```make
SONIC_MAKE_DEBS += $(LIBTEAM)
```

to:

```make
ifneq ($(filter libteam,$(SONIC_PPA_PACKAGES)),)
SONIC_ONLINE_DEBS += $(LIBTEAM)
else
SONIC_MAKE_DEBS += $(LIBTEAM)
endif
```

Finally, insert the URL-override block **after** every `add_derived_package` call in the file (that is, after the `LIBTEAM_UTILS_DBG` group and before `DBG_SRC_ARCHIVE += libteam`). `add_derived_package` makes derived debs inherit the main deb's URL (`rules/functions:94`), so each must be overridden:

```make
# PPA mode: the main deb and each derived deb get their own download address.
# This must come after every add_derived_package call — that macro makes the
# derived debs inherit the main deb's _URL (rules/functions:94).
ifneq ($(filter libteam,$(SONIC_PPA_PACKAGES)),)
$(LIBTEAM)_URL             = $(call ppa_url,libteam,$(LIBTEAM))
$(LIBTEAM_DBG)_URL         = $(call ppa_url,libteam,$(LIBTEAM_DBG))
$(LIBTEAM_DEV)_URL         = $(call ppa_url,libteam,$(LIBTEAM_DEV))
$(LIBTEAMDCTL)_URL         = $(call ppa_url,libteam,$(LIBTEAMDCTL))
$(LIBTEAMDCTL_DBG)_URL     = $(call ppa_url,libteam,$(LIBTEAMDCTL_DBG))
$(LIBTEAM_UTILS)_URL       = $(call ppa_url,libteam,$(LIBTEAM_UTILS))
$(LIBTEAM_UTILS_DBG)_URL   = $(call ppa_url,libteam,$(LIBTEAM_UTILS_DBG))
endif
```

- [ ] **Step 4: Edit `rules/libteam.dep` (two inserted lines, zero modified)**

```diff
 SPATH       := $($(LIBTEAM)_SRC_PATH)
 DEP_FILES   := $(SONIC_COMMON_FILES_LIST) rules/libteam.mk rules/libteam.dep   
 DEP_FILES   += $(SONIC_COMMON_BASE_FILES_LIST)
+ifeq ($(filter libteam,$(SONIC_PPA_PACKAGES)),)
 DEP_FILES   += $(shell git ls-files $(SPATH))
+endif
```

Keying off the package name rather than off whether `$(SPATH)` is empty keeps the guard condition identical to the one in the `.mk`. In PPA mode the cache key degrades to the `.mk` content, which includes the version and suffix, so changing the suffix correctly invalidates the cache.

- [ ] **Step 5: Edit `src/libteam/Makefile:18` to drop the hardcoded URL**

```diff
-	dget -u http://archive.ubuntu.com/ubuntu/pool/main/libt/libteam/libteam_$(LIBTEAM_VERSION_FULL).dsc
+	dget -u $(LIBTEAM_DSC_URL)
```

This collapses the dsc address to one definition. `LIBTEAM_DSC_URL` is built from `_VERSION_STOCK`, so the local build path still fetches the official source package even once `_VERSION_FULL` carries a PPA suffix.

- [ ] **Step 6: Run the tests to verify they pass**

```bash
./scripts/ppa/tests/run-tests.sh
```

Expected: exit code 0, both suites printing `all assertions passed`.

- [ ] **Step 7: Confirm zero regression in local mode**

```bash
make -s -f scripts/ppa/query.mk PKG=libteam
```

Expected (`SONIC_PPA_PACKAGES` is empty in `rules/config`, so local mode and no suffix on the deb name):

```
PKG=libteam
MODE=local
STOCK_VERSION=1.31-1build4
DSC_URL=http://archive.ubuntu.com/ubuntu/pool/main/libt/libteam/libteam_1.31-1build4.dsc
SUFFIX=+sonic1~ppa1
PATCH_DIR=src/libteam/patch
MAIN_DEB=libteam5_1.31-1build4_amd64.deb
DERIVED_DEBS=libteam5-dbgsym_1.31-1build4_amd64.deb libteam-dev_1.31-1build4_amd64.deb libteamdctl0_1.31-1build4_amd64.deb libteamdctl0-dbgsym_1.31-1build4_amd64.deb libteam-utils_1.31-1build4_amd64.deb libteam-utils-dbgsym_1.31-1build4_amd64.deb
SOURCE=libteam
```

The key line is `MAIN_DEB`: identical to before the change (`libteam5_1.31-1build4_amd64.deb`, no suffix). `SOURCE=libteam` is now derivable from the dsc URL.

Then confirm the names really do change in PPA mode:

```bash
make -s -f scripts/ppa/query.mk PKG=libteam SONIC_PPA_PACKAGES=libteam | grep -E '^(MODE|MAIN_DEB)='
```

Expected:

```
MODE=ppa
MAIN_DEB=libteam5_1.31-1build4+sonic1~ppa1_amd64.deb
```

- [ ] **Step 8: Commit**

```bash
git add rules/libteam.mk rules/libteam.dep src/libteam/Makefile scripts/ppa/tests/rules_test.mk
git commit -m "build(ppa): wire libteam for PPA-or-local selection

libteam is the clean baseline for this mechanism: all 14 active patches are
in the series and src/libteam/Makefile does nothing outside dget and
dpkg-buildpackage, so a failure here means the scaffolding is wrong rather
than the package being special.

The PPA suffix is inlined into LIBTEAM_VERSION_FULL so every deb-name
definition and every add_derived_package call stays literally unchanged;
only the registration line becomes a branch. That keeps the diff to pure
insertions, which matters because this tree is rebased onto sonic-net/202605
repeatedly and re-indentation would turn every upstream edit into a conflict.

Each derived deb needs its _URL overridden after the add_derived_package
call, because that macro makes derived debs inherit the main deb's URL
(rules/functions:94).

The dsc URL moves into LIBTEAM_DSC_URL, built from the new
LIBTEAM_VERSION_STOCK rather than from _VERSION_FULL, so the local build
path still fetches the official source package once _VERSION_FULL carries a
PPA suffix.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: `build-source.sh` plus the clean chroot and the libteam source package

**Files:**
- Create: `scripts/ppa/build-source.sh`
- Create: `scripts/ppa/build-clean.sh`
- Create: `scripts/ppa/tests/test-build-source.sh`

**Interfaces:**
- Consumes: `scripts/ppa/query.mk` (Task 1), `LIBTEAM_DSC_URL` / `LIBTEAM_VERSION_STOCK` (Task 2)
- Produces: `target/source/<pkg>/<source>_<stock><suffix>.dsc` plus the matching `_source.changes`, `.debian.tar.xz`, and the orig depending on `-sa` / `-sd`; `scripts/ppa/build-clean.sh <pkg>` places the binary artifacts in `target/source/<pkg>/build/`

- [ ] **Step 1: Write `scripts/ppa/build-clean.sh` (the clean-environment builder)**

`sbuild`/`pbuilder` are not used: they would mean installing four packages on the host, building a persistent `/srv/chroot` tree, running `sbuild-adduser` and logging back in — all requiring sudo. This project's rule is that host modifications are a last resort. Use a throwaway `ubuntu:resolute` container instead: it is the slave image's own `FROM` base (`sonic-slave-resolute/Dockerfile.j2:19`), already pulled by the build; `--rm` starts from the pristine image every time and so is clean by construction; and it does **not** carry the slave's `Dh_Lib.pm` patch, so dbgsym comes out as a real `.ddeb`.

Create (`chmod +x`):

```bash
#!/bin/bash
# Build an already-generated source package inside a throwaway ubuntu:resolute
# container, to model the Launchpad builder. Acceptance criterion 1.
#
# Deliberately not the slave image: the slave preinstalls a lot of build-deps
# and carries the Dh_Lib.pm patch, so it cannot surface the lost-out-of-tree-
# action class of problems, nor the .ddeb behaviour.
# Deliberately not sbuild/pbuilder: those need sudo to install host packages
# and to build a persistent chroot.
#
# Usage: scripts/ppa/build-clean.sh <pkg>
set -euo pipefail

PKG="${1:?usage: $0 <pkg>}"
cd "$(dirname "$0")/../.."
REPO=$PWD
SRCDIR="$REPO/target/source/$PKG"

ls "$SRCDIR"/*.dsc >/dev/null 2>&1 || { echo "$PKG: no .dsc in $SRCDIR; run build-source.sh first" >&2; exit 1; }

rm -rf "$SRCDIR/build"

# apt-get build-dep ./ reads the unpacked debian/control and needs no deb-src
# entries, so the ubuntu:resolute image's default sources are enough.
docker run --rm \
    -v "$SRCDIR:/src" \
    -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
    ubuntu:resolute bash -euc '
        apt-get -qq update
        apt-get -qq install -y --no-install-recommends build-essential devscripts
        mkdir /build && cd /build
        dpkg-source -x /src/*.dsc pkg
        cd pkg
        apt-get -qq build-dep -y --no-install-recommends ./
        dpkg-buildpackage -b -us -uc
        mkdir -p /src/build
        cp -a /build/*.deb /build/*.ddeb /src/build/ 2>/dev/null || true
        chown -R "$HOST_UID:$HOST_GID" /src/build
    '

echo "== $PKG built in a clean ubuntu:resolute container:"
ls -1 "$SRCDIR/build"
```

First confirm the base image is present locally (the slave build already pulled it):

```bash
chmod +x scripts/ppa/build-clean.sh
docker images --format '{{.Repository}}:{{.Tag}}' | grep -x 'ubuntu:resolute'
./scripts/ppa/build-clean.sh libteam
```

Expected: `grep -x` prints `ubuntu:resolute`; `build-clean.sh` then reports `libteam: no .dsc in .../target/source/libteam; run build-source.sh first` and exits 1 — the source package does not exist yet, which is what the next steps produce.

- [ ] **Step 2: Write the failing test**

Create `scripts/ppa/tests/test-build-source.sh` (`chmod +x`):

```bash
#!/bin/bash
# Verify the source package build-source.sh produced for one package:
#   - a .dsc and a _source.changes exist
#   - the upload manifest lists no .deb (PPAs accept source uploads only)
#   - the SONiC patches are appended to debian/patches/series in the same
#     order as src/<pkg>/patch/series
#   - the patches ship UNAPPLIED (the Launchpad builder applies them)
set -euo pipefail

PKG="${1:?usage: test-build-source.sh <pkg>}"
cd "$(dirname "$0")/../../.."

# read, not eval: DERIVED_DEBS holds several space-separated names and eval
# would split them into words and try to execute them
while IFS='=' read -r k v; do declare "Q_$k=$v"; done \
    < <(make -s -f scripts/ppa/query.mk PKG="$PKG")
OUT="target/source/$PKG"

dsc=$(ls "$OUT"/*.dsc 2>/dev/null | head -1)
[ -n "$dsc" ] || { echo "FAIL: no .dsc in $OUT"; exit 1; }
echo "ok   dsc present: $dsc"

changes=$(ls "$OUT"/*_source.changes 2>/dev/null | head -1)
[ -n "$changes" ] || { echo "FAIL: no _source.changes in $OUT"; exit 1; }
echo "ok   changes present: $changes"

if grep -qE '^\s.*\.deb$' "$changes"; then
    echo "FAIL: $changes lists a .deb; PPAs reject binary uploads"; exit 1
fi
echo "ok   changes contains no .deb"

# The version must be stock plus suffix
want_ver="${Q_STOCK_VERSION}${Q_SUFFIX}"
if ! grep -q "^Version: ${want_ver}\$" "$dsc"; then
    echo "FAIL: $dsc Version is not '$want_ver'"; grep '^Version:' "$dsc"; exit 1
fi
echo "ok   version is $want_ver"

# Unpack, then check the tail of the series and that patches are unapplied
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
dpkg-source --no-check -x "$dsc" "$tmp/src" >/dev/null
grep -vE '^\s*(#|$)' "$Q_PATCH_DIR/series" > "$tmp/want"
tail -n "$(wc -l < "$tmp/want")" "$tmp/src/debian/patches/series" > "$tmp/got"
if ! diff -u "$tmp/want" "$tmp/got"; then
    echo "FAIL: SONiC patches are not appended verbatim at the end of debian/patches/series"; exit 1
fi
echo "ok   $(wc -l < "$tmp/want") SONiC patches appended in order"

if [ -d "$tmp/src/.pc" ]; then
    echo "FAIL: $tmp/src/.pc exists; patches must ship UNAPPLIED"; exit 1
fi
echo "ok   patches ship unapplied"

echo "test-build-source($PKG): all assertions passed"
```

- [ ] **Step 3: Run the test to verify it fails**

```bash
./scripts/ppa/tests/test-build-source.sh libteam
```

Expected: exit code 1 with `FAIL: no .dsc in target/source/libteam` — neither the script nor the artifacts exist yet.

- [ ] **Step 4: Write `scripts/ppa/build-source.sh`**

Create (`chmod +x`):

```bash
#!/bin/bash
# Produce unsigned Debian source packages for one or more packages, ready to
# upload to a Launchpad PPA.
#
# Runs inside the slave-resolute container (needs dget / dch / dpkg-source;
# the container already ships devscripts). Deliberately does not sign or
# upload: GPG and dput are handled by scripts/ppa/sign-upload.sh on the host.
#
# Usage: scripts/ppa/build-source.sh <pkg>...
#   e.g. scripts/ppa/build-source.sh libteam isc-dhcp lm-sensors
set -euo pipefail

[ $# -ge 1 ] || { echo "usage: $0 <pkg>..." >&2; exit 2; }
cd "$(dirname "$0")/../.."
REPO=$PWD

for PKG in "$@"; do
    echo "=== $PKG"
    # read, not eval: DERIVED_DEBS holds several space-separated names and eval
# would split them into words and try to execute them
while IFS='=' read -r k v; do declare "Q_$k=$v"; done \
    < <(make -s -f scripts/ppa/query.mk PKG="$PKG")

    [ -n "${Q_DSC_URL:-}" ] || { echo "$PKG: <PREFIX>_DSC_URL is not set in rules/$PKG.mk" >&2; exit 1; }
    [ -n "${Q_STOCK_VERSION:-}" ] || { echo "$PKG: <PREFIX>_VERSION_STOCK is not set in rules/$PKG.mk" >&2; exit 1; }

    # A binary file inside a patch needs debian/source/include-binaries. None
    # in this batch, but fail loudly rather than emit a package dpkg-source
    # will later refuse.
    if grep -rlq $'^GIT binary patch' "$REPO/$Q_PATCH_DIR"/*.patch 2>/dev/null; then
        echo "$PKG: patch series contains a binary patch; needs debian/source/include-binaries" >&2
        exit 1
    fi

    WORK=$(mktemp -d)
    OUT="$REPO/target/source/$PKG"
    mkdir -p "$OUT"

    pushd "$WORK" >/dev/null
    # -u is structurally required: on an Ubuntu slave the .dsc uploader's
    # personal key is in no available keyring, and debian-keyring does not help.
    dget -u "$Q_DSC_URL"

    SRCDIR=$(find . -maxdepth 1 -type d -name "$Q_SOURCE-*" | head -1)
    [ -n "$SRCDIR" ] || { echo "$PKG: cannot find extracted source dir for $Q_SOURCE" >&2; exit 1; }
    pushd "$SRCDIR" >/dev/null

    # dget extracted via dpkg-source -x, which already applied the upstream
    # debian/patches, so the working tree is fully patched. Appending the SONiC
    # patches to the series in the same order is equivalent — but the patches
    # themselves must ship unapplied; the builder applies them at build time.
    mkdir -p debian/patches
    [ -f debian/patches/series ] || : > debian/patches/series
    while read -r p; do
        cp "$REPO/$Q_PATCH_DIR/$p" debian/patches/
        echo "$p" >> debian/patches/series
    done < <(grep -vE '^\s*(#|$)' "$REPO/$Q_PATCH_DIR/series")

    # The .pc left behind by dget's extraction would make dpkg-source think
    # the patches are applied.
    rm -rf .pc

    dch --newversion "${Q_STOCK_VERSION}${Q_SUFFIX}" \
        --distribution resolute --force-distribution \
        "SONiC packaging for Ubuntu resolute: apply the $PKG patch series from sonic-buildimage."

    # The first upload of a given upstream version carries the orig (-sa);
    # later ones must use -sd or Launchpad rejects them over an orig checksum
    # conflict. Decide from whether the orig is already in the PPA pool; when
    # that cannot be determined, be conservative and say so.
    SA_FLAG=-sd
    if [ -n "${SONIC_PPA_URL:-}" ]; then
        origin_orig="$SONIC_PPA_URL/pool/main/$(echo "$Q_SOURCE" | \
            sed -E 's/^(lib.).*/\1/; t; s/^(.).*/\1/')/$Q_SOURCE/"
        if ! curl -sfL "$origin_orig" | grep -q "${Q_SOURCE}_.*\.orig\."; then
            SA_FLAG=-sa
        fi
    else
        echo "  note: SONIC_PPA_URL unset, cannot tell if the orig is already uploaded; using -sa for the first local run" >&2
        SA_FLAG=-sa
    fi

    dpkg-buildpackage -S "$SA_FLAG" -us -uc -d
    popd >/dev/null

    rm -f "$OUT"/*
    mv ./*.dsc ./*_source.changes ./*.tar.* ./*.buildinfo "$OUT"/ 2>/dev/null || true
    popd >/dev/null
    rm -rf "$WORK"

    echo "  -> $OUT"
    ls -1 "$OUT"
done
```

- [ ] **Step 5: Produce the libteam source package, then run the test to verify it passes**

Run inside the container (the host has neither `dget` nor a resolute devscripts):

```bash
make sonic-slave-run SONIC_RUN_CMDS="scripts/ppa/build-source.sh libteam"
./scripts/ppa/tests/test-build-source.sh libteam
```

Expected: `build-source.sh` prints `-> /sonic/target/source/libteam` and the file list; the test exits 0 with

```
ok   dsc present: target/source/libteam/libteam_1.31-1build4+sonic1~ppa1.dsc
ok   changes present: target/source/libteam/libteam_1.31-1build4+sonic1~ppa1_source.changes
ok   changes contains no .deb
ok   version is 1.31-1build4+sonic1~ppa1
ok   14 SONiC patches appended in order
ok   patches ship unapplied
test-build-source(libteam): all assertions passed
```

- [ ] **Step 6: Build in the clean container — acceptance criterion 1**

```bash
./scripts/ppa/build-clean.sh libteam
```

Expected: the build succeeds and `target/source/libteam/build/` holds 7 artifacts — `libteam5`, `libteam-dev`, `libteamdctl0`, `libteam-utils` as `.deb`, plus `libteam5-dbgsym`, `libteamdctl0-dbgsym`, `libteam-utils-dbgsym` as **`.ddeb`** (confirming design §3.6: a clean container has no `Dh_Lib.pm` patch from the slave image, so the extension stays Ubuntu-native `.ddeb`).

If it fails on patch fuzz (`stg import` tolerates fuzz, `dpkg-source` applies patches with zero fuzz), refresh each offending patch with `quilt push -a` plus `quilt refresh`, update the corresponding file in `src/libteam/patch/`, and commit the refresh separately.

- [ ] **Step 7: Commit**

```bash
git add scripts/ppa/build-source.sh scripts/ppa/build-clean.sh scripts/ppa/tests/test-build-source.sh
git commit -m "build(ppa): generate unsigned source packages from the in-tree patch series

build-source.sh turns a package's stock .dsc plus src/<pkg>/patch/series into
an uploadable source package. It reads every fact from scripts/ppa/query.mk,
so rules/<pkg>.mk stays the only place the version and dsc URL are written.

The patches are copied into debian/patches and appended to series but left
UNAPPLIED, and .pc is removed: dget extracts via dpkg-source -x, which has
already applied the upstream patches, so appending in the same order is
equivalent and the Launchpad builder applies ours at build time.

Signing and uploading are deliberately absent — mounting the GPG agent
socket into a DinD container is expensive and fragile, so those live in
sign-upload.sh on the host.

-sa is chosen only when the orig is not already in the PPA pool; reusing an
orig with a different checksum is an upload rejection.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: isc-dhcp (internalise the LTO strip)

`isc-dhcp` represents the guaranteed-build-failure class: `src/isc-dhcp/Makefile:28-29` exports `DEB_CFLAGS_MAINT_STRIP` / `DEB_LDFLAGS_MAINT_STRIP` outside `dpkg-buildpackage` to disable LTO. Those two lines are not in the source package, a Launchpad builder never sees them, and the generated source package **will** fail to build. They must move into `debian/rules`.

**Files:**
- Create: `src/isc-dhcp/patch/0019-resolute-disable-lto-for-vendored-bind.patch`
- Modify: `src/isc-dhcp/patch/series`
- Modify: `rules/isc-dhcp.mk`
- Modify: `rules/isc-dhcp.dep`
- Modify: `src/isc-dhcp/Makefile` (line 13 uses `_DSC_URL`; the out-of-tree exports on lines 25-29 are removed)
- Modify: `scripts/ppa/tests/rules_test.mk` (add isc-dhcp assertions)

**Interfaces:**
- Consumes: the functions from Task 1, the `.mk` edit shape from Task 2
- Produces: `ISC_DHCP_VERSION_STOCK` = `4.4.3-P1-2`, `ISC_DHCP_DSC_URL`

- [ ] **Step 1: Write the failing assertions**

In `scripts/ppa/tests/rules_test.mk`, change `SONIC_PPA_PACKAGES` to `libteam isc-dhcp`, add `include rules/isc-dhcp.mk` after `include rules/libteam.mk`, and append:

```make
$(call assert,iscdhcp-online,$(filter isc-dhcp-relay%,$(SONIC_ONLINE_DEBS)),isc-dhcp-relay_4.4.3-P1-2+sonic1~ppa1_amd64.deb)
$(call assert,iscdhcp-stock-ver,$(ISC_DHCP_VERSION_STOCK),4.4.3-P1-2)
$(call assert,iscdhcp-dsc-url,$(ISC_DHCP_DSC_URL),http://deb.debian.org/debian/pool/main/i/isc-dhcp/isc-dhcp_4.4.3-P1-2.dsc)
$(call assert,iscdhcp-dbg-url,$($(ISC_DHCP_RELAY_DBG)_URL),https://ppa.launchpadcontent.net/o/n/ubuntu/pool/main/i/isc-dhcp/isc-dhcp-relay-dbgsym_4.4.3-P1-2+sonic1~ppa1_amd64.ddeb)
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
./scripts/ppa/tests/run-tests.sh
```

Expected: `rules_test` exits 1 with those four failures, including `FAIL iscdhcp-stock-ver: got "" want "4.4.3-P1-2"`.

- [ ] **Step 3: Create the patch that internalises the LTO strip**

The patch content to land in `debian/rules`, immediately after `#!/usr/bin/make -f` and before any `include`:

```make
# resolute: the vendored bind 9.11.36 does not link with -flto=auto. libisc.a
# carries the symbols as T, but svtest and dhclient still report undefined
# references. Strip LTO from both CFLAGS and LDFLAGS.
#
# This used to live in src/isc-dhcp/Makefile as two exports around
# dpkg-buildpackage. That works for a local build but is invisible to a
# Launchpad builder, which only ever sees the source package.
export DEB_CFLAGS_MAINT_STRIP = -flto=auto -ffat-lto-objects
export DEB_LDFLAGS_MAINT_STRIP = -flto=auto -ffat-lto-objects
```

Generate the patch against the **real** extracted `debian/rules`, not by hand:

```bash
make sonic-slave-run SONIC_RUN_CMDS="bash -c 'cd /tmp && dget -u http://deb.debian.org/debian/pool/main/i/isc-dhcp/isc-dhcp_4.4.3-P1-2.dsc && head -20 isc-dhcp-4.4.3-P1/debian/rules'"
```

Use the actual first 20 lines to decide the insertion point, then produce a well-formed patch with `quilt new 0019-resolute-disable-lto-for-vendored-bind.patch`, `quilt add debian/rules`, edit, `quilt refresh`, and copy the generated file into `src/isc-dhcp/patch/`.

- [ ] **Step 4: Add the patch to the series**

Append one line to the end of `src/isc-dhcp/patch/series`:

```
0019-resolute-disable-lto-for-vendored-bind.patch
```

- [ ] **Step 5: Remove the out-of-tree exports from `src/isc-dhcp/Makefile` and switch to `_DSC_URL`**

```diff
-	dget -u http://deb.debian.org/debian/pool/main/i/isc-dhcp/isc-dhcp_$(ISC_DHCP_VERSION_FULL).dsc
+	dget -u $(ISC_DHCP_DSC_URL)
```

```diff
-	# resolute: bind 9.11.36 (vendored in isc-dhcp) link error with -flto=auto:
-	# libisc.a has the symbols (T) but svtest/dhclient link reports undefined
-	# reference. Disable LTO for this package (CFLAGS + LDFLAGS).
-	export DEB_CFLAGS_MAINT_STRIP="-flto=auto -ffat-lto-objects"
-	export DEB_LDFLAGS_MAINT_STRIP="-flto=auto -ffat-lto-objects"
-
```

Removing them is safe: the same strip now reaches `debian/rules` via patch `0019` in the series, so both the local build and the PPA build get it. This also eliminates having the LTO handling written in two places.

- [ ] **Step 6: Edit `rules/isc-dhcp.mk`**

```make
# isc-dhcp packages

ISC_DHCP_VERSION = 4.4.3-P1
ISC_DHCP_VERSION_STOCK = ${ISC_DHCP_VERSION}-2
ISC_DHCP_VERSION_FULL = $(ISC_DHCP_VERSION_STOCK)$(call ppa_ver,isc-dhcp)

ISC_DHCP_DSC_URL = http://deb.debian.org/debian/pool/main/i/isc-dhcp/isc-dhcp_$(ISC_DHCP_VERSION_STOCK).dsc

export ISC_DHCP_VERSION ISC_DHCP_VERSION_FULL ISC_DHCP_VERSION_STOCK ISC_DHCP_DSC_URL
```

That is: the original `ISC_DHCP_VERSION_FULL = ${ISC_DHCP_VERSION}-2` line becomes two lines, `_DSC_URL` is inserted, and the two new variables are added to the existing `export` line.

At the registration point:

```diff
-SONIC_MAKE_DEBS += $(ISC_DHCP_RELAY)
+ifneq ($(filter isc-dhcp,$(SONIC_PPA_PACKAGES)),)
+SONIC_ONLINE_DEBS += $(ISC_DHCP_RELAY)
+else
+SONIC_MAKE_DEBS += $(ISC_DHCP_RELAY)
+endif
```

After the `add_derived_package` call (before `export ISC_DHCP_RELAY ISC_DHCP_RELAY_DBG`), insert:

```make
# PPA mode: the main deb and the dbgsym each get their own address. Must come
# after add_derived_package.
ifneq ($(filter isc-dhcp,$(SONIC_PPA_PACKAGES)),)
$(ISC_DHCP_RELAY)_URL     = $(call ppa_url,isc-dhcp,$(ISC_DHCP_RELAY))
$(ISC_DHCP_RELAY_DBG)_URL = $(call ppa_url,isc-dhcp,$(ISC_DHCP_RELAY_DBG))
endif
```

- [ ] **Step 7: Edit `rules/isc-dhcp.dep` (two inserted lines)**

```diff
 DEP_FILES   += $(SONIC_COMMON_BASE_FILES_LIST)
+ifeq ($(filter isc-dhcp,$(SONIC_PPA_PACKAGES)),)
 DEP_FILES   += $(shell git ls-files $(SPATH))
+endif
```

- [ ] **Step 8: Run the make-layer tests to verify they pass**

```bash
./scripts/ppa/tests/run-tests.sh
```

Expected: exit code 0, both suites printing `all assertions passed`.

- [ ] **Step 9: Produce the source package and build it in the clean chroot**

```bash
make sonic-slave-run SONIC_RUN_CMDS="scripts/ppa/build-source.sh isc-dhcp"
./scripts/ppa/tests/test-build-source.sh isc-dhcp
./scripts/ppa/build-clean.sh isc-dhcp
```

Expected: the test script reports `ok   18 SONiC patches appended in order` (17 existing plus the new `0019`); `build-clean.sh` succeeds and `target/source/isc-dhcp/build/` holds `isc-dhcp-relay_*.deb` and `isc-dhcp-relay-dbgsym_*.ddeb`. **This is the core acceptance point of this task** — without `0019` taking effect, the build fails with undefined references while linking `svtest` / `dhclient`.

- [ ] **Step 10: Confirm the local build path did not regress**

```bash
make sonic-slave-run SONIC_RUN_CMDS="rm -f target/debs/resolute/isc-dhcp-relay_* && make target/debs/resolute/isc-dhcp-relay_4.4.3-P1-2_amd64.deb"
```

Expected: the build succeeds. This confirms that moving the LTO strip out of the Makefile and into `debian/rules` also delivers the fix to the local build path.

- [ ] **Step 11: Commit**

```bash
git add src/isc-dhcp/patch/ src/isc-dhcp/Makefile rules/isc-dhcp.mk rules/isc-dhcp.dep scripts/ppa/tests/rules_test.mk
git commit -m "build(isc-dhcp): move the LTO strip into debian/rules, wire for PPA

The two DEB_*_MAINT_STRIP exports lived in src/isc-dhcp/Makefile around
dpkg-buildpackage. A Launchpad builder only sees the source package, so a
generated .dsc would fail to link the vendored bind 9.11.36 exactly the way
it did before the workaround existed. Patch 0019 puts the same strip into
debian/rules, which makes it apply to the local build too and removes the
duplicate handling.

isc-dhcp is in the first batch precisely because it is the guaranteed-failure
case: 17 existing patches (highest fuzz risk) and a Debian source uploaded to
an Ubuntu PPA.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: lm-sensors (internalise `PROG_EXTRA=sensord`)

`lm-sensors` is the only representative of the builds-fine-but-the-artifact-is-wrong class. `PROG_EXTRA=sensord` on `src/lm-sensors/Makefile:31` is an upstream lm-sensors build variable that decides whether the `sensord` program is **compiled at all**. Losing it raises no error — the `sensord` binary package still exists in `debian/control` (added by the existing patch `0001`), it just has no executable in it or the build fails late — and `docker-platform-monitor` needs it.

**Files:**
- Create: `src/lm-sensors/patch/0003-build-sensord-via-prog-extra.patch`
- Modify: `src/lm-sensors/patch/series`
- Modify: `rules/lm-sensors.mk`
- Modify: `rules/lm-sensors.dep`
- Modify: `src/lm-sensors/Makefile` (line 16 uses `_DSC_URL`; `PROG_EXTRA=` is dropped from lines 29 and 31)
- Modify: `scripts/ppa/tests/rules_test.mk` (add lm-sensors assertions)

**Interfaces:**
- Consumes: the functions from Task 1, the edit shape from Task 2
- Produces: `LM_SENSORS_VERSION_STOCK` = `3.6.2-2build1`, `LM_SENSORS_DSC_URL`

- [ ] **Step 1: Write the failing assertions**

In `scripts/ppa/tests/rules_test.mk`, change `SONIC_PPA_PACKAGES` to `libteam isc-dhcp lm-sensors`, add `include rules/lm-sensors.mk`, and append:

```make
$(call assert,lmsensors-stock-ver,$(LM_SENSORS_VERSION_STOCK),3.6.2-2build1)
$(call assert,lmsensors-main-name,$(LM_SENSORS),lm-sensors_3.6.2-2build1+sonic1~ppa1_amd64.deb)
$(call assert,lmsensors-dsc-url,$(LM_SENSORS_DSC_URL),http://archive.ubuntu.com/ubuntu/pool/main/l/lm-sensors/lm-sensors_3.6.2-2build1.dsc)
$(call assert,lmsensors-sensord-url,$($(SENSORD)_URL),https://ppa.launchpadcontent.net/o/n/ubuntu/pool/main/l/lm-sensors/sensord_3.6.2-2build1+sonic1~ppa1_amd64.deb)
$(call assert,lmsensors-fancontrol-url,$($(FANCONTROL)_URL),https://ppa.launchpadcontent.net/o/n/ubuntu/pool/main/l/lm-sensors/fancontrol_3.6.2-2build1+sonic1~ppa1_all.deb)
```

The `fancontrol` assertion also covers the `Arch: all` filename path (`_all.deb` rather than `_amd64.deb`).

- [ ] **Step 2: Run the tests to verify they fail**

```bash
./scripts/ppa/tests/run-tests.sh
```

Expected: `rules_test` exits 1 with those five failures, including `FAIL lmsensors-stock-ver: got "" want "3.6.2-2build1"`.

- [ ] **Step 3: Create the patch that internalises `PROG_EXTRA`**

First look at what the stock `debian/rules` contains:

```bash
make sonic-slave-run SONIC_RUN_CMDS="bash -c 'cd /tmp && dget -u http://archive.ubuntu.com/ubuntu/pool/main/l/lm-sensors/lm-sensors_3.6.2-2build1.dsc && grep -nE \"PROG_EXTRA|^export|dh_auto_build|^%:\" lm-sensors-3.6.2/debian/rules'"
```

If the stock `debian/rules` already has an `export` block, insert after it; otherwise insert right after `#!/usr/bin/make -f`. Produce the patch with `quilt new 0003-build-sensord-via-prog-extra.patch`, `quilt add debian/rules`, edit, `quilt refresh`. The content to add:

```make
# SONiC: lm-sensors' upstream build only compiles sensord when PROG_EXTRA
# names it. The sensord binary package is added by patch 0001, but without
# this the program itself is never built. This used to be an environment
# variable in src/lm-sensors/Makefile, which a Launchpad builder cannot see.
export PROG_EXTRA = sensord
```

Copy the generated patch into `src/lm-sensors/patch/` and append to `src/lm-sensors/patch/series`:

```
0003-build-sensord-via-prog-extra.patch
```

- [ ] **Step 4: Edit `src/lm-sensors/Makefile`**

```diff
-	dget -u http://archive.ubuntu.com/ubuntu/pool/main/l/lm-sensors/lm-sensors_$(LM_SENSORS_VERSION_FULL).dsc
+	dget -u $(LM_SENSORS_DSC_URL)
```

```diff
-	DEB_BUILD_OPTIONS=nocheck DEB_BUILD_PROFILES=nocheck PROG_EXTRA=sensord dpkg-buildpackage -us -uc -b -j$(SONIC_CONFIG_MAKE_JOBS) --admindir $(SONIC_DPKG_ADMINDIR)
+	DEB_BUILD_OPTIONS=nocheck DEB_BUILD_PROFILES=nocheck dpkg-buildpackage -us -uc -b -j$(SONIC_CONFIG_MAKE_JOBS) --admindir $(SONIC_DPKG_ADMINDIR)
```

`PROG_EXTRA=` leaves the command line because patch `0003` now puts it in `debian/rules`. `DEB_BUILD_OPTIONS=nocheck` **stays as is** — it only affects the local build. The Launchpad builder will really run the tests, which is a deliberate acceptance: if they fail there, we decide then whether to patch in `nocheck` or fix the tests. This task does not pre-judge that.

Make the same change to the `PROG_EXTRA=sensord` in the `CROSS_BUILD_ENVIRON` branch above (line 29).

- [ ] **Step 5: Edit `rules/lm-sensors.mk`**

```make
LM_SENSORS_VERSION=$(LM_SENSORS_MAJOR_VERSION).$(LM_SENSORS_MINOR_VERSION).$(LM_SENSORS_PATCH_VERSION)
LM_SENSORS_VERSION_STOCK=$(LM_SENSORS_VERSION)-2build1
LM_SENSORS_VERSION_FULL=$(LM_SENSORS_VERSION_STOCK)$(call ppa_ver,lm-sensors)

LM_SENSORS_DSC_URL=http://archive.ubuntu.com/ubuntu/pool/main/l/lm-sensors/lm-sensors_$(LM_SENSORS_VERSION_STOCK).dsc
```

At the registration point:

```diff
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
```

Here the URL overrides can share the registration block, because `SONIC_MAKE_DEBS += $(LM_SENSORS)` in `rules/lm-sensors.mk` already sits after every `add_derived_package` call.

Add `LM_SENSORS_VERSION_STOCK` and `LM_SENSORS_DSC_URL` to the `export` list at the end of the file.

- [ ] **Step 6: Edit `rules/lm-sensors.dep` (two inserted lines)**

```diff
 DEP_FILES   += $(SONIC_COMMON_BASE_FILES_LIST)
+ifeq ($(filter lm-sensors,$(SONIC_PPA_PACKAGES)),)
 DEP_FILES   += $(shell git ls-files $(SPATH))
+endif
```

- [ ] **Step 7: Run the make-layer tests to verify they pass**

```bash
./scripts/ppa/tests/run-tests.sh
```

Expected: exit code 0.

- [ ] **Step 8: Produce the source package, build in the clean chroot, and verify `sensord` is really there**

```bash
make sonic-slave-run SONIC_RUN_CMDS="scripts/ppa/build-source.sh lm-sensors"
./scripts/ppa/tests/test-build-source.sh lm-sensors
./scripts/ppa/build-clean.sh lm-sensors
B=target/source/lm-sensors/build
ls -1 "$B"/sensord_3.6.2-2build1+sonic1~ppa1_amd64.deb
dpkg -c "$B"/sensord_3.6.2-2build1+sonic1~ppa1_amd64.deb | grep -E 'usr/sbin/sensord$'
```

Expected: the test script reports `ok   3 SONiC patches appended in order`; `build-clean.sh` produces 7 artifacts under `target/source/lm-sensors/build/`; `sensord_*.deb` exists; `dpkg -c` output contains `usr/sbin/sensord`. **This is the core acceptance point of this task** — without `0003` taking effect the `sensord` executable is absent while the build may still "succeed".

- [ ] **Step 9: Compare against the local build artifact — acceptance criterion 2**

```bash
make sonic-slave-run SONIC_RUN_CMDS="rm -f target/debs/resolute/sensord_* && make target/debs/resolute/lm-sensors_3.6.2-2build1_amd64.deb"
B=target/source/lm-sensors/build
dpkg -c target/debs/resolute/sensord_3.6.2-2build1_amd64.deb | awk '{print $NF}' | sort > /tmp/local.list
dpkg -c "$B"/sensord_3.6.2-2build1+sonic1~ppa1_amd64.deb     | awk '{print $NF}' | sort > /tmp/clean.list
diff -u /tmp/local.list /tmp/clean.list && echo "file lists identical"
```

Expected: `diff` produces no output and `file lists identical` is printed. This also confirms the local path did not regress after moving `PROG_EXTRA` from the Makefile into `debian/rules`.

- [ ] **Step 10: Commit**

```bash
git add src/lm-sensors/patch/ src/lm-sensors/Makefile rules/lm-sensors.mk rules/lm-sensors.dep scripts/ppa/tests/rules_test.mk
git commit -m "build(lm-sensors): move PROG_EXTRA=sensord into debian/rules, wire for PPA

PROG_EXTRA=sensord was an environment variable on the dpkg-buildpackage
command line, so a Launchpad builder never sees it. Patch 0001 already adds
the sensord binary package to debian/control, which makes this the one
silent-failure shape in the whole migration: the build succeeds and the deb
list looks right, but /usr/sbin/sensord is absent — and
docker-platform-monitor needs it. Patch 0003 sets it in debian/rules
instead, so both the local build and the PPA build get it.

DEB_BUILD_OPTIONS=nocheck is left on the local command line on purpose. It
only affects local builds; the builder will run the test suite, and if that
fails we will decide then whether to patch in nocheck or fix the tests.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: `manifest.sh` and `sign-upload.sh`

**Files:**
- Create: `scripts/ppa/manifest.sh`
- Create: `scripts/ppa/sign-upload.sh`
- Modify: `slave.mk` (add the `ppa-manifest` phony target)

**Interfaces:**
- Consumes: `scripts/ppa/query.mk`, `target/source/<pkg>/*_source.changes`
- Produces: the `make ppa-manifest` status table; `scripts/ppa/sign-upload.sh --dry-run`, which is verifiable before PPA ownership is settled

- [ ] **Step 1: Write the failing test**

```bash
./scripts/ppa/manifest.sh
```

Expected: `bash: ./scripts/ppa/manifest.sh: No such file or directory`, exit code 127.

- [ ] **Step 2: Write `scripts/ppa/manifest.sh`**

Create (`chmod +x`):

```bash
#!/bin/bash
# Print the status table for every PPA candidate package. This is what replaces
# "keep a YAML so you can see everything at once": the table is derived 100%
# from rules/*.mk, so it is an artifact rather than a source of truth and
# cannot drift.
#
# Usage: scripts/ppa/manifest.sh [<pkg>...]
#   With no arguments, lists every package that declares a _DSC_URL.
set -euo pipefail
cd "$(dirname "$0")/../.."

pkgs=("$@")
if [ ${#pkgs[@]} -eq 0 ]; then
    mapfile -t pkgs < <(grep -l '_DSC_URL' rules/*.mk | sed 's|rules/||; s|\.mk$||' | sort)
fi

printf '%-14s %-6s %-24s %-14s %s\n' PACKAGE MODE STOCK-VERSION SUFFIX DEBS
for p in "${pkgs[@]}"; do
    while IFS='=' read -r k v; do declare "Q_$k=$v"; done \
        < <(make -s -f scripts/ppa/query.mk PKG="$p")
    ndebs=$(( 1 + $(echo "$Q_DERIVED_DEBS" | wc -w) ))
    printf '%-14s %-6s %-24s %-14s %s\n' \
        "$Q_PKG" "$Q_MODE" "$Q_STOCK_VERSION" "$Q_SUFFIX" "$ndebs"
    if [ "${VERBOSE:-}" = "1" ]; then
        for d in $Q_MAIN_DEB $Q_DERIVED_DEBS; do
            printf '    %s\n' "$d"
        done
    fi
done
```

- [ ] **Step 3: Add the `slave.mk` target**

Insert at the top level of `slave.mk` (anywhere among the phony targets is fine):

```make
# Print the PPA candidate status table. All data comes from rules/*.mk via
# scripts/ppa/query.mk.
.PHONY: ppa-manifest
ppa-manifest:
	$(Q)scripts/ppa/manifest.sh
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
chmod +x scripts/ppa/manifest.sh
./scripts/ppa/manifest.sh
```

Expected (everything local while `SONIC_PPA_PACKAGES` is empty):

```
PACKAGE        MODE   STOCK-VERSION            SUFFIX         DEBS
isc-dhcp       local  4.4.3-P1-2               +sonic1~ppa1   2
libteam        local  1.31-1build4             +sonic1~ppa1   7
lm-sensors     local  3.6.2-2build1            +sonic1~ppa1   7
```

Then confirm the per-package switch works:

```bash
SONIC_PPA_PACKAGES=libteam ./scripts/ppa/manifest.sh
```

Expected: the `libteam` row's `MODE` becomes `ppa` while the other two stay `local`.

- [ ] **Step 5: Write `scripts/ppa/sign-upload.sh`**

Create (`chmod +x`):

```bash
#!/bin/bash
# Sign (and optionally upload) the source packages produced by
# build-source.sh, on the host.
#
# Deliberately not run in the container: mounting the GPG agent socket into a
# DinD container is expensive and fragile. Requires devscripts (debsign) and
# dput on the host.
#
# Usage:
#   scripts/ppa/sign-upload.sh --key <KEYID> [<pkg>...]            sign only
#   scripts/ppa/sign-upload.sh --key <KEYID> --upload ppa:o/n ...  sign and upload
#   scripts/ppa/sign-upload.sh --dry-run [<pkg>...]                just say what it would do
set -euo pipefail
cd "$(dirname "$0")/../.."

KEY=""; PPA=""; DRY=0
while [ $# -gt 0 ]; do
    case "$1" in
        --key)     KEY="$2"; shift 2 ;;
        --upload)  PPA="$2"; shift 2 ;;
        --dry-run) DRY=1; shift ;;
        *)         break ;;
    esac
done

pkgs=("$@")
if [ ${#pkgs[@]} -eq 0 ]; then
    mapfile -t pkgs < <(find target/source -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
fi
[ ${#pkgs[@]} -gt 0 ] || { echo "nothing in target/source/; run build-source.sh first" >&2; exit 1; }

for p in "${pkgs[@]}"; do
    changes=$(ls "target/source/$p"/*_source.changes 2>/dev/null | head -1) || true
    [ -n "$changes" ] || { echo "$p: no _source.changes; run build-source.sh first" >&2; exit 1; }

    if [ "$DRY" = 1 ]; then
        echo "would debsign${KEY:+ -k $KEY} $changes"
        [ -n "$PPA" ] && echo "would dput $PPA $changes"
        continue
    fi

    [ -n "$KEY" ] || { echo "--key is required unless --dry-run" >&2; exit 2; }
    debsign -k "$KEY" "$changes"
    echo "signed $changes"

    if [ -n "$PPA" ]; then
        dput "$PPA" "$changes"
        echo "uploaded $changes -> $PPA"
    fi
done
```

- [ ] **Step 6: Verify the dry run (needs no PPA ownership)**

```bash
chmod +x scripts/ppa/sign-upload.sh
./scripts/ppa/sign-upload.sh --dry-run
```

Expected: one `would debsign target/source/<pkg>/<src>_<ver>_source.changes` line per package under `target/source/`, exit code 0. Passing `--upload ppa:o/n` adds a `would dput` line per package.

- [ ] **Step 7: Commit**

```bash
git add scripts/ppa/manifest.sh scripts/ppa/sign-upload.sh slave.mk
git commit -m "build(ppa): add the status table and the host-side sign/upload step

make ppa-manifest prints one row per candidate package (mode, stock version,
effective suffix, deb count), derived entirely from rules/*.mk via query.mk.
This is what replaces 'keep a YAML so you can see everything at once': the
table is an artifact rather than a source of truth, so it cannot drift.

sign-upload.sh runs on the host because mounting the GPG agent socket into a
DinD container is expensive and fragile. --dry-run makes the whole path
verifiable before the PPA ownership question is settled.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Explicitly out of scope for this plan

The following depend on the PPA ownership decision (design §10):

- The actual upload, and end-to-end verification of acceptance criteria 2–4 (`dpkg -c` diff against PPA artifacts, binary package set comparison, full image build).
- Confirming whether the PPA's debug-symbol publishing switch can be enabled. If it cannot, follow the existing pattern in `rules/lldpd.mk`: keep the variable defined but drop dbgsym from `SONIC_ONLINE_DEBS`.
- The `socat` readline licensing call (design §8).
- The second batch, starting with `libyang3` (the package with the most out-of-tree actions).
