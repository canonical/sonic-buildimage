# docker image for ptf

DOCKER_PTF = docker-ptf.gz
$(DOCKER_PTF)_PATH = $(DOCKERS_PATH)/docker-ptf
$(DOCKER_PTF)_DEPENDS += $(LIBTHRIFT) $(PYTHON_THRIFT) $(PTF) $(SWSS) $(LIBTEAMDCT) $(LIBTEAM_UTILS)
SONIC_DOCKER_IMAGES += $(DOCKER_PTF)
