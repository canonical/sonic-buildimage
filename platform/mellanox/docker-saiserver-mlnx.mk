# docker image for mlnx saiserver

DOCKER_SAISERVER_MLNX = docker-saiserver$(SAITHRIFT_VER)-mlnx.gz
$(DOCKER_SAISERVER_MLNX)_PATH = $(PLATFORM_PATH)/docker-saiserver-mlnx
$(DOCKER_SAISERVER_MLNX)_DEPENDS += $(SAISERVER) $(PYTHON_SDK_API)
$(DOCKER_SAISERVER_MLNX)_PYTHON_DEBS += $(MLNX_SFPD)
$(DOCKER_SAISERVER_MLNX)_LOAD_DOCKERS += $(DOCKER_CONFIG_ENGINE_BUSTER)
SONIC_DOCKER_IMAGES += $(DOCKER_SAISERVER_MLNX)
SONIC_BUSTER_DOCKERS += $(DOCKER_SAISERVER_MLNX)

$(DOCKER_SAISERVER_MLNX)_CONTAINER_NAME = saiserver$(SAITHRIFT_VER)

$(DOCKER_SAISERVER_MLNX)_RUN_OPT += --privileged -t
$(DOCKER_SAISERVER_MLNX)_RUN_OPT += -v /host/machine.conf:/etc/machine.conf
$(DOCKER_SAISERVER_MLNX)_RUN_OPT += -v /etc/sonic:/etc/sonic:ro
$(DOCKER_SYNCD_BASE)_RUN_OPT += --tmpfs /run/criu
