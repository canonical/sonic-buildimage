# sonic mellanox single image installer

SONIC_SINGLE_IMAGE = sonic-cavium.bin
$(SONIC_SINGLE_IMAGE)_MACHINE = cavium
$(SONIC_SINGLE_IMAGE)_IMAGE_TYPE = onie
$(SONIC_SINGLE_IMAGE)_DEPENDS += $(CAVM_PLATFORM_DEB) 
$(SONIC_SINGLE_IMAGE)_DOCKERS += $(SONIC_INSTALL_DOCKER_IMAGES)
SONIC_INSTALLERS += $(SONIC_SINGLE_IMAGE)
