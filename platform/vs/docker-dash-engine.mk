# docker image for vs gbsyncd

DOCKER_DASH_ENGINE = docker-dash-engine.gz
$(DOCKER_DASH_ENGINE)_VERSION = 1.0.0
$(DOCKER_DASH_ENGINE)_PACKAGE_NAME = dash-engine
$(DOCKER_DASH_ENGINE)_PATH = $(PLATFORM_PATH)/docker-dash-engine

# The p4lang/behavioral-model base image is published for amd64 only
ifeq ($(CONFIGURED_ARCH),amd64)
SONIC_DOCKER_IMAGES += $(DOCKER_DASH_ENGINE)
SONIC_INSTALL_DOCKER_IMAGES += $(DOCKER_DASH_ENGINE)
endif


$(DOCKER_DASH_ENGINE)_CONTAINER_NAME = dash_engine
$(DOCKER_DASH_ENGINE)_CONTAINER_PRIVILEGED = true
$(DOCKER_DASH_ENGINE)_RUN_OPT += --privileged -t

