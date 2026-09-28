# 202605_resolute 上的 arm64 vs：原生构建与启动报告

- 日期：2026-09-28
- 基线：`canonical/202605_resolute` 的 `d2f9ae8502`
- 改动：本地分支 `feat/resolute-arm64-vs`（6 个 GPG 签名提交，未推送），工作树 `/home/sheldon-qi/sbi-arm64-native`
- 构建机：`vera`（10.241.5.36，TOR3 实验室，预留约 18 小时）。Cavium ThunderX-88XX，48 核、每核一线程，62 GB 内存，219 GB SSD，Ubuntu 26.04.1 arm64，内核 7.0.0-34-generic，docker-ce 29.8.1。
- 前序：[交叉构建探路报告](2026-09-23-resolute-arm64-cross-probe-report-zh.md)
- 本文为中文版；英文版为唯一事实来源（`-en.md`）

## 0. 结论

**原生 arm64 构建 `target/sonic-vs.bin` 是可行的。**从基线出发只需要**六处小改动，产出的镜像能在 KVM 里启动**：

- 14 个容器起来了。
- 32 个前面板端口从 CONFIG_DB 经 APPL_DB 全部编排进 ASIC_DB（33 个 SAI 端口对象，含 CPU 口）。由 VM 数据网卡承载的 4 个端口为 oper up。
- ASIC_DB 里有 69 条路由。
- BGP（FRR 10.5.4）在运行，配置了 32 个 peer。
- 唯一失败的单元是 `watchdog-control`，它在所有 vs 镜像上都这样失败，amd64 也一样（§5）。

2026-09-23 的交叉探路预言了这个结果。交叉路径用了八处破例，仍然卡在容器层，只建出了 `docker-base` 和 `docker-dash-engine`。原生构建除了已修掉的问题之外，没有再碰到任何代码层面的失败。六处改动里有四处是交叉探路 §6 预言过的，由一次静态扫描确认；扫描在 slave 镜像构建期间运行，又补上了第五处。第六处直到镜像启动才暴露出来，而且顺带揭示了 amd64 上的一件事（§3）。

还有两件事没解决：

- **ONIE + GRUB 的安装路径没有测。**这台 ThunderX 上，UEFI 固件在 KVM 下还没走到 ONIE 就触发了同步异常，所以镜像是直接加载内核启动的（§4）。
- **arm64 vs 镜像没有自己的平台身份。**用真实的 arm64 ONIE（`arm64-qemu_armv8a-r0`）安装时，平台包装不上，swss/syncd 会停掉。这需要先定平台命名（§6）。

## 1. 改动

六处都在 `feat/resolute-arm64-vs` 上，每处一个提交。除了 amd64 的 `sonic-platform-vs` 包名改成了 `_all.deb`，没有一处改变 amd64 构建的行为；树里也没有其他地方引用旧包名。

| 提交 | 改动 | 消除的失败 |
|---|---|---|
| `7c469ec934` | `sonic-slave-resolute/Dockerfile.j2`：`gcc-multilib` 只在 amd64 上装 | resolute 没有发布 arm64 的 `gcc-multilib`，slave 镜像停在这一行 |
| `f989cb441d` | `platform/vs/rules.mk`：`override TARGET_BOOTLOADER = grub` | `Makefile.work` 把非 amd64 默认设为 uboot，`build_debian.sh` 随后要找不存在的 `platform/vs/sonic_fit.its` |
| `96f264e2b9` | `sonic-platform-vs`：`Architecture: all`，产物名改为 `_all.deb` | 纯 Python 包却声明为 amd64，`dpkg-buildpackage` 什么都产不出来 |
| `13d5623f1c` | `docker-dash-engine`：仅限 amd64（make 规则加 unit 文件拷贝） | 它的基础镜像 `p4lang/behavioral-model:latest` 只有 amd64 版 |
| `2c04ece9e9` | pmon：`ssd_tools` 及其宿主机包装脚本只在 amd64 上带 | 预编译的 `iSmart`（x86-64）和 `SmartCmd`（i386）会以无法运行的形式进入 arm64 镜像 |
| `8858c03ecd` | `build_debian.sh`：非 amd64 上安装 `initramfs-tools busybox-initramfs` | arm64 的 initrd 里没有 busybox，挂不上根文件系统（§3） |

静态扫描在 06:08–07:34 UTC 运行，正值 slave 镜像构建期间、包构建开始之前。前四处改动作为已知项（来自交叉探路 §6）交给扫描，由它确认，第五处是它新找到的。扫描对 vs arm64 的构建闭包跑了 8 个维度的 finder，每条发现由两个视角不同的对抗式复核 agent 核对（代码是否真会走到、失败是否真会发生）。56 条发现里 29 条确认、8 条有争议、9 条被驳回；另外 10 条的复核调用失败，未能核实。确认会导致构建失败的，恰好就是前四处改动；pmon 那条被确认为"静默产出错误架构文件"。之后的真实构建里，没有出现扫描清单之外的代码层面失败，其余失败都出在宿主机和网络上：`j2` 不在 PATH 上，以及一次 `TRUSTED_GPG_URLS` 的 wget 瞬时失败。

## 2. 构建

| 阶段 | 时间（UTC） | 耗时 | 结果 |
|---|---|---|---|
| 宿主机准备与克隆 | 06:04 之前 | 约 20 分钟 | 克隆 21 秒；60 个子模块 6 分钟 |
| slave 镜像（原生，70 步） | 06:05–约 08:20 | 约 2 小时 15 分（其中 Docker 构建步骤约 2 小时 11 分） | 修掉 `gcc-multilib` 后无失败 |
| 包、容器、镜像（`-k`） | 08:25:59–11:41:46 | 3 小时 16 分 | 216 个目标，0 失败（更早一次尝试因 `TRUSTED_GPG_URLS` 的 wget 瞬时失败而立即退出） |
| initramfs 修复后的确认重建 | 14:05:22–14:52:31 | 47 分钟 | 只重建 rootfs 和安装包 |

slave 镜像的耗时主要花在 ThunderX 核心跑得慢的串行任务上：一步装 1800 个包的 dpkg 约 40 分钟（含 texlive 生成格式文件）；`grpcio 1.71.0` 源码编译 12 分钟（两个架构都没有 cp314 的 wheel）；`cargo-tarpaulin` 最后一个单线程 `rustc` 约 11 分钟（整步 13 分钟）；导出并解包 15.2 GB 的镜像约 20 分钟。

产出（在 `target/` 里计数，记录于 `verify-v3.txt`）：154 个 deb（145 个 arm64、9 个 all）、32 个 wheel、29 个容器镜像（26 个装进镜像，另 3 个是中间层），确认重建出的 `sonic-vs.bin` 为 1,424,703,471 字节（1.42 GB）。对这个镜像的检查，全部记录在 `verify-v3.txt`：

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

## 4. 镜像是怎么启动的

- `/dev/kvm` 可用（宿主机运行在 EL2，GICv3），但 edk2 固件在这台 ThunderX 的 KVM 下起不来。`AAVMF_CODE.no-secboot.fd`、`AAVMF_CODE.fd`、`QEMU_EFI.fd`，加上 `pmu=off` 或只给一个 vCPU，全都一上来就报 `Synchronous Exception at 0x496C`。在 TCG 下固件横幅能打印出来，之后九分钟以上毫无进展。所以 ONIE、SONiC 安装器、GRUB 在这里都跑不了。
- 在 KVM 下直接加载内核可以启动。Ubuntu 的 arm64 内核（宿主机的和 SONiC 的 `7.0.0-1002-sonic`）都是 zstd 压缩的 EFI zboot 镜像，而 QEMU 的 `-kernel` 只会解 gzip 的 zboot，所以先把内核解压成原始 Image。
- 磁盘按 `installer/install.sh` 的方式布置：GPT，ext4 卷标 `SONiC-OS`，`image-<版本>/{fs.squashfs,boot,docker,platform}`，外加 `machine.conf`。内核命令行用的是安装器写进 GRUB 的那一行，console 改为 `ttyAMA0`。
- 工具在 [data/2026-09-28-arm64-native-vmtest/](data/2026-09-28-arm64-native-vmtest/)。`dockerfs.tar.gz` 必须像安装器那样用 `--numeric-owner` 解包。不加的话，GNU tar 会按宿主机的 passwd 重新映射属主，database 容器里的 redis 就读不了 `/etc/redis/redis.conf`。

确认镜像（`build_version` 为 `arm64-native.0-dirty-20260928.140528`）的结果，`machine.conf` 设为 `onie_platform=x86_64-kvm_x86_64-r0`（这是镜像唯一认识的平台）。记录在 `v3-serial2.log` 和 `runtime-v3.txt`：

- 内核启动后约 30 秒出现登录提示。最后几个容器（lldp、snmp、mgmt-framework）在开机后约 4–5 分钟起来。
- 容器：bgp、database、eventd、gbsyncd、gnmi、lldp、mgmt-framework、pmon、radv、snmp、swss、syncd、sysmgr、teamd。
- 端口：APPL_DB 里 32 个，全部 32 个 admin up。对应 VM 四块数据网卡的 Ethernet0/4/8/12 为 oper up；其余 28 个背后没有网卡，保持 oper down，这和任何网卡数少于端口数的 vs VM 一样。
- ASIC_DB：33 个 PORT、69 个 ROUTE_ENTRY、34 个 ROUTER_INTERFACE、672 个 QUEUE、416 个 SCHEDULER_GROUP 对象。
- BGP：FRRouting 10.5.4，router id 10.1.0.1，AS 65100，配置了 32 个 peer。
- swss、syncd、database、teamd、lldp、snmp、gnmi、mgmt-framework、bgp、pmon 里的 supervisord：所有常驻进程均为 RUNNING，一次性程序（`start`、`dependent-startup`、`swssconfig` 等）已 EXITED。唯一例外是 bgp 里的 `sharpd`，按设计为 `STOPPED Not started`。
- 管理网卡从 QEMU 的 DHCP 服务器拿到 10.0.2.15（`DHCPACK of 10.0.2.15 from 10.0.2.2`）。

initramfs 修复之前的第一版镜像，换上替代 initrd 启动后，结果相同（`runtime-v2.txt`）。

## 5. 不属于 arm64 的发现

| 发现 | 范围 |
|---|---|
| `watchdog-control.service` 失败：`/etc/sonic/vs_chassis_metadata.json not found` | 所有 vs 镜像，上游也一样。构建里没有任何东西生成这个文件，只有 sonic-mgmt 的虚拟机框测试床会写它。代码与上游 `sonic-net/202605` 一致，自 #18512（2024）起就是如此。 |
| `show version` 打印 `Distribution: Debian forky/sid` | 所有 resolute 镜像。Ubuntu 的 base-files 带的 `/etc/debian_version` 内容是 `forky/sid`，`build_debian.sh:680` 把它抄进 `sonic_version.yml`，sonic-utilities 再在前面加上 "Debian "。仅影响显示。 |

## 6. arm64 的遗留事项

已由启动测试证实：

- **平台身份。**用 `onie_platform=arm64-qemu_armv8a-r0` 启动，这是 SONiC 发布的唯一一个 arm64 ONIE（`onie-recovery-arm64-qemu_armv8a-r0.iso`）会报告的平台串：
  - `show platform summary` 显示 `HwSKU: None`。
  - `sonic-platform-vs` 没有装上，因为只有 `x86_64-kvm_x86_64-r0` 有 lazy-install 目录。
  - swss 和 syncd 停掉，`bgp` 和 `featured` 失败。

  静态扫描给出的修法是：加一个 git 跟踪的符号链接 `device/virtual/arm64-qemu_armv8a-r0 -> x86_64-kvm_x86_64-r0`，在 `src/sonic-device-data` 里加对应的符号链接，并把这个平台加进 `$(VS_PLATFORM_MODULE)_PLATFORM`。这需要先定下 arm64 vs 的平台名，本次没有构建。

来自静态扫描、在这台机器上无法走到的：

- **ONIE 下的内核格式。**ONIE 的 GRUB 2.04 不认 zstd 的 EFI zboot 内核（"invalid magic number"）。扫描给出三条出路：
  - 构建时把 zboot 内核解成 GRUB 2.04 能接受的 gzip 压缩原始 arm64 Image。改动最小，不用动安装器；一名复核 agent 验证过结果能被接受。
  - 让安装器安装镜像自带的 GRUB 2.14（用 `grub-mkstandalone` 生成 arm64-efi），而不是调用 ONIE 的 `grub-install`。内嵌的 stub 还必须 `set prefix=($root)/grub` 并带上 2.14 的 arm64-efi 模块，否则 `grubenv` 会失效。
  - 要求使用带 GRUB 2.12 或更新版本构建的 ONIE。
- **控制台默认值。**`installer/default_platform.conf` 默认用 x86 的 8250 串口（`serial --port=0x3f8`、`console=ttyS0`）。arm64 需要一个 `platform/vs/platform_arm64.conf` 改用 PL011（`ttyAMA0`）。
- 小问题，不妨碍启动：
  - klish 在原生路径上用 `-L`/rpath `/usr/lib/x86_64-linux-gnu` 链接。
  - `sonic-utilities` 装了一个预编译的 x86-64 `vtFA_RTK_5766_v2`。
  - `files/initramfs-tools/modules.arm` 列了 `m25p80` 和 `ar7part`，而 linux-sonic 7.0 的 arm64 内核里没有这两个模块。

途中踩到的坑，供复现时参考：

- 顶层 `Makefile` 用一条没有前置依赖的 `%::` 规则构建目标。只要 `target/sonic-vs.bin` 存在，`make target/sonic-vs.bin` 就直接报 "up to date"，根本不看 `build_debian.sh`。要重建得先删掉目标文件。
- 用 `pip --user` 装 `jinjanator`，`j2` 落在 `~/.local/bin`，非交互 shell 的 PATH 里没有它。于是 `build_mirror_config.sh` 写出空的 `sources.list`，slave 构建报 "no build stage in current context"。
- `sonic-build-hooks` 目标每次跑 make 都会用 wget 拉 `TRUSTED_GPG_URLS`。一次瞬时失败（exit 4）让第一次尝试直接退出。

## 7. 与交叉探路对照

| | 交叉（2026-09-23，amd64 宿主机） | 原生（2026-09-28，arm64 宿主机） |
|---|---|---|
| 代码改动 | 7 处代码破例，另加换模拟器和 vfs 驱动 | 6 个提交 |
| slave 镜像 | 8 轮全量加 3 轮影子构建 | 1 次构建（更早一次因 `j2` 不在 PATH 上立即退出） |
| 最远走到 | 容器层上的依赖前沿（建出 2 个镜像） | 镜像建成并启动 |
| 构建中的模拟 | 每个 arm64 容器和 rootfs 都跑在 qemu-user 下 | 无 |
| 容器镜像标签 | 错标为 amd64 | arm64 |

交叉探路的结论是原生机器能消除 21 条失败里的 19 条，原生构建证实了这一点。它点名的两条架构固有问题（vs 平台包只支持 amd64、dash-engine 基础镜像只有 amd64）就是提交 `96f264e2b9` 和 `13d5623f1c`。

## 8. 现状

- 本地仓库的 `feat/resolute-arm64-vs` 分支，在 `d2f9ae8502` 之上有六个签名提交，未推送。
- `vera` 上保留着构建树 `~/sonic-buildimage`（分支 `arm64-native`，同样的六处改动，未提交）、两版镜像，以及 `~/vmtest` 下的测试盘。这台机器从 2026-09-28 05:45 UTC 起预留约 18 小时。
- 日志已拷到 `/home/sheldon-qi/sbi-arm64-native-logs/`：
  - 构建日志（`build-configure.log`、`build-bin-attempt1.log`、`build-bin.log`、`rfs-confirm.log`）；
  - 走到登录提示的 SONiC 启动的串口日志：`v2-serial.log`（第一版镜像，替换了 initrd）、`v3-serial.log` 和 `v3-serial2.log`（确认镜像）、`v3b-serial.log`（确认镜像，`onie_platform=arm64-qemu_armv8a-r0`）；
  - `kk3.log`（直接启动宿主机内核）、`fw-aavmf-nosb.log` 和 `fwtest.out`（UEFI 尝试）；
  - `runtime-v2.txt`、`runtime-v3.txt`、`verify-v3.txt` 以及生成它们的脚本；
  - 扫描和论断复核的结果。

  失败的第一次启动（§3 的现象）没有留下串口日志。
