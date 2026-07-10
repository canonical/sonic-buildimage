# linux kernel package — Launchpad PPA prebuilt (linux-sonic 7.0.0-1002.2)
#
# Source: ~canonical-kernel-team/+archive/ubuntu/bootstrap (resolute series).
# Procured via SONIC_ONLINE_DEBS (curl +files URL), not built from source.
# Package style: Ubuntu (image depends on separate linux-modules; no linux-kbuild;
# build-script tree ships inside linux-headers).

KERNEL_VERSION = 7.0.0
KERNEL_ABISUFFIX = -1002
KERNEL_FEATURESET = sonic
KERNEL_PKGVERSION = 7.0.0-1002.2
# Note: KVERSION_SHORT is used by Arista
KVERSION_SHORT := $(KERNEL_VERSION)$(KERNEL_ABISUFFIX)-$(KERNEL_FEATURESET)
ifeq ($(CONFIGURED_ARCH), armhf)
# Override kernel version for ARMHF as it uses arm MP (multi-platform) for short version
KVERSION ?= $(KVERSION_SHORT)-armmp
else
KVERSION ?= $(KVERSION_SHORT)
endif

export KVERSION_SHORT KVERSION KERNEL_VERSION KERNEL_ABISUFFIX KERNEL_FEATURESET KERNEL_PKGVERSION

# Launchpad PPA binary pool (ppa.launchpadcontent.net direct 200; the +files URL's 303
# target launchpadlibrarian.net is unreachable from the build env — see Task 0).
KERNEL_PPA_URL = https://ppa.launchpadcontent.net/canonical-kernel-team/bootstrap/ubuntu/pool/main/l/linux-sonic

# common headers (architecture-independent, all) — MAIN_TARGET
LINUX_HEADERS_COMMON = linux-sonic-headers-$(KERNEL_VERSION)$(KERNEL_ABISUFFIX)_$(KERNEL_PKGVERSION)_all.deb
$(LINUX_HEADERS_COMMON)_URL = $(KERNEL_PPA_URL)/$(LINUX_HEADERS_COMMON)

# arch-specific image + modules + headers (derived from common)
LINUX_IMAGE   = linux-image-$(KVERSION)_$(KERNEL_PKGVERSION)_$(CONFIGURED_ARCH).deb
LINUX_MODULES = linux-modules-$(KVERSION)_$(KERNEL_PKGVERSION)_$(CONFIGURED_ARCH).deb
LINUX_HEADERS = linux-headers-$(KVERSION)_$(KERNEL_PKGVERSION)_$(CONFIGURED_ARCH).deb

$(LINUX_HEADERS_COMMON)_DERIVED_DEBS = $(LINUX_IMAGE) $(LINUX_MODULES) $(LINUX_HEADERS)
$(LINUX_IMAGE)_URL   = $(KERNEL_PPA_URL)/$(LINUX_IMAGE)
$(LINUX_MODULES)_URL = $(KERNEL_PPA_URL)/$(LINUX_MODULES)
$(LINUX_HEADERS)_URL = $(KERNEL_PPA_URL)/$(LINUX_HEADERS)

# Install order via _DEPENDS topological -install prerequisites (slave.mk:1004):
#   linux-modules  before  linux-image  (image Depends: linux-modules)
#   common headers before  arch headers (arch headers Depends: common)
$(LINUX_IMAGE)_DEPENDS += $(LINUX_MODULES)
$(LINUX_HEADERS)_DEPENDS += $(LINUX_HEADERS_COMMON)

SONIC_ONLINE_DEBS += $(LINUX_HEADERS_COMMON) $(LINUX_IMAGE) $(LINUX_MODULES) $(LINUX_HEADERS)
