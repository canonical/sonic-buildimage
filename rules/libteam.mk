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
ifneq ($(filter libteam,$(SONIC_PPA_PACKAGES)),)
SONIC_ONLINE_DEBS += $(LIBTEAM)
else
SONIC_MAKE_DEBS += $(LIBTEAM)
endif

LIBTEAM_DBG = libteam5-dbgsym_$(LIBTEAM_VERSION_FULL)_$(CONFIGURED_ARCH).deb
$(eval $(call add_derived_package,$(LIBTEAM),$(LIBTEAM_DBG)))

LIBTEAM_DEV = libteam-dev_$(LIBTEAM_VERSION_FULL)_$(CONFIGURED_ARCH).deb
$(LIBTEAM_DEV)_DEPENDS += $(LIBTEAMDCTL)
$(eval $(call add_derived_package,$(LIBTEAM),$(LIBTEAM_DEV)))

LIBTEAMDCTL = libteamdctl0_$(LIBTEAM_VERSION_FULL)_$(CONFIGURED_ARCH).deb
$(eval $(call add_derived_package,$(LIBTEAM),$(LIBTEAMDCTL)))

LIBTEAMDCTL_DBG = libteamdctl0-dbgsym_$(LIBTEAM_VERSION_FULL)_$(CONFIGURED_ARCH).deb
$(eval $(call add_derived_package,$(LIBTEAM),$(LIBTEAMDCTL_DBG)))

LIBTEAM_UTILS = libteam-utils_$(LIBTEAM_VERSION_FULL)_$(CONFIGURED_ARCH).deb
$(LIBTEAM_UTILS)_DEPENDS += $(LIBTEAMDCTL)
$(eval $(call add_derived_package,$(LIBTEAM),$(LIBTEAM_UTILS)))

LIBTEAM_UTILS_DBG = libteam-utils-dbgsym_$(LIBTEAM_VERSION_FULL)_$(CONFIGURED_ARCH).deb
$(eval $(call add_derived_package,$(LIBTEAM),$(LIBTEAM_UTILS_DBG)))

# PPA 模式：主包与每个派生包各自的下载地址。必须位于所有 add_derived_package
# 调用之后 —— 那个宏会让派生包继承主包的 _URL（rules/functions:94）。
ifneq ($(filter libteam,$(SONIC_PPA_PACKAGES)),)
$(LIBTEAM)_URL             = $(call ppa_url,libteam,$(LIBTEAM))
$(LIBTEAM_DBG)_URL         = $(call ppa_url,libteam,$(LIBTEAM_DBG))
$(LIBTEAM_DEV)_URL         = $(call ppa_url,libteam,$(LIBTEAM_DEV))
$(LIBTEAMDCTL)_URL         = $(call ppa_url,libteam,$(LIBTEAMDCTL))
$(LIBTEAMDCTL_DBG)_URL     = $(call ppa_url,libteam,$(LIBTEAMDCTL_DBG))
$(LIBTEAM_UTILS)_URL       = $(call ppa_url,libteam,$(LIBTEAM_UTILS))
$(LIBTEAM_UTILS_DBG)_URL   = $(call ppa_url,libteam,$(LIBTEAM_UTILS_DBG))
endif

# The .c, .cpp, .h & .hpp files under src/{$DBG_SRC_ARCHIVE list}
# are archived into debug one image to facilitate debugging.
#
DBG_SRC_ARCHIVE += libteam
