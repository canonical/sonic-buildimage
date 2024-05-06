# libsaithrift-dev package
SAI_VER = 0.9.4

LIBSAITHRIFT_DEV = libsaithrift$(SAITHRIFT_VER)-dev_$(SAI_VER)_$(CONFIGURED_ARCH).deb
$(LIBSAITHRIFT_DEV)_SRC_PATH = $(SRC_PATH)/sonic-sairedis/SAI
ifeq ($(SAITHRIFT_V2),y)
$(LIBSAITHRIFT_DEV)_DEPENDS += $(INVM_LIBSAI) $(INVM_HSAI) $(LIBSAIMETADATA) $(LIBSAIMETADATA_DEV)
$(LIBSAITHRIFT_DEV)_RDEPENDS += $(INVM_HSAI) $(LIBSAIMETADATA)
$(LIBSAITHRIFT_DEV)_BUILD_ENV = SAITHRIFTV2=true SAITHRIFT_VER=v2
else
$(LIBSAITHRIFT_DEV)_DEPENDS += $(INVM_LIBSAI) $(INVM_HSAI)
$(LIBSAITHRIFT_DEV)_RDEPENDS += $(INVM_HSAI)
endif
$(LIBSAITHRIFT_DEV)_DEPENDS += $(LIBSAIMETADATA) $(LIBSAIMETADATA_DEV)
$(LIBSAITHRIFT_DEV)_RDEPENDS += $(LIBSAIMETADATA) $(INVM_LIBSAI) $(INVM_SHELL)

PYTHON_SAITHRIFT = python-saithrift$(SAITHRIFT_VER)_$(SAI_VER)_$(CONFIGURED_ARCH).deb
$(eval $(call add_extra_package,$(LIBSAITHRIFT_DEV),$(PYTHON_SAITHRIFT)))

SONIC_DPKG_DEBS += $(LIBSAITHRIFT_DEV)
