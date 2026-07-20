# 设计:resolute 上 Broadcom 平台构建支持

- 日期:2026-07-20
- 仓库:`canonical/sonic-buildimage` 分支 `202605_resolute`
- 作者:Sheldon Qi
- 状态:已通过设计评审,待写实施计划

## 1. 背景与动机

`202605_resolute` 分支已将 SONiC 从 Debian Trixie 迁移到 Ubuntu Resolute(26.04),VS 平台(`sonic-vs.bin`)已成功构建。但 Broadcom 平台在 resolute 上**从未构建过**——`target/` 下无任何 broadcom 产物。

resolute 对 `platform/broadcom/` 只做了一个机械改名 commit(`b85dee25a7`:把 `DOCKER_CONFIG_ENGINE_TRIXIE` 改为 `..._RESOLUTE`、Dockerfile.j2 的 `FROM ...trixie` 改 `...resolute`),**SAI 版本、opennsl 内核模块逻辑零改动**。真正的 resolute 适配全在 `rules/`(linux-sonic kernel、grub2、FIPS、iproute2)。

用户目标是支持 Broadcom 平台(TH3 / XGS 家族),产出标准 `sonic-broadcom.bin`。

## 2. 目标与范围

### 2.1 目标

在 `202605_resolute` 分支上让 `make PLATFORM=broadcom` 产出标准 `sonic-broadcom.bin`,含:
- 三套 syncd 容器(`docker-syncd-brcm` / `-dnx` / `-legacy-th`)
- 三套 opennsl 内核模块(`opennsl-modules` / `-dnx` / `-legacy-th`)
- 三套闭源 SAI .deb(XGS `15.2.0.0.0.0.3.1` / DNX `14.1.0.1.0.0.27.0` / legacy-th `13.2.1.120`)
- libsaithrift-dev、sswsyncd 等配套

### 2.2 TH3 落点

TH3 属 XGS 家族,走:
- SAI:`platform/broadcom/sai-xgs.mk`(libsaibcm v15.2.0,分支 `SAI_15.2.0_GA`)
- syncd 容器:`platform/broadcom/docker-syncd-brcm.mk`(`MACHINE=broadcom`)
- 内核模块:`platform/broadcom/sai-modules.mk` → `opennsl-modules`(v15.2.0.0.0.0.0.0)
- device 配置:`device/broadcom/x86_64-broadcom_common/x86_64-broadcom_b98/`(b98 = TH3)

因标准 `sonic-broadcom.bin` 经 `one-image.mk:5` 的 `DEPENDENT_MACHINE = broadcom-dnx broadcom-legacy-th` 会同时打包三套 syncd,即使只要 TH3 也须让 DNX 14.1 和 legacy-th 13.2 两条链一并跑通。**用户选择直接出标准三套 bin**。

### 2.3 成功标准(无硬件)

用户当前**无真实 Broadcom 硬件**。成功标准为:
- 构建全程跑通,无报错
- 镜像结构完整(`sonic-broadcom.bin` 可生成,ONIE installer 布局正确)
- 三套 syncd 容器能构建出来

opennsl kmod **仅需证明"能对 resolute 内核 headers 编译 + 打包出依赖正确的 .deb"**,不要求 runtime 验证模块加载 / 连 ASIC。

## 3. 架构:闭源 blob 周围的开源自建链

### 3.1 闭源 vs 开源的真实分布

| 组件 | 形态 | 版本 | 开源? |
|---|---|---|---|
| **libsaibcm(SAI 实现)** | 预编译 .deb 下载 | XGS 15.2 / DNX 14.1 / legacy-th 13.2 | ❌ 闭源 blob |
| **bcmcmd / bcmsh / bcm_common** | 二进制下载 | 固定 `20190307` | ❌ 闭源 |
| opennsl 内核模块 | 子模块源码 build | 15.2 / 14.1 / 13.2.1 | ✅ 开源可改(github.com/sonic-net/saibcm-modules) |
| syncd | sonic-sairedis 源码编译 | — | ✅ 开源 |
| sswsyncd(bcmcmd/dsserve C++) | 树内源码 build | — | ✅ 开源 |
| docker 镜像 / device 配置 | 模板 + 源码 | — | ✅ 开源 |

**核心事实:闭源只有 libsaibcm .deb + 诊断二进制;其余全部开源可自建。** 闭源 blob 与版本绑定方式见 §3.2。

### 3.2 闭源组件的版本绑定

1. **【硬】kmod 版本 ↔ SAI 版本必须配对成套**:XGS SAI 15.2 只配 opennsl kmod 15.2;DNX 14.1 配 14.1;legacy-th 13.2.1 配 13.2.1。用户态 SAI 与内核模块间有私有 ABI,不能跨版本混搭。→ 三套 bin 必须拉三套 kmod。
2. **【硬】kmod 必须针对"精确运行的内核"编译**:resolute 内核为 `linux-sonic 7.0.0-1002-sonic`(trixie 是 `6.12.41+deb13-sonic-amd64`)。kmod 的 `debian/rules` ABI 推导逻辑 + `debian/control` Depends 都基于 trixie 内核名,内核一变必须重编 + 改打包元数据。→ **本设计核心阻塞点**。
3. **【软,已 de-risk】闭源 .deb 的 glibc 依赖**:libsaibcm 声明 `Depends: libc6 (>= 2.38), libgcc-s1 (>= 3.4), libstdc++6 (>= 14), libprotobuf32t64 (>= 3.21.12), libyaml-0-2, lz4`,全是 `>=` 下界,resolute(Ubuntu 26.04,glibc 2.43、libstdc++6 ≥ 15)全部满足。证据:已下载 XGS .deb `dpkg-deb -I` 实查 control;下载通道 HTTP 200(2026-06-19 更新)。
4. **【软,已知小点】protobuf 包名差异**:libsaibcm 声明 `libprotobuf32t64`(trixie time64 命名),resolute 的 `rules/protobuf.mk:12` 产出 `libprotobuf32`(无 `t64`)。构建期实查 resolute 的 `libprotobuf32` 是否 `Provides: libprotobuf32t64`,若否则用 equivs 垫 provides 或 `--ignore-deps`。**不阻塞设计,留作构建期处理点**。
5. **【软,只能实编验证】GCC15 链接闭源 libsaibcm**:sswsyncd / libsaithrift-dev / syncd 的 BCM 专用代码会链接闭源 libsaibcm(老 GCC 编)与 GCC15(resolute)编的链接方。C ABI 自 GCC5 稳定,大概率 OK;C++ 边界可能有边角。只能实编验证,作为构建期失败兜底点。

### 3.3 构建产物结构

```
sonic-broadcom.bin (ONIE installer)
├── 三套 syncd 容器 (docker-syncd-brcm / -dnx / -legacy-th)   ← 开源自建
│   ├── syncd (sonic-sairedis 源码编译)                          ← 开源
│   ├── libsaibcm .deb (XGS15.2/DNX14.1/legacy13.2)             ← 闭源 blob 下载
│   └── sswsyncd (bcmcmd/dsserve C++ 源码)                       ← 开源自建
├── 三套 opennsl kmod (saibcm-modules{,-dnx,-legacy-th})        ← 开源子模块 + patch 自建
│   └── 需对齐 resolute linux-sonic 7.0.0-1002-sonic 内核        ← ★硬阻塞,本设计核心
├── libsaithrift-dev (绑闭源 SAI)                                 ← 开源自建
└── vendor platform-modules (22 套,LAZY_INSTALLS,运行期按机型装) ← 不阻塞通用 bin
```

## 4. 核心改动:opennsl kmod 适配(方案 A — quilt patch)

### 4.1 方案选择

三套 `saibcm-modules{,-dnx,-legacy-th}` 均为 git 子模块(`.gitmodules` 指向 `github.com/sonic-net/saibcm-modules.git`)。AGENTS.md 要求"不得直接改外部源码,须打 patch 从 build rule apply"。

选定**方案 A:quilt patch 文件**。理由:
- SONiC 构建图 `slave.mk:811` 已自动 `<SRC_PATH>.patch/series` quilt apply,零新增机制
- 完全合规 AGENTS.md,不碰 gitlink
- resolute 专属改动隔离在 patch 文件,上游 merge 冲突小
- kmod 适配本质是"针对 resolute 内核版本的本地移植",不值得进子模块主干(方案 B 过度工程);方案 C(环境变量覆盖)对 `:=` 立即赋值和静态 `control` 文件有硬伤

否决方案 B(子模块内提交 + gitlink 推进):工作量大、要建 3 个子模块 resolute 分支 + gitlink 可达性维护,且与上游 trixie 命名分歧要长期维护分支。
否决方案 C(build rule 环境变量覆盖 + sed):`debian/rules` 的 `KVER := $(word 1,...)` 是立即赋值覆盖不稳;`debian/control` 是静态文件,sed 不可 review 易碎。

### 4.2 patch 组织

三套子模块源码树版本/分支不同,`debian/rules`/`control` 内容有差异,**各一份 patch**:

```
platform/broadcom/saibcm-modules.patch/series
platform/broadcom/saibcm-modules.patch/0001-resolute-kernel-abi.patch          # XGS
platform/broadcom/saibcm-modules-dnx.patch/series
platform/broadcom/saibcm-modules-dnx.patch/0001-resolute-kernel-abi.patch      # DNX
platform/broadcom/saibcm-modules-legacy-th.patch/series
platform/broadcom/saibcm-modules-legacy-th.patch/0001-resolute-kernel-abi.patch # legacy-th
```

### 4.3 改动内容

#### (a) `debian/rules` — ABI 推导逻辑

**现状**(saibcm-modules/debian/rules:50-52):
```make
KVER := $(word 1,$(subst -, ,$(KVERSION)))
KVER_ARCH := $(KVER)-sonic-amd64
KVER_COMMON := $(KVER)-common-sonic
```

**问题**:
- trixie `KVERSION=6.12.41+deb13-sonic-amd64` → `word 1` = `6.12.41+deb13`(版本与 debian 后缀用 `+` 分隔,不丢)→ `KVER_ARCH=6.12.41+deb13-sonic-amd64` ✅
- resolute `KVERSION=7.0.0-1002-sonic` → `subst -` → `7.0.0 1002 sonic`,`word 1` = `7.0.0`(**丢 `-1002`**)→ `KVER_ARCH=7.0.0-sonic-amd64` ❌ 找不到 headers 目录(实际是 `7.0.0-1002-sonic-amd64`)

**改法**:让 `KVER` 保留到 `-sonic` 之前,即 `7.0.0-1002`。使 `KVER_ARCH=7.0.0-1002-sonic-amd64`、`KVER_COMMON` 对应调整。

**还需核查**(可能纳入同一 patch 或单独 patch):
- `KVER_COMMON` 对应的通用 headers 包名:resolute 是 `linux-sonic-headers-7.0.0-1002`(前缀 `linux-sonic-headers-`,非 trixie 的 `linux-headers-...-common-sonic`)。`debian/rules` 里 `build-arch` 那一堆 `sudo ln -sfn /usr/src/linux-headers-$(KVER_COMMON)/...` 软链假设要适配 resolute 的 Ubuntu 风格(build-script-tree-in-headers 结构)。
- 实际 patch 内容以子模块 checkout 后的源码为准生成。

#### (b) `debian/control` — Depends

三套 control:13 都硬编码:
```
Depends: linux-image-6.12.41+deb13-sonic-amd64-unsigned
```
改为(硬写 resolute 包名,无 arch 后缀):
```
Depends: linux-image-7.0.0-1002-sonic
```
resolute 内核包名见 `rules/linux-kernel.mk:32` `LINUX_IMAGE = linux-image-$(KVERSION)_...` 其中 `KVERSION=7.0.0-1002-sonic`。

## 5. 已知小点(构建期处理)

| 点 | 处理 | 何时 |
|---|---|---|
| libprotobuf32t64 vs libprotobuf32 包名差异 | 构建期实查 resolute `libprotobuf32` 是否 `Provides: libprotobuf32t64`;若否则 equivs 垫 provides 或 `--ignore-deps` | M2(syncd 装闭源 .deb 时) |
| GCC15 链接闭源 libsaibcm 编 sswsyncd/libsaithrift-dev | C ABI 自 GCC5 稳定,实编验证;失败则按具体报错处理 | M2 |

## 6. 验证里程碑(三步递进)

| 里程碑 | make target | 证明什么 | 失败兜底方向 |
|---|---|---|---|
| **M1: 三套 kmod** | `target/debs/broadcom/opennsl-modules*.deb`(含 -dnx / -legacy-th) | kmod 能对 resolute linux-sonic 7.0.0-1002 headers 编译;patch 的 ABI 推导 + control Depends 修法正确 | patch ABI 推导 / 软链 / Depends |
| **M2: 三套 syncd 容器** | `target/docker-syncd-brcm*.gz` 等 | syncd / sswsyncd 编译;libsaibcm .deb 装下;protobuf 包名差异处理 | GCC15 链接、protobuf provides 垫片 |
| **M3: sonic-broadcom.bin** | `target/sonic-broadcom.bin` | 镜像组装;三套 syncd + kmod 打包;ONIE installer 结构完整 | one-image LAZY_BUILD_INSTALLS、镜像布局 |

## 7. 不做的事(YAGNI)

- 不做 arm64 broadcom(`device/arista/arm64-arista_goldfinch-r0` 有 device 目录但无镜像构建路径,非目标)
- 不做 PDE(`INCLUDE_PDE=y`)/ saiserver / rpc 变体(默认不拉,需显式开)
- 不做 ABOOT swi(`sonic-aboot-broadcom.swi`)的 resolute 适配,除非 M3 后 ONIE bin 过了发现需要(M3 目标只含 `sonic-broadcom.bin`)
- 不重写 vendor platform-modules(LAZY_INSTALLS,不阻塞通用 bin)
- 不改 SAI 版本 / URL(已确认 2026-06-19 更新、下载可达、依赖可满足)
- 不改 gitlink、不改子模块源码(走 patch)

## 8. AGENTS.md 合规

- kmod 改动走 patch 文件(非直接改子模块源码)
- 不动 gitlink
- Jinja2 模板视为源,生成物不动
- 不 bypass slave.mk 构建图(用 `make` target)
- 最小 scoped 改动,不做无关格式化 / 依赖升级

## 9. 风险登记

| # | 风险 | 状态 | 缓解 |
|---|---|---|---|
| 1 | opennsl kmod `debian/control` 硬编码 trixie 内核名,apt Depends 不可满足 | **确认** | patch 改 Depends 为 `linux-image-7.0.0-1002-sonic`(§4.3b) |
| 2 | opennsl kmod `debian/rules` ABI 推导丢 `-1002`,与实际内核 ABI 不匹配 | **确认** | patch 改 KVER 解析(§4.3a) |
| 3 | 闭源 SAI .deb 在 Ubuntu 26.04 的 glibc 依赖 | **已 de-risk(无问题)** | 已 `dpkg-deb -I` 实查,依赖全是 `>=` 下界 |
| 4 | libprotobuf32t64 vs libprotobuf32 包名 | **确认(小点)** | 构建期实查 + 可选 equivs(§5) |
| 5 | GCC15 链接闭源 libsaibcm 编 sswsyncd/libsaithrift-dev | 推测(只能实编) | M2 验证,C ABI 稳定大概率 OK |
| 6 | build-arch 软链假设不适配 resolute Ubuntu 风格 headers 结构 | 推测 | M1 验证,按需扩 patch |
| 7 | Broadcom 镜像 resolute 上零构建验证 | **确认** | 本设计三里程碑递进验证 |

## 10. 后续

本设计通过后,转入 `superpowers:writing-plans` 生成详细实施计划,按 M1 → M2 → M3 递进执行。
