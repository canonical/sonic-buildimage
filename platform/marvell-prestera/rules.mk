include $(PLATFORM_PATH)/sai.mk
include $(PLATFORM_PATH)/docker-syncd-mrvl-prestera.mk
include $(PLATFORM_PATH)/docker-syncd-mrvl-prestera-rpc.mk
include $(PLATFORM_PATH)/docker-saiserver-mrvl-prestera.mk
include $(PLATFORM_PATH)/libsaithrift-dev.mk
include $(PLATFORM_PATH)/one-image.mk
ifeq ($(CONFIGURED_ARCH),arm64)
# Resolute arm64 supports only the Asterfusion CX204Y, which boots through GRUB
override TARGET_BOOTLOADER = grub
include $(PLATFORM_PATH)/mrvl-prestera.mk
include $(PLATFORM_PATH)/platform-asterfusion.mk
else
include $(PLATFORM_PATH)/platform-marvell.mk
ifeq ($(CONFIGURED_ARCH),armhf)
include $(PLATFORM_PATH)/mrvl-prestera.mk
include $(PLATFORM_PATH)/platform-nokia.mk
endif
endif

SONIC_ALL += $(SONIC_ONE_IMAGE) \
             $(DOCKER_FPM) 	\
             $(DOCKER_SYNCD_MRVL_RPC)

# Inject mrvl-prestera sai into syncd
$(SYNCD)_DEPENDS += $(MRVL_SAI)
$(SYNCD)_UNINSTALLS += $(MRVL_SAI)

ifeq ($(ENABLE_SYNCD_RPC),y)
$(SYNCD)_DEPENDS := $(filter-out $(LIBTHRIFT_DEV),$($(SYNCD)_DEPENDS))
$(SYNCD)_DEPENDS += $(LIBSAITHRIFT_DEV)
endif

# Runtime dependency on mrvl-prestera sai is set only for syncd
$(SYNCD)_RDEPENDS += $(MRVL_SAI)
