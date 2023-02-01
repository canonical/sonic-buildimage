# Mellanox BIOS Firmware

ifeq ($(shell [ -f $(PLATFORM_PATH)/bios/msn3800_bios.tar.gz ] && echo yes),yes)
MLNX_SN3800_BIOS_ARCHIVE = msn3800_bios.tar.gz
$(MLNX_SN3800_BIOS_ARCHIVE)_PATH = $(PLATFORM_PATH)/bios/
SONIC_COPY_FILES += $(MLNX_SN3800_BIOS_ARCHIVE)

MLNX_BIOS_ARCHIVES += $(MLNX_SN3800_BIOS_ARCHIVE)
endif

ifdef MLNX_BIOS_ARCHIVES
MLNX_FILES += $(MLNX_BIOS_ARCHIVES)

export MLNX_BIOS_ARCHIVES
endif
