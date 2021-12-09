# sonic one aboot installer

SONIC_ONE_ABOOT_IMAGE = sonic-aboot-barefoot.swi
$(SONIC_ONE_ABOOT_IMAGE)_MACHINE = barefoot
$(SONIC_ONE_ABOOT_IMAGE)_IMAGE_TYPE = aboot
$(SONIC_ONE_ABOOT_IMAGE)_INSTALLS += $(BFN_MODULE)
$(SONIC_ONE_ABOOT_IMAGE)_INSTALLS += $(FLASHROM)
$(SONIC_ONE_ABOOT_IMAGE)_INSTALLS += $(SYSTEMD_SONIC_GENERATOR)
$(SONIC_ONE_ABOOT_IMAGE)_LAZY_INSTALLS += $(BFN_PLATFORM_MODULE)
$(SONIC_ONE_ABOOT_IMAGE)_LAZY_INSTALLS += $(BFN_MONTARA_PLATFORM_MODULE)
$(SONIC_ONE_ABOOT_IMAGE)_INSTALLS += $(ARISTA_PLATFORM_MODULE_PYTHON3) \
                                     $(ARISTA_PLATFORM_MODULE_DRIVERS) \
                                     $(ARISTA_PLATFORM_MODULE_LIBS) \
                                     $(ARISTA_PLATFORM_MODULE)
ifeq ($(INSTALL_DEBUG_TOOLS),y)
$(SONIC_ONE_ABOOT_IMAGE)_DOCKERS += $(SONIC_INSTALL_DOCKER_DBG_IMAGES)
$(SONIC_ONE_ABOOT_IMAGE)_DOCKERS += $(filter-out $(patsubst %-$(DBG_IMAGE_MARK).gz,%.gz, $(SONIC_INSTALL_DOCKER_DBG_IMAGES)), $(SONIC_INSTALL_DOCKER_IMAGES))
else
$(SONIC_ONE_ABOOT_IMAGE)_DOCKERS += $(SONIC_INSTALL_DOCKER_IMAGES)
endif
SONIC_INSTALLERS += $(SONIC_ONE_ABOOT_IMAGE)
