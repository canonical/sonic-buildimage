# host-sflow package

HSFLOWD_VERSION = 2.0.51
HSFLOWD_SUBVERSION = 26

export ENABLE_SFLOW_DROPMON
export HSFLOWD_VERSION HSFLOWD_SUBVERSION

HSFLOWD = hsflowd_$(HSFLOWD_VERSION)-$(HSFLOWD_SUBVERSION)_$(CONFIGURED_ARCH).deb
$(HSFLOWD)_SRC_PATH = $(SRC_PATH)/sflow/hsflowd

SONIC_MAKE_DEBS += $(HSFLOWD)

HSFLOWD_DBG = hsflowd-dbgsym_$(HSFLOWD_VERSION)-$(HSFLOWD_SUBVERSION)_$(CONFIGURED_ARCH).$(DBG_DEB)
$(HSFLOWD_DBG)_DEPENDS += $(HSFLOWD)
$(HSFLOWD_DBG)_RDEPENDS += $(HSFLOWD)
$(eval $(call add_derived_package,$(HSFLOWD),$(HSFLOWD_DBG)))

export HSFLOWD HSFLOWD_DBG

# sflowtool package

SFLOWTOOL_VERSION = 5.04
export SFLOWTOOL_VERSION

SFLOWTOOL = sflowtool_$(SFLOWTOOL_VERSION)_$(CONFIGURED_ARCH).deb
$(SFLOWTOOL)_SRC_PATH = $(SRC_PATH)/sflow/sflowtool

SONIC_MAKE_DEBS += $(SFLOWTOOL)
export SFLOWTOOL

# psample package

PSAMPLE_VERSION = 1.1
PSAMPLE_SUBVERSION = 1
export PSAMPLE_VERSION PSAMPLE_SUBVERSION

PSAMPLE = psample_$(PSAMPLE_VERSION)-$(PSAMPLE_SUBVERSION)_$(CONFIGURED_ARCH).deb
$(PSAMPLE)_SRC_PATH = $(SRC_PATH)/sflow/psample

SONIC_MAKE_DEBS += $(PSAMPLE)
export PSAMPLE

# The .c, .cpp, .h & .hpp files under src/{$DBG_SRC_ARCHIVE list}
# are archived into debug one image to facilitate debugging.
#
DBG_SRC_ARCHIVE += sflow
