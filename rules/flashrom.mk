# flashrom package — stock Ubuntu online deb (all SONiC patches upstreamed)

FLASHROM_VERSION = 1.6.0-2ubuntu1

FLASHROM = flashrom_$(FLASHROM_VERSION)_$(CONFIGURED_ARCH).deb
FLASHROM_POOL_URL = http://archive.ubuntu.com/ubuntu/pool/main/f/flashrom
$(FLASHROM)_URL = $(FLASHROM_POOL_URL)/$(FLASHROM)
SONIC_ONLINE_DEBS += $(FLASHROM)

export FLASHROM_VERSION
export FLASHROM
