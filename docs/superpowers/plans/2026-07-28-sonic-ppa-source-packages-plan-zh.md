# PPA 源码包脚手架 实现计划

> **给执行者：** 必需子技能：用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现本计划。步骤用 checkbox（`- [ ]`）语法跟踪。

**目标：** 在 `sonic-buildimage` 内搭出「打包配方留在树里、预编译产物从 Launchpad PPA 拉取」的双模式脚手架，并打通首批三个包（`libteam` / `isc-dhcp` / `lm-sensors`）到「源码包可在干净 chroot 中构建」。

**架构：** `rules/config` 三个开关决定每个包走 PPA 还是本地自建；`rules/functions` 五个函数把版本后缀与 PPA pool URL 的推导集中掉；`rules/<pkg>.mk` 只做纯插入式的模式分支。`scripts/ppa/query.mk` 在最小 stub 上下文里 include `rules/<pkg>.mk` 并输出 key=value，成为脚本与单测的唯一事实来源。源码包生成在 slave 容器内完成且不签名，签名与上传在宿主机。

**技术栈：** GNU Make（条件、`$(call)` 函数）、Bash、`devscripts`（`dget` / `dch` / `debsign` / `dpkg-buildpackage -S`）、`quilt` 补丁格式、一次性 `ubuntu:resolute` docker 容器（干净构建环境）、`dput`。宿主机侧只用已装好的 `debsign` 与 `dput`，**全程无需 sudo、不动宿主机**。

**设计文档：** [2026-07-28 PPA 源码包设计](../specs/2026-07-28-sonic-ppa-source-packages-design-zh.md)

**工作区：** 实现在自 `202605_resolute_sheldon` 派生的 worktree 分支上进行（执行时用 superpowers:using-git-worktrees 创建）。本计划文档本身在 `202605_resolute_doc`。

---

## 全局约束

- **只对 `BLDENV=resolute` 生效。** `SONIC_PPA_PACKAGES` 默认为空；为空时构建行为与引入本机制之前完全一致。不改 `trixie` / `bookworm` / `bullseye` 的任何行为。
- **纯插入优先，禁止重排缩进。** 本仓库需反复 rebase 到 `sonic-net/202605`（且已经历一次上游 force-rewrite）。改动 `rules/*.mk` / `rules/*.dep` / `src/*/Makefile` 时，只允许插入新行与修改必须修改的那一行；不得为了让内容落进 `ifneq` 块而给已有行加缩进。
- **每个包只新增两个变量**：`<PREFIX>_VERSION_STOCK`（不含 PPA 后缀的上游版本）与 `<PREFIX>_DSC_URL`（官方 `.dsc` 地址）。`<PREFIX>` = 包目录名经 `tr 'a-z-' 'A-Z_'`：`libteam`→`LIBTEAM`、`isc-dhcp`→`ISC_DHCP`、`lm-sensors`→`LM_SENSORS`。两者都必须 `export`。
- **`ppa_*` 函数不可用于 `rules/sonic-fips.mk`。** `rules/functions` 只被 `slave.mk:289` include；而 `Makefile.work:155` 会在**没有** `rules/functions` 的宿主机上下文里 include `rules/sonic-fips.mk`。本批次不涉及该文件，但后续批次必须遵守。
- **版本号** = `<stock 版本><后缀>`，后缀默认 `+sonic1~ppa1`。单包重传用 `SONIC_PPA_SUFFIX_<pkg>` 提到 `~ppa2`。已上传过的版本号不可重用，Launchpad 会 reject。
- **签名与上传只在宿主机。** 容器内产出的一律是未签名源码包（`-us -uc`）。
- **dbgsym**：URL 一侧用 `.ddeb`，make 目标名与落盘名保持 `.deb`。依据是 `slave.mk:761` 的 `curl -L -f -o <本地名> <URL>` 允许两者不同名。
- **提交必须 GPG 签名**（本仓库 `commit.gpgsign=true`），commit message 末尾加 `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`。
- **`scripts/ppa/query.mk` 不得 include `slave.mk`。** 它必须能在无 docker、未 `make configure` 的裸仓库里直接运行。

---

## 文件结构

| 文件 | 职责 |
|---|---|
| `rules/config` | 三个全局开关（`SONIC_PPA_PACKAGES` / `SONIC_PPA_URL` / `SONIC_PPA_SUFFIX`）。修改，不新建。 |
| `rules/functions` | 五个 `ppa_*` 推导函数。修改，不新建。 |
| `scripts/ppa/query.mk` | **唯一事实出口**：在 stub 上下文里 include `rules/<pkg>.mk`，把模式、版本、dsc URL、补丁目录、deb 清单以 key=value 打印。被三个脚本与两个单测共用。 |
| `scripts/ppa/build-source.sh` | 容器内：`dget` stock → 补丁进 `debian/patches` → `dch` → `dpkg-buildpackage -S` → `target/source/<pkg>/`。 |
| `scripts/ppa/build-clean.sh` | 在一次性 `ubuntu:resolute` 容器里构建源码包，模拟 Launchpad builder。验收第 1 项用。 |
| `scripts/ppa/sign-upload.sh` | 宿主机：`debsign` + 可选 `dput`。 |
| `scripts/ppa/manifest.sh` | `make ppa-manifest` 的实现，打印状态表。 |
| `scripts/ppa/tests/assert.mk` | 两个测试套件共用的 `assert` 断言宏与 `FAILURES` 收集。 |
| `scripts/ppa/tests/functions_test.mk` | `ppa_*` 五函数的单测（10 个用例）。 |
| `scripts/ppa/tests/rules_test.mk` | `rules/<pkg>.mk` 双模式单测（local 与 ppa 各自的注册列表与 URL）。 |
| `scripts/ppa/tests/run-tests.sh` | 跑上面两个 `.mk`，非零退出即失败。 |
| `rules/{libteam,isc-dhcp,lm-sensors}.mk` | 每个加两个变量 + 一个 `ifneq/else/endif` 注册分支。 |
| `rules/{libteam,isc-dhcp,lm-sensors}.dep` | 每个加两行 `ifeq/endif` 守卫。 |
| `src/{libteam,isc-dhcp,lm-sensors}/Makefile` | `dget` 改用 `$(<PREFIX>_DSC_URL)`，消除硬编码 URL。 |
| `src/isc-dhcp/patch/0019-resolute-disable-lto.patch` | 把 `DEB_*_MAINT_STRIP` 内化进 `debian/rules`。 |
| `src/lm-sensors/patch/0003-build-sensord-via-prog-extra.patch` | 把 `PROG_EXTRA=sensord` 内化进 `debian/rules`。 |
| `slave.mk` | 一个 `ppa-manifest` phony 目标。 |

---

## Task 1：make 层（开关、函数、query.mk、单测夹具）

**文件：**
- 修改：`rules/config`（追加到文件末尾）
- 修改：`rules/functions`（追加到文件末尾）
- 新建：`scripts/ppa/query.mk`
- 新建：`scripts/ppa/tests/assert.mk`
- 新建：`scripts/ppa/tests/functions_test.mk`
- 新建：`scripts/ppa/tests/run-tests.sh`

**接口：**
- 产出（后续任务依赖）：
  - `$(call ppa_suffix,<pkg>)` → 后缀字符串，如 `+sonic1~ppa1`
  - `$(call ppa_ver,<pkg>)` → 该包在 PPA 模式下返回后缀，否则返回空字符串
  - `$(call ppa_pool_dir,<src-name>)` → pool 二级目录，如 `libt` / `l`
  - `$(call ppa_file,<deb-name>)` → dbgsym 换成 `.ddeb`，其余原样
  - `$(call ppa_url,<src-name>,<deb-name>)` → 完整下载 URL
  - `make -s -f scripts/ppa/query.mk PKG=<pkg>` → 打印 `PKG=` `MODE=` `STOCK_VERSION=` `DSC_URL=` `SUFFIX=` `PATCH_DIR=` `MAIN_DEB=` `DERIVED_DEBS=` `SOURCE=` `PPA_POOL_URL=` 十行
  - 变量 `SONIC_PPA_PACKAGES` / `SONIC_PPA_URL` / `SONIC_PPA_SUFFIX` / `SONIC_PPA_SUFFIX_<pkg>`

- [ ] **Step 1：写失败的单测**

先新建共用断言宏 `scripts/ppa/tests/assert.mk`（两个测试套件共用，不要各写一份）：

```make
# make 层单测共用的断言宏。
#
# 用法：include 本文件后
#   $(call assert,<名称>,<实际值>,<期望值>)
# 收集失败到 FAILURES；测试套件的默认目标据此决定退出码。
FAILURES :=

define assert
$(if $(filter-out x$(3),x$(2)),\
  $(warning FAIL $(1): got "$(2)" want "$(3)")$(eval FAILURES += $(1)),\
  $(info ok   $(1)))
endef

# 各测试套件在自己的默认目标里 include 本段逻辑：
#   ifneq ($(strip $(FAILURES)),)
#   	@echo "FAILED: $(FAILURES)"; exit 1
#   else
#   	@echo "<suite>: all assertions passed"
#   endif
```

再新建 `scripts/ppa/tests/functions_test.mk`：

```make
# ppa_* 辅助函数的单测。不 include slave.mk —— 只 include rules/functions,
# 使本测试能在裸仓库里瞬间跑完。
# 用法: make -s -f scripts/ppa/tests/functions_test.mk

SONIC_PPA_URL              := https://ppa.launchpadcontent.net/o/n/ubuntu
SONIC_PPA_SUFFIX           := +sonic1~ppa1
SONIC_PPA_SUFFIX_lm-sensors := +sonic1~ppa2
SONIC_PPA_PACKAGES         := libteam lm-sensors

include rules/functions
include scripts/ppa/tests/assert.mk

$(call assert,ppa_ver-on,$(call ppa_ver,libteam),+sonic1~ppa1)
$(call assert,ppa_ver-off,$(call ppa_ver,isc-dhcp),)
$(call assert,ppa_suffix-global,$(call ppa_suffix,libteam),+sonic1~ppa1)
$(call assert,ppa_suffix-override,$(call ppa_suffix,lm-sensors),+sonic1~ppa2)
$(call assert,pool_dir-lib,$(call ppa_pool_dir,libteam),libt)
$(call assert,pool_dir-plain,$(call ppa_pool_dir,lm-sensors),l)
$(call assert,pool_dir-hyphen,$(call ppa_pool_dir,isc-dhcp),i)
$(call assert,ppa_file-plain,$(call ppa_file,libteam5_1.31-1build4_amd64.deb),libteam5_1.31-1build4_amd64.deb)
$(call assert,ppa_file-dbgsym,$(call ppa_file,libteam5-dbgsym_1.31-1build4_amd64.deb),libteam5-dbgsym_1.31-1build4_amd64.ddeb)
$(call assert,ppa_url-dbgsym,$(call ppa_url,libteam,libteam5-dbgsym_1.31-1build4_amd64.deb),https://ppa.launchpadcontent.net/o/n/ubuntu/pool/main/libt/libteam/libteam5-dbgsym_1.31-1build4_amd64.ddeb)
$(call assert,ppa_url-all-deb,$(call ppa_url,lm-sensors,fancontrol_3.6.2-2build1+sonic1~ppa2_all.deb),https://ppa.launchpadcontent.net/o/n/ubuntu/pool/main/l/lm-sensors/fancontrol_3.6.2-2build1+sonic1~ppa2_all.deb)

.PHONY: default
default:
ifneq ($(strip $(FAILURES)),)
	@echo "FAILED: $(FAILURES)"; exit 1
else
	@echo "functions_test: all assertions passed"
endif
```

新建 `scripts/ppa/tests/run-tests.sh`（`chmod +x`）：

```bash
#!/bin/bash
# 跑 PPA 脚手架的全部 make 层单测。必须从仓库根目录运行。
set -euo pipefail

cd "$(dirname "$0")/../../.."

rc=0
for t in scripts/ppa/tests/*_test.mk; do
    echo "== $t"
    make -s -f "$t" || rc=1
done

if [ "$rc" -ne 0 ]; then
    echo "PPA make-layer tests FAILED"
    exit 1
fi
echo "PPA make-layer tests passed"
```

- [ ] **Step 2：跑测试确认失败**

```bash
chmod +x scripts/ppa/tests/run-tests.sh
./scripts/ppa/tests/run-tests.sh
```

期望：退出码 1，且输出里含 10 条 `FAIL`（因为 `ppa_*` 函数尚不存在，`$(call ...)` 全部展开为空字符串；`ppa_ver-off` 一条会误过，因为期望值本就是空）。具体应看到 `FAIL ppa_ver-on: got "" want "+sonic1~ppa1"` 等，最后一行 `FAILED: ...`。

- [ ] **Step 3：追加三个开关到 `rules/config` 末尾**

```make

# ---- Launchpad PPA 消费（仅 resolute）----

# SONIC_PPA_PACKAGES - 从 PPA 拉取预编译 deb、而不本地自建的包，按 src/ 下的
# 目录名列出，空格分隔。留空则全部本地自建，构建行为与未引入本机制时一致。
# 可在 rules/config.user 里覆盖，便于单机把某个包临时切回本地自建。
SONIC_PPA_PACKAGES ?=

# SONIC_PPA_URL - PPA 的 pool 根 URL。必须用 ppa.launchpadcontent.net 直连，
# 因为 +files 形式会重定向到 launchpadlibrarian.net，构建环境不可达。
# 例：https://ppa.launchpadcontent.net/<owner>/<name>/ubuntu
SONIC_PPA_URL ?=

# SONIC_PPA_SUFFIX - 追加在上游版本号之后的 SONiC 修订后缀。排序位于 stock
# 版本之上、下一个 Ubuntu 修订之下，因此 Ubuntu 出 SRU 时会自然盖过我们。
# 同一修订需要重传时用 SONIC_PPA_SUFFIX_<pkg> 覆盖单个包，例：
#   SONIC_PPA_SUFFIX_libteam ?= +sonic1~ppa2
SONIC_PPA_SUFFIX ?= +sonic1~ppa1
```

- [ ] **Step 4：追加五个函数到 `rules/functions` 末尾**

```make

# ---- Launchpad PPA 辅助函数 ----
#
# 注意：本文件只被 slave.mk:289 include。Makefile.work:155 会在没有本文件的
# 宿主机上下文里 include rules/sonic-fips.mk，因此下列函数不可用于该文件。

# ppa_suffix <pkg> —— 单包覆盖优先于全局默认
ppa_suffix = $(or $(SONIC_PPA_SUFFIX_$(1)),$(SONIC_PPA_SUFFIX))

# ppa_ver <pkg> —— 仅当该包处于 PPA 模式时返回后缀，否则返回空。
# 供 <PREFIX>_VERSION_FULL 内联使用，从而所有 deb 名定义无需分支。
ppa_ver = $(if $(filter $(1),$(SONIC_PPA_PACKAGES)),$(call ppa_suffix,$(1)))

# ppa_pool_dir <source-name> —— Debian pool 二级目录：libxxx → libx，其余取首字母
ppa_pool_dir = $(if $(filter lib%,$(1)),$(shell echo $(1) | cut -c1-4),$(shell echo $(1) | cut -c1))

# ppa_file <deb-name> —— dbgsym 在 PPA 上发布为 .ddeb（Launchpad builder 上无法
# 施加 slave 里那个 Dh_Lib.pm 补丁）。只改 URL 一侧；make 目标名与落盘名仍是 .deb，
# 靠 slave.mk:761 的 curl -o 撑住。
ppa_file = $(if $(findstring -dbgsym,$(1)),$(patsubst %.deb,%.ddeb,$(1)),$(1))

# ppa_url <source-name>,<deb-name> —— PPA 只有 main 一个 component，与该包在
# Ubuntu 官方归档里属于 main 还是 universe 无关（monit 官方在 universe，
# 进 PPA 后仍在 pool/main/m/monit/）。
ppa_url = $(SONIC_PPA_URL)/pool/main/$(call ppa_pool_dir,$(1))/$(1)/$(call ppa_file,$(2))
```

- [ ] **Step 5：跑测试确认通过**

```bash
./scripts/ppa/tests/run-tests.sh
```

期望：退出码 0，输出 11 行 `ok  ...`（10 个断言 + 汇总行 `functions_test: all assertions passed`）。

- [ ] **Step 6：新建 `scripts/ppa/query.mk`**

```make
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
```

- [ ] **Step 7：验证 query.mk 在三个包上都能跑**

```bash
for p in libteam isc-dhcp lm-sensors; do echo "--- $p"; make -s -f scripts/ppa/query.mk PKG=$p; done
```

期望（本任务尚未给包加 `_VERSION_STOCK` / `_DSC_URL`，故那三行为空，这是正常的）：

```
--- libteam
PKG=libteam
MODE=local
STOCK_VERSION=
DSC_URL=
SUFFIX=+sonic1~ppa1
PATCH_DIR=src/libteam/patch
MAIN_DEB=libteam5_1.31-1build4_amd64.deb
DERIVED_DEBS=libteam5-dbgsym_1.31-1build4_amd64.deb libteam-dev_1.31-1build4_amd64.deb libteamdctl0_1.31-1build4_amd64.deb libteamdctl0-dbgsym_1.31-1build4_amd64.deb libteam-utils_1.31-1build4_amd64.deb libteam-utils-dbgsym_1.31-1build4_amd64.deb
SOURCE=
PPA_POOL_URL=
--- isc-dhcp
...
MAIN_DEB=isc-dhcp-relay_4.4.3-P1-2_amd64.deb
DERIVED_DEBS=isc-dhcp-relay-dbgsym_4.4.3-P1-2_amd64.deb
...
--- lm-sensors
...
MAIN_DEB=lm-sensors_3.6.2-2build1_amd64.deb
DERIVED_DEBS=lm-sensors-dbgsym_3.6.2-2build1_amd64.deb fancontrol_3.6.2-2build1_all.deb libsensors5_3.6.2-2build1_amd64.deb libsensors5-dbgsym_3.6.2-2build1_amd64.deb sensord_3.6.2-2build1_amd64.deb sensord-dbgsym_3.6.2-2build1_amd64.deb
```

三个包都必须退出码 0，`MAIN_DEB` 恰好一个，`PATCH_DIR` 恰好一个。

- [ ] **Step 8：确认默认开关不改变构建行为**

```bash
grep -cE '^SONIC_PPA_(PACKAGES|URL|SUFFIX) \?=' rules/config
make -s -f scripts/ppa/query.mk PKG=libteam | grep '^MODE='
```

期望：`grep -c` 输出恰好 `3`（三个开关的 `?=` 赋值）；`MODE=local`。因为 `SONIC_PPA_PACKAGES` 为空，`SONIC_MAKE_DEBS` 仍注册 libteam，构建路径未变。

- [ ] **Step 9：提交**

```bash
git add rules/config rules/functions scripts/ppa/query.mk scripts/ppa/tests/
git commit -m "build(ppa): add the make layer for PPA-vs-local package selection

Three switches in rules/config (SONIC_PPA_PACKAGES / _URL / _SUFFIX, all
inert when the package list is empty) and four helper functions in
rules/functions that centralise the version-suffix and pool-URL derivation.

scripts/ppa/query.mk includes rules/<pkg>.mk in a minimal stub context and
prints the PPA facts as key=value, so the scripts and the tests read them
from rules/*.mk rather than from a parallel manifest. It deliberately does
not include slave.mk: it has to run in a bare checkout with no docker and
no 'make configure'.

The main deb is read back out of whichever registration list is non-empty
instead of from a per-package variable name, because those names do not
follow a rule (isc-dhcp's is ISC_DHCP_RELAY, not ISC_DHCP).

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Task 2：libteam 接线（双模式 + rules 单测）

`libteam` 是干净基线：14 个生效补丁全在 series 里、`src/libteam/Makefile` 除 `dget` 与 `dpkg-buildpackage` 外**没有任何树外动作**。它跑不通就说明脚手架本身有问题，因此第一个做。

**文件：**
- 修改：`rules/libteam.mk`
- 修改：`rules/libteam.dep`
- 修改：`src/libteam/Makefile:18`
- 新建：`scripts/ppa/tests/rules_test.mk`

**接口：**
- 消费：Task 1 的 `ppa_ver` / `ppa_url` / `SONIC_PPA_*` / `query.mk`
- 产出：`LIBTEAM_VERSION_STOCK` = `1.31-1build4`、`LIBTEAM_DSC_URL`；`rules/<pkg>.mk` 的改动形态模板，Task 4 / Task 5 照此套用

- [ ] **Step 1：写失败的单测**

新建 `scripts/ppa/tests/rules_test.mk`：

```make
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
```

- [ ] **Step 2：跑测试确认失败**

```bash
./scripts/ppa/tests/run-tests.sh
```

期望：`functions_test` 通过，`rules_test` 失败退出码 1。应看到 `FAIL libteam-online: got "" want "libteam5_1.31-1build4+sonic1~ppa1_amd64.deb"`、`FAIL libteam-not-make: got "libteam5_1.31-1build4_amd64.deb" want ""`、`FAIL libteam-stock-ver: got "" want "1.31-1build4"` 等。

- [ ] **Step 3：改 `rules/libteam.mk`**

只改一行（版本行），其余全为插入。改完后文件头部与注册处应长成：

```make
# libteam packages

LIBTEAM_VERSION := 1.31
LIBTEAM_VERSION_STOCK := $(LIBTEAM_VERSION)-1build4
LIBTEAM_VERSION_FULL := $(LIBTEAM_VERSION_STOCK)$(call ppa_ver,libteam)

LIBTEAM_DSC_URL := http://archive.ubuntu.com/ubuntu/pool/main/libt/libteam/libteam_$(LIBTEAM_VERSION_STOCK).dsc

export LIBTEAM_VERSION
export LIBTEAM_VERSION_FULL
export LIBTEAM_VERSION_STOCK
export LIBTEAM_DSC_URL

LIBTEAM = libteam5_$(LIBTEAM_VERSION_FULL)_$(CONFIGURED_ARCH).deb
$(LIBTEAM)_SRC_PATH = $(SRC_PATH)/libteam
$(LIBTEAM)_DEPENDS += $(LIBNL_GENL3_DEV) $(LIBNL_CLI_DEV)
```

即：原来的 `LIBTEAM_VERSION_FULL := $(LIBTEAM_VERSION)-1build4` 一行改为上面的两行（`_VERSION_STOCK` + 内联后缀的 `_VERSION_FULL`），并插入 `LIBTEAM_DSC_URL` 与两个新 `export`。**原来的 `SONIC_MAKE_DEBS += $(LIBTEAM)` 那一行先留在原处不动**（它在 `$(LIBTEAM)_DEPENDS` 之后）。

然后把该行替换为模式分支。原文：

```make
SONIC_MAKE_DEBS += $(LIBTEAM)
```

改为：

```make
ifneq ($(filter libteam,$(SONIC_PPA_PACKAGES)),)
SONIC_ONLINE_DEBS += $(LIBTEAM)
else
SONIC_MAKE_DEBS += $(LIBTEAM)
endif
```

最后，在文件里所有 `add_derived_package` 调用**之后**（即 `LIBTEAM_UTILS_DBG` 那组之后、`DBG_SRC_ARCHIVE += libteam` 之前）插入 URL 覆盖块。`add_derived_package` 会让派生包继承主包 URL（`rules/functions:94`），必须逐个覆盖：

```make
# PPA 模式：主包与每个派生包各自的下载地址。必须位于所有 add_derived_package
# 调用之后 —— 那个宏会让派生包继承主包的 _URL（rules/functions:94）。
ifneq ($(filter libteam,$(SONIC_PPA_PACKAGES)),)
$(LIBTEAM)_URL             = $(call ppa_url,libteam,$(LIBTEAM))
$(LIBTEAM_DBG)_URL         = $(call ppa_url,libteam,$(LIBTEAM_DBG))
$(LIBTEAM_DEV)_URL         = $(call ppa_url,libteam,$(LIBTEAM_DEV))
$(LIBTEAMDCTL)_URL         = $(call ppa_url,libteam,$(LIBTEAMDCTL))
$(LIBTEAMDCTL_DBG)_URL     = $(call ppa_url,libteam,$(LIBTEAMDCTL_DBG))
$(LIBTEAM_UTILS)_URL       = $(call ppa_url,libteam,$(LIBTEAM_UTILS))
$(LIBTEAM_UTILS_DBG)_URL   = $(call ppa_url,libteam,$(LIBTEAM_UTILS_DBG))
endif
```

- [ ] **Step 4：改 `rules/libteam.dep`（两行插入，零行修改）**

```diff
 SPATH       := $($(LIBTEAM)_SRC_PATH)
 DEP_FILES   := $(SONIC_COMMON_FILES_LIST) rules/libteam.mk rules/libteam.dep   
 DEP_FILES   += $(SONIC_COMMON_BASE_FILES_LIST)
+ifeq ($(filter libteam,$(SONIC_PPA_PACKAGES)),)
 DEP_FILES   += $(shell git ls-files $(SPATH))
+endif
```

按包名而非按 `$(SPATH)` 是否为空判断，与 `.mk` 的守卫条件一致。PPA 模式下缓存键退化为 `.mk` 内容 —— 其中含版本号与后缀，所以改后缀会正确使缓存失效。

- [ ] **Step 5：改 `src/libteam/Makefile:18` 消除硬编码 URL**

```diff
-	dget -u http://archive.ubuntu.com/ubuntu/pool/main/libt/libteam/libteam_$(LIBTEAM_VERSION_FULL).dsc
+	dget -u $(LIBTEAM_DSC_URL)
```

这一步把 dsc 地址收敛成一个定义。`LIBTEAM_DSC_URL` 用的是 `_VERSION_STOCK`，因此即使将来 `_VERSION_FULL` 带上 PPA 后缀，本地自建路径拿到的仍是官方源码包。

- [ ] **Step 6：跑测试确认通过**

```bash
./scripts/ppa/tests/run-tests.sh
```

期望：退出码 0，两个测试都输出 `all assertions passed`。

- [ ] **Step 7：确认 local 模式零回归**

```bash
make -s -f scripts/ppa/query.mk PKG=libteam
```

期望（`SONIC_PPA_PACKAGES` 在 `rules/config` 里为空，故为 local 模式，deb 名不带后缀）：

```
PKG=libteam
MODE=local
STOCK_VERSION=1.31-1build4
DSC_URL=http://archive.ubuntu.com/ubuntu/pool/main/libt/libteam/libteam_1.31-1build4.dsc
SUFFIX=+sonic1~ppa1
PATCH_DIR=src/libteam/patch
MAIN_DEB=libteam5_1.31-1build4_amd64.deb
DERIVED_DEBS=libteam5-dbgsym_1.31-1build4_amd64.deb libteam-dev_1.31-1build4_amd64.deb libteamdctl0_1.31-1build4_amd64.deb libteamdctl0-dbgsym_1.31-1build4_amd64.deb libteam-utils_1.31-1build4_amd64.deb libteam-utils-dbgsym_1.31-1build4_amd64.deb
SOURCE=libteam
```

关键：`MAIN_DEB` 与改动前完全一致（`libteam5_1.31-1build4_amd64.deb`，无后缀），`SOURCE=libteam` 已能从 dsc URL 推出。

再确认 PPA 模式下名字确实变化：

```bash
make -s -f scripts/ppa/query.mk PKG=libteam SONIC_PPA_PACKAGES=libteam | grep -E '^(MODE|MAIN_DEB)='
```

期望：

```
MODE=ppa
MAIN_DEB=libteam5_1.31-1build4+sonic1~ppa1_amd64.deb
```

- [ ] **Step 8：提交**

```bash
git add rules/libteam.mk rules/libteam.dep src/libteam/Makefile scripts/ppa/tests/rules_test.mk
git commit -m "build(ppa): wire libteam for PPA-or-local selection

libteam is the clean baseline for this mechanism: all 14 active patches are
in the series and src/libteam/Makefile does nothing outside dget and
dpkg-buildpackage, so a failure here means the scaffolding is wrong rather
than the package being special.

The PPA suffix is inlined into LIBTEAM_VERSION_FULL so every deb-name
definition and every add_derived_package call stays literally unchanged;
only the registration line becomes a branch. That keeps the diff to pure
insertions, which matters because this tree is rebased onto sonic-net/202605
repeatedly and re-indentation would turn every upstream edit into a conflict.

Each derived deb needs its _URL overridden after the add_derived_package
call, because that macro makes derived debs inherit the main deb's URL
(rules/functions:94).

The dsc URL moves into LIBTEAM_DSC_URL, built from the new
LIBTEAM_VERSION_STOCK rather than from _VERSION_FULL, so the local build
path still fetches the official source package once _VERSION_FULL carries a
PPA suffix.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Task 3：`build-source.sh` + 干净 chroot + libteam 源码包

**文件：**
- 新建：`scripts/ppa/build-source.sh`
- 新建：`scripts/ppa/build-clean.sh`
- 新建：`scripts/ppa/tests/test-build-source.sh`

**接口：**
- 消费：`scripts/ppa/query.mk`（Task 1）、`LIBTEAM_DSC_URL` / `LIBTEAM_VERSION_STOCK`（Task 2）
- 产出：`target/source/<pkg>/<source>_<stock><suffix>.dsc` 与同名 `_source.changes`、`.debian.tar.xz`（`orig` 视 `-sa`/`-sd` 而定）；`scripts/ppa/build-clean.sh <pkg>` 把二进制产物放进 `target/source/<pkg>/build/`

- [ ] **Step 1：写 `scripts/ppa/build-clean.sh`（干净环境构建器）**

不用 `sbuild`/`pbuilder`：那要往宿主机装 4 个包、建持久 `/srv/chroot` 树、`sbuild-adduser` 再重新登录，全部需要 sudo。本项目的规矩是宿主机改动只作最后手段。改用一次性 `ubuntu:resolute` 容器 —— 它正是 slave 镜像自己的 `FROM` base（`sonic-slave-resolute/Dockerfile.j2:19`），构建时已经拉好；`--rm` 每次从原始镜像起因而天然干净；且**没有** slave 里那个 `Dh_Lib.pm` 补丁，dbgsym 会如实产出 `.ddeb`。

新建（`chmod +x`）：

```bash
#!/bin/bash
# 在一次性 ubuntu:resolute 容器里构建一个已生成的源码包,用来模拟 Launchpad
# builder。验收标准第 1 项。
#
# 刻意不用 slave 镜像:slave 预装了大量 build-dep 并打了 Dh_Lib.pm 补丁,用它
# 就验不出「树外动作丢失」这类问题,也验不出 .ddeb 行为。
# 刻意不用 sbuild/pbuilder:那需要 sudo 往宿主机装东西并建持久 chroot。
#
# 用法: scripts/ppa/build-clean.sh <pkg>
set -euo pipefail

PKG="${1:?usage: $0 <pkg>}"
cd "$(dirname "$0")/../.."
REPO=$PWD
SRCDIR="$REPO/target/source/$PKG"

ls "$SRCDIR"/*.dsc >/dev/null 2>&1 || { echo "$PKG: no .dsc in $SRCDIR; run build-source.sh first" >&2; exit 1; }

rm -rf "$SRCDIR/build"

# apt-get build-dep ./ 读的是解包后的 debian/control,不需要 deb-src 源,
# 所以 ubuntu:resolute 镜像默认的 sources 就够。
docker run --rm \
    -v "$SRCDIR:/src" \
    -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
    ubuntu:resolute bash -euc '
        apt-get -qq update
        apt-get -qq install -y --no-install-recommends build-essential devscripts
        mkdir /build && cd /build
        dpkg-source -x /src/*.dsc pkg
        cd pkg
        apt-get -qq build-dep -y --no-install-recommends ./
        dpkg-buildpackage -b -us -uc
        mkdir -p /src/build
        # 每个包的产物组合不同(有的无 dbgsym、有的有 _all.deb),所以两条 glob
        # 各自允许失配;但至少要有一个产物,否则是真失败,不能被 || true 吞掉。
        cp -a /build/*.deb  /src/build/ 2>/dev/null || true
        cp -a /build/*.ddeb /src/build/ 2>/dev/null || true
        n=$(ls -1 /src/build | wc -l)
        [ "$n" -gt 0 ] || { echo "build produced no .deb/.ddeb artifacts" >&2; exit 1; }
        echo "collected $n artifact(s)"
        chown -R "$HOST_UID:$HOST_GID" /src/build
    '

echo "== $PKG built in a clean ubuntu:resolute container:"
ls -1 "$SRCDIR/build"
```

先确认基础镜像在本地（构建 slave 时已拉过）：

```bash
chmod +x scripts/ppa/build-clean.sh
docker images --format '{{.Repository}}:{{.Tag}}' | grep -x 'ubuntu:resolute'
./scripts/ppa/build-clean.sh libteam
```

期望：`grep -x` 输出 `ubuntu:resolute`；此时 `build-clean.sh` 报 `libteam: no .dsc in .../target/source/libteam; run build-source.sh first` 并退出码 1 —— 源码包还没造出来，这正是接下来几步要做的。

- [ ] **Step 2：写失败的测试**

新建 `scripts/ppa/tests/test-build-source.sh`（`chmod +x`）：

```bash
#!/bin/bash
# 验证 build-source.sh 为一个包产出的源码包是否正确：
#   - 产出 .dsc 与 _source.changes
#   - 上传清单里没有任何 .deb（PPA 只收 source upload）
#   - SONiC 补丁已追加进 debian/patches/series，顺序与 src/<pkg>/patch/series 一致
#   - 补丁保持「未应用」状态（由 Launchpad builder 在构建时应用）
set -euo pipefail

PKG="${1:?usage: test-build-source.sh <pkg>}"
cd "$(dirname "$0")/../../.."

# 用 read 而非 eval：DERIVED_DEBS 的值含空格，eval 会把它按词拆开去执行
while IFS='=' read -r k v; do declare "Q_$k=$v"; done \
    < <(make -s -f scripts/ppa/query.mk PKG="$PKG")
OUT="target/source/$PKG"

dsc=$(ls "$OUT"/*.dsc 2>/dev/null | head -1)
[ -n "$dsc" ] || { echo "FAIL: no .dsc in $OUT"; exit 1; }
echo "ok   dsc present: $dsc"

changes=$(ls "$OUT"/*_source.changes 2>/dev/null | head -1)
[ -n "$changes" ] || { echo "FAIL: no _source.changes in $OUT"; exit 1; }
echo "ok   changes present: $changes"

if grep -qE '^\s.*\.deb$' "$changes"; then
    echo "FAIL: $changes lists a .deb; PPAs reject binary uploads"; exit 1
fi
echo "ok   changes contains no .deb"

# 版本号必须是 stock + suffix
want_ver="${Q_STOCK_VERSION}${Q_SUFFIX}"
if ! grep -q "^Version: ${want_ver}\$" "$dsc"; then
    echo "FAIL: $dsc Version is not '$want_ver'"; grep '^Version:' "$dsc"; exit 1
fi
echo "ok   version is $want_ver"

# 解包，检查 series 尾部与补丁未应用
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
dpkg-source --no-check -x "$dsc" "$tmp/src" >/dev/null
grep -vE '^\s*(#|$)' "$Q_PATCH_DIR/series" > "$tmp/want"
tail -n "$(wc -l < "$tmp/want")" "$tmp/src/debian/patches/series" > "$tmp/got"
if ! diff -u "$tmp/want" "$tmp/got"; then
    echo "FAIL: SONiC patches are not appended verbatim at the end of debian/patches/series"; exit 1
fi
echo "ok   $(wc -l < "$tmp/want") SONiC patches appended in order"

if [ -d "$tmp/src/.pc" ]; then
    echo "FAIL: $tmp/src/.pc exists; patches must ship UNAPPLIED"; exit 1
fi
echo "ok   patches ship unapplied"

echo "test-build-source($PKG): all assertions passed"
```

- [ ] **Step 3：跑测试确认失败**

```bash
./scripts/ppa/tests/test-build-source.sh libteam
```

期望：退出码 1，输出 `FAIL: no .dsc in target/source/libteam`（脚本与产物都还不存在）。

- [ ] **Step 4：写 `scripts/ppa/build-source.sh`**

新建（`chmod +x`）：

```bash
#!/bin/bash
# 为一个或多个包产出未签名的 Debian 源码包，供上传到 Launchpad PPA。
#
# 在 slave-resolute 容器内运行（需要 dget / dch / dpkg-source，容器已含
# devscripts）。刻意不签名、不上传：GPG 与 dput 由宿主机上的
# scripts/ppa/sign-upload.sh 负责。
#
# 用法: scripts/ppa/build-source.sh <pkg>...
#   例: scripts/ppa/build-source.sh libteam isc-dhcp lm-sensors
set -euo pipefail

[ $# -ge 1 ] || { echo "usage: $0 <pkg>..." >&2; exit 2; }
cd "$(dirname "$0")/../.."
REPO=$PWD

for PKG in "$@"; do
    echo "=== $PKG"
    # 用 read 而非 eval：DERIVED_DEBS 的值含空格，eval 会把它按词拆开去执行
while IFS='=' read -r k v; do declare "Q_$k=$v"; done \
    < <(make -s -f scripts/ppa/query.mk PKG="$PKG")

    [ -n "${Q_DSC_URL:-}" ] || { echo "$PKG: <PREFIX>_DSC_URL is not set in rules/$PKG.mk" >&2; exit 1; }
    [ -n "${Q_STOCK_VERSION:-}" ] || { echo "$PKG: <PREFIX>_VERSION_STOCK is not set in rules/$PKG.mk" >&2; exit 1; }

    # 补丁里含二进制文件需要 debian/source/include-binaries；本批次没有，
    # 但要显式报错而不是静默产出一个 dpkg-source 会拒绝的包。
    if grep -rlq $'^GIT binary patch' "$REPO/$Q_PATCH_DIR"/*.patch 2>/dev/null; then
        echo "$PKG: patch series contains a binary patch; needs debian/source/include-binaries" >&2
        exit 1
    fi

    WORK=$(mktemp -d)
    OUT="$REPO/target/source/$PKG"
    mkdir -p "$OUT"

    pushd "$WORK" >/dev/null
    # -u 是结构性必需：Ubuntu slave 上 .dsc 上传者的个人 key 不在任何可用
    # keyring 里，装 debian-keyring 也验不了。
    dget -u "$Q_DSC_URL"

    SRCDIR=$(find . -maxdepth 1 -type d -name "$Q_SOURCE-*" | head -1)
    [ -n "$SRCDIR" ] || { echo "$PKG: cannot find extracted source dir for $Q_SOURCE" >&2; exit 1; }
    pushd "$SRCDIR" >/dev/null

    # dget 已通过 dpkg-source -x 应用了上游 debian/patches，所以工作树是
    # 「完全打好补丁」的状态。把 SONiC 补丁按同一顺序追加进 series 即等价，
    # 但补丁本身必须保持未应用 —— builder 会在构建时应用。
    mkdir -p debian/patches
    [ -f debian/patches/series ] || : > debian/patches/series
    while read -r p; do
        cp "$REPO/$Q_PATCH_DIR/$p" debian/patches/
        echo "$p" >> debian/patches/series
    done < <(grep -vE '^\s*(#|$)' "$REPO/$Q_PATCH_DIR/series")

    # dget 解包时留下的 .pc 会让 dpkg-source 认为补丁已应用
    rm -rf .pc

    dch --newversion "${Q_STOCK_VERSION}${Q_SUFFIX}" \
        --distribution resolute --force-distribution \
        "SONiC packaging for Ubuntu resolute: apply the $PKG patch series from sonic-buildimage."

    # 该 upstream 版本首次上传要带 orig（-sa）；后续必须 -sd，否则 Launchpad
    # 会因 orig 校验和冲突 reject。以 PPA pool 里是否已有该 orig 为准；
    # 无法判定时保守用 -sd 并提示。
    # pool URL 由 query.mk 给出(见 Q_PPA_POOL_URL),不在这里用 sed 重推一遍
    # ppa_pool_dir 的逻辑 —— 那会让同一规则存在两份实现。
    SA_FLAG=-sd
    if [ -n "${Q_PPA_POOL_URL:-}" ]; then
        if ! curl -sfL "$Q_PPA_POOL_URL/" | grep -q "${Q_SOURCE}_.*\.orig\."; then
            SA_FLAG=-sa
        fi
    else
        echo "  note: SONIC_PPA_URL unset, cannot tell if the orig is already uploaded; using -sa for the first local run" >&2
        SA_FLAG=-sa
    fi

    dpkg-buildpackage -S "$SA_FLAG" -us -uc -d
    popd >/dev/null

    rm -f "$OUT"/*
    mv ./*.dsc ./*_source.changes ./*.tar.* ./*.buildinfo "$OUT"/ 2>/dev/null || true
    popd >/dev/null
    rm -rf "$WORK"

    echo "  -> $OUT"
    ls -1 "$OUT"
done
```

- [ ] **Step 5：跑脚本产出 libteam 源码包，再跑测试确认通过**

在容器内跑（宿主机上没有 `dget` 也没有 resolute 的 devscripts）：

```bash
make sonic-slave-run SONIC_RUN_CMDS="scripts/ppa/build-source.sh libteam"
./scripts/ppa/tests/test-build-source.sh libteam
```

期望：`build-source.sh` 输出 `-> /sonic/target/source/libteam` 与文件清单；测试退出码 0，输出

```
ok   dsc present: target/source/libteam/libteam_1.31-1build4+sonic1~ppa1.dsc
ok   changes present: target/source/libteam/libteam_1.31-1build4+sonic1~ppa1_source.changes
ok   changes contains no .deb
ok   version is 1.31-1build4+sonic1~ppa1
ok   14 SONiC patches appended in order
ok   patches ship unapplied
test-build-source(libteam): all assertions passed
```

- [ ] **Step 6：在干净容器里构建，验收标准第 1 项**

```bash
./scripts/ppa/build-clean.sh libteam
```

期望：构建成功，`target/source/libteam/build/` 下 7 个产物 —— `libteam5`、`libteam-dev`、`libteamdctl0`、`libteam-utils` 四个 `.deb`，以及 `libteam5-dbgsym`、`libteamdctl0-dbgsym`、`libteam-utils-dbgsym` 三个 **`.ddeb`**（证实设计 §3.6：干净容器里没有 slave 的 `Dh_Lib.pm` 补丁，扩展名保持 Ubuntu 原生的 `.ddeb`）。

若因补丁 fuzz 失败（`stg import` 容忍 fuzz，`dpkg-source` 应用补丁时零 fuzz），用 `quilt push -a` + `quilt refresh` 逐个 refresh 后更新 `src/libteam/patch/` 里对应的补丁文件，并把 refresh 单独提交。

- [ ] **Step 7：提交**

```bash
git add scripts/ppa/build-source.sh scripts/ppa/build-clean.sh scripts/ppa/tests/test-build-source.sh
git commit -m "build(ppa): generate unsigned source packages from the in-tree patch series

build-source.sh turns a package's stock .dsc plus src/<pkg>/patch/series into
an uploadable source package. It reads every fact from scripts/ppa/query.mk,
so rules/<pkg>.mk stays the only place the version and dsc URL are written.

The patches are copied into debian/patches and appended to series but left
UNAPPLIED, and .pc is removed: dget extracts via dpkg-source -x, which has
already applied the upstream patches, so appending in the same order is
equivalent and the Launchpad builder applies ours at build time.

Signing and uploading are deliberately absent — mounting the GPG agent
socket into a DinD container is expensive and fragile, so those live in
sign-upload.sh on the host.

-sa is chosen only when the orig is not already in the PPA pool; reusing an
orig with a different checksum is an upload rejection.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Task 4：isc-dhcp（内化 LTO strip）

`isc-dhcp` 是「构建必挂」类的代表：`src/isc-dhcp/Makefile:28-29` 在 `dpkg-buildpackage` 之外 `export DEB_CFLAGS_MAINT_STRIP` / `DEB_LDFLAGS_MAINT_STRIP` 关掉 LTO。这两行不在源码包里，Launchpad builder 看不到，源码包**一定**构建失败。必须内化进 `debian/rules`。

**文件：**
- 新建：`src/isc-dhcp/patch/0019-resolute-disable-lto-for-vendored-bind.patch`
- 修改：`src/isc-dhcp/patch/series`
- 修改：`rules/isc-dhcp.mk`
- 修改：`rules/isc-dhcp.dep`
- 修改：`src/isc-dhcp/Makefile`（第 13 行改用 `_DSC_URL`；第 25-29 行的树外 export 删除）
- 修改：`scripts/ppa/tests/rules_test.mk`（加 isc-dhcp 断言）

**接口：**
- 消费：Task 1 的函数、Task 2 的 `.mk` 改动形态
- 产出：`ISC_DHCP_VERSION_STOCK` = `4.4.3-P1-2`、`ISC_DHCP_DSC_URL`

- [ ] **Step 1：写失败的断言**

在 `scripts/ppa/tests/rules_test.mk` 里，把 `SONIC_PPA_PACKAGES` 改为 `libteam isc-dhcp`，在 `include rules/libteam.mk` 之后加 `include rules/isc-dhcp.mk`，并追加断言：

```make
$(call assert,iscdhcp-online,$(filter isc-dhcp-relay%,$(SONIC_ONLINE_DEBS)),isc-dhcp-relay_4.4.3-P1-2+sonic1~ppa1_amd64.deb)
$(call assert,iscdhcp-stock-ver,$(ISC_DHCP_VERSION_STOCK),4.4.3-P1-2)
$(call assert,iscdhcp-dsc-url,$(ISC_DHCP_DSC_URL),http://deb.debian.org/debian/pool/main/i/isc-dhcp/isc-dhcp_4.4.3-P1-2.dsc)
$(call assert,iscdhcp-dbg-url,$($(ISC_DHCP_RELAY_DBG)_URL),https://ppa.launchpadcontent.net/o/n/ubuntu/pool/main/i/isc-dhcp/isc-dhcp-relay-dbgsym_4.4.3-P1-2+sonic1~ppa1_amd64.ddeb)
```

- [ ] **Step 2：跑测试确认失败**

```bash
./scripts/ppa/tests/run-tests.sh
```

期望：`rules_test` 退出码 1，含 `FAIL iscdhcp-stock-ver: got "" want "4.4.3-P1-2"` 等四条。

- [ ] **Step 3：造内化 LTO strip 的补丁**

要写进 `debian/rules` 的内容，位置在 `#!/usr/bin/make -f` 之后、任何 `include` 之前：

```make
# resolute: bind 9.11.36（isc-dhcp 内嵌）无法用 -flto=auto 链接。libisc.a 里
# 符号是 T，但 svtest 与 dhclient 链接时仍报 undefined reference。
# 从 CFLAGS 与 LDFLAGS 两侧都剥掉 LTO。
#
# 这两行原先在 src/isc-dhcp/Makefile 里、以 dpkg-buildpackage 前后的 export
# 形式存在。那对本地自建有效，但 Launchpad builder 只看得到源码包。
export DEB_CFLAGS_MAINT_STRIP = -flto=auto -ffat-lto-objects
export DEB_LDFLAGS_MAINT_STRIP = -flto=auto -ffat-lto-objects
```

补丁必须以**真实**解包出的 `debian/rules` 为基准生成，不要手写 diff。先看实际内容：

```bash
make sonic-slave-run SONIC_RUN_CMDS="bash -c 'cd /tmp && dget -u http://deb.debian.org/debian/pool/main/i/isc-dhcp/isc-dhcp_4.4.3-P1-2.dsc && head -20 isc-dhcp-4.4.3-P1/debian/rules'"
```

按实际前 20 行决定插入位置，然后用 `quilt new 0019-resolute-disable-lto-for-vendored-bind.patch` + `quilt add debian/rules` + 编辑 + `quilt refresh` 生成规范补丁，把生成的文件放进 `src/isc-dhcp/patch/`。

- [ ] **Step 4：把补丁加进 series**

在 `src/isc-dhcp/patch/series` 末尾追加一行：

```
0019-resolute-disable-lto-for-vendored-bind.patch
```

- [ ] **Step 5：删掉 `src/isc-dhcp/Makefile` 的树外 export，并改用 `_DSC_URL`**

```diff
-	dget -u http://deb.debian.org/debian/pool/main/i/isc-dhcp/isc-dhcp_$(ISC_DHCP_VERSION_FULL).dsc
+	dget -u $(ISC_DHCP_DSC_URL)
```

```diff
-	# resolute: bind 9.11.36 (vendored in isc-dhcp) link error with -flto=auto:
-	# libisc.a has the symbols (T) but svtest/dhclient link reports undefined
-	# reference. Disable LTO for this package (CFLAGS + LDFLAGS).
-	export DEB_CFLAGS_MAINT_STRIP="-flto=auto -ffat-lto-objects"
-	export DEB_LDFLAGS_MAINT_STRIP="-flto=auto -ffat-lto-objects"
-
```

删除是安全的：同样的 strip 现在由 series 里的 `0019` 补丁写进 `debian/rules`，本地自建与 PPA 构建都会生效。这一步同时消除了「两个地方各写一份 LTO 处理」的漂移。

- [ ] **Step 6：改 `rules/isc-dhcp.mk`**

```make
# isc-dhcp packages

ISC_DHCP_VERSION = 4.4.3-P1
ISC_DHCP_VERSION_STOCK = ${ISC_DHCP_VERSION}-2
ISC_DHCP_VERSION_FULL = $(ISC_DHCP_VERSION_STOCK)$(call ppa_ver,isc-dhcp)

ISC_DHCP_DSC_URL = http://deb.debian.org/debian/pool/main/i/isc-dhcp/isc-dhcp_$(ISC_DHCP_VERSION_STOCK).dsc

export ISC_DHCP_VERSION ISC_DHCP_VERSION_FULL ISC_DHCP_VERSION_STOCK ISC_DHCP_DSC_URL
```

即：原 `ISC_DHCP_VERSION_FULL = ${ISC_DHCP_VERSION}-2` 一行改成两行，插入 `_DSC_URL`，并把两个新变量加进已有的 `export` 行。

注册处：

```diff
-SONIC_MAKE_DEBS += $(ISC_DHCP_RELAY)
+ifneq ($(filter isc-dhcp,$(SONIC_PPA_PACKAGES)),)
+SONIC_ONLINE_DEBS += $(ISC_DHCP_RELAY)
+else
+SONIC_MAKE_DEBS += $(ISC_DHCP_RELAY)
+endif
```

在 `add_derived_package` 调用之后（`export ISC_DHCP_RELAY ISC_DHCP_RELAY_DBG` 之前）插入：

```make
# PPA 模式:主包与 dbgsym 各自的下载地址。必须位于 add_derived_package 之后。
ifneq ($(filter isc-dhcp,$(SONIC_PPA_PACKAGES)),)
$(ISC_DHCP_RELAY)_URL     = $(call ppa_url,isc-dhcp,$(ISC_DHCP_RELAY))
$(ISC_DHCP_RELAY_DBG)_URL = $(call ppa_url,isc-dhcp,$(ISC_DHCP_RELAY_DBG))
endif
```

- [ ] **Step 7：改 `rules/isc-dhcp.dep`（两行插入）**

```diff
 DEP_FILES   += $(SONIC_COMMON_BASE_FILES_LIST)
+ifeq ($(filter isc-dhcp,$(SONIC_PPA_PACKAGES)),)
 DEP_FILES   += $(shell git ls-files $(SPATH))
+endif
```

- [ ] **Step 8：跑 make 层测试确认通过**

```bash
./scripts/ppa/tests/run-tests.sh
```

期望：退出码 0，两个测试均 `all assertions passed`。

- [ ] **Step 9：产出源码包并在干净 chroot 里构建**

```bash
make sonic-slave-run SONIC_RUN_CMDS="scripts/ppa/build-source.sh isc-dhcp"
./scripts/ppa/tests/test-build-source.sh isc-dhcp
./scripts/ppa/build-clean.sh isc-dhcp
```

期望：测试脚本报 `ok   18 SONiC patches appended in order`（17 个原有 + 新增的 `0019`）；`build-clean.sh` 构建成功，`target/source/isc-dhcp/build/` 下有 `isc-dhcp-relay_*.deb` 与 `isc-dhcp-relay-dbgsym_*.ddeb`。**这是本任务的核心验收点** —— 若 `0019` 没生效，构建会在链接 `svtest` / `dhclient` 时报 undefined reference 而失败。

- [ ] **Step 10：确认本地自建路径未回归**

```bash
make sonic-slave-run SONIC_RUN_CMDS="rm -f target/debs/resolute/isc-dhcp-relay_* && make target/debs/resolute/isc-dhcp-relay_4.4.3-P1-2_amd64.deb"
```

期望：构建成功。这一步证实把 LTO strip 从 Makefile 挪到 `debian/rules` 之后，本地自建路径同样得到该修复。

- [ ] **Step 11：提交**

```bash
git add src/isc-dhcp/patch/ src/isc-dhcp/Makefile rules/isc-dhcp.mk rules/isc-dhcp.dep scripts/ppa/tests/rules_test.mk
git commit -m "build(isc-dhcp): move the LTO strip into debian/rules, wire for PPA

The two DEB_*_MAINT_STRIP exports lived in src/isc-dhcp/Makefile around
dpkg-buildpackage. A Launchpad builder only sees the source package, so a
generated .dsc would fail to link the vendored bind 9.11.36 exactly the way
it did before the workaround existed. Patch 0019 puts the same strip into
debian/rules, which makes it apply to the local build too and removes the
duplicate handling.

isc-dhcp is in the first batch precisely because it is the guaranteed-failure
case: 17 existing patches (highest fuzz risk) and a Debian source uploaded to
an Ubuntu PPA.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Task 5：lm-sensors（内化 `PROG_EXTRA=sensord`）

`lm-sensors` 是「构建成功但产物错」类的唯一代表：`src/lm-sensors/Makefile:31` 的 `PROG_EXTRA=sensord` 是上游 lm-sensors 的构建变量，决定 `sensord` 这个程序**是否被编译**。丢了它不会报错 —— `debian/control` 里 `sensord` 二进制包依然存在（由已有的 `0001` 补丁添加），只是里面的可执行文件缺失或整包构建失败，而 `docker-platform-monitor` 需要它。

**文件：**
- 新建：`src/lm-sensors/patch/0003-build-sensord-via-prog-extra.patch`
- 修改：`src/lm-sensors/patch/series`
- 修改：`rules/lm-sensors.mk`
- 修改：`rules/lm-sensors.dep`
- 修改：`src/lm-sensors/Makefile`（第 16 行改用 `_DSC_URL`；第 31 行去掉 `PROG_EXTRA=`）
- 修改：`scripts/ppa/tests/rules_test.mk`（加 lm-sensors 断言）

**接口：**
- 消费：Task 1 的函数、Task 2 的形态
- 产出：`LM_SENSORS_VERSION_STOCK` = `3.6.2-2build1`、`LM_SENSORS_DSC_URL`

- [ ] **Step 1：写失败的断言**

在 `scripts/ppa/tests/rules_test.mk` 里把 `SONIC_PPA_PACKAGES` 改为 `libteam isc-dhcp lm-sensors`，加 `include rules/lm-sensors.mk`，并追加：

```make
$(call assert,lmsensors-stock-ver,$(LM_SENSORS_VERSION_STOCK),3.6.2-2build1)
$(call assert,lmsensors-main-name,$(LM_SENSORS),lm-sensors_3.6.2-2build1+sonic1~ppa1_amd64.deb)
$(call assert,lmsensors-dsc-url,$(LM_SENSORS_DSC_URL),http://archive.ubuntu.com/ubuntu/pool/main/l/lm-sensors/lm-sensors_3.6.2-2build1.dsc)
$(call assert,lmsensors-sensord-url,$($(SENSORD)_URL),https://ppa.launchpadcontent.net/o/n/ubuntu/pool/main/l/lm-sensors/sensord_3.6.2-2build1+sonic1~ppa1_amd64.deb)
$(call assert,lmsensors-fancontrol-url,$($(FANCONTROL)_URL),https://ppa.launchpadcontent.net/o/n/ubuntu/pool/main/l/lm-sensors/fancontrol_3.6.2-2build1+sonic1~ppa1_all.deb)
```

`fancontrol` 那条同时验证 `Arch: all` 的文件名路径（`_all.deb` 而非 `_amd64.deb`）。

- [ ] **Step 2：跑测试确认失败**

```bash
./scripts/ppa/tests/run-tests.sh
```

期望：`rules_test` 退出码 1，含 `FAIL lmsensors-stock-ver: got "" want "3.6.2-2build1"` 等五条。

- [ ] **Step 3：造内化 `PROG_EXTRA` 的补丁**

先看 stock `debian/rules` 长什么样：

```bash
make sonic-slave-run SONIC_RUN_CMDS="bash -c 'cd /tmp && dget -u http://archive.ubuntu.com/ubuntu/pool/main/l/lm-sensors/lm-sensors_3.6.2-2build1.dsc && grep -nE \"PROG_EXTRA|^export|dh_auto_build|^%:\" lm-sensors-3.6.2/debian/rules\'"
```

若 stock `debian/rules` 已有 `export` 段就插在其后，否则插在 `#!/usr/bin/make -f` 之后。用 `quilt new 0003-build-sensord-via-prog-extra.patch` + `quilt add debian/rules` + 编辑 + `quilt refresh` 生成，内容为：

```make
# SONiC: lm-sensors' upstream build only compiles sensord when PROG_EXTRA
# names it. The sensord binary package is added by patch 0001, but without
# this the program itself is never built. This used to be an environment
# variable in src/lm-sensors/Makefile, which a Launchpad builder cannot see.
export PROG_EXTRA = sensord
```

把生成的补丁文件放进 `src/lm-sensors/patch/`，并在 `src/lm-sensors/patch/series` 末尾追加：

```
0003-build-sensord-via-prog-extra.patch
```

- [ ] **Step 4：改 `src/lm-sensors/Makefile`**

```diff
-	dget -u http://archive.ubuntu.com/ubuntu/pool/main/l/lm-sensors/lm-sensors_$(LM_SENSORS_VERSION_FULL).dsc
+	dget -u $(LM_SENSORS_DSC_URL)
```

```diff
-	DEB_BUILD_OPTIONS=nocheck DEB_BUILD_PROFILES=nocheck PROG_EXTRA=sensord dpkg-buildpackage -us -uc -b -j$(SONIC_CONFIG_MAKE_JOBS) --admindir $(SONIC_DPKG_ADMINDIR)
+	DEB_BUILD_OPTIONS=nocheck DEB_BUILD_PROFILES=nocheck dpkg-buildpackage -us -uc -b -j$(SONIC_CONFIG_MAKE_JOBS) --admindir $(SONIC_DPKG_ADMINDIR)
```

`PROG_EXTRA=` 从命令行去掉，因为它现在由 `0003` 补丁写进 `debian/rules`。`DEB_BUILD_OPTIONS=nocheck` **保留不动** —— 它只影响本地自建；Launchpad builder 上测试会真跑，这是刻意接受的（若测试在 builder 上失败，届时再决定是加 `nocheck` 补丁还是修测试，本任务不预判）。

同理修改上方 `CROSS_BUILD_ENVIRON` 分支里的 `PROG_EXTRA=sensord`（第 29 行）。

- [ ] **Step 5：改 `rules/lm-sensors.mk`**

```make
LM_SENSORS_VERSION=$(LM_SENSORS_MAJOR_VERSION).$(LM_SENSORS_MINOR_VERSION).$(LM_SENSORS_PATCH_VERSION)
LM_SENSORS_VERSION_STOCK=$(LM_SENSORS_VERSION)-2build1
LM_SENSORS_VERSION_FULL=$(LM_SENSORS_VERSION_STOCK)$(call ppa_ver,lm-sensors)

LM_SENSORS_DSC_URL=http://archive.ubuntu.com/ubuntu/pool/main/l/lm-sensors/lm-sensors_$(LM_SENSORS_VERSION_STOCK).dsc
```

注册处：

```diff
-SONIC_MAKE_DEBS += $(LM_SENSORS)
+ifneq ($(filter lm-sensors,$(SONIC_PPA_PACKAGES)),)
+SONIC_ONLINE_DEBS += $(LM_SENSORS)
+$(LM_SENSORS)_URL     = $(call ppa_url,lm-sensors,$(LM_SENSORS))
+$(LM_SENSORS_DBG)_URL = $(call ppa_url,lm-sensors,$(LM_SENSORS_DBG))
+$(FANCONTROL)_URL     = $(call ppa_url,lm-sensors,$(FANCONTROL))
+$(LIBSENSORS)_URL     = $(call ppa_url,lm-sensors,$(LIBSENSORS))
+$(LIBSENSORS_DBG)_URL = $(call ppa_url,lm-sensors,$(LIBSENSORS_DBG))
+$(SENSORD)_URL        = $(call ppa_url,lm-sensors,$(SENSORD))
+$(SENSORD_DBG)_URL    = $(call ppa_url,lm-sensors,$(SENSORD_DBG))
+else
+SONIC_MAKE_DEBS += $(LM_SENSORS)
+endif
```

这里 URL 覆盖可以和注册写在同一个块里，因为 `rules/lm-sensors.mk` 的 `SONIC_MAKE_DEBS += $(LM_SENSORS)` 本来就在所有 `add_derived_package` 调用之后。

把 `LM_SENSORS_VERSION_STOCK` 与 `LM_SENSORS_DSC_URL` 加进文件末尾的 `export` 列表。

- [ ] **Step 6：改 `rules/lm-sensors.dep`（两行插入）**

```diff
 DEP_FILES   += $(SONIC_COMMON_BASE_FILES_LIST)
+ifeq ($(filter lm-sensors,$(SONIC_PPA_PACKAGES)),)
 DEP_FILES   += $(shell git ls-files $(SPATH))
+endif
```

- [ ] **Step 7：跑 make 层测试确认通过**

```bash
./scripts/ppa/tests/run-tests.sh
```

期望：退出码 0。

- [ ] **Step 8：产出源码包，干净 chroot 构建，并验证 `sensord` 真的在**

```bash
make sonic-slave-run SONIC_RUN_CMDS="scripts/ppa/build-source.sh lm-sensors"
./scripts/ppa/tests/test-build-source.sh lm-sensors
./scripts/ppa/build-clean.sh lm-sensors
B=target/source/lm-sensors/build
ls -1 "$B"/sensord_3.6.2-2build1+sonic1~ppa1_amd64.deb
dpkg -c "$B"/sensord_3.6.2-2build1+sonic1~ppa1_amd64.deb | grep -E 'usr/sbin/sensord$'
```

期望：测试脚本报 `ok   3 SONiC patches appended in order`；`build-clean.sh` 在 `target/source/lm-sensors/build/` 下产出 7 个产物；`sensord_*.deb` 存在；`dpkg -c` 输出含 `usr/sbin/sensord`。**这是本任务的核心验收点** —— 若 `0003` 没生效，`sensord` 可执行文件不会出现，而构建可能仍然「成功」。

- [ ] **Step 9：对比本地自建产物，验收标准第 2 项**

```bash
make sonic-slave-run SONIC_RUN_CMDS="rm -f target/debs/resolute/sensord_* && make target/debs/resolute/lm-sensors_3.6.2-2build1_amd64.deb"
B=target/source/lm-sensors/build
dpkg -c target/debs/resolute/sensord_3.6.2-2build1_amd64.deb        | awk '{print $NF}' | sort > /tmp/local.list
dpkg -c "$B"/sensord_3.6.2-2build1+sonic1~ppa1_amd64.deb            | awk '{print $NF}' | sort > /tmp/clean.list
diff -u /tmp/local.list /tmp/clean.list && echo "file lists identical"
```

期望：`diff` 无输出，打印 `file lists identical`。这一步同时证实把 `PROG_EXTRA` 从 Makefile 挪进 `debian/rules` 之后本地路径未回归。

- [ ] **Step 10：提交**

```bash
git add src/lm-sensors/patch/ src/lm-sensors/Makefile rules/lm-sensors.mk rules/lm-sensors.dep scripts/ppa/tests/rules_test.mk
git commit -m "build(lm-sensors): move PROG_EXTRA=sensord into debian/rules, wire for PPA

PROG_EXTRA=sensord was an environment variable on the dpkg-buildpackage
command line, so a Launchpad builder never sees it. Patch 0001 already adds
the sensord binary package to debian/control, which makes this the one
silent-failure shape in the whole migration: the build succeeds and the deb
list looks right, but /usr/sbin/sensord is absent — and
docker-platform-monitor needs it. Patch 0003 sets it in debian/rules
instead, so both the local build and the PPA build get it.

DEB_BUILD_OPTIONS=nocheck is left on the local command line on purpose. It
only affects local builds; the builder will run the test suite, and if that
fails we will decide then whether to patch in nocheck or fix the tests.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Task 6：`manifest.sh` + `sign-upload.sh`

**文件：**
- 新建：`scripts/ppa/manifest.sh`
- 新建：`scripts/ppa/sign-upload.sh`
- 修改：`slave.mk`（加 `ppa-manifest` phony 目标）

**接口：**
- 消费：`scripts/ppa/query.mk`、`target/source/<pkg>/*_source.changes`
- 产出：`make ppa-manifest` 状态表；`scripts/ppa/sign-upload.sh --dry-run` 可在无 PPA 归属时验证

- [ ] **Step 1：写失败的测试**

```bash
./scripts/ppa/manifest.sh
```

期望：`bash: ./scripts/ppa/manifest.sh: No such file or directory`，退出码 127。

- [ ] **Step 2：写 `scripts/ppa/manifest.sh`**

新建（`chmod +x`）：

```bash
#!/bin/bash
# 打印每个 PPA 候选包的状态表。取代「另建一份 YAML 好一眼看全」的做法：
# 本表 100% 由 rules/*.mk 推导,是产物而非真相,因此不会漂移。
#
# 用法: scripts/ppa/manifest.sh [<pkg>...]     不给参数则列出所有已声明 _DSC_URL 的包
set -euo pipefail
cd "$(dirname "$0")/../.."

pkgs=("$@")
if [ ${#pkgs[@]} -eq 0 ]; then
    mapfile -t pkgs < <(grep -l '_DSC_URL' rules/*.mk | sed 's|rules/||; s|\.mk$||' | sort)
fi

printf '%-14s %-6s %-24s %-14s %s\n' PACKAGE MODE STOCK-VERSION SUFFIX DEBS
for p in "${pkgs[@]}"; do
    while IFS='=' read -r k v; do declare "Q_$k=$v"; done \
        < <(make -s -f scripts/ppa/query.mk PKG="$p")
    ndebs=$(( 1 + $(echo "$Q_DERIVED_DEBS" | wc -w) ))
    printf '%-14s %-6s %-24s %-14s %s\n' \
        "$Q_PKG" "$Q_MODE" "$Q_STOCK_VERSION" "$Q_SUFFIX" "$ndebs"
    if [ "${VERBOSE:-}" = "1" ]; then
        for d in $Q_MAIN_DEB $Q_DERIVED_DEBS; do
            printf '    %s\n' "$d"
        done
    fi
done
```

- [ ] **Step 3：加 `slave.mk` 目标**

在 `slave.mk` 的 phony 目标区（`SONIC_TARGET_LIST` 定义附近，任何位置均可，只需在文件顶层）插入：

```make
# 打印 PPA 候选包状态表。数据全部来自 rules/*.mk,经 scripts/ppa/query.mk 提取。
.PHONY: ppa-manifest
ppa-manifest:
	$(Q)scripts/ppa/manifest.sh
```

- [ ] **Step 4：跑测试确认通过**

```bash
chmod +x scripts/ppa/manifest.sh
./scripts/ppa/manifest.sh
```

期望（`SONIC_PPA_PACKAGES` 为空时全部 local）：

```
PACKAGE        MODE   STOCK-VERSION            SUFFIX         DEBS
isc-dhcp       local  4.4.3-P1-2               +sonic1~ppa1   2
libteam        local  1.31-1build4             +sonic1~ppa1   7
lm-sensors     local  3.6.2-2build1            +sonic1~ppa1   7
```

再确认按包切换生效：

```bash
SONIC_PPA_PACKAGES=libteam ./scripts/ppa/manifest.sh
```

期望：`libteam` 行的 `MODE` 变为 `ppa`，其余两行仍为 `local`。

- [ ] **Step 5：写 `scripts/ppa/sign-upload.sh`**

新建（`chmod +x`）：

```bash
#!/bin/bash
# 在宿主机上签名（并可选上传）由 build-source.sh 产出的源码包。
#
# 刻意不在容器内进行：把 GPG agent socket 挂进 DinD 容器代价高且脆弱。
# 需要宿主机装有 devscripts（debsign）与 dput。
#
# 用法:
#   scripts/ppa/sign-upload.sh --key <KEYID> [<pkg>...]            只签名
#   scripts/ppa/sign-upload.sh --key <KEYID> --upload ppa:o/n ...  签名并上传
#   scripts/ppa/sign-upload.sh --dry-run [<pkg>...]                只列出会做什么
set -euo pipefail
cd "$(dirname "$0")/../.."

KEY=""; PPA=""; DRY=0
while [ $# -gt 0 ]; do
    case "$1" in
        --key)     KEY="$2"; shift 2 ;;
        --upload)  PPA="$2"; shift 2 ;;
        --dry-run) DRY=1; shift ;;
        *)         break ;;
    esac
done

pkgs=("$@")
if [ ${#pkgs[@]} -eq 0 ]; then
    mapfile -t pkgs < <(find target/source -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
fi
[ ${#pkgs[@]} -gt 0 ] || { echo "nothing in target/source/; run build-source.sh first" >&2; exit 1; }

for p in "${pkgs[@]}"; do
    changes=$(ls "target/source/$p"/*_source.changes 2>/dev/null | head -1) || true
    [ -n "$changes" ] || { echo "$p: no _source.changes; run build-source.sh first" >&2; exit 1; }

    if [ "$DRY" = 1 ]; then
        echo "would debsign${KEY:+ -k $KEY} $changes"
        [ -n "$PPA" ] && echo "would dput $PPA $changes"
        continue
    fi

    [ -n "$KEY" ] || { echo "--key is required unless --dry-run" >&2; exit 2; }
    debsign -k "$KEY" "$changes"
    echo "signed $changes"

    if [ -n "$PPA" ]; then
        dput "$PPA" "$changes"
        echo "uploaded $changes -> $PPA"
    fi
done
```

- [ ] **Step 6：验证 dry-run（无需 PPA 归属）**

```bash
chmod +x scripts/ppa/sign-upload.sh
./scripts/ppa/sign-upload.sh --dry-run
```

期望：为 `target/source/` 下每个包各打印一行 `would debsign target/source/<pkg>/<src>_<ver>_source.changes`，退出码 0。传入 `--upload ppa:o/n` 时每包多一行 `would dput`。

- [ ] **Step 7：提交**

```bash
git add scripts/ppa/manifest.sh scripts/ppa/sign-upload.sh slave.mk
git commit -m "build(ppa): add the status table and the host-side sign/upload step

make ppa-manifest prints one row per candidate package (mode, stock version,
effective suffix, deb count), derived entirely from rules/*.mk via query.mk.
This is what replaces 'keep a YAML so you can see everything at once': the
table is an artifact rather than a source of truth, so it cannot drift.

sign-upload.sh runs on the host because mounting the GPG agent socket into a
DinD container is expensive and fragile. --dry-run makes the whole path
verifiable before the PPA ownership question is settled.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## 完成后仍未做的事

以下依赖 PPA 归属决定（设计 §10），不在本计划范围：

- 真正上传，以及验收标准第 2–4 项的端到端验证（`dpkg -c` 对比 PPA 产物、二进制包集合对比、整镜像构建）。
- 确认 PPA 的 debug symbols 发布开关能否打开。若不能，按 `rules/lldpd.mk` 的现成做法把 dbgsym 从 `SONIC_ONLINE_DEBS` 里摘掉但保留变量定义。
- `socat` 的 readline 授权判断（设计 §8）。
- 第二批：从 `libyang3` 开始（树外动作最多的包）。


---

## 实现结果（2026-07-29 回填）

本计划已在 `202605_resolute_ppa` 上执行完毕，34 个提交，六个任务全部通过任务级 review 与全分支终审。**上面各步骤里的代码块是执行前的方案，不是最终落地的代码** —— 执行过程中在计划自己的代码里发现并修掉了若干真实缺陷，最终形态以 `scripts/ppa/`、`rules/ppa-functions` 和[设计文档](../specs/2026-07-28-sonic-ppa-source-packages-design-zh.md)为准（设计文档已同步）。

计划与落地的主要差异：

| 计划里写的 | 实际落地 | 原因 |
|---|---|---|
| 函数追加进 `rules/functions` | 新建 `rules/ppa-functions` | `Makefile.cache:110` 把 `rules/functions` 列入 `SONIC_COMMON_FILES_LIST`，动它会让全部 267 个缓存目标在所有发行版上 cache key 失效 |
| `dget -u` | `dget -d -u` + `dpkg-source --skip-patches -x` | `dget -u` 会预先应用上游自带的 quilt 补丁 |
| 整个 series 追加进 `debian/patches/series` | 按 `debian/`-only / upstream-only / mixed 分类（新增 `scripts/ppa/patch-class.sh`） | 改 `debian/` 的补丁在 builder 端会被二次应用 |
| 各脚本各自读 `query.mk` | 抽出 `scripts/ppa/query-pkg.sh` | 重复三份导致同一缺陷只修了一处，而漏掉的那处会把 A 包的源码包搬进 B 包目录并退出 0 |
| 断言 `.pc` 不存在 | 断言 plain `dpkg-source -x` 零 fuzz 成功 | 原断言永真 |
| 首批仅需内化各包 Makefile 里的动作 | isc-dhcp 还需 `-std=gnu17`；lm-sensors 还需 `librrd-dev` | slave 镜像的全局 `buildflags.conf` 与预装 build-dep 都不会跟到 builder |

新增的测试套件共 7 个（`scripts/ppa/tests/run-tests.sh` 一次跑完）。
