# scripts/ppa/query.mk 自测：以 make -f 真正跑一次 query.mk（不是直接
# include rules/*.mk），确认它在 local 与 ppa 两种模式下都打印全部十个
# key。rules_test.mk 已经直接 include rules/*.mk 逐个校验各 deb 的
# _URL 等具体取值；这里测的是 query.mk 这一层本身——包括它的
# CONFIG_USER_PATH 隔离、include 链是否完整——用同一个包（libteam）在两种
# 模式下对照。
# 用法: make -s -f scripts/ppa/tests/query_test.mk

include scripts/ppa/tests/assert.mk

PKG := libteam

# query_field(mode-env,key) -- runs one query.mk invocation and extracts a
# single key's value. Piping through sed *inside* the same $(shell) call
# lets sed read query.mk's real, newline-separated output and pull out
# exactly the one line we want before $(shell) collapses whatever newlines
# remain in its result into spaces: a plain $(filter KEY=%,$(RAW)) over the
# raw multi-line output would only ever capture DERIVED_DEBS' first word,
# since by the time Make gets to filter over it, DERIVED_DEBS' several deb
# names have already been flattened onto the same "line" as every other
# KEY=value pair.
query_field = $(shell CONFIG_USER_PATH=/dev/null $(1) make -s -f scripts/ppa/query.mk PKG=$(PKG) 2>&1 | sed -n 's/^$(2)=//p')

# A suffix distinct from rules/config's own SONIC_PPA_SUFFIX default
# (+sonic1~ppa1) so the ppa-mode assertions below prove the override is
# actually being read, not just coincidentally matching the default.
PPA_ENV := SONIC_PPA_PACKAGES=$(PKG) SONIC_PPA_URL=https://ppa.launchpadcontent.net/o/n/ubuntu SONIC_PPA_SUFFIX=+sonic9~ppa9

# --- local mode: no SONIC_PPA_* set at all ---
$(call assert,local-pkg,$(call query_field,,PKG),$(PKG))
$(call assert,local-mode,$(call query_field,,MODE),local)
$(call assert,local-stock-version-nonempty,$(if $(call query_field,,STOCK_VERSION),set,),set)
$(call assert,local-dsc-url-nonempty,$(if $(call query_field,,DSC_URL),set,),set)
# SUFFIX is computed unconditionally by query.mk regardless of MODE (it's
# ppa_suffix($(PKG)), not gated on whether $(PKG) is actually in
# SONIC_PPA_PACKAGES) -- so even in local mode it reports rules/config's
# real SONIC_PPA_SUFFIX default, not an empty string.
$(call assert,local-suffix-is-config-default,$(call query_field,,SUFFIX),+sonic1~ppa1)
$(call assert,local-patch-dir,$(call query_field,,PATCH_DIR),src/libteam/patch)
# local mode registers the main deb under SONIC_MAKE_DEBS with no PPA suffix
$(call assert,local-main-deb,$(call query_field,,MAIN_DEB),libteam5_1.31-1build4_amd64.deb)
$(call assert,local-derived-count,$(words $(call query_field,,DERIVED_DEBS)),6)
$(call assert,local-source,$(call query_field,,SOURCE),libteam)
$(call assert,local-ppa-pool-url-empty,$(call query_field,,PPA_POOL_URL),)

# --- ppa mode: SONIC_PPA_PACKAGES includes this package ---
$(call assert,ppa-pkg,$(call query_field,$(PPA_ENV),PKG),$(PKG))
$(call assert,ppa-mode,$(call query_field,$(PPA_ENV),MODE),ppa)
$(call assert,ppa-stock-version-matches-local,$(call query_field,$(PPA_ENV),STOCK_VERSION),$(call query_field,,STOCK_VERSION))
$(call assert,ppa-dsc-url-matches-local,$(call query_field,$(PPA_ENV),DSC_URL),$(call query_field,,DSC_URL))
$(call assert,ppa-suffix-honors-override,$(call query_field,$(PPA_ENV),SUFFIX),+sonic9~ppa9)
$(call assert,ppa-patch-dir-matches-local,$(call query_field,$(PPA_ENV),PATCH_DIR),$(call query_field,,PATCH_DIR))
# ppa mode registers the main deb under SONIC_ONLINE_DEBS with the suffix appended
$(call assert,ppa-main-deb,$(call query_field,$(PPA_ENV),MAIN_DEB),libteam5_1.31-1build4+sonic9~ppa9_amd64.deb)
# same derived-deb count as local mode; the sed-based extraction above must
# still capture all 6 words, not just the first, to make this pass
$(call assert,ppa-derived-count,$(words $(call query_field,$(PPA_ENV),DERIVED_DEBS)),6)
$(call assert,ppa-derived-all-suffixed,$(words $(filter %+sonic9~ppa9_amd64.deb,$(call query_field,$(PPA_ENV),DERIVED_DEBS))),6)
$(call assert,ppa-source-matches-local,$(call query_field,$(PPA_ENV),SOURCE),$(call query_field,,SOURCE))
$(call assert,ppa-pool-url-nonempty,$(if $(call query_field,$(PPA_ENV),PPA_POOL_URL),set,),set)

.PHONY: default
default:
ifneq ($(strip $(FAILURES)),)
	@echo "FAILED: $(FAILURES)"; exit 1
else
	@echo "query_test: all assertions passed"
endif
