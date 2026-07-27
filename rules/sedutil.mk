# resolute: fetch stock Ubuntu sedutil deb via SONIC_ONLINE_DEBS instead of
# binary-repackaging from GitHub. Ubuntu provides sedutil 1.20.0 in universe.

SEDUTIL_VERSION = 1.20.0-2build1
SEDUTIL = sedutil_$(SEDUTIL_VERSION)_$(CONFIGURED_ARCH).deb
SEDUTIL_POOL_URL = http://archive.ubuntu.com/ubuntu/pool/universe/s/sedutil
$(SEDUTIL)_URL = $(SEDUTIL_POOL_URL)/$(SEDUTIL)
SONIC_ONLINE_DEBS += $(SEDUTIL)
