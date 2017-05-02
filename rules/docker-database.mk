# docker image for database

DOCKER_DATABASE = docker-database.gz
$(DOCKER_DATABASE)_PATH = $(DOCKERS_PATH)/docker-database
$(DOCKER_DATABASE)_DEPENDS += $(REDIS_SERVER) $(REDIS_TOOLS)
$(DOCKER_DATABASE)_LOAD_DOCKERS += $(DOCKER_BASE)
SONIC_DOCKER_IMAGES += $(DOCKER_DATABASE)
SONIC_INSTALL_DOCKER_IMAGES += $(DOCKER_DATABASE)

$(DOCKER_DATABASE)_CONTAINER_NAME = database
$(DOCKER_DATABASE)_RUN_OPT += --net=host --privileged -t --log-driver=syslog --log-opt=tag="{{.ID}}({{.Name}})"

$(DOCKER_DATABASE)_BASE_IMAGE_FILES += redis-cli:/usr/bin/redis-cli
