# sonic generic ONIE image installer

SONIC_GENERIC_ONIE_IMAGE = sonic-generic.bin
$(SONIC_GENERIC_ONIE_IMAGE)_DEPENDS += $(SYSTEMD_SONIC_GENERATOR)
$(SONIC_GENERIC_ONIE_IMAGE)_MACHINE = generic
$(SONIC_GENERIC_ONIE_IMAGE)_IMAGE_TYPE = onie
$(SONIC_GENERIC_ONIE_IMAGE)_INSTALLS =
$(SONIC_GENERIC_ONIE_IMAGE)_DOCKERS =
SONIC_INSTALLERS += $(SONIC_GENERIC_ONIE_IMAGE)
