# jammy-based docker image for sonic swss layer

DOCKER_SWSS_LAYER_JAMMY= docker-swss-layer-jammy.gz
$(DOCKER_SWSS_LAYER_JAMMY)_PATH = $(DOCKERS_PATH)/docker-swss-layer-jammy

$(DOCKER_SWSS_LAYER_JAMMY)_DEPENDS += $(SWSS)
$(DOCKER_SWSS_LAYER_JAMMY)_LOAD_DOCKERS += $(DOCKER_CONFIG_ENGINE_JAMMY)

$(DOCKER_SWSS_LAYER_JAMMY)_DBG_DEPENDS = $($(DOCKER_CONFIG_ENGINE_JAMMY)_DBG_DEPENDS) \
                                             $(SWSS_DBG)
$(DOCKER_SWSS_LAYER_JAMMY)_DBG_IMAGE_PACKAGES = $($(DOCKER_CONFIG_ENGINE_JAMMY)_DBG_IMAGE_PACKAGES)

SONIC_DOCKER_IMAGES += $(DOCKER_SWSS_LAYER_JAMMY)
SONIC_JAMMY_DOCKERS += $(DOCKER_SWSS_LAYER_JAMMY)
