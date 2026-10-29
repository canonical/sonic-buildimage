# 星融 CX204Y-48GT 的 Resolute SONiC 支持 — 设计

- 日期:2026-10-29
- 构建分支:`feat/resolute-cx204y`(新建),基于 `feat/resolute-arm64-vs` 的 `d3b6c4c08b`(draft PR #18,目前唯一能编 arm64 Resolute 镜像的分支)
- 目标硬件:星融 CX204Y-48GT-M-S —— Marvell AlleyCat5X(98DX35xx)芯片,用芯片自带的 Cortex-A55(arm64),48 × 1G 电口 + 4 × 25G SFP28,4 GB 内存,32 GB eMMC,U-Boot 带 UEFI(`bootefi`)
- 相关文档:[arm64 原生构建报告](../2026-09-28-resolute-arm64-native-build-report-zh.md)、[arm64 vs 交叉构建探路设计](2026-09-23-resolute-arm64-vs-cross-probe-design-zh.md)
- 本文为中文版;英文版(`-en.md`)为唯一事实来源

## 1. 目标与范围

产出一个 Resolute(Ubuntu 26.04)SONiC 的 ONIE 安装包,能在 CX204Y-48GT 上装机、启动;内部测试时打开厂商 SAI 后,52 个端口都能转发。

**不在范围内:** 星融其他机型;PoE 和 PTP 功能;编译内核;修改任何现有子模块;让社区 Marvell SAI 驱动 CX204Y(缺这块板子的 ASK XML);决定厂商二进制放在哪里;推回上游。

## 2. 已定决策

| 议题 | 决定 |
|---|---|
| 内核 | 原样使用 arm 分支预编译的 linux-sonic `7.0.0-1002`。只外编两个模块:`mvcpss` 和 `x204y-48gt` |
| 源码位置 | CX204Y 的源码全部放在本仓库,不新建子模块 |
| 厂商基线 | 设备配置和平台脚本以 AsterNOS 固件 `V6.1R006P002` 为准;固件里没有的 C 源码取自 `asternos_patches@105a124` |
| 审阅结构 | 原样导入和适配改动分成不同的提交 |
| 平台范围 | 在 Resolute 上,`marvell-prestera` 的 arm64 镜像只支持 CX204Y,走 GRUB 启动 |
| 厂商二进制 | 仅用于内部测试。不进 git,通过 SAI 覆盖开关接入 |

## 3. 已验证的事实

下列各项都在本设计之前实测确认,没有推断。

| 项 | 结论 | 证据 |
|---|---|---|
| 厂商固件 | `AsterNOS-Campus-V6.1R006P002-arm64.bin`,2026-10-10 从 `release/V6.1R006` 构建:Debian 12.15,内核 `6.1.0-29-2-arm64` | `fs.squashfs` 里的 `sonic_version.yml` |
| 厂商引导链 | U-Boot `bootcmd=run bootefi` → `fatload mmc 0:1` → EFI 分区上的 GRUB → `devicetree` + 原始 Image + initrd。分区:p1 EFI 分区(vfat,512 MB)、p2 ONIE(512 MB)、p3 系统。GRUB 用 `--no-nvram` 安装,启动目标用 `fw_setenv` 设置 | 厂商 `install.sh` |
| 社区 FIT 路线 | 对 Ubuntu 内核不可用:原始 Image 69.3 MiB。在 AC5X 的 FIT 布局里会和 initrd 重叠 5.3 MiB,还超过 Marvell U-Boot 2020.10 的 `CONFIG_SYS_BOOTM_LEN`(64 MiB) | QEMU + U-Boot 2025.10 实测;`sonic_fit.its` |
| 厂商 SAI | `mrvllibsai 1.16.1-2`(维护者 `jenkins@asterfusion.com`,CPSS 4.5.4)。`sai_query_api_version` 返回 11601。`NEEDED libpython3.11.so.1.0`,只被 xpShell 调试命令行使用 | 反汇编;syncd 层里的 dpkg 记录 |
| Python 依赖 | 只是加载时依赖:能从 SAI 触发它的唯一入口是 `SAI_SWITCH_ATTR_SWITCH_SHELL_ENABLE`,syncd 只在 `-d` 时才设置,`marvell-prestera` 不带这个参数。放上桩库后,在 Resolute arm64 用户态(glibc 2.43、libnl 3.12)里 `dlopen(RTLD_NOW)` 成功,syncd 要用的 13 个入口全部解析到 | qemu-user 加载测试 |
| SAI 接口差距 | 1.16.1 → 1.18.1 只在 `ipmc_group` 和 `port` 两张方法表末尾追加了函数,syncd 都不引用。这个库缺 `sai_query_stats_st_capability` 和 `sai_tam_telemetry_get_data`,syncd 里用 `#ifdef` 包着,所以 syncd 必须对着这个库编译 | SAI 头文件对比;`VendorSai.cpp` |
| 厂商包可还原 | syncd 层保留了 `var/lib/dpkg/info/mrvllibsai.{list,md5sums}` 和 status 记录。144 个文件全部还在,md5 和记录逐个一致 | 对解出的层做 md5 校验 |
| `mvcpss` | 社区 `mrvl-prestera` 那份(CPSS 4.3.13,gitlink `5607a8b7cd`)不改就能在 7.0 上编过。它的 ioctl 头文件和厂商的一致,厂商自己也是用 4.3.12 的模块配 4.5.4 的用户态。厂商自带的那份在 7.0 上编不过 | 在容器里对 7.0 做 Kbuild |
| CPLD 驱动 | `x204y-48gt.c` 改两行(i2c 的 `probe`/`remove` 签名)后能在 7.0 上编过。出货模块里有三个公开源码里没有的属性:`device_type`、`fan_num`、`poe_percent` | Kbuild;模块字符串 |
| 设备树 | 厂商 dtb 用的是 Marvell SDK 绑定(`ac5-gpio`、`ac5-wd`、`mv_dma`、`ac5-pcie`),连厂商自己的 6.1 内核里都没有这些驱动。按主线绑定写的 DTS 能干净编译;`dtbs_check` 报的每一条在主线板子上也都有(RD 板本身的警告,以及 CN9130 ClearFog 同样在用、尚无 schema 的 `marvell,reg-init`) | `vmlinuz` 字符串;`dtbs_check` |
| 内核就绪情况 | arm64 initrd 里已经带了 `sdhci-xenon-driver`、`sdhci-pltfm` 和 `mmc_block`(`MODULES=most`);`SERIAL_8250_DW=y`;`MODULE_SIG_FORCE` 关闭 | `lsinitramfs`;内核配置 |

## 4. 分支和提交结构

提交都做 GPG 签名,顺序如下:

1. **原样导入 —— 固件。** 设备目录 `device/asterfusion/arm64-asterfusion_cx204y_48gt_d-r0/`(4 个 SKU 全部)取自 `fs.squashfs`;`asterProcess/`、systemd 单元、`sensors`、`platform_api_mgnt.sh`、`asterfusion_x204y_48gt_sensors.py` 取自平台 deb;`sonic_platform/*.py` 从它的 wheel 里解出。排除:`rsmu_ctl`、两个 `.ko`、wheel 包本身。提交信息里记录固件 md5 和每个文件在安装包内的路径。
2. **原样导入 —— `asternos_patches@105a124`。** 只取固件里没有的:`x204y-48gt.c`、`x204y-48gt.h`、模块 `Makefile`、`setup.py`。
3. **原样导入 —— Linux v7.0。** `ac5-98dx25xx.dtsi`、`ac5-98dx35xx.dtsi`,以及 dt-bindings 头文件 `arm-gic.h`、`irq.h`、`gpio.h`。
4. **适配改动**,一个主题一个提交(见第 5 节)。

文件在 `platform/marvell-prestera/sonic-platform-asterfusion/x204y-48gt/` 下沿用 `asternos_patches` 的目录布局,这样每个原样导入提交都能直接和来源比对。

## 5. 组件划分

| 单元 | 位置 | 作用 | 依赖 |
|---|---|---|---|
| A. 设备目录 | `device/asterfusion/arm64-asterfusion_cx204y_48gt_d-r0/` | 端口表、HwSKU、`sai.profile`、缓存/QoS 模板 | 固件导入 |
| B. 平台源码包 | `platform/marvell-prestera/sonic-platform-asterfusion/` | 一个源码包出两个 deb。**B1**(首次开机才装,只装在 CX204Y 上):`x204y-48gt.ko`、`mvcpss.ko`、`sonic_platform` wheel、`asterProcess` 及其 systemd 单元。**B2**(构建镜像时就装):`/boot` 里的 dtb,因为 GRUB 在首次开机完成之前就要读它 | `mvcpss` 在构建时从 `mrvl-prestera` 子模块拷源码,和 `sonic-platform-marvell` 的做法相同;linux-sonic `7.0.0-1002` 的内核头文件 |
| C. DTS | B 里的 `dts/` | 板级 DTS 加原样的主线 dtsi;用 `cpp` + `dtc` 编译(Resolute 构建容器里已有) | 只有 SONiC 才有的节点(`prestera`、SMC 看门狗、`ac5-ehci`)写在板级 DTS 里;dtsi 保持原样 |
| D. 构建规则 | `platform/marvell-prestera/*.mk`、`build_debian.sh` | arm64 设 `TARGET_BOOTLOADER = grub`;去掉 Nokia 和 RD 的 include;`one-image.mk` 只装 B1 和 B2;syncd 镜像原地改用 Resolute 底,和 Broadcom 的做法相同;zboot → gzip 那一步的条件从 `vs` 扩成 `vs` 或 `marvell-prestera`(不写成所有 arm64:nvidia-bluefield 的 BFB 需要 PE 格式内核) | arm 分支 |
| E. 安装脚本 | `platform/marvell-prestera/platform_arm64.conf`(整份替换)、`installer/default_platform.conf` | 平台文件只覆盖 `demo_install_uefi_grub`:`grub-install --no-nvram` 之后用 `fw_setenv` 设置 `efi_image`、`bootefi` 和 `bootcmd`,替代 `efibootmgr`。通用文件加一个可选变量 `GRUB_DEVICETREE`;设了才在启动项里加一行 `devicetree`,其他平台不受影响 | ONIE 的 `fw_setenv` 和 `/etc/fw_env.config` |
| F. 二进制留口 | `sai.mk`、还原脚本、桩库包 | 第 6 节 | — |

开机流程:

```
U-Boot (bootcmd=run bootefi) → EFI 分区上的 GRUB → devicetree + gzip Image + initrd(含 sdhci-xenon)
  → systemd → x204y_48gt-platform-init.service(asterProcess)
       ├─ modprobe mvcpss、x204y-48gt、optoe …
       └─ 在 SFP 多路复用器通道上实例化 optoe2
  → pmon 安装 sonic_platform wheel → syncd 加载 SAI
```

`asterProcess` 会用 `new_device` 创建 i2c 多路复用器和 EEPROM,而 DTS 已经声明了这些设备。由一个适配提交删掉这几条,只保留 SFP 的 `optoe2`。DTS 的 alias 把总线编号固定成和厂商一致,所以平台代码里的路径(`6-0040`、`7-0050`、总线 10–13)不用改。

## 6. 二进制依赖

SONiC 的成熟做法是二进制不进 git:`.mk` 里写死版本号和下载地址(`SONIC_ONLINE_DEBS`),再用一个默认为空的变量让构建者改用别的来源(Mellanox 的 `MLNX_SDK_ASSETS_BASE_URL`、nvidia-bluefield 的 `SDK_ASSETS_BASE_URL`)。本设计照这个模式做。

- **覆盖开关。** `sai.mk` 默认仍用社区的 `mrvllibsai 1.17.1-13`,保证构建总能跑完。在 `rules/config.user` 里设置 `MRVL_SAI_ASSETS_BASE_URL` 和 `MRVL_SAI_ASSETS_VERSION`,就改用另一个 deb。syncd 随之对着它编译,那两个缺失的可选函数也就不成问题。`config.user` 和 `sai.mk` 的 include 顺序要在实现时确认。
- **还原脚本(提交进仓库;只读数据,从不执行厂商代码)。** 输入:AsterNOS `.bin`。步骤:核对安装包自带的 payload sha1;解开 `fs.zip` 和 zstd 压缩的 `dockerfs`;找到含 `mrvllibsai` dpkg 记录的那一层;按 `.list` 收集文件;用 `.md5sums` 逐个校验;用原 status 字段重新打包。输出:`mrvllibsai_1.16.1-2_arm64.deb`,包名、版本、维护者都不改。任何文件缺失或 md5 不符都报错退出。
- **Python 桩库单独成包。** 本仓库里一个小的源码包,编出 `libpython3.11.so.1.0`,其中 18 个函数一旦被调用就打印名字并 abort。只在打开覆盖开关时,才加入 syncd 的编译依赖和容器。编译时也需要它,因为 syncd 的 configure 会链接 `-lsai`,链接器必须能解析这个库的 `NEEDED` 项。
- **存储。** deb 放在哪里暂不决定,设计不依赖它。

其余所有产物都从源码构建。

## 7. 已知缺口

| 缺口 | 影响 | 处理 |
|---|---|---|
| CPLD 公开源码缺 `device_type`、`fan_num`、`poe_percent` | `asterProcess` 写入失败;`sensors` 读不到风扇数量 | 按 GPL 向星融索取当前源码。在此之前确认写入失败不会让服务停掉,会停就加保护 |
| 社区 SAI 没有 CX204Y 的 ASK XML | 默认 SAI 下,syncd 在 CX204Y 上无法初始化 | 预期内;内部测试走覆盖开关 |
| PoE 管理程序 `API_BT_Share_workspace` 和 PTP 工具 `rsmu_ctl` 只有二进制 | 有这些功能的 SKU 用不了 PoE 和 PTP | 不导入;48GT-M-S 不受影响 |
| 固件 `default_sku` 是 `CX204Y-48GT-M-SWP4`(PoE 款) | 非 PoE 机器会以 PoE SKU 启动;两者端口表相同 | 读过机器 EEPROM 后决定:改默认值,或移植 `sku_setup` |
| ONIE 平台名、ONIE 的 GRUB 片段(`50_onie_grub`)、`fw_env.config`、EFI 分区挂载点 | 安装脚本的假设可能不成立 | 根据真机采集结果定稿;安装脚本对不上时必须明确报错,绝不能装到一半 |

## 8. 验证

**阶段 0 —— 离线(x86 主机)。** 两个模块对着 7.0 头文件编译;编译 dtb 并跑 `dtbs_check`;对固件跑还原脚本,确认 144 个 md5 全部通过、`dpkg-deb -c` 和 `.list` 一致;用还原的 deb 加桩库包重做一次 qemu-user 加载测试;对安装脚本做语法检查;用 QEMU + U-Boot `qemu_arm64` 走一遍 `bootefi` → GRUB `devicetree`(用 virt 的 dtb 代替)→ gzip Image → initrd。

**阶段 1 —— 原生 arm64 构建(vera 或 testflinger 借的机器)。** `PLATFORM=marvell-prestera PLATFORM_ARCH=arm64` 编两次:默认 SAI 一次,打开覆盖开关一次。检查:`fs.zip` 的 `boot/` 里有 gzip 内核和 CX204Y 的 dtb;模块的 vermagic 是 `7.0.0-1002-sonic`;syncd 镜像是 Resolute 底;覆盖模式下 syncd 不引用那两个可选函数,容器里有桩库。

**阶段 2 —— 真机。**
1. 装机前在 ONIE 里采集:`onie-sysinfo -p`、`fw_printenv`(先保存整套 U-Boot 环境变量,因为 `bootcmd` 会被改)、`/etc/fw_env.config`、GRUB 版本、EFI 分区挂载情况、`sgdisk -p /dev/mmcblk0`、EEPROM 里的 SKU。据此关闭第 7 节的待定项。
2. 装机并启动:看串口日志;eMMC、USB、管理口、i2c 多路复用器、RTC 都识别;`mvcpss` 和 `x204y-48gt` 加载成功;平台服务启动;`show platform` 能报出风扇、电源、温度和 SFP 在位。
3. 用厂商 SAI:syncd 启动,48 × 1G 和 4 × 25G 端口 up,基本的二层、三层转发正常。
4. 回退:ONIE rescue、AsterNOS 原版 `.bin`、保存的 U-Boot 环境变量。

**里程碑。** 阶段 0、1 通过;真机上能经 ONIE 装机、启动进 SONiC、平台设备可见、用厂商 SAI 能转发。借到真机之前,里程碑到阶段 1 结束为止。

## 9. 来源

| 来源 | 标识 |
|---|---|
| AsterNOS 固件 | `AsterNOS-Campus-V6.1R006P002-arm64.bin`,md5 `baa645bd66b2fd922064707ce81139a4`,payload sha1 `4a8dc1d145fa3939d8c45f941a3f74b3ebb21d52` |
| 星融补丁仓库 | `github.com/asterfusion/asternos_patches` 分支 `202311`,提交 `105a124a61b639db9299794d79838f111aca4dd7` |
| Linux | kernel.org 的 `linux-7.0.tar.xz`,sha256 `bb7f6d80b387c757b7d14bb93028fcb90f793c5c0d367736ee815a100b3891f0` |
| CPSS 内核模块 | 子模块 `platform/marvell-prestera/mrvl-prestera`,`5607a8b7cd65cd4892a4fdcf7101ca13c214e48a`(CPSS_4.3.13_016) |
| 基线分支 | `feat/resolute-arm64-vs`,`d3b6c4c08b25ead9f744fd7ca724e2cfd1110441` |
