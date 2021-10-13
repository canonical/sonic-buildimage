
CAMEO_ESC601_32Q_PLATFORM_MODULE_VERSION = 1.0.0
CAMEO_ESC600_128Q_PLATFORM_MODULE_VERSION = 1.0.0
CAMEO_ESQC610_56SQ_PLATFORM_MODULE_VERSION = 1.0.0
CAMEO_ESC602_32Q_PLATFORM_MODULE_VERSION = 1.0.0
CAMEO_ESCC601_32Q_PLATFORM_MODULE_VERSION = 1.0.0

export CAMEO_ESC601_32Q_PLATFORM_MODULE_VERSION
export CAMEO_ESC600_128Q_PLATFORM_MODULE_VERSION
export CAMEO_ESQC610_56SQ_PLATFORM_MODULE_VERSION
export CAMEO_ESC602_32Q_PLATFORM_MODULE_VERSION

CAMEO_ESC601_32Q_PLATFORM_MODULE = sonic-platform-cameo-esc601-32q_$(CAMEO_ESC601_32Q_PLATFORM_MODULE_VERSION)_amd64.deb
$(CAMEO_ESC601_32Q_PLATFORM_MODULE)_SRC_PATH = $(PLATFORM_PATH)/sonic-platform-modules-cameo
$(CAMEO_ESC601_32Q_PLATFORM_MODULE)_DEPENDS += $(LINUX_HEADERS) $(LINUX_HEADERS_COMMON)
$(CAMEO_ESC601_32Q_PLATFORM_MODULE)_PLATFORM = x86_64-cameo_esc601_32q-r0
SONIC_DPKG_DEBS += $(CAMEO_ESC601_32Q_PLATFORM_MODULE)

CAMEO_ESC600_128Q_PLATFORM_MODULE = sonic-platform-cameo-esc600-128q_$(CAMEO_ESC600_128Q_PLATFORM_MODULE_VERSION)_amd64.deb
$(CAMEO_ESC600_128Q_PLATFORM_MODULE)_PLATFORM = x86_64-cameo_esc600_128q-r0
$(eval $(call add_extra_package,$(CAMEO_ESC601_32Q_PLATFORM_MODULE),$(CAMEO_ESC600_128Q_PLATFORM_MODULE)))

CAMEO_ESQC610_56SQ_PLATFORM_MODULE = sonic-platform-cameo-esqc610-56sq_$(CAMEO_ESQC610_56SQ_PLATFORM_MODULE_VERSION)_amd64.deb
$(CAMEO_ESQC610_56SQ_PLATFORM_MODULE)_PLATFORM = x86_64-cameo_esqc610_56sq-r0
$(eval $(call add_extra_package,$(CAMEO_ESC601_32Q_PLATFORM_MODULE),$(CAMEO_ESQC610_56SQ_PLATFORM_MODULE)))

CAMEO_ESC602_32Q_PLATFORM_MODULE = sonic-platform-cameo-esc602-32q_$(CAMEO_ESC602_32Q_PLATFORM_MODULE_VERSION)_amd64.deb
$(CAMEO_ESC602_32Q_PLATFORM_MODULE)_PLATFORM = x86_64-cameo_esc602_32q-r0
$(eval $(call add_extra_package,$(CAMEO_ESC601_32Q_PLATFORM_MODULE),$(CAMEO_ESC602_32Q_PLATFORM_MODULE)))

CAMEO_ESCC601_32Q_PLATFORM_MODULE = sonic-platform-cameo-escc601-32q_$(CAMEO_ESCC601_32Q_PLATFORM_MODULE_VERSION)_amd64.deb
$(CAMEO_ESCC601_32Q_PLATFORM_MODULE)_PLATFORM = x86_64-cameo_escc601_32q-r0
$(eval $(call add_extra_package,$(CAMEO_ESC601_32Q_PLATFORM_MODULE),$(CAMEO_ESCC601_32Q_PLATFORM_MODULE)))

