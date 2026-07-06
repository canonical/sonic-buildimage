# SONiC Resolute 迁移：修改分类目录

**仓库 / Repo:** `/home/sheldon-qi/sonic-buildimage-resolute`（branch `resolute`）
**对照基线 / Baseline:** `77cfa809d`（merge-base 与 `202605`）
**范围 / Scope:** `202605..resolute` = **70 个提交**，142 个非 `src/` 文件 + 43 个 `src/` 文件（含子模块指针与子模块内 Makefile/补丁）
**日期 / Date:** 2026-07-06
**状态 / Status:** ✅ `target/sonic-vs.bin` 构建成功并经 KVM 启动验证（os-release = Ubuntu 26.04）

> 本文是**按主题分类的修改目录**：回答"我们改了哪些方面、各为解决什么问题"。
> 与同目录另外两份文档互补——
> [resolute-migration-code-review-zh.md](resolute-migration-code-review-zh.md) 是**缺陷视角**（评审发现的问题与遗留）；
> [resolute-vs-migration-report-zh.md](resolute-vs-migration-report-zh.md) 是**按包的迁移叙事**（per-package 改动详录）。
> 本文是**按主题的正面修改目录**（problem → root cause → fix → files → commits）。

---

## 1. 背景与目标

把 SONiC 202605 的 VS 镜像构建基线从 **Debian trixie** 迁移到 **Ubuntu resolute (26.04)**。Ubuntu resolute 比 trixie 整体新一档工具链（GCC 15 / C23、Python 3.14、boost 默认 1.90、glibc 2.43、dpkg 1.23、cmake 4.x、doxygen 1.15、SWIG 4.4），且 Ubuntu 与 Debian 在包命名、镜像布局、源码包拆分上系统不同。这两类差异叠加，使"换 distro"远不止改 `FROM`——从构建管线、slave 镜像、子模块源码到运行时模板逐层失败。

本文把 70 个提交归纳为 **12 个主题**，每个主题说明：解决了什么问题、为何在 resolute 上破坏、如何修复、改了哪些文件。

---

## 2. 修改主题总览

| # | 主题 | 解决的问题（一句话） | 状态 | 提交数 |
|---|---|---|---|---|
| 1 | 管线与 distro 基座切换 | 把整条构建管线（apt 源、debootstrap、docker、基座镜像、固件）从 Debian 切到 Ubuntu resolute | ✅ | 9 |
| 2 | sonic-slave-resolute 构建镜像 | 创建 Ubuntu resolute slave 镜像并适配新工具链（boost 默认 1.90→pin 1.83、glibc fortify、thrift 0.22、Pillow、内核依赖） | ✅ | 11+3 |
| 3 | FIPS 复用 trixie 二进制 | resolute 无独立 FIPS 发布，靠 ABI 兼容复用 trixie FIPS 二进制 | ✅ | 3 |
| 4 | dbgsym `.ddeb` 单点修复 | Ubuntu debhelper 把 dbgsym 改产 `.ddeb`，单点 patch `Dh_Lib.pm` 改回 `.deb` | ✅ | 7 |
| 5 | dpkg Maintainer 字段严格性 | resolute dpkg 1.23 严格解析 Maintainer/changelog trailer，逐包修复非标准格式 | ✅ | 6 |
| 6 | grub2 Ubuntu 拆分与 C23 适配 | Ubuntu 拆分 src:grub2 + GCC15 C23 `bool` 关键字 + overlayfs 禁目录硬链接 | ✅ | 10 |
| 7 | libnl3 nh_id 别名 / FRR / isc-dhcp LTO | libnl3 API 重命名（`nh_id`↔`nhid`）+ GCC15 LTO 链接假阳性 | ✅ | 5 |
| 8 | 工具链驱动的 submodule 指针升级 | 14 个子模块内打源码补丁（C++17/boost1.88/SWIG4.4/doxygen1.15/py3.14）并 bump 父指针 | ✅ | 4 |
| 9 | 包级构建修复 | cmake4 兼容、dget 跳 GPG、dbgsym mv 兜底、libwtmpdb、libyang3 宏、libstdc++ 头 | ✅ | 6 |
| 10 | resolute 命名 variant 重构 | 创建 resolute 命名 base 链，trixie variant 还原 pristine，两套并存 | ✅ | 1（113 文件） |
| 11 | fsroot-vs pip 生态与 pkgutil 运行时修复 | py3.14 移除 `pkgutil.get_loader`、pip/GCC15/glibc 断层、rsync EBUSY | ⚠️ 部分 | 2 |
| 12 | 文档与交付状态记录 | Category-C 包替换目录 + done-bar 验证矩阵 | ✅ | 3 |

> 提交数列：每个主题直接归入的提交数（含跨主题复用）。#2 的"11+3"指 11 个直接归入 + 3 个构建系统打磨提交（`7db6e8e0b`/`f40481279`/`08aa45d64`，概念已在该主题 notes 覆盖）。去重后总提交 70。

---

## 3. 根因分类（工具链差异映射）

迁移中所有失败可归为 7 类工具链差异（与 [迁移报告 §2](resolute-vs-migration-report-zh.md) 一致），下表把 12 个主题映射到根因类别：

| 根因类别 | trixie | resolute | 命中主题 |
|---|---|---|---|
| 1. dpkg 解析严格化 | 宽松 | 严格（dpkg 1.23） | #5 Maintainer、#4 dbgsym |
| 2. GCC 15 / C23 | GCC 14 / C17 | GCC 15 / C23 | #6 grub2、#2 slave（gnu17）、#8 子模块 |
| 3. C++17 + libstdc++ 15 | C++14 可用 | gtest 要求 C++17 | #8 子模块、#2 slave（boost 1.88） |
| 4. LTO 假阳性 | 偶发 | 普遍（`-flto=auto`） | #7 FRR/isc-dhcp、#8 子模块 |
| 5. doxygen 1.15 | 1.9.8 | 1.15.0 | #8 SAI `Doxyfile` |
| 6. boost 默认 1.90（header-only） | 1.83 default | 1.90 default（1.83/1.88 在 universe） | #8 swss-common/linkmgrd（早期按 1.88 迁移）、#2 slave（pin 1.83） |
| 7. Python 3.14 / 包名变更 | py3.13 / 旧名 | py3.14 / 新名 | #11 pkgutil/pip、#6 grub2 拆分、#1 包重命名 |

另有两类**架构性差异**（非工具链版本）：
- **Ubuntu vs Debian 源码包布局**：组件、镜像源、debootstrap 缓存路径、docker 上游版本串、grub2 源码包拆分（主题 #1、#6、#10）。
- **构建系统硬编码 distro 字面量**：leaf docker `ARG BASE` 用字面量 trixie、`slave.mk` 无 resolute 分支、FIPS mk 无 resolute 块（主题 #1、#2、#3、#10）。

---

## 4. 各主题详述

### 4.1 管线与 distro 基座切换

**问题 / Problem**
SONiC 202605 构建管线每一层都硬编码为 Debian：apt sources 模板只产出 `main contrib non-free-firmware`；debootstrap/docker-engine/源码包全走 `deb.debian.org`；docker 上游版本串是 `~debian.13~trixie`；基座镜像 `FROM debian:trixie`；`DEFAULT_CONTAINER_REGISTRY` 指向只镜像 Debian 的 `publicmirror.azurecr.io`；`build_debian.sh` 装 Debian non-free 固件。把 `IMAGE_DISTRO` 切到 resolute 后每一层失配，slave 构建、debootstrap、docker 基座拉取、`rfs.squashfs` apt install 全线失败。

**根因 / Root Cause**
resolute = Ubuntu 26.04 LTS，与 trixie 在三方面系统不同：
1. **组件布局**：Ubuntu 用 `main universe multiverse restricted`，无 `contrib`/`non-free-firmware`/`non-free`。
2. **镜像源**：Ubuntu amd64 走 `archive.ubuntu.com/ubuntu`、armhf/arm64 走 `ports.ubuntu.com/ubuntu-ports`、security 走 `security.ubuntu.com/ubuntu`；`deb.debian.org` 不含 Ubuntu 包。debootstrap 写的 apt-list 缓存路径变为 `archive.ubuntu.com_ubuntu_dists_*`，而 `build_debian_base_system.sh` 仍 grep Debian 路径 → 空 → 失败。
3. **libc6 ABI**：`ubuntu:resolute` libc6 2.43 vs `debian:trixie` 2.41；resolute 编出的 deb（如 socat 1.8.1.1）声明 `Depends: libc6 (>= 2.42)`，trixie 基座 `dpkg -i` 报 `however`。
4. **包名重命名**：`libncurses5-dev` 删除、`libboost-system-dev`→版本号包、`dnsutils`→`bind9-dnsutils`、`qemu-kvm`→`qemu-system-x86`、`libpam-dev`→`libpam0g-dev` 等；9 个包无 installation candidate。
5. **固件**：`firmware-linux-nonfree` 是 Debian non-free 包，Ubuntu 改在 main 提供 `linux-firmware`。
6. **源码版本**：SONiC 钉的 bash 5.2.37/socat 1.7.4.1/libnl3 3.7.0/libyang3 3.12.2/grub2 2.06 都是 trixie 版，Ubuntu pool 里没有，resolute 原生版本是 5.3/1.8.1.1/3.12.0/3.13.6/2.14。

**修复 / Fix**
- `files/apt/sources.list.j2` 新增 `DISTRIBUTION == 'resolute'` 分支（`components='main universe multiverse restricted'`），所有 deb/deb-src 行改用 `{{ components }}` 变量；`scripts/build_mirror_config.sh` 与 `build_debian_base_system.sh` 加 resolute 块（debootstrap MIRROR_URL + apt-list 缓存路径对齐 Ubuntu 写入路径）。
- `build_debian.sh`：docker 版本串改 `5:29.6.1-1~ubuntu.26.04~$IMAGE_DISTRO`、containerd `2.2.5-1~ubuntu.26.04~$IMAGE_DISTRO`，GPG key/repo 指向 `download.docker.com/linux/ubuntu`；固件改 `linux-firmware || true`。
- `rules/config.user`：`DEFAULT_CONTAINER_REGISTRY =`（置空，使 `Makefile.work` 不追加 `/`，直接从 docker.io 拉 `ubuntu:resolute`）。
- `sonic-slave-resolute/Dockerfile.j2`：9 个 Debian 专用包重映射为 resolute 等价名。
- `23ae50b13`：5 个包换到 resolute 原生版本并经 `dget` 从 `archive.ubuntu.com/ubuntu/pool` 取源（bash 5.3、socat 1.8.1.1、libyang3 3.13.6、libnl3 3.12.0、grub2 2.14），原 SONiC 专用补丁（quilt/stg/patch apply）注释为 TODO 待移植。
- `dockers/docker-base-trixie/Dockerfile.j2`：三条 `ARG BASE` 全部从 `debian:trixie` 改 `ubuntu:resolute`（基座 libc6 2.43 匹配 resolute deb 的 `>= 2.42`）。*（此为"早期方案"，后续主题 #10 才创建 resolute 命名目录并把 trixie 还原 pristine。）*

**关键文件 / Key Files**
`files/apt/sources.list.j2`、`scripts/build_mirror_config.sh`、`scripts/build_debian_base_system.sh`、`build_debian.sh`、`rules/config.user`、`sonic-slave-resolute/Dockerfile.j2`、`rules/{bash,grub2,libnl3,libyang3,socat}.mk`、`src/{bash,grub2,libnl3,libyang3,socat}/Makefile`、`dockers/docker-base-trixie/Dockerfile.j2`

**提交 / Commits**
`7c13fdbd9` `8f4fc81ed` `a4874681d` `41bec4fdb` `9713d304e` `cb80ffdf6` `23ae50b13` `3d265d73b` `92b24de74`

**状态 / Status** ✅ 已解决（vs 构建验证：os-release=Ubuntu 26.04）

**遗留 / Caveats** `23ae50b13` 把所有补丁 apply 步骤注释为 TODO（bash plugin、socat fix-strchr、libyang3 pr2362、libnl3 RTA_NH_ID、grub2 build-rules）——补丁移植落到后续主题（#6/#7/#9）；`LINUX_KERNEL_VERSION` 仍为 `6.12.41+deb13`，内核另作处理（主题 #8）。

---

### 4.2 sonic-slave-resolute 构建镜像

**问题 / Problem**
SONiC 用一个按发行版生成的 "slave" Docker 镜像（`sonic-slave-<distro>`）内含完整工具链与编译依赖，所有 .deb 都在此容器内构建。master 只有 `sonic-slave-trixie`。要从零创建 `sonic-slave-resolute`（`FROM ubuntu:resolute`，改用 Ubuntu docker 仓库），并让 `Makefile`/`slave.mk`/`Makefile.work` 识别 `BLDENV=resolute`。slave 镜像本身构建时会因 trixie 与 resolute 工具链的版本/符号差异逐项失败。

**根因 / Root Cause**
1. **Python 3.14**：pip 上 Pillow 11.1.0 无 cp314 wheel，被迫源码编译，缺 libjpeg 头。
2. **boost 默认 1.90**：1.90 起 `boost_system` 改 header-only，不再提供 `libboost_system.so`，而 systemd-sonic-generator 链接 `-lboost_system`，且 `ssg-test.cc` 调用已删除的 `boost::filesystem::extension`。
3. **glibc 2.41 + `_FORTIFY_SOURCE=3`**：fortify 宏经 `_Generic` 把 `strchr()` 返回包成 `const char*`，socat `filan.c:994` 的 `*strchr(s,'\n')='\0'` 报 "assignment of read-only location"。
4. **thrift 0.22.0**（trixie 为 0.19.0t64）：原 `libthrift-0.19.0t64` 包不存在。
5. **内核构建依赖**：`apt build-dep linux` 不满足 SONiC 内核 Build-Depends-Arch（`lz4`、`gcc-14`、`kernel-wedge>=2.105`），且 `config_v2.py:18 import dacite`（未安装）。
6. **gcc-multilib** 不再被传递依赖拉入（grub2 构建 i386 模块需要），`dh-python` 缺失（ifupdown2 build-dep）。

**修复 / Fix**
- 新建 `sonic-slave-resolute/Dockerfile.j2`（839 行，以 trixie 为蓝本改 `FROM ubuntu:resolute`、docker 源指向 `download.docker.com/linux/ubuntu`）+ `Dockerfile.user.j2`、`docker.sources`、`pip.conf`（`break-system-packages=true`）。
- 接线 `BLDENV=resolute`：`Makefile` 加 `NORESOLUTE`（默认 0=构建 resolute，同时把 `NOBOOKWORM`/`NOTRIXIE` 默认置 1）与 `BUILD_RESOLUTE` 分支；`Makefile.work` 把 `BLDENV=resolute` 映射到 `SLAVE_DIR=sonic-slave-resolute`；`slave.mk` 设 `IMAGE_DISTRO:=resolute`。
- `rules/config.user`：`INCLUDE_FIPS=y`、`PLATFORM=vs`、ccache、`BUILD_SKIP_TEST=y`、docker cache、`KERNEL_PROCURE_METHOD=download`、`SONIC_DPKG_CACHE_METHOD=rwcache`、`SONIC_VERSION_CACHE_METHOD=none`（启用 version cache 会让 slave Dockerfile 的 wget 静默跳过下载）。
- boost 全部 dev 包钉到 **1.83**（`libboost1.83-dev` + `libboost-*-1.83-dev`，18 行 `1.88-dev`→`1.83-dev`）。**选 1.83 而非 1.88 的理由**：resolute 默认 `libboost-dev` 是 1.90（main，`boost_system` header-only 无 `libboost_system.so`），必须 versioned pin；1.83/1.88 都在 universe，但 **1.83 对齐 trixie/bookworm 上游**（trixie `libboost-dev` default 即 1.83，bookworm slave 亦 pin 1.83），且 1.83 保留 `io_service`/`io_context::work`/`boost::filesystem::extension`/`std::hash<uuid>`（1.88 删的）。实验验证：slave 重建 + libswsscommon/sonic-eventd/systemd-sonic-generator/sonic-linkmgrd 四包在 1.83 header 下编译通过。早期曾 pin 1.88（触发 linkmgrd 49 文件 io_context 迁移，见 #8），改 1.83 后迁移代码兼容保留不回退。+ 补 `dh-python`。
- socat：新增 `src/socat/patch/fix-strchr-const-write.patch`（`filan.c:994` 改临时变量 `char *nl=strchr(s,'\n'); if(nl) *nl='\0';`）。
- thrift 改装 `libthrift-0.22.0` + `libthrift-dev` + `thrift-compiler` + `python3-thrift`；Pillow 源码编译补 `libjpeg-dev` + `zlib1g-dev`；内核显式装 `lz4 gcc-14 kernel-wedge` + `python3-dacite`；显式装 `gcc-multilib`。
- `systemd-sonic-generator/debian/rules`：`override_dh_auto_test` 增加 `findstring nocheck,$(DEB_BUILD_OPTIONS)` 跳过 make test。早期 pin 1.88 时 ssg-test 因 `boost::filesystem::extension` API 删除而**编译失败**；改 1.83 后该 API 恢复、ssg-test 能编译，但 `make test` 运行时 buffer overflow（GCC15 `_FORTIFY_SOURCE` 抓出 ssg 代码 `realpath` 返回值未检查）——非 boost 问题。nocheck 仍保留（响应全局 `BUILD_SKIP_TEST=y`），但原因从"boost API 删"变"ssg 自身代码债"。
- 另 3 个构建系统打磨提交：`7db6e8e0b`（`git reset --hard` 无条件化，原仅 CROSS 分支）、`f40481279`（全局 `APPEND CFLAGS -std=gnu17` + 放宽 GCC15 `-Werror` for bash + `libnl3` `--force-depends` 安装）、`08aa45d64`（修 `Dockerfile.user.j2` 的 `FROM sonic-slave-resolute`）。

**关键文件 / Key Files**
`sonic-slave-resolute/{Dockerfile.j2,Dockerfile.user.j2,docker.sources,pip.conf}`、`rules/config.user`、`Makefile`、`Makefile.work`、`slave.mk`、`src/socat/Makefile`、`src/socat/patch/fix-strchr-const-write.patch`、`src/systemd-sonic-generator/debian/rules`

**提交 / Commits**
`760e09cc3` `e16c4d8b8` `5e29f4bcd` `ad5f75252` `fde427606` `c70f10552` `3b03d9928` `1c3e48e58` `65772aba9` `7a7c1fa4d` `e3a75d22f` ＋ `7db6e8e0b` `f40481279` `08aa45d64`

**状态 / Status** ✅ 已解决（vs 平台验证；非 vs/交叉构建路径未充分验证）

**遗留 / Caveats** Docker engine 钉到 `5:29.6.1-1~ubuntu.26.04~resolute`；FIPS Go 仍从 `fips/trixie/` 下载（见主题 #3）；`Dockerfile.j2` 末尾 vendor include 仍写 `DEBIAN_VERSION='trixie'`（潜在残留）；全局 `-std=gnu17` 层级偏粗（见评审 I14，`wpasupplicant` 对 `.cpp` 用 `$(CC)$(CFLAGS)` 需额外补救）；交叉构建路径仍装 unversioned `libboost-dev:$arch`（→1.90，评审 I25 latent，未随 1.83 落地一并修）。

---

### 4.3 FIPS 复用 trixie 二进制

**问题 / Problem**
`rules/sonic-fips.mk` 只为 trixie/bookworm/bullseye 写了版本块。`BLDENV=resolute` 匹配不到任何块，`FIPS_VERSION`/`FIPS_GOLANG_*` 全空，拼出畸形 URL（`fips/trixie//amd64/golang--go__amd64.deb`），wget 退出码 8；`FIPS_URL_PREFIX=$(BUILD_PUBLIC_URL)/fips/$(BLDENV)/...` 拼出 `fips/resolute/...`，而 mirror 上只有 `fips/trixie/`（`fips/resolute/` 404），FIPS slave 构建中断。

**根因 / Root Cause**
sonic-fips.mk 用 `ifeq ($(BLDENV), trixie|bookworm|bullseye)` 三选一块，resolute 无分支。能复用 trixie 二进制的前提是 **ABI 兼容**：resolute 与 trixie 同处 glibc 2.43 t64 transition，共享 `libssl3t64`/`libgssrpc4t64`（64-bit time_t 转义后的 t64 包名），故 FIPS openssl 3.5.4-1+fips / Go 1.24.4-1+fips / krb5 1.21.3-5+fips 的 trixie 二进制可在 resolute 上直接 dpkg 安装。

**修复 / Fix**
`rules/sonic-fips.mk` 新增 `ifeq ($(BLDENV), resolute)` 块，镜像 trixie 全部 FIPS 版本号（`FIPS_VERSION=1.8.0-24-gd744cf2-2`、`FIPS_OPENSSL_VERSION=3.5.4-1+fips`、`FIPS_OPENSSH_VERSION=10.0p1-7+fips`、`FIPS_PYTHON_VERSION=3.13.5-2+fips`、`FIPS_GOLANG_VERSION=1.24.4-1+fips`、`FIPS_KRB5_VERSION=1.21.3-5+fips`），三个包名分支加 resolute（`FIPS_OPENSSL_LIBSSL=libssl3t64_*`、`FIPS_GOLANG_SRC=golang-1.24-src_*_all.deb`、`FIPS_KRB5_LIBGSSRPC4=libgssrpc4t64_*`）。引入 `FIPS_DOWNLOAD_BLDENV` 解耦下载路径与 `BLDENV`：resolute 块内 `FIPS_DOWNLOAD_BLDENV = trixie`，`FIPS_URL_PREFIX` 改用 `$(FIPS_DOWNLOAD_BLDENV)`。回退：`config.user` 设 `INCLUDE_FIPS=n` 走 Ubuntu 官方 resolute `golang-go` + `openssl`。

**关键文件 / Key Files**
`rules/sonic-fips.mk`、`sonic-slave-resolute/Dockerfile.j2`、`rules/config`、`docs/superpowers/plans/fips-status.txt`

**提交 / Commits**
`d2dc94d34` `be892f7f6` `a1e350554`

**状态 / Status** ✅ 已解决（trixie FIPS Go 1.24.4-1+fips 在 resolute slave 安装成功，未触发回退）

**遗留 / Caveats** 复用依赖 resolute 与 trixie 共享 glibc 2.43 t64 transition；若日后 glibc 分叉此复用会失效。`Dockerfile.j2:589-590` 硬编码 `fips/trixie` Go 路径与 mk 层 `FIPS_URL_PREFIX` 是两条独立路径，需保持一致。

---

### 4.4 dbgsym `.ddeb` 单点修复

**问题 / Problem**
大量 src Makefile 的 dbgsym 搬移步骤失败，报 `mv: cannot stat ...-dbgsym_*.deb`。受影响：通用 deb 宏 `SONIC_MAKE_DEBS`（`slave.mk` 的 `mv -f ... $* $($*_DERIVED_DEBS) ...`）与 `src/radius/{nss,pam}` 的 `mv $(DERIVED_TARGETS) ...`（匹配 `*-dbgsym_*.deb` glob）。trixie 上正常，resolute 上对空 glob 原子失败，vs 构建在多个包处中断。

**根因 / Root Cause**
resolute 是 Ubuntu，debhelper 在 `/usr/share/perl5/Debian/Debhelper/Dh_Lib.pm` 把常量 `DBGSYM_PACKAGE_TYPE` 硬编码为 `'ddeb'`（trixie 为 `'deb'`）；`dh_builddeb` 据此把自动生成的 dbgsym 包从 `.deb` 重命名为 `.ddeb`。SONiC src Makefile 全部按 trixie 的 `.deb` 后缀编写，在 resolute 上对 `.ddeb` 文件做 `.deb` glob 自然匹配为空。注：resolute 并非"不生成 dbgsym"，而是生成后改名——这是早期几条 band-aid 误判的根源。

**修复 / Fix**
**单点根因修复**：`sonic-slave-resolute/Dockerfile.j2` 末尾新增一条 RUN，用 `grep -q "DBGSYM_PACKAGE_TYPE' => 'ddeb'"` 检测 + `sed -i "s/...ddeb/...deb/"` 把 `Dh_Lib.pm` 常量改为 `'deb'`，再 `grep -q "...'deb'"` 校验。这样 resolute 的 dbgsym 包保持 `.deb` 后缀（与 trixie 一致），所有上游 Makefile 无需改动。两端的 `grep -q` 守卫使补丁幂等，并在 upstream 改了常量值时显式失败。随后 `e13951d8e` 回退此前所有针对症状的临时方案：`slave.mk` 移除 `noautodbgsym`、恢复原始 `mv -f`；`radius/{nss,pam}` 恢复上游 `-mv`；丢弃 28 个未提交的 `|| true` Makefile 改动。

**关键文件 / Key Files**
`sonic-slave-resolute/Dockerfile.j2`、`slave.mk`、`src/radius/nss/Makefile`、`src/radius/pam/Makefile`

**提交 / Commits**
`f748d5301` `e4fb165c7` `7dc9f6755` `0b0987805` `7e401df58` `c1dfdf0a3` `e13951d8e`

**状态 / Status** ✅ 已解决（真实 vs 构建：补丁下 0 个 .ddeb 重命名，17 个 deb 顺利完成）

**遗留 / Caveats** `noautodbgsym`（`7e401df58`）是错误尝试（会丢 debug deb），已回退；只有 `Dh_Lib.pm` 常量是真正杠杆。补丁在 slave 容器构建期 sed 应用，需 rebuild slave 镜像才生效。补丁非幂等的脆弱性（`grep -q ddeb && sed`）见评审 I13——靠 slave 总从 fresh `FROM ubuntu:resolute` 重建才 work。

---

### 4.5 dpkg Maintainer 字段严格性

**问题 / Problem**
上游多个源码包的 `debian/control` Maintainer 字段或 `debian/changelog` trailer 用了非标准格式（trixie 容忍）。resolute dpkg 1.23 在解析阶段直接 error 退出，导致 hsflowd、rasdaemon、python3-libyang、sonic-fib 等无法构建。四类失效：(1) 逗号分隔多 Maintainer（rasdaemon `Russell Coker <..>, Taihsiang Ho <..>`）；(2) 方括号邮箱（host-sflow `Neil McKee [neil.mckee@inmon.com]`）；(3) `None <None>` 占位符（libyang3-py3 由 stdeb 生成时未设 `DEBFULLNAME`/`DEBEMAIL`）；(4) changelog 缺 trailer（sonic-fib 末行空）。

**根因 / Root Cause**
dpkg 1.23 收紧 `Dpkg::Control::FieldsCore::field_parse_maintainer`：经 `Dpkg::Email::Address->new($maint)` 严格按 RFC 5322 / Debian policy 校验，失败即 `error('cannot parse Maintainer field value')`，不再容忍多 Maintainer 逗号列表与方括号地址。changelog trailer 由 `Dpkg::Changelog::Parse` 另一条路径解析，resolute 报 `cannot parse maintainer email address "None <None>"`，空 trailer 同被拒。trixie 解析宽松，这些历史格式从未修正。陷阱：hsflowd Makefile 每次构建都 `git clone github.com/sflow/host-sflow`，直接改本地 git 的 Maintainer 是 no-op，必须在 clone + `cp -r DEBIAN_build/* debian` 之后于 Makefile 内 sed。

**修复 / Fix**
方案经一次反转。第一次（`8bbdb1471`）做全局 Perl 补丁改写 `field_parse_maintainer`（失败回退取首 Maintainer / `[email]`→`<email>` + warning）。随后（`2d30538b7`）撤销全局补丁（理由：掩盖真实错误），改为每包源头 sed：
- hsflowd Makefile：`cp -r DEBIAN_build/* debian` 后 sed `Neil McKee [..]` → `Neil McKee <..>`；
- rasdaemon Makefile：`git apply` 后 sed 删多 Maintainer（保留首个）；
- libyang3-py3 Makefile：quilt 后 sed `None <None>` → `SONiC Build <sonic-build@local>`（同时修 changelog trailer 与 control Maintainer）；
- sonic-fib `debian/changelog` 补 trailer ` -- SONiC Build <sonic-build@local>  Mon, 01 Jan 2024 00:00:00 +0000`。

**关键文件 / Key Files**
`sonic-slave-resolute/Dockerfile.j2`、`src/sflow/hsflowd/Makefile`、`src/rasdaemon/Makefile`、`src/libyang3-py3/Makefile`、`src/libraries/sonic-fib/debian/changelog`

**提交 / Commits**
`8bbdb1471` `8d7011427` `2d30538b7` `8387648b6` `ce32dd433` `9353339ce`

**状态 / Status** ✅ 已解决（最终态为 per-package sed，全局 dpkg 补丁已彻底删除）

**遗留 / Caveats** changelog trailer（libyang3-py3、sonic-fib）属 `Dpkg::Changelog::Parse` 路径，全局 `field_parse_maintainer` 补丁本覆盖不到，故 per-package 修复是必要的。

---

### 4.6 grub2 Ubuntu 拆分与 C23 适配

**问题 / Problem**
原用单一 src:grub2 构建全部 grub 包（trixie 2.06，salsa git + stg）。迁 resolute 后同时撞三道墙：
1. Ubuntu 把 grub2 拆成两个源码包——src:grub2 只产 grub2-common/grub-pc/grub-common/grub-efi，其 `debian/rules` 在 `DEB_SOURCE=grub2` 时 `SB_SUBMIT=no` 显式排除 `grub-efi-amd64-bin/-unsigned/-dbg`，ONIE 安装镜像所需的 `grub-efi-amd64-bin` 缺失。
2. resolute GCC 15 默认 C23（gnu23），`false`/`bool` 成关键字，grub2 2.06 gnulib（`base64.h:25`）把 false/bool 当枚举常量 → "cannot use keyword false as enumeration constant"。
3. grub2 2.14 `debian/rules` 用 `ln -v obj/monolithic/* <version>/` 目录硬链接，overlayfs 禁止目录硬链接 → "hard link not allowed for directory"。

**根因 / Root Cause**
Ubuntu 为分离签名/未签名 EFI 二进制把 src:grub2 拆成 src:grub2 与 src:grub2-unsigned；src:grub2 的 `debian/rules` 通过 `SB_SUBMIT`/`DEB_SOURCE` 只构建 PC/通用包，EFI 包归 src:grub2-unsigned。Debian trixie 仍单一 src:grub2 产出全部。C23：resolute GCC 15 默认 `-std=gnu23`，HOST_CFLAGS 经 dpkg-buildflags 带 `-std=gnu17`，但 TARGET_CFLAGS 在 configure 默认仅 `-Os` 无 `-std=`，目标代码落回 C23。overlayfs：2.14 `debian/rules` 用目录硬链接，overlayfs 对目录硬链接返回 EXDEV。

**修复 / Fix**
三处分别修复：
1. **换源 + 规避 C23**：src:grub2 从 Debian 2.06 换为 Ubuntu resolute 2.14-2ubuntu2（`dget` Ubuntu pool）。2.06 上 `export TARGET_CFLAGS=-std=gnu17`（`6c12cec27`/`5871ea04f`）被放弃（grub2 构建系统不传递该环境变量给目标编译，且 `.ONESHELL` 下误用 make 语法 `:=` 被 shell 拒绝）；2.14 本身 C23-native，绕过 false/bool 问题。
2. **Ubuntu 拆分**：新增第二源码构建 src:grub2-unsigned（2.14-2ubuntu1），`DEB_SOURCE=grub2-unsigned` 触发 `SB_SUBMIT=yes` 产出 grub-efi-amd64/-bin；`rules/grub2.mk` 把 `GRUB_EFI_AMD64`/`GRUB_EFI_AMD64_BIN` 从 src:grub2 派生目标移除，改挂 grub2-unsigned 构建；`dbee659c3` 补 `export GRUB2_UNSIGNED_VERSION` 让子 make 可见。
3. **overlayfs 目录硬链接**：脚本 `src/grub2/patch-overlayfs-ln.sh` 把 2.14 `debian/rules` 里的 `ln -v obj/monolithic/$(SB_PACKAGE)/* ... || :` 改为逐文件 `cp -al` 循环（文件硬链接 overlayfs 允许；目录拷贝无需目录硬链接），两个 Makefile 中 dget 解包后调用。
4. **slave 依赖**：`Dockerfile.j2` 加 `apt-get -y build-dep grub2`（满足 2.14 额外 Build-Depends：qemu-system/libfuse3-dev/libsdl2-dev/autoconf-archive/python3-pytest/patchutils/...）；`729efcb59` 把该 RUN 从多行 install 续行块中间挪到块末修复 Dockerfile 解析错误。

**关键文件 / Key Files**
`rules/grub2.mk`、`src/grub2/Makefile`、`src/grub2-unsigned/Makefile`、`src/grub2/patch-overlayfs-ln.sh`、`sonic-slave-resolute/Dockerfile.j2`、`src/libnl3/Makefile`、`rules/libnl3.mk`

**提交 / Commits**
`6c12cec27` `5871ea04f` `9a3f010a3` `225846d81` `094d193db` `3e4490854` `dbee659c3` `729efcb59` `b30fb7b5e` `adee5275c`

**状态 / Status** ✅ 已解决（产物 `grub2-common_2.14-2ubuntu2_amd64.deb` 与 `grub-efi-amd64-bin_2.14-2ubuntu1_amd64.deb` 落地 `target/debs/resolute/`）

**遗留 / Caveats** (1) 可复现性缺口：`src/grub2/.gitignore` 用 `*` 忽略全部，`patch-overlayfs-ln.sh` 虽被两 Makefile 引用却未入库，fresh clone 会在 `chmod +x` 处失败（应 `git add -f` 或移入 `patch/`）。(2) SONiC 原 grub2 补丁（adjust-build-rules、large-uid-skip-cpio #25400）未移植到 2.14（stg 已注释 TODO）。(3) `b30fb7b5e`/`adee5275c` 实为 libnl3 相关（`-d` 跳 Build-Conflicts、移除 `--force-depends`），与 grub2 仅通过"slave 加 build-dep grub2"间接关联。

---

### 4.7 libnl3 nh_id 别名 / FRR / isc-dhcp LTO

**问题 / Problem**
三类路由栈编译/链接失败：
1. swss `fpmsyncd/routesync.cpp:2201` 调用 `rtnl_route_get_nh_id()`（带下划线，旧 SONiC 在 libnl 3.7.0 的 0003 stg 补丁添加的名字）。resolute 升 libnl 3.12.0 后该功能原生实现为 `rtnl_route_get_nhid`/`set_nhid`（无 `_id` 后缀），旧 stg patch 未移植 → swss 链接时未定义符号。
2. FRR 链接报 `inlining failed in call to always_inline 'inet_ntop': function body can be overwritten at link time` + `lto-wrapper fatal`。
3. isc-dhcp 4.4.3-P1 内嵌 bind 9.11.36 在 `-flto=auto` 下 `svtest`/`dhclient` 链接报 `undefined reference to isc_log_registercategories`；且 resolute dh_install 不再生成 `debian/tmp/usr/sbin/dhclient`，udeb 阶段 `cp dhclient-script` 失败。

**根因 / Root Cause**
resolute = GCC 15 + dpkg-buildpackage 默认硬化（`-flto=auto`、`-ffat-lto-objects`、`_FORTIFY_SOURCE=3`）+ 上游库大幅升级：
1. libnl3 升至 3.12.0（3.7.0 → 3.12.0-2）。3.12.0 原生引入 RTA_NH_ID 但 API 命名 `rtnl_route_get_nhid`（无下划线），与 swss 期望不一致；旧 0003 补丁为 3.7.0 写不能直接 apply；且 3.12.0-2 与 apt 仓库版本号完全相同，dpkg 不会优先本地 patch 版，无法靠 bump 版本号解决。
2. FRR：GCC15 LTO + FORTIFY=3 对 glibc `inet_ntop` always_inline 包装器处理不当——LTO 把函数体留到链接期，FORTIFY 认为 always_inline 体"可在链接期被覆盖"。
3. isc-dhcp：内嵌 bind 9.11.36 静态库 `libisc.a` 在 LTO 模式下符号解析丢失；独立于 LTO，resolute dh_install 行为变化使 udeb 目标目录缺失。

**修复 / Fix**
1. **libnl3**（`b4feb6f40`）：放弃移植整条 stg patch series，改用脚本 `src/libnl3/patch/add-nh_id-aliases.sh` 在解包后的 `libnl3-3.12.0` 源码根注入 4 处别名：`route.h` 加 `rtnl_route_get/set_nh_id` 声明；`route_obj.c` 末尾追加两个 alias 函数体转发原生 `get/set_nhid`；**awk 把别名注册进链接器 version-script `libnl-route-3.sym`**（libnl 用 `-Wl,--version-script` 构建，未注册符号不导出到 .so）的 `libnl_3_9` 节点；同步写 `debian/libnl-route-3-200.symbols`。Makefile 把 `stg init/import` 替换为 `bash ../patch/add-nh_id-aliases.sh`。用别名 wrapper 而非 bump 版本号，绕开版本号冲突。
2. **FRR**（`bc4b9553f`+`671f1be3e`）：`src/sonic-frr/Makefile` native 分支 `dpkg-buildpackage` 前导出 `DEB_CFLAGS_MAINT_STRIP="-flto=auto -ffat-lto-objects"` + `DEB_LDFLAGS_MAINT_STRIP=...` 剥离 LTO；bump `frr` 子模块指针到 `e2affde73`（10.5.4-sonic-0）。
3. **isc-dhcp**（`6a05c7fdd`+`c5fc4fe39`）：同样导出 `DEB_*_MAINT_STRIP` 剥 LTO；`debian/rules` 的 `override_dh_install` 里 `cp dhclient-script.udeb` 前插 `mkdir -p debian/isc-dhcp-client-udeb/sbin`。

**关键文件 / Key Files**
`src/libnl3/Makefile`、`src/libnl3/patch/add-nh_id-aliases.sh`、`src/sonic-frr/Makefile`、`src/sonic-frr/frr`、`src/isc-dhcp/Makefile`

**提交 / Commits**
`b4feb6f40` `671f1be3e` `bc4b9553f` `6a05c7fdd` `c5fc4fe39`

**状态 / Status** ✅ 已解决

**遗留 / Caveats** libnl3 version-script 修复关键且隐蔽：仅声明/定义符号不够，必须把别名写进 `.sym` 版本节点否则符号不导出。FRR/isc-dhcp LTO 关闭为 per-package 临时绕过（仅 native 构建），上游真正修复需 bind/frr 适配 GCC15+LTO+FORTIFY=3。libnl3 死代码与版本号建议（应 `+sonic1` 非 `~sonic1`）见评审 I15。

---

### 4.8 工具链驱动的 submodule 指针升级

**问题 / Problem**
`sonic-buildimage` 本身不含源码，只通过 gitlink 指针钉住 `src/` 下子模块提交。全新克隆做 vs 构建时，原钉住的子模块提交早于 resolute 工具链，每一个源码编译步骤（gtest、orchagent、swss-common、sairedis/SAI、linkmgrd、gnmi、dash-api、libnexthopgroup、内核 libbpf 等）都直接编译失败。需在各子模块仓库内打好补丁，再把父 gitlink bump 到携带补丁的新提交。

**根因 / Root Cause**
1. **GCC 15 + libgtest-dev 强制 C++17**（`C++ versions less than C++17 are not supported`），GCC15 把 `-Wconversion`/`-Wmaybe-uninitialized`(LTO 误报)/`-Wdiscarded-qualifiers` 当 `-Werror`；C++17 废弃 `std::iterator` typedef、`<cstdbool>`，给 `std::remove` 加 `[[nodiscard]]`。
2. **boost 1.88** 删除 `boost::asio::io_service`、`io_context::work`、成员 `post()`，自带 `std::hash<uuids::uuid>`；`libboost1.88-dev` 包名变化需 Build-Depends/Depends 加 alternates。> **注：** slave 最终 pin 1.83（见 #2），1.83 保留这些 API；但 submodule 迁移代码（io_context 新 API、`executor_work_guard`、删自定义 hash）已提交且 1.83 兼容（实验验证 linkmgrd 编译通过），保留不回退。
3. **SWIG 4.4** Go 后端不再展开 `$function`（需改 `$action`），生成的包装码在 GCC15 下命中 `-Werror=conversion`/`-Wdisabled-optimization`。
4. **doxygen 1.15.0** 的 `<ref>` 自动链接包裹破坏 SAI `parse.pl` 解析的 2199 个类型标签。
5. **`_FORTIFY_SOURCE=3`** 让 `strstr`/`strchr` 经 `_Generic` 返回 `const char*`，libbpf.c 把返回值赋 `char*`，且 libbpf 自带 `override CFLAGS += -Werror` 覆盖 dpkg-buildflags 的 `-Wno-error`。
6. **cmake 4.x** 删除 `cmake_minimum_required<3.5` 支持（sonic-bmp/PcapPlusPlus）。

**修复 / Fix**
`5e4f25d43` 一次性 bump 14 个子模块（内部改动已逐一核对）：
- `sonic-swss`→`6d3a46bb`：`configure.ac` `-std=c++17`、`orchagent/directory.h` 去掉 `std::iterator` 改显式 5 typedef、`Makefile.am` 丢掉 tests、刷新 `Cargo.lock`；
- `sonic-swss-common`→`646e726`：`configure.ac` c++17、`common/boolean.h` 删 `operator bool&()`（真根因，消除 7 处隐式转换错误）；
- `sonic-sairedis`+嵌套 SAI→`e703aff`（SAI `68da16e5`）：`configure.ac` c++17 + `-include cstdint/sstream/string` + `-Wno-error=maybe-uninitialized`、`pyext/py3/Makefile.am` SWIG `-Wno-error`、`meta/Doxyfile AUTOLINK_SUPPORT=NO`（一键清零 2199 错误）；
- `sonic-gnmi`→`c8f96ff`：go-redis v7.4.1、`$function`→`$action` sed（版本无关）；
- `linkmgrd`→`3e6ad1b`：全局 `io_service`→`io_context`、`executor_work_guard`、free `asio::post`；
- `dhcprelay`/`sonic-stp`/`sonic-bmp`(cmake_minimum_required 3.5)/`sonic-redfish`/`sonic-dash-ha`/`sonic-mgmt-common`+`framework`(go-redis/go-cmp)/`wpasupplicant/sonic-wpa-supplicant`/`platform/vpp`(resolute 变体命名)。
- 另两个更早 bump：`eac57a2d5` `sonic-linux-kernel`→`c54d5e3`（对 `tools/lib/bpf/libbpf.c` 的 `strstr`/`strchr` 返回值 sed 强制 cast 成 `char*`）；`25d0b0faf` `sonic-dash-api`→`43c676b`（子模块内 `g++ -std=c++14`→`c++17`），并直接在父树改 `src/libraries/sonic-fib/configure.ac` 的 `CFLAGS_COMMON` c++14→c++17（libnexthopgroup 是树内库，不走子模块指针）；`99cd4adac` `sonic-swss-common`→`c1a34b5c3`（`debian/control` 加 `libboost1.88-dev` alternates）。

**关键文件 / Key Files**
`src/{sonic-swss,sonic-swss-common,sonic-sairedis,sonic-gnmi,linkmgrd,dhcprelay,sonic-stp,sonic-bmp,sonic-redfish,sonic-dash-ha,sonic-mgmt-common,sonic-mgmt-framework,sonic-linux-kernel,sonic-dash-api,wpasupplicant/sonic-wpa-supplicant}`、`platform/vpp`、`src/libraries/sonic-fib/configure.ac`

**提交 / Commits**
`5e4f25d43` `99cd4adac` `eac57a2d5` `25d0b0faf`

**状态 / Status** ✅ 已解决（fresh clone 可复现；3 个损坏对象库 mgmt-framework/swss/sairedis 从 origin 重克隆修复）

**遗留 / Caveats** 父仓库 commit 仅移动 gitlink，真正源码补丁在各子模块提交内，复现要求这些 resolute 分支已 push 到构建机可克隆远端。linkmgrd `make test` 仍有残留 `io_context::work`（5 处 `ioService.post` + 析构名），但 vs 构建不编译 `test/` 故不影响产物（评审 I11）。swss tests 移除丢 ~9 个测试二进制（评审 I10）。

---

### 4.9 包级构建修复

**问题 / Problem**
迁 resolute 后多个源码包在 slave 内构建失败，各因不同：
1. `psample` cmake 配置报 "CMake Error at CMakeLists.txt:1"；
2. `openssh`/`makedumpfile`/`kdump-tools`/`lldpd`/`libnl3` dget 拉 .dsc 时 GPG 校验失败，且 dbgsym 衍生产物 mv 阶段 No such file；
3. openssh build-dep 报 "unmet build dependencies: libwtmpdb-dev"；
4. `libyang3` 3.13.6 缺 `LYD_VALIDATE_NOEXTDEPS` 宏，sonic-mgmt-common 编译 `yparser.go` 报 undeclared；
5. `sonic-eventd` 编译 `timestamp_formatter.cpp` 时 `stringstream`/`unordered_map` 未声明，且 changelog trailer 解析失败；
6. `sonic-sysmgr` changelog trailer 因尾随空格被 dpkg 拒。

**根因 / Root Cause**
(a) resolute 自带 cmake 4.2，CMake 4.x 废弃 `cmake_minimum_required<3.5`（3.27 弃用、4.0 移除），上游 libpsample `CMakeLists.txt:1` 仍写 `VERSION 3.3`。(b) slave 容器 HOME 无 .gnupg 且 keyring 缺 Debian 维护者公钥，dget 默认 GPG 校验失败；同时 resolute debhelper 把 DBGSYM_PACKAGE_TYPE 硬编码 'ddeb'，`*-dbgsym_*.deb` 实际产 `.ddeb`，`mv $(DERIVED_TARGETS)` 因文件不存在而非零退出。(c) SONiC 用 dget 从 `deb.debian.org` 拉 Debian openssh 10.0p1-7，其 Build-Depends 含 `libwtmpdb-dev`，而 slave `apt build-dep openssh` 装的是 Ubuntu resolute 自带 openssh 的依赖（不含 libwtmpdb-dev）。(d) 换底时 libyang3 pr2362 补丁被注释跳过，但上游 3.13.6 不提供 `LYD_VALIDATE_NOEXTDEPS`（该宏由 SONiC pr2362 补丁 `parser_data.h #define LYD_VALIDATE_NOEXTDEPS 0x0040` 新增，被 `yparser.go` 引用）。(e) resolute libstdc++（GCC 15 系）不再经 `<iostream>`/`<swss/logger.h>` 传递性引入 `<sstream>`/`<unordered_map>`；dpkg 对 changelog trailer 更严，尾随空格非法。(f) resolute 默认 boost 1.90（slave pin 1.83，见 #2）；`libboost-serialization1.83-dev` 存在（universe），submodule control 用 `1.83-dev | 1.88-dev` 交替项兼容。

**修复 / Fix**
按包最小化定向修复：
1. `psample`：git clone 后 `sed 's/cmake_minimum_required(VERSION 3.3)/VERSION 3.5/' CMakeLists.txt`；
2. `makedumpfile`/`kdump-tools`/`lldpd`/`libnl3`/`openssh`：dget 加 `-u` 跳 GPG（与 bash/iproute2/lm-sensors 等已有包对齐）；libnl3/lldpd/openssh 把收尾 `mv $(DERIVED_TARGETS)` 改 `-mv ... 2>/dev/null; mv $* ...`，让 dbgsym(.ddeb) 缺失不阻断主目标；
3. `Dockerfile.j2`：`apt-get build-dep openssh` 后显式 `apt-get install -y libwtmpdb-dev`；
4. `libyang3`：重新启用 `patch -p1 < ../patch/0001-pr2362-lyd_validate_noextdeps.patch`（验证在 3.13.6 上所有 hunk 带 offset 干净应用），恢复宏；
5. `sonic-eventd`：changelog trailer 补双前导空格 + RFC2822 时间戳；`debian/control` Build-Depends 改 `libboost-serialization1.83-dev | libboost-serialization1.88-dev` 交替项；`timestamp_formatter.cpp` 顶部补 `#include <sstream>` 与 `<unordered_map>`；
6. `sonic-sysmgr`：changelog 去 trailer 尾随空格。

**关键文件 / Key Files**
`src/sflow/psample/Makefile`、`src/openssh/Makefile`、`src/makedumpfile/Makefile`、`src/kdump-tools/Makefile`、`src/lldpd/Makefile`、`src/libnl3/Makefile`、`src/libyang3/Makefile`、`src/libyang3/patch/0001-pr2362-lyd_validate_noextdeps.patch`、`src/sonic-eventd/{debian/changelog,debian/control,rsyslog_plugin/timestamp_formatter.cpp}`、`src/sonic-sysmgr/debian/changelog`、`sonic-slave-resolute/Dockerfile.j2`

**提交 / Commits**
`796db0b37` `2113e3207` `96a7ac97b` `ecfbb5636` `f040e7f9b` `586c35eef`

**状态 / Status** ✅ 已解决

**遗留 / Caveats** `ecfbb5636` 的 dbgsym mv 兜底与主题 #4 的 `Dh_Lib.pm` 单点补丁并存——后者从源头让 .ddeb→.deb，前者保证即便 .deb 不存在也不阻断主产物。dget `-u` 未修复 slave keyring 缺密钥根因（可接受，因其他 SONiC 源码包早已如此）。pr2362 补丁实为上游 Brad House 提交 `cfc94cc0` 的再实现，libyang3 升版后仍需维持。

---

### 4.10 resolute 命名 variant 重构

**问题 / Problem**
vs 镜像已构建并启动验证，但先前实现是"换内容不换名"：`docker-base-trixie` 的 FROM 被改成 `ubuntu:resolute`（`3d265d73b`），而 50 个 leaf docker 的 `ARG BASE` 仍硬编码 trixie 字面量。后果：(1) 命名与内容不一致；(2) trixie variant 被污染，无法做 `BLDENV=trixie` 对照；(3) 缺 resolute 命名 base 链。目标：`BLDENV=resolute` 下所有容器改用 resolute 命名 base 链，trixie variant 还原 pristine（`FROM debian:trixie`），两套并存。

**根因 / Root Cause**
三层约束叠加：
1. **工具链版本不匹配**（最先触发）：slave 已迁 `ubuntu:resolute`，产出的 deb（如 socat 1.8.1.1）声明 `Depends: libc6 (>= 2.42)`，而 `docker-base-trixie` 原 `FROM debian:trixie` 的 libc6 是 2.41 → `dpkg -i` 报 `however`。docker base 必须跟到 `ubuntu:resolute`。
2. **构建系统架构硬约束**（决定必须改 leaf）：leaf docker 的 `Dockerfile.j2` 用字面量 `ARG BASE=docker-config-engine-trixie-...`，而 docker 构建规则（`slave.mk`）不传 `--build-arg BASE`，leaf 的 `FROM $BASE` 完全由 .j2 默认值决定。无法靠 `slave.mk` 变量 remap 让 leaf 切 base（3 次失败尝试已证）。
3. **j2 变量名生成规则**（一次构建失败的坑）：3 个 resolute variant .j2 从 trixie 复制而来，内部引用 `docker_*_trixie_{debs,whls,pkgs}`，但 j2 变量名由 make 按 docker PATH 生成（`slave.mk: $(eval export $(subst -,_,$(notdir ...))_whls=...)`）：path `docker-base-resolute` → make 导出 `docker_base_resolute_whls`，而 .j2 仍读 `docker_base_trixie_whls` → `jinja2.UndefinedError`。

**修复 / Fix**
1. 新建 resolute variant 三层 base 链（`ubuntu:resolute → docker-base-resolute → docker-config-engine-resolute → docker-swss-layer-resolute`）：`dockers/docker-{base,config-engine,swss-layer}-resolute/Dockerfile.j2` + `rules/docker-*-resolute.{mk,dep}`，变量 `DOCKER_{BASE,CONFIG_ENGINE,SWSS_LAYER}_RESOLUTE`，注册 `SONIC_DOCKER_IMAGES +=` 与 `SONIC_RESOLUTE_DOCKERS +=`，`_LOAD_DOCKERS` 链。
2. 批量改 50 个 leaf `.j2` 的 `ARG BASE`/`FROM`：`docker-config-engine-trixie-` → `-resolute-`（排除 trixie variant 自身目录）。含 2 个 watchdog（直接 FROM，builder+final 各一处）与 vs syncd/gbsyncd-vs 及 broadcom/mellanox/marvell-*/components/nvidia-bluefield syncd/saiserver。
3. 批量改 45 个 `.mk` 的 `_LOAD_DOCKERS`/`_DBG_DEPENDS`/`_DBG_IMAGE_PACKAGES`：`$(DOCKER_CONFIG_ENGINE_TRIXIE)` → `$(DOCKER_CONFIG_ENGINE_RESOLUTE)` 等（sed 模式 `DOCKER_*_TRIXIE)` 只匹配变量引用闭合括号，不误伤 `DOCKER_*_TRIXIE_DBG` 下划线后缀变量）。含共享 template `platform/template/docker-{syncd,gbsyncd}-trixie.mk` 直接改。
4. `slave.mk` 加 `else ifeq ($(BLDENV),resolute)` 分支：`DOCKER_IMAGES = $(filter-out $(DOCKER_BASE_TRIXIE) $(DOCKER_CONFIG_ENGINE_TRIXIE) $(DOCKER_SWSS_LAYER_TRIXIE),$(SONIC_DOCKER_IMAGES))`（filter-out 3 个 trixie base）。`BLDENV=trixie` 仍走 else 默认分支不受影响。
5. j2 var-name 修复：3 个 resolute variant .j2 内部 sed `docker_*_trixie_` → `docker_*_resolute_`（仅 _debs/_whls/_pkgs 引用），消除 `jinja2.UndefinedError`。
6. trixie variant 还原 pristine：`dockers/docker-base-trixie/Dockerfile.j2` FROM `ubuntu:resolute` → `debian:trixie`（revert `3d265d73b`），其余 trixie 目录/rules 不动。

**关键文件 / Key Files**
`slave.mk`、`dockers/docker-{base,config-engine,swss-layer}-resolute/{Dockerfile.j2}`、`rules/docker-{base,config-engine,swss-layer}-resolute.{mk,dep}`、`dockers/docker-base-trixie/Dockerfile.j2`、`platform/template/docker-{syncd,gbsyncd}-trixie.mk`、50 leaf `dockers/*/Dockerfile.j2` + 45 `rules/docker-*.mk`、`docs/superpowers/specs/2026-07-05-resolute-variant-naming-design.md`

**提交 / Commits**
`a8fee77a4`（113 文件）

**状态 / Status** ✅ 已解决（`target/sonic-vs.bin` 产出，三个 resolute base 被 build，`docker-base-trixie` 未 build（filter-out 生效），KVM 启动 os-release=Ubuntu 26.04）

**遗留 / Caveats** (1) `platform/vpp` 子模块内部 variant-naming 改动需单独子模块提交 + 指针 bump（vs 不用 vpp 故不影响）。(2) `docker-sonic-vs`（bookworm 体系，findstring 守卫，默认不 build）未迁移。(3) 共享 template `docker-*-trixie.mk` 被直接改成 resolute 引用，意味着 `BLDENV=trixie` 下若 build 非 vs 平台 syncd 会指向 resolute base 而 trixie base 仍 pristine——潜在不一致；vs 构建（`BLDENV=resolute`）不受影响。

---

### 4.11 fsroot-vs pip 生态与 pkgutil 运行时修复

**问题 / Problem**
fsroot-vs 镜像构建阶段 Python pip 生态与运行时连环失败：(1) pyangbind 的 lxml 依赖被 pip 重建为 lxml 5.4.0 sdist，Cython 生成码编译失败；(2) M2Crypto 等 SWIG 扩展引用 glibc 内部符号 `__fds_bits` 且因 `-Wincompatible-pointer-types` 失败；(3) grpcio `setup.py` 探测 `c++` 二进制但构建主机只装 gcc；(4) 运行时 sonic-package-manager 用 `pkgutil.get_loader()` 定位 CLI 插件目录，该 API 在 Python 3.14 已移除；(5) Docker builder-stage rsync 时 `/etc/hosts` 被 buildkit bind-mount，rsync rename 返回 EBUSY；(6) resolute 用 `resolv-config.service` 替代 `resolvconf.service`，构建期清理语句失败。

**根因 / Root Cause**
resolute = Python 3.14（PyPI 仅 cp314 wheel）+ GCC 15 + glibc，多重断层叠加：1) Python 3.14 移除 `pkgutil.get_loader`（3.12 弃用），`sonic_package_manager/manager.py:167` 与 `sonic_cli_gen/generator.py:77` 仍用旧 API；2) apt 装的 `python3-lxml` 无 pip RECORD，pip 视为未安装，pyangbind 把 lxml 解析为 5.4.0 sdist，其 Cython 生成码触发 GCC 15 新增 `-Wincompatible-pointer-types` 硬错误；3) `__fds_bits` 是 glibc 内部宏（公开成员是 `fds_bits`），M2Crypto SWIG 包装直接引用需 `-D__fds_bits=fds_bits`；4) `c++` 二进制属 `g++` 包而非 `gcc`；5) Docker buildkit 为 builder stage bind-mount `/etc/hosts`（只读 bind），rsync 原子 rename 对该文件返回 EBUSY；6) resolute 用 `resolv-config.service`，不存在 `resolvconf.service` 与 `/etc/resolvconf/resolv.conf.d/original`。

**修复 / Fix**
- `build_debian.sh`：`gcc` 改 `g++`（顺带拉 gcc），追加 `libxml2-dev libxslt1-dev swig libssl-dev`；`rm -f .../original` 改 `|| true` 并前置 `mkdir -p`。
- `files/build_templates/sonic_debian_extension.j2`：`install_pip_package` 包裹 `env CFLAGS="-Wno-error=incompatible-pointer-types -D__fds_bits=fds_bits" pip3 install --no-build-isolation`；pyangbind 前先 `pip3 install 'lxml==6.1.1'`（cp314 wheel 预满足依赖），再 `pip3 install --no-build-isolation --no-deps pyangbind==0.8.7` 跳过 lxml 重建；`systemctl disable resolvconf.service || true`；用 sed 给 `manager.py` 打补丁——把 `pkgutil.get_loader(f'{command}.plugins')` 替换为 `importlib.util.find_spec(...)` 构造的 shim（动态 `type("L",(),{"path":...})()` 模拟 `.path` 属性），并把 `import pkgutil` 替换为 `import importlib.util, importlib`。
- `dockers/dockerfile-macros.j2` 的 `rsync_from_builder_stage` 宏增加 `--exclude=/etc/hosts`。
- `e93860839` 修正 `ca6536aeb` 引入的 off-by-one：原 sed 用 `spec.submodule_search_locations[0]`（包目录 `.../show/plugins`），下游 `os.path.dirname()` 得到父目录 `.../show`，插件落点高一层；改为 `spec.origin`（`.../show/plugins/__init__.py`），`dirname()` 还原为插件目录本身。已验证最终为 `spec.origin`。

**关键文件 / Key Files**
`build_debian.sh`、`dockers/dockerfile-macros.j2`、`files/build_templates/sonic_debian_extension.j2`

**提交 / Commits**
`ca6536aeb` `e93860839`

**状态 / Status** ⚠️ 部分

**遗留 / Caveats** 残留缺口：`sonic_cli_gen/generator.py:77` 仍用 `pkgutil.get_loader(f'{command}.plugins.auto')`，且 fsroot-vs 中该文件与源码字节一致（未打补丁）。`manager.py` import `CliGenerator`，而 `CliGenerator.install_cli_plugin/remove_cli_plugin` 调用模块级 `get_cli_plugin_path`（`generator.py:76→77`），因此当 sonic-package-manager 安装/卸载带 YANG 模型且触发自动 CLI 生成的包时，在 Python 3.14 下仍会 AttributeError。两个提交未覆盖此处，需追加同样的 `importlib.util.find_spec` 补丁。次要风险：`--no-build-isolation` 对所有 pip wheel 全局生效（依赖预装 lxml 6.1.1 才安全）；pkgutil shim 仅模拟 `.path` 属性，若上游新增对 pkg_loader 其他字段访问则 shim 失效。

---

### 4.12 文档与交付状态记录

**问题 / Problem**
迁移有两类信息缺口需落地为可追溯记录：(1) **Category-C 决策缺口**——SONiC 对 bash/iproute2/libnl3/libyang3/openssh/thrift 等 15 个包打了自定义补丁并自构建，resolute apt 换版后必须逐包判定"直接换 apt / 需移植补丁 / 必须保留源码构建"，否则迁移工作无法分派。(2) **验证缺口**——在 C1 子模块升级 + 变体重命名 + C3 pkgutil 修复落地后，需一个 done-bar 检查矩阵证明 vs 镜像"构建/启动/运行"通过，并如实记录冒烟失败项的真实根因。

**根因 / Root Cause**
(1) resolute 整体更换基础包版本（bash 5.3、iproute2 6.19、libnl3 3.12.0、libyang3 3.13.6、openssh 10.2p1、thrift 0.22.0、redis 8.0.5、swig 4.4.0 等），而 SONiC 对这些包打了强耦合补丁（bash 583 行 plugin.c/plugin.h 管理框架、iproute2 EVPN MH 字段、libnl3 RTA_NH_ID + ABI 符号版本、libyang3 LYD_VALIDATE_NOEXTDEPS、openssh 反向 SSH/TACACS 等），新版本是否已含或需重新移植必须逐包核验；另 ifupdown2 在 resolute apt 不存在、thrift 0.11.0→0.22.0 破坏 saithrift union 序列化（ABI 不兼容），故只能保留源码构建。(2) 首次记录（`33acdab0d`）把 `show ip intf` 失败误判为"squashfs 打包丢失 show/plugins/*.py"，根因是错误检查了构建中间产物 `target/sonic-vs.bin__vs__rfs.squashfs`（stale），而非 KVM 实际运行的根文件系统 `part3/image-resolute.0-e938608/fs.squashfs`；真正根因是两层非构建问题——(a) 上游 sonic-utilities `util_base.py:31` 用 `importlib.import_module` 导入带连字符模块名 `show.plugins.dhcp-relay/macsec`，Python 模块名不允许连字符，该 bug 在 trixie/202605 即存在（非 resolute 回归）；(b) `show ip` 子命令树依赖 `Db()`→configdb 连接，冒烟时 db 容器刚 Up、configdb 未初始化（vs 无 minigraph），属时序问题。

**修复 / Fix**
1. 新建双语 Category-C 包替换目录（`docs/superpowers/specs/category-c-catalog-{zh,en}.md`），对 15 个包逐行给出 verdict + resolute apt 版本号 + 理由：`safe-to-swap=2`（redis 无补丁、swig 无补丁且向后兼容）、`needs-patch-port=11`（bash/iproute2/libnl3/libyang3/lldpd/openssh/monit/lm-sensors/initramfs-tools/grub2/kdump-tools）、`keep-source-build=2`（thrift 破坏 saithrift、ifupdown2 不在 apt）。
2. 新建 `docs/superpowers/plans/done-bar-status.txt` 落地 done-bar 矩阵：KVM 启动到 login、`show version`（报 Build commit `e938608` + docker 镜像 tagged `resolute.0-e938608`）、`docker ps`（database/gnmi/pmon healthy）、`/etc/os-release`=Ubuntu 26.04 四项 PASS。
3. `3b3d0965d` 修正：通过 qemu-nbd + squashfs 挂载真实运行根文件系统 `part3/image-resolute.0-e938608/fs.squashfs`（非 stale 中间产物），确认 18 个 `show/plugins/*.py`（含 `dhcp-relay.py`/`macsec.py`）均在盘上，撤回"squashfs 丢失 show/plugins"错误结论，把两处冒烟失败重分类为非构建缺陷——连字符导入为上游技术债、`show ip` 失败为 configdb 未就绪 + vs 无 minigraph 的时序/环境问题，明确标注 "no build defect found"。

**关键文件 / Key Files**
`docs/superpowers/specs/category-c-catalog-{en,zh}.md`、`docs/superpowers/plans/done-bar-status.txt`

**提交 / Commits**
`93f1fe2a2` `33acdab0d` `3b3d0965d`

**状态 / Status** ✅ 已解决

**遗留 / Caveats** 本主题为纯文档/记录主题，不含代码改动；把迁移的"规划决策"与"验证结论"固化下来。Category-C 目录是规划文档，其 11 个 `needs-patch-port` 判定的实际补丁移植发生在其它主题（如 libyang3 pr2362 `f040e7f9b`、libnl3 nh_id 别名 `b4feb6f40`、frr LTO `bc4b9553f`）。已撤销的"squashfs 打包丢失 show/plugins"错误记录在 `3b3d0965d` 中明确标注 retracted。

---

## 5. 已知遗留汇总（不影响 vs 构建）

| 来源 | 遗留项 | 影响 |
|---|---|---|
| #2 | 全局 `-std=gnu17` 层级偏粗（`wpasupplicant` 对 `.cpp` 用 `$(CC)$(CFLAGS)` 需额外补救）；`Dockerfile.j2` 末尾 vendor include 仍写 `DEBIAN_VERSION='trixie'` | vs 构建不受影响；潜在残留 |
| #4 | `Dh_Lib.pm` patch `grep -q ddeb && sed` 非幂等 | 靠 slave 总从 fresh base 重建才 work；debhelper 升级可能硬失败（base 已 pin） |
| #6 | `patch-overlayfs-ln.sh` 未入库（.gitignore `*`）；原 grub2 补丁（large-uid cpio #25400）未移植到 2.14 | fresh clone 复现性缺口；2.14 上 large-uid 是否已上游合入未验证 |
| #7 | libnl3 死代码（symbols awk）+ 孤立 patch + 版本号建议（应 `+sonic1` 非 `~sonic1`）；alias 脚本非幂等 | 不影响 swss 链接；收尾项 |
| #8 | linkmgrd `test/` 残留 `io_context::work`（`make test` 断）；swss tests 移除丢 ~9 个测试二进制 | vs 构建不编译 `test/`；非 vs 潜在覆盖率回归 |
| #10 | `platform/vpp` variant-naming 改动需子模块提交 + 指针 bump；`docker-sonic-vs`（bookworm）未迁移；共享 template `docker-*-trixie.mk` 改 resolute 使 `BLDENV=trixie` 下非 vs 平台 syncd 潜在不一致 | vs 构建不受影响 |
| #11 | `sonic_cli_gen/generator.py:77` 仍用 `pkgutil.get_loader`（未打补丁）；`--no-build-isolation` 全局生效；pkgutil shim 仅模拟 `.path` | 带自动 CLI 生成的包安装/卸载在 py3.14 下 AttributeError（运行时） |
| 评审 I7/I8 | 13 个平台 Dockerfile 缺 `--exclude=/etc/hosts` / `libxml2-16` | 非 vs 平台构建遇 EBUSY / apt 失败 |
| 评审 I9 | bash plugin 未 port（32 hunks/8 文件/583 行） | plugin 功能在 resolute 上未提供（已知回归） |

---

## 6. 与其他文档的关系

- **[resolute-migration-code-review-zh.md](resolute-migration-code-review-zh.md)** — 缺陷视角：评审 C1-C4 + I5-I18 + M19-M27，及 C1-C4 的后续解决记录。读它了解"哪里有 bug、哪里未收尾"。
- **[resolute-vs-migration-report-zh.md](resolute-vs-migration-report-zh.md)** — 按包的迁移叙事：per-package 改动详录 + 7 类根因总表 + 最终验证。读它了解"每个包具体怎么改的"。
- **本文** — 按主题的正面修改目录：12 主题的 problem → root cause → fix → files → commits。读它了解"整体改了哪些方面、各为解决什么问题"。
- **`specs/category-c-catalog-{zh,en}.md`** — 15 个 Category-C 包的 swap/patch-port/keep-source-build 判定清单。
- **`specs/2026-07-05-resolute-variant-naming-design.md`** — 变体命名重构设计稿（主题 #10 的设计依据）。
- **`plans/done-bar-status.txt` / `fips-status.txt`** — 交付验证矩阵与 FIPS 状态记录。
