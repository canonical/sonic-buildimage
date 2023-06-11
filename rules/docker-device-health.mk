# docker image for device-health agent

DOCKER_DEVICE_HEALTH_STEM = docker-device-health
DOCKER_DEVICE_HEALTH = $(DOCKER_DEVICE_HEALTH_STEM).gz
DOCKER_DEVICE_HEALTH_DBG = $(DOCKER_DEVICE_HEALTH_STEM)-$(DBG_IMAGE_MARK).gz

$(DOCKER_DEVICE_HEALTH)_DEPENDS += $(SONIC_DEVICE_HEALTH)

$(DOCKER_DEVICE_HEALTH)_DBG_DEPENDS = $($(DOCKER_CONFIG_ENGINE_BULLSEYE)_DBG_DEPENDS)
$(DOCKER_DEVICE_HEALTH)_DBG_DEPENDS += $(SONIC_DEVICE_HEALTH_DBG) $(LIBSWSSCOMMON_DBG)

$(DOCKER_DEVICE_HEALTH)_DBG_IMAGE_PACKAGES = $($(DOCKER_CONFIG_ENGINE_BULLSEYE)_DBG_IMAGE_PACKAGES)

$(DOCKER_DEVICE_HEALTH)_LOAD_DOCKERS += $(DOCKER_CONFIG_ENGINE_BULLSEYE)

$(DOCKER_DEVICE_HEALTH)_PATH = $(DOCKERS_PATH)/$(DOCKER_DEVICE_HEALTH_STEM)

$(DOCKER_DEVICE_HEALTH)_INSTALL_PYTHON_WHEELS = $(SONIC_UTILITIES_PY3)
$(DOCKER_DEVICE_HEALTH)_INSTALL_DEBS = $(PYTHON3_SWSSCOMMON)

$(DOCKER_DEVICE_HEALTH)_VERSION = 1.0.0
$(DOCKER_DEVICE_HEALTH)_PACKAGE_NAME = device-health

SONIC_DOCKER_IMAGES += $(DOCKER_DEVICE_HEALTH)
ifeq ($(INCLUDE_DEVICE_HEALTH), y)
SONIC_INSTALL_DOCKER_IMAGES += $(DOCKER_DEVICE_HEALTH)
endif

SONIC_DOCKER_DBG_IMAGES += $(DOCKER_DEVICE_HEALTH_DBG)
ifeq ($(INCLUDE_DEVICE_HEALTH), y)
SONIC_INSTALL_DOCKER_DBG_IMAGES += $(DOCKER_DEVICE_HEALTH_DBG)
endif

$(DOCKER_DEVICE_HEALTH)_CONTAINER_NAME = device-health
$(DOCKER_DEVICE_HEALTH)_RUN_OPT += --privileged -t
$(DOCKER_DEVICE_HEALTH)_RUN_OPT += -v /etc/sonic:/etc/sonic:ro
$(DOCKER_DEVICE_HEALTH)_RUN_OPT += -v /usr/share/sonic/scripts:/usr/share/sonic/scripts:ro
$(DOCKER_DEVICE_HEALTH)_RUN_OPT += -v /usr/share/device_health:/usr/share/device_health:rw
$(DOCKER_DEVICE_HEALTH)_RUN_OPT += -v /var/run/dbus:/var/run/dbus:rw

SONIC_BULLSEYE_DOCKERS += $(DOCKER_DEVICE_HEALTH)
SONIC_BULLSEYE_DBG_DOCKERS += $(DOCKER_DEVICE_HEALTH_DBG)
$(DOCKER_DEVICE_HEALTH)_FILES = $(SUPERVISOR_PROC_EXIT_LISTENER_SCRIPT)
