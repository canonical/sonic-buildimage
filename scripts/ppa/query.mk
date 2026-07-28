# 在最小 stub 上下文里 include rules/<pkg>.mk，把 PPA 相关事实以 key=value 打印。
# scripts/ppa/*.sh 与 scripts/ppa/tests/* 共用本文件，使这些信息只有
# rules/*.mk 一个来源，不需要平行的 manifest。
#
# 用法：make -s -f scripts/ppa/query.mk PKG=libteam
#
# 刻意不 include slave.mk —— 本文件必须能在无 docker、未 make configure 的
# 裸仓库里直接运行。

PKG ?=
ifeq ($(PKG),)
$(error PKG is required, e.g. make -s -f scripts/ppa/query.mk PKG=libteam)
endif

# rules/<pkg>.mk 期望的最小上下文
CONFIGURED_ARCH    ?= amd64
SRC_PATH           := src
SONIC_MAKE_DEBS    :=
SONIC_ONLINE_DEBS  :=
SONIC_DERIVED_DEBS :=

include rules/config
-include rules/config.user
include rules/functions
include rules/$(PKG).mk

# 包目录名 → make 变量前缀
PREFIX     := $(shell echo $(PKG) | tr 'a-z-' 'A-Z_')

# 主 deb 取自两个注册列表中非空的那个。这样无需为每个包约定「主 deb 变量叫
# 什么」—— isc-dhcp 的是 ISC_DHCP_RELAY，并不等于 PREFIX。
MAIN_DEB   := $(strip $(SONIC_MAKE_DEBS) $(SONIC_ONLINE_DEBS))
MODE       := $(if $(filter $(PKG),$(SONIC_PPA_PACKAGES)),ppa,local)

# 含 series 的补丁目录。多于一个即为歧义，报错而不猜。
PATCH_DIRS := $(patsubst %/series,%,$(wildcard src/$(PKG)/*/series))

# Debian 源码包名：dsc URL basename 里 `_` 之前那段
SOURCE     := $(firstword $(subst _, ,$(notdir $($(PREFIX)_DSC_URL))))

# 该源码包在 PPA pool 里的目录 URL。SONIC_PPA_URL 为空时整串为空，脚本据此
# 判断「无法确定 orig 是否已上传」。集中在此，避免脚本用 sed 重推一遍。
PPA_POOL_URL := $(if $(SONIC_PPA_URL),$(SONIC_PPA_URL)/pool/main/$(call ppa_pool_dir,$(SOURCE))/$(SOURCE))

ifneq ($(words $(MAIN_DEB)),1)
$(error $(PKG): expected exactly 1 main deb, got "$(MAIN_DEB)")
endif
ifneq ($(words $(PATCH_DIRS)),1)
$(error $(PKG): expected exactly 1 patch dir containing a series file, got "$(PATCH_DIRS)")
endif

.PHONY: default
default:
	@echo 'PKG=$(PKG)'
	@echo 'MODE=$(MODE)'
	@echo 'STOCK_VERSION=$($(PREFIX)_VERSION_STOCK)'
	@echo 'DSC_URL=$($(PREFIX)_DSC_URL)'
	@echo 'SUFFIX=$(call ppa_suffix,$(PKG))'
	@echo 'PATCH_DIR=$(PATCH_DIRS)'
	@echo 'MAIN_DEB=$(MAIN_DEB)'
	@echo 'DERIVED_DEBS=$(SONIC_DERIVED_DEBS)'
	@echo 'SOURCE=$(SOURCE)'
	@echo 'PPA_POOL_URL=$(PPA_POOL_URL)'
