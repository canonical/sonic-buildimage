# Launchpad linux-sonic 内核迁移 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**目标：** 把 resolute 构建的内核从 trixie 采购的 `6.12.41+deb13-sonic` 换成 Launchpad PPA `linux-sonic 7.0.0-1002.2` 预构建二进制包（amd64/arm64）。

**架构：** 复用 `slave.mk` 的 `SONIC_ONLINE_DEBS` 机制，从 Launchpad `+files` URL `curl` 4 个 kernel deb 到 `$debs_path`，靠 `_DEPENDS` 拓扑决定 dpkg 安装顺序。不走 `sonic-linux-kernel/Makefile` 的 build-from-source。

**技术栈：** GNU make（SONiC build system）、dpkg/apt、bash（build_debian.sh）、Launchpad HTTP API/`+files`。

## Global Constraints（全计划适用）

- 版本串：trixie `6.12.41+deb13`（pkg `6.12.41-1`）→ Launchpad `7.0.0-1002`（pkg `7.0.0-1002.2`）。
- ABI 串新顺序：`7.0.0-1002-sonic-{arch}`（`-sonic-` 在 `-1002` 之后）。
- Launchpad PPA：`~canonical-kernel-team/+archive/ubuntu/bootstrap`，resolute series。
- 包名（amd64/arm64）：
  - image：`linux-image-7.0.0-1002-sonic_7.0.0-1002.2_{arch}.deb`（**无 `-unsigned`**）
  - modules：`linux-modules-7.0.0-1002-sonic_7.0.0-1002.2_{arch}.deb`（**新增，image 依赖它**）
  - headers(arch)：`linux-headers-7.0.0-1002-sonic_7.0.0-1002.2_{arch}.deb`
  - headers(common)：`linux-sonic-headers-7.0.0-1002_7.0.0-1002.2_all.deb`
  - **无 `linux-kbuild`**（Ubuntu headers 自带 build 脚本树）。
- 构建仓库：`~/sonic-buildimage-resolute`（分支 `202605_resolute`）。
- armhf 不在范围（PPA 无 armhf image/modules）。

---

## File Structure（改动映射）

| 文件 | 职责 | 改动类型 |
|---|---|---|
| `rules/linux-kernel.mk` | 版本/ABI/包名定义 + online deb 声明 | **重写** |
| `rules/linux-kernel.dep` | 依赖图（去掉 source-build 依赖） | **简化** |
| `rules/config.user` | 本地构建旋钮 | 改 L25-26 |
| `build_debian.sh` | 装镜像内核 + boot 路径 | 改 L32, L151-154 |
| `files/dsc/install_debian.j2` | DSC 引导（arm64） | 改 L251-252 |
| `platform/nokia-vs/.../nokia-7215-init.sh` | nokia-vs 模块加载 | 改 L183 |
| `platform/marvell-prestera/.../nokia-7215-init.sh` | 硬件平台模块加载 | 改 L14-15 |
| `src/sonic-linux-kernel/Makefile` | build-from-source（保留，不触发） | 不动 |

任务边界：每任务独立可测、含自己测试与 commit。Task 0 是静态验证（不碰构建）；Task 1-3 是 make 流水线核心；Task 4 是镜像安装；Task 5 是路径硬编码清理；Task 6 是端到端验证。

---

### Task 0: 静态包级验证（坐实设计前提）

**Files:**
- Read: `https://launchpad.net/~canonical-kernel-team/+archive/ubuntu/bootstrap/+files/<deb>`
- Test: 临时下载的 deb（用后删除）

**Interfaces:**
- Produces: 确认 4 个 `+files` URL 对 amd64/arm64 都 200；确认 image deb `Depends: linux-modules`；确认 headers deb 含 `scripts/` + `Kbuild`。这些坐实 Task 1 的包名与 `_DEPENDS` 方向。若与设计不符，**停下回报**，调整后再继续。

- [ ] **Step 1: 验证 4 个 `+files` URL 可下载（amd64 + arm64）**

```bash
cd /tmp
KERNEL_PPA_URL="https://launchpad.net/~canonical-kernel-team/+archive/ubuntu/bootstrap/+files"
for arch in amd64 arm64; do
  for pkg in linux-image-7.0.0-1002-sonic linux-modules-7.0.0-1002-sonic linux-headers-7.0.0-1002-sonic; do
    deb="${pkg}_7.0.0-1002.2_${arch}.deb"
    echo "== $deb =="
    curl -sIL "${KERNEL_PPA_URL}/${deb}" | grep -iE '^HTTP|content-length|location'
  done
done
# common headers (all)
deb="linux-sonic-headers-7.0.0-1002_7.0.0-1002.2_all.deb"
echo "== $deb =="; curl -sIL "${KERNEL_PPA_URL}/${deb}" | grep -iE '^HTTP|content-length|location'
```

Expected: 每个 URL 最终 HTTP 200 + 有 content-length（303 重定向到 launchpadlibrarian.net 后 200）。

- [ ] **Step 2: 确认 image deb 的 `Depends` 方向**

```bash
cd /tmp
KERNEL_PPA_URL="https://launchpad.net/~canonical-kernel-team/+archive/ubuntu/bootstrap/+files"
curl -sL "${KERNEL_PPA_URL}/linux-image-7.0.0-1002-sonic_7.0.0-1002.2_amd64.deb" -o /tmp/lp-image.deb
dpkg-deb -I /tmp/lp-image.deb | grep -iE 'Depends|linux-modules'
```

Expected: 输出含 `Depends: ... linux-modules-7.0.0-1002-sonic ...`。这坐实 Task 1 的 `$(LINUX_IMAGE)_DEPENDS += $(LINUX_MODULES)`（先装 modules 再装 image）。

- [ ] **Step 3: 确认 headers deb 含 kbuild 脚本树**

```bash
cd /tmp
KERNEL_PPA_URL="https://launchpad.net/~canonical-kernel-team/+archive/ubuntu/bootstrap/+files"
curl -sL "${KERNEL_PPA_URL}/linux-headers-7.0.0-1002-sonic_7.0.0-1002.2_amd64.deb" -o /tmp/lp-headers.deb
dpkg-deb -c /tmp/lp-headers.deb | grep -E 'scripts/Makefile|/Kbuild$|/scripts/' | head -10
```

Expected: 输出含 `.../linux-headers-7.0.0-1002-sonic/scripts/Makefile.*` 与 `.../Kbuild`。坐实 headers 自带 kbuild 脚本树、无 `linux-kbuild` gap。

- [ ] **Step 4: 清理临时文件**

```bash
rm -f /tmp/lp-image.deb /tmp/lp-headers.deb
```

- [ ] **Step 5: 记录结论**

无需 commit（Task 0 不改仓库）。把 Step 1-3 的实际输出记入实现日志/PR 描述。若任何一步与预期不符（如 image 不 Depends modules，或 headers 无 Kbuild），**停下来汇报**，不要进入 Task 1。

---

### Task 1: 重写 `rules/linux-kernel.mk` 为 online deb

**Files:**
- Modify: `rules/linux-kernel.mk`（整体重写，原 46 行）

**Interfaces:**
- Consumes: `slave.mk` 的 `SONIC_ONLINE_DEBS` 机制（`+files` URL + `_DERIVED_DEBS` 一次 curl + `_DEPENDS` 拓扑安装）。
- Produces: `KVERSION`、`KVERSION_SHORT`、`KERNEL_VERSION`、`KERNEL_ABISUFFIX`、`KERNEL_FEATURESET`、`KERNEL_PKGVERSION`（导出，供 60+ PLATFORM_MODULE .mk 拼 deb 名）；4 个 deb 变量 `LINUX_IMAGE`/`LINUX_MODULES`/`LINUX_HEADERS`/`LINUX_HEADERS_COMMON`（供 `build_debian.sh` 和 out-of-tree 模块 `.mk` 引用）。

- [ ] **Step 1: 备份并重写 `rules/linux-kernel.mk`**

用以下完整内容替换 `rules/linux-kernel.mk` 全文：

```makefile
# linux kernel package — Launchpad PPA prebuilt (linux-sonic 7.0.0-1002.2)
#
# Source: ~canonical-kernel-team/+archive/ubuntu/bootstrap (resolute series).
# Procured via SONIC_ONLINE_DEBS (curl +files URL), not built from source.
# Package style: Ubuntu (image depends on separate linux-modules; no linux-kbuild;
# build-script tree ships inside linux-headers).

KERNEL_VERSION = 7.0.0
KERNEL_ABISUFFIX = -1002
KERNEL_FEATURESET = sonic
KERNEL_PKGVERSION = 7.0.0-1002.2
# Note: KVERSION_SHORT is used by Arista
KVERSION_SHORT := $(KERNEL_VERSION)$(KERNEL_ABISUFFIX)-$(KERNEL_FEATURESET)
ifeq ($(CONFIGURED_ARCH), armhf)
# Override kernel version for ARMHF as it uses arm MP (multi-platform) for short version
KVERSION ?= $(KVERSION_SHORT)-armmp
else
KVERSION ?= $(KVERSION_SHORT)-$(CONFIGURED_ARCH)
endif

export KVERSION_SHORT KVERSION KERNEL_VERSION KERNEL_ABISUFFIX KERNEL_FEATURESET KERNEL_PKGVERSION

# Launchpad PPA binary pool (+files URL → 303 → launchpadlibrarian.net; curl -L follows).
KERNEL_PPA_URL = https://launchpad.net/~canonical-kernel-team/+archive/ubuntu/bootstrap/+files

# common headers (architecture-independent, all) — MAIN_TARGET
LINUX_HEADERS_COMMON = linux-sonic-headers-$(KERNEL_VERSION)$(KERNEL_ABISUFFIX)_$(KERNEL_PKGVERSION)_all.deb
$(LINUX_HEADERS_COMMON)_URL = $(KERNEL_PPA_URL)/$(LINUX_HEADERS_COMMON)

# arch-specific image + modules + headers (derived from common)
LINUX_IMAGE   = linux-image-$(KVERSION)_$(KERNEL_PKGVERSION)_$(CONFIGURED_ARCH).deb
LINUX_MODULES = linux-modules-$(KVERSION)_$(KERNEL_PKGVERSION)_$(CONFIGURED_ARCH).deb
LINUX_HEADERS = linux-headers-$(KVERSION)_$(KERNEL_PKGVERSION)_$(CONFIGURED_ARCH).deb

$(LINUX_HEADERS_COMMON)_DERIVED_DEBS = $(LINUX_IMAGE) $(LINUX_MODULES) $(LINUX_HEADERS)
$(LINUX_IMAGE)_URL   = $(KERNEL_PPA_URL)/$(LINUX_IMAGE)
$(LINUX_MODULES)_URL = $(KERNEL_PPA_URL)/$(LINUX_MODULES)
$(LINUX_HEADERS)_URL = $(KERNEL_PPA_URL)/$(LINUX_HEADERS)

# Install order via _DEPENDS topological -install prerequisites (slave.mk:1004):
#   linux-modules  before  linux-image  (image Depends: linux-modules)
#   common headers before  arch headers (arch headers Depends: common)
$(LINUX_IMAGE)_DEPENDS += $(LINUX_MODULES)
$(LINUX_HEADERS)_DEPENDS += $(LINUX_HEADERS_COMMON)

SONIC_ONLINE_DEBS += $(LINUX_HEADERS_COMMON) $(LINUX_IMAGE) $(LINUX_MODULES) $(LINUX_HEADERS)
```

- [ ] **Step 2: 验证 make 能解析（configure 干跑）**

```bash
cd ~/sonic-buildimage-resolute
make configure PLATFORM=vs CONFIGURED_ARCH=amd64 2>&1 | grep -iE 'KERNEL_PROCURE_METHOD|SONIC_ONLINE_DEBS|linux-sonic|error|warning' | head -20
```

Expected: 无 error；`KERNEL_PROCURE_METHOD` 行仍显示（slave.mk 默认值，无害，Task 2 会清理 config.user）；不再触发 sonic-linux-kernel build-from-source。

- [ ] **Step 3: 验证变量展开正确**

```bash
cd ~/sonic-buildimage-resolute
make -n -f slave.mk print-KVERSION 2>/dev/null || \
  make configure PLATFORM=vs CONFIGURED_ARCH=arm64 -j1 2>&1 | grep -iE 'KVERSION|linux-image-7.0.0|linux-modules-7.0.0|linux-sonic-headers' | head
```

Expected: 看到 `7.0.0-1002-sonic-amd64`/`-arm64`、`linux-image-7.0.0-1002-sonic_...`、`linux-modules-7.0.0-1002-sonic_...`、`linux-sonic-headers-7.0.0-1002_...` 等串。若 arch64 时仍显示 amd64，检查 `CONFIGURED_ARCH` 传递。

- [ ] **Step 4: 触发实际下载（amd64 vs）**

```bash
cd ~/sonic-buildimage-resolute
make target/debs/resolute/linux-sonic-headers-7.0.0-1002_7.0.0-1002.2_all.deb -j1 2>&1 | tail -20
ls -la target/debs/resolute/ | grep -E 'linux-(image|modules|headers|sonic-headers)-7.0.0'
```

Expected: `target/debs/resolute/` 下落 4 个 deb：`linux-sonic-headers-7.0.0-1002_*.deb`、`linux-image-7.0.0-1002-sonic_*.deb`、`linux-modules-7.0.0-1002-sonic_*.deb`、`linux-headers-7.0.0-1002-sonic_*.deb`。`_DERIVED_DEBS` 让一次下载把主+派生都拉下来。

- [ ] **Step 5: Commit**

```bash
cd ~/sonic-buildimage-resolute
git add rules/linux-kernel.mk
git commit -m "build: switch kernel to Launchpad linux-sonic via SONIC_ONLINE_DEBS

Rewrite rules/linux-kernel.mk: 6.12.41+deb13 (build-from-source) ->
linux-sonic 7.0.0-1002.2 from ~canonical-kernel-team/ubuntu/bootstrap
PPA via +files URL. Drop LINUX_KBUILD (Ubuntu headers carry the kbuild
script tree). Add LINUX_MODULES (image depends on it). common headers
renamed linux-headers-...-common-sonic -> linux-sonic-headers-...

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: 简化 `rules/linux-kernel.dep` + 清理 `config.user`

**Files:**
- Modify: `rules/linux-kernel.dep`
- Modify: `rules/config.user:25-26`

**Interfaces:**
- Consumes: Task 1 的新 `LINUX_HEADERS_COMMON` 变量（dep 文件引用它做 cache key）。
- Produces: dep 文件不再依赖 sonic-linux-kernel git 内容；config.user 不再设无效的 `KERNEL_PROCURE_METHOD`。

- [ ] **Step 1: 重写 `rules/linux-kernel.dep`**

用以下完整内容替换 `rules/linux-kernel.dep` 全文：

```makefile

DEP_FILES   := rules/linux-kernel.mk rules/linux-kernel.dep

# Kernel is now an ONLINE_DEB (curl +files URL), no source build ->
# no SMDEP_FILES (sonic-linux-kernel git content) and no build flags
# (KERNEL_PROCURE_METHOD/KERNEL_CACHE_PATH/SECURE_UPGRADE).
$(LINUX_HEADERS_COMMON)_DEP_FILES   := $(DEP_FILES)
$(LINUX_HEADERS_COMMON)_CACHE_OVERRIDE := $(SONIC_DPKG_CACHE_METHOD_OVERRIDE)
```

- [ ] **Step 2: 改 `rules/config.user` L25-26**

把 `rules/config.user` 的第 25-26 行：

```
# Kernel: download prebuilt instead of building from source (procure, ABI +deb13-sonic)
KERNEL_PROCURE_METHOD = download
```

替换为：

```
# Kernel: prebuilt linux-sonic 7.0.0-1002.2 from Launchpad PPA, fetched via
# SONIC_ONLINE_DEBS in rules/linux-kernel.mk (curl +files URL, no source build).
# KERNEL_PROCURE_METHOD is now inert (no consumer; kernel is an ONLINE_DEB).
```

- [ ] **Step 3: 验证 configure 仍通过**

```bash
cd ~/sonic-buildimage-resolute
make configure PLATFORM=vs CONFIGURED_ARCH=amd64 2>&1 | grep -iE 'error|warning.*kernel|linux-sonic' | head
```

Expected: 无 error。`KERNEL_PROCURE_METHOD` 仍可能打印默认值 `build`（slave.mk:353-354 兜底），无害——kernel 走 ONLINE_DEBS，不读这个变量。

- [ ] **Step 4: Commit**

```bash
cd ~/sonic-buildimage-resolute
git add rules/linux-kernel.dep rules/config.user
git commit -m "build: simplify kernel dep graph + drop inert KERNEL_PROCURE_METHOD

rules/linux-kernel.dep: remove SMDEP_FILES (no source build) and build
flags. config.user: KERNEL_PROCURE_METHOD had no consumer; comment it out
(kernel now an ONLINE_DEB from Launchpad).

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: 验证 out-of-tree 模块编译（headers + kbuild 树）

**Files:**
- Test: 任意 `DEPENDS LINUX_HEADERS` 的包（amd64 用 `rules/sonic-genl-packet-ko.mk`，arm64 用 nokia-vs `platform-nokia.mk`）

**Interfaces:**
- Consumes: Task 1-2 的 `LINUX_HEADERS`/`LINUX_HEADERS_COMMON` online deb（slave.mk dpkg -i 安装后 `/lib/modules/$(KVERSION)/build` 软链就位）。
- Produces: 实证 Launchpad headers 能让 out-of-tree 模块编出 `.ko`（坐实无 kbuild gap）。

- [ ] **Step 1: amd64 — 编 `sonic-genl-packet-ko` 模块**

```bash
cd ~/sonic-buildimage-resolute
make target/debs/resolute/genl-packet-module_1.0-1_amd64.deb -j1 2>&1 | tail -25
```

Expected: 构建成功，产出 `genl-packet-module_1.0-1_amd64.deb`。log 里应看到 dpkg 先装 `linux-headers-7.0.0-1002-sonic` + `linux-sonic-headers-7.0.0-1002`，再 `make -C /lib/modules/7.0.0-1002-sonic-amd64/build M=... modules`。

- [ ] **Step 2: 若失败，检查 `/lib/modules/.../build` 软链**

```bash
# 在构建环境(slave 容器)内或构建后检查:
ls -la /lib/modules/7.0.0-1002-sonic-amd64/build 2>/dev/null
ls /usr/src/linux-headers-7.0.0-1002-sonic/scripts/Makefile* 2>/dev/null
```

Expected: `build` 软链指向 `/usr/src/linux-headers-7.0.0-1002-sonic`；`scripts/Makefile.*` 存在。若软链缺失，检查 headers deb 是否 dpkg -i 成功（看 build log 的 dpkg 段）。

- [ ] **Step 3: arm64 — 编 nokia-vs 模块（若 arm64 可用）**

```bash
cd ~/sonic-buildimage-resolute
make configure PLATFORM=nokia-vs CONFIGURED_ARCH=arm64 2>&1 | tail -3
make target/debs/resolute/nokia-7215-platform_*_arm64.deb -j1 2>&1 | tail -25
```

Expected: 产出 nokia-7215 platform deb；log 里 nokia_7215 模块靠 `/lib/modules/7.0.0-1002-sonic-arm64/build` 编出 `.ko`。若 arm64 主机不可用，此步可跳过并在 PR 标注，amd64 Step 1-2 已坐实 headers 可用。

- [ ] **Step 4: Commit（若改了任何东西；通常不改，本任务为验证）**

无文件改动则不 commit，把结论记入 PR 描述。

---

### Task 4: `build_debian.sh` 装 modules + 版本串

**Files:**
- Modify: `build_debian.sh:32`
- Modify: `build_debian.sh:151-154`

**Interfaces:**
- Consumes: Task 1 的 `LINUX_KERNEL_VERSION` 语义（= `7.0.0-1002`，不含 `-sonic`，拼 `vmlinuz-${LINUX_KERNEL_VERSION}-sonic-${arch}`）。
- Produces: 镜像 rootfs 里装好 `vmlinuz` + `/lib/modules/.../kernel`（modules deb 同 image 一起装）。

- [ ] **Step 1: 改 `build_debian.sh:32`**

把第 32 行：
```
LINUX_KERNEL_VERSION=6.12.41+deb13
```
改为：
```
LINUX_KERNEL_VERSION=7.0.0-1002
```

- [ ] **Step 2: 改 `build_debian.sh:151-154`（cp + install 加 modules）**

把第 151-154 行：
```
sudo cp $debs_path/initramfs-tools-core_*.deb $debs_path/initramfs-tools_*.deb $debs_path/linux-image-${LINUX_KERNEL_VERSION}-*_${CONFIGURED_ARCH}.deb $FILESYSTEM_ROOT
basename_deb_packages=$(basename -a $debs_path/initramfs-tools-core_*.deb $debs_path/initramfs-tools_*.deb $debs_path/linux-image-${LINUX_KERNEL_VERSION}-*_${CONFIGURED_ARCH}.deb | sed 's,^,./,')
sudo LANG=C DEBIAN_FRONTEND=noninteractive chroot $FILESYSTEM_ROOT apt -y install $basename_deb_packages
( cd $FILESYSTEM_ROOT; sudo rm -f $basename_deb_packages )
```

替换为：
```
sudo cp $debs_path/initramfs-tools-core_*.deb $debs_path/initramfs-tools_*.deb $debs_path/linux-image-${LINUX_KERNEL_VERSION}-*_${CONFIGURED_ARCH}.deb $debs_path/linux-modules-${LINUX_KERNEL_VERSION}-*_${CONFIGURED_ARCH}.deb $FILESYSTEM_ROOT
basename_deb_packages=$(basename -a $debs_path/initramfs-tools-core_*.deb $debs_path/initramfs-tools_*.deb $debs_path/linux-image-${LINUX_KERNEL_VERSION}-*_${CONFIGURED_ARCH}.deb $debs_path/linux-modules-${LINUX_KERNEL_VERSION}-*_${CONFIGURED_ARCH}.deb | sed 's,^,./,')
sudo LANG=C DEBIAN_FRONTEND=noninteractive chroot $FILESYSTEM_ROOT apt -y install $basename_deb_packages
( cd $FILESYSTEM_ROOT; sudo rm -f $basename_deb_packages )
```

- [ ] **Step 3: 核对 boot 路径自动跟随（不改，仅确认）**

```bash
cd ~/sonic-buildimage-resolute
grep -n 'LINUX_KERNEL_VERSION' build_debian.sh
```

Expected: L773/L783/L784 等用 `${LINUX_KERNEL_VERSION}-sonic-${CONFIGURED_ARCH}` 模板，自动展开为 `7.0.0-1002-sonic-{arch}`。无需单独改。

- [ ] **Step 4: Commit**

```bash
cd ~/sonic-buildimage-resolute
git add build_debian.sh
git commit -m "build: install linux-modules deb alongside image + bump version to 7.0.0-1002

build_debian.sh: LINUX_KERNEL_VERSION 6.12.41+deb13 -> 7.0.0-1002; add
linux-modules-* to cp+install list (Ubuntu-style image deb needs the
separate modules deb or /lib/modules is empty and update-initramfs fails).

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: 清理硬编码版本串（j2 + 平台脚本）

**Files:**
- Modify: `files/dsc/install_debian.j2:251-252`
- Modify: `platform/nokia-vs/sonic-platform-nokia/7215-c1/scripts/nokia-7215-init.sh:183`
- Modify: `platform/marvell-prestera/sonic-platform-nokia/7215-a1/scripts/nokia-7215-init.sh:14-15`

**Interfaces:**
- Consumes: 无（独立文本替换）。
- Produces: 所有 `6.12.41+deb13` 串更新为 `7.0.0-1002`，boot/insmod 路径与新内核 ABI 一致。

- [ ] **Step 1: 改 `files/dsc/install_debian.j2:251-252`**

把第 251-252 行：
```
    kernel /$image_dir/boot/vmlinuz-6.12.41+deb13-sonic-arm64
    initrd /$image_dir/boot/initrd.img-6.12.41+deb13-sonic-arm64
```
改为：
```
    kernel /$image_dir/boot/vmlinuz-7.0.0-1002-sonic-arm64
    initrd /$image_dir/boot/initrd.img-7.0.0-1002-sonic-arm64
```

- [ ] **Step 2: 改 `platform/nokia-vs/.../nokia-7215-init.sh:183`**

把第 183 行：
```
KVER=6.12.41+deb13-sonic-arm64
```
改为：
```
KVER=7.0.0-1002-sonic-arm64
```

- [ ] **Step 3: 改 `platform/marvell-prestera/.../nokia-7215-init.sh:14-15`**

把第 14-15 行：
```
    sudo insmod /lib/modules/6.12.41+deb13-sonic-arm64/kernel/extra/nokia_7215_ixs_a1_cpld.ko
    sudo insmod /lib/modules/6.12.41+deb13-sonic-arm64/kernel/extra/cn9130_cpu_thermal_sensor.ko
```
改为：
```
    sudo insmod /lib/modules/7.0.0-1002-sonic-arm64/kernel/extra/nokia_7215_ixs_a1_cpld.ko
    sudo insmod /lib/modules/7.0.0-1002-sonic-arm64/kernel/extra/cn9130_cpu_thermal_sensor.ko
```

- [ ] **Step 4: 全局核对无残留 `6.12.41+deb13` 或 `deb13-sonic` 串**

```bash
cd ~/sonic-buildimage-resolute
grep -rn -E '6\.12\.41\+deb13|deb13-sonic' --include='*.sh' --include='*.mk' --include='*.j2' --include='*.yml' --include='*.cfg' --include='*.user' . 2>/dev/null | grep -viE 'node_modules' | head
```

Expected: 无输出（或仅 src/sonic-linux-kernel 内 build-from-source 残留，那不影响 ONLINE_DEB 路径）。若仍有 .sh/.j2 残留，补改。

- [ ] **Step 5: Commit**

```bash
cd ~/sonic-buildimage-resolute
git add files/dsc/install_debian.j2 platform/nokia-vs/sonic-platform-nokia/7215-c1/scripts/nokia-7215-init.sh platform/marvell-prestera/sonic-platform-nokia/7215-a1/scripts/nokia-7215-init.sh
git commit -m "build: update hardcoded kernel version strings to 7.0.0-1002-sonic

install_debian.j2 (DSC boot), nokia-vs + marvell-prestera nokia-7215-init.sh
(insmod paths): 6.12.41+deb13-sonic-arm64 -> 7.0.0-1002-sonic-arm64.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: 端到端构建 + 镜像/运行时验证

**Files:**
- Test: `target/sonic-vs.bin`（amd64）、arm64 vs 产物

**Interfaces:**
- Consumes: Task 1-5 全部改动。
- Produces: 一个可启动的 `sonic-vs.bin`，内核 `uname -r` = `7.0.0-1002-sonic-{arch}`。

- [ ] **Step 1: amd64 完整 vs 构建**

```bash
cd ~/sonic-buildimage-resolute
make configure PLATFORM=vs CONFIGURED_ARCH=amd64
make target/sonic-vs.bin -j$(nproc) 2>&1 | tee /tmp/vs-build.log | tail -30
```

Expected: 产出 `target/sonic-vs.bin`，构建无 fatal error。log 里 dpkg 段确认 `linux-modules` 先于 `linux-image` 安装、`linux-sonic-headers`(common) 先于 `linux-headers`(arch) 安装。

- [ ] **Step 2: 镜像级验证（挂 rootfs）**

```bash
cd ~/sonic-buildimage-resolute
# 找 squashfs（用 part3 的 image-*/fs.squashfs，不是中间 *.squashfs）
FS=$(find target -path '*image-*/fs.squashfs' 2>/dev/null | head -1)
echo "squashfs: $FS"
sudo mkdir -p /mnt/vsroot && sudo mount -t squashfs -o loop "$FS" /mnt/vsroot
ls /mnt/vsroot/boot/vmlinuz-7.0.0-1002-sonic-amd64
ls /mnt/vsroot/lib/modules/7.0.0-1002-sonic-amd64/kernel/ | head
ls /mnt/vsroot/boot/initrd.img-7.0.0-1002-sonic-amd64
cat /mnt/vsroot/etc/os-release | grep -i pretty
sudo umount /mnt/vsroot
```

Expected: vmlinuz 存在；`/lib/modules/.../kernel/` 有模块（坐实 modules deb 装入）；initrd 存在（`update-initramfs` 成功）；`os-release` 仍 resolute。

- [ ] **Step 3: 运行时验证（启动 vs）**

```bash
cd ~/sonic-buildimage-resolute
# 用 sonic-vs.bin 启动一个 vs 实例（QEMU/KVM），登录后:
#   uname -r            -> 7.0.0-1002-sonic-amd64
#   modprobe <某模块>    -> 无 error
#   show platform ...    -> 复用 resolute vs build success 冒烟
```

Expected: `uname -r` = `7.0.0-1002-sonic-amd64`；关键 `modprobe` 不报错；vs 基础冒烟通过（参考 memory/resolute-vs-build-success 验证项）。

- [ ] **Step 4: arm64 vs 构建（若 arm64 可用）**

```bash
cd ~/sonic-buildimage-resolute
make configure PLATFORM=vs CONFIGURED_ARCH=arm64
make target/sonic-vs.bin -j$(nproc) 2>&1 | tee /tmp/vs-arm64-build.log | tail -30
```

Expected: arm64 产物产出，同样镜像级验证（vmlinuz/modules/initrd/os-release）。若 arm64 主机不可用，跳过并在 PR 标注。

- [ ] **Step 5: 记录验证结论 + 回滚预案**

无需 commit（验证任务）。把 Step 1-4 实际输出记入 PR 描述。

**回滚预案（若端到端失败）：**
```bash
cd ~/sonic-buildimage-resolute
git revert <Task1 commit> <Task2 commit> <Task4 commit> <Task5 commit>
# 或整体: git reset --hard <pre-Task1-SHA>
# 旧 trixie 内核 deb 仍在 dpkg cache (/var/cache/sonic/artifacts)，回滚后构建继续可用。
```

---

## Self-Review（计划自检，已执行）

1. **Spec 覆盖：** spec §1 包名映射 → Task 1；§2 download 实现 + 8 处文件 → Task 1-5；§3 验证四层 → Task 0(包级)+Task 3(构建级 headers)+Task 6(镜像级+运行时)。armhf 范围边界 → Global Constraints + §7。全覆盖。
2. **Placeholder 扫描：** 无 TBD/TODO；每步含实际命令/代码/预期输出。
3. **类型/命名一致：** `LINUX_IMAGE`/`LINUX_MODULES`/`LINUX_HEADERS`/`LINUX_HEADERS_COMMON`、`KVERSION`、`KERNEL_PKGVERSION` 在 Task 1 定义、Task 3-4 引用，名称一致。`KERNEL_PPA_URL`、`+files` 路径全计划一致。版本串 `7.0.0-1002`/`7.0.0-1002.2` 全计划一致。

## 执行交接

Plan complete and saved to `docs/superpowers/plans/2026-07-10-sonic-202605-resolute-launchpad-kernel-migration-plan-zh.md` + `-en.md`。两种执行方式：

1. **Subagent-Driven（推荐）** — 每任务派新 subagent，任务间 review，快速迭代。
2. **Inline Execution** — 本会话用 executing-plans 批量执行，带 checkpoint。

哪种？
