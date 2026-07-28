# rules/<pkg>.mk 双模式单测：验证 SONIC_PPA_PACKAGES 是否含该包时，注册到
# 正确的列表、deb 名是否带后缀、每个 deb 的 _URL 是否正确。
# 用法: make -s -f scripts/ppa/tests/rules_test.mk

CONFIGURED_ARCH    := amd64
SRC_PATH           := src
SONIC_MAKE_DEBS    :=
SONIC_ONLINE_DEBS  :=
SONIC_DERIVED_DEBS :=

SONIC_PPA_URL      := https://ppa.launchpadcontent.net/o/n/ubuntu
SONIC_PPA_SUFFIX   := +sonic1~ppa1
# 本次只把 libteam 切到 PPA 模式，用于验证「按包生效」而非全局生效
SONIC_PPA_PACKAGES := libteam

include rules/functions
include rules/libteam.mk
include scripts/ppa/tests/assert.mk

# PPA 模式：注册到 ONLINE 而非 MAKE，且 deb 名带后缀
$(call assert,libteam-online,$(SONIC_ONLINE_DEBS),libteam5_1.31-1build4+sonic1~ppa1_amd64.deb)
$(call assert,libteam-not-make,$(SONIC_MAKE_DEBS),)
$(call assert,libteam-main-name,$(LIBTEAM),libteam5_1.31-1build4+sonic1~ppa1_amd64.deb)
$(call assert,libteam-stock-ver,$(LIBTEAM_VERSION_STOCK),1.31-1build4)

# 派生包数量不变（1 主 + 6 派生）
$(call assert,libteam-derived-count,$(words $(SONIC_DERIVED_DEBS)),6)

# 主包 URL
$(call assert,libteam-main-url,$($(LIBTEAM)_URL),https://ppa.launchpadcontent.net/o/n/ubuntu/pool/main/libt/libteam/libteam5_1.31-1build4+sonic1~ppa1_amd64.deb)

# dbgsym 派生包 URL 必须被覆盖成自己的地址，且扩展名为 .ddeb
# （add_derived_package 默认让它继承主包 URL，rules/functions:94）
$(call assert,libteam-dbg-url,$($(LIBTEAM_DBG)_URL),https://ppa.launchpadcontent.net/o/n/ubuntu/pool/main/libt/libteam/libteam5-dbgsym_1.31-1build4+sonic1~ppa1_amd64.ddeb)

# 非 dbgsym 派生包 URL 保持 .deb
$(call assert,libteam-dev-url,$($(LIBTEAM_DEV)_URL),https://ppa.launchpadcontent.net/o/n/ubuntu/pool/main/libt/libteam/libteam-dev_1.31-1build4+sonic1~ppa1_amd64.deb)

# dsc URL 用 stock 版本，绝不能带 PPA 后缀
$(call assert,libteam-dsc-url,$(LIBTEAM_DSC_URL),http://archive.ubuntu.com/ubuntu/pool/main/libt/libteam/libteam_1.31-1build4.dsc)

.PHONY: default
default:
ifneq ($(strip $(FAILURES)),)
	@echo "FAILED: $(FAILURES)"; exit 1
else
	@echo "rules_test: all assertions passed"
endif
