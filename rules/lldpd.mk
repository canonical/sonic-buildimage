# lldpd package — stock Ubuntu online deb (all SONiC patches upstreamed)

LLDPD_VERSION = 1.0.19
LLDPD_VERSION_FULL = $(LLDPD_VERSION)-1

LLDPD_POOL_URL = http://archive.ubuntu.com/ubuntu/pool/universe/l/lldpd

LLDPD = lldpd_$(LLDPD_VERSION_FULL)_$(CONFIGURED_ARCH).deb
$(LLDPD)_URL = $(LLDPD_POOL_URL)/$(LLDPD)
SONIC_ONLINE_DEBS += $(LLDPD)

LIBLLDPCTL = liblldpctl-dev_$(LLDPD_VERSION_FULL)_$(CONFIGURED_ARCH).deb
$(LIBLLDPCTL)_URL = $(LLDPD_POOL_URL)/$(LIBLLDPCTL)
SONIC_ONLINE_DEBS += $(LIBLLDPCTL)

# NOTE: lldpd-dbgsym is NOT available as an online deb — Ubuntu dbgsym
# packages live at ddebs.ubuntu.com (separate archive), not the main pool.
# LLDPD_DBG is kept as a variable so rules/docker-lldp.mk can reference it
# without error, but it is intentionally NOT added to SONIC_ONLINE_DEBS.
LLDPD_DBG = lldpd-dbgsym_$(LLDPD_VERSION_FULL)_$(CONFIGURED_ARCH).deb

# Export these variables so they can be used in a sub-make
export LLDPD_VERSION
export LLDPD_VERSION_FULL
export LLDPD
export LIBLLDPCTL
export LLDPD_DBG

# The .c, .cpp, .h & .hpp files under src/{$DBG_SRC_ARCHIVE list}
# are archived into debug one image to facilitate debugging.
#
DBG_SRC_ARCHIVE += lldpd
