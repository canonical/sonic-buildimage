# rasdaemon package — stock Ubuntu online deb (all SONiC patches upstreamed)

RASDAEMON_VERSION = 0.8.4-1

RASDAEMON = rasdaemon_$(RASDAEMON_VERSION)_$(CONFIGURED_ARCH).deb
RASDAEMON_POOL_URL = http://archive.ubuntu.com/ubuntu/pool/universe/r/rasdaemon
$(RASDAEMON)_URL = $(RASDAEMON_POOL_URL)/$(RASDAEMON)
SONIC_ONLINE_DEBS += $(RASDAEMON)

export RASDAEMON_VERSION
export RASDAEMON
