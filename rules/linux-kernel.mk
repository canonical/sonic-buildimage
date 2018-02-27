# linux kernel package

KVERSION_SHORT = 3.16.0-5
KVERSION ?= $(KVERSION_SHORT)-amd64
KERNEL_VERSION = 3.16.51
KERNEL_SUBVERSION = 3+deb8u1

export KVERSION_SHORT KVERSION KERNEL_VERSION KERNEL_SUBVERSION

LINUX_HEADERS_COMMON = linux-headers-$(KVERSION_SHORT)-common_$(KERNEL_VERSION)-$(KERNEL_SUBVERSION)_amd64.deb
$(LINUX_HEADERS_COMMON)_SRC_PATH = $(SRC_PATH)/sonic-linux-kernel
SONIC_MAKE_DEBS += $(LINUX_HEADERS_COMMON)

LINUX_HEADERS = linux-headers-$(KVERSION)_$(KERNEL_VERSION)-$(KERNEL_SUBVERSION)_amd64.deb
$(eval $(call add_derived_package,$(LINUX_HEADERS_COMMON),$(LINUX_HEADERS)))

LINUX_KERNEL = linux-image-$(KVERSION)_$(KERNEL_VERSION)-$(KERNEL_SUBVERSION)_amd64.deb
$(eval $(call add_derived_package,$(LINUX_HEADERS_COMMON),$(LINUX_KERNEL)))
