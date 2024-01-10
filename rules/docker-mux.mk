# Docker image for MUX

DOCKER_MUX_STEM = docker-mux
DOCKER_MUX = $(DOCKER_MUX_STEM).gz
DOCKER_MUX_DBG = $(DOCKER_MUX_STEM)-$(DBG_IMAGE_MARK).gz

$(DOCKER_MUX)_PATH = $(DOCKERS_PATH)/$(DOCKER_MUX_STEM)

$(DOCKER_MUX)_DEPENDS = $(SONIC_LINKMGRD) $(LIBSWSSCOMMON)
$(DOCKER_MUX)_DBG_DEPENDS = $($(DOCKER_CONFIG_ENGINE_BULLSEYE)_DBG_DEPENDS)
$(DOCKER_MUX)_DBG_DEPENDS += $(SONIC_LINKMGRD_DBG) $(LIBSWSSCOMMON_DBG)

$(DOCKER_MUX)_DBG_IMAGE_PACKAGES = $($(DOCKER_CONFIG_ENGINE_BULLSEYE)_DBG_IMAGE_PACKAGES)

$(DOCKER_MUX)_LOAD_DOCKERS = $(DOCKER_CONFIG_ENGINE_BULLSEYE)

$(DOCKER_MUX)_VERSION = 1.0.0
$(DOCKER_MUX)_PACKAGE_NAME = mux
$(DOCKER_MUX)_WARM_SHUTDOWN_BEFORE = swss
$(DOCKER_MUX)_FAST_SHUTDOWN_BEFORE = swss

ifeq ($(INCLUDE_MUX), y)
SONIC_DOCKER_IMAGES += $(DOCKER_MUX)
SONIC_INSTALL_DOCKER_IMAGES += $(DOCKER_MUX)
endif

ifeq ($(INCLUDE_MUX), y)
SONIC_DOCKER_DBG_IMAGES += $(DOCKER_MUX_DBG)
SONIC_INSTALL_DOCKER_DBG_IMAGES += $(DOCKER_MUX_DBG)
endif

SONIC_BULLSEYE_DOCKERS += $(DOCKER_MUX)
SONIC_BULLSEYE_DBG_DOCKERS += $(DOCKER_MUX_DBG)

$(DOCKER_MUX)_CONTAINER_NAME = mux
$(DOCKER_MUX)_RUN_OPT += -t
$(DOCKER_MUX)_RUN_OPT += -v /etc/sonic:/etc/sonic:ro
$(DOCKER_MUX)_RUN_OPT += -v /etc/timezone:/etc/timezone:ro 
$(DOCKER_MUX)_FILES += $(SUPERVISOR_PROC_EXIT_LISTENER_SCRIPT)
