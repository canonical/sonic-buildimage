# docker image for telemetry agent

DOCKER_TELEMETRY_STEM = docker-sonic-telemetry
DOCKER_TELEMETRY = $(DOCKER_TELEMETRY_STEM).gz
DOCKER_TELEMETRY_DBG = $(DOCKER_TELEMETRY_STEM)-$(DBG_IMAGE_MARK).gz

$(DOCKER_TELEMETRY)_PATH = $(DOCKERS_PATH)/$(DOCKER_TELEMETRY_STEM)

$(DOCKER_TELEMETRY)_DEPENDS += $(SONIC_MGMT_COMMON)
$(DOCKER_TELEMETRY)_DEPENDS += $(SONIC_TELEMETRY)
$(DOCKER_TELEMETRY)_DBG_DEPENDS = $($(DOCKER_CONFIG_ENGINE_BULLSEYE)_DBG_DEPENDS)

$(DOCKER_TELEMETRY)_LOAD_DOCKERS += $(DOCKER_CONFIG_ENGINE_BULLSEYE)

$(DOCKER_TELEMETRY)_VERSION = 1.0.0
$(DOCKER_TELEMETRY)_PACKAGE_NAME = telemetry

$(DOCKER_TELEMETRY)_DBG_IMAGE_PACKAGES = $($(DOCKER_CONFIG_ENGINE_BULLSEYE)_DBG_IMAGE_PACKAGES)

SONIC_DOCKER_IMAGES += $(DOCKER_TELEMETRY)
ifeq ($(INCLUDE_SYSTEM_TELEMETRY), y)
SONIC_INSTALL_DOCKER_IMAGES += $(DOCKER_TELEMETRY)
endif

SONIC_DOCKER_DBG_IMAGES += $(DOCKER_TELEMETRY_DBG)
ifeq ($(INCLUDE_SYSTEM_TELEMETRY), y)
SONIC_INSTALL_DOCKER_DBG_IMAGES += $(DOCKER_TELEMETRY_DBG)
endif

$(DOCKER_TELEMETRY)_CONTAINER_NAME = telemetry
$(DOCKER_TELEMETRY)_RUN_OPT += --privileged -t
$(DOCKER_TELEMETRY)_RUN_OPT += -v /etc/sonic:/etc/sonic:ro
$(DOCKER_TELEMETRY)_RUN_OPT += -v /usr/share/sonic/scripts:/usr/share/sonic/scripts:ro
$(DOCKER_TELEMETRY)_RUN_OPT += -v /etc:/host_etc:ro
$(DOCKER_TELEMETRY)_RUN_OPT += --mount type=bind,source="/var/platform/",target="/mnt/platform/"
ifneq ($(INCLUDE_SYSTEM_GNMI), y)
$(DOCKER_TELEMETRY)_RUN_OPT += -v /var/run/dbus:/var/run/dbus:rw
endif
>>>>>>> upstream/master

$(DOCKER_TELEMETRY)_FILES += $(SUPERVISOR_PROC_EXIT_LISTENER_SCRIPT)
$(DOCKER_TELEMETRY)_BASE_IMAGE_FILES += monit_telemetry:/etc/monit/conf.d
