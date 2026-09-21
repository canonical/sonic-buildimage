# ONIE 多引导机制与 Ubuntu SONiC 装机 SOP

**日期**：2026-09-09
**适用**：x86_64 UEFI 白盒交换机（本文实证机型 Dell EMC S5232F-ON，`x86_64-dellemc_s5232f_c3538-r0`）
**来源**：2026-07-26 在 dut02 上的实际操作会话（423 次命令）+ `installer/default_platform.conf` 源码
**关系**：[2026-07-26 验证报告](2026-07-26-dut02-s5232f-validation-report-zh.md) 记的是"当时做了什么"，本文记的是"这套机制是什么"和"下次怎么做"。

---

# 第一部分 · 基础知识：ONIE 是怎么支持多引导的

很多人把 ONIE 理解成"一个装机器的 U 盘"。实际上它是**常驻磁盘的一层固件级引导环境**，装完 NOS 也不会消失。整台机器的引导决策分布在**四层**，每层都有自己的"默认项"和自己的"一次性跳转"机制，互不知情。绝大多数引导事故都源于只改了其中一层，却以为改的是全局。

```
┌─ 层 0  UEFI NVRAM ─────────────────────────────────────────┐
│  BootOrder / BootNext / BootCurrent                        │
│  每项 = (分区 PARTUUID, EFI 可执行文件路径)                 │
└───────────────┬────────────────────────────────────────────┘
                │ 固件加载某个 grubx64.efi
┌───────────────▼─ 层 1  各引导器的入口 grub.cfg ─────────────┐
│  ESP (sda1) /EFI/{onie,UBUNTU-NOS,SONIC-OS,debian}/        │
│  ⚠ /EFI/debian/grub.cfg 是被多个 NOS 争抢的共享入口         │
└───────────────┬────────────────────────────────────────────┘
                │ configfile 跳到某个分区的完整 grub.cfg
┌───────────────▼─ 层 2  NOS 自己的 grub 菜单 ────────────────┐
│  saved_entry(持久) / next_entry(一次性) / onie_entry(一次性)│
└───────────────┬────────────────────────────────────────────┘
                │ 若选中的是 SONiC
┌───────────────▼─ 层 3  SONiC 双镜像 ────────────────────────┐
│  /host/image-<ver>/ ；sonic-installer list/set-default      │
└─────────────────────────────────────────────────────────────┘
```

## 层 0 · UEFI NVRAM

固件里存着一张有序的引导项表。dut02 装完两个 OS 之后的实测：

```
BootCurrent: 0006
BootOrder: 0006,0000,0004,0005,0001,0002,0003
Boot0000* UBUNTU-NOS  HD(1,GPT,b966357b-…,0x800,0x80000)/File(\EFI\UBUNTU-NOS\grubx64.efi)
Boot0004* ONIE: Open Network Install Environment
                      HD(1,GPT,b966357b-…,0x800,0x80000)/File(\EFI\ONIE\GRUBX64.EFI)
Boot0005* EDA-DIAG    HD(1,GPT,40f9e57a-…,0x800,0x40000)/File(\EFI\EDA-DIAG\GRUBX64.EFI)
Boot0006* SONiC-OS    HD(1,GPT,b966357b-…,0x800,0x80000)/File(\EFI\SONIC-OS\GRUBX64.EFI)
```

注意 `Boot0005` 的 PARTUUID 与其余三项**不同**——EDA-DIAG 在独立 eMMC（`mmcblk0`）自己的 ESP 上，不在 `sda1`。所以缩容/重分区 `sda` 完全不影响它，它也因此是个理想的镜像暂存区。

操作：

| 目的 | 命令 |
|---|---|
| 改持久顺序 | `efibootmgr -o 0006,0000,0004,0005,…` |
| 一次性下次进某项 | `efibootmgr -n 0000` |
| 新建项 | `efibootmgr -c -d /dev/sda -p 1 -L "UBUNTU-NOS" -l "\\EFI\\UBUNTU-NOS\\grubx64.efi"` |
| 删项 | `efibootmgr -b 0000 -B` |

⚠️ **`onie-nos-install` 会动这一层。** 实测装完官方 SONiC 后，`Boot0000 UBUNTU-NOS` 整项消失（`sda3` 分区和文件系统完好无损，只是 NVRAM 里的引导项没了）。ONIE 装机脚本里确有按卷标清 EFI 变量的逻辑（`create_demo_uefi_partition()` 里遍历 `efibootmgr | grep -e "$demo_volume_label" -e "$legacy_volume_label"` 并 `-B` 删除），但 `UBUNTU-NOS` 不该匹配 `SONiC-OS`；更可能是装机前 ONIE 的 uninstall 阶段（`onie/tools/lib/onie/onie-uninstaller-common`）清理"旧 NOS"引导项所致。**我们没有逐行坐实是哪一条**，所以规则不是"理解它"，而是：**装完必查 `efibootmgr`，缺了就 `-c` 重建、`-o` 重排。**

## 层 1 · 入口 grub.cfg 与 `/EFI/debian` 的争抢

每个 `grubx64.efi` 里编译期嵌了一个 `prefix`，决定它去哪读配置。Debian 系（含 Ubuntu、也含 SONiC）的惯例 prefix 是 **`/EFI/debian`**。dut02 的 ESP 实测：

```
/EFI/onie/grubx64.efi
/EFI/UBUNTU-NOS/grubx64.efi
/EFI/SONiC-OS/grubx64.efi
/EFI/debian/grub.cfg          ← 只有一份，大家共用
```

SONiC 的 ONIE 安装脚本会**无条件覆盖**这个共享入口（`installer/default_platform.conf:567-579`，注释原文就叫 "Make a first grub config file that located in default debian path"）：

```sh
cat <<EOF > $tmp_config
search --no-floppy --label --set=root $demo_volume_label   # SONiC-OS
set prefix=(\$root)'/grub'
configfile \$prefix/grub.cfg
EOF
mkdir -p /boot/efi/EFI/debian/
cp $tmp_config /boot/efi/EFI/debian/grub.cfg
```

**后果**：装完 SONiC，即使固件按 `Boot0000 (UBUNTU-NOS)` 引导，`UBUNTU-NOS/grubx64.efi` 也会去读 `/EFI/debian/grub.cfg`，而那份已经写着 `search --label SONiC-OS` → 于是跳进 `sda4` 的 SONiC grub。**层 0 选的项，未必决定你最终进哪个 OS。** 这是双 NOS 共存最反直觉的一点。

（`Boot0005 EDA-DIAG` 不受影响，它的 grubx64.efi 在另一块盘的 ESP 上，prefix 不指向 `sda1`。）

## 层 2 · NOS grub 的三个跳转变量

SONiC 生成的 `/host/grub/grub.cfg` 开头是这段（`installer/default_platform.conf:521-537`）：

```sh
if [ -s $prefix/grubenv ]; then load_env; fi
if [ "${saved_entry}" ]; then set default="${saved_entry}"; fi
if [ "${next_entry}" ]; then
    set default="${next_entry}"; unset next_entry; save_env next_entry
fi
if [ "${onie_entry}" ]; then
    set next_entry="${default}"          # 记住"本来要去哪"
    set default="${onie_entry}"          # 这次去 ONIE
    unset onie_entry; save_env onie_entry next_entry
fi
```

三个变量语义不同：

| 变量 | 语义 | 谁写 |
|---|---|---|
| `saved_entry` | 持久默认项 | `grub-set-default` |
| `next_entry` | 一次性，消费后自动清 | `grub-reboot` / `grub-editenv … set next_entry=` |
| `onie_entry` | 一次性进 ONIE，**并自动安排下次回到原处** | SONiC 侧"重启进 ONIE"的实现 |

Ubuntu NOS 侧同理，用 `next_entry`；它的 grub 根在 **`/grub/`** 而不是 `/boot/grub/`（因为 `root=LABEL=UBUNTU-NOS` 且 grub 目录在分区根）：

```bash
sudo grub-editenv /grub/grubenv set next_entry=ONIE && sudo reboot
```

Ubuntu NOS 的菜单实测有三项，后两项是 chainload：

```
menuentry 'Ubuntu NOS 1.0.0'   → linux /boot/vmlinuz root=LABEL=UBUNTU-NOS …
menuentry 'EDA-DIAG'           → chainloader /EFI/EDA-DIAG/grubx64.efi   (hd2,gpt1)
menuentry ONIE                 → chainloader /EFI/onie/grubx64.efi       (hd0,gpt1)
```

⚠️ **两个真实咬过人的坑：**

1. **`save_env` 在这台机器的 ext4 上写不回。** 设了 `next_entry=ONIE` 进 ONIE 之后，该变量**没有被消费掉**，意味着此后每次重启都会进 ONIE，回不去 Ubuntu。grubenv 是固定 **1024 字节**格式（25 字节头 + `#` 填充），不能按行删。当时的解法是在 ONIE 里 `mount -o rw` 挂上 `sda3`，备份后**整块重写一个干净的空 grubenv**。
2. **残留的 `onie_entry` 会让引导去向和你设的 `BootNext` 完全对不上。** 实测设了 `efibootmgr -n 0000`（Ubuntu），结果落进 ONIE，`BootCurrent` 确实是 `0000`。原因是链路末端 `sda4` 的 grubenv 里有个残留 `onie_entry` 被消费了。静态读 grub.cfg 解释不了这种现象——**必须用 console 看一次真实引导过程**，这是唯一能观测层 1/层 2 交互的手段。

## 层 3 · SONiC 的双镜像

SONiC 在自己的 `sda4`（`/host`，标签 `SONiC-OS`）里以目录形式并存多个镜像：

```
/host/image-202605.1174613-ec1bb42e4/
/host/image-202605_resolute_sheldon.0-1d988dec/
```

```
$ sudo sonic-installer list
Current: SONiC-OS-202605.1174613-ec1bb42e4          ← 正在跑的
Next:    SONiC-OS-202605_resolute_sheldon.0-1d988dec ← 下次启动的
Available: …
```

**为什么只留两个镜像**，源码给了确切答案。`sonic-installer install` 走 `install_env = "sonic"` 分支，生成新 grub.cfg 时只从旧 grub.cfg 里捞**当前正在运行**那一个 menuentry（`installer/default_platform.conf:552-555`）：

```sh
old_sonic_menuentry=$(cat /host/grub/grub.cfg | sed "/^menuentry '${demo_volume_label}-${running_sonic_revision}'/,/}/!d")
onie_menuentry=$(cat /host/grub/grub.cfg | sed "/menuentry ONIE/,/}/!d")
```

新 grub.cfg = 新镜像项 + `$old_sonic_menuentry` + `$onie_menuentry`。第三个镜像的 menuentry 根本不在被捞取的范围内，于是**静默消失**。同一段也解释了为什么 ONIE 入口能在多次 `sonic-installer install` 之后一直保留——它被显式捞取并带过去了。

同一个 `install_demo_os()` 函数复用于三种场景（`install_env` = `onie` / `sonic` / `build`）：从 ONIE 首装、从运行中的 SONiC 装、构建时生成。只有 `install_env = "onie"` 那条分支会把 ONIE 自己的 grub 片段 `$onie_root_dir/grub.d/50_onie_grub` 追加进菜单——**ONIE 菜单项最初就是这么进 SONiC grub 的**，之后靠上面那行 `sed` 代代相传。

> resolute 分支的差异只有内核文件名：`installer/default_platform.conf:599,604` 是 `vmlinuz-7.0.0-1002-sonic` / `initrd.img-7.0.0-1002-sonic`（上游是 `vmlinuz-6.12.41+deb13-sonic-${arch}`）。注意 Ubuntu 的 ABI 串不带 arch 后缀。

## ONIE 自身的模式机

ONIE 常驻在 `sda2`（标签 `ONIE-BOOT`，128 MB，ext4），有自己的 grub 和五个菜单项：

```
onie_menu_install    "ONIE: Install OS"
onie_menu_rescue     "ONIE: Rescue"
onie_menu_uninstall  "ONIE: Uninstall OS"
onie_menu_update     "ONIE: Update ONIE"
onie_menu_embed      "ONIE: Embed ONIE"
set fallback="${onie_menu_rescue}"
```

进哪个由两个 grubenv 变量决定（`sda2` 的 grub.cfg 里有原文注释）：

```sh
if   [ "$onie_mode" = "install"   ] ; then set default="${onie_menu_install}"
elif [ "$onie_mode" = "uninstall" ] ; then set default="${onie_menu_uninstall}"; reset_onie_mode
elif [ "$onie_mode" = "update"    ] ; then set default="${onie_menu_update}"
elif [ "$onie_mode" = "embed"     ] ; then set default="${onie_menu_embed}"
elif [ "$onie_mode" = "rescue"    ] ; then set default="${onie_menu_rescue}";    reset_onie_mode
elif [ "$onie_mode" = "diag"      ] ; then set default="${diag_menu}";           reset_onie_mode
else
   if [ "$onie_nos_mode" = "yes" ] ; then set default="${onie_menu_rescue}"; fi   # 装过 NOS
fi
```

优先级：`onie_mode`（一次性，`uninstall`/`rescue`/`diag` 用完自动 `reset_onie_mode`）> `onie_nos_mode`（持久标记）> 缺省 install。选中的模式通过内核命令行 `boot_reason=$onie_boot_reason` 传给 ONIE initramfs。

**dut02 实测 `onie_nos_mode=yes`** ——装过 NOS 的机器进 ONIE 默认落在 **Rescue**，不会自动联网装机。这是好事（不会误擦），但意味着你不能指望"重启进 ONIE 就开装"。

ONIE 自带的模式工具在 `/mnt/onie-boot/onie/tools/bin/`：`onie-boot-mode`、`onie-nos-mode`、`onie-fwpkg`、`onie-fw-version`、`onie-version`。SONiC 装 DIAG 分区时就调了 `onie-boot-mode -q -o install`（`default_platform.conf:546`）。

**Rescue 环境的可用性**（dut02 实测，ONIE 3.40.1.1-9 / kernel 4.9.30-onie+）：起 `dropbear` + `udhcpc`，DHCP 拿到与正常系统**同一个** mgmt IP，`root` **空密码**可 SSH——比串口可靠得多。但：

- `PATH` 只有 `/usr/bin:/bin`，而 `resize2fs`/`e2fsck`/`sgdisk`/`parted`/`partprobe` 都在 `/usr/sbin`，**必须显式 `export PATH=/usr/sbin:/sbin:/usr/bin:/bin`**
- `reboot` 在 `/sbin/reboot`，也不在 PATH
- 没有 `grub-editenv`、没有 `strings`
- dropbear 每条命令都吐一堆安全告警，脚本里要 `grep -vE "WARNING:|vulnerable|decrypt later|…"` 过滤

**不要靠猜**。进 ONIE 之前先把 initrd 拆开看清楚有什么：

```bash
xzcat onie-initrd.xz | cpio -t | grep -E "resize2fs|e2fsck|sgdisk|parted|dropbear|udhcpc"
xzcat onie-initrd.xz | cpio -idm && grep "^root" etc/shadow    # 确认空密码
```

## 「下次启动进 X」速查

| 想去哪 | 在哪操作 | 怎么做 |
|---|---|---|
| 另一个 EFI 引导项（一次性） | 任意 OS | `efibootmgr -n <NNNN>` |
| 另一个 EFI 引导项（持久） | 任意 OS | `efibootmgr -o <新顺序>` |
| ONIE（一次性） | Ubuntu NOS | `grub-editenv /grub/grubenv set next_entry=ONIE` |
| ONIE（一次性，用完自动回来） | SONiC | 设 `onie_entry`（层 2 逻辑会自动填 `next_entry`） |
| 另一个 SONiC 镜像（持久） | SONiC | `sonic-installer set-default <ver>` |
| ONIE 进 Install 而非 Rescue | ONIE / NOS | `onie-boot-mode -o install`，或在 ONIE 菜单手选 |

**排障顺序永远是从外往里**：`efibootmgr` 看 `BootCurrent` → 看 `/EFI/debian/grub.cfg` 指向谁 → 看目标分区 grubenv 有无残留 `next_entry`/`onie_entry` → 最后才看 NOS 内部。任何一层都能推翻上一层的意图。**静态分析对不上时，用 console 看一次真实引导，不要继续猜。**

---

# 第二部分 · 装机 SOP

场景：一台已经装了别人的 NOS、磁盘被占满的在役交换机，要在**不破坏原系统**的前提下装上自建 Ubuntu SONiC，并保留回滚路径。

> 全文用占位符：`<DUT-MGMT-IP>`、`<PW>`、`<CONSOLE-SERVER>`、`<CONSOLE-PW>`、`<sda3-PARTUUID>`。执行前替换。

## 阶段 0 · 勘察（装之前必须回答的问题）

1. **镜像与平台匹配吗**——离线拆开 `.bin` 验，别装完才发现：
   ```bash
   sed -e '1,/^exit_marker$/d' sonic-xxx.bin | tar -xO installer/platforms_asic | grep -i <平台关键字>
   grep -a -m2 -oE "payload_sha1=[a-f0-9]+|image_version=[^\"]*" sonic-xxx.bin
   ```
2. **引导链长什么样**——`efibootmgr -v`；只读挂 `sda1` 看 `/EFI/*`；只读挂 `sda2` 看 ONIE grub.cfg 与 grubenv（`onie_nos_mode`）。
3. **ONIE rescue 进得去吗、进去有什么**——拉 initrd 回本地 `cpio -t`（见上）。
4. **原系统有哪些不可再生物**——只在磁盘上、任何 repo 都找不回的东西。dut02 上是 `switchdevd` 二进制和 `libsaibcm 11.2 .deb`。
   ```bash
   tar czf preserve.tar.gz /usr/share/sonic/platform /usr/sbin/switchdevd \
       /etc/machine.conf /etc/netplan /etc/frr /var/lib/cloud/instance/user-data.txt
   # 外加 dpkg -l / sgdisk -p / ip route / systemctl list-unit-files 的文本快照
   ```
5. **原系统开机会自己改磁盘吗**——cloud-init 的 `growpart` + `resizefs`（`frequency: always`）会**每次开机把根分区扩回填满整盘**。查 `/etc/cloud/cloud.cfg` 和 `/var/log/cloud-init.log`。这一条决定了阶段 2 的顺序。

## 阶段 1 · 预置镜像

放到**与要动的盘无关**的存储上。dut02 用独立 eMMC 的 EDA-DIAG 分区：

```bash
sudo mount /dev/mmcblk0p2 /mnt/eda && sudo mkdir -p /mnt/eda/sonic-staging
scp sonic-xxx.bin admin@<DUT-MGMT-IP>:/mnt/eda/sonic-staging/
ssh … 'sha1sum /mnt/eda/sonic-staging/*.bin'      # 两端对
```

好处有二：缩容和装机全程不碰它；日后镜像被 `sonic-installer` 淘汰时可零代价恢复。⚠️ 每次重启后需重新 `mount /dev/mmcblk0p2 /mnt/eda`。

## 阶段 2 · 缩容 + 双启动（一次 ONIE 会话内完成）

**顺序是死的：缩容和装机必须在同一次 ONIE 会话里做完，中间不能重启回原系统。** 否则 `growpart` 会在那次重启时把分区扩回去，缩容白做（非破坏性，只是白做）。让新分区紧挨着旧分区建出来，**物理堵死 growpart 的可扩展空间**。

```bash
# 从原系统一次性进 ONIE
sudo grub-editenv /grub/grubenv set next_entry=ONIE && sudo reboot

# ONIE rescue：root 空密码 SSH 到同一个 mgmt IP
export PATH=/usr/sbin:/sbin:/usr/bin:/bin
grep sda3 /proc/mounts || echo "sda3 未挂载，可以动"
e2fsck -fy /dev/sda3
resize2fs /dev/sda3 2621440                    # 2621440 × 4K = 10 GiB
sgdisk -d 3 /dev/sda
sgdisk -n 3:788480:21762047 -t 3:8300 -c 3:UBUNTU-NOS -u 3:<sda3-PARTUUID> /dev/sda
partprobe /dev/sda
```

**`sgdisk -n` 的四个参数一个都不能省**：起始扇区（必须与原值一致）、分区名、分区类型、PARTUUID。删了再建等于换了个新分区，任何按 PARTUUID 寻址的东西都会断。dut02 的引导链全按 **LABEL** 寻址（`/EFI/debian/grub.cfg` → `search --label` → `root=LABEL=UBUNTU-NOS`），而 `resize2fs` 保留文件系统 label，所以不受影响——**但这是这台机器的性质，不是普遍规律，动手前先确认目标机按什么寻址。**

验证（四项全过再往下走）：

```bash
sgdisk -v /dev/sda                                              # GPT 自检
sgdisk -i 3 /dev/sda | grep -iE "unique GUID|name|First sector" # 三个标识符逐项对
blkid /dev/sda3                                                 # LABEL/UUID 还在
e2fsck -fn /dev/sda3                                            # 只读复检
```

## 阶段 3 · 装机

```bash
mount /dev/mmcblk0p2 /mnt/eda
sha1sum /mnt/eda/sonic-staging/sonic-xxx.bin        # 装前最后一次校验
onie-nos-install /mnt/eda/sonic-staging/sonic-xxx.bin
```

装完自动重启进新系统。**立刻做三项检查**：

```bash
sudo sgdisk -p /dev/sda | grep -E "^ *[0-9]"        # ① sda3↔sda4 之间没有空隙(方案成立的唯一判据)
sudo dumpe2fs -h /dev/sda3 | grep -i "Filesystem state"   # ② 原系统 fs 干净
sudo efibootmgr                                      # ③ 原系统的 EFI 项还在吗
```

③ 大概率**不在了**（见层 0 的告警）。重建并重排：

```bash
sudo efibootmgr -c -d /dev/sda -p 1 -L "UBUNTU-NOS" -l "\\EFI\\UBUNTU-NOS\\grubx64.efi"
sudo efibootmgr -o 0006,0000,0004,0005,0001,0002,0003      # 新 NOS 优先，原系统次之
```

**真机验证原系统还能起来**（这是"非破坏"唯一的证明，不能只看分区表）：

```bash
sudo efibootmgr -n 0000 && sudo reboot
```

然后**盯 console** 看它到底进了哪。这一步实测就抓到过"设了 Ubuntu 却落进 ONIE"——残留 `onie_entry` 导致，静态分析看不出来。进去之后确认 `growpart` 确实被堵死：

```bash
sudo sgdisk -p /dev/sda | tail -4                   # 分区仍是 10G
sudo dumpe2fs -h /dev/sda3 | grep "Block count"     # fs 仍是 2621440
sudo grep -iE "growpart|resize" /var/log/cloud-init.log | tail
# 期望：cc_resizefs 确实运行了，但 resize2fs 是空操作
```

## 阶段 4 · 传自建镜像（高时延链路）

单流 scp 在 373 ms RTT + 丢包的路径上会被打崩（突发 2.6 MB/s，持续降到 0.25 MB/s，2 GB 要 1–2 小时）。**并行 4 流 + 每片独立重试 + 按大小做断点判定**，聚合 ~3.8 MB/s，2 GB 约 30 分钟：

```bash
split -d -b 548M target/sonic-broadcom.bin ~/rparts/rpart-

push(){ local f=$1 sz=$(stat -c%s ~/rparts/$f)
  for t in 1 2 3 4 5 6; do
    have=$(ssh $H "stat -c%s /host/staging/$f 2>/dev/null"); have=${have:-0}
    [ "$have" -ge "$sz" ] && { echo "$f DONE"; return 0; }   # 已完成的片不重传
    scp $SSHOPT ~/rparts/$f $H:/host/staging/$f && return 0
    sleep 4
  done; return 1; }

for f in rpart-00 rpart-01 rpart-02 rpart-03; do push $f & done; wait
ssh $H 'cd /host/staging && cat rpart-0{0,1,2,3} > image.bin && rm -f rpart-* && sha1sum image.bin'
```

`SSHOPT` 里 `ServerAliveInterval=15 ServerAliveCountMax=8` 是必需的，否则卡死的流不会被判定失败。反向（交换机→构建机）更慢，用 `ssh + dd skip_bytes` 续传：

```bash
HAVE=$(stat -c%s "$LOCAL"); ssh $H "dd if=$REMOTE bs=1M skip=$HAVE iflag=skip_bytes" >> "$LOCAL"
```

## 阶段 5 · 装第二个 SONiC 镜像

```bash
sudo sonic-installer list                        # ⚠ 先确认将被淘汰的是哪一个
df -h /host                                      # 空间够吗
yes | sudo sonic-installer install /host/staging/image.bin
sudo sonic-installer list                        # 两镜像共存，Next=新的
sudo reboot
```

三个已知失败点：

- **只保留两个镜像**，装第三个时最旧的非当前镜像**静默消失**（源码原因见层 3）。dut02 上就这么把官方对照镜像连同 GRUB 项一起弄丢了——因为 `.bin` 还暂存在 eMMC 上才零代价恢复。
- **悬空的 `/etc/resolv.conf` 会让安装在 `migrate_sonic_packages` 阶段失败**，该阶段要 `cp /etc/resolv.conf` 进新镜像的 chroot。
- `sonic-installer install` 会把 `/etc/sonic` 复制到 `/host/old_config`，新镜像首启自动迁移——**所以做 A/B 对比时配置一致性是天然的**，这是个可以主动利用的性质。

回滚：`sudo sonic-installer set-default <旧版本>` + reboot。

## 阶段 6 · 验收

```bash
sudo sonic-installer list | grep Current
uname -r; grep VERSION= /etc/os-release          # 确认真的是新镜像在跑
show interfaces status | head
sudo docker ps --format '{{.Names}}' | wc -l
show system-health detail | grep -A2 Services    # 用这个，不要去数 grep -c OK
```

判 ASIC 起没起（Broadcom）：`bcmcmd "cancun stat"` 看 CIH/CMH/CCH/CEH/CFH 是否 `LOADED`；`redis-cli -n 1 keys "ASIC_STATE:SAI_OBJECT_TYPE_PORT:*" | wc -l` 看端口对象。

**跨镜像取证的坑**：`/var/log` 是 loop 挂载、**跨镜像共享**的文件系统，`syslog`/`audit.log` 的历史计数不能作为"当前这个镜像"的证据。

---

## 附录 · 证据来源

- 操作会话：`~/.claude/projects/-home-sheldon-qi-sonic-buildimage/3a4812fc-94ff-4203-b4c4-fae5331ca491.jsonl`（2026-07-26 02:33 → 07-27 14:17，423 次 Bash 调用）；前传崩溃会话 `c44da5c8-…`
- grub 生成逻辑：`installer/default_platform.conf:465-639`（入口 cfg `567-579`、三变量 `521-537`、双镜像 `552-555`、ONIE 片段 `608-611`、resolute 内核路径 `599/604`）
- ONIE 模式机：目标机 `sda2` 的 `/grub/grub.cfg:175-230` 与 `onie/tools/`
- 相关记忆：`lab-switch-onie-install-official-202605`、`lab-switch-10-240-36-51-provenance`、`resolute-lab-switch-sai-swap-incident`
