# lm-senensors package

LM_SENSORS_MAJOR_VERSION = 3
LM_SENSORS_MINOR_VERSION = 6
LM_SENSORS_PATCH_VERSION = 2

LIBSENSORS_VERSION = 5

LM_SENSORS_VERSION=$(LM_SENSORS_MAJOR_VERSION).$(LM_SENSORS_MINOR_VERSION).$(LM_SENSORS_PATCH_VERSION)
LM_SENSORS_VERSION_STOCK=$(LM_SENSORS_VERSION)-2build1
LM_SENSORS_VERSION_FULL=$(LM_SENSORS_VERSION_STOCK)$(call ppa_ver,lm-sensors)

LM_SENSORS_DSC_URL=http://archive.ubuntu.com/ubuntu/pool/main/l/lm-sensors/lm-sensors_$(LM_SENSORS_VERSION_STOCK).dsc

LM_SENSORS = lm-sensors_$(LM_SENSORS_VERSION_FULL)_$(CONFIGURED_ARCH).deb
$(LM_SENSORS)_SRC_PATH = $(SRC_PATH)/lm-sensors

LM_SENSORS_DBG = lm-sensors-dbgsym_$(LM_SENSORS_VERSION_FULL)_$(CONFIGURED_ARCH).deb
$(eval $(call add_derived_package,$(LM_SENSORS),$(LM_SENSORS_DBG)))

FANCONTROL = fancontrol_$(LM_SENSORS_VERSION_FULL)_all.deb
$(eval $(call add_derived_package,$(LM_SENSORS),$(FANCONTROL)))

LIBSENSORS = libsensors$(LIBSENSORS_VERSION)_$(LM_SENSORS_VERSION_FULL)_$(CONFIGURED_ARCH).deb
$(eval $(call add_derived_package,$(LM_SENSORS),$(LIBSENSORS)))

LIBSENSORS_DBG = libsensors$(LIBSENSORS_VERSION)-dbgsym_$(LM_SENSORS_VERSION_FULL)_$(CONFIGURED_ARCH).deb
$(eval $(call add_derived_package,$(LM_SENSORS),$(LIBSENSORS_DBG)))

SENSORD = sensord_$(LM_SENSORS_VERSION_FULL)_$(CONFIGURED_ARCH).deb
$(eval $(call add_derived_package,$(LM_SENSORS),$(SENSORD)))
$(SENSORD)_DEPENDS += $(LIBSENSORS) $(LM_SENSORS)

SENSORD_DBG = sensord-dbgsym_$(LM_SENSORS_VERSION_FULL)_$(CONFIGURED_ARCH).deb
$(eval $(call add_derived_package,$(LM_SENSORS),$(SENSORD_DBG)))

# Unlike rules/libteam.mk and rules/isc-dhcp.mk, this merges the main-deb
# registration (SONIC_ONLINE_DEBS/SONIC_MAKE_DEBS) and every _URL override
# into one single ifneq block instead of keeping them in two separate blocks.
# That is only safe because this whole block, registration included, already
# sits after every add_derived_package call above it -- the same requirement
# those other two files' separate override block satisfies (that macro makes
# derived debs inherit the main deb's _URL by default, rules/functions:94).
# Registration order itself does not matter to add_derived_package; only the
# _URL overrides do. Moving this block above any add_derived_package call
# above would silently leave $(LM_SENSORS_DBG)_URL and friends pointing at
# whatever $(LM_SENSORS)_URL happened to be at that point (unset, for the
# local-build else branch), not this block's own PPA URL.
ifneq ($(filter lm-sensors,$(SONIC_PPA_PACKAGES)),)
SONIC_ONLINE_DEBS += $(LM_SENSORS)
$(LM_SENSORS)_URL     = $(call ppa_url,lm-sensors,$(LM_SENSORS))
$(LM_SENSORS_DBG)_URL = $(call ppa_url,lm-sensors,$(LM_SENSORS_DBG))
$(FANCONTROL)_URL     = $(call ppa_url,lm-sensors,$(FANCONTROL))
$(LIBSENSORS)_URL     = $(call ppa_url,lm-sensors,$(LIBSENSORS))
$(LIBSENSORS_DBG)_URL = $(call ppa_url,lm-sensors,$(LIBSENSORS_DBG))
$(SENSORD)_URL        = $(call ppa_url,lm-sensors,$(SENSORD))
$(SENSORD_DBG)_URL    = $(call ppa_url,lm-sensors,$(SENSORD_DBG))
else
SONIC_MAKE_DEBS += $(LM_SENSORS)
endif

# The .c, .cpp, .h & .hpp files under src/{$DBG_SRC_ARCHIVE list}
# are archived into debug one image to facilitate debugging.
#
DBG_SRC_ARCHIVE += lm-sensors

export LM_SENSORS
export FANCONTROL
export LIBSENSORS
export SENSORD
export LM_SENSORS_VERSION
export LM_SENSORS_VERSION_STOCK
export LM_SENSORS_VERSION_FULL
export LM_SENSORS_DSC_URL
export LM_SENSORS_DBG
export LIBSENSORS_DBG
export SENSORD_DBG
