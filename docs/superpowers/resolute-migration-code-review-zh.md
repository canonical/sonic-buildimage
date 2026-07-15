# SONiC Resolute 迁移代码评审

**仓库:** `/home/sheldon-qi/sonic-buildimage-resolute` (branch `resolute`)
**审查范围:** `77cfa809d` (merge-base with `origin/202605`) .. `92b24de74` (HEAD) = 62 committed commits + 工作树未提交改动 + 多个 submodule 内未提交改动
**日期:** 2026-07-05
**对照基线:** [设计规格](specs/2026-07-03-sonic-202605-resolute-migration-design-en.md) / [实现计划](plans/2026-07-03-sonic-202605-resolute-migration-plan-en.md) / [迁移报告](resolute-vs-migration-report.md)

> 本评审由独立只读 subagent 完成：交叉核验了 diff、submodule、报告与代码的对应关系（非仅读报告）。

---

## 1. 目标达成情况

**5 个 Phase（committed HEAD `92b24de74`）：**

| Phase | 状态 | 证据 |
|---|---|---|
| P0 管线 + spikes | ✅ | `760e09cc3`/`e16c4d8b8`/`8f4fc81ed`；docker `5:29.6.1-1~ubuntu.26.04~resolute`；kernel 走 R2 fallback（source-build，非 procure） |
| P1 sonic-slave-resolute | ✅ | `5e29f4bcd`+`f40481279`+`c1dfdf0a3`；`fips-status.txt` 记录 FIPS=ON（trixie reuse） |
| P2 host OS | ✅ | `a4874681d`/`41bec4fdb`/`92b24de74`；**k8s/cri 跳过未按 plan 实现**（见 I5） |
| P3 container base | ✅ 但用 trixie 命名 | `3d265d73b` `docker-base-trixie FROM ubuntu:resolute` |
| P4 vs 容器 | ⚠️ committed 指向 trixie 命名链；WT 改指 resolute 命名（未提交，见 C2） |
| P5 assemble+boot | ⚠️ 部分 | `sonic-vs.bin` 2.4GB + os-release=Ubuntu 26.04 有断言；**SONiC smoke 无证据**；`done-bar-status.txt` 不存在 |

- **Goal 1（source-swap）：达成，但 spec 把工作量低估了。** spec 称"几乎只是 source swap""no source-build changes"——resolute 的 GCC15/boost1.88/SWIG4.4/doxygen1.15/py3.14 必然破坏既有 SONiC submodule 源码，submodule 补丁不可避免。这是 spec 问题，不是实现问题。
- **Goal 2（Category-C catalog）：✅ 已交付且完整**（`93f1fe2a2`，15/15 包有 verdict，非 stub）。

**值得肯定的优点**：62 个基础设施 commit 逻辑自洽；多个根因修复精准——`SAI/meta/Doxyfile:312` `AUTOLINK_SUPPORT=NO` 一键清零 2199 错误（正确层级，autolink 无下游依赖）、`swss-common/common/boolean.h` 移除 `operator bool&()`（真根因，语义保留）、`gnmi` `$function→$action` sed 与版本无关、`libnl3` linker version-script 注册符号正确、`Dh_Lib.pm` 单点 patch 取代散布 `mv` band-aid；FIPS 决策锁定且有文档；variant-naming 设计稿正确诊断了架构约束。

---

## 2. 实现方法的问题

### Critical（Must Fix）

**C1. Fresh clone 无法复现构建——所有 submodule 源码补丁 + 多个 parent WT 补丁未提交，父指针未 bump。**
- 证据：`git status --short` 显示 `m src/sonic-swss src/sonic-sairedis src/sonic-gnmi src/linkmgrd src/sonic-stp src/sonic-redfish src/dhcprelay src/wpasupplicant/sonic-wpa-supplicant`（小写 m = submodule 工作树 dirty，指针未变）。
- 关键未提交补丁：`swss` c++17 + `directory.h` typedefs + tests 移除；`sairedis`+`SAI` `Doxyfile`+`configure.ac`+`pyext`（嵌套 SAI 需 4 步：SAI 提交 Doxyfile → sairedis 更新 SAI gitlink → sairedis 提交 → 父更新 sairedis gitlink，全未满足）；`gnmi` Makefile sed + 未记录的 `go.mod`/`go.sum`；`linkmgrd` 49 文件；`libnl3` `Makefile`+untracked `patch/add-nh_id-aliases.sh`；`sonic_debian_extension.j2` 全部 pip 修复；`build_debian.sh` g++/swig；variant-naming 重构 118 文件。
- 影响：clone HEAD → 缺 c++17/Doxyfile/boolean.h/io_context/libnl3 alias/pkgutil sed → slave 之后全程失败。报告 §3 序言与 §5 透明承认，但这意味着"done"不可复现。
- 修复：在每个 submodule 内提交补丁 → bump 父 gitlink → 提交 parent WT。这是交付的前置。

**C2. Variant-naming 状态矛盾：报告 §4.5 已过时，WT 实现了其声称"已回退"的共存方案，且未验证。**
- 证据：报告 §4.5"现状"称"已回退到已提交方案（`docker-base-trixie FROM ubuntu:resolute`），resolute variant 目录未被 vs 构建使用"。但实际 WT：
  - `dockers/docker-base-trixie/Dockerfile.j2` 被 **staged** 改回 `FROM debian:trixie`（revert `3d265d73b`）。
  - 118 个 leaf `.j2`/`.mk` 把 `ARG BASE`/`_LOAD_DOCKERS` 从 trixie 改 resolute（unstaged），如 `dockers/docker-database/Dockerfile.j2:2` → `docker-config-engine-resolute-...`、`rules/docker-database.mk` → `DOCKER_CONFIG_ENGINE_RESOLUTE`。
  - `slave.mk` WT 新增 resolute 块（`filter-out $(DOCKER_BASE_TRIXIE) ...`）。
  - untracked `dockers/docker-{base,config-engine,swss-layer}-resolute/` + `rules/docker-*-resolute.{mk,dep}`（FROM 链与 `_LOAD_DOCKERS` 自洽）+ `docs/superpowers/specs/2026-07-05-resolute-variant-naming-design.md` 设计稿。
- 即 WT 正在实现设计稿的"共存 variant"方案（revert trixie base 到 pristine + filter-out + leaf 改指 resolute），与报告 §4.5"已回退、variant 目录未使用"直接矛盾。
- 风险：(a) 报告 materially 不准确；(b) WT 重构未经验证（build 证据 Jul 4 早于 WT Jul 5）；(c) **staged 的 `docker-base-trixie` revert 若单独提交会破坏构建**（trixie libc6 2.41 < resolute deb 需要的 2.42+，正是 `3d265d73b` 解决的失败）——它是原子重构的一部分，不能单独提交。
- 修复：要么撤销 WT variant 重构（回到 committed "trixie 名 resolute 内容"），要么完整验证后原子提交全部（staged+unstaged+untracked）并更新报告 §4.5。当前半 staged 状态是隐患。

**C3. `sonic-package-manager` pkgutil sed 存在 off-by-one 运行时 bug。**
- 证据：`files/build_templates/sonic_debian_extension.j2:1057-1061`（WT）。sed 把 `pkgutil.get_loader(f'{command}.plugins')` 替换为 `importlib.util.find_spec(...)`，并设 `pkg_loader.path = spec.submodule_search_locations[0]`（= 包目录）。但原 `pkgutil.get_loader(...).path` 返回 `spec.origin`（= `__init__.py`）。下游 `os.path.dirname(pkg_loader.path)` 因此返回插件目录的**父级** → `get_cli_plugin_directory('show')` 返回 `.../show` 而非 `.../show/plugins`，CLI 插件文件放错位置。
- 同时 `|| true` 在构建时掩盖了 sed 不匹配（若上游改名 `pkg_loader` 或改 f-string → 保留坏的 `pkgutil.get_loader` → 运行时 crash）；路径硬编码 `python3.14/dist-packages/...` → py3.15 升级即断。
- 修复：`pkg_loader.path = spec.origin`；更好的做法是 patch `src/sonic-utilities` 源码 + bump 指针（可审查、抗升级）。

**C4. Done-bar 未满足：SONiC smoke 无证据，且 build 证据早于 WT 重构。**
- 证据：报告 §4 仅展示 `os-release` + `sonic login:`；spec §8 Phase 5 要求 `config load_minigraph -y`/`show version`/`show ip intf`/containers healthy，均无输出证据。plan Task 18 Step 5 要求的 `docs/superpowers/plans/done-bar-status.txt` 不存在。`target/sonic-vs.bin` 时间戳 Jul 4 22:58 早于 WT variant 重构（Jul 5），故 WT 状态的构建未经验证。
- 修复：在最终（提交后）状态重跑 one-image + KVM，记录 smoke 命令实际输出到 `done-bar-status.txt`。

### Important（Should Fix）

**I5. k8s/cri 跳过未按 spec/plan 实现。** `build_debian.sh:238-282` k8s 块与 trixie 字节相同，无 `IMAGE_DISTRO==resolute` 守卫；跳过仅靠既有 `INCLUDE_KUBERNETES=n`（`rules/config` 默认，非 resolute 专有）。spec 承诺的"cleanly guarded on `IMAGE_DISTRO==resolute` (reversible for backlog)"未交付。`build_debian.sh:278` cri-dockerd URL `cri-dockerd_${MASTER_CRI_DOCKERD}.3-0.debian-${IMAGE_DISTRO}_amd64.deb` → resolute 下生成 `debian-resolute`（启用即 404，latent backlog bug）。

**I6. Kernel 未 procure，`config.user` 死开关。** `rules/linux-kernel.mk` 未改（source-build）；`eac57a2d5` bump sonic-linux-kernel submodule（libbpf const cast）。`rules/config.user:26` `KERNEL_PROCURE_METHOD = download` 无任何代码读取（dead knob），注释却写"download prebuilt"——doc/code 不符。spec 主路径未实现，走了 R2 fallback（source-build），但 ABI 保留 `+deb13`（R2 建议 `+resolute`）。可接受，但应删除/纠正 config.user 误导性注释。

**I7. 10 个 resolute 平台 Dockerfile 缺 `--exclude=/etc/hosts`（rsync EBUSY）。** `dockers/dockerfile-macros.j2:49` 宏已修（WT），但 10 个 inline-rsync 的 `.j2` 漏改：broadcom（`docker-syncd-brcm-dnx:35`、`-legacy-th:35`、`-rpc:70`、`dnx-rpc:70`）、marvell-teralynx（`saiserver:47`、`syncd:39`、`rpc:59`）、marvell-prestera（`saiserver:39`、`syncd:32`、`rpc:58`）。构建这些平台镜像会遇 EBUSY。报告 §3.1.D 称"12 个 Dockerfile 之前已改 [已提交]"——**错误**，`git diff 77cfa809d..HEAD` 显示 dockers/ 下无任何 rsync/hosts 已提交改动，全为 WT。另 `/etc/hostname` 也被 buildkit bind-mount，未排除（latent）。

**I8. 3 个 resolute Dockerfile 缺 `libxml2`→`libxml2-16`。** `platform/mellanox/docker-saiserver-mlnx/Dockerfile.j2:46`、`platform/mellanox/docker-syncd-mlnx/Dockerfile.j2:36`、`platform/nvidia-bluefield/docker-syncd-bluefield/Dockerfile.j2:35` ARG BASE 已切 resolute 但 `libxml2` 未转换 → resolute 上 apt-get 失败。

**I9. bash plugin 未 port——功能回归。** `src/bash/Makefile:15-18` `quilt push -a` 被注释，TODO"port 0001 plugin patch to 5.3"。补丁文件 `src/bash/patches/0001-Add-plugin-support-to-bash.patch` 存在且与 trixie 字节相同，但应用被禁用。plugin = 自定义 `plugin.c`/`plugin.h` + `load_plugins()` + `on_shell_execve` 钩子（SONiC mgmt framework 用）。报告 §5 称"~7 hunks"——**实际 32 hunks/8 文件/583 行**，移植工作量被严重低估。

**I10. swss tests 移除丢失 ~9 个测试二进制（超出声称根因）。** `src/sonic-swss/Makefile.am:2,4` 从 SUBDIRS 移除 `tests` 丢弃 `swssnet_ut`/`request_parser_ut`/`quoted_ut`/`aclorch_ut`/`dashtunnelorch_ut`/flex_counter/p4orch 等 ~9 个。声称根因仅 `dashtunnelorch_ut.cpp` 的 protobuf 失败。对 vs 可接受（运行时不需要 tests），但对非 vs 构建是潜在覆盖率回归。更精确做法：仅从 `mock_tests/Makefile.am` 的 `tests_SOURCES` 移 `dashtunnelorch_ut.cpp`。

**I11. linkmgrd `test/` 未完成 io_context 迁移。** `src/` 49 文件已迁移（sound），但 `test/` 残留：`test/FakeLinkProber.cpp:46,73,156,168,196` 5 处 `ioService.post(...)` 成员调用未转自由函数；`test/MuxPortTest.h:44`、`test/LinkManagerStateMachineTest.h:65` 仍用 `io_context::work`（1.88 移除，**1.83 保留**——slave 已改 1.83，故此项在 1.83 下非问题）；`test/MuxManagerTest.cpp:339` `mWork.~work()` 析构名与新 `executor_work_guard` 类型不匹配。`make all`（vs）不编译 test/ 故 vs 构建通过，但 `make test` 会断。> **注（2026-07-06）：** slave 改 1.83 后 `io_context::work` 恢复，但 `ioService.post` 成员调用与 `~work()` 析构名问题是迁移不完整（与 boost 版本无关），`make test` 在 1.83 下未验证。

**I12. `slave.mk` resolute 块未过滤 bookworm/bullseye 等。** WT resolute 块仅 `filter-out $(DOCKER_BASE_TRIXIE) $(DOCKER_CONFIG_ENGINE_TRIXIE) $(DOCKER_SWSS_LAYER_TRIXIE)`，而默认 `else` 分支过滤 `JESSIE..BOOKWORM` 全部。`docker-sonic-vs` 注册在 `SONIC_BOOKWORM_DOCKERS`（`platform/vs/docker-sonic-vs.mk:53`）+ `SONIC_DOCKER_IMAGES`，其 `_LOAD_DOCKERS=DOCKER_SWSS_LAYER_BOOKWORM`（未构建）。被 `platform/vs/syncd-vs.mk:7 findstring(BLDENV, bookworm trixie)` + installer 双重守卫挡住，故 vs 下 latent 非活跃，但应过滤以与默认分支一致，避免未来意外。

**I13. `Dh_Lib.pm` patch 非幂等且脆。** `sonic-slave-resolute/Dockerfile.j2:862-864`（commit `c1dfdf0a3`）：`grep -q "DBGSYM_PACKAGE_TYPE' => 'ddeb'" ... && sed ...`。在已 patch 层上重跑时首个 `grep -q ddeb` 失败 → `&&` 链短路 → RUN 退出 1 → 构建失败。实际靠 slave 总从 fresh `FROM ubuntu:resolute` 重建才 work。应为 `grep -q deb || sed ...`。debhelper 升级可能硬失败（base 已 pin，风险低）。

**I14. 全局 `-std=gnu17` 是错误层级。** `sonic-slave-resolute/Dockerfile.j2:884`（commit `f40481279`）写 `APPEND CFLAGS -std=gnu17 ...` 到 `/etc/dpkg/buildflags.conf`。仅 CFLAGS（无 CXXFLAGS），标准 C++ 编译安全；但 `wpasupplicant` `build.rules:85-94` 用 `%.c*` 通配 `.cpp` 经 `$(CC) $(CFLAGS)` → `cc1plus: -std=gnu17 valid for C/ObjC but not C++`，需 §3.7 WT 单独 `DEB_CFLAGS_MAINT_STRIP` 补救。更干净：放弃全局 C 标准，按包用 `DEB_CFLAGS_MAINT_APPEND` 修 bash 的 K&R 问题。

**I15. `libnl3` 静默丢弃 4 个 patch + 死代码 + 版本号建议错误。** `src/libnl3/Makefile:32-33` 用 `bash ../patch/add-nh_id-aliases.sh` 取代 `stg import -s ../patch/series`，孤立了 `switch-to-debhelper.patch`、`keep-symbol-versions-in-libraries.patch`、`update-changelog.patch`、`skip-tests-when-having-no-private-netns.patch`——报告 §3.1.E 未提及。`debian/libnl-route-3-200.symbols` 的 awk 是**死代码**（文件仅 16 行模板，regex `^rtnl_route_get_nhid;$` 永不匹配，报告称"symbols file 已更新"误导）。`patch/0004-rtnl_route_get_nh_id-alias-for-3.12.patch` 孤立未引用。报告 §6 lesson 2 建议 bump 版本 `3.12.0-2~sonic1` 是**倒退**——`~` 在 dpkg 比较中排在空字符串前，比 `3.12.0-2` 旧，apt 不会覆盖；应为 `3.12.0-2+sonic1` 或 `3.12.0-2.1`。alias 脚本非幂等（无 grep guard，靠 `rm -rf ./libnl3-3.12.0` 缓解）。

**I16. `gnmi` `go.mod`/`go.sum` 未记录修改。** go-redis `v7.0.0-beta`→`v7.4.1`，新增 `cncf/xds`、`envoyproxy/go-control-plane`、`protoc-gen-validate`、`genproto`。报告 §3.5 未提。可能是新 Go 工具链 `go mod tidy` 结果，但应记录或还原。

**I17. trixie 控制路径部分受损。** `Makefile:53-74` catch-all 已移除 trixie 派发（仅 resolute），`make <target> BLDENV=trixie` 经 catch-all 不工作；trixie 仅经 `make_work`（`Makefile:120` `$(if $(BUILD_TRIXIE),...)`，用于 `sonic-slave-build` 等）或直接 `make -f Makefile.work BLDENV=trixie <target>` 可用。spec §8 要求 trixie 作 control 全程可用——slave build 可，但 one-image 经顶层 catch-all 不可。且 WT variant 重构后 leaf 指 resolute base，`BLDENV=trixie` 会拉 resolute base（非纯 trixie control），committed 状态下 trixie control 完好。

**I18. `dget -u` 经 HTTP 跳过 GPG + 未来 404 风险。** bash/socat/libnl3/libyang3/grub2 + lldpd/openssh/makedumpfile/kdump-tools 全用 `dget -u`（skip GPG）经 HTTP 拉取。完整性缺口（符合 SONiC 既有约定）；Ubuntu pool 在版本被取代时会删除 .dsc → 未来构建 404 风险。

### Minor（Nice to Have）

- **M19.** `dockers/docker-swss-layer-resolute.mk:1` 注释仍写"trixie-based docker image"（复制未改）。
- **M20.** catalog libnl3 行称"RTA_NH_ID NOT in resolute libnl3 3.12.0"——不精确：feature 上游已实现（`rtnl_route_get_nhid` 无下划线，字段 `rt_nhid`，attr `ROUTE_ATTR_NHID`），缺的只是 SONiC 旧名（带下划线）。
- **M21.** 报告 §3.7 把 `sonic-eventd`/`sonic-sysmgr` 归为 submodule——实际是父仓库 tracked tree；`sonic-dbus-bridge` 是 `sonic-redfish` 内子目录非 submodule。
- **M22.** 报告 §3.1.B 把 M2Crypto `CFLAGS=-D__fds_bits=fds_bits` 和 `systemctl disable resolvconf.service || true` 归到 `build_debian.sh`——实际在 `sonic_debian_extension.j2:87,545`（§3.1.C 正确，§3.1.B 内部不一致）。"glibc 2.43 重命名 `__fds_bits`"也不准确——split 古已有之，真实触发是 M2Crypto SWIG 硬编码 `__fds_bits` 而 `Python.h` 定义 `_GNU_SOURCE`→`__USE_XOPEN`→`__fds_bits` 隐藏。M2Crypto 经 apt 装（`j2:265`），`install_pip_package` 宏的 CFLAGS 根本不作用于它。
- **M23.** 报告 §3.4"2199 unrecognized-tag"标签略偏——实际是 `invalid type tag value`（`ProcessTagType` 锚定 regex 失配），非 unrecognized tag name。
- **M24.** `sonic_debian_extension.j2:231` 注释"regex by pyangbind transitive"已过时（regex 经 sonic-utilities 拉取）。
- **M25.** `sonic-slave-resolute/Dockerfile.j2:734-735` 交叉构建路径仍装 unversioned `libboost-dev:$arch`——与 amd64 修复的 1.90 header-only 陷阱相同，armhf/arm64 上重现（latent）。
- **M26.** 报告 §3.1.A 称 gcc-multilib 为 openssh——commit `e3a75d22f` 称是为 grub2 i386 模块构建（libwtmpdb-dev 才是 openssh）。
- **M27.** 工作树残留构建产物（`database-chassis.service`、`installer/platforms*`、`*.egg-info`、`src/*/build`）应 gitignore/清理；仅 `docker-base-trixie` staged 而其余 unstaged——staging 不一致。

---

## 3. 改进建议

1. **先提交再宣告完成。** 在每个 submodule 内提交源码补丁 → bump 父 gitlink → 提交 parent WT（`sonic_debian_extension.j2`/`build_debian.sh`/`slave.mk` resolute 块/`libnl3` alias/`dockerfile-macros.j2`/12 个 Dockerfile rsync/variant 重构或其撤销）。提交前重跑 fresh-clone 构建验证可复现性（C1）。

2. **解决 variant-naming 二选一。** 要么撤销 WT variant 重构（回到 committed "trixie 名 resolute 内容"，报告 §4.5 即准确），要么按设计稿完整验证后原子提交（staged docker-base-trixie revert + 118 leaf + slave.mk 块 + variant 目录）并更新报告 §4.5。绝不保留当前半 staged 状态（C2）。设计稿方案本身 sound（revert trixie base pristine + filter-out + leaf 改指 resolute），但 slave.mk resolute 块应同时过滤 `SONIC_BOOKWORM_DOCKERS` 等以与默认 `else` 一致（I12）。

3. **修复 `pkgutil` sed off-by-one。** `pkg_loader.path = spec.origin`（非 `submodule_search_locations[0]`）；或改 patch `sonic-utilities` 源码 + bump 指针（C3）。去掉路径里硬编码的 `python3.14`。

4. **补 done-bar 证据。** 在最终（提交后）状态重跑 `make PLATFORM=vs BLDENV=resolute` + KVM boot，记录 `config load_minigraph -y`/`show version`/`show ip intf`/`docker ps` 实际输出到 `docs/superpowers/plans/done-bar-status.txt`（C4）。

5. **补 13 个遗漏 Dockerfile。** 10 个 inline-rsync 加 `--exclude=/etc/hosts`（I7）；3 个加 `libxml2-16`（I8）。`grep -rn 'rsync -axAX' platform/ dockers/` + `grep -rn 'libxml2\b' platform/ dockers/` 全树核对。

6. **k8s/cri 守卫显式化。** 即使沿用 `INCLUDE_KUBERNETES=n`，也应在 `build_debian.sh:278` 把 cri-dockerd URL 改为不依赖 `debian-${IMAGE_DISTRO}` 的形式，或在 spec 中明确"靠既有 flag 跳过"并更新 plan Task 12（I5）。

7. **kernel 文档对齐。** 删除 `config.user` 的 `KERNEL_PROCURE_METHOD=download` 死开关及误导注释，或实现 procure 路径（I6）。

8. **sed 补丁稳健化。** `pkgutil` sed、`hsflowd`/`sonic-stp` Maintainer sed、`gnmi` `$function` sed——优先 patch 源码 + bump 指针而非 sed 生成/导入文件；必须 sed 时用稳定锚（函数签名而非行号/变量名），并加 `grep -q` 幂等 guard（C3、I13、I15 同理）。

9. **`libnl3` 收尾。** 决定 alias wrapper vs 版本 bump（用 `+sonic1` 非 `~sonic1`）；删 4 个被孤立 patch 或显式 port；删死代码 symbols awk + 孤立 0004 patch + stg git init 死开销；加 grep guard 使脚本幂等（I15）。

10. **`-std=gnu17` 改按包。** 去掉全局 `APPEND CFLAGS -std=gnu17`，bash 用 `DEB_CFLAGS_MAINT_APPEND=-std=gnu17`，避免 wpasupplicant 等 `$(CC)$(CFLAGS)`-on-.cpp 连锁补救（I14）。

11. **bash plugin 决策。** port 32 hunks 到 5.3，或在 catalog/report 显式标记"plugin 功能在 resolute 上未提供"为已知回归（I9）。

12. **swss tests / linkmgrd test/ 收尾。** swss 改为仅移除 `dashtunnelorch_ut.cpp`（保留其余测试）；linkmgrd 完成 `test/` 迁移（5 处 `ioService.post` + `io_context::work` + `~work()`），使 `make test` 不断（I10、I11）。

13. **报告订正。** 修正 §3.1.B/§3.1.D 归属与"已提交"误述、§3.1.E symbols 误导、§3.5 go.mod 未记录、§3.6 test/ 未迁、§4.5 variant 现状、§5 bash hunks 计数（M19-M27）。

---

## 4. 总体评估

**是否达到可交付状态？** **No / With fixes.**

**理由：** 基础设施层（62 commits：slave/FIPS/grub2 拆分/dbgsym 单点/dget swap/管线）与 Goal 2 catalog（15/15 完整）扎实，多个根因修复精准（Doxyfile/boolean.h/gnmi sed/libnl3 version-script），FIPS 决策锁定有据。但当前不可交付有四道硬伤：

1. **构建不可复现**：fresh clone HEAD 缺全部 submodule 源码补丁 + 父指针未 bump（C1）；
2. **报告与代码矛盾**：报告 §4.5 与 WT 实际状态直接矛盾，WT 是未验证的 variant 重构且 staged revert 单独提交即破坏构建（C2）；
3. **运行时 bug**：`pkgutil` sed off-by-one 是真实运行时 bug（C3）；
4. **done-bar 缺证**：SONiC smoke 无证据且 build 证据早于 WT 重构（C4）。

补齐 I7/I8 的 13 个 Dockerfile、提交全部 submodule 补丁 + 指针、二选一解决 variant 命名、修复 C3、补 smoke 证据后，方可宣告完成。

> **后续更新（2026-07-05，见 §5）：** 上述四道硬伤（C1-C4）**已全部解决**——C1 submodule 补丁+指针已提交、C2 variant-naming 按设计稿提交、C3 pkgutil sed 修复、C4 build+KVM smoke 验证通过（两条 smoke"失败"经 systematic-debugging 调查均非 build 缺陷）。当前状态：**可交付**，仅剩 Important/Minor 级遗留项（I7-I15，均不影响 vs build）。



---

## 5. 后续进展

review 后已处理项（resolute 仓库 `resolute` 分支）：

| Issue | 状态 | 证据 |
|---|---|---|
| **C1** submodule 补丁未提交 + 父指针未 bump | ✅ 已修复 | 14 个 submodule 在各自 `resolute` 分支提交补丁 + 父 gitlink bump（`5e4f25d43`）；3 个损坏对象库（mgmt-framework/swss/sairedis）从 origin 重克隆修复；fresh clone 可复现 |
| **C2** variant-naming 报告与代码矛盾 | ✅ 已修复 | variant-naming 重构按设计稿提交（`a8fee77a4`，113 文件）；报告 §4.5 已更新反映 committed 状态；C4 验证 docker 镜像 `resolute.0-e938608` tag |
| **C3** pkgutil sed off-by-one | ✅ 已修复 | `sonic_debian_extension.j2` 改 `spec.submodule_search_locations[0]` → `spec.origin`（`e93860839`）；C4 build 后 fsroot-vs/squashfs 的 manager.py 确认含 `spec.origin` |
| **C4** done-bar smoke 无证据 | ✅ 通过 | 提交后状态 build 成功 + KVM boot + `show version`（build commit e938608）+ `docker ps`（容器健康）+ os-release=Ubuntu 26.04 ✅。smoke 中两条命令"失败"经调查均**非 build 缺陷**（见下）。详见 `done-bar-status.txt` |
| **boost 1.83 落地**（2026-07-06） | ✅ 已落地 | `sonic-slave-resolute/Dockerfile.j2` 18 行 `1.88-dev`→`1.83-dev`（resolute 工作树，未 commit）。理由：resolute 默认 boost 1.90（main，`boost_system` header-only 无 `libboost_system.so`），1.83/1.88 在 universe；选 **1.83** 对齐 trixie/bookworm 上游（trixie `libboost-dev` default 即 1.83，bookworm slave 亦 pin 1.83），且 1.83 保留 1.88 删的 `io_service`/`io_context::work`/`extension`/`std::hash<uuid>`。实验验证 slave 重建 + libswsscommon/sonic-eventd/ssg/linkmgrd 四包编译通过；submodule 已迁 io_context 代码 1.83 兼容保留不回退。交叉路径 unversioned `libboost-dev:$arch`（→1.90，M25）未一并修 |
| **I19** docker-base-resolute 缺失 iproute2（2026-07-15） | ✅ 已修复 | 根因：`docker-base-resolute/Dockerfile.j2` 从 trixie 复制，apt 列表无 `iproute2`（trixie 通过 `rules/iproute2.mk` 本地构建 deb 安装）。但 `rules/iproute2.mk` 用 `ifeq ($(BLDENV),trixie)` 守卫 `IPROUTE2` 变量——resolute 下为空，`docker-base-resolute.mk` 的 `$(IPROUTE2)` 依赖静默展开为空 → 所有 resolute 容器中 `ip` 命令缺失。修复：在 `docker-base-resolute/Dockerfile.j2` 的 apt 列表加回 `iproute2`；从 `rules/docker-base-resolute.mk` 移除 `$(IPROUTE2)` 依赖。放弃 EVPN Multihoming protocol 字段补丁（当前范围不需要）。同样的 BLDENV 守卫模式还影响 `sonic-redfish`（`BMCWEB`/`SONIC_DBUS_BRIDGE` 为空，bmcweb/sonic-dbus-bridge 静默缺失）和 `platform/vpp`（`VPPINFRA` 未构建）——已知，尚未修复 |

**C4 期间调查结论（systematic-debugging）：**
- **`failed to import plugin show.plugins.dhcp-relay/macsec`** — 非 squashfs 打包丢失（曾误判，因查了 `target/sonic-vs.bin__vs__rfs.squashfs` 这个非真实中间产物，只含 requests 依赖树）。查**真实运行 rootfs**（qcow2 `part3/image-resolute.0-e938608/fs.squashfs`）确认 `show/plugins/` 有完整 18 个 .py 含 `dhcp-relay.py`/`macsec.py`，sonic-utilities 完整。真因：Python 模块名不能含连字符——`util_base.py:23` `pkgutil.iter_modules` 返回磁盘名 `dhcp-relay`，`:31` `importlib.import_module` 必然 `ModuleNotFoundError`。**upstream master 未修**（同样用 `import_module`），commits `f36ac95a`/`8647356d` 降级为 `log_warning`（不致命）；tri/202605 同样失败 → 非 resolute 回归，非 C1-C3。
- **`show ip intf`/`show ip bgp sum` "No such command"** — 真因 `Db()` 连 configdb 失败（smoke 时 database 容器刚 Up + vs 无 minigraph → configdb 空/未就绪）→ click 不注册 `ip` 子命令树。运行时/时序问题，非 build defect。
- **`config load_minigraph -y`** — vs 镜像默认不预装 `minigraph.xml`（`OSError`），预期行为，需单独生成/导入。
- **3 个 submodule 对象库损坏**（C1 期间）：`--reference` 克隆的 alternates 丢失 + `git gc` 后 missing blobs/trees。重克隆修复。值得在 build-restore 文档记录。
- **调查教训**：查 vs rootfs 问题须查**真实运行 squashfs**（qcow2 `part3/image-*/fs.squashfs`，用 qemu-nbd + squashfs mount），不能用 build 中间产物 `target/*.squashfs`——后者可能是不完整过期快照。

**仍未处理（review Important/Minor，按优先级，均不影响 vs build）：**
- I7/I8：13 个平台 Dockerfile 缺 `--exclude=/etc/hosts` / `libxml2-16`（非 vs 平台）
- I9：bash plugin 未 port（32 hunks/8 文件/583 行）
- I10/I11：swss tests 移除 / linkmgrd test/ 未完成 io_context 迁移（`make test` 断，vs build 不编译 test/）
- I13/I14/I15：`Dh_Lib.pm` 非幂等 / 全局 `-std=gnu17` / libnl3 死代码与版本号建议（`+sonic1` 非 `~sonic1`）
