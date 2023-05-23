# docker image for lldp agent

DOCKER_LLDP_STEM = docker-lldp
DOCKER_LLDP = $(DOCKER_LLDP_STEM).gz
DOCKER_LLDP_DBG = $(DOCKER_LLDP_STEM)-$(DBG_IMAGE_MARK).gz

$(DOCKER_LLDP)_PATH = $(DOCKERS_PATH)/docker-lldp

$(DOCKER_LLDP)_DEPENDS += $(LLDPD) $(LIBSWSSCOMMON) $(PYTHON3_SWSSCOMMON)

$(DOCKER_LLDP)_DBG_DEPENDS = $($(DOCKER_CONFIG_ENGINE_BULLSEYE)_DBG_DEPENDS)
$(DOCKER_LLDP)_DBG_DEPENDS += $(LLDPD_DBG) $(LIBSWSSCOMMON_DBG)

$(DOCKER_LLDP)_DBG_IMAGE_PACKAGES = $($(DOCKER_CONFIG_ENGINE_BULLSEYE)_DBG_IMAGE_PACKAGES)

$(DOCKER_LLDP)_PYTHON_WHEELS += $(DBSYNCD_PY3)
$(DOCKER_LLDP)_LOAD_DOCKERS += $(DOCKER_CONFIG_ENGINE_BULLSEYE)

$(DOCKER_LLDP)_VERSION = 1.0.0
$(DOCKER_LLDP)_PACKAGE_NAME = lldp
$(DOCKER_LLDP)_WARM_SHUTDOWN_BEFORE = swss
$(DOCKER_LLDP)_FAST_SHUTDOWN_BEFORE = swss

SONIC_DOCKER_IMAGES += $(DOCKER_LLDP)
SONIC_INSTALL_DOCKER_IMAGES += $(DOCKER_LLDP)

SONIC_DOCKER_DBG_IMAGES += $(DOCKER_LLDP_DBG)
SONIC_INSTALL_DOCKER_DBG_IMAGES += $(DOCKER_LLDP_DBG)

$(DOCKER_LLDP)_CONTAINER_NAME = lldp
$(DOCKER_LLDP)_RUN_OPT += --privileged -t
$(DOCKER_LLDP)_RUN_OPT += -v /etc/sonic:/etc/sonic:ro
$(DOCKER_LLDP)_RUN_OPT += -v /etc/timezone:/etc/timezone:ro 
$(DOCKER_LLDP)_RUN_OPT += -v /usr/share/sonic/scripts:/usr/share/sonic/scripts:ro

$(DOCKER_LLDP)_BASE_IMAGE_FILES += lldpctl:/usr/bin/lldpctl
$(DOCKER_LLDP)_BASE_IMAGE_FILES += lldpcli:/usr/bin/lldpcli
$(DOCKER_LLDP)_FILES += $(SUPERVISOR_PROC_EXIT_LISTENER_SCRIPT)

SONIC_BULLSEYE_DOCKERS += $(DOCKER_LLDP)
SONIC_BULLSEYE_DBG_DOCKERS += $(DOCKER_LLDP_DBG)
