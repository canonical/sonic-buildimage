# libpython3.11 stand-in, used with vendor SAI builds selected by MRVL_SAI_ASSETS_BASE_URL

MRVL_SAI_PYSTUB = mrvl-sai-pystub_1.0_$(CONFIGURED_ARCH).deb
$(MRVL_SAI_PYSTUB)_SRC_PATH = $(PLATFORM_PATH)/mrvl-sai-pystub
SONIC_DPKG_DEBS += $(MRVL_SAI_PYSTUB)
