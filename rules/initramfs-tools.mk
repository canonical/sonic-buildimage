# initramfs-tools package

INITRAMFS_TOOLS_VERSION = 0.130
export INITRAMFS_TOOLS_VERSION

INITRAMFS_TOOLS = initramfs-tools_$(INITRAMFS_TOOLS_VERSION)_all.deb
$(INITRAMFS_TOOLS)_SRC_PATH = $(SRC_PATH)/initramfs-tools
SONIC_MAKE_DEBS += $(INITRAMFS_TOOLS)

INITRAMFS_TOOLS_CORE = initramfs-tools-core_$(INITRAMFS_TOOLS_VERSION)_all.deb
$(eval $(call add_extra_package,$(INITRAMFS_TOOLS),$(INITRAMFS_TOOLS_CORE)))

SONIC_STRETCH_DEBS += $(INITRAMFS_TOOLS) $(INITRAMFS_TOOLS_CORE)
