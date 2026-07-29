# Include rules/<pkg>.mk in a minimal stub context, and print the
# PPA-related facts as key=value pairs.
# scripts/ppa/*.sh and scripts/ppa/tests/* share this file, so these
# facts have a single source -- rules/*.mk -- and don't need a parallel
# manifest.
#
# Usage: make -s -f scripts/ppa/query.mk PKG=libteam
#
# Deliberately does not include slave.mk -- this file must be able to
# run directly in a bare checkout, without docker and without having
# run make configure.

PKG ?=
ifeq ($(PKG),)
$(error PKG is required, e.g. make -s -f scripts/ppa/query.mk PKG=libteam)
endif

# Minimal context expected by rules/<pkg>.mk
CONFIGURED_ARCH    ?= amd64
BLDENV             ?= resolute
SRC_PATH           := src
SONIC_MAKE_DEBS    :=
SONIC_ONLINE_DEBS  :=
SONIC_DERIVED_DEBS :=

include rules/config
# CONFIG_USER_PATH indirection: lets callers that need a hermetic run (see
# scripts/ppa/tests/manifest_test.sh) point this at /dev/null instead of a
# developer's real rules/config.user, which -include's with a plain `=` and
# so would otherwise beat both this variable's own `?=` default and any
# SONIC_PPA_* value the caller passed in via the environment.
CONFIG_USER_PATH ?= rules/config.user
-include $(CONFIG_USER_PATH)
include rules/functions
include rules/ppa-functions
include rules/$(PKG).mk

# Package directory name -> make variable prefix
PREFIX     := $(shell echo $(PKG) | tr 'a-z-' 'A-Z_')

# The main deb comes from whichever of the two registration lists is
# non-empty. This avoids needing a convention for what the "main deb
# variable" is called for each package -- isc-dhcp's is ISC_DHCP_RELAY,
# which is not equal to PREFIX.
MAIN_DEB   := $(strip $(SONIC_MAKE_DEBS) $(SONIC_ONLINE_DEBS))
MODE       := $(if $(filter $(PKG),$(SONIC_PPA_PACKAGES)),ppa,local)

# The patch directory containing series. More than one is ambiguous;
# error out rather than guess.
PATCH_DIRS := $(patsubst %/series,%,$(wildcard src/$(PKG)/*/series))

# Debian source package name: the part before `_` in the dsc URL's basename
SOURCE     := $(firstword $(subst _, ,$(notdir $($(PREFIX)_DSC_URL))))

# This source package's directory URL in the PPA pool. When
# SONIC_PPA_URL is empty, the whole string is empty, and the scripts
# use that to decide "cannot tell whether the orig is already
# uploaded". Kept in one place here so scripts don't have to re-derive
# it with sed.
PPA_POOL_URL := $(if $(SONIC_PPA_URL),$(SONIC_PPA_URL)/pool/main/$(call ppa_pool_dir,$(SOURCE))/$(SOURCE))

ifneq ($(words $(MAIN_DEB)),1)
$(error $(PKG): expected exactly 1 main deb, got "$(MAIN_DEB)")
endif
ifneq ($(words $(PATCH_DIRS)),1)
$(error $(PKG): expected exactly 1 patch dir containing a series file, got "$(PATCH_DIRS)")
endif

# add_derived_package (rules/functions:94) gives a derived deb a $(2)_URL that
# references its main deb's $(1)_URL -- but $(call ...) fully expands that
# reference at the moment add_derived_package is invoked, which in every
# rules/<pkg>.mk is BEFORE the ppa-mode block further down the file has set
# the main deb's own _URL. So a derived deb that never gets its own _URL
# override afterwards (see rules/libteam.mk's and rules/isc-dhcp.mk's
# comments on that ordering requirement) does not end up quietly inheriting
# the main deb's URL -- it ends up with an empty one, downloading nothing.
# The two checks below catch that (a missing override -> fewer non-empty
# URLs than debs) and its opposite mistake, a copy-pasted ppa_url call that
# names the wrong deb (two debs resolving to the identical URL -- $(sort ...)
# both sorts and deduplicates, so comparing word counts before/after it
# catches any repeated value). Only meaningful in ppa mode: in local mode
# none of these debs have a _URL at all, so every word would be "empty" and
# check (a) would fire for every package.
ifeq ($(MODE),ppa)
ALL_DEBS := $(MAIN_DEB) $(SONIC_DERIVED_DEBS)
ALL_URLS := $(foreach d,$(ALL_DEBS),$($(d)_URL))
ifneq ($(words $(ALL_URLS)),$(words $(ALL_DEBS)))
$(error $(PKG): $(words $(ALL_DEBS)) deb(s) registered ($(ALL_DEBS)) but only $(words $(ALL_URLS)) have a non-empty _URL in ppa mode -- one of them is missing its own _URL override after add_derived_package and its URL silently came out empty instead)
endif
ifneq ($(words $(sort $(ALL_URLS))),$(words $(ALL_URLS)))
$(error $(PKG): two or more of $(ALL_DEBS) resolve to the identical _URL in ppa mode -- check for a copy-pasted ppa_url call that names the wrong deb)
endif
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
	@echo 'SOURCE=$(SOURCE)'
	@echo 'PPA_POOL_URL=$(PPA_POOL_URL)'
