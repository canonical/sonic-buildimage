# Unit tests for the ppa_* helper functions. Does not include
# slave.mk -- only includes rules/functions and rules/ppa-functions, so
# this test can run instantly in a bare checkout.
# Usage: make -s -f scripts/ppa/tests/functions_test.mk

SONIC_PPA_URL              := https://ppa.launchpadcontent.net/o/n/ubuntu
SONIC_PPA_SUFFIX           := +sonic1~ppa1
SONIC_PPA_SUFFIX_lm-sensors := +sonic1~ppa2
SONIC_PPA_PACKAGES         := libteam lm-sensors

include rules/functions
include rules/ppa-functions
include scripts/ppa/tests/assert.mk

$(call assert,ppa_ver-on,$(call ppa_ver,libteam),+sonic1~ppa1)
$(call assert,ppa_ver-off,$(call ppa_ver,isc-dhcp),)
$(call assert,ppa_suffix-global,$(call ppa_suffix,libteam),+sonic1~ppa1)
$(call assert,ppa_suffix-override,$(call ppa_suffix,lm-sensors),+sonic1~ppa2)
$(call assert,pool_dir-lib,$(call ppa_pool_dir,libteam),libt)
$(call assert,pool_dir-plain,$(call ppa_pool_dir,lm-sensors),l)
$(call assert,pool_dir-hyphen,$(call ppa_pool_dir,isc-dhcp),i)
$(call assert,ppa_file-plain,$(call ppa_file,libteam5_1.31-1build4_amd64.deb),libteam5_1.31-1build4_amd64.deb)
$(call assert,ppa_file-dbgsym,$(call ppa_file,libteam5-dbgsym_1.31-1build4_amd64.deb),libteam5-dbgsym_1.31-1build4_amd64.ddeb)
$(call assert,ppa_url-dbgsym,$(call ppa_url,libteam,libteam5-dbgsym_1.31-1build4_amd64.deb),https://ppa.launchpadcontent.net/o/n/ubuntu/pool/main/libt/libteam/libteam5-dbgsym_1.31-1build4_amd64.ddeb)
$(call assert,ppa_url-all-deb,$(call ppa_url,lm-sensors,fancontrol_3.6.2-2build1+sonic1~ppa2_all.deb),https://ppa.launchpadcontent.net/o/n/ubuntu/pool/main/l/lm-sensors/fancontrol_3.6.2-2build1+sonic1~ppa2_all.deb)

.PHONY: default
default:
ifneq ($(strip $(FAILURES)),)
	@echo "FAILED: $(FAILURES)"; exit 1
else
	@echo "functions_test: all assertions passed"
endif
