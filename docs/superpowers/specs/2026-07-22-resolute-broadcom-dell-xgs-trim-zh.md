# 设计:resolute Broadcom 平台裁剪为 dell / XGS-only

**分支:** `202605_resolute_doc`(本文档)
**构建仓库:** `/home/sheldon-qi/sonic-buildimage-resolute`(`202605_resolute_sheldon` 分支)+ worktree `sonic-buildimage-resolute-reorg`(正式化 stack `202605_resolute_pr01..pr08`)
**日期:** 2026-07-22
**状态:** 设计已确认,待实现

---

## 1. 背景与目标

正式化 review 阶段,reviewer 要求 resolute 的改动尽量聚焦。当前 Broadcom PR(stack 里的 `pr08`)携带了**整套** Broadcom 平台:XGS kmod + SAI、DNX/Jericho 变体、legacy-Tomahawk 变体、saiserver,以及 **18 个厂商**的 kmod patch 系列。

**决策:把 resolute 的 Broadcom 交付面收敛到 Canonical 在 Ubuntu 26.04 上唯一验证的平台族 —— dell,而 dell 全系是 XGS**(TD2/TD3/TD4、TH/TH2/TH3/TH4/TH5)。

据此:
- **DNX/Jericho + legacy-Tomahawk** 是统一镜像 `sonic-broadcom.bin` 顺带打包的其它 ASIC 族,dell 运行时**完全用不到**,且在 26.04 上**未验证** → 移除。
- 另外 17 个非-dell 厂商的 kmod patch 是 Linux-7.0 适配扫荡期**投机性**加入的(其中 10 个厂商在 `rules.mk` 里本就被注释,patch 从不生效) → 移除。

**产出:** `pr08` 从 19 commit 收敛到 2 commit;resolute 的 Broadcom delta 变为纯 XGS/dell。

---

## 2. 现状事实(实现前已核查)

以下事实决定了裁剪的边界与手法:

1. **`rules.mk`、`sai-modules.mk`、`one-image.mk`、`one-aboot.mk`、`sai-dnx.mk`、`sai-legacy-th.mk` 与 `sonic-net/202605` 逐字节相同** —— resolute 从未改过它们;`rules.mk` 里那些 `#include`(被注释的厂商)和 `# TODO(trixie)` 都是 trixie 迁移期就有的上游内容。resolute 真正的 Broadcom delta 只在 `*.patch/` overlay 目录 + 5 个被改的文件(4 个 docker `*.mk`、3 个 `Dockerfile.j2`、`sswsyncd/debian/rules`,外加 `rules.mk` 尾部一个空行)。

2. **`sai-modules.mk` 一个文件里构建了三套 kmod**:XGS(`BRCM_OPENNSL_KERNEL`,第 1–9 行)、DNX(`BRCM_DNX_OPENNSL_KERNEL`,第 11–20 行)、legacy-TH(`BRCM_LEGACY_TH_OPENNSL_KERNEL`,第 22–31 行)。`saibcm-modules-dnx.patch/`、`saibcm-modules-legacy-th.patch/` 是被这里消费的,而**不是**被 `sai-dnx.mk` / `sai-legacy-th.mk`(那两个只拉 SAI **库** online deb)。

3. **`one-image.mk:5` 与 `one-aboot.mk:5` 设了 `DEPENDENT_MACHINE = broadcom-dnx broadcom-legacy-th`** —— 这是统一镜像顺带构建 DNX/legacy-TH 机型 fsroot 的触发器。不砍掉它,构建仍会去建那两套(其 kmod 源码已被删)而失败。

4. **文件量**:非-dell 厂商 patch 目录 = 81 文件;dnx + legacy-th kmod patch = 24 文件;dell = 4 文件(保留)。

5. `canonical/202605_resolute` 远端 ref 已删除;内容仍在本地 `pr08` tip 与本地备份 `202605_resolute`(`aa7fc4f76d`)中,重建无需该远端。

---

## 3. 目标 delta(相对 `sonic-net/202605`,精确到此,不多不少)

### 3.1 保留的 resolute 改动
- `platform/broadcom/rules.mk` —— 编辑为 dell/XGS-only include 列表(见 §4.1)
- `platform/broadcom/sai-modules.mk` —— 编辑为仅 XGS kmod(见 §4.2)
- `platform/broadcom/one-image.mk` —— 编辑 `DEPENDENT_MACHINE` 与 `LAZY_BUILD_INSTALLS`(见 §4.3)
- `platform/broadcom/saibcm-modules.patch/**`(10 文件,XGS kmod 的 Linux-7.0 patch 系列)
- `platform/broadcom/sswsyncd/debian/rules`(1)
- `platform/broadcom/docker-syncd-brcm/Dockerfile.j2`(1)
- `platform/broadcom/sonic-platform-modules-dell.patch/**`(4)

### 3.2 删除(resolute 新增的)
- `platform/broadcom/saibcm-modules-dnx.patch/**`
- `platform/broadcom/saibcm-modules-legacy-th.patch/**`
- 17 个非-dell 厂商目录:`sonic-platform-modules-{accton,alphanetworks,arista,cel,delta,ingrasys,inventec,juniper,micas,mitac,nexthop,nokia,quanta,ragile,ruijie,tencent,ufispace}.patch/**`

### 3.3 还原为上游(resolute 改过、现已失去引用的)
- `docker-pde.mk`、`docker-saiserver-brcm.mk`、`docker-syncd-brcm-dnx.mk`、`docker-syncd-brcm-legacy-th.mk`
- `docker-syncd-brcm-dnx/Dockerfile.j2`、`docker-syncd-brcm-legacy-th/Dockerfile.j2`、`docker-saiserver-brcm/Dockerfile.j2`

---

## 4. 三个 `.mk` 的编辑细节

### 4.1 `rules.mk`(注释风格沿用文件既有的 `#include` 惯例,每组上方加一行 resolute 说明)

**保持 active:** `sai-modules.mk`、`sai-xgs.mk`、`sswsyncd.mk`、`platform-modules-dell.mk`、`docker-syncd-brcm.mk`、`one-image.mk`、`raw-image.mk`、`libsaithrift-dev.mk`,以及 `INCLUDE_PDE` / `INCLUDE_GBSYNCD` 两个 guarded 块(维持原样;其文件按 §3.3 还原上游)。

**注释掉:**
- `sai-dnx.mk`、`sai-legacy-th.mk`(DNX / legacy-TH ASIC 族)
- 当前 active 的 8 个非-dell 厂商:`nokia, arista, nexthop, accton, cel, supermicro, ufispace, micas`
- `docker-syncd-brcm-rpc.mk`、`docker-saiserver-brcm.mk`、`docker-syncd-brcm-legacy-th.mk`、`docker-syncd-brcm-legacy-th-rpc.mk`、`docker-syncd-brcm-dnx.mk`、`docker-syncd-brcm-dnx-rpc.mk`、`one-aboot.mk`(`one-aboot` 是 Arista Aboot 镜像格式,非 dell 所需,且它自己也会经 `DEPENDENT_MACHINE` 拉回被删机型,必须去掉)
- `SONIC_ALL +=` 行去掉 `$(SONIC_ONE_ABOOT_IMAGE)`

> 说明:`rpc` / `saiserver` / `pde` 都是测试/开发容器,dell 生产镜像不需要;这与已确认的 "XGS-only 闭包" 一致。

### 4.2 `sai-modules.mk`
删除 `BRCM_DNX_OPENNSL_KERNEL`(11–20)与 `BRCM_LEGACY_TH_OPENNSL_KERNEL`(22–31)两块;保留 XGS 块(1–9),上方加一行 resolute 说明。

### 4.3 `one-image.mk`
- 第 5 行:`DEPENDENT_MACHINE` 值清空 + 加 resolute 注释说明只建 XGS。
- 第 148 行:`LAZY_BUILD_INSTALLS = $(BRCM_OPENNSL_KERNEL)`(去掉 `$(BRCM_DNX_OPENNSL_KERNEL)`)。
- `LAZY_INSTALLS` 那一大串厂商变量**不动** —— 未 include 的厂商变量展开为空,自然 no-op;去动它只会给 diff 平白增加上百行、零收益。

---

## 5. 双目标执行(用户决策:sheldon 顶上加 trim commit + 同步重写 pr08)

§3、§4 的文件操作(删除 + 还原上游 + 3 个 `.mk` 编辑)对两条分支完全相同。3 个编辑后的 `.mk` 写一次、复用。

### 5.1 目标 A —— `202605_resolute_sheldon`(主构建树,真正的交付分支)
**顶上追加一个 commit**(sheldon:129 → 130),加法式:
`build(broadcom): scope resolute broadcom to dell/XGS — drop DNX/legacy-TH + non-dell vendor kmods`
正文说明:dell 全系 XGS;统一镜像顺带的 DNX/Jericho + legacy-TH 在 26.04 未用未验证,故移除 `DEPENDENT_MACHINE`、`sai-modules.mk` 的两块 kmod 定义、以及 17 个非-dell 厂商 overlay。

### 5.2 目标 B —— `202605_resolute_pr08`(reorg worktree,review stack)
重写 pr08 = `202605_resolute_pr07` + 2 个 GPG 签名 commit,使其最终 tree **等于裁剪后的 sheldon tree**(减去 `rules/config.user`,stack 从不携带它):
1. `build(broadcom): saibcm-modules XGS Linux 7.0 kmod series + dell-only build wiring`
   —— `rules.mk`、`sai-modules.mk`、`one-image.mk`、`saibcm-modules.patch`、`sswsyncd`、`docker-syncd-brcm`。
2. `build(broadcom): dell platform kmods Linux 7.0 API-drift patch series`
   —— `sonic-platform-modules-dell.patch`。

手法:从 `pr07` 新开分支;`git checkout <旧 pr08> -- <保留的 patch 目录>`;3 个编辑后的 `.mk` 从上游基线落上去;两个 commit。旧 pr08 tip 留在 reflog + 本地 `202605_resolute` 备份。**review 前不 push。**

### 5.3 一致性校验
`git diff 202605_resolute_pr08 202605_resolute_sheldon` → 仅剩 `rules/config.user`(与裁剪前的不变式一致)。

---

## 6. 验证(在主构建树对裁剪后的 sheldon 执行 —— 构建环境在那里)

1. **结构性(快,不真建):** `BLDENV=resolute make -f Makefile.work target/sonic-broadcom.bin SONIC_CONFIG_PRINT_DEPENDENCIES=y` —— 确认依赖树里**没有** `broadcom-dnx` / `broadcom-legacy-th` / 非-dell 厂商目标。
2. **XGS kmod 在 Linux 7.0 上可建:** `target/debs/resolute/opennsl-modules_15.2.0.0.0.0.0.0_amd64.deb`。
3. **dell 平台 deb 可建**(dell.patch 能 apply)。
4. **可选**:完整 `target/sonic-broadcom.bin`(耗时长)作最终确认。

pr08 与 sheldon 共享同一 Broadcom 子树,验证 sheldon 即覆盖两者。

---

## 7. 风险与回滚

- **回滚**:旧 pr08 tip 在 reflog;本地 `202605_resolute`(`aa7fc4f76d`)是完整旧状态备份;sheldon 的 trim 是加法 commit,`git reset --hard HEAD^` 即撤销。
- **主要风险**:过度裁剪 `rules.mk`(误注释某个 `sonic-broadcom.bin` 实际需要的 include)。§6.1 的结构性依赖树打印在**不真正构建**的前提下即可捕获此类断链。
- **产物语义变化**:裁剪后的 `sonic-broadcom.bin` 不再支持 DNX/Jericho 与 legacy-TH ASIC。这是**有意为之**(dell/XGS-only),需在 commit message 与 release note 中写明。

---

## 8. 不做的事(YAGNI)

- 不改 `one-image.mk` 的 `LAZY_INSTALLS` 厂商清单(空变量 no-op,改它纯增 diff)。
- 不动 `sai-xgs.mk`、`docker-syncd-brcm` 的 XGS 内容。
- 不改 `AGENTS.md`、不改 `/tmp/g3` group 列表以外的正式化脚本(除非后续需要从裁剪后的 sheldon 重生 stack)。
- 不 push、不建 PR —— 待 review。
