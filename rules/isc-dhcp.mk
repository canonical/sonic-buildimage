# isc-dhcp packages

ISC_DHCP_VERSION = 4.4.3-P1
ISC_DHCP_VERSION_STOCK = ${ISC_DHCP_VERSION}-2
ISC_DHCP_VERSION_FULL = $(ISC_DHCP_VERSION_STOCK)$(call ppa_ver,isc-dhcp)

ISC_DHCP_DSC_URL = http://deb.debian.org/debian/pool/main/i/isc-dhcp/isc-dhcp_$(ISC_DHCP_VERSION_STOCK).dsc

export ISC_DHCP_VERSION ISC_DHCP_VERSION_FULL ISC_DHCP_VERSION_STOCK ISC_DHCP_DSC_URL

ISC_DHCP_RELAY = isc-dhcp-relay_$(ISC_DHCP_VERSION_FULL)_$(CONFIGURED_ARCH).deb
$(ISC_DHCP_RELAY)_SRC_PATH = $(SRC_PATH)/isc-dhcp
ifneq ($(filter isc-dhcp,$(SONIC_PPA_PACKAGES)),)
SONIC_ONLINE_DEBS += $(ISC_DHCP_RELAY)
else
SONIC_MAKE_DEBS += $(ISC_DHCP_RELAY)
endif

ISC_DHCP_RELAY_DBG = isc-dhcp-relay-dbgsym_$(ISC_DHCP_VERSION_FULL)_$(CONFIGURED_ARCH).deb
$(eval $(call add_derived_package,$(ISC_DHCP_RELAY),$(ISC_DHCP_RELAY_DBG)))

# PPA 模式:主包与 dbgsym 各自的下载地址。必须位于 add_derived_package 之后。
ifneq ($(filter isc-dhcp,$(SONIC_PPA_PACKAGES)),)
$(ISC_DHCP_RELAY)_URL     = $(call ppa_url,isc-dhcp,$(ISC_DHCP_RELAY))
$(ISC_DHCP_RELAY_DBG)_URL = $(call ppa_url,isc-dhcp,$(ISC_DHCP_RELAY_DBG))
endif

export ISC_DHCP_RELAY ISC_DHCP_RELAY_DBG
