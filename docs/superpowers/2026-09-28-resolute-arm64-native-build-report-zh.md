# 202605_resolute 上的 arm64 vs：原生构建、ONIE 装机与启动报告

- 日期：2026-09-28（在 `vera` 上构建并直接加载内核启动），2026-09-29（在 `podler` 上重建、经 ONIE 装机、测试 kexec 和 kdump）
- 基线：`canonical/202605_resolute` 的 `d2f9ae8502`，到 2026-09-29 仍是该分支的最新提交
- 改动：本地分支 `feat/resolute-arm64-vs`，9 个 GPG 签名提交（15 个文件，+56/−6），未推送；工作树 `/home/sheldon-qi/sbi-arm64-native`
- 机器：两台都是 TOR3 实验室经 testflinger 预留的机器，预留均已结束。
  - `vera`（10.241.5.36）：Cavium ThunderX-88XX，48 核、每核一线程，62 GB 内存，219 GB SSD，Ubuntu 26.04.1 arm64，内核 7.0.0-34-generic，docker-ce 29.8.1。
  - `podler`（10.241.24.14）：单路 AmpereOne 参考平台，192 个 Ampere-1a 核，251 GB 内存，879 GB NVMe，Ubuntu 26.04 arm64，docker-ce 29.8.1，QEMU 10.2.1。
- 前序：[交叉构建探路报告](2026-09-23-resolute-arm64-cross-probe-report-zh.md)
- 本文为中文版；英文版为唯一事实来源（`-en.md`）

## 0. 结论

**原生 arm64 构建 `target/sonic-vs.bin` 是可行的，镜像能经 SONiC 自己的 arm64 ONIE 装机并正常运行。**从基线出发需要 9 个小提交，全部在超仓里（§1）：

- 在 podler 上从全新克隆开始构建约一小时：slave 镜像 25 分钟，包、容器和安装包 33 分钟（§2）。
- 用 SONiC 发布的 arm64 ONIE 恢复镜像，在 KVM 下 `onie-nos-install` 能装上它，ONIE 自带的 GRUB 2.04 能启动它。`show version` 显示 `Platform: arm64-qemu_armv8a-r0`、`HwSKU: Force10-S6000`（§4）。
- 14 个容器起来了。APPL_DB 里有 32 个端口，ASIC_DB 里有 33 个 PORT 和 69 个 ROUTE_ENTRY 对象，BGP 在运行，配置了 32 个 peer。
- 按 fast-reboot 和 warm-reboot 的方式加载，`kexec` 能启动镜像自带的内核；kdump 能抓到 vmcore（§4.6）。
- 失败的单元只有 `watchdog-control` 和 `system-health`。两者都因缺一个只有 sonic-mgmt 测试床才会写的文件而失败，相关代码在 x86 vs 上也一样（§6）。

除了 `sonic-platform-vs` 的包名改成 `_all.deb`，没有一个提交改变 amd64 构建的产物。

还剩下的：

- 子模块里有三处检查只认 x86 的平台名来判断 vs，因此认不出 arm64 vs（§7.1）。其中一处每次开机都能看到：snmp 记一条 ERR，机箱序列号缺失。每处都要在子模块里提交，所以这里没改。
- arm64 镜像里去掉了两个只有 x86 版的组件：pmon 的 SSD 厂商工具和 docker-dash-engine。两者都不损失任何功能（§5）。
- 在 arm64 宿主机的 KVM 下跑 UEFI，测试机需要比 resolute 自带更新的 edk2（§4.1）。这只关乎测试机，镜像本身不带 edk2。

2026-09-23 的交叉探路预言了构建结果。交叉路径用了八处破例，仍然卡在容器层，只建出了 `docker-base` 和 `docker-dash-engine`。原生构建除了本文修掉的问题之外，没有碰到任何代码层面的失败。

## 1. 改动

九处都在 `feat/resolute-arm64-vs` 上，每处一个提交。

| 提交 | 改动 | 消除的失败 |
|---|---|---|
| `7c469ec934` | `sonic-slave-resolute/Dockerfile.j2`：`gcc-multilib` 只在 amd64 上装 | resolute 没有发布 arm64 的 `gcc-multilib`，slave 镜像停在这一行 |
| `f989cb441d` | `platform/vs/rules.mk`：`override TARGET_BOOTLOADER = grub` | `Makefile.work` 把非 amd64 默认设为 uboot，`build_debian.sh` 随后要找不存在的 `platform/vs/sonic_fit.its` |
| `96f264e2b9` | `sonic-platform-vs`：`Architecture: all`，产物名改为 `_all.deb` | 纯 Python 包却声明为 amd64，`dpkg-buildpackage` 什么都产不出来 |
| `13d5623f1c` | `docker-dash-engine`：仅限 amd64（make 规则加 unit 文件拷贝） | 它的基础镜像 `p4lang/behavioral-model:latest` 只有 amd64 版（§5.2） |
| `2c04ece9e9` | pmon：`ssd_tools` 及其宿主机包装脚本只在 amd64 上带 | 预编译的厂商二进制是 x86-64 和 i386 的（§5.1） |
| `8858c03ecd` | `build_debian.sh`：非 amd64 上安装 `initramfs-tools busybox-initramfs` | arm64 的 initrd 里没有 busybox，挂不上根文件系统（§3） |
| `6de838da5e` | `build_debian.sh`：arm64 上的 vs 把内核存成 gzip 压缩的原始 Image | ONIE 的 GRUB 2.04 拒绝 EFI zboot 内核（§4.2） |
| `624636d7d3` | arm64 vs 构建把 `arm64-qemu_armv8a-r0` 当作 vs 平台 | 这是 ONIE 报告的平台名；不认它，镜像就没有 HwSKU，swss/syncd 会停（§4.3） |
| `d3b6c4c08b` | `platform/vs/platform_arm64.conf`：GRUB 和内核控制台改用 PL011 串口 | 安装器默认用 x86 的 8250 串口（§4.4） |

合计改动 15 个文件，+56/−6 行，没有子模块提交，也没有升级 gitlink。新增文件只有 `platform_arm64.conf`（6 行）。改动最大的两块是 `build_debian.sh`（+17：initramfs 3 行，内核转换 14 行）和平台别名（6 个文件，+18/−3）。除 `sonic-platform-vs` 的包名外，每处改动都有 `CONFIGURED_ARCH` 或 `CONFIGURED_PLATFORM` 条件保护；树里也没有其他地方引用旧包名。

前五处改动来自一次静态扫描。扫描在 2026-09-28 06:08–07:34 UTC 运行，正值 slave 镜像构建期间、包构建开始之前。前四处作为已知项（来自交叉探路 §6）交给扫描，由它确认，第五处是它新找到的。扫描对 vs arm64 的构建闭包跑了 8 个维度的 finder，每条发现由两个视角不同的对抗式复核 agent 核对（代码是否真会走到、失败是否真会发生）。56 条发现里 29 条确认、8 条有争议、9 条被驳回；另外 10 条的复核调用失败，未能核实。之后的真实构建里，没有出现扫描清单之外的代码层面失败，其余失败都出在宿主机和网络上：`j2` 不在 PATH 上，以及一次 `TRUSTED_GPG_URLS` 的 wget 瞬时失败。

最后三个提交按四个视角复核过：amd64 回归、arm64 运行时、安装与升级路径、构建稳健性。每条发现都由另一个 agent 核对。§4.2–§4.4 的设计取舍吸收了这些发现，复核留下的缺口列在 §7。

## 2. 构建

vera，2026-09-28：

| 阶段 | 时间（UTC） | 耗时 | 结果 |
|---|---|---|---|
| 宿主机准备与克隆 | 06:04 之前 | 约 20 分钟 | 克隆 21 秒；60 个子模块 6 分钟 |
| slave 镜像（原生，70 步） | 06:05–约 08:20 | 约 2 小时 15 分（其中 Docker 构建步骤约 2 小时 11 分） | 修掉 `gcc-multilib` 后无失败 |
| 包、容器、镜像（`-k`） | 08:25:59–11:41:46 | 3 小时 16 分 | 216 个目标，0 失败（更早一次尝试因 `TRUSTED_GPG_URLS` 的 wget 瞬时失败而立即退出） |
| initramfs 修复后的确认重建 | 14:05:22–14:52:31 | 47 分钟 | 只重建 rootfs 和安装包 |

vera 上 slave 镜像的耗时主要花在 ThunderX 核心跑得慢的串行任务上：一步装 1800 个包的 dpkg 约 40 分钟（含 texlive 生成格式文件）；`grpcio 1.71.0` 源码编译 12 分钟（两个架构都没有 cp314 的 wheel）；`cargo-tarpaulin` 最后一个单线程 `rustc` 约 11 分钟（整步 13 分钟）；导出并解包 15.2 GB 的镜像约 20 分钟。

podler，2026-09-29，从全新克隆开始，缓存为空：

| 阶段 | 时间（UTC） | 耗时 | 结果 |
|---|---|---|---|
| 宿主机准备、克隆、子模块 | 03:58:31–03:59:36 | 约 1 分钟 | 需要让 download.docker.com 绕过代理（§7.3） |
| slave 镜像 | 03:59:36–04:24:42 | 25 分钟 | 无失败 |
| 包、容器、镜像（`-k`） | 04:24:42–04:57:43 | 33 分钟 | 216 个目标，0 失败 |
| 修改提交后的重建 | 例如 07:55:45–08:07:31 | 12–14 分钟 | 只重建有改动的包和安装包 |

整个构建 podler 比 vera 快约五倍。

vera 上的产出（在 `target/` 里计数，记录于 `verify-v3.txt`）：154 个 deb（145 个 arm64、9 个 all）、32 个 wheel、29 个容器镜像（26 个装进镜像，另 3 个是中间层），确认重建出的 `sonic-vs.bin` 为 1,424,703,471 字节（1.42 GB）。podler 上建出的镜像也是 1.43 GB。对 vera 镜像的检查，全部记录在 `verify-v3.txt`：

- 载荷 sha1 自检通过。
- rootfs 里的 `bash`、`dockerd`、`python3.14` 都是 aarch64 ELF（e_machine `b700`）。
- os-release 为 Ubuntu 26.04.1 LTS。
- `dockerfs.tar.gz` 里 26 个容器镜像的镜像配置全部是 `architecture=arm64`。（交叉构建会把最后的 `FROM scratch` 阶段打上构建机的架构，原生构建不会。）

## 3. initramfs 的发现

**现象。**第一版镜像启动进入 initramfs 后停住，先报 `squashfs: Unknown parameter 'loop'`，再报 `No init found`。

**原因。**arm64 的 initrd 里没有 busybox。SONiC 从 Debian 源码自己构建 `initramfs-tools` 0.142。它在 Ubuntu slave 上构建时，`initramfs-tools-core` 对 `busybox-initramfs` 只是 Recommends，而 `files/apt/apt.conf.d/81norecommends` 关掉了 Recommends。Debian 的 `busybox` 包自带 initramfs hook；Ubuntu 的不带，因为 Ubuntu 把这个 hook 挪进了 `busybox-initramfs`。没有 busybox，initrd 就退回到 klibc 的 `mount`，它不支持 `loop` 选项，于是把它当作 squashfs 的挂载参数交给内核。缺少 `awk`、`cut`、`gzip` 会让后面的 SONiC 初始化脚本出错，但真正让启动停下的是这次 loop 挂载。

**为什么 amd64 从没碰到。**amd64 独有的固件安装那一步会装 `linux-firmware-misc` 和 `linux-firmware-intel-misc`，两者都声明了 `Breaks: initramfs-tools (<< 0.142ubuntu8~)`，于是 apt 把 SONiC 的 0.142 换成 Ubuntu 的 0.151ubuntu1，而后者的 `initramfs-tools-core` 硬依赖 `busybox-initramfs`。更早的构建通过 `linux-firmware` 元包也发生了同样的替换，因为每个拆分包都带这条 Breaks。

**这对 amd64 意味着什么。**

- 每个 amd64 resolute 镜像实际运行的都是 Ubuntu 未改动的 initramfs-tools：装进去的文件和 initrd 的 `/init` 与 Ubuntu 0.151ubuntu1 逐字节一致。
- 启动 vs 用的 `loop=`/`loopfstype=` 根文件系统挂载，来自 Ubuntu 在 0.151ubuntu1 里自己的改动（`/init` 解析参数，`scripts/local` 执行 `mount -o loop`），不是来自 SONiC 的补丁。
- 所以 `src/initramfs-tools` 及其两个补丁在 amd64 上是死代码。第一个补丁（loop 文件系统）与 Ubuntu 的实现重复。第二个（`loopoffset=`）在 Ubuntu 里没有对应，但它唯一的使用者是 Arista Aboot（`files/Aboot/boot0.j2:884`），而 resolute 的所有目标平台都不构建 Aboot。
- 其他 SONiC 的 initramfs 改动仍然生效：`files/initramfs-tools/udev.patch`，以及 `/etc/initramfs-tools` 下的 hook。

**修复**是在其他架构上直接安装 Ubuntu 的 `initramfs-tools` 和 `busybox-initramfs`（而不是那两个固件拆分包），让每个架构都得到 amd64 已有的 initramfs-tools 0.151ubuntu1 和 busybox-initramfs。确认重建的镜像里是 `initramfs-tools 0.151ubuntu1` 加 `busybox-initramfs`，这个镜像不做任何手工改动就能启动。要不要删掉这份死掉的源码构建，是另一个决定，本次改动不涉及。

上述论断经过对抗式复核（每条论断三个复核 agent 加一个裁判），比对了 2026-08-27 的 amd64 vs rootfs 和构建日志，以及 2026-09-17 的 amd64 broadcom 构建日志。那次 broadcom 构建出自 PR #17 合入前的工作，跑的是基线上同样的那行两个固件包安装。手头没有在基线上构建的 amd64 vs 镜像。

## 4. ONIE 装机与启动

ONIE 测试在 podler 上用 QEMU 10.2.1 运行：`-machine virt,gic-version=3 -accel kvm -cpu host`，4 个 vCPU、8 GB 内存、一块空白的 64 GB virtio-scsi 磁盘、user 模式网络。用到的：

- **ONIE：**SONiC 发布在 `packages.trafficmanager.net/public/onie/` 的 `onie-recovery-arm64-qemu_armv8a-r0.iso`。它报告的版本是 `master-03031019`，2022-03-03 构建，内核 5.4.86，GRUB 2.04。
- **固件：**qemu-efi-aarch64 2026.05-2ubuntu2 里的 `AAVMF_CODE.no-secboot.fd`（§4.1）。
- **测试工具：**[data/2026-09-29-arm64-onie-vmtest/](data/2026-09-29-arm64-onie-vmtest/) 里的 `onie-install-test.py`。它从 ISO 把 ONIE 写到空白磁盘上，弹出 ISO，从磁盘启动 ONIE，对经 HTTP 提供的镜像运行 `onie-nos-install`。然后经安装器写好的 GRUB 重启进 SONiC，等到串口出现登录提示，五分钟后经 ssh 收集状态。

下文用到的固件、GRUB、kexec 和 kdump 测试脚本也在同一目录。

### 4.1 KVM 下的 UEFI 固件

- resolute 自带的 edk2（qemu-efi-aarch64 2025.11-3ubuntu7 和 2025.11-3ubuntu7.2）在 KVM 下一秒内就停在 `Synchronous Exception at 0x47EFE008`。同样的命令，下面这些版本约 20 秒就进入 ONIE：Ubuntu 2024.02-2ubuntu0.9、2025.02-8ubuntu3.2、2026.05-2ubuntu2；Debian 2025.02-8+deb13u1、2026.08+ds-2（`fwvers.sh`）。
- 原因是 edk2-stable202511 的 LPA2 支持带来的已知上游回归：Debian #1124168 和 edk2 #11962。Debian 在 2025.11-5 里 revert 了三个 LPA2 提交修掉了它：2025.11-4 崩在同一个地址，2025.11-5 能启动。resolute 的 2025.11-3ubuntu7.x 早于这次 revert。上游的正式修复是 1a4c4fb5a7（没有 LPA2 的 FEAT_LPA 系统）和 b8df7d9c8e（支持 LPA2 的 CPU 上的早期 ID 映射）。
- `pmu=off`、`gic-version=host`、`-bios QEMU_EFI.fd` 都绕不过去。KVM 下只能用 `host` 和 `max` 两种 CPU，在 `host` 上关掉 pauth、pmu 或 steal time 也没用。TCG 下所有具名 CPU 型号都能启动 resolute 的固件，只有 `-cpu max` 卡死（`tcgsweep.sh`）。
- vera 用 resolute 的固件也以同样方式停住（`Synchronous Exception at 0x496C`），所以 §4.7 在那里用的是直接加载内核。vera 没有换新固件复测，所以同一原因可能性大，但未证实。
- 要在任何 arm64 KVM 宿主机上跑 UEFI，用 `dpkg-deb -x` 从 qemu-efi-aarch64 2026.05-2ubuntu2（`archive.ubuntu.com/ubuntu/pool/main/e/edk2/`）或 Debian 2026.08 里解出 `AAVMF_CODE.no-secboot.fd` 即可，不用安装。还没有向 Launchpad 报 bug。

### 4.2 内核格式

linux-sonic 的 arm64 `vmlinuz` 是 EFI zboot 镜像：一个在偏移 4 处写着 `zimg` 的 PE 外壳，里面包着 zstd 压缩的 Image。2.12 之前的 GRUB 会检查偏移 0x38 处的 arm64 Image 魔数，于是以 `error: invalid magic number` 拒绝这个文件。上游 GRUB 在 69edb31205 里去掉了这项检查（首见于 2.12），但到 2026.08 为止的所有 ONIE 发布版和 ONIE master 仍在构建 GRUB 2.04。所以原样带着 zboot 内核的镜像能从 ONIE 装上，之后却永远起不来。

下表中每个 GRUB 都加载 linux-sonic 7.0.0-1002 内核的三种形态。"能启动"指内核打印出了 `Linux version`（`grubrun.sh`、`grubver.sh`、`grubvanilla.sh`）：

| GRUB | zboot（原样） | 原始 Image | gzip 压缩的 Image |
|---|---|---|---|
| ONIE `master-03031019`（2.04） | 拒绝 | 能启动 | 能启动 |
| 上游 2.06 | 拒绝 | 能启动 | 能启动 |
| Ubuntu jammy 2.06-2ubuntu14.8 | 拒绝 | 能启动 | 能启动 |
| Debian bookworm 2.06-13+deb12u2（反向移植了修复） | 能启动 | 能启动 | 能启动 |
| 上游 2.12 | 能启动 | 能启动 | 能启动 |
| Debian trixie 2.12-9+deb13u2 | 能启动 | 能启动 | 能启动 |
| Ubuntu noble 2.12-1ubuntu7.3 | 能启动 | 能启动 | 能启动 |
| Debian sid 2.14-4 | 能启动 | 能启动 | 能启动 |
| Ubuntu resolute 2.14-2ubuntu1 | 能启动 | 能启动 | 能启动 |

**修复**（`6de838da5e`）在 `build_debian.sh` 里为 arm64 上的 vs 转换内核：

- 从 zboot 头读出载荷的偏移、长度和压缩方式，用 `dd` 截出载荷，解压后重新 gzip，用同一个文件名替换原文件。`build_debian.sh` 对 pensando 的内核本来就存成 gzip。
- 安装器的 `grub.cfg` 以及所有引用这个文件名的地方都不用动。gzip 压缩的 Image 在表里每一个 GRUB 上都能用。
- `dd` 只读载荷那些字节。如果用 `tail | head` 管道，在 `pipefail` 下只要载荷后面还有超过一个管道缓冲区（64 KiB）的数据，就会以 141（SIGPIPE）退出。
- 转换只限 vs。nvidia-bluefield 也是 arm64 加 GRUB，但它的 BFB 打包需要 PE 内核。
- 安全启动构建（`SECURE_UPGRADE_MODE` 为 dev 或 prod）跳过转换。这类构建在这一步之前刚对 PE 内核签名并校验过，解包会丢掉签名。何况 arm64 vs 本来就不支持安全启动：安装器的 shim 路径只找 `shimx64.efi` 和 `grubx64.efi`。
- 对这段代码做过单元测试：
  - 产物与在 podler 上能启动的那个 Image 逐字节一致，文件权限保持 0600。
  - 再跑一次不做任何改动。
  - amd64、broadcom arm64、nvidia-bluefield arm64，以及 `SECURE_UPGRADE_MODE` 为 dev 或 prod 的 vs arm64，都不会被改动。

没有采用的做法：

- **让安装器装镜像自带的 GRUB 2.14，不调用 ONIE 的 `grub-install`。**安装器改动更大，而且内嵌的 stub 还必须 `set prefix=($root)/grub` 并带上 2.14 的 arm64-efi 模块，否则 `grubenv` 会失效。
- **要求使用带 GRUB 2.12 或更新版本的 ONIE。**目前没有任何 ONIE 发布版满足。ONIE PR #1128（GRUB 2.14）尚未合入，目标分支是 `onie-modernization-2026`，而且只在 x86 上测过。

在 SONiC 内部升级（`sonic-installer install`）会运行新镜像的 `install.sh`，但不会运行 `grub-install`，所以 ONIE 的 GRUB 2.04 会一直留到下次重装。之后的每一个 arm64 vs 镜像都必须保留这个转换。

### 4.3 平台身份

SONiC 唯一发布的 arm64 ONIE 报告 `onie_platform=arm64-qemu_armv8a-r0`，而 vs 镜像只认识 `x86_64-kvm_x86_64-r0`。不带这个提交和控制台提交构建的镜像，能说明这意味着什么：

- 安装器停在 "Do you still wish to install this image?"。
- 启动后 `HwSKU: None`，`sonic-platform-vs` 没有装上。
- 14 个容器里只有 7 个在跑（database、eventd、gbsyncd、gnmi、pmon、sysmgr、teamd），`bgp.service` 失败。

**修复**（`624636d7d3`）只在 arm64 vs 构建里把 `arm64-qemu_armv8a-r0` 当作 vs 平台的另一个名字：

- `sonic-device-data` 在生成 vs HwSKU 数据之后，加一个指向 `x86_64-kvm_x86_64-r0` 的符号链接 `device/arm64-qemu_armv8a-r0`，两个名字共享生成的文件。git 里不加任何东西。这一步照同一 recipe 里现成的 `vpp` 条件分支写。这个包不会串到别的架构：它的缓存模式是 `none`，依赖标志里包含 `CONFIGURED_PLATFORM` 和 `CONFIGURED_ARCH`。
- `build_image.sh` 把这个名字写进 `platforms_asic`，紧挨着对 `x86_64-kvm_x86_64-r0` 做同样事情的 `alpinevs` 那几行。
- `sonic-platform-vs` 也为它做懒安装。
- 新增的 `device_info.VS_PLATFORMS` 让 `get_system_mac` 和 `sonic-cfggen` 给两个名字都用确定性的 vs MAC，并让 `minigraph` 像对 kvm 那样在别名上也关掉 `tunnel_qos_remap`。
- 不给别名配 `installer.conf`：vs 的那份只为多 ASIC vs 设 `swiotlb=65536`（#6674）。

没有采用的做法：

- **在 `device/virtual/` 下加 git 跟踪的符号链接。**这会让所有构建（包括 amd64 vs 和 broadcom）都多出一个假的 arm64 平台。aboot 镜像的瘦身步骤也会因它崩溃，因为 `shutil.rmtree` 不接受符号链接。
- **装机时把 `onie_platform` 改写成 x86 的名字。**来不及：`install.sh` 在第 113 行检查 `platforms_asic`，在第 165 行才加载 `platform.conf`。而且会记下一个 ONIE 从没报告过的平台。

检查：

- 打桩的 `device_info` 给两个名字返回同一个确定性的 vs MAC，其他平台走非 vs 路径。
- 在打开 remap 的样例拓扑上，`minigraph.parse_xml` 对两个 vs 名字都保持 `tunnel_qos_remap` 关闭，对 Dell S6000 打开。不加这个改动时，别名会把它打开。
- 在运行中的 arm64 镜像上排查了其他依赖平台名的代码。范围覆盖宿主机和全部 14 个容器，文本文件和 ELF 二进制都查了，还有 `device_info` 里全部 49 个无参函数；另外借助 `PLATFORM` 环境变量覆盖，用两个名字分别跑了 30 多条 show 和工具命令。结果又找到三处，都在子模块里（§7.1）。

### 4.4 控制台

`installer/default_platform.conf` 默认用 x86 的 8250 串口：GRUB 用 `serial --port=0x3f8 --speed=9600`，内核用 `console=ttyS0,9600n8`。在 QEMU virt 上，ONIE 的 GRUB 2.04 会打印 `serial port 'port3f8' isn't found` 和 `terminal 'serial' isn't found`。这不妨碍启动，但内核控制台被设成了 QEMU virt 上不存在的 `ttyS0`，kdump 也会沿用这个设置。

**修复**（`d3b6c4c08b`）新增 `platform/vs/platform_arm64.conf`，`build_image.sh` 在 arm64 上把它用作 `platform.conf`：

- GRUB 只用 console 终端。在 QEMU virt 上它就是固件的 EFI 控制台，也就是 PL011 串口。
- 内核参数为 `console=tty0 console=ttyAMA0,115200n8 quiet`。
- 装好的 `grub.cfg` 开头因此是 `# serial console: EFI ConOut`、`terminal_input console`、`terminal_output console`。

另外在代码里核对过（未实际运行）：

- `sonic-installer install` 会用这个文件重新运行新镜像的 `install.sh`。
- fast-reboot 和 soft-reboot 从 `grub.cfg` 取 `linux` 那一行，内核路径仍在同一个字段。
- `rc.local` 的 `program_console_speed` 和串口 getty 都能处理 `ttyAMA0`。
- kdump 从 `/proc/cmdline` 复制控制台参数。

### 4.5 结果

分支最新提交在 podler 上构建为 `arm64-native.0-a58976d49`，从 ONIE 装机：

- **时间线：**24 秒 ONIE 开始写盘，47 秒从磁盘启动 ONIE（报告 GRUB 2.04），112 秒 SONiC 装完，120 秒出现 GRUB 菜单，150 秒 SONiC 串口出现登录提示。安装器没有任何提问。
- **启动：**内核命令行带 `console=tty0 console=ttyAMA0,115200n8`。装好的 `vmlinuz` 以 `1f 8b` 开头，即 gzip。
- **身份：**`show version` 显示 `SONiC.arm64-native.0-a58976d49`、内核 `7.0.0-1002-sonic`、`Platform: arm64-qemu_armv8a-r0`、`HwSKU: Force10-S6000`、`ASIC: vs`。
- **平台数据：**`/usr/share/sonic/device/arm64-qemu_armv8a-r0` 链接到 `x86_64-kvm_x86_64-r0`，`sonic-platform-vs` 1.0 已安装，`/host/image-*/platform/` 下有别名的目录。
- **容器：**bgp、database、eventd、gbsyncd、gnmi、lldp、mgmt-framework、pmon、radv、snmp、swss、syncd、sysmgr、teamd。
- **数据面：**APPL_DB 里 32 个端口；ASIC_DB 里 33 个 PORT、69 个 ROUTE_ENTRY 对象。BGP 的 router id 为 10.1.0.1，AS 65100，配置了 32 个 peer。
- **健康状态：**`systemctl is-system-running` 报告 `degraded`，失败的单元是 `watchdog-control` 和 `system-health`（§6）。

与不带别名和控制台两个提交的镜像对比：

| | 不带最后两个提交 | 分支最新提交 |
|---|---|---|
| 装机时的 ASIC 类型提示 | 有 | 无 |
| GRUB 报错 | `serial port 'port3f8' isn't found`、`terminal 'serial' isn't found` | 无 |
| HwSKU | None | Force10-S6000 |
| 容器 | 7 个 | 14 个 |
| 失败的单元 | bgp、system-health、watchdog-control | system-health、watchdog-control |

数据目录里的 `onie-e2e-output.txt` 是一份完整的测试工具输出。

### 4.6 kexec 与 kdump

这些测试在不带最后两个提交的镜像装好的 SONiC 里运行。那两个提交只改平台名和控制台参数，而 kdump 的控制台参数是从 `/proc/cmdline` 复制的。脚本是 `kexec-test.sh` 和 `kdump-test.sh`。

- **加载：**`kexec -l` 用 `-a`（fast-reboot 和 warm-reboot 的方式）、`-s`（`kexec_file_load`，安全启动时使用）和 `-c`（`kexec_load`）都成功。镜像自带的 gzip Image、原来的 zboot 文件和原始 Image 三种都行：9 个组合全部 `rc=0`、`kexec_loaded=1`。
- **跳转：**用 `-a` 加载镜像自带的内核后执行 `kexec -e`，能启动。系统回来时 boot id 变了，`/proc/cmdline` 里有 `SONIC_BOOT_TYPE=kexec-test`，内核为 `7.0.0-1002-sonic`。
- **kdump：**`config kdump enable` 并重启后，命令行带 `crashkernel=0M-2G:256M,2G-4G:320M,4G-8G:384M,8G-:448M`，`kexec_crash_loaded=1`，状态为 "ready to kdump"。用 sysrq-c 触发崩溃后约 30 秒内系统回来，`/var/crash/202609290601/` 里有一个 161 MB 的转储文件 `kdump.202609290601`。

### 4.7 vera 上的直接内核启动

vera 在 2026-09-28 做了最早的几次启动，没有经过 UEFI（§4.1）。把镜像的内核解压成原始 Image，由 QEMU 直接加载；磁盘按 `installer/install.sh` 的方式布置。工具在 [data/2026-09-28-arm64-native-vmtest/](data/2026-09-28-arm64-native-vmtest/)。`dockerfs.tar.gz` 必须像安装器那样用 `--numeric-owner` 解包。不加的话，GNU tar 会按宿主机的 passwd 重新映射属主，database 容器里的 redis 就读不了 `/etc/redis/redis.conf`。

`machine.conf` 设为 `onie_platform=x86_64-kvm_x86_64-r0` 时，确认镜像（`arm64-native.0-dirty-20260928.140528`）的结果与 §4.5 相同，记录在 `v3-serial2.log` 和 `runtime-v3.txt`：

- 内核启动后约 30 秒出现登录提示，最后几个容器在开机后约 4–5 分钟起来。
- 跑的是同样的 14 个容器，端口、ASIC_DB 和 BGP 的计数也相同。
- 对应 VM 四块数据网卡的 Ethernet0/4/8/12 为 oper up。其余 28 个背后没有网卡，保持 oper down，这和任何网卡数少于端口数的 vs VM 一样。
- swss、syncd、database、teamd、lldp、snmp、gnmi、mgmt-framework、bgp、pmon 里 supervisord 的所有常驻进程都是 RUNNING。唯一例外是 bgp 里的 `sharpd`，按设计为 `STOPPED Not started`。

## 5. arm64 上去掉的组件

### 5.1 pmon 的 SSD 厂商工具

**为什么只有 x86 版。**`iSmart`（Innodisk iSMART V3.9.41，2018，x86-64）和 `SmartCmd`（Virtium 1.0.2427，2017，静态链接的 i386）是厂商的闭源工具。2019 年 Mellanox 把它们作为预编译二进制提交进仓库（sonic-buildimage #3218），用来从自家 x86 交换机上的 Innodisk、Virtium SSD 读取额外的健康数据。它们没有源码，上游此后再没改过这两个文件。Innodisk 只按询价提供 iSMART，也没写明支持哪些 CPU 架构。Virtium 发布过其他工具的 aarch64 版（vtView、vtTestCmd、vtSecureCmd），但没有 SmartCmd。

**上游现状。**上游从没在任何架构上排除过它们，所以它的 ARM 镜像里照样带着 x86 文件。在唯一一台用 Innodisk SSD 的 ARM 设备（armhf 的 Nokia 7215）上，这会每小时产生一条 `ERR ... [Errno 8] Exec format error: 'iSmart'`。issue #21319 从 2025-01 开到现在，目前唯一的应对是在 sonic-mgmt 的日志分析里忽略这条消息。

**arm64 损失什么：什么都没有。**

- 这两个二进制在 arm64 上无论原生还是用 qemu-user 10.2 都跑不起来。在 qemu 下它们能启动，但 qemu 不翻译它们读盘用的 SG_IO 和 NVMe ioctl。
- `ssd.py`（sonic-platform-common）总是先跑 `smartctl`，只在型号字符串匹配时才调用厂商工具。工具失败时它保留 smartctl 的数据，只记一条错误日志。smartmontools 7.5 和 nvme-cli 2.16 在 resolute arm64 的 main 里，pmon 里本来就装着；smartctl 的驱动器数据库覆盖 Innodisk 的 3IE3/3ME3/3IE4/3ME4 系列。
- arm64 vs 的磁盘永远匹配不到厂商型号。它是 QEMU 的 virtio-scsi `sda`：stormond 的 ata/nvme sysfs 过滤会跳过它，smartctl 对它也不输出 `Device Model:` 这一行。
- 没有任何 arm64 SONiC 平台用 Innodisk 或 Virtium 的 SATA SSD。Nokia 7215 的 arm64 版用的是 eMMC，而 resolute 不构建 armhf。

**两个相关发现。**

- sonic-utilities 会通过它的 wheel 在所有架构上装另一个 x86-64 的 Virtium 工具 `vtFA_RTK_5766_v2`（2026-05 加入，#4508）。它只在 Mellanox 收集技术支持信息的路径里、针对一个特定的 Virtium NVMe 型号运行，所以在 arm64 上是无用的死文件（17.7 KB）。
- `SmartCmd` 内嵌了 Virtium 的软件许可：不可转让，只许留一份备份，并负有保护义务。SONiC 的第三方许可文件里两个工具都没有覆盖。这是 Canonical 现在构建的 amd64 镜像就存在的问题，与 arm64 无关，应交法务确认。

### 5.2 docker-dash-engine

**为什么只有 x86 版。**这个容器 `FROM p4lang/behavioral-model` 构建。p4lang 发布的这个镜像全部 98 个 tag，连同它的整条基础镜像链（`p4lang/pi`、`p4lang/third-party`），都只有 amd64 版。p4lang 的 CI 在 x86 机器上构建，没有设置多平台。这是发布方式的选择，不是代码的限制。bmv2 的源码是可移植的：社区的多架构镜像 `kathara/bmv2` 在 podler 上跑通了 dash-engine 用的那条 `simple_switch_grpc ... --no-p4` 命令，并在 9559 端口提供 P4Runtime 服务。唯一一个要求 arm64 镜像的请求（p4lang/third-party#47，2026-09-01）至今没有回复。

**它在 resolute 上任何架构都不起作用。**

- dash-engine 只是一个空的 bmv2 交换机。DASH 流水线和 SAI 在 syncd 的 `syncd_dash` 里，由它通过 P4Runtime 对 dash-engine 编程。
- `platform/vs/syncd-vs.mk` 只在 `BLDENV` 为 bookworm 或 trixie 时构建 DASH SAI，所以 resolute 从不构建 `syncd_dash`。
- 因此 amd64 resolute 镜像里已经带着一个 175 MB、默认禁用、锁定在一个基于 Ubuntu 20.04 的 digest 上、没有任何东西能驱动的 dash-engine 容器。arm64 上去掉它，没有任何损失。
- 在 arm64 上这个锁定甚至不起作用：`versions-docker` 里只有 `amd64:` 条目，arm64 构建会跟着 `:latest` 漂。

**上游现状。**

- 上游不在 arm64 上构建 vs 镜像。
- PR #25591（草稿）按 `INCLUDE_VS_DASH_SAI` 控制 dash-engine，而这个开关默认是 `y`。按它的写法，arm64 原生构建照样会在 `FROM` 处失败，所以按架构排除仍然必要。
- PR #27346（开放中）加了一个 `INCLUDE_VS_DASH_ENGINE` 开关。

**要在 arm64 上真正做 DPU 仿真需要什么。**

- arm64 版的 bmv2 和 PI。
- 在 resolute 上构建的 p4lang deb，并且也要装进 syncd 容器。
- 给 DASH 的 libsai 打包加多架构补丁；它写死了 `_amd64` 的文件名和 `x86_64-linux-gnu`。
- 在 `BLDENV=resolute` 上启用 DASH SAI。
- arm64 版的 `p4runtime-sh` 镜像；sonic-mgmt 的 DPU 配置流程用它下发 underlay 路由。

这条链上没有一个项目跑 arm64 CI，所以只有在有明确需求时才值得做。

有两件事在 amd64 上也可以做：

- 让 dash-engine 只在 DASH SAI 真正构建时才装（`INCLUDE_VS_DASH_SAI=y` 且 `BLDENV` 为 bookworm 或 trixie）。这样 amd64 resolute 镜像也会去掉那个孤儿容器，属于产品决定。
- 升级 `rules/p4lang.mk` 里钉住的 p4lang 版本。三个 `.dsc` 里有两个已从 OBS 消失，但默认构建从 SONiC 的 web 版本缓存取这些文件，所以不急。

## 6. 不属于 arm64 的发现

| 发现 | 范围 |
|---|---|
| `watchdog-control.service` 失败：`/etc/sonic/vs_chassis_metadata.json not found` | 所有 vs 镜像，上游也一样。构建里没有任何东西生成这个文件，只有 sonic-mgmt 的虚拟机框测试床会写它。代码与上游 `sonic-net/202605` 一致，自 #18512（2024）起就是如此。 |
| `system-health.service` 因同一个文件失败 | 原因相同。`healthd` 在读任何平台配置之前就先构造 vs 的 `Chassis`，所以与平台名无关。在 vera 上用 x86 名时，串口日志显示它也启动了不止一次，但抓取状态时没有被列为失败。systemd 会不会放弃重启，取决于守护进程崩溃得有多快，能否在十秒内撞上五次启动的上限（推断）。 |
| `show version` 打印 `Distribution: Debian forky/sid` | 所有 resolute 镜像。Ubuntu 的 base-files 带的 `/etc/debian_version` 内容是 `forky/sid`，`build_debian.sh:680` 把它抄进 `sonic_version.yml`，sonic-utilities 再在前面加上 "Debian "。仅影响显示。 |

## 7. 遗留事项

### 7.1 子模块里认不出 arm64 名字的检查

下面几处都只用 `x86_64-kvm_x86_64-r0` 或子串 `kvm` 识别 vs，超仓里的 `VS_PLATFORMS` 管不到它们。三处都在装好的镜像上复现过：同一个镜像，分别用 arm64 名和 x86 名对比。上游 `master` 和 `202605` 的代码与此相同，因为上游没有这个别名。修其中任何一处，都需要在该子模块的 `202605_resolute` 分支上做 Canonical 提交并升级 gitlink，所以这里一处都没改。

| 位置 | 对 arm64 vs 的影响 | 触发条件 |
|---|---|---|
| sonic-utilities `scripts/decode-syseeprom:238,243`（`.*kvm.*`） | 见下方列表。 | 每次 snmp 启动 |
| sonic-utilities `utilities_common/hft.py:14`（平台白名单） | `show hft` 和 `config hft` 没有注册（报 "No such command"）。HFT 数据面按 SAI 能力判断，照常启动；在 vs 上它本来就只模拟控制面。 | 始终 |
| sonic-platform-daemons `sonic-ycabled/ycable/ycable.py:307`（CONFIG_DB 平台名 `==` x86 名） | ycabled 把系统当成真硬件，加载 `sfputil` 失败，连退四次后在 pmon 里进入 FATAL。没有任何东西报告这件事。双 ToR 的 vs 测试床因此无法切换 mux 状态（从代码推断）。 | 仅在 `subtype: DualToR` 时 |

`decode-syseeprom` 出错的过程：

- 它以 0 退出，并打印 "Failed to read system EEPROM info"。在 x86 名下它以 ENODEV（19）退出，这个返回码是上游在 sonic-utilities #3750 里专为 vs 加的。
- snmp 的启动前步骤（`docker_image_ctl.j2:128-129`）把这句话不加引号地传给 `HSET`，参数个数不对，redis 拒绝。
- 于是 STATE_DB 里的 `chassis_serial_number` 缺失，而不是 "N/A"，SNMP 的 `entPhysicalSerialNum` 为空。
- 每次 snmp 启动都记一条 `ERR ... wrong number of arguments for 'hset'`。这条路径上的另外两条 ERR，sonic-mgmt 的日志分析已经忽略了，但这一条没有。

建议的修法：

- **decode-syseeprom：**在 `asic_type == 'vs'` 时也视为没有 EEPROM，同时保留 `kvm` 模式，因为 vpp 镜像也用 kvm 这个名字，而它的 `asic_type` 是 vpp。在 VM 上用改过的副本验证过：它以 19 退出，snmp 随后写入 "N/A"。
- **ycabled：**改用 `VS_PLATFORMS`，或者按 `asic_type` 判断，后者也可以提给上游。
- **HFT：**把别名加进白名单，或改为接受 `VS_PLATFORMS`。

同一次排查（§4.3）没有找到第四处。`syncd_init_common.sh:642` 也检查了 `kvm`，但只在 xsight 分支里，vs 永远走不到。

### 7.2 小问题

- klish 在原生路径上用 `-L`/rpath `/usr/lib/x86_64-linux-gnu` 链接。
- `files/initramfs-tools/modules.arm` 列了 `m25p80` 和 `ar7part`，而 linux-sonic 7.0 的 arm64 内核里没有这两个模块。
- `vtFA_RTK_5766_v2`（§5.1）。

### 7.3 坑

- 顶层 `Makefile` 用一条没有前置依赖的 `%::` 规则构建目标。只要 `target/sonic-vs.bin` 存在，`make target/sonic-vs.bin` 就直接报 "up to date"，根本不看 `build_debian.sh`。要重建得先删掉目标文件。
- 用 `pip --user` 装 `jinjanator`，`j2` 落在 `~/.local/bin`，非交互 shell 的 PATH 里没有它。于是 `build_mirror_config.sh` 写出空的 `sources.list`，slave 构建报 "no build stage in current context"。
- `sonic-build-hooks` 目标每次跑 make 都会用 wget 拉 `TRUSTED_GPG_URLS`。在 vera 上，一次瞬时失败（exit 4）让第一次尝试直接退出。
- 在 podler 上，实验室的 apt 代理对 `download.docker.com` 返回 `ERR_DNS_FAIL`，docker-ce 装不上。在 `/etc/apt/apt.conf.d/` 里加 `Acquire::http::Proxy::download.docker.com "DIRECT";`（以及对应的 https 一行）即可。
- 在 arm64 KVM 宿主机上，resolute 自带的 edk2 起不来 UEFI 虚拟机（§4.1）。

## 8. 与交叉探路对照

| | 交叉（2026-09-23，amd64 宿主机） | 原生（2026-09-28 和 29，arm64 宿主机） |
|---|---|---|
| 代码改动 | 7 处代码破例，另加换模拟器和 vfs 驱动 | 9 个提交 |
| slave 镜像 | 8 轮全量加 3 轮影子构建 | 每台机器 1 次构建（vera 上更早一次因 `j2` 不在 PATH 上立即退出） |
| 最远走到 | 容器层上的依赖前沿（建出 2 个镜像） | 镜像经 ONIE 装机并运行 |
| 构建中的模拟 | 每个 arm64 容器和 rootfs 都跑在 qemu-user 下 | 无 |
| 容器镜像标签 | 错标为 amd64 | arm64 |

交叉探路的结论是原生机器能消除 21 条失败里的 19 条，原生构建证实了这一点。它点名的两条架构固有问题（vs 平台包只支持 amd64、dash-engine 基础镜像只有 amd64）就是提交 `96f264e2b9` 和 `13d5623f1c`。

## 9. 现状

- 本地仓库的 `feat/resolute-arm64-vs` 分支，在 `d2f9ae8502` 之上有 9 个签名提交，未推送。
- 两台机器的预留都已结束，vera 和 podler 上的构建树和虚拟机都已不在。
- vera 的日志已拷到 `/home/sheldon-qi/sbi-arm64-native-logs/`：
  - 构建日志（`build-configure.log`、`build-bin-attempt1.log`、`build-bin.log`、`rfs-confirm.log`）；
  - 走到登录提示的直接启动的串口日志：`v2-serial.log`（第一版镜像，替换了 initrd）、`v3-serial.log` 和 `v3-serial2.log`（确认镜像）、`v3b-serial.log`（确认镜像，`onie_platform=arm64-qemu_armv8a-r0`）；
  - `kk3.log`（直接启动宿主机内核）、`fw-aavmf-nosb.log` 和 `fwtest.out`（UEFI 尝试）；
  - `runtime-v2.txt`、`runtime-v3.txt`、`verify-v3.txt` 以及生成它们的脚本；
  - 扫描和论断复核的结果。

  失败的第一次启动（§3 的现象）没有留下串口日志。
- podler 的预留结束前没有拷出任何文件。[data/2026-09-29-arm64-onie-vmtest/](data/2026-09-29-arm64-onie-vmtest/) 里的脚本是按运行时的原样从会话记录中还原的，§2 和 §4 的数字来自它们被记录下来的输出。
