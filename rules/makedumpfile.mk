# makedumpfile
# resolute: fetch stock Ubuntu deb via SONIC_ONLINE_DEBS. SONiC self-build was
# a zero-patch vanilla build; Ubuntu 26.04 ships the same version (1.7.7-1).

MAKEDUMPFILE_POOL_URL = http://archive.ubuntu.com/ubuntu/pool/main/m/makedumpfile
MAKEDUMPFILE_VERSION = 1.7.7-1

MAKEDUMPFILE = makedumpfile_$(MAKEDUMPFILE_VERSION)_$(CONFIGURED_ARCH).deb
$(MAKEDUMPFILE)_URL = $(MAKEDUMPFILE_POOL_URL)/$(MAKEDUMPFILE)
SONIC_ONLINE_DEBS += $(MAKEDUMPFILE)

export MAKEDUMPFILE_VERSION
export MAKEDUMPFILE
