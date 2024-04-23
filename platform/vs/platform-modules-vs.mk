# VS Platform modules

VS_PLATFORM_MODULE_VERSION = 1.0

export VS_PLATFORM_MODULE_VERSION

VS_PLATFORM_MODULE = sonic-platform-vs_$(VS_PLATFORM_MODULE_VERSION)_amd64.deb
$(VS_PLATFORM_MODULE)_SRC_PATH = $(PLATFORM_PATH)/sonic-platform-modules-vs
$(VS_PLATFORM_MODULE)_DEPENDS =
$(VS_PLATFORM_MODULE)_PLATFORM = x86_64-kvm_x86_64-r0
SONIC_DPKG_DEBS += $(VS_PLATFORM_MODULE)
