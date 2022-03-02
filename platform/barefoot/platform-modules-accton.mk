# BFN Platform modules

BFN_MONTARA_QS_PLATFORM_MODULE_VERSION = 1.1

export BFN_MONTARA_QS_PLATFORM_MODULE_VERSION

BFN_MONTARA_QS_PLATFORM_MODULE = sonic-platform-accton-wedge100bf-32qs_$(BFN_MONTARA_QS_PLATFORM_MODULE_VERSION)_amd64.deb
$(BFN_MONTARA_QS_PLATFORM_MODULE)_SRC_PATH = $(PLATFORM_PATH)/sonic-platform-modules-accton
$(BFN_MONTARA_QS_PLATFORM_MODULE)_DEPENDS += $(LINUX_HEADERS) $(LINUX_HEADERS_COMMON)
$(BFN_MONTARA_QS_PLATFORM_MODULE)_PLATFORM = x86_64-accton_wedge100bf_32qs-r0
SONIC_DPKG_DEBS += $(BFN_MONTARA_QS_PLATFORM_MODULE)
