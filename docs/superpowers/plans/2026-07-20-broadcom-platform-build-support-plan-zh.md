# Broadcom 平台构建支持实施计划(resolute / TH3 / 标准三套 bin)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `202605_resolute` 分支上让 `make PLATFORM=broadcom` 产出标准 `sonic-broadcom.bin`(含 XGS + DNX + legacy-th 三套 syncd 容器 + 三套 opennsl kmod)。

**Architecture:** 闭源只有 libsaibcm .deb + 诊断二进制(已 de-risk:依赖全是 `>=` 下界、下载可达);核心阻塞是开源的 opennsl 内核模块要重新对齐 resolute `linux-sonic 7.0.0-1002-sonic` 内核。三套 `saibcm-modules{,-dnx,-legacy-th}` 子模块各一份 quilt patch,改 `debian/rules` 的 ABI/路径推导 + `debian/control` 的硬编码 Depends,走 SONiC 构建图自带的 `<SRC_PATH>.patch/series` quilt apply 机制。验证分三里程碑递进:kmod → syncd 容器 → bin。

**Tech Stack:** GNU make(quilt patch + SONiC 构建图)、debhelper/dpkg(opennsl kmod 打包)、Docker(syncd 容器)、SONiC buildimage slave.mk 构建图。

**对应 spec:** `docs/superpowers/specs/2026-07-20-broadcom-platform-build-support-design-zh.md`

**双仓库约定:**
- 本计划文档落 doc 仓库 `/home/sheldon-qi/sonic-buildimage`(`202605_resolute_doc` 分支)
- 所有代码改动落 build 仓库 `/home/sheldon-qi/sonic-buildimage-resolute`(`202605_resolute` 分支)。下文"仓库"指 build 仓库,所有路径默认相对 build 仓库根。

## Global Constraints

(摘自 spec §2-§9,每个 task 的要求隐式包含本节)

- 目标内核:**resolute `linux-sonic 7.0.0-1002-sonic`**(`rules/linux-kernel.mk:32`,`KVERSION=7.0.0-1002-sonic`)。ABI 串 `7.0.0-1002-sonic` 不含 arch。
- 内核 headers 安装布局(已实测,`dpkg-deb -c` 确认):
  - arch headers 目录:`/usr/src/linux-headers-7.0.0-1002-sonic/`(= KVERSION,无 `-amd64`,含 Makefile/Module.symvers/scripts/build-script tree)
  - common headers 目录:`/usr/src/linux-sonic-headers-7.0.0-1002/`(前缀是 `linux-sonic-headers-`,非 trixie 的 `linux-headers-...-common-sonic`)
  - arch 包自带 `include/generated`、`include/config`、`arch/x86/include/generated`、`arch/x86/module.lds`(trixie 时这些在 common,需软链;resolute 已在 arch)
- 已 export 的内核变量(来自 `rules/linux-kernel.mk:21`,`export KVERSION_SHORT KVERSION KERNEL_VERSION KERNEL_ABISUFFIX KERNEL_FEATURESET KERNEL_PKGVERSION`):`KVERSION=7.0.0-1002-sonic`、`KERNEL_VERSION=7.0.0`、`KERNEL_ABISUFFIX=-1002`、`KERNEL_FEATURESET=sonic`。
- SAI 版本不动:XGS `libsaibcm_15.2.0.0.0.0.3.1`、DNX `14.1.0.1.0.0.27.0`、legacy-th `13.2.1.120`(已确认下载通道 HTTP 200、2026-06-19 更新、依赖可满足)。
- 三套子模块 gitlink 不动、源码不改,只通过 `<SRC_PATH>.patch/` quilt patch(slave.mk:811 自动 apply)。
- AGENTS.md:Jinja2 模板为源、不 bypass slave.mk 构建图、最小 scoped 改动、pinned 版本不随意升。
- 成功标准(无硬件):构建全程跑通 + 镜像结构完整 + syncd 容器能构建。kmod 仅需证明"能编译+打包依赖正确",不要求 runtime 验证。
- 语言约定:本计划中文,另有英文版 `2026-07-20-broadcom-platform-build-support-plan-en.md`。

## 构建前约定(每个 task 通用)

- **构建命令前缀**:所有 `make` 命令在 build 仓库根执行,需带 resolute 构建环境。标准前缀(下文记作 `$MAKE`):
  ```bash
  cd /home/sheldon-qi/sonic-buildimage-resolute
  export BLDENV=resolute NORESOLUTE=0
  # PLATFORM=broadcom 写进 rules/config.user 或命令行;见 Task 0
  ```
- **构建是 DinD(容器内)执行**:`make` 会拉起 sonic-slave-resolute 容器编译。单次完整构建很慢;每个 task 尽量构建最小 target,不要跑 `make all`。
- **构建产物路径**:`target/debs/resolute/<deb>`、`target/docker-*.gz`、`target/sonic-broadcom.bin`。
- **失败排查入口**:构建失败时看 `target/` 下日志 + slave 容器输出。patch 不 apply 看 quilt 报错;kmod 编译失败看 `debian/rules build-arch` 那段输出;apt Depends 失败看 `apt install` 报错里 `Depends: ... but ... is not installable`。
- **缓存**:`rules/config.user` 已开 SONIC 版本缓存/docker 层缓存(memory 记录)。重复构建会命中缓存;改了 patch 要 `rm -f target/debs/resolute/<对应deb>` 强制重建,或清 `target/debs/resolute/.cache/` 对应项。

---

## Task 0:构建前基线确认 + 复现现状失败(TDD 起点)

**目的:** 锁定 build 仓库干净状态,把 `PLATFORM=broadcom` 默认化,先**证明现状构建会失败**(预期失败),作为后续修复的对照基线。不改任何代码,只配置 + 触发。

**Files:**
- Read: `rules/config.user`(确认 PLATFORM 设置)
- (可能 Modify): `rules/config.user`(若 PLATFORM 不是 broadcom)

**Interfaces:**
- Produces: build 仓库 `PLATFORM=broadcom` 就绪状态;一份"现状失败"日志(存到 `/tmp/broadcom-baseline-fail.log`),供 Task 1-5 对照。

- [ ] **Step 1: 确认 build 仓库干净 + 分支正确**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
git status
git rev-parse --abbrev-ref HEAD
```
Expected: `nothing to commit, working tree clean`;分支 `202605_resolute`。若不干净,先 stash 或确认无关。

- [ ] **Step 2: 确认 PLATFORM=broadcom**

```bash
grep -nE "^PLATFORM|^CONFIGURED_PLATFORM" rules/config.user
```
Expected: 有 `PLATFORM ?= broadcom` 或 `PLATFORM = broadcom`。若仍是 `vs`,改成 broadcom:
```bash
# 改 rules/config.user 里 PLATFORM 行为 broadcom
sed -i 's/^PLATFORM ?= .*/PLATFORM ?= broadcom/' rules/config.user
grep -n "^PLATFORM" rules/config.user
```
Expected: `PLATFORM ?= broadcom`。

- [ ] **Step 3: 触发 kmod 构建(预期失败,这就是 TDD 的"红灯")**

构建单套 kmod(XGS)最小 target:
```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
export BLDENV=resolute NORESOLUTE=0
make target/debs/resolute/opennsl-modules_15.2.0.0.0.0.0.0_amd64.deb 2>&1 | tee /tmp/broadcom-baseline-fail.log
```
Expected: **失败**。预期失败点(任一):`debian/rules` 里 `cd /usr/src/linux-headers-7.0.0-sonic-amd64`(KVER 丢 `-1002`,目录不存在)或 `make -C systems/linux/user/...` 找不到内核源码树。把失败末尾 ~30 行记下来,Task 1 修完要能对照从这里通过。

- [ ] **Step 4: 不 commit(本 task 无代码改动)**

config.user 的 PLATFORM 改动若你希望保留作为 broadcom 开发默认,可单独 commit:
```bash
git add rules/config.user
git commit -m "build: default PLATFORM=broadcom for broadcom bring-up"
```
否则不 commit,后续 task 命令行带 `PLATFORM=broadcom`。**推荐 commit**,省得每个 make 命令都带变量。

---

## Task 1:XGS kmod patch(M1 核心)

> **执行状态(2026-07-20):** ✅ M1 XGS kmod 完成。实际产生 **9 个 patch**(commit `0365f7c520`+`d895c45aa6`+`346ea22436`),覆盖 4 类问题,超出原 plan 的 4-patch 预估。`target/debs/resolute/opennsl-modules_15.2.0.0.0.0.0.0_amd64.deb` 已构建并验证(Depends=`linux-image-7.0.0-1002-sonic`,8 个 .ko 在 `lib/modules/7.0.0-1002-sonic/extra/`)。完整 patch 清单与每类根因见 `~/sonic-buildimage-resolute/.superpowers/sdd/progress-broadcom.md` ledger。下方 Task 1/1b 节为原设计意图(保留);实际新增的 0003-0009(kbuild 配置 + 打包路径)是执行中发现的同型问题,根因与 ledger 记录一致。

**目的:** 给 `saibcm-modules`(XGS)子模块做 quilt patch,让 opennsl-modules 能对 resolute `7.0.0-1002-sonic` 内核编译。这是整个计划最硬的点,单独验证。

**Files:**
- Create: `platform/broadcom/saibcm-modules.patch/series`
- Create: `platform/broadcom/saibcm-modules.patch/0001-resolute-kernel-abi.patch`
- 参考(不改): `platform/broadcom/saibcm-modules/debian/rules`(217 行)、`platform/broadcom/saibcm-modules/debian/control`(13 行 Depends)

**Interfaces:**
- Consumes: `KVERSION`/`KERNEL_VERSION`/`KERNEL_ABISUFFIX`(由 `rules/linux-kernel.mk:21` export,slave.mk 传进构建容器)
- Produces: `target/debs/resolute/opennsl-modules_15.2.0.0.0.0.0.0_amd64.deb`(依赖 `linux-image-7.0.0-1002-sonic`,ABI 对齐 7.0.0-1002-sonic)

**改动原理(实测确认):**
trixie 的 `debian/rules:37-39`:
```make
KVER := $(word 1,$(subst -, ,$(KVERSION)))
KVER_ARCH := $(KVER)-sonic-amd64
KVER_COMMON := $(KVER)-common-sonic
```
- trixie `KVERSION=6.12.41+deb13-sonic-amd64` → `KVER=6.12.41+deb13`,`KVER_ARCH=6.12.41+deb13-sonic-amd64`(✅ 对),`KVER_COMMON=6.12.41+deb13-common-sonic`(✅ 对应 `/usr/src/linux-headers-6.12.41+deb13-common-sonic/`)
- resolute `KVERSION=7.0.0-1002-sonic` → `KVER=7.0.0`(❌ 丢 `-1002`),且目录前缀和命名规则都变了

resolute 实际布局(已 `dpkg-deb -c` 确认):
- arch 目录:`/usr/src/linux-headers-7.0.0-1002-sonic/`(= `$(KVERSION)`,无 `-amd64`)
- common 目录:`/usr/src/linux-sonic-headers-7.0.0-1002/`(前缀 `linux-sonic-headers-`,= `linux-sonic-headers-$(KERNEL_VERSION)$(KERNEL_ABISUFFIX)`)

**patch 改法**:不再用 `word 1` 截断 KVERSION,直接用已 export 的变量拼。

- [ ] **Step 1: 进子模块目录,确认待改文件现状**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute/platform/broadcom/saibcm-modules
sed -n '35,40p' debian/rules   # 看 KVER 段
sed -n '13p' debian/control    # 看 Depends
```
Expected: `rules` 37-39 行如上;`control:13` = `Depends: linux-image-6.12.41+deb13-sonic-amd64-unsigned`。

- [ ] **Step 2: 用 quilt 在子模块内新建 patch**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute/platform/broadcom/saibcm-modules
export QUILT_PATCHES=../saibcm-modules.patch
mkdir -p ../saibcm-modules.patch
quilt new 0001-resolute-kernel-abi.patch
```

- [ ] **Step 3: 把 debian/rules 的 KVER 段加进 patch**

```bash
quilt edit debian/rules
```
把 37-39 行:
```make
KVER := $(word 1,$(subst -, ,$(KVERSION)))
KVER_ARCH := $(KVER)-sonic-amd64
KVER_COMMON := $(KVER)-common-sonic
```
改为:
```make
# Resolute linux-sonic 7.0.0-1002-sonic: ABI string has no arch suffix,
# and common headers dir uses 'linux-sonic-headers-' prefix.
# Use exported KERNEL_VERSION / KERNEL_ABISUFFIX instead of parsing KVERSION.
KVER_ARCH := $(KVERSION)
KVER_COMMON := $(KERNEL_VERSION)$(KERNEL_ABISUFFIX)
```
(删掉 `KVER` 那行,它不再被用。改完 `grep -n '\bKVER\b' debian/rules` 确认无残留引用;若有别处引用 KVER,保留 KVER := $(KVERSION) 作为兼容。)

- [ ] **Step 4: 把 debian/rules 里 common 路径前缀改对(关键)**

`debian/rules` 里所有 `/usr/src/linux-headers-$(KVER_COMMON)` 指向 common 目录,但 resolute common 目录前缀是 `linux-sonic-headers-` 不是 `linux-headers-`。改为 `/usr/src/linux-sonic-headers-$(KVER_COMMON)`:

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute/platform/broadcom/saibcm-modules
grep -n "linux-headers-\$(KVER_COMMON)" debian/rules
```
Expected: 多处(约 68/69/72/92/94-98/102/103/107/134/135/139 行等)。逐个改 `linux-headers-$(KVER_COMMON)` → `linux-sonic-headers-$(KVER_COMMON)`。

> 注:arch 路径 `linux-headers-$(KVER_ARCH)` **不改**——resolute arch 目录前缀仍是 `linux-headers-`,且 `$(KVER_ARCH)` 现在 = `7.0.0-1002-sonic`,拼出 `linux-headers-7.0.0-1002-sonic` ✅。

- [ ] **Step 5: 软链段暂不改(留作 Step 8 失败兜底)**

trixie 的 `build-arch`(rules:91-98)在 common 建 `include/generated`、`arch/x86/include/generated`、`arch/x86/module.lds`、`include/config`、`Module.symvers` 的软链。resolute 的 arch 包**已自带**这些(已实测)。XGS 版用 `ln -sfn`,`-f` 强制覆盖基本不报错。**本 step 先不改**,保持最小改动。若 Step 8 失败在这些 `ln` 上,再回来改成 `if [ ! -e ... ]` 守卫(DNX 版 rules:96-106 已是守卫写法,可参考)。

- [ ] **Step 6: 把 debian/control 的 Depends 加进 patch**

```bash
quilt edit debian/control
```
把第 13 行:
```
Depends: linux-image-6.12.41+deb13-sonic-amd64-unsigned
```
改为:
```
Depends: linux-image-7.0.0-1002-sonic
```

- [ ] **Step 7: 生成 patch 文件 + series**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute/platform/broadcom/saibcm-modules
quilt refresh
quilt pop -a
ls -la ../saibcm-modules.patch/
cat ../saibcm-modules.patch/series
```
Expected: `series` 内容 = `0001-resolute-kernel-abi.patch`;`.patch/` 下有该 patch 文件。`quilt pop -a` 后子模块工作树回到干净(改动收进 patch)。

- [ ] **Step 8: 构建 XGS kmod,验证通过(M1 绿灯)**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
export BLDENV=resolute NORESOLUTE=0
rm -f target/debs/resolute/opennsl-modules_15.2.0.0.0.0.0.0_amd64.deb
make target/debs/resolute/opennsl-modules_15.2.0.0.0.0.0.0_amd64.deb 2>&1 | tee /tmp/broadcom-m1-xgs.log
```
Expected: **成功**,产出 `target/debs/resolute/opennsl-modules_15.2.0.0.0.0.0.0_amd64.deb`。

验证依赖:
```bash
dpkg-deb -I target/debs/resolute/opennsl-modules_15.2.0.0.0.0.0.0_amd64.deb | grep -i depends
```
Expected: 含 `Depends: linux-image-7.0.0-1002-sonic`。

- [ ] **Step 8b: 失败兜底(若 Step 8 失败)**

- 若失败在 `cd /usr/src/linux-headers-7.0.0-sonic-amd64`(仍带旧名):patch 没全 apply 或有遗漏引用,`grep -rn "6.12.41\|\bKVER\b\|sonic-amd64" debian/` 找残留。
- 若失败在 `ln -sfn .../include/generated`(软链):按 Step 5 加守卫 `if [ ! -e ... ]`。
- 若失败在 `make -C systems/linux/user/...` 找不到内核树:核对 slave 容器内 `/usr/src/linux-headers-7.0.0-1002-sonic` 是否存在(`docker exec` 进 slave 容器 `ls /usr/src/`)。
修完重跑 Step 8。

- [ ] **Step 9: Commit**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
git add platform/broadcom/saibcm-modules.patch/
git commit -m "build(broadcom): opennsl kmod (XGS) patch for resolute linux-sonic 7.0.0-1002

Adapt saibcm-modules debian/rules + control to resolute kernel:
- KVER_ARCH := \$(KVERSION) (arch headers dir = 7.0.0-1002-sonic, no -amd64)
- KVER_COMMON := \$(KERNEL_VERSION)\$(KERNEL_ABISUFFIX) (common dir prefix linux-sonic-headers-)
- common path prefix linux-headers- -> linux-sonic-headers-
- control Depends: linux-image-7.0.0-1002-sonic

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```
Expected: 只 commit `.patch/` 目录,子模块 gitlink 不变。

---

## Task 1b:opennsl 源码兼容 Linux 7.0 API(M1 新增,Task 1 构建暴露)

**背景(实现中发现):** Task 1 的 ABI/路径 patch 成功(软链 OK、headers 找到),但构建进入 C 编译阶段失败。根因:opennsl SDK 6.5.35(SAI 15.2)的内核模块兼容层(`lkm.h` 的 `#if LINUX_VERSION_CODE`)只覆盖到 Linux 4.15/6.8/6.11,未覆盖 linux-sonic 7.0.0(= mainline Linux 7.0,VERSION=7/0/0)的 API 漂移。**这是可打的源码 patch,非根本不兼容**(research 已用 commit + 头文件二分确认,见 ledger)。公开上游 saibcm-modules 无适配分支,只能本地 patch。

**三类错误 + 修法:**

1. **`del_timer_sync` 隐式声明** — Linux 6.2 改名 `timer_delete_sync`,保留 deprecated wrapper 到 6.14,**6.15 删除**。7.0 无。修:在两处 lkm.h 加兼容宏。
2. **`from_timer` 隐式声明** — Linux 6.16 改名 `timer_container_of`(**无兼容 wrapper**)。7.0 timer.h:132 有 `timer_container_of`,无 `from_timer`。修:加兼容宏 `#define from_timer(...) timer_container_of(...)`。
3. **`struct filename` static_assert(fs.h:2433)** — Linux 7.0 重构 `struct filename`(`__filename_head` + `static_assert(sizeof % 64 == 0)`),需 `-fms-extensions` 让匿名 struct 成员字段注入;opennsl `make/Make.config` 用自定义 `$(CC)` 编内核 .o 不走 kbuild,没继承 `KBUILD_CFLAGS` 的 `-fms-extensions`。修:给内核对象 CFLAGS 加 `-fms-extensions`(**一行 flag,不动源码**)。

**Files:**
- Modify(经 quilt patch,进 `saibcm-modules.patch/0002-linux-7.0-api-compat.patch`):
  - `platform/broadcom/saibcm-modules/systems/linux/kernel/modules/include/lkm.h`(公共 lkm.h)
  - `platform/broadcom/saibcm-modules/systems/linux/kernel/modules/bcm-ngknet/include/lkm/lkm.h`(bcm-ngknet lkm.h,已有 timer_arg wrapper)
  - `platform/broadcom/saibcm-modules/make/Make.config`(CFLAGS 加 -fms-extensions)

**Interfaces:**
- Produces: 同 Task 1,`target/debs/resolute/opennsl-modules_15.2.0.0.0.0.0.0_amd64.deb`(这次能编译通过)

- [ ] **Step 1: 在 saibcm-modules.patch 里新增第二个 patch**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute/platform/broadcom/saibcm-modules
export QUILT_PATCHES=../saibcm-modules.patch
# Task 1 的 0001 patch 已存在;新增 0002
quilt new 0002-linux-7.0-api-compat.patch
```

- [ ] **Step 2: 加 timer 兼容宏到两个 lkm.h**

对**公共** `systems/linux/kernel/modules/include/lkm.h` 和 **bcm-ngknet** `systems/linux/kernel/modules/bcm-ngknet/include/lkm/lkm.h`,在 `#include <linux/timer.h>` 之后(若文件无该 include,加在 `#include <linux/sched.h>` 附近)加:
```c
/* Linux 6.15 removed del_timer_sync (renamed timer_delete_sync in 6.2,
 * wrapper kept till 6.14). Linux 6.16 renamed from_timer to timer_container_of
 * (no compat wrapper). Provide aliases for older opennsl source. */
#if LINUX_VERSION_CODE >= KERNEL_VERSION(6,15,0)
#define del_timer_sync(t) timer_delete_sync(t)
#endif
#if LINUX_VERSION_CODE >= KERNEL_VERSION(6,16,0)
#define from_timer(var, cb, field) timer_container_of(var, cb, field)
#endif
```
若公共 lkm.h 无 `#include <linux/timer.h>`,先加 `#include <linux/timer.h>`(否则 `timer_delete_sync`/`timer_container_of` 未声明)。

- [ ] **Step 3: make/Make.config 内核对象 CFLAGS 加 -fms-extensions**

```bash
quilt edit make/Make.config
```
在内核对象编译的 CFLAGS 段(research 指出 line ~362/366/387 的 `$(CC) $(CFLAGS)` 内核 .o 编译;也可在公共 `CFLAGS +=` 段加)加:
```make
CFLAGS += -fms-extensions
```
> 注意:只在编译内核模块 .o 的路径加,避免影响用户态编译(若公共 CFLAGS 会污染用户态,则加到内核专属的 `LKM_CFLAGS` 或 `KMOD_CFLAGS` 变量;先查 `make/Make.config` 哪个 CFLAGS 只作用于内核对象)。优先加在内核专属 CFLAGS。

- [ ] **Step 4: refresh + pop**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute/platform/broadcom/saibcm-modules
quilt refresh
quilt pop -a
cat ../saibcm-modules.patch/series   # 应有 0001 + 0002 两行
```

- [ ] **Step 5: 重新构建(验证全部三类错误消除)**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
export BLDENV=resolute NORESOLUTE=0
rm -f target/debs/resolute/opennsl-modules_15.2.0.0.0.0.0.0_amd64.deb
make PLATFORM=broadcom target/debs/resolute/opennsl-modules_15.2.0.0.0.0.0.0_amd64.deb 2>&1 | tee /tmp/broadcom-m1-xgs-retry.log
```
Expected: 成功,产出 deb,`dpkg-deb -I` Depends = `linux-image-7.0.0-1002-sonic`。

- [ ] **Step 5b: 失败兜底(可能冒出更多 6.x/7.0 API 漂移)**

如 net_device ops、ethtool、genl、ktime 等其他 API 漂移。**这些是增量兼容宏工作**(同 zitingguo 分支沿 6.12 打补丁的套路),不是架构问题。按报错 `grep` 受影响 API,加对应 `#if LINUX_VERSION_CODE` 兼容宏或调整调用。每修一类重跑 Step 5。若漂移过多(>5 类),回报评估。

- [ ] **Step 6: amend Task 1 commit 或新增 commit**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
git add platform/broadcom/saibcm-modules.patch/
# 若 Task 1 的 0001 commit 已存在,新增 0002 commit:
git commit -m "build(broadcom): opennsl kmod Linux 7.0 API compat (timer + fms-extensions)

- lkm.h: del_timer_sync->timer_delete_sync alias (>=6.15), from_timer->timer_container_of (>=6.16)
- make/Make.config: -fms-extensions for struct filename anonymous member injection (7.0 fs.h static_assert)

linux-sonic 7.0.0 = mainline 7.0; opennsl SDK 6.5.35 compat layer only covered <=4.15/6.11.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2:DNX + legacy-th kmod patch(M1 完成)

**目的:** 复制 Task 1 的 patch 模式到另两套子模块。三套 KVER 段(37-39)完全一致,改法相同;差异在 rules 的软链段写法(DNX 用 `rm`+`if` 守卫,XGS/legacy-th 用 `ln -sfn`)。

**Files:**
- Create: `platform/broadcom/saibcm-modules-dnx.patch/{series,0001-resolute-kernel-abi.patch}`
- Create: `platform/broadcom/saibcm-modules-legacy-th.patch/{series,0001-resolute-kernel-abi.patch}`

**Interfaces:**
- Produces: `target/debs/resolute/opennsl-modules-dnx_14.1.0.1.0.0.0.0_amd64.deb`、`opennsl-modules-legacy-th_13.2.1.0_amd64.deb`

- [ ] **Step 1: DNX 子模块 patch(同 Task 1 Step 2-7)**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute/platform/broadcom/saibcm-modules-dnx
export QUILT_PATCHES=../saibcm-modules-dnx.patch
mkdir -p ../saibcm-modules-dnx.patch
quilt new 0001-resolute-kernel-abi.patch
quilt edit debian/rules   # 同 Task 1 Step 3 + Step 4 的改法
quilt edit debian/control # Depends -> linux-image-7.0.0-1002-sonic
quilt refresh
quilt pop -a
```
> DNX rules 的软链段已是 `if [ ! -e ... ]` 守卫写法(96-106),基本不用动软链段。但 common 路径前缀仍要改(Step 4 同款)。

- [ ] **Step 2: 构建 DNX kmod**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
export BLDENV=resolute NORESOLUTE=0
rm -f target/debs/resolute/opennsl-modules-dnx_14.1.0.1.0.0.0.0_amd64.deb
make target/debs/resolute/opennsl-modules-dnx_14.1.0.1.0.0.0.0_amd64.deb 2>&1 | tee /tmp/broadcom-m1-dnx.log
```
Expected: 产出 DNX kmod deb,`dpkg-deb -I` 的 Depends = `linux-image-7.0.0-1002-sonic`。

- [ ] **Step 3: legacy-th 子模块 patch + 构建(同上)**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute/platform/broadcom/saibcm-modules-legacy-th
export QUILT_PATCHES=../saibcm-modules-legacy-th.patch
mkdir -p ../saibcm-modules-legacy-th.patch
quilt new 0001-resolute-kernel-abi.patch
quilt edit debian/rules    # 同 Task 1 Step 3 + Step 4(XGS 与 legacy-th rules 同构,ln -sfn 写法)
quilt edit debian/control  # Depends -> linux-image-7.0.0-1002-sonic
quilt refresh
quilt pop -a

cd /home/sheldon-qi/sonic-buildimage-resolute
rm -f target/debs/resolute/opennsl-modules-legacy-th_13.2.1.0_amd64.deb
make target/debs/resolute/opennsl-modules-legacy-th_13.2.1.0_amd64.deb 2>&1 | tee /tmp/broadcom-m1-legacy.log
```
Expected: 产出 legacy-th kmod deb,Depends 正确。

- [ ] **Step 4: Commit(M1 完成)**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
git add platform/broadcom/saibcm-modules-dnx.patch/ platform/broadcom/saibcm-modules-legacy-th.patch/
git commit -m "build(broadcom): opennsl kmod (dnx + legacy-th) patches for resolute kernel

Same pattern as XGS: KVER_ARCH/KVER_COMMON + common path prefix + control Depends.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

**M1 里程碑达成:** 三套 opennsl kmod 全部构建成功,ABI 对齐 resolute linux-sonic 7.0.0-1002-sonic,Depends 正确。

---

## Task 3:三套 syncd 容器构建(M2)

**目的:** 构建 `docker-syncd-brcm` / `-dnx` / `-legacy-th` 三个容器镜像。验证 syncd/sswsyncd 能在 GCC15/resolute 下编译,闭源 libsaibcm .deb 能装下,protobuf 包名差异处理。

**Files:**
- 不改文件(本 task 纯构建验证,除非遇到 protobuf/GCC 问题才打补丁)
- 关注: `platform/broadcom/docker-syncd-brcm.mk`、`sswsyncd.mk`、`sai-xgs.mk`/`sai-dnx.mk`/`sai-legacy-th.mk`

**Interfaces:**
- Consumes: M1 的三套 kmod deb、三套闭源 libsaibcm .deb(下载)
- Produces: `target/docker-syncd-brcm.gz`、`docker-syncd-brcm-dnx.gz`、`docker-syncd-brcm-legacy-th.gz`

- [ ] **Step 1: 构建闭源 SAI .deb 下载(XGS/DNX/legacy-th 先确保下载到本地)**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
export BLDENV=resolute NORESOLUTE=0
make target/debs/resolute/libsaibcm_15.2.0.0.0.0.3.1_amd64.deb 2>&1 | tee /tmp/broadcom-m2-sai-xgs.log
make target/debs/resolute/libsaibcm_dnx_14.1.0.1.0.0.27.0_amd64.deb 2>&1 | tee /tmp/broadcom-m2-sai-dnx.log
make target/debs/resolute/libsaibcm_13.2.1.120_amd64.deb 2>&1 | tee /tmp/broadcom-m2-sai-legacy.log
```
Expected: 三个闭源 .deb 下载到 `target/debs/resolute/`(它们是 SONIC_ONLINE_DEBS,纯下载不编译)。下载通道已确认可达(HTTP 200)。

- [ ] **Step 2: 处理 protobuf 包名差异(若装 libsaibcm 报 unmet)**

若 Step 1 或后续 syncd 构建里 apt 装 libsaibcm 报 `libprotobuf32t64` 不可用:
```bash
# 先查 resolute 的 libprotobuf32 是否 Provides: libprotobuf32t64
docker exec sonic-slave-resolute bash -c "apt-cache show libprotobuf32 2>/dev/null | grep -i provides"
# 或查 protobuf.mk 产出的包
dpkg-deb -I target/debs/resolute/libprotobuf32_*.deb 2>/dev/null | grep -iE "provides|package"
```
- 若已 `Provides: libprotobuf32t64` → 无需处理。
- 若否 → 在 `rules/protobuf.mk` 给产出的 `libprotobuf32` 加 `Provides: libprotobuf32t64`(用 `_PROVIDES` 变量,若 SONiC 构建图支持;否则 equivs 垫一个空 provides 包)。改完重跑。

- [ ] **Step 3: 构建 docker-syncd-brcm(XGS)**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
export BLDENV=resolute NORESOLUTE=0
make target/docker-syncd-brcm.gz 2>&1 | tee /tmp/broadcom-m2-syncd-xgs.log
```
Expected: 产出 `target/docker-syncd-brcm.gz`。

- [ ] **Step 3b: 失败兜底(GCC15 链接闭源 libsaibcm)**

若失败在 sswsyncd / libsaithrift-dev / syncd 编译链接闭源 libsaibcm:
- C ABI 自 GCC5 稳定,大概率是别的(shared 命名、头文件路径)。
- 看具体报错:`undefined reference to`、`cannot find -lsaibcm`、头文件 not found 等,按错误处理(可能要给 sswsyncd 的 build 加 `-I`/`-L` 或 SONiC 的 `*_BUILD_ENV`/`*_CFLAGS`)。
- 这是 spec §5 标的"只能实编验证"点,按具体报错对症。

- [ ] **Step 4: 构建 docker-syncd-brcm-dnx + -legacy-th**

```bash
make target/docker-syncd-brcm-dnx.gz 2>&1 | tee /tmp/broadcom-m2-syncd-dnx.log
make target/docker-syncd-brcm-legacy-th.gz 2>&1 | tee /tmp/broadcom-m2-syncd-legacy.log
```
Expected: 两个容器 gz 产出。

- [ ] **Step 5: 若 Step 2/3b 动了 protobuf.mk 或其他 rules,commit;否则无 commit**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
git status   # 确认有无 rules/ 改动
# 若有:
git add rules/protobuf.mk  # 或其他
git commit -m "build(broadcom): protobuf provides libprotobuf32t64 for closed libsaibcm dep"
```

**M2 里程碑达成:** 三套 syncd 容器构建成功,闭源 libsaibcm 装下,protobuf/GCC 问题处理。

---

## Task 4:sonic-broadcom.bin 镜像组装(M3,最终目标)

**目的:** 组装标准 ONIE installer `sonic-broadcom.bin`,含三套 syncd 容器 + kmod + vendor LAZY 模块。

**Files:**
- 不改文件(纯构建,除非 one-image 有 resolute 适配问题)

**Interfaces:**
- Consumes: M1 三套 kmod、M2 三套 syncd 容器、三套闭源 SAI、所有基础容器(config-engine-resolute 等)
- Produces: `target/sonic-broadcom.bin` ← **最终交付物**

- [ ] **Step 1: 构建 sonic-broadcom.bin**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
export BLDENV=resolute NORESOLUTE=0
make target/sonic-broadcom.bin 2>&1 | tee /tmp/broadcom-m3-bin.log
```
Expected: 产出 `target/sonic-broadcom.bin`。

- [ ] **Step 1b: 失败兜底(one-image 组装 / LAZY_BUILD_INSTALLS / RFS / installer)**

- `one-image.mk:148` `LAZY_BUILD_INSTALLS = $(BRCM_OPENNSL_KERNEL) $(BRCM_DNX_OPENNSL_KERNEL)` —— ONIE bin 只 lazy-build XGS+DNX 两个 kmod(legacy-th 只进 ABOOT swi,不在 ONIE bin)。若这里报错,核对 M1 产物路径对不对。
- RFS/installer 阶段失败(`build_debian.sh`):看是哪个 deb 没装上、kernel 引导问题等。resolute 的 grub2/linux-sonic 在 VS 已趟过,但 broadcom 镜像首次走,可能有 broadcom 特有路径(如 `/lib/modules/$(KVER_ARCH)` 在 build-arch 建的软链在 RFS 里要存在)。
- 按具体报错对症;可能需要小幅 patch(但尽量最小改动)。

- [ ] **Step 2: 验证镜像结构**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
ls -la target/sonic-broadcom.bin
file target/sonic-broadcom.bin
# 检查镜像内含三套 syncd 容器(用 onie-image 解包或 sonic_installer)
# 简单确认:镜像大小合理(broadcom bin 通常 ~1-2GB)
```
Expected: 文件存在,是 ONIE installer 格式,大小合理。

- [ ] **Step 3: 若有改动 commit;否则记录最终状态**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
git status
# 若 M3 有适配改动:
git add -A
git commit -m "build(broadcom): sonic-broadcom.bin assembles on resolute

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

**M3 里程碑达成 / 最终目标完成:** `target/sonic-broadcom.bin` 成功构建。🎉

---

## 回退与清理

- 若某 task 彻底卡住需回退:`git checkout -- platform/broadcom/saibcm-modules.patch/` 等(只回退 patch 目录,子模块 gitlink 从未动)。
- 子模块工作树若 quilt 残留 `.pc/`:`cd platform/broadcom/saibcm-modules && quilt pop -a; rm -rf .pc`。
- 临时构建日志都在 `/tmp/broadcom-*.log`,可随时 `tail` 查。

## 成功判据(整体)

- [ ] M1:三套 `opennsl-modules*.deb` 产出,Depends = `linux-image-7.0.0-1002-sonic`
- [ ] M2:三套 `docker-syncd-brcm*.gz` 产出
- [ ] M3:`target/sonic-broadcom.bin` 产出(最终目标)
