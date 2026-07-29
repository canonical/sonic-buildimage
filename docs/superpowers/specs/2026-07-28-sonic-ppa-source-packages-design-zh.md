# 把上游软件的 deb 打包从 sonic-buildimage 解耦到 Launchpad PPA — 设计

**日期**：2026-07-28
**分支**：设计文档在 `202605_resolute_doc`；实现在自 `202605_resolute_sheldon` 派生的 worktree 分支
**目标发行版**：Ubuntu 26.04 `resolute`（`BLDENV=resolute`）
**相关**：[2026-07-10 Launchpad 内核迁移方案](../plans/2026-07-10-sonic-202605-resolute-launchpad-kernel-migration-plan-zh.md) 已把内核切到 PPA 消费，本设计沿用同一消费模式

---

## 1. 目标

把「第三方上游软件的 deb 打包」从 `sonic-buildimage` 的镜像构建中解耦出去：镜像构建不再编译这些包，改为从 Launchpad PPA 拉取预编译产物；打包配方（补丁 series、版本号、stock 源地址）仍留在本仓库，作为生成 PPA 源码包的唯一依据。

本次只搭架子并打通首批三个包，不做全量迁移。

### 1.1 非目标

- **不以加速构建为目标。** 实测（`target/debs/resolute/*.log`，57 个包全为真实构建 `CACHE::SAVED`）deb 阶段合计 4335 秒 ≈ 72 分钟，其中本设计涉及的两类包只占约 18 分钟（25%），而最容易搬走的第一类只占 7 分钟（10%）。剩余 75% 是 SONiC 自研组件与构建期需要网络的包，PPA 帮不上。加速不成立，本设计不以此为卖点。
- **不解耦源码。** `src/<pkg>/patch/series` 继续留在本仓库。理由见 §4.1。
- **不动 SONiC 自研组件**（`swss` / `sairedis` / `sonic-gnmi` / `sonic-host-services` 等）。它们本就该在树里。
- **不做上游化 / MIR。** 补丁能否推上游是另一件事，不在本设计范围。
- **不动 `trixie` / `bookworm` / `bullseye`。** 所有开关默认关闭，非 resolute 构建行为完全不变。

---

## 2. 范围

### 2.1 纳入（29 个源码树）

**第一类：dget/wget 拉取真实 Debian/Ubuntu 源码包 + SONiC 补丁（15 个）**

`bash`、`initramfs-tools`、`iproute2`、`iptables`、`isc-dhcp`、`kdump-tools`、`libteam`、`libyang3`、`lm-sensors`、`monit`、`openssh`、`redis`、`socat`、`thrift`、`mpdecimal`

这类的 `src/<pkg>/Makefile` 是同一个模式：

```make
dget -u .../<pkg>_<ver>.dsc      # 拉官方源码包
git init && stg init
stg import -s ../patch/series     # 叠 SONiC 补丁（bash 用 quilt push -a）
dpkg-buildpackage -us -uc -b      # 只出 binary
```

**本设计最初在这里写错了，实现阶段实测推翻，现修正如下。** 原premise是「把同一 series 按同一顺序追加进 `debian/patches/series` 即等价」。它只在一种情况下成立，实际需要两条规则：

1. **取源码时不能让补丁被预先应用。** `dget -u` 会经 `dpkg-source -x` 把上游 `debian/patches` 全部应用并留下 `.pc`。必须改用 `dget -d -u`（只下载）+ `dpkg-source --skip-patches -x`，让工作树保持原始状态；上游补丁与 SONiC 补丁都以**未应用**状态并列在 series 里，由 builder 在构建时统一应用。
2. **改 `debian/` 的补丁不能进 series。** 在 `3.0 (quilt)` 里 `debian/patches/*` 是打在**上游源码**上的；`debian/` 目录本身以最终内容装进 debian tarball，且 `dpkg-source` 计算自动补丁时忽略 `debian/` 下的改动。因此一个修改 `debian/rules` 的补丁若同时列在 series 里，会在 builder 端被**二次应用**，报 `Reversed (or previously applied) patch detected!`。这类补丁必须**直接应用到工作树**（让效果烘进 debian tarball），且**不列入 series**。

实测三个首批包的补丁构成：

| 包 | 只改 `debian/` | 只改上游 | 上游源码包自带的 quilt 补丁 |
|---|---|---|---|
| `libteam` | 0 | 14（全部） | 0（连 `debian/patches/series` 都没有） |
| `isc-dhcp` | 4 | 14 | 10 |
| `lm-sensors` | 2（全部） | 0 | 14 |

`libteam` 恰好一个 `debian/` 补丁都没有、上游也零补丁，这正是它能率先端到端跑通、而问题直到 `isc-dhcp` 才暴露的原因 —— 也说明「先做最干净的基线包」这个选包策略是对的：它把脚手架本身的问题和包特有的问题分开了。

**第二类：上游 tarball / git + SONiC 自写 `debian/`（14 个源码树）**

`ifupdown2`、`thrift_0_14_1`、`libyang3-py3`、`wpasupplicant`、`sonic-device-data`、`sflow/{hsflowd,psample,sflowtool}`、`tacacs/{audisp,nss,pam,bash_tacplus}`、`radius/{nss,pam}`

这类需要额外一步：把当前的 clone/download 逻辑前移成「生成 `orig.tar.*`」，然后 `debian/` 原样搬入。`radius/pam` 最麻烦，要把 `freeradius-server` 和 `pam_radius` 两个仓库合成一个 orig。

### 2.2 排除

| 包 | 排除原因 |
|---|---|
| `sonic-fips` | 构建期 `git clone` + 从 `BUILD_PUBLIC_URL` `curl` 预编译产物 |
| `dash-sai` | 构建期 `git clone` DASH + `git submodule update` |
| `sonic-p4rt` | Bazel，构建期拉大量外部依赖 |
| `p4lang`（pi/bmv2/p4c） | 源自 openSUSE OBS 的第三方 dsc，且 boost 强绑定 |
| `sonic-frr` | 构建期 clone frr submodule + stgit 叠 85 个补丁。技术上可做，工程量单独一个档次，列为独立的第二阶段 |
| `grpc`、`protobuf` | `ifeq ($(BLDENV),bullseye)`，resolute 不构建 |
| `snmpd` | `ifeq ($(BLDENV),bookworm)`，resolute 不构建 |
| `sonic-redfish` | `ifeq ($(BLDENV),trixie)`，resolute 不构建；且构建期 clone |
| SONiC 自研组件（28 个） | `debian/rules` 里跑 pip/go/cargo，且与镜像版本同步演进 |

Launchpad builder 在**无网络**的干净 chroot 里运行，这是排除的唯一实质标准 —— 不是「有没有二进制」。预编译二进制放进 `orig.tar.*` 由 `debian/rules` 安装是合法形态（`sedutil` 就是这种）；放进 `debian/` 目录则需要 `debian/source/include-binaries`；真正被禁的是在上传里夹带 `.deb`（PPA 只收 source upload）。

---

## 3. 调研得出的硬约束

以下均已在本仓库核实，是设计的输入而非假设。

### 3.1 消费侧已有成熟先例

`rules/linux-kernel.mk` 已在从 Launchpad PPA(`canonical-kernel-team/bootstrap`)消费预编译内核，用的正是本设计要用的全套机制：`SONIC_ONLINE_DEBS` + `ppa.launchpadcontent.net/.../pool/main/` 直连 URL（`+files` 会重定向到 launchpadlibrarian.net，构建环境不可达）+ `_DEPENDS` 排装序。`rules/libnl3.mk`、`rules/lldpd.mk` 是同机制的 de-fork 先例。

### 3.2 include 顺序（决定生成物/函数放哪）

| 位置 | 内容 |
|---|---|
| `slave.mk:164-165` | `include rules/config`、`-include rules/config.user` |
| `slave.mk:289` | `include rules/functions` |
| `slave.mk:298` | `include rules/*.mk`（glob） |
| `Makefile.cache:129` | `include rules/*.dep`（glob） |

因此：全局开关放 `rules/config`（可被 `config.user` 覆盖），辅助函数放 `rules/functions`（文件名不含 `.mk`，不会被 glob 二次包含）。**任何生成物都不能放进 `rules/` 且以 `.mk` 结尾**，否则会被 298 行二次包含 —— 本设计不产生这类生成物。

### 3.3 online deb 的本地文件名可与 URL 不同名

`slave.mk:750-767` 的 online 规则核心是：

```make
$(foreach deb,$* $($*_DERIVED_DEBS), \
    curl -L -f -o $(DEBS_PATH)/$(deb) $($(deb)_CURL_OPTIONS) $($(deb)_URL) ... )
```

落盘名是 make 目标名，URL 独立。这一条同时解决了 dbgsym 扩展名问题（§7）。

### 3.4 `add_derived_package` 在 online 模式下可用

`rules/functions:89-99`：

```make
define add_derived_package
$(2)_DEPENDS += $(1)
...
$(1)_DERIVED_DEBS += $(2)
$(2)_URL = $($(1)_URL)          # 第 94 行：派生包继承主包 URL
...
```

派生包本来就进 `$*_DERIVED_DEBS`，被 §3.3 的 foreach 一并下载；只是默认继承主包 URL，需要在 `add_derived_package` 调用**之后**逐个覆盖 `_URL`。这意味着所有 `add_derived_package` 调用、`_DEPENDS`、`_RDEPENDS`、`DBG_SRC_ARCHIVE` 声明**都不需要改动**。

### 3.5 `.dep` 的空 SPATH 是已知雷

`rules/<pkg>.dep` 形如：

```make
SPATH       := $($(SOCAT)_SRC_PATH)
DEP_FILES   += $(shell git ls-files $(SPATH))
```

PPA 模式下 deb 名变了、`_SRC_PATH` 不再设置 → `SPATH` 为空 → `git ls-files` 列出整个仓库 → 命中符号链接/gitlink → `hash-object` 失败（`Makefile.cache:655`，grub2/libnl3 上已踩过）。必须加守卫。

### 3.6 dbgsym 在 Launchpad 上必然是 `.ddeb`

`sonic-slave-resolute/Dockerfile:649` 通过 sed 改 `/usr/share/perl5/Debian/Debhelper/Dh_Lib.pm` 的 `DBGSYM_PACKAGE_TYPE` 把 `ddeb` 改回 `deb`。Launchpad builder 上无法施加此补丁，产物一定是 `.ddeb`。本设计范围内有 14 个 `rules/*.mk` 引用 `-dbgsym`（`tacacs` 5 处、`iptables` 4 处、`libteam` 与 `lm-sensors` 各 3 处，其余 1–2 处）。

### 3.7 SONiC 在 Makefile 里做的事，在 PPA 上全部会丢

**这是本设计最大的风险源。** `src/<pkg>/Makefile` 里 `dpkg-buildpackage` 之外的一切都不在源码包内，Launchpad builder 看不到：

| 包 | 树外动作 | 到 builder 上的后果 |
|---|---|---|
| `isc-dhcp` | `export DEB_CFLAGS_MAINT_STRIP="-flto=auto -ffat-lto-objects"`、`DEB_LDFLAGS_MAINT_STRIP` 同 | **必然构建失败**（bind 9.11 vendored 的 LTO 链接错误） |
| `lm-sensors` | `PROG_EXTRA=sensord` | **静默少一个 binary**：不报错，但 `sensord` 不被构建，而 `docker-platform-monitor` 需要它 |
| `libyang3` | `sed -i -e '/.*libxxhash.*/d' debian/control`、`dpkg-buildpackage -d` | build-dep 解不开；`-d` 在 builder 上无效 |
| `bash`、`socat`、`lm-sensors`、`initramfs-tools` | `DEB_BUILD_OPTIONS=nocheck` / `-Pnocheck` | builder 会真跑测试套件 |
| `socat`、`openssh`、`monit`、`libyang3` | 部分补丁以 `patch -p1 < ../patch/xxx.patch` 硬打，**不在 series 里** | 转 quilt 时最易漏 |
| `iproute2` | `sed -i "1s/(ver)/(ver+sonic.0)/" debian/changelog` | 被本设计的 `dch` 流程替代 |
| `bash` | `cp -a ../Files/. ./` + `./configure` | 仅服务本地 UT，不影响产物 |

处理原则：**功能性与构建修复类的树外动作必须内化进 `debian/rules`**（作为一个 SONiC 补丁进 `debian/patches`）；仅服务本地测试的可以丢弃。每个包迁移时必须逐项过一遍这张表。

### 3.8 变量导出现状

多数第一类包的 `rules/<pkg>.mk` 已 `export` 版本变量（供 sub-make 使用）；`redis`、`thrift` 未 export 任何变量。stock `.dsc` 的 URL 目前**硬编码在 `src/<pkg>/Makefile` 里**，只有 `iproute2` 提成了 `IPROUTE2_DSC_URL`。

---

## 4. 方案选择

### 4.1 打包配方留在本仓库，不另建 packaging 仓库

**已否决的方案**：新建 `sonic-packaging` monorepo 或每包一个独立 git 仓库。

否决理由：本项目已有一次「源码分家导致静默分叉」的实际损失 —— 子模块分支不跟随超仓 rebase，gitlink 保留旧提交，上游修复被静默丢弃（SAI 计数器恒零的真因）。另建 packaging 仓库会造出同构的第二个分叉面：`rules/<pkg>.mk` 里的版本号在这边、补丁在那边，rebase 到 `sonic-net/202605` 时两边不同步无人会察觉。放在同一棵树里，补丁与消费它的版本号在同一个 commit 内变动，该风险消失。

代价是明确的：解耦的是**构建**，不是**源码**。`src/<pkg>/patch/` 继续留在树里。

### 4.2 用 Makefile 变量控制，不用 YAML

**已否决的方案**：`ppa/packages.yaml` + 生成器 + 生成的 `.mk`。

否决的决定性理由：YAML 必须重写一份版本号，而版本号已存在于 `rules/<pkg>.mk`（且 §4.1 的整个论证就是为了消灭第二真相）。逐项审查后，YAML 里绝大多数字段都可推导：

| 字段 | 是否需要 |
|---|---|
| Debian 源码包名 | 不需要 —— 从 dsc URL basename 推 |
| 版本号 | 不需要 —— 已在 `<PREFIX>_VERSION*` |
| stock dsc URL | 需要 —— 但用现有命名 `<PREFIX>_DSC_URL`（`iproute2` 已是此形态） |
| 补丁目录 | 不需要 —— 在 `src/<pkg>/` 下找含 `series` 的目录 |
| apply 方式（stgit/quilt） | 不需要 —— 造源码包不复现 apply 流程，补丁保持未应用状态 |
| `ddeb` 标记 | 不需要 —— deb 名以 `-dbgsym` 结尾即是 |
| 单包版本后缀覆盖 | 需要 —— 但可收进 `rules/config` 的按需变量 + 一个函数 |
| 候选包集合 | 不需要 —— 脚本传参，默认取 `SONIC_PPA_PACKAGES` |

Makefile 路线另有三项白送的收益：`rules/config.user` 提供 per-developer 覆盖（迁移期尤其有用，且这正是本项目唯一的本机改动文件）；`rules/*.mk` 已为 sub-make `export` 相关变量，脚本从 make 目标启动即可从环境读取，无需解析；`rules/config` 已有 51 个 `?=` 开关，风格一致。

YAML 唯一的优势是「一个文件看全所有包状态」。补偿办法是 `make ppa-manifest` —— 内容 100% 从 `.mk` 推导，是**产物**而非**真相**，永不漂移。

### 4.3 双模式，而非一刀切

每包保留本地自建路径，由 `SONIC_PPA_PACKAGES` 决定走哪条。任一包在 PPA 上出问题时改一个变量即可回退，不阻塞整镜像构建，也使「是否 PPA 引入的回归」可二分定位。跑稳后再逐步删除本地分支。

---

## 5. 架构

```
rules/config                     全局开关（config.user 可覆盖）
  ├─ SONIC_PPA_URL               PPA pool 根 URL（本阶段留空）
  ├─ SONIC_PPA_SUFFIX            全局版本后缀，默认 +sonic1~ppa1
  ├─ SONIC_PPA_SUFFIX_<pkg>      单包覆盖，按需出现
  └─ SONIC_PPA_PACKAGES          走 PPA 的包列表

rules/functions                  5 个辅助函数（见 §6.2）

rules/<pkg>.mk                   1 行改动 + 1 个 ifneq 块（见 §6.3）
rules/<pkg>.dep                  2 行插入（见 §6.4）

scripts/ppa/query.mk             唯一事实出口：在最小 stub 上下文里 include
                                 rules/<pkg>.mk，把模式/版本/dsc URL/补丁目录/
                                 deb 清单以 key=value 打印。下面三个脚本与单测
                                 共用它，因此这些信息只有 rules/*.mk 一个来源。
scripts/ppa/build-source.sh      容器内：产出未签名源码包 → target/source/<pkg>/
scripts/ppa/build-clean.sh       在一次性 ubuntu:resolute 容器里构建源码包，
                                 模拟 Launchpad builder（验收第 1 项）
scripts/ppa/sign-upload.sh       宿主机：debsign → dput
scripts/ppa/manifest.sh          make ppa-manifest 的实现，输出状态表
```

数据流：

```
rules/<pkg>.mk（版本 + dsc URL + 补丁目录）
        │
        ├──► make：决定该包从 PPA 下载还是本地构建
        │
        └──► build-source.sh：dget stock → 拷补丁进 debian/patches → dch → dpkg-buildpackage -S
                        │
                        └──► 宿主机 debsign + dput ──► Launchpad 构建 ──► PPA pool
                                                                              │
                                                        SONIC_ONLINE_DEBS curl ┘
```

---

## 6. 详细设计

### 6.1 `rules/config` 新增

```make
# ---- Launchpad PPA 消费（仅 resolute）----
# 走 PPA 而非本地自建的包。留空则行为与今天完全一致。
SONIC_PPA_PACKAGES ?=
# PPA pool 根 URL，例：https://ppa.launchpadcontent.net/<owner>/<name>/ubuntu
SONIC_PPA_URL ?=
# 版本后缀全局默认；单包重传时用 SONIC_PPA_SUFFIX_<pkg> 覆盖
SONIC_PPA_SUFFIX ?= +sonic1~ppa1
```

`SONIC_PPA_PACKAGES` 为空时所有 `ifneq` 分支不成立，非 resolute 构建与今天零差异。

### 6.2 `rules/functions` 新增

```make
# 单包后缀覆盖优先于全局
ppa_suffix = $(or $(SONIC_PPA_SUFFIX_$(1)),$(SONIC_PPA_SUFFIX))

# 仅当该包处于 PPA 模式时才产生后缀，供版本变量内联使用
ppa_ver = $(if $(filter $(1),$(SONIC_PPA_PACKAGES)),$(call ppa_suffix,$(1)))

# Debian pool 二级目录：libxxx → libx，其余取首字母
ppa_pool_dir = $(if $(filter lib%,$(1)),$(shell echo $(1) | cut -c1-4),$(shell echo $(1) | cut -c1))

# dbgsym 在 PPA 上是 .ddeb；只改 URL 一侧，make 目标名与落盘名仍是 .deb
ppa_file = $(if $(findstring -dbgsym,$(1)),$(patsubst %.deb,%.ddeb,$(1)),$(1))
ppa_url  = $(SONIC_PPA_URL)/pool/main/$(call ppa_pool_dir,$(1))/$(1)/$(call ppa_file,$(2))
```

五个函数一律加 `ppa_` 前缀 —— `rules/functions` 是全局命名空间，`pool_dir` 这种通用名容易与后续新增冲突。

`ppa_pool_dir` 的 `$(shell cut)` 每包只在 make 解析期执行一次，开销可忽略；若后续成为热点可改为纯 make 的 `$(word)` 实现。

### 6.3 `rules/<pkg>.mk` 改动形态

约束：**纯插入优先，不重排缩进**。本仓库需反复 rebase 到 `sonic-net/202605`（且已经历一次上游 force-rewrite），重排缩进会让上游每次改动这些文件都变成冲突。因此把后缀内联进版本变量，使所有 deb 名定义与 `add_derived_package` 调用保持字面不变；只在注册处插入 `ifneq/else/endif`。

以 `lm-sensors` 为例（唯一修改的行是版本行）：

```diff
-LM_SENSORS_VERSION_FULL=$(LM_SENSORS_VERSION)-2build1
+LM_SENSORS_VERSION_STOCK=$(LM_SENSORS_VERSION)-2build1
+LM_SENSORS_VERSION_FULL=$(LM_SENSORS_VERSION_STOCK)$(call ppa_ver,lm-sensors)
+
+LM_SENSORS_DSC_URL = http://archive.ubuntu.com/ubuntu/pool/main/l/lm-sensors/lm-sensors_$(LM_SENSORS_VERSION_STOCK).dsc

 ... 7 个 deb 定义与 add_derived_package 调用，全部原样不动 ...

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
+
+export LM_SENSORS_DSC_URL
```

要点：

- 必须引入 `_VERSION_STOCK` 中间变量。`_DSC_URL` 指向官方源码包，用的是 **stock 版本**（不含 PPA 后缀），因此不能复用已内联后缀的 `_VERSION_FULL`；若直接把 `-2build1` 字面量写进 `_DSC_URL`，则同一字面量出现两处、升版本时必漏其一。这是每个包迁移时最易出错的一处。
- `ppa_url` 里的 `pool/main/` 是硬编码且正确的：PPA 只有 `main` 一个 component，与该包在 Ubuntu 官方归档里属于 `main` 还是 `universe` 无关（例如 `monit` 官方在 universe，进 PPA 后仍在 `pool/main/m/monit/`）。
- `_URL` 覆盖必须位于所有 `add_derived_package` 调用之后（§3.4）。`lm-sensors.mk` / `libteam.mk` 的现有布局天然满足。
- `fancontrol` 是 `_all.deb`，名字来自现有变量，Arch: all 自动正确。
- 本地模式分支只留原有的 `SONIC_MAKE_DEBS += ...` 一行，`_SRC_PATH` 等声明保持在 `ifneq` 之外不动（在 PPA 模式下 `_SRC_PATH` 残留无害，`.dep` 的守卫按包名判断而非按 SPATH 是否为空判断）。

### 6.4 `rules/<pkg>.dep` 改动形态

2 行插入、0 行修改：

```diff
 SPATH       := $($(LM_SENSORS)_SRC_PATH)
 DEP_FILES   := $(SONIC_COMMON_FILES_LIST) rules/lm-sensors.mk rules/lm-sensors.dep
 DEP_FILES   += $(SONIC_COMMON_BASE_FILES_LIST)
+ifeq ($(filter lm-sensors,$(SONIC_PPA_PACKAGES)),)
 DEP_FILES   += $(shell git ls-files $(SPATH))
+endif
```

按包名而非按 `$(SPATH)` 是否为空判断，语义更明确，且与 `.mk` 的守卫条件一致。PPA 模式下缓存键退化为 `.mk` 内容 —— 其中包含版本号与后缀，因此改后缀会正确地使缓存失效并触发重新下载。

### 6.5 源码包生成脚本

签名与上传不在容器内进行 —— 把 GPG agent socket 挂进 DinD 容器代价高且脆弱。三个动作正交，各自可单独运行：

```
# 容器内（slave-resolute 已含 devscripts / quilt / stgit / python3-yaml）
scripts/ppa/build-source.sh <pkg>...
  1. dget -d -u $(<PREFIX>_DSC_URL)                 # -d 只下载不解包；-u 必需，因为 .dsc
                                                    #   上传者的个人 key 不在任何可用 keyring
     dpkg-source --skip-patches -x <dsc>            # 解包但一个补丁都不应用，工作树保持原始
  2. 定位 src/<pkg>/ 下含 series 的目录（多于一个则报错退出）
  3. 按 §2.1 的规则给每个生效补丁分类（依据其 `+++` 头里的路径）：
       只改上游文件 → 拷进 debian/patches/ 并追加进 series（保持未应用）
       只改 debian/ → 直接应用到工作树，不进 series
       两者都改     → 报错并指名该补丁，必须由人拆分
  4. 检查补丁是否含二进制文件；若有则报错（需 debian/source/include-binaries，B1 内目前没有）
  5. dch --newversion <stock版本><后缀> --distribution resolute --force-distribution
     （--force-distribution 必需：否则 dch 拒绝把 distribution 改成非当前值）
  6. dpkg-buildpackage -S -sa -us -uc               # 或 -sd，见下
  7. 落到 target/source/<pkg>/

# 宿主机（需 devscripts + dput；slave 镜像里没有 dput，无需添加）
scripts/ppa/sign-upload.sh [--key <KEYID>] [--upload]
  debsign -k <KEYID> target/source/*/*_source.changes
  dput ppa:<owner>/<name> target/source/*/*_source.changes
```

`-sa`（携带 orig）仅在该 upstream 版本首次上传时使用；后续同 orig 必须 `-sd`，否则 Launchpad 会因 orig 校验和冲突 reject。脚本依据「PPA 中是否已存在该 orig」自动选择，无法判定时默认 `-sd` 并提示。

`dget -u` 中的 `-u` 是结构性必需：Ubuntu slave 上 `.dsc` 上传者的个人 key 不在任何可用 keyring 中，装 `debian-keyring` 也验不了。

### 6.6 `make ppa-manifest`

打印每个候选包的：包名、模式（ppa/local）、stock 版本、生效后缀、产物 deb 列表、拉取 URL。用于替代 YAML 的「一览」价值。实现为 `scripts/ppa/manifest.sh`，由 `slave.mk` 的 phony 目标调用，数据全部来自已 export 的 make 变量。

---

## 7. 版本方案与 dbgsym

**版本**：`<stock版本><SONIC_PPA_SUFFIX>`，默认 `+sonic1~ppa1`。排序位于 stock 之上、下一个 Ubuntu 修订之下 —— `1.31-1build4+sonic1~ppa1` > `1.31-1build4` 但 < `1.31-1build5`。Ubuntu 发 SRU 时会自然盖过我们，这是期望行为。同一 SONiC 修订需要重传时把该包的后缀提到 `~ppa2`（`SONIC_PPA_SUFFIX_<pkg>`）；不能重用已上传过的版本号，Launchpad 会 reject。

**dbgsym**：产物在 PPA 上是 `.ddeb`（§3.6）。`ppa_file` 只改 URL 一侧，make 目标名与落盘名仍为 `...-dbgsym_<ver>_amd64.deb`，靠 §3.3 的 `curl -o` 撑住，SONiC 侧零改造。

前置条件：PPA 需开启 debug symbols 发布（per-PPA 设置，非默认开启）。**这是待验证项。** 若无法开启，退路是照 `rules/lldpd.mk` 的现成做法 —— 变量保留定义以免 `rules/docker-*.mk` 引用报错，但不加入 `SONIC_ONLINE_DEBS`，放弃这些包的调试符号。

---

## 8. 首批三个包

选包标准是**覆盖风险维度**，不是「先挑简单的」。

| 包 | 覆盖的风险 | 为什么非它不可 |
|---|---|---|
| **libteam** | 干净基线 | 14 个生效补丁全在 series 里（另有 4 个被注释掉）、**零树外动作**、7 个二进制（1 主 + 6 派生，含 3 个 dbgsym）、有 `_DEPENDS` 排序、有 `add_derived_package`。它跑不通即说明链路本身有问题，而非某包特殊。应第一个做。 |
| **isc-dhcp** | 构建必挂类 | `DEB_CFLAGS_MAINT_STRIP` / `DEB_LDFLAGS_MAINT_STRIP` 不内化进 `debian/rules` 就一定失败。17 个补丁（fuzz 风险最高）。Debian 源上传 Ubuntu PPA。 |
| **lm-sensors** | 构建成功但产物错 | `PROG_EXTRA=sensord` 是功能性树外变量，丢了不报错、只是 `sensord` 不存在，而 `docker-platform-monitor` 需要它。这是唯一一类静默失败，必须在首批验到，同时检验 §9 的验收标准是否真抓得住。外加 7 个二进制、含 `_all.deb`、含 nocheck。 |

**首批不含 `socat`**：它自建的唯一理由是 `enable_readline`，而 Debian/Ubuntu 是**故意**关闭 readline 的（GPL 与 OpenSSL 授权不兼容，Debian #632481）。在公开 PPA 中发布启用了 readline 的 socat，等于分发 Debian 认定不可分发的二进制。需先确定 PPA 公开/私有并作授权判断，不适合放在验证链路的这批里。其补丁还以 `patch -p1` 硬打、不在 series 中，多一层转换风险。

**首批不含 `bash`**：其独特风险（`DEB_BUILD_OPTIONS=nocheck` 丢失）已由 `lm-sensors` 覆盖；另一个树外动作 `cp -a ../Files/. ./` 仅服务本地 UT、不影响产物。

**第二批从 `libyang3` 开始**：它是树外动作最多的包 —— `sed -i` 删 `debian/control` 的 libxxhash build-dep、`patch -p1` 硬打、`-d` 跳过 build-dep 检查，三种外泄形态一次占全。

---

## 9. 验收标准

每个包独立验收，四项全过才算迁移完成：

1. **源码包可在干净环境中构建。** 用 `scripts/ppa/build-clean.sh` 在一次性 `ubuntu:resolute` 容器里构建生成的 `.dsc`，不依赖 slave 容器的任何预装内容。这一步在上传前本地完成，用来提前暴露 §3.7 的树外动作丢失。

  刻意**不用** `sbuild`/`pbuilder`：那需要往宿主机装 4 个包、建持久 `/srv/chroot` 树、`sbuild-adduser` 再重新登录，全部要 sudo；而本项目的规矩是宿主机改动只作最后手段。`ubuntu:resolute` 正是 slave 镜像自己的 `FROM` base，构建时已经拉好，`docker run --rm` 每次从原始镜像起因而天然干净，且**没有** slave 里那个 `Dh_Lib.pm` 补丁 —— dbgsym 会如实产出 `.ddeb`，顺带验证了 §3.6。保真度与 sbuild 相同：Launchpad builder 同样用 apt 解 `Build-Depends`，只是构建过程本身没有外网。
2. **产物文件清单一致。** `dpkg -c` 对比 PPA 产物与本地自建产物，除版本号字符串外文件列表一致。这是抓 `lm-sensors` 那类静默缺失的关键一项。
3. **二进制包集合一致。** PPA 实际发布的 deb 名单与 `rules/<pkg>.mk` 声明的主包 + 派生包集合完全对应，无缺无多。
4. **整镜像构建通过。** `SONIC_PPA_PACKAGES` 含该包的情况下走完 vs 与 broadcom 两个目标。

任一项不过：把该包从 `SONIC_PPA_PACKAGES` 移除即回退，不阻塞其他包。

---

## 10. 已知风险与未决事项

| 项 | 状态 | 说明 |
|---|---|---|
| PPA 归属与公私 | **未决**，本阶段不阻塞 | `SONIC_PPA_URL` 留空即可搭完架子并本地验证到「源码包在干净 chroot 中构建通过」。归属确定后才能完成上传与端到端验证。私有 PPA 的 pool 需要认证，`curl` 一侧要带凭据 —— 会引入 `_CURL_OPTIONS` 上的额外设计。 |
| dbgsym 发布开关 | **待验证** | 见 §7。退路已确定。 |
| `socat` 的 readline 授权 | **待判断** | 见 §8。 |
| 补丁 fuzz | 已知风险 | `stg import` 容忍 fuzz，而 `dpkg-source` 构建前应用补丁时零 fuzz。老补丁可能需要 refresh。`isc-dhcp` 的 17 个补丁风险最高，故列入首批。 |
| `DBG_SRC_ARCHIVE` 降级 | 已接受 | 该机制把 `src/<name>` 下的 `.c/.h` 归档进 debug 镜像。PPA 模式下该目录只剩补丁，归档内容会近乎为空。属外观性降级，不阻塞。 |
| `_DEPENDS` 语义漂移 | 已知 | 本地模式下 `$(LIBTEAM)_DEPENDS += $(LIBNL_GENL3_DEV) ...` 表达构建依赖；online 模式下 `_DEPENDS` 表达 `dpkg -i` 装序。保留原声明在 PPA 模式下语义不同但无害（装序更保守）。迁移时逐包确认不会引入循环。 |
| 构建可复现性 | 已接受的权衡 | 迁移后这些包的产物来自外部服务，不再「一切从源码本地可复现」。这是解耦的固有代价；双模式开关保留了随时回到本地构建的能力。 |

---

## 11. 实现顺序

1. `rules/config` 三个变量 + `rules/functions` 五个函数 + `scripts/ppa/query.mk` + 单测夹具。此时 `SONIC_PPA_PACKAGES` 为空，构建行为零变化。
2. `libteam` 接入：改 `.mk` / `.dep`，写 `build-source.sh` 产出源码包，写 `build-clean.sh` 并用它完成验收第 1 项。全程无需 sudo、不动宿主机。
3. `isc-dhcp` 接入：额外把 `DEB_*_MAINT_STRIP` 内化为一个进 `debian/patches` 的补丁。
4. `lm-sensors` 接入：额外把 `PROG_EXTRA=sensord` 内化进 `debian/rules`。
5. `make ppa-manifest`。
6. PPA 归属确定后：签名、上传、完成验收第 2–4 项。

第 1–5 步不依赖 PPA 归属，可立即开始。
