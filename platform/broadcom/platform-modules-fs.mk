## N8560W_48BC
FS_N8560W_48BC_PLATFORM_MODULE_VERSION = 1.0
export FS_N8560W_48BC_PLATFORM_MODULE_VERSION

FS_N8560W_48BC_PLATFORM_MODULE = platform-modules-fs-n8560w-48bc_$(FS_N8560W_48BC_PLATFORM_MODULE_VERSION)_amd64.deb
$(FS_N8560W_48BC_PLATFORM_MODULE)_SRC_PATH = $(PLATFORM_PATH)/sonic-platform-modules-fs
$(FS_N8560W_48BC_PLATFORM_MODULE)_DEPENDS += $(LINUX_HEADERS) $(LINUX_HEADERS_COMMON) $(PDDF_PLATFORM_MODULE)
$(FS_N8560W_48BC_PLATFORM_MODULE)_PLATFORM = x86_64-fs_n8560w_48bc-r0
SONIC_DPKG_DEBS += $(FS_N8560W_48BC_PLATFORM_MODULE)
SONIC_STRETCH_DEBS += $(FS_N8560W_48BC_PLATFORM_MODULE)

## N8560W_32C
FS_N8560W_32C_PLATFORM_MODULE_VERSION = 1.0
export FS_N8560W_32C_PLATFORM_MODULE_VERSION

FS_N8560W_32C_PLATFORM_MODULE = platform-modules-fs-n8560w-32c_$(FS_N8560W_32C_PLATFORM_MODULE_VERSION)_amd64.deb
$(FS_N8560W_32C_PLATFORM_MODULE)_PLATFORM = x86_64-fs_n8560w_32c-r0
$(eval $(call add_extra_package,$(FS_N8560W_48BC_PLATFORM_MODULE),$(FS_N8560W_32C_PLATFORM_MODULE)))
