# libpam-radius-auth — resolute: stock Ubuntu online deb (de-fork, no source needed)

PAM_RADIUS_VERSION = 3.0.0-1build1

export PAM_RADIUS_VERSION

LIBPAM_RADIUS = libpam-radius-auth_$(PAM_RADIUS_VERSION)_$(CONFIGURED_ARCH).deb
LIBPAM_RADIUS_POOL_URL = http://archive.ubuntu.com/ubuntu/pool/universe/libp/libpam-radius-auth
$(LIBPAM_RADIUS)_URL = $(LIBPAM_RADIUS_POOL_URL)/$(LIBPAM_RADIUS)
SONIC_ONLINE_DEBS += $(LIBPAM_RADIUS)

# libnss-radius packages

NSS_RADIUS_VERSION = 1.0.1-1

export NSS_RADIUS_VERSION

LIBNSS_RADIUS = libnss-radius_$(NSS_RADIUS_VERSION)_$(CONFIGURED_ARCH).deb
$(LIBNSS_RADIUS)_SRC_PATH = $(SRC_PATH)/radius/nss
SONIC_MAKE_DEBS += $(LIBNSS_RADIUS)

LIBNSS_RADIUS_DBG = libnss-radius-dbgsym_$(NSS_RADIUS_VERSION)_$(CONFIGURED_ARCH).deb
$(LIBNSS_RADIUS_DBG)_DEPENDS += $(LIBNSS_RADIUS)
$(LIBNSS_RADIUS_DBG)_RDEPENDS += $(LIBNSS_RADIUS)
$(eval $(call add_derived_package,$(LIBNSS_RADIUS),$(LIBNSS_RADIUS_DBG)))

SONIC_STRETCH_DEBS += $(LIBNSS_RADIUS)
