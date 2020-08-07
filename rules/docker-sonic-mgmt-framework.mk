# docker image for mgmt-framework

DOCKER_MGMT_FRAMEWORK_STEM = docker-sonic-mgmt-framework
DOCKER_MGMT_FRAMEWORK = $(DOCKER_MGMT_FRAMEWORK_STEM).gz
DOCKER_MGMT_FRAMEWORK_DBG = $(DOCKER_MGMT_FRAMEWORK_STEM)-$(DBG_IMAGE_MARK).gz

$(DOCKER_MGMT_FRAMEWORK)_PATH = $(DOCKERS_PATH)/$(DOCKER_MGMT_FRAMEWORK_STEM)

$(DOCKER_MGMT_FRAMEWORK)_DEPENDS += $(SONIC_MGMT_COMMON)
$(DOCKER_MGMT_FRAMEWORK)_DEPENDS += $(SONIC_MGMT_FRAMEWORK)
$(DOCKER_MGMT_FRAMEWORK)_DBG_DEPENDS = $($(DOCKER_CONFIG_ENGINE_BUSTER)_DBG_DEPENDS)
$(DOCKER_MGMT_FRAMEWORK)_DBG_DEPENDS += $(SONIC_MGMT_FRAMEWORK_DBG)

SONIC_DOCKER_IMAGES += $(DOCKER_MGMT_FRAMEWORK)
$(DOCKER_MGMT_FRAMEWORK)_LOAD_DOCKERS += $(DOCKER_CONFIG_ENGINE_BUSTER)
$(DOCKER_MGMT_FRAMEWORK)_DBG_IMAGE_PACKAGES = $($(DOCKER_CONFIG_ENGINE_BUSTER)_DBG_IMAGE_PACKAGES)

ifeq ($(INCLUDE_MGMT_FRAMEWORK), y)
SONIC_INSTALL_DOCKER_IMAGES += $(DOCKER_MGMT_FRAMEWORK)
endif

SONIC_DOCKER_DBG_IMAGES += $(DOCKER_MGMT_FRAMEWORK_DBG)
ifeq ($(INCLUDE_MGMT_FRAMEWORK), y)
SONIC_INSTALL_DOCKER_DBG_IMAGES += $(DOCKER_MGMT_FRAMEWORK_DBG)
endif

$(DOCKER_MGMT_FRAMEWORK)_CONTAINER_NAME = mgmt-framework
$(DOCKER_MGMT_FRAMEWORK)_RUN_OPT += --privileged -t
$(DOCKER_MGMT_FRAMEWORK)_RUN_OPT += -v /etc/sonic:/etc/sonic:ro
$(DOCKER_MGMT_FRAMEWORK)_RUN_OPT += -v /etc:/host_etc:ro
$(DOCKER_MGMT_FRAMEWORK)_RUN_OPT += --mount type=bind,source="/var/platform/",target="/mnt/platform/"

$(DOCKER_MGMT_FRAMEWORK)_BASE_IMAGE_FILES += sonic-cli:/usr/bin/sonic-cli
