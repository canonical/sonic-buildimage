# Mellanox HW Management

MLNX_HW_MANAGEMENT_VERSION = V1.0.0190

export MLNX_HW_MANAGEMENT_VERSION

MLNX_HW_MANAGEMENT = hw-management_1.mlnx.$(MLNX_HW_MANAGEMENT_VERSION)_amd64.deb
$(MLNX_HW_MANAGEMENT)_SRC_PATH = $(PLATFORM_PATH)/hw-management
$(MLNX_HW_MANAGEMENT)_DEPENDS += $(LINUX_HEADERS) $(LINUX_HEADERS_COMMON)
SONIC_MAKE_DEBS += $(MLNX_HW_MANAGEMENT)
