# sonic centec one image installer

SONIC_ONE_IMAGE = sonic-centec.bin
$(SONIC_ONE_IMAGE)_DEPENDS = $(SYSTEMD_SONIC_GENERATOR)
$(SONIC_ONE_IMAGE)_MACHINE = centec
$(SONIC_ONE_IMAGE)_IMAGE_TYPE = onie
$(SONIC_ONE_IMAGE)_LAZY_INSTALLS += $(CENTEC_E582_48X6Q_PLATFORM_MODULE) \
                                    $(CENTEC_E582_48X2Q4Z_PLATFORM_MODULE)
ifeq ($(INSTALL_DEBUG_TOOLS),y)
$(SONIC_ONE_IMAGE)_DOCKERS += $(SONIC_INSTALL_DOCKER_DBG_IMAGES)
$(SONIC_ONE_IMAGE)_DOCKERS += $(filter-out $(patsubst %-$(DBG_IMAGE_MARK).gz,%.gz, $(SONIC_INSTALL_DOCKER_DBG_IMAGES)), $(SONIC_INSTALL_DOCKER_IMAGES))
else
$(SONIC_ONE_IMAGE)_DOCKERS = $(SONIC_INSTALL_DOCKER_IMAGES)
endif
SONIC_INSTALLERS += $(SONIC_ONE_IMAGE)
