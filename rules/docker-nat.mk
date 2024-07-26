# docker image for nat

DOCKER_NAT_STEM = docker-nat
DOCKER_NAT = $(DOCKER_NAT_STEM).gz
DOCKER_NAT_DBG = $(DOCKER_NAT_STEM)-$(DBG_IMAGE_MARK).gz

$(DOCKER_NAT)_PATH = $(DOCKERS_PATH)/$(DOCKER_NAT_STEM)

$(DOCKER_NAT)_DEPENDS += $(SWSS) $(IPTABLESIP4TC) $(IPTABLESIP6TC) $(IPTABLESIPTC) $(IPXTABLES12) $(IPTABLES)
$(DOCKER_NAT)_DBG_DEPENDS = $($(DOCKER_SWSS_LAYER_NOBLE)_DBG_DEPENDS)
$(DOCKER_NAT)_DBG_DEPENDS += $(SWSS_DBG) $(LIBSWSSCOMMON_DBG)
$(DOCKER_NAT)_DBG_IMAGE_PACKAGES = $($(DOCKER_SWSS_LAYER_NOBLE)_DBG_IMAGE_PACKAGES)

$(DOCKER_NAT)_LOAD_DOCKERS += $(DOCKER_SWSS_LAYER_NOBLE)

$(DOCKER_NAT)_VERSION = 1.0.0
$(DOCKER_NAT)_PACKAGE_NAME = nat
$(DOCKER_NAT)_WARM_SHUTDOWN_BEFORE = swss
$(DOCKER_NAT)_FAST_SHUTDOWN_BEFORE = swss

ifeq ($(INCLUDE_NAT), y)
SONIC_DOCKER_IMAGES += $(DOCKER_NAT)
SONIC_INSTALL_DOCKER_IMAGES += $(DOCKER_NAT)
endif

ifeq ($(INCLUDE_NAT), y)
SONIC_DOCKER_DBG_IMAGES += $(DOCKER_NAT_DBG)
SONIC_INSTALL_DOCKER_DBG_IMAGES += $(DOCKER_NAT_DBG)
endif

$(DOCKER_NAT)_CONTAINER_NAME = nat
$(DOCKER_NAT)_RUN_OPT += -t --cap-add=NET_ADMIN
$(DOCKER_NAT)_RUN_OPT += -v /etc/sonic:/etc/sonic:ro
$(DOCKER_NAT)_RUN_OPT += -v /etc/timezone:/etc/timezone:ro 
$(DOCKER_NAT)_RUN_OPT += -v /host/warmboot:/var/warmboot

$(DOCKER_NAT)_FILES += $(SUPERVISOR_PROC_EXIT_LISTENER_SCRIPT)

$(DOCKER_NAT)_BASE_IMAGE_FILES += natctl:/usr/bin/natctl

SONIC_NOBLE_DOCKERS += $(DOCKER_NAT)
SONIC_NOBLE_DBG_DOCKERS += $(DOCKER_NAT_DBG)
