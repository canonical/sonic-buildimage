# SONiC 202605 Resolute — 内核迁移至 Launchpad linux-sonic 二进制包（amd64/arm64）

- **日期：** 2026-07-10
- **范围：** 仅 `amd64` + `arm64`。`armhf` 不在范围内（见 §7）。
- **目标仓库：** `~/sonic-buildimage-resolute`（分支 `202605_resolute`）——构建发生处。
- **文档分支：** `~/sonic-buildimage` 分支 `202605_resolute_doc`。
- **数据源：** Launchpad PPA `~canonical-kernel-team/+archive/ubuntu/bootstrap`，resolute series，`linux-sonic 7.0.0-1002.2`。

## 1. 目标

把 resolute 构建中由 trixie 采购的内核（`6.12.41+deb13-sonic`）换成 Launchpad PPA 预构建的 `linux-sonic 7.0.0-1002.2` 二进制包，覆盖 `amd64` 与 `arm64`。机制为 SONiC make 流水线下载 `.deb`（`SONIC_ONLINE_DEBS`），不走源码构建。

## 2. 背景（已核实）

### 2.1 当前 trixie 采购现状

- 版本定义在 `rules/linux-kernel.mk:3-6`：`KERNEL_VERSION=6.12.41`、`KERNEL_ABISUFFIX=+deb13`、`KERNEL_SUBVERSION=1`、`KERNEL_FEATURESET=sonic` → ABI `6.12.41+deb13-sonic-{arch}`，包版本 `6.12.41-1`。
- `rules/config.user:26` 设 `KERNEL_PROCURE_METHOD = download`，但全代码库无任何代码消费该变量（仅 `slave.mk:353` 设默认值）。`src/sonic-linux-kernel/Makefile` 只有 build-from-source 路径（`wget` DSC + `dpkg-buildpackage`）。**`download` 是空壳**；当前内核 `.deb` 实际来自 dpkg cache（`/var/cache/sonic/artifacts`）。
- 打包风格：Debian 风格——`linux-image-...-unsigned`（amd64）、`linux-kbuild-6.12.41+deb13`、`linux-headers-...-common-sonic`（all, MAIN_TARGET）、`linux-headers-...-sonic-{arch}`。模块打进 image 包，无独立 `linux-modules`。

### 2.2 Launchpad linux-sonic 7.0.0-1002.2

- 版本 `7.0.0-1002.2`，ABI `7.0.0-1002`，flavor `sonic`，series `resolute`。
- 打包风格：Ubuntu 风格——`linux-image-7.0.0-1002-sonic`（**无 `-unsigned`**）、`linux-modules-7.0.0-1002-sonic`（**独立包，image 依赖它**）、`linux-headers-7.0.0-1002-sonic`（arch）、`linux-sonic-headers-7.0.0-1002`（common，all）、`linux-buildinfo`/`linux-tools`/`linux-cloud-tools`（可选）。**无 `linux-kbuild`**。
- amd64 与 arm64 对 image/modules/headers/headers-common/buildinfo/tools 全覆盖；cloud-tools 仅 amd64；armhf 仅有 headers，无 image/modules。

## 3. SONiC 对内核的消费全景（设计依据）

| 消费方 | 机制 | 文件 |
|---|---|---|
| 装进镜像（运行期） | `build_debian.sh` 从 `$debs_path` cp+install `linux-image-*` deb | `build_debian.sh:151-153` |
| out-of-tree 模块编译（构建期） | 60+ 个 `platform-modules-*.mk` 的 `_DEPENDS += $(LINUX_HEADERS) $(LINUX_HEADERS_COMMON)`，靠 `/lib/modules/$(KVERSION)/build` 软链找 build 树 | `platform/broadcom/sai-modules.mk`、`platform/mellanox/mft.mk`、`platform/nokia-vs/platform-nokia.mk:11` 等 |
| boot 路径（secure boot / initrd / FIT / DSC 引导） | 硬编码 `vmlinuz-${LINUX_KERNEL_VERSION}-sonic-${arch}` 等 | `build_debian.sh:773,783-784`、`files/dsc/install_debian.j2:251-252` |

**vs 平台内核依赖判定：**
- `PLATFORM=vs`（`platform/vs/rules.mk`）不引入任何 `DEPENDS LINUX_HEADERS` 的包 → 纯 vs 零内核编译依赖。
- `nokia-vs`（`platform/nokia-vs/rules.mk` → `platform-nokia.mk:11`）编译 `nokia_7215` 模块，依赖 headers。
- 所有真实硬件平台（broadcom/mellanox/barefoot/centec/…）均依赖 headers。

**`linux-kbuild` 缺失非 gap：** Ubuntu 内核的 build 脚本树（`scripts/`、`Kbuild`）含在 `linux-headers` 包内（`/usr/src/linux-headers-*/scripts/`），`/lib/modules/$(KVERSION)/build` 软链由 headers 包 postinst 创建并指向它。trixie 的 `linux-kbuild` 是 Debian 风格额外拆分，Ubuntu 不需要。换包后 `LINUX_KBUILD` 变量应整个移除。

## 4. §1 包名映射（trixie → Launchpad，amd64/arm64）

| 角色 | trixie（现状） | Launchpad linux-sonic 7.0.0-1002.2 | 处置 |
|---|---|---|---|
| 镜像 image+vmlinuz | `linux-image-6.12.41+deb13-sonic-unsigned_6.12.41-1_{arch}.deb` | `linux-image-7.0.0-1002-sonic_7.0.0-1002.2_{arch}.deb` | 重命名：去 `-unsigned`，版本串改 |
| 内核模块 `/lib/modules` | *(打进 image)* | `linux-modules-7.0.0-1002-sonic_7.0.0-1002.2_{arch}.deb` | **新增**：image rdepends 它，必须同装 |
| 架构 headers | `linux-headers-6.12.41+deb13-sonic_6.12.41-1_{arch}.deb` | `linux-headers-7.0.0-1002-sonic_7.0.0-1002.2_{arch}.deb` | 重命名 |
| 通用 headers（all, MAIN_TARGET） | `linux-headers-6.12.41+deb13-common-sonic_6.12.41-1_all.deb` | `linux-sonic-headers-7.0.0-1002_7.0.0-1002.2_all.deb` | 重命名：common 包名整体改变 |
| kbuild | `linux-kbuild-6.12.41+deb13_6.12.41-1_{arch}.deb` | 无 | **移除** `LINUX_KBUILD` 变量及 DEPENDS |
| buildinfo / tools / cloud-tools | *(无)* | 存在 | **不引入**（SONiC 不消费） |

**版本/ABI 串：** `6.12.41+deb13`（pkg `6.12.41-1`）→ `7.0.0-1002`（pkg `7.0.0-1002.2`）。注意 Launchpad 的 ABI 里 `-sonic-` 在 `-1002` 之后，顺序与 trixie 不同——所有 `vmlinuz-${LINUX_KERNEL_VERSION}-sonic-${arch}` 模板串要核对新顺序。

## 5. §2 download 实现 + 改动文件清单

### 5.1 核心决策

复用 `slave.mk` 的 `SONIC_ONLINE_DEBS` 下载基础设施，把 4 个 kernel deb 定义为 online deb（`curl` `+files` URL），不走 `sonic-linux-kernel/Makefile` 的 build-from-source。自带缓存（`$debs_path` 命中即跳过）、SBOM（ONLINE_DEB fragment）、`rwcache`、`_DEPENDS` 拓扑安装——全是现成机制。

### 5.2 已验证支撑

- **URL：** `https://launchpad.net/~canonical-kernel-team/+archive/ubuntu/bootstrap/+files/<deb>` → HTTP 303 → `launchpadlibrarian.net`。`slave.mk` ONLINE_DEB 用 `curl -L -f`（自动跟随 303）。`ppa.launchpadcontent.net` pool 路径 403（该 PPA 禁用），只能用 `+files` URL。
- **安装顺序：** `slave.mk:1004` 的 `-install` target 把 `$($*_DEPENDS)` 作为 prerequisite，ONLINE_DEB 同样适用（`slave.mk:767`）。`modules→image`、`common→headers` 顺序靠现有机制保证。
- **common headers** 是 `_all.deb`，amd64/arm64 共用。

### 5.3 改动文件（8 处）

1. **`rules/linux-kernel.mk`**（核心，重写）
   - 版本：`KERNEL_VERSION=7.0.0`、`KERNEL_ABISUFFIX=-1002`、`KERNEL_FEATURESET=sonic`，新增 `KERNEL_PKGVERSION=7.0.0-1002.2`。
   - `KVERSION_SHORT = 7.0.0-1002-sonic`、`KVERSION = 7.0.0-1002-sonic-{arch}`（公式沿用；KVERSION 供 60+ 个 PLATFORM_MODULE .mk 拼 deb 名，必须保留）。
   - 4 个 deb 改 Launchpad 命名（见 §4），删 `LINUX_KBUILD` 及 `add_derived_package` 链。
   - 每个 deb 加 `_URL = $(KERNEL_PPA_URL)/<debname>`，`KERNEL_PPA_URL=https://launchpad.net/~canonical-kernel-team/+archive/ubuntu/bootstrap/+files`。
   - `_DEPENDS`：`$(LINUX_IMAGE)_DEPENDS += $(LINUX_MODULES)`、`$(LINUX_HEADERS)_DEPENDS += $(LINUX_HEADERS_COMMON)`。
   - `SONIC_ONLINE_DEBS += $(LINUX_HEADERS_COMMON) $(LINUX_IMAGE) $(LINUX_MODULES) $(LINUX_HEADERS)`（替换原 `SONIC_MAKE_DEBS`）。

2. **`rules/linux-kernel.dep`**（简化）：去掉 `SMDEP_FILES`（不再 build from source）、去掉 `DEP_FLAGS` 里的 `KERNEL_PROCURE_METHOD/KERNEL_CACHE_PATH/SECURE_UPGRADE`；DEP_FILES 只留 `rules/linux-kernel.mk rules/linux-kernel.dep`。

3. **`build_debian.sh`**
   - L32：`LINUX_KERNEL_VERSION=6.12.41+deb13` → `7.0.0-1002`。
   - L151-152：cp+install 列表加 `linux-modules-7.0.0-1002-sonic-*_${arch}.deb`（否则 `/lib/modules` 空，`update-initramfs`/`modprobe` 失败）。
   - L773/783-784：secure boot / FIT 路径用 `${LINUX_KERNEL_VERSION}-sonic-${arch}`，自动跟随，无需单独改。

4. **`files/dsc/install_debian.j2:251-252`**（DSC 引导，arm64）：`vmlinuz/initrd.img-6.12.41+deb13-sonic-arm64` → `7.0.0-1002-sonic-arm64`。

5. **`platform/nokia-vs/sonic-platform-nokia/7215-c1/scripts/nokia-7215-init.sh:183`**：`KVER=6.12.41+deb13-sonic-arm64` → `7.0.0-1002-sonic-arm64`。

6. **`platform/marvell-prestera/sonic-platform-nokia/7215-a1/scripts/nokia-7215-init.sh:14-15`**：`/lib/modules/6.12.41+deb13-sonic-arm64/` → `7.0.0-1002-sonic-arm64`。

7. **`rules/config.user:25-26`**：`KERNEL_PROCURE_METHOD = download` 移除/改注释（不再走 Makefile，变量已失效；加注释说明 kernel 走 `SONIC_ONLINE_DEBS` 从 Launchpad）。

8. **`src/sonic-linux-kernel/Makefile`**：不动（build-from-source 路径保留，但 kernel 移出 `SONIC_MAKE_DEBS` 后不再被触发；submodule 可选保留）。

## 6. §3 验证方案

### A. 包级（实施前，静态）
- 4 个 deb 的 `+files` URL 全部 `curl -I -L` 返回 200（确认 amd64/arm64 各包在）。
- 下载 `linux-image-7.0.0-1002-sonic` deb → `dpkg-deb -I` 查 `Depends: linux-modules-7.0.0-1002-sonic`，坐实 `_DEPENDS` 方向；反向则调整 rules。
- 下载 `linux-headers-7.0.0-1002-sonic` deb → 确认含 `/usr/src/linux-headers-7.0.0-1002-sonic/scripts/` 与 `Kbuild`，坐实 headers 自带 kbuild 脚本树、无 `linux-kbuild` gap。

### B. 构建级（make 时）
- `make configure PLATFORM=vs CONFIGURED_ARCH=amd64`：info 打印确认 `SONIC_ONLINE_DEBS` 含 4 个 kernel deb、不再触发 build-from-source。
- 触发下载：`make -n target/debs/resolute/linux-image-7.0.0-1002-sonic_*.deb` 干跑确认 recipe 为 curl；实跑确认 `$debs_path` 落 4 个 deb。
- dpkg 安装：build log 确认 `linux-modules` 先于 `linux-image`、`linux-sonic-headers`（common）先于 `linux-headers`（arch）安装。
- nokia-vs 模块（arm64）：确认能靠 `/lib/modules/7.0.0-1002-sonic-arm64/build` 编出 `nokia_7215_*.ko`。

### C. 镜像级（build_debian.sh 后）
- `target/sonic-vs.bin`（amd64）/ arm64 产物存在。
- 按 qcow2 part3 `image-*/fs.squashfs`（非中间 `*.squashfs`）挂载 rootfs，检查：
  - `/boot/vmlinuz-7.0.0-1002-sonic-{arch}` 存在；
  - `/lib/modules/7.0.0-1002-sonic-{arch}/kernel/` 有模块（modules deb 装入）；
  - `/boot/initrd.img-7.0.0-1002-sonic-{arch}` 存在（`update-initramfs` 成功）；
  - `os-release` 仍 resolute。

### D. 运行时（启动 vs）
- `sonic-vs.bin` 启动到 login；`uname -r` = `7.0.0-1002-sonic-{arch}`；`modprobe` 关键模块不报错；复用 resolute vs build success 基础冒烟。

### 验证矩阵
| 层 | amd64 | arm64 |
|---|---|---|
| A 包级 | 同套 | 同套（arch 包各自） |
| B 构建 | vs 主构建 | nokia-vs（含 out-of-tree 模块，最能验证 headers） |
| C 镜像 | sonic-vs.bin | arm64 vs 产物 |
| D 运行 | 启动 + uname | 启动 + uname |

## 7. 范围边界（能换 / 不能换）

**能换：** amd64、arm64 的 `image + modules + headers(arch) + headers-common`，版本串 `7.0.0-1002-sonic-{arch}`。

**不能换（gap）：**
- **armhf：** Launchpad `linux-sonic` 无 armhf 的 image/modules（仅有 headers）。armhf 硬件平台（centec/marvell-prestera 等）用 `linux-image-...-sonic-armmp`，换不动。本次明确不覆盖。
- cloud-tools 仅 amd64（vs 不用，非 gap）。

## 8. 待实现时验证项（不阻塞设计）

1. `linux-image-7.0.0-1002-sonic` deb 的 `debian/control` `Depends` 是否为 `linux-modules-7.0.0-1002-sonic`（坐实 `_DEPENDS` 方向）。
2. `linux-headers-7.0.0-1002-sonic` deb 是否含 `scripts/` + `Kbuild`（kbuild 脚本树）。
3. nokia-vs 模块编译实证（arm64 headers 可用性）。

## 9. 后续

设计批准后，进入 `writing-plans` 产出实现计划（分步骤、可验证、含回滚）。
