# SONiC device-health package

SONIC_DEVICE_HEALTH_VERSION = 1.0.0-0
SONIC_DEVICE_HEALTH_PKG_NAME = device-health

SONIC_DEVICE_HEALTH = sonic-$(SONIC_DEVICE_HEALTH_PKG_NAME)_$(SONIC_DEVICE_HEALTH_VERSION)_$(CONFIGURED_ARCH).deb
$(SONIC_DEVICE_HEALTH)_SRC_PATH = $(SRC_PATH)/sonic-device-health
$(SONIC_DEVICE_HEALTH)_DEPENDS  = $(LIBSWSSCOMMON_DEV) $(LIBSWSSCOMMON) 

SONIC_DPKG_DEBS += $(SONIC_DEVICE_HEALTH)

# The .c, .cpp, .h & .hpp files under src/{$DBG_SRC_ARCHIVE list}
# are archived into debug one image to facilitate debugging.
#
DBG_SRC_ARCHIVE += sonic-device-health

