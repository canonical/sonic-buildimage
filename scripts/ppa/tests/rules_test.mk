# Dual-mode unit test for rules/<pkg>.mk: verifies that when
# SONIC_PPA_PACKAGES does or doesn't contain the package, it registers
# to the correct list, the deb names carry the suffix, and each deb's
# _URL is correct.
# Usage: make -s -f scripts/ppa/tests/rules_test.mk

CONFIGURED_ARCH    := amd64
SRC_PATH           := src
SONIC_MAKE_DEBS    :=
SONIC_ONLINE_DEBS  :=
SONIC_DERIVED_DEBS :=

SONIC_PPA_URL      := https://ppa.launchpadcontent.net/o/n/ubuntu
SONIC_PPA_SUFFIX   := +sonic1~ppa1
# Only switches libteam, isc-dhcp, lm-sensors to PPA mode here, to verify the switch applies per-package rather than globally
SONIC_PPA_PACKAGES := libteam isc-dhcp lm-sensors

include rules/functions
include rules/ppa-functions
include rules/libteam.mk
include rules/isc-dhcp.mk
include rules/lm-sensors.mk
include scripts/ppa/tests/assert.mk

# PPA mode: registers to ONLINE rather than MAKE, and the deb name carries the suffix
# (using $(filter libteam5%,...) instead of a bare-value comparison:
# SONIC_ONLINE_DEBS is now a global list shared by libteam and
# isc-dhcp, so a bare comparison would get polluted by the other
# package's main package name)
$(call assert,libteam-online,$(filter libteam5%,$(SONIC_ONLINE_DEBS)),libteam5_1.31-1build4+sonic1~ppa1_amd64.deb)
$(call assert,libteam-not-make,$(SONIC_MAKE_DEBS),)
$(call assert,libteam-main-name,$(LIBTEAM),libteam5_1.31-1build4+sonic1~ppa1_amd64.deb)
$(call assert,libteam-stock-ver,$(LIBTEAM_VERSION_STOCK),1.31-1build4)

# Derived package count is unchanged (1 main + 6 derived). Same filtering reason: SONIC_DERIVED_DEBS is also a shared list now.
$(call assert,libteam-derived-count,$(words $(filter libteam%,$(SONIC_DERIVED_DEBS))),6)

# Main package URL
$(call assert,libteam-main-url,$($(LIBTEAM)_URL),https://ppa.launchpadcontent.net/o/n/ubuntu/pool/main/libt/libteam/libteam5_1.31-1build4+sonic1~ppa1_amd64.deb)

# The dbgsym derived package's URL must be overridden to its own
# address, with a .ddeb extension
# (add_derived_package defaults to having it inherit the main package's
# URL, rules/functions:94)
$(call assert,libteam-dbg-url,$($(LIBTEAM_DBG)_URL),https://ppa.launchpadcontent.net/o/n/ubuntu/pool/main/libt/libteam/libteam5-dbgsym_1.31-1build4+sonic1~ppa1_amd64.ddeb)

# A non-dbgsym derived package's URL keeps the .deb extension
$(call assert,libteam-dev-url,$($(LIBTEAM_DEV)_URL),https://ppa.launchpadcontent.net/o/n/ubuntu/pool/main/libt/libteam/libteam-dev_1.31-1build4+sonic1~ppa1_amd64.deb)

# The dsc URL uses the stock version and must never carry the PPA suffix
$(call assert,libteam-dsc-url,$(LIBTEAM_DSC_URL),http://archive.ubuntu.com/ubuntu/pool/main/libt/libteam/libteam_1.31-1build4.dsc)

$(call assert,iscdhcp-online,$(filter isc-dhcp-relay%,$(SONIC_ONLINE_DEBS)),isc-dhcp-relay_4.4.3-P1-2+sonic1~ppa1_amd64.deb)
$(call assert,iscdhcp-stock-ver,$(ISC_DHCP_VERSION_STOCK),4.4.3-P1-2)
$(call assert,iscdhcp-dsc-url,$(ISC_DHCP_DSC_URL),http://deb.debian.org/debian/pool/main/i/isc-dhcp/isc-dhcp_4.4.3-P1-2.dsc)
$(call assert,iscdhcp-dbg-url,$($(ISC_DHCP_RELAY_DBG)_URL),https://ppa.launchpadcontent.net/o/n/ubuntu/pool/main/i/isc-dhcp/isc-dhcp-relay-dbgsym_4.4.3-P1-2+sonic1~ppa1_amd64.ddeb)

$(call assert,lmsensors-stock-ver,$(LM_SENSORS_VERSION_STOCK),3.6.2-2build1)
$(call assert,lmsensors-main-name,$(LM_SENSORS),lm-sensors_3.6.2-2build1+sonic1~ppa1_amd64.deb)
$(call assert,lmsensors-dsc-url,$(LM_SENSORS_DSC_URL),http://archive.ubuntu.com/ubuntu/pool/main/l/lm-sensors/lm-sensors_3.6.2-2build1.dsc)
$(call assert,lmsensors-sensord-url,$($(SENSORD)_URL),https://ppa.launchpadcontent.net/o/n/ubuntu/pool/main/l/lm-sensors/sensord_3.6.2-2build1+sonic1~ppa1_amd64.deb)
$(call assert,lmsensors-fancontrol-url,$($(FANCONTROL)_URL),https://ppa.launchpadcontent.net/o/n/ubuntu/pool/main/l/lm-sensors/fancontrol_3.6.2-2build1+sonic1~ppa1_all.deb)

.PHONY: default
default:
ifneq ($(strip $(FAILURES)),)
	@echo "FAILED: $(FAILURES)"; exit 1
else
	@echo "rules_test: all assertions passed"
endif
