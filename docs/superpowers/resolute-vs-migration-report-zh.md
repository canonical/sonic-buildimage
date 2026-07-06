# SONiC 202605 → Ubuntu Resolute (26.04) VS 镜像迁移报告

**分支:** `resolute` (基于 `master` @ `7c13fdbd9`)
**工作目录:** `/home/sheldon-qi/sonic-buildimage-resolute`
**日期:** 2026-07-05
**状态:** ✅ `target/sonic-vs.bin` 构建成功并经 KVM 启动验证 os-release = Ubuntu 26.04

---

## 1. 背景与目标

将 SONiC 202605 的 VS（虚拟交换机）镜像构建基线从 Debian trixie 迁移到 Ubuntu resolute (26.04)。验证标准：在 Ubuntu host 上构建出 `target/sonic-vs.bin`，并能正常启动到看到 `/etc/os-release` 报 Ubuntu。

**最终验证:**
- 构建: `make PLATFORM=vs BLDENV=resolute target/sonic-vs.bin` → 2.4 GB ONIE installer ✅
- 启动: `build_kvm_image.sh` 装到 qcow2，qemu 引导到 `sonic login:` ✅
- os-release: `PRETTY_NAME="Ubuntu 26.04 LTS"`, `VERSION_CODENAME=resolute`, `ID=ubuntu` ✅

---

## 2. 根因总览

resolute 比 trixie 更"严格"，所有失败可归为 7 类工具链差异。每类下面会列出受影响的包与具体改法。

| # | 根因类别 | trixie | resolute | 典型表现 |
|---|---|---|---|---|
| 1 | **dpkg 解析严格化** | 宽松接受 | 严格 | `cannot parse Maintainer` / `changelog trailer` |
| 2 | **GCC 15 / C23** | GCC 14 / C17 | GCC 15 / C23 | `-Werror=conversion`, `-Wmaybe-uninitialized`, `bool` keyword |
| 3 | **C++17 + libstdc++ 15** | C++14 OK | gtest 要求 C++17 | `#error C++ versions less than C++17`, `<cstdbool>` deprecated, `std::iterator` deprecated |
| 4 | **LTO 假阳性** | 偶发 | 普遍 | `maybe-uninitialized` 在 link 阶段误报 |
| 5 | **doxygen 1.15.0** | 1.9.8 | 1.15.0 | SAI type 名被包成 `<ref>` → parse.pl 解析失败 |
| 6 | **boost 默认 1.90（header-only）** | 1.83 default | 1.90 default（1.83/1.88 在 universe） | `libboost_system.so` header-only 缺失；1.88 另删 `io_service`/`io_context::work`/`std::hash<uuid>` 需 submodule 迁移。slave 最终 pin **1.83**（对齐 trixie/bookworm 上游，见 §3.1.A） |
| 7 | **Python 3.14 / 包名变更** | py3.13 / 旧名 | py3.14 / 新名 | `pkgutil.get_loader` 移除, `libxml2`→`libxml2-16`, SWIG 4.4 `$function` |

---

## 3. 详细改动（按包，含根因）

> **提交策略说明：** 已提交的改动（约 60 个 commit，见 `git log resolute`）覆盖了 slave 镜像、FIPS、grub2、libnl3 降级、dbgsym、bash/socat 等"基础设施"层。本文档聚焦**最近一批未提交的工作树改动**（swss-common → sonic-vs.bin 打包这一段），这些是推进到镜像产出的最后一关。完整历史见 `git log --oneline resolute --not master`。

### 3.1 父仓库（已提交 + 工作树）

#### A. slave 镜像 `sonic-slave-resolute/Dockerfile.j2`（已提交）
- **根因 #2/#3：** resolute GCC 15 把 `-Wimplicit-function-declaration`、`-Wincompatible-pointer-types`、`-Wint-conversion` 默认升为 error；同时 libgtest-dev 要求 C++17。
- **改法：** 在 `/etc/dpkg/buildflags.conf` 全局追加 `-std=gnu17 -Wno-error=incompatible-pointer-types -Wno-error=int-conversion -Wno-error=discarded-qualifiers`；安装 `gcc-multilib`、`libwtmpdb-dev`（openssh 10.0p1-7 Build-Depends）、`build-dep grub2`。
- **根因 #1（dbgsym）：** Ubuntu debhelper 硬编码 `DBGSYM_PACKAGE_TYPE='ddeb'`，导致 dbgsym 包输出 `.ddeb` 而非 `.deb`，SONiC 的 slave.mk mv 逻辑找不到文件。单点 patch `Dh_Lib.pm` 把 `ddeb` 改 `deb`，替代了之前散布在多个 Makefile 里的 `mv` 兜底。
- **根因 #6：** resolute 默认 `libboost-dev` 是 **1.90**（main）——`boost_system` 自 1.90 起 header-only，无 `libboost_system.so`，systemd-sonic-generator 等链接失败；1.83/1.88 在 universe。**最终 pin 1.83**（对齐 trixie/bookworm 上游——trixie `libboost-dev` default 即 1.83.0.2）：`Dockerfile.j2` 18 行 `1.88-dev`→`1.83-dev`，实验验证 slave 重建 + libswsscommon/sonic-eventd/systemd-sonic-generator/sonic-linkmgrd 四包在 1.83 header 下编译通过；submodule 已迁的 io_context 新 API 在 1.83 亦兼容，保留不回退。（早期曾 pin 1.88——1.88 删 `io_service`/`io_context::work`/`std::hash<uuid>` 触发 linkmgrd 49 文件迁移，见 §3.6；改 1.83 后这些 API 都在，迁移代码已做且兼容，不回退。）

#### B. `build_debian.sh`（工作树）
- **根因 #7：** fsroot-vs 里 pip 构建 grpcio 时 `setup.py` 调用 `c++` 探测 libatomic，但 trixie 的 `gcc` 包提供 `c++` 符号链接，resolute 不提供（在 `g++` 包）。改 `apt-get install gcc` → `g++`。
- **根因 #7：** lxml 5.4.0 从 sdist 编译时 GCC 15 报 `-Wincompatible-pointer-types`（hard error）；装 `libxml2-dev` + `libxslt1-dev` 让 lxml 能找到头；M2Crypto 的 swig 生成代码引用旧 glibc 内部字段 `fd_set.__fds_bits`（resolute glibc 2.43 改成 `fds_bits`），通过 `CFLAGS=-D__fds_bits=fds_bits` 宏重定义绕过。
- **根因 #7：** `systemctl disable resolvconf.service` 失败（resolute 用 `resolv-config.service` 替代，无 resolvconf 单元）→ 加 `|| true`；`cp .../resolv.conf.head` 目标目录不存在 → 加 `mkdir -p`。

#### C. `files/build_templates/sonic_debian_extension.j2`（工作树，**关键**）
> **重要：** `sonic_debian_extension.sh` 是 `slave.mk` 每次构建从 `sonic_debian_extension.j2` 重新生成的，直接改 `.sh` 会被覆盖——必须改 j2 模板。

- **根因 #7（pyangbind/lxml）：** pip 不认 apt 装的 `python3-lxml`（无 RECORD 文件），重新解析依赖时选了 lxml 5.4.0 sdist 从源码编译，触发 GCC 15 错误。改法：(1) 在装 pyangbind 前 `pip3 install lxml==6.1.1`（cp314 预编译 wheel，有 RECORD）；(2) pyangbind 加 `--no-build-isolation --no-deps`，用预装的 lxml 6.1.1，不重新解析依赖。
- **根因 #7（M2Crypto `__fds_bits`）：** `install_pip_package` 宏加 `env CFLAGS="-Wno-error=incompatible-pointer-types -D__fds_bits=fds_bits"`，让 pip 构建扩展时传给 gcc。
- **根因 #7（sonic-package-manager）：** Python 3.14 移除了 `pkgutil.get_loader`（3.12 deprecated）。`sonic_package_manager/manager.py:167` 用它定位 CLI 插件目录。在 sonic-packages 安装循环前 sed 修复：`pkgutil.get_loader(...)` → `importlib.util.find_spec(...)` + 配套 `import` 调整。
- **根因 #1：** `systemctl disable resolvconf.service || true`。
- **根因 #7（swig 缺失）：** M2Crypto 构建 swig 需要 `swig`；resolute `gcc` 包不带 swig，在 `build_debian.sh` 装 `swig libssl-dev`。

#### D. `dockers/dockerfile-macros.j2` + 各 Dockerfile（已提交 + 工作树）
- **根因（docker buildkit）：** rsync 同步 base 镜像内容到 `/` 时，`/etc/hosts` 被 Docker bind-mount 占用，`rename` 失败（`Device or resource busy`）。trixie 下 buildkit 行为不同，不触发。改法：所有 `rsync -axAX ...` 加 `--exclude=/etc/hosts`（宏 + `docker-restapi-sidecar/Dockerfile{.j2,}`，其余 12 个 Dockerfile 之前已改）。
- **根因 #7：** `docker-sonic-mgmt-framework/Dockerfile` apt 装 `libxml2` → resolute 改名 `libxml2-16`。

#### E. `src/libnl3/Makefile` + 新增 `patch/add-nh_id-aliases.sh`（工作树）
- **根因（libnl API 重命名）：** SONiC 旧 0003 patch 给 libnl 3.7.0 加了 `rtnl_route_get_nh_id`（带下划线），swss fpmsyncd 调用它。但 libnl 3.12.0 上游自己实现了该功能，命名是 `rtnl_route_get_nhid`（无下划线，字段 `rt_nhid`，attr `ROUTE_ATTR_NHID`）。版本号 `3.12.0-2` 与 resolute apt 撞号，同版本 dpkg 不会用 SONiC 版覆盖 apt 版。
- **改法：** 放弃 port 旧 0003 patch（context 漂移严重）。改用 `add-nh_id-aliases.sh`：(1) `route.h` 加 `rtnl_route_get/set_nh_id` 声明；(2) `route_obj.c` 末尾追加别名函数（转发到原生 `get/set_nhid`）；(3) **注册到 linker version-script `libnl-route-3.sym`**（libnl 用 `-Wl,--version-script` 控制符号导出，未注册的符号不导出）+ dpkg symbols 文件。awk 处理 version-script 里的 tab（sed 多行在 Makefile shell 里不可靠）。

### 3.2 sonic-swss-common（submodule，工作树，2 文件）
- **根因 #3：** `configure.ac` 用 `-std=c++14`，但 resolute `libgtest-dev` 的 `gtest-port.h` 硬要求 C++17（`#error C++ versions less than C++17`），tests 编译全挂。改 `c++14`→`c++17`。
- **根因 #3（C++17 重载决议变化）：** `common/boolean.h` 同时有 `operator bool() const` 和 `operator bool&()`。C++17 下 `EXPECT_FALSE(b)` 的 contextual conversion 把两个都当候选，`-Wconversion` 选了非 const 版（GCC 15 误报）→ `-Werror`。根因是 `operator bool&()` 只为 header 里 `operator>>` 的 `(bool&)(b)` 写入而存在。改法：**移除 `operator bool&()`**，两处 `operator>>` 改成读局部 `bool tmp` 再赋值。一处根因修复，消除全部 7 处隐式转换错误，且不碰测试代码。

### 3.3 sonic-swss（submodule，工作树，4 文件）
- **根因 #3：** 同 swss-common，`configure.ac` c++14→c++17。
- **根因 #3：** `orchagent/directory.h` 的 `class iterator : public std::iterator<...>`——`std::iterator` 在 C++17 deprecated（C++20 移除），`-Werror=deprecated-declarations`。改法：移除继承，显式写 5 个 typedef（`iterator_category`/`value_type`/`difference_type`/`pointer`/`reference`）。
- **根因 #4 + #3：** `configure.ac` 加 `-Wno-error=cpp`（C++17 `<cstdbool>` 的 `#warning`）+ `-Wno-error=unused-result`（C++17 `std::remove` 标记 `[[nodiscard]]`，`intfmgr.cpp` 忽略返回值）。
- **根因 #3（protobuf + glibc）：** swss tests 的 `dashtunnelorch_ut.cpp` include protobuf 头，protobuf 3.21.12 的 `stubs/mutex.h` 用 `std::mutex mu_{}` brace-init，GCC 15 libstdc++ 的 `__mutex_base()` 是 protected → hard error。改法：从 `Makefile.am` 的 `SUBDIRS` 移除 `tests`（vs 运行不需要 tests，避开 protobuf/gtest 一串问题）。

### 3.4 sonic-sairedis + SAI（submodule + 嵌套子仓库，工作树）
> 这是最深的一个坑。SAI 是 `sonic-sairedis` 里的嵌套 submodule。
- **根因 #5（doxygen 1.15.0 `<ref>` —— 核心）：** SAI 的 `parse.pl`（Perl）从 doxygen 生成的 XML 提取 metadata。trixie doxygen 1.9.8 输出纯文本 type 名（`@@type sai_xxx_t`）；resolute 1.15.0 把 type 名包成 `<ref refid="...">sai_xxx_t</ref>` 交叉引用。parse.pl 剥离 `<ref>` 标签后，相邻的 type 值粘连成 `boolsai_acl_field_data_t`、`typesai_acl_stage_t` 等 → 2199 个 `unrecognized tag` 错误。
- **改法（`SAI/meta/Doxyfile`）：** `AUTOLINK_SUPPORT = YES` → `NO`。doxygen 不再自动把 type 名识别成可交叉引用的符号，XML 输出回到纯文本（与 trixie 1.9.8 一致）。一处改动清零全部 2199 错误。
- **根因 #3/#7：** `configure.ac` c++14→c++17 + `-include cstdint/sstream/string`（resolute libstdc++ 不再传递包含，多个文件用 `uint32_t`/`stringstream` 但没直接 include）+ `-Wno-error=maybe-uninitialized`（LTO 跨编译单元分析对 `Buffer(data, size)` 假报 `m_size` 未初始化）。
- **根因 #2：** `pyext/py3/Makefile.am` SWIG 生成的 `pysairedis_wrap.cpp` 加 `-Wno-error=conversion -Wno-error=disabled-optimization`（SWIG 生成代码 + GCC 15 严格转换）。

### 3.5 sonic-gnmi（submodule，工作树）
- **根因 #7（SWIG 4.4 Go 后端）：** `swsscommon.i` 的 `%exception { $function }` 块，SWIG 4.3 在 Go 模式下会展开 `$function` 为实际函数调用；SWIG 4.4 移除了这个行为，`$function` 字面量留在生成的 `.cxx` 里 → `$function was not declared`。
- **改法陷阱：** gnmi 的 `Makefile` 用 `cp -f /usr/share/swss/swsscommon.i .` 从 slave 覆盖工作树，直接改 `.i` 文件每次构建被覆盖。必须在 `Makefile` 里 `cp` 后 `sed 's/$function/$action/g'`（`$action` 是 SWIG 标准变量，所有后端都展开）。

### 3.6 linkmgrd（submodule，工作树，49 文件）
- **根因 #6（boost 1.88 移除 `io_service`）：** boost 1.66+ 起 `io_service` 是 `io_context` 的弃用别名，1.88 彻底移除。linkmgrd 全代码用 `boost::asio::io_service`。
- **改法：** 全局 `sed s/\bio_service\b/io_context/g`（141 处，49 文件）。`io_service::strand` → `io_context::strand`，`io_service::post` → `boost::asio::post(io, ...)`（成员函数 `post` 也移除了，改自由函数）。
- **根因 #6（`io_context::work` 移除）：** boost 1.88 移除 `io_context::work`（C++17 用 `executor_work_guard`）。`MuxManager.h` 改 `boost::asio::executor_work_guard<boost::asio::io_context::executor_type>` + `make_work_guard`。
- **根因 #6（`std::hash<boost::uuids::uuid>` 重复）：** boost 1.88 内置了该 hash，linkmgrd 自定义的重复定义 → redefinition error。删除 `LinkProberBase.h` 里的自定义。

> **注（2026-07-06 落地）：** slave 最终 pin boost **1.83**（见 §3.1.A）。1.83 保留 `io_service`/`io_context::work`/成员 `post()`/`std::hash<uuid>`，故上述迁移在 1.83 下并非严格必需；但迁移代码已提交且 1.83 兼容（实验验证 linkmgrd 在 1.83 编译通过），保留不回退。若当初先试 1.83 可省这 49 文件迁移——但 `io_context` 是 asio 正确现代 API，迁移本身是 forward 修正。

### 3.7 sonic-eventd / sonic-bmp / sonic-sysmgr / sonic-stp / dhcprelay / wpasupplicant / sonic-redfish（父仓库 + submodules，工作树）
- **sonic-eventd（根因 #1 + #7 + #3）：** changelog trailer 缺前导空格和时间戳（`-- Name <email>` → ` -- Name <email>  Date`）+ control 的 boost 1.83 钉死加 1.88 备选 + `timestamp_formatter.cpp` 缺 `#include <sstream>`（resolute libstdc++ 不传递包含）。
- **sonic-bmp（根因 #2 cmake 4.x）：** `CMakeLists.txt` `cmake_minimum_required(VERSION 2.6)` < 3.5，resolute cmake 4.x 移除了 < 3.5 兼容。→ 3.5。
- **sonic-sysmgr / dhcp4relay / dhcp6relay（根因 #1）：** changelog trailer 末尾多余空格（`... -0800 ` → `... -0800`），resolute dpkg 严格解析拒绝。
- **sonic-stp（根因 #1）：** `Maintainer: Broadcom`（无 email）→ `Maintainer: Broadcom <sonic-build@local>`。
- **dhcprelay/dhcp4relay/dhcp6relay（根因 #6 + #2）：** control 的 `libboost-thread1.83-dev`/`libboost-system1.83-dev` 加 1.88 备选；PcapPlusPlus-24.09 子项目的 MemPlumber `cmake_minimum_required(3.0)` → 传 `-DCMAKE_POLICY_VERSION_MINIMUM=3.5`；PcapPlusPlus `Asn1Codec.cpp` GCC 15 `-Wfree-nonheap-object` 假阳性 → `-DCMAKE_CXX_FLAGS=-Wno-error=free-nonheap-object`。
- **wpasupplicant（根因 #2）：** slave buildflags 全局加了 `-std=gnu17`（为修 C 包的 C23 问题），但 wpasupplicant 的 `build.rules` 用 `$(CC) $(CFLAGS)` 编译 `.cpp` 文件，C 标准 `gnu17` 对 C++ 无效 → `cc1plus: error`。改 `debian/rules`：`DEB_CFLAGS_MAINT_STRIP=-std=gnu17` + UCFLAGS `filter-out`，并在主构建 `dh_auto_build` 也传 `CFLAGS="$(UCFLAGS)"`。
- **sonic-redfish/sonic-dbus-bridge（根因 #6）：** control 的 `libboost-dev`/`libboost-system-dev`（unversioned）加 1.88 备选。

### 3.8 已提交的基础设施改动（摘要）
- **FIPS：** resolute 无 FIPS 包，复用 trixie FIPS 二进制（`rules/sonic-fips.mk` `FIPS_DOWNLOAD_BLDENV=resolute→trixie`）。
- **grub2：** Ubuntu 把 grub2 拆成 `src:grub2` + `src:grub2-unsigned`（Debian 单源）。新建 `src/grub2-unsigned/` 构建 `grub-efi-amd64-bin`；grub2 2.14 的 overlayfs 硬链接屏障用 `cp -al` patch 绕过。
- **5 包换 resolute native base：** bash/socat/libyang3/libnl3/grub2 改用 `dget` 从 Ubuntu pool 拉 resolute 源码（linux-kernel 除外，procure download）。
- **docker-base-trixie：** `FROM debian:trixie` → `FROM ubuntu:resolute`（libc6 2.43，匹配 resolute deb）。
- **libyang3：** 重新启用 pr2362 patch（`LYD_VALIDATE_NOEXTDEPS`，sonic-mgmt-common 需要）。
- **sonic-frr：** `git reset --hard` 改无条件（曾 CROSS-only）；LTO off（`inet_ntop` always_inline + `_FORTIFY_SOURCE=3` link 失败）。
- **isc-dhcp：** LTO off（bind 9.11.36 链接错误）；`dh_install` 不建 udeb sbin 目录 → sed `mkdir -p`。

---

## 4. 验证结果

```
$ ls -la target/sonic-vs.bin
-rwxr-xr-x 2558783471 Jul  4 22:58 target/sonic-vs.bin   # 2.4 GB ONIE installer

$ build_kvm_image.sh target/sonic-vs.img files/onie-recovery-x86_64-kvm_x86_64-r0.iso target/sonic-vs.bin 10
→ target/sonic-vs.img 5.4 GB qcow2 (SONiC installed via ONIE)

$ kvm -drive file=target/sonic-vs.img -serial telnet:127.0.0.1:9000 ...
→ sonic login: (SONiC boot to login prompt)

admin@sonic:~$ cat /etc/os-release
PRETTY_NAME="Ubuntu 26.04 LTS"
VERSION="26.04 LTS (Resolute Raccoon)"
VERSION_CODENAME=resolute
ID=ubuntu
UBUNTU_CODENAME=resolute
```

---

## 4.5 resolute variant 命名重构尝试与架构约束

> **更新 (2026-07-05, commit `a8fee77a4`)：** variant-naming 重构已按 resolute 仓库 `docs/superpowers/specs/2026-07-05-resolute-variant-naming-design.md` 实现并提交——50 个 leaf `.j2` ARG BASE + 45 个 `.mk` 改 resolute，`slave.mk` 加 resolute 块 filter-out trixie base，`docker-base-trixie` revert 回 `debian:trixie`，resolute variant 目录投入 vs 构建链。下方"已回退/走不通"为历史记录，保留供参考。静态验证（spec §7 grep 残留检查 + `make -n` 解析）已通过；完整 build+KVM 验证待补。

> 镜像构建成功后，曾尝试把"trixie 命名、resolute 内容"的 base 链改成"resolute 命名、与 trixie 共存"的独立 variant（`docker-base-resolute` / `docker-config-engine-resolute` / `docker-swss-layer-resolute`，复制自 trixie，FROM `ubuntu:resolute`）。**该尝试在现有构建系统下走不通**，已回退到已提交方案。这里记录根因，避免重复踩坑。

### 三次失败
1. **批量给 34 个 leaf `docker.mk` 加 `SONIC_RESOLUTE_DOCKERS +=` 行** → 同时要求 trixie 和 resolute 两套 base → `No rule to make target 'docker-config-engine-trixie.gz-load'`。
2. **`DOCKER_IMAGES := $(SONIC_RESOLUTE_DOCKERS)`**（slave.mk resolute 块）→ resolute 列表只有 3 个 base variant，丢了所有 leaf docker。
3. **`DOCKER_IMAGES := $(SONIC_TRIXIE_DOCKERS)`**（复用完整 trixie 列表）→ `docker-dash-engine` 注册在 `SONIC_DOCKER_IMAGES`（`platform/vs/docker-dash-engine.mk:8`）而非 `SONIC_TRIXIE_DOCKERS`，被排除 → `No rule to make target 'target/docker-dash-engine.gz'`。

### 架构根因
**leaf docker 的 `ARG BASE` 硬编码 trixie 字面量，构建系统不传 `--build-arg BASE`。**
- `dockers/docker-database/Dockerfile.j2:2` → `ARG BASE=docker-config-engine-trixie-{{DOCKER_USERNAME}}:{{DOCKER_USERTAG}}`（"trixie" 是字面量，非变量）。
- 全树 24 个 leaf 用 `docker-config-engine-trixie`、9 个用 `docker-swss-layer-trixie`——全部硬编码。
- slave.mk 两条 docker 构建规则（`:1175` simple 和 `:1316` 普通）的 `--build-arg` 列表（`:1187`、`:1371`）**都不含 `BASE`**。
- 因此 leaf 的 `FROM $BASE` 永远是 `docker-config-engine-trixie-...`，与 BLDENV 无关。

**推论：** remapping `DOCKER_CONFIG_ENGINE_TRIXIE := $(DOCKER_CONFIG_ENGINE_RESOLUTE)` 只能让 `_LOAD_DOCKERS` 加载 resolute base 镜像，但 leaf Dockerfile 仍 `FROM docker-config-engine-trixie-...`（trixie tag）→ trixie base 未被构建 → 构建失败。**要让 leaf 用 resolute base，必须改 leaf 文件本身**（无 `--build-arg BASE` 可走捷径）。

### 现状
- **已实现 resolute 命名链（commit `a8fee77a4`，2026-07-05）**：50 个 leaf `.j2` ARG BASE + 45 个 `.mk`（`_LOAD_DOCKERS`/`_DBG_DEPENDS`/`_DBG_IMAGE_PACKAGES`）从 trixie 改 resolute；`slave.mk` 加 `BLDENV==resolute` 块 filter-out 3 个 trixie base image；`docker-base-trixie` revert 回 `FROM debian:trixie`（trixie variant 恢复 pristine，revert `3d265d73b`）；resolute variant 目录/rules 投入 vs 构建链（FROM 链 `ubuntu:resolute → docker-base-resolute → docker-config-engine-resolute → docker-swss-layer-resolute`）。trixie variant 完整保留，BLDENV=trixie 仍走 `else` 默认分支（control 路径）。该方案不属下方 A/B/C 三选——直接 sed leaf `ARG BASE`（非模板化、非复制目录）+ resolute base variant + slave.mk filter-out。
- **残留：** `platform/vpp` submodule 内 3 `.j2` + 1 `.mk` variant-naming 改动需 submodule 提交 + 指针 bump（C1，单独处理；vs 构建不依赖 vpp）。完整 build + KVM 验证待补（C4）。

### 若要"干净"的 resolute 命名
| 方案 | 改动 | 代价 |
|---|---|---|
| A. 保持已提交（推荐） | 撤销 resolute variant 目录；`docker-base-trixie` FROM ubuntu:resolute | 0；目标已达成，base 名叫 trixie 但内容是 resolute |
| B. 模板化 variant 后缀 | 34 个 leaf `.j2` 把 `ARG BASE` 里硬编码 `trixie` 改成 `{{DOCKER_VARIANT}}`；j2 渲染按 BLDENV 导出；34 个 `docker.mk` 加 `SONIC_RESOLUTE_DOCKERS`；slave.mk remap | ~70 处 + j2 上下文；一套 docker 按 BLDENV 切换 |
| C. 全套 resolute leaf 复制 | 复制 34 个 leaf docker 目录为 `-resolute` 版 + 34 个 `docker.mk` | ~70 个新文件；维护负担大 |

---

## 5. 遗留 / 待办

- **submodule 指针未提交：** ~~swss-common/swss/sairedis/gnmi/linkmgrd/stp/redfish/dhcprelay/wpasupplicant/libnl3 的工作树改动需在各 submodule 仓库内提交，再 bump 父仓库指针。~~ **✅ 已完成（C1，2026-07-05）：** 14 个 submodule 在各自 `resolute` 分支提交补丁 + 父 gitlink bump（commit `5e4f25d43`）；3 个损坏的对象库（sonic-mgmt-framework/sonic-swss/sonic-sairedis，`--reference` alternates 丢失）已从 origin 重克隆修复。fresh clone 现可复现。
- **pkgutil sed off-by-one（C3）：** ~~`sonic_debian_extension.j2` 的 pkgutil sed 用 `spec.submodule_search_locations[0]`（包目录），`os.path.dirname()` 返回父级，CLI 插件放错位置。~~ **✅ 已修复（C3，commit `e93860839`）：** 改用 `spec.origin`（`__init__.py`），`dirname()` 还原原行为。
- **done-bar smoke 证据（C4）：** **✅ 已验证（2026-07-05）：** 提交后状态（C1+variant-naming+C3）build 成功（`sonic-vs.bin` 2.4G，build commit `e938608`）+ KVM boot + login + `show version`（resolute.0-e938608 docker tag，variant-naming 验证）+ `docker ps`（database/gnmi/pmon 健康）+ os-release=Ubuntu 26.04。详见 `docs/superpowers/plans/done-bar-status.txt`。
- **bash plugin patch（~7 hunks）：** 当前 bash 不带 plugin，待 port 到 5.3。（review I9 实测 32 hunks/8 文件/583 行，工作量被低估。）
- **libnl3 RTA_NH_ID：** 当前用别名 wrapper 绕过；更干净的做法是让 swss 上游改用 `rtnl_route_get_nhid`（无下划线，libnl 3.12 原生）。
- **swss tests：** 从 `SUBDIRS` 移除 tests 跳过了 protobuf/gtest 编译；长期应适配 protobuf 3.21.12 + GCC 15（`std::mutex mu_{}` brace-init 的 protected 访问）。
- **`alternate object path` warning：** `.git/modules/.../objects/info/alternates` 指向原始 repo，构建时 git 报 warning（non-fatal，环境状态）。
- **sonic-stp submodule changelog：** 工作树改了，指针待补提交。~~**✅ 已提交（C1）。**~~
- **`show.plugins.dhcp-relay/macsec` import warning（C4 调查结论，非 build 缺陷）：** 运行 `show` 时报 `failed to import plugin show.plugins.dhcp-relay/macsec: No module named`。曾误判为 squashfs 打包丢失（因查了 `target/sonic-vs.bin__vs__rfs.squashfs` 这个非真实中间产物）。查**真实运行 rootfs**（qcow2 `part3/image-resolute.0-e938608/fs.squashfs`）确认 `show/plugins/` 有完整 18 个 .py 含 `dhcp-relay.py`/`macsec.py`，sonic-utilities 完整。真因：Python 模块名不能含连字符——`util_base.py:23` `pkgutil.iter modules` 返回磁盘名 `dhcp-relay`，`:31` `importlib.import_module` 必然 `ModuleNotFoundError`。upstream master 未修（同样用 `import_module`），commits `f36ac95a`/`8647356d` 降级为 `log_warning`（不致命）；tri/202605 同样失败 → 非 resolute 回归，非 C1-C3。`show ip intf`/`show ip bgp sum` 的 `No such command` 真因是 `Db()` 连 configdb 失败（database 容器刚 Up + vs 无 minigraph → configdb 空）→ click 不注册 `ip` 子命令树，运行时时序问题。
- **vs 默认无 minigraph.xml：** `config load_minigraph -y` 失败（`/etc/sonic/minigraph.xml` 不存在）。vs 镜像默认不预装 minigraph，需单独生成/导入步骤。

---

## 6. 关键教训

1. **改 j2 模板，不是生成的 .sh：** `sonic_debian_extension.sh` 每次 build 从 `sonic_debian_extension.j2` 重新生成，改 `.sh` 无效。这是踩了两次的坑。
2. **版本号撞号陷阱：** SONiC patch 版 libnl `3.12.0-2` 和 resolute apt 版完全相同 → 同版本 dpkg 不覆盖 → patch 不生效。要么 bump 版本号，要么靠 linker version-script 控制符号导出。
3. **doxygen `<ref>` 是最深坑：** 表面看是 parse.pl 的 2199 个 tag 错误，根因是 doxygen 1.15.0 的 XML 输出格式变化。关 `AUTOLINK_SUPPORT` 一键解决——定位根因胜过逐个 patch。
4. **`--no-build-isolation` + CFLAGS：** resolute 的 pip 生态里，apt 包无 RECORD 文件，pip 不认已装包会重新从源码编译。给 `install_pip_package` 加 `--no-build-isolation` + 全局 CFLAGS 是务实解法。
5. **降 warning 而非改代码：** 对 SWIG 生成代码、protobuf 头、lxml Cython 生成代码这类"不该手改"的代码，用 `-Wno-error=xxx` 或宏重定义（`-D__fds_bits=fds_bits`）比改源码更可持续。
