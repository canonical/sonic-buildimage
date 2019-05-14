# libyang

LIBYANG_VERSION_BASE = 0.16
LIBYANG_VERSION = $(LIBYANG_VERSION_BASE).105
LIBYANG_SUBVERSION = 1

export LIBYANG_VERSION_BASE
export LIBYANG_VERSION
export LIBYANG_SUBVERSION

LIBYANG = libyang$(LIBYANG_VERSION_BASE)_$(LIBYANG_VERSION)-$(LIBYANG_SUBVERSION)_amd64.deb
$(LIBYANG)_SRC_PATH = $(SRC_PATH)/libyang
$(LIBYAND)_DEPENDS += $(SWIG_BASE) $(SWIG)
SONIC_MAKE_DEBS += $(LIBYANG)
SONIC_STRETCH_DEBS += $(LIBYANG)

LIBYANG_DEV = libyang-dev_$(LIBYANG_VERSION)-$(LIBYANG_SUBVERSION)_amd64.deb
$(eval $(call add_derived_package,$(LIBYANG),$(LIBYANG_DEV)))

export LIBYANG LIBYANG_DEV
