# docker image for rest-api

DOCKER_RESTAPI_STEM = docker-sonic-restapi
DOCKER_RESTAPI = $(DOCKER_RESTAPI_STEM).gz

$(DOCKER_RESTAPI)_DEPENDS += $(LIBHIREDIS) $(LIBNL3) $(LIBNL_GENL3) \
                             $(LIBNL_ROUTE3) $(LIBSWSSCOMMON) $(RESTAPI)

$(DOCKER_RESTAPI)_PATH = $(DOCKERS_PATH)/$(DOCKER_RESTAPI_STEM)

$(DOCKER_RESTAPI)_LOAD_DOCKERS += $(DOCKER_CONFIG_ENGINE_BULLSEYE)

$(DOCKER_RESTAPI)_VERSION = 1.0.0
$(DOCKER_RESTAPI)_PACKAGE_NAME = restapi

ifeq ($(INCLUDE_RESTAPI), y)
SONIC_DOCKER_IMAGES += $(DOCKER_RESTAPI)
SONIC_INSTALL_DOCKER_IMAGES += $(DOCKER_RESTAPI)
endif

$(DOCKER_RESTAPI)_CONTAINER_NAME = restapi
$(DOCKER_RESTAPI)_RUN_OPT += -t
$(DOCKER_RESTAPI)_RUN_OPT += -v /var/run/redis/redis.sock:/var/run/redis/redis.sock
$(DOCKER_RESTAPI)_RUN_OPT += -v /etc/sonic/credentials:/etc/sonic/credentials:ro
$(DOCKER_RESTAPI)_RUN_OPT += -p=8081:8081/tcp

$(DOCKER_RESTAPI)_FILES += $(SUPERVISOR_PROC_EXIT_LISTENER_SCRIPT)
