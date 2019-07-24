# sonic mellanox one image installer

SONIC_ONE_IMAGE = sonic-mellanox.bin
$(SONIC_ONE_IMAGE)_DEPENDS += $(SYSTEMD_SONIC_GENERATOR)
$(SONIC_ONE_IMAGE)_MACHINE = mellanox
$(SONIC_ONE_IMAGE)_IMAGE_TYPE = onie
$(SONIC_ONE_IMAGE)_INSTALLS += $(SX_KERNEL) $(KERNEL_MFT) $(MFT_OEM) $(MFT) $(MLNX_HW_MANAGEMENT)
ifeq ($(INSTALL_DEBUG_TOOLS),y)
$(SONIC_ONE_IMAGE)_DOCKERS += $(SONIC_INSTALL_DOCKER_DBG_IMAGES)
$(SONIC_ONE_IMAGE)_DOCKERS += $(filter-out $(patsubst %-$(DBG_IMAGE_MARK).gz,%.gz, $(SONIC_INSTALL_DOCKER_DBG_IMAGES)), $(SONIC_INSTALL_DOCKER_IMAGES))
else
$(SONIC_ONE_IMAGE)_DOCKERS = $(SONIC_INSTALL_DOCKER_IMAGES)
endif
$(SONIC_ONE_IMAGE)_FILES += $(MLNX_SPC_FW_FILE) $(MLNX_SPC2_FW_FILE) $(MLNX_FFB_SCRIPT) $(ISSU_VERSION_FILE)
SONIC_INSTALLERS += $(SONIC_ONE_IMAGE)
