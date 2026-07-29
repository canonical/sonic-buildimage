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
BLDENV             ?= resolute
SRC_PATH           := src
SONIC_MAKE_DEBS    :=
SONIC_ONLINE_DEBS  :=
SONIC_DERIVED_DEBS :=

include rules/config
# CONFIG_USER_PATH indirection: lets callers that need a hermetic run (see
# scripts/ppa/tests/manifest_test.sh) point this at /dev/null instead of a
# developer's real rules/config.user, which -include's with a plain `=` and
# so would otherwise beat both this variable's own `?=` default and any
# SONIC_PPA_* value the caller passed in via the environment.
CONFIG_USER_PATH ?= rules/config.user
-include $(CONFIG_USER_PATH)
include rules/functions
include rules/ppa-functions
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

# add_derived_package (rules/functions:94) gives a derived deb a $(2)_URL that
# references its main deb's $(1)_URL -- but $(call ...) fully expands that
# reference at the moment add_derived_package is invoked, which in every
# rules/<pkg>.mk is BEFORE the ppa-mode block further down the file has set
# the main deb's own _URL. So a derived deb that never gets its own _URL
# override afterwards (see rules/libteam.mk's and rules/isc-dhcp.mk's
# comments on that ordering requirement) does not end up quietly inheriting
# the main deb's URL -- it ends up with an empty one, downloading nothing.
# The two checks below catch that (a missing override -> fewer non-empty
# URLs than debs) and its opposite mistake, a copy-pasted ppa_url call that
# names the wrong deb (two debs resolving to the identical URL -- $(sort ...)
# both sorts and deduplicates, so comparing word counts before/after it
# catches any repeated value). Only meaningful in ppa mode: in local mode
# none of these debs have a _URL at all, so every word would be "empty" and
# check (a) would fire for every package.
ifeq ($(MODE),ppa)
ALL_DEBS := $(MAIN_DEB) $(SONIC_DERIVED_DEBS)
ALL_URLS := $(foreach d,$(ALL_DEBS),$($(d)_URL))
ifneq ($(words $(ALL_URLS)),$(words $(ALL_DEBS)))
$(error $(PKG): $(words $(ALL_DEBS)) deb(s) registered ($(ALL_DEBS)) but only $(words $(ALL_URLS)) have a non-empty _URL in ppa mode -- one of them is missing its own _URL override after add_derived_package and its URL silently came out empty instead)
endif
ifneq ($(words $(sort $(ALL_URLS))),$(words $(ALL_URLS)))
$(error $(PKG): two or more of $(ALL_DEBS) resolve to the identical _URL in ppa mode -- check for a copy-pasted ppa_url call that names the wrong deb)
endif
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
