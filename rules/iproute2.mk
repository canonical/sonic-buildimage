# iproute2 - patched for EVPN Multihoming protocol field support

ifneq ($(filter $(BLDENV), trixie resolute),)

ifeq ($(BLDENV), trixie)
IPROUTE2_VERSION_BASE = 6.15.0
IPROUTE2_VERSION = $(IPROUTE2_VERSION_BASE)-1
IPROUTE2_DSC_URL = https://deb.debian.org/debian/pool/main/i/iproute2/iproute2_$(IPROUTE2_VERSION).dsc
else
IPROUTE2_VERSION_BASE = 6.19.0
IPROUTE2_VERSION = $(IPROUTE2_VERSION_BASE)-1ubuntu1
IPROUTE2_DSC_URL = http://archive.ubuntu.com/ubuntu/pool/main/i/iproute2/iproute2_$(IPROUTE2_VERSION).dsc
endif
IPROUTE2_VERSION_FULL = $(IPROUTE2_VERSION)+sonic.0

export IPROUTE2_VERSION_BASE
export IPROUTE2_VERSION
export IPROUTE2_VERSION_FULL
export IPROUTE2_DSC_URL
export IPROUTE2
export IPROUTE2_DBG

IPROUTE2 = iproute2_$(IPROUTE2_VERSION_FULL)_$(CONFIGURED_ARCH).deb
$(IPROUTE2)_SRC_PATH = $(SRC_PATH)/iproute2
SONIC_MAKE_DEBS += $(IPROUTE2)

IPROUTE2_DBG = iproute2-dbgsym_$(IPROUTE2_VERSION_FULL)_$(CONFIGURED_ARCH).deb
$(IPROUTE2_DBG)_DEPENDS += $(IPROUTE2)
$(IPROUTE2_DBG)_RDEPENDS += $(IPROUTE2)
$(eval $(call add_derived_package,$(IPROUTE2),$(IPROUTE2_DBG)))

endif
