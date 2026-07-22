# Resolute Broadcom → dell/XGS-only 裁剪 — 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: 用 superpowers:subagent-driven-development(推荐)或 superpowers:executing-plans 逐任务执行。步骤用复选框(`- [ ]`)跟踪。

**目标:** 把 resolute Broadcom 平台收敛到 dell(全系 XGS)—— 去掉 DNX/Jericho + legacy-Tomahawk kmod 与 17 个非-dell 厂商 kmod overlay —— 以一个加法 commit 落到 `202605_resolute_sheldon`,并把 review stack 的 `pr08` 同步重写成匹配的 2-commit。

**架构:** 这是 git 手术,不是应用代码。目标 A(`202605_resolute_sheldon`,主构建树 `/home/sheldon-qi/sonic-buildimage-resolute`)顶上加一个 trim commit。目标 B(`202605_resolute_pr08`,worktree `/home/sheldon-qi/sonic-buildimage-resolute-reorg`)从 `pr07` 重建 + 2 个 commit,其 broadcom 子树从裁剪后的 sheldon checkout,使两树仅差 `rules/config.user`。Spec:`docs/superpowers/specs/2026-07-22-resolute-broadcom-dell-xgs-trim-zh.md`。

**技术栈:** git(worktree、`checkout <ref> -- path`、`rm`、`commit -S`)、quilt 0.69、SONiC `slave.mk` 构建(`make -f Makefile.work`、`BLDENV=resolute`)、GPG 签名。

## 全局约束

- **不 push、不建 PR。** review 前全部只在本地。(spec §8)
- **每个 commit 都 GPG 签名**(`commit.gpgsign=true` 已开;身份 `Sheldon Qi <sheldon.qi@canonical.com>`)。Trailer:`Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`。
- **只显式 stage `platform/broadcom/…` 路径。绝不 `git add -A`/`git add .`** —— 主树带着无关的构建产物、`rules/config.user`、脏 submodule gitlink(如 frr),它们绝不能进任何 commit。(spec §5.1)
- **`rules/config.user` 绝不提交。**
- **不动 `AGENTS.md`。**
- **机制规则(spec §3.4):** `saibcm-modules` 是子模块 → 保留 `.patch/` overlay。`dell`/`sswsyncd` 是在树源码 → 直接改源码(不用 overlay)。拉取型源(bash/socat/grub)不动。
- **终态不变式:** `git diff 202605_resolute_pr08 202605_resolute_sheldon` 只打印 `rules/config.user`。

---

### 任务 1:预检 —— 备份 + 保证干净 index

**文件:** 不改动(仅安全)。

**接口:**
- 产出:备份 ref `202605_resolute_sheldon_pretrim`、`202605_resolute_pr08_pretrim`;记录 tip 供回滚。

- [ ] **步骤 1:记录当前 tip、确认分支**

运行:
```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
git rev-parse --abbrev-ref HEAD                 # 期望:202605_resolute_sheldon
git rev-parse --short 202605_resolute_sheldon
git -C /home/sheldon-qi/sonic-buildimage-resolute-reorg rev-parse --abbrev-ref HEAD
git rev-parse --short 202605_resolute_pr07 202605_resolute_pr08
```
期望:主树在 `202605_resolute_sheldon`(tip `d6cde25d1e` 或更新);`pr07`/`pr08` 存在。

- [ ] **步骤 2:建备份分支(回滚锚点)**

运行:
```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
git branch -f 202605_resolute_sheldon_pretrim 202605_resolute_sheldon
git branch -f 202605_resolute_pr08_pretrim   202605_resolute_pr08
git rev-parse --short 202605_resolute_sheldon_pretrim 202605_resolute_pr08_pretrim
```
期望:两个备份 ref 打印 SHA。(本地 `202605_resolute` @ `aa7fc4f76d` 是额外备份。)

- [ ] **步骤 3:保证主树 index 干净**

运行:
```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
git reset -q                       # 取消任何预 stage;不动工作树
git diff --cached --name-only      # 必须为空
```
期望:`git diff --cached --name-only` 无输出。若有输出,停下排查 —— 任务 2 假定 index 从空开始,只有我们显式 add 的内容才进 commit。

- [ ] **步骤 4:确认上游 ref + quilt 可用**

运行:
```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
git rev-parse --verify sonic-net/202605 >/dev/null && echo "sonic-net/202605 OK"
command -v quilt && quilt --version
```
期望:`sonic-net/202605 OK` 且 `quilt` `0.69`。

*(不 commit —— 仅预检。)*

---

### 任务 2:目标 A —— 在 `202605_resolute_sheldon` 顶上加 trim commit

**文件(全在 `platform/broadcom/` 下):**
- 覆写:`rules.mk`
- 修改:`sai-modules.mk`、`one-image.mk`
- 在树源码直接改:`sonic-platform-modules-dell/**`(就地应用 overlay)
- 删除:`sonic-platform-modules-dell.patch/`、`saibcm-modules-dnx.patch/`、`saibcm-modules-legacy-th.patch/`,以及 17 个 `sonic-platform-modules-{accton,alphanetworks,arista,cel,delta,ingrasys,inventec,juniper,micas,mitac,nexthop,nokia,quanta,ragile,ruijie,tencent,ufispace}.patch/`
- 还原上游:`docker-pde.mk`、`docker-saiserver-brcm.mk`、`docker-syncd-brcm-dnx.mk`、`docker-syncd-brcm-legacy-th.mk`、`docker-syncd-brcm-dnx/Dockerfile.j2`、`docker-syncd-brcm-legacy-th/Dockerfile.j2`、`docker-saiserver-brcm/Dockerfile.j2`
- 不动(保留的 resolute delta):`saibcm-modules.patch/`、`sswsyncd/debian/rules`、`docker-syncd-brcm/Dockerfile.j2`

**接口:**
- 消费:任务 1 的备份 ref + 干净 index。
- 产出:`202605_resolute_sheldon` 前进一个 commit,broadcom 子树变为 dell/XGS-only。后续任务(`pr08`)从此 tip checkout `platform/broadcom/**`。

- [ ] **步骤 1:删除要丢弃的 overlay(dnx、legacy-th、17 个非-dell 厂商)**

运行:
```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
git rm -r --quiet \
  platform/broadcom/saibcm-modules-dnx.patch \
  platform/broadcom/saibcm-modules-legacy-th.patch \
  platform/broadcom/sonic-platform-modules-accton.patch \
  platform/broadcom/sonic-platform-modules-alphanetworks.patch \
  platform/broadcom/sonic-platform-modules-arista.patch \
  platform/broadcom/sonic-platform-modules-cel.patch \
  platform/broadcom/sonic-platform-modules-delta.patch \
  platform/broadcom/sonic-platform-modules-ingrasys.patch \
  platform/broadcom/sonic-platform-modules-inventec.patch \
  platform/broadcom/sonic-platform-modules-juniper.patch \
  platform/broadcom/sonic-platform-modules-micas.patch \
  platform/broadcom/sonic-platform-modules-mitac.patch \
  platform/broadcom/sonic-platform-modules-nexthop.patch \
  platform/broadcom/sonic-platform-modules-nokia.patch \
  platform/broadcom/sonic-platform-modules-quanta.patch \
  platform/broadcom/sonic-platform-modules-ragile.patch \
  platform/broadcom/sonic-platform-modules-ruijie.patch \
  platform/broadcom/sonic-platform-modules-tencent.patch \
  platform/broadcom/sonic-platform-modules-ufispace.patch
echo "deleted overlays: $(git diff --cached --name-only | grep -cE '\.patch/series$') series files"
```
期望:`19` 个 series 文件被 stage 为删除。

- [ ] **步骤 2:把 4 个 docker `.mk` + 3 个 Dockerfile.j2 还原上游**

运行:
```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
git checkout sonic-net/202605 -- \
  platform/broadcom/docker-pde.mk \
  platform/broadcom/docker-saiserver-brcm.mk \
  platform/broadcom/docker-syncd-brcm-dnx.mk \
  platform/broadcom/docker-syncd-brcm-legacy-th.mk \
  platform/broadcom/docker-syncd-brcm-dnx/Dockerfile.j2 \
  platform/broadcom/docker-syncd-brcm-legacy-th/Dockerfile.j2 \
  platform/broadcom/docker-saiserver-brcm/Dockerfile.j2
git diff --cached --name-only | grep -E 'docker-(pde|saiserver-brcm|syncd-brcm-dnx|syncd-brcm-legacy-th)'
```
期望:4 个 `.mk` + 3 个 `Dockerfile.j2` 作为 staged(已还原为上游内容)出现。

- [ ] **步骤 3:覆写 `rules.mk` 为 dell/XGS-only include 列表**

把 `platform/broadcom/rules.mk` 写为**完全如下**内容:
```makefile
include $(PLATFORM_PATH)/sai-modules.mk
include $(PLATFORM_PATH)/sai-xgs.mk
# resolute: DNX/Jericho + legacy-Tomahawk SAI dropped (no dell platform uses them)
#include $(PLATFORM_PATH)/sai-dnx.mk
#include $(PLATFORM_PATH)/sai-legacy-th.mk
include $(PLATFORM_PATH)/sswsyncd.mk
# resolute: dell is the only validated platform on Ubuntu 26.04; other vendor kmods disabled
#include $(PLATFORM_PATH)/platform-modules-nokia.mk
include $(PLATFORM_PATH)/platform-modules-dell.mk
#include $(PLATFORM_PATH)/platform-modules-arista.mk
#include $(PLATFORM_PATH)/platform-modules-nexthop.mk
#include $(PLATFORM_PATH)/platform-modules-ingrasys.mk
#include $(PLATFORM_PATH)/platform-modules-accton.mk
#include $(PLATFORM_PATH)/platform-modules-alphanetworks.mk
#include $(PLATFORM_PATH)/platform-modules-inventec.mk
#include $(PLATFORM_PATH)/platform-modules-cel.mk
#include $(PLATFORM_PATH)/platform-modules-delta.mk
#include $(PLATFORM_PATH)/platform-modules-quanta.mk
##include $(PLATFORM_PATH)/platform-modules-mitac.mk
#include $(PLATFORM_PATH)/platform-modules-juniper.mk
#include $(PLATFORM_PATH)/platform-modules-brcm-xlr-gts.mk
#include $(PLATFORM_PATH)/platform-modules-ruijie.mk
#include $(PLATFORM_PATH)/platform-modules-ragile.mk
#include $(PLATFORM_PATH)/platform-modules-supermicro.mk
#include $(PLATFORM_PATH)/platform-modules-tencent.mk
#include $(PLATFORM_PATH)/platform-modules-ufispace.mk
#include $(PLATFORM_PATH)/platform-modules-micas.mk
include $(PLATFORM_PATH)/docker-syncd-brcm.mk
# resolute: rpc/saiserver/dnx/legacy-th syncd containers dropped (test-only or non-XGS)
#include $(PLATFORM_PATH)/docker-syncd-brcm-rpc.mk
#include $(PLATFORM_PATH)/docker-saiserver-brcm.mk
#include $(PLATFORM_PATH)/docker-syncd-brcm-legacy-th.mk
#include $(PLATFORM_PATH)/docker-syncd-brcm-legacy-th-rpc.mk
ifeq ($(INCLUDE_PDE), y)
include $(PLATFORM_PATH)/docker-pde.mk
include $(PLATFORM_PATH)/sonic-pde-tests.mk
endif
include $(PLATFORM_PATH)/one-image.mk
include $(PLATFORM_PATH)/raw-image.mk
# resolute: one-aboot (Arista Aboot image) dropped — not dell; re-pulls dropped machines via DEPENDENT_MACHINE
#include $(PLATFORM_PATH)/one-aboot.mk
include $(PLATFORM_PATH)/libsaithrift-dev.mk
#include $(PLATFORM_PATH)/docker-syncd-brcm-dnx.mk
#include $(PLATFORM_PATH)/docker-syncd-brcm-dnx-rpc.mk
ifeq ($(INCLUDE_GBSYNCD), y)
include $(PLATFORM_PATH)/../components/docker-gbsyncd-credo.mk
include $(PLATFORM_PATH)/../components/docker-gbsyncd-broncos.mk
include $(PLATFORM_PATH)/../components/docker-gbsyncd-agera2.mk
include $(PLATFORM_PATH)/../components/docker-gbsyncd-milleniob.mk
endif

BCMCMD = bcmcmd
$(BCMCMD)_URL = "$(BUILD_PUBLIC_URL)/20190307/bcmcmd"

DSSERVE = dsserve
$(DSSERVE)_URL = "$(BUILD_PUBLIC_URL)/20190307/dsserve"

SONIC_ONLINE_FILES += $(BCMCMD) $(DSSERVE)

SONIC_ALL += $(SONIC_ONE_IMAGE) \
             $(DOCKER_FPM)

# Inject brcm sai into syncd
$(SYNCD)_DEPENDS += $(BRCM_XGS_SAI) $(BRCM_XGS_SAI_DEV)
$(SYNCD)_UNINSTALLS += $(BRCM_XGS_SAI_DEV) $(BRCM_XGS_SAI)

ifeq ($(ENABLE_SYNCD_RPC),y)
# Remove the libthrift_0.11.0 dependency injected by rules/syncd.mk
$(SYNCD)_DEPENDS := $(filter-out $(LIBTHRIFT_DEV),$($(SYNCD)_DEPENDS))
$(SYNCD)_DEPENDS += $(LIBSAITHRIFT_DEV)
endif
```

- [ ] **步骤 4:改 `sai-modules.mk` —— 仅 XGS kmod**

把 `platform/broadcom/sai-modules.mk` 整个 body 替换为**完全如下**:
```makefile
# Broadcom SAI modules
# resolute: XGS kmod only — DNX/Jericho and legacy-Tomahawk kmods dropped
# (no dell platform uses them; see rules.mk).

BRCM_OPENNSL_KERNEL_VERSION = 15.2.0.0.0.0.0.0
BRCM_OPENNSL_KERNEL = opennsl-modules_$(BRCM_OPENNSL_KERNEL_VERSION)_amd64.deb
$(BRCM_OPENNSL_KERNEL)_SRC_PATH = $(PLATFORM_PATH)/saibcm-modules
$(BRCM_OPENNSL_KERNEL)_DEPENDS += $(LINUX_HEADERS) $(LINUX_HEADERS_COMMON)
$(BRCM_OPENNSL_KERNEL)_BUILD_ENV += PKG_NAME=$(BRCM_OPENNSL_KERNEL)
$(BRCM_OPENNSL_KERNEL)_MACHINE = broadcom
SONIC_DPKG_DEBS += $(BRCM_OPENNSL_KERNEL)
```
(即删除原第 11–31 行:`BRCM_DNX_OPENNSL_KERNEL` 与 `BRCM_LEGACY_TH_OPENNSL_KERNEL` 两块。)

- [ ] **步骤 5:改 `one-image.mk` —— 切断 DNX/legacy-TH**

在 `platform/broadcom/one-image.mk` 做两处编辑:

编辑 1 —— 把此行:
```makefile
$(SONIC_ONE_IMAGE)_DEPENDENT_MACHINE = broadcom-dnx broadcom-legacy-th
```
改为:
```makefile
# resolute: XGS-only image — DNX/Jericho + legacy-Tomahawk machine variants dropped
$(SONIC_ONE_IMAGE)_DEPENDENT_MACHINE =
```

编辑 2 —— 把此行:
```makefile
$(SONIC_ONE_IMAGE)_LAZY_BUILD_INSTALLS = $(BRCM_OPENNSL_KERNEL) $(BRCM_DNX_OPENNSL_KERNEL)
```
改为:
```makefile
$(SONIC_ONE_IMAGE)_LAZY_BUILD_INSTALLS = $(BRCM_OPENNSL_KERNEL)
```

- [ ] **步骤 6:stage 3 个编辑后的 `.mk`**

运行:
```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
git add platform/broadcom/rules.mk platform/broadcom/sai-modules.mk platform/broadcom/one-image.mk
```

- [ ] **步骤 7:把 dell overlay 就地应用进在树源码,然后删除 overlay**

运行:
```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
( cd platform/broadcom/sonic-platform-modules-dell \
    && QUILT_PATCHES=../sonic-platform-modules-dell.patch quilt push -a \
    && rm -rf .pc )
git rm -r --quiet platform/broadcom/sonic-platform-modules-dell.patch
git add platform/broadcom/sonic-platform-modules-dell
```
期望:quilt 打印 `Applying patch 0001…`、`0002…`、`0003…`,然后 `Now at patch …0003…`。无 `.rej` 文件。

- [ ] **步骤 8:验证 dell 源码已带上 3 处 API 修复(即"测试")**

运行:
```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
echo "-- gpio .set int (期望 1) --"; git diff --cached -- platform/broadcom/sonic-platform-modules-dell | grep -c '^+static int fpga_gpio_set'
echo "-- bin_attribute const (期望 4) --"; git diff --cached -- platform/broadcom/sonic-platform-modules-dell | grep -c '^+.*const struct bin_attribute \*bin_attr'
echo "-- irq_find_mapping (期望 1) --"; git diff --cached -- platform/broadcom/sonic-platform-modules-dell | grep -c '^+.*irq_find_mapping('
echo "-- control retarget (期望 >=1) --"; git diff --cached -- platform/broadcom/sonic-platform-modules-dell/debian/control | grep -c 'linux-sonic-headers-7.0.0-1002'
echo "-- 无残留 .rej/.pc --"; git status --porcelain platform/broadcom/sonic-platform-modules-dell | grep -E '\.rej|\.pc' || echo "clean"
```
期望:`1`、`4`、`1`、`>=1`、`clean`。

- [ ] **步骤 9:安全闸 —— 确认只有 broadcom 路径被 stage**

运行:
```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
git diff --cached --name-only | grep -v '^platform/broadcom/' && echo "!!! 有非 broadcom 被 stage —— 停" || echo "OK: 只有 platform/broadcom 被 stage"
git diff --cached --name-only | grep -c 'config.user' | grep -qx 0 && echo "OK: 无 config.user" || echo "!!! config.user 被 stage —— 停"
```
期望:`OK: 只有 platform/broadcom 被 stage` 且 `OK: 无 config.user`。任一失败则 `git reset` 排查。

- [ ] **步骤 10:提交(GPG 签名)**

运行:
```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
git commit -S -F - <<'EOF'
build(broadcom): scope resolute broadcom to dell/XGS — drop DNX/legacy-TH + non-dell vendor kmods

resolute validates only the dell platform family on Ubuntu 26.04, and all
dell platforms are XGS (TD/TH). The unified sonic-broadcom.bin otherwise
bundles DNX/Jericho and legacy-Tomahawk kmods (via one-image DEPENDENT_MACHINE
and the sai-modules.mk kmod defs) that no dell platform uses at runtime, plus
17 non-dell vendor kmod overlays that are unvalidated on 7.0 (10 already
disabled in rules.mk).

- rules.mk: dell/XGS-only include list (DNX/legacy-TH SAI, rpc/saiserver,
  aboot, and non-dell vendors commented out; SONIC_ONE_ABOOT_IMAGE dropped
  from SONIC_ALL).
- sai-modules.mk: XGS kmod only (DNX + legacy-TH kmod defs removed).
- one-image.mk: DEPENDENT_MACHINE emptied; LAZY_BUILD_INSTALLS -> XGS only.
- dell kmod Linux-7.0 fixes applied directly to the in-tree source
  (gpio .set void->int, sysfs bin_attribute const .read x4, irq_linear_revmap
  -> irq_find_mapping, debian/control kernel dep retarget); overlay removed.
- saibcm-modules stays a submodule + .patch overlay (kept).
- Dropped overlays (dnx, legacy-th, 17 vendors) removed; the 4 now-unused
  docker .mk + 3 Dockerfile.j2 reverted to upstream.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
git log -1 --format='%h %G? %s'
```
期望:一行,`%G?` = `G`(签名有效),subject 如上。记此 SHA 为 `SHELDON_TRIM`。

---

### 任务 3:验证裁剪后 sheldon 的构建图 + kmod/deb 构建

**文件:** 无(验证)。在主树用 resolute slave 镜像跑。

**接口:**
- 消费:`202605_resolute_sheldon` @ `SHELDON_TRIM`。
- 产出:确认裁剪后仍是可构建的 XGS/dell 图(动 `pr08` 前的闸)。

> **重要(执行中发现):** 下面每条 `make -f Makefile.work` 都必须显式带 `PLATFORM=broadcom`。`rules/config.user` 里有 `PLATFORM ?= vs`,否则会静默按 `vs` 平台构建(仓库根的 `.platform` 只喂 `CONFIGURED_PLATFORM`,不喂真正 gate 构建配方的 `PLATFORM`)。下面的命令已经带上了。

- [ ] **步骤 1:结构性 —— 依赖图里无 DNX/legacy-TH/非-dell 目标**

运行:
```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
BLDENV=resolute PLATFORM=broadcom make -f Makefile.work target/sonic-broadcom.bin SONIC_CONFIG_PRINT_DEPENDENCIES=y 2>&1 | tee /tmp/brcm_deps.txt | tail -5
echo "-- dnx/legacy-th 目标 (期望 0) --"; grep -cE 'opennsl-modules-(dnx|legacy-th)|broadcom-(dnx|legacy-th)|libsaibcm_(dnx|13\.2)' /tmp/brcm_deps.txt
echo "-- 非-dell 厂商 module deb (期望 0) --"; grep -cE 'platform-modules-(accton|arista|nokia|cel|nexthop|ufispace|micas|quanta|ingrasys)' /tmp/brcm_deps.txt
```
期望:两个计数都为 `0`。(若 print 目标在输出依赖前就报错,以步骤 2/3 作为闸,并注明。)

- [ ] **步骤 2:构建 XGS kmod deb(dell 的内核模块基座)**

运行:
```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
BLDENV=resolute PLATFORM=broadcom make -f Makefile.work target/debs/resolute/opennsl-modules_15.2.0.0.0.0.0.0_amd64.deb 2>&1 | tail -15
ls -l target/debs/resolute/opennsl-modules_15.2.0.0.0.0.0.0_amd64.deb
```
期望:`[ finished ] … opennsl-modules_…deb`,文件存在。

- [ ] **步骤 3:构建两个 dell 平台模块 deb(证明在树 dell 源码在 7.0 上能编,覆盖全部 3 处修复)**

运行:
```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
BLDENV=resolute PLATFORM=broadcom make -f Makefile.work target/debs/resolute/platform-modules-z9332f_1.1_amd64.deb 2>&1 | tail -20
BLDENV=resolute PLATFORM=broadcom make -f Makefile.work target/debs/resolute/platform-modules-z9864f_1.1_amd64.deb 2>&1 | tail -20
ls -l target/debs/resolute/platform-modules-z9332f_1.1_amd64.deb target/debs/resolute/platform-modules-z9864f_1.1_amd64.deb
```
期望:两个构建都完成,两个 deb 都存在。覆盖:`z9332f` 覆盖 bin_attribute-const(`mc24lc64t.c`)和 irq_find_mapping(`cls-i2c-mux-pca954x.c`)两处修复;`z9864f` 覆盖 gpio `.set` void→int 修复(`fpga_gpio.c`)。

- [ ] **步骤 4(可选):完整镜像**

运行:
```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
BLDENV=resolute PLATFORM=broadcom make -f Makefile.work target/sonic-broadcom.bin 2>&1 | tail -25
ls -l target/sonic-broadcom.bin
```
期望:产出 ONIE installer。耗时长;步骤 1–3 通过且时间紧则可跳过。

*(不 commit —— 仅验证。)*

---

### 任务 4:目标 B —— 同步重写 `pr08` = `pr07` + 2 commit

**文件(在 worktree `/home/sheldon-qi/sonic-buildimage-resolute-reorg`):** 重建分支 `202605_resolute_pr08`。broadcom 文件从 `202605_resolute_sheldon` @ `SHELDON_TRIM` checkout。

**接口:**
- 消费:裁剪后的 `202605_resolute_sheldon`;已有的 `202605_resolute_pr07`。
- 产出:`202605_resolute_pr08`,其树 == 裁剪后 sheldon 减 `rules/config.user`。

- [ ] **步骤 1:干净 worktree + 把 pr08 reset 回 pr07**

运行:
```bash
cd /home/sheldon-qi/sonic-buildimage-resolute-reorg
git status --porcelain | head        # 期望空(worktree 干净)
git checkout -q 202605_resolute_pr08
git rev-parse --short HEAD            # == 202605_resolute_pr08_pretrim
git reset -q --hard 202605_resolute_pr07
git rev-parse --short HEAD 202605_resolute_pr07   # 现在相等
```
期望:worktree 干净;reset 后 `pr08` == `pr07`。(旧 tip 已存为 `202605_resolute_pr08_pretrim` + reflog。)

- [ ] **步骤 2:commit 1 —— 核心 XGS 接线 + kmod + sswsyncd + syncd docker**

运行:
```bash
cd /home/sheldon-qi/sonic-buildimage-resolute-reorg
git checkout 202605_resolute_sheldon -- \
  platform/broadcom/rules.mk \
  platform/broadcom/sai-modules.mk \
  platform/broadcom/one-image.mk \
  platform/broadcom/saibcm-modules.patch \
  platform/broadcom/sswsyncd \
  platform/broadcom/docker-syncd-brcm
git diff --cached --name-only | grep -v '^platform/broadcom/' && echo "!!! 停" || echo "OK: 只有 broadcom 被 stage"
git commit -S -F - <<'EOF'
build(broadcom): saibcm-modules XGS Linux 7.0 kmod series + dell-only build wiring

XGS-only broadcom build wiring for Ubuntu 26.04 (Linux 7.0): rules.mk scoped
to dell/XGS, sai-modules.mk XGS kmod only, one-image.mk DEPENDENT_MACHINE
emptied. saibcm-modules (submodule) carries its Linux-7.0 kmod fixes as a
.patch/ overlay; sswsyncd debian/rules and the docker-syncd-brcm base image
retargeted to resolute.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
git log -1 --format='%h %G? %s'
```
期望:`OK: 只有 broadcom 被 stage`;签名 commit(`%G?`=`G`)。

- [ ] **步骤 3:commit 2 —— dell 在树源码(直接改,无 overlay)**

运行:
```bash
cd /home/sheldon-qi/sonic-buildimage-resolute-reorg
git checkout 202605_resolute_sheldon -- platform/broadcom/sonic-platform-modules-dell
git diff --cached --name-only | grep -v '^platform/broadcom/sonic-platform-modules-dell/' && echo "!!! 停" || echo "OK: 只有 dell 源码被 stage"
git commit -S -F - <<'EOF'
build(broadcom): dell platform kmods Linux 7.0 API-drift fixes (in-tree)

dell driver source edited in-tree (not a .patch overlay, per the in-tree
source convention): gpio_chip .set void->int (z9864f/fpga_gpio.c), sysfs
bin_attribute const .read x4 (mc24lc64t.c), irq_linear_revmap -> irq_find_mapping
(z9332f/cls-i2c-mux-pca954x.c), and debian/control kernel dep retarget to
linux-sonic 7.0.0-1002. See spec §9 for the kernel-version root cause.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
git log -1 --format='%h %G? %s'
```
期望:`OK: 只有 dell 源码被 stage`;签名 commit。

- [ ] **步骤 4:验证 broadcom 子树与 sheldon 完全一致(即"测试")**

运行:
```bash
cd /home/sheldon-qi/sonic-buildimage-resolute-reorg
git diff --name-only 202605_resolute_pr08 202605_resolute_sheldon -- platform/broadcom | tee /tmp/brcm_delta.txt
echo "broadcom delta 行数 (期望 0): $(wc -l < /tmp/brcm_delta.txt)"
```
期望:`0` —— `pr08` 的 broadcom 子树现与裁剪后 sheldon 完全一致。

---

### 任务 5:终态一致性校验 + 汇报

**文件:** 无。确认终态不变式;不 push。

- [ ] **步骤 1:整树不变式 —— pr08 vs sheldon 仅差 config.user**

运行:
```bash
cd /home/sheldon-qi/sonic-buildimage-resolute-reorg
git diff --name-only 202605_resolute_pr08 202605_resolute_sheldon | tee /tmp/final_delta.txt
echo "-- 非 config.user 差异(期望无)--"
grep -v '^rules/config.user$' /tmp/final_delta.txt && echo "!!! 意外差异 —— 排查" || echo "OK: 仅 rules/config.user 不同"
```
期望:`OK: 仅 rules/config.user 不同`。

- [ ] **步骤 2:签名 + commit 形态**

运行:
```bash
cd /home/sheldon-qi/sonic-buildimage-resolute-reorg
echo "-- pr08 = pr07 + 2 signed commit --"
git log --format='%h %G? %s' 202605_resolute_pr07..202605_resolute_pr08
cd /home/sheldon-qi/sonic-buildimage-resolute
echo "-- sheldon +1 signed commit --"
git log --format='%h %G? %s' 202605_resolute_sheldon_pretrim..202605_resolute_sheldon
```
期望:pr08 显示 2 个 commit(都 `%G?`=`G`);sheldon 显示 1 个 commit(`%G?`=`G`)。

- [ ] **步骤 3:汇报 —— 不 push**

向用户总结:sheldon trim SHA、pr08 两个 SHA、验证结果(依赖图干净、XGS kmod + z9332f deb 已建、不变式成立)。明确说明没有 push,且备份(`*_pretrim`、本地 `202605_resolute`)在。等 review 再谈 push。

*(不 commit。)*

---

## 回滚

- 撤 sheldon trim:`cd /home/sheldon-qi/sonic-buildimage-resolute && git reset --hard 202605_resolute_sheldon_pretrim`
- 撤 pr08 重写:`cd /home/sheldon-qi/sonic-buildimage-resolute-reorg && git reset --hard 202605_resolute_pr08_pretrim`
- 更深备份:本地分支 `202605_resolute` @ `aa7fc4f76d`。
- dell overlay 内容保存在 git 历史(备份 ref)里,若直接改的路子需回退可取回。

## 注意 / 坑

- **绝不 `git add -A`。** 主树有脏 submodule gitlink(frr 天生脏)和 `rules/config.user`;只放显式 `platform/broadcom/**` 路径。
- `git checkout <ref> -- <path>` 既还原工作树又 stage —— 任务 2.2 / 任务 4 那些步骤不需要另外 `git add`。
- 任务 2.7 的 quilt 应用必须零 `.rej`;若 fuzz/reject,说明 pristine dell 源码漂移了 —— 停,重新解码 hunk。
- 构建步骤在主树跑,docker build 期间会打印非致命的 `unable to normalize alternate object path …/.git/objects` 警告 —— 忽略(已知、无害;只丢镜像 git label)。
