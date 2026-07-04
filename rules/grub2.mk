# grub2 package

GRUB2_UPSTREAM_VERSION := 2.14
GRUB2_VERSION := 2.14-2ubuntu2

export GRUB2_UPSTREAM_VERSION

export GRUB2_VERSION

GRUB2_COMMON = grub2-common_$(GRUB2_VERSION)_$(CONFIGURED_ARCH).deb
$(GRUB2_COMMON)_SRC_PATH = $(SRC_PATH)/grub2
SONIC_MAKE_DEBS += $(GRUB2_COMMON)

GRUB_COMMON = grub-common_$(GRUB2_VERSION)_$(CONFIGURED_ARCH).deb
$(eval $(call add_derived_package,$(GRUB2_COMMON),$(GRUB_COMMON)))

GRUB_EFI = grub-efi_$(GRUB2_VERSION)_$(CONFIGURED_ARCH).deb
$(eval $(call add_derived_package,$(GRUB2_COMMON),$(GRUB_EFI)))

ifeq ($(CONFIGURED_ARCH),amd64)
GRUB_PC_BIN = grub-pc-bin_$(GRUB2_VERSION)_$(CONFIGURED_ARCH).deb
$(eval $(call add_derived_package,$(GRUB2_COMMON),$(GRUB_PC_BIN)))
else ifeq ($(CONFIGURED_ARCH),arm64)
endif

# resolute: Ubuntu splits grub2 into src:grub2 (above) and src:grub2-unsigned
# (below). src:grub2 builds grub2-common/grub-pc etc. but EXCLUDES
# grub-efi-amd64-bin/unsigned/dbg (debian/rules: SB_SUBMIT=no when
# DEB_SOURCE=grub2). Those come from src:grub2-unsigned (DEB_SOURCE=grub2-unsigned
# -> SB_SUBMIT=yes -> ONLY_BUILD=-pgrub-efi-amd64-bin...). Debian trixie had a
# single src:grub2 producing all; Ubuntu resolute split them, so we build both.
GRUB2_UNSIGNED_VERSION = 2.14-2ubuntu1

ifeq ($(CONFIGURED_ARCH),amd64)
GRUB_EFI_AMD64 = grub-efi-amd64_$(GRUB2_UNSIGNED_VERSION)_$(CONFIGURED_ARCH).deb
$(GRUB_EFI_AMD64)_SRC_PATH = $(SRC_PATH)/grub2-unsigned
$(GRUB_EFI_AMD64)_DEPENDS += $(GRUB2_COMMON)
SONIC_MAKE_DEBS += $(GRUB_EFI_AMD64)

GRUB_EFI_AMD64_BIN = grub-efi-amd64-bin_$(GRUB2_UNSIGNED_VERSION)_$(CONFIGURED_ARCH).deb
$(eval $(call add_derived_package,$(GRUB_EFI_AMD64),$(GRUB_EFI_AMD64_BIN)))
else ifeq ($(CONFIGURED_ARCH),arm64)
GRUB_EFI_ARM64 = grub-efi-arm64_$(GRUB2_UNSIGNED_VERSION)_$(CONFIGURED_ARCH).deb
$(GRUB_EFI_ARM64)_SRC_PATH = $(SRC_PATH)/grub2-unsigned
$(GRUB_EFI_ARM64)_DEPENDS += $(GRUB2_COMMON)
SONIC_MAKE_DEBS += $(GRUB_EFI_ARM64)

GRUB_EFI_ARM64_BIN = grub-efi-arm64-bin_$(GRUB2_UNSIGNED_VERSION)_$(CONFIGURED_ARCH).deb
$(eval $(call add_derived_package,$(GRUB_EFI_ARM64),$(GRUB_EFI_ARM64_BIN)))
endif

# The .c, .cpp, .h & .hpp files under src/{$DBG_SRC_ARCHIVE list}
# are archived into debug one image to facilitate debugging.
#
DBG_SRC_ARCHIVE += openssh
