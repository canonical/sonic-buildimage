# Dell S5232F 上验证自建 resolute SONiC、修复 FRR 构建缺陷、并配置为 fabric 节点

**日期**：2026-07-26
**目标设备**：`<DUT-MGMT-IP>`（Dell EMC S5232F-ON，BCM56873 / Trident3，platform `x86_64-dellemc_s5232f_c3538-r0`）
**约束**：这是别人（Henry Mao / Canonical，经 cloud-init + PPA `henrymao/ubuntu-nos` 部署）维护的实验机，全程只做非破坏性操作、并对维护者原系统留有回滚路径。

---

## 0. 背景与核心问题

延续一个此前因上下文超限而崩溃的会话（`c44da5c8`）。用户最初的核心追问是：

> **本地构建出的 `sonic-broadcom.bin` 到底能不能在这块硬件上跑起来。**

围绕这个问题，本次实际走完了一条完整链路：CANCUN 前置调研 → 官方镜像对照实验 → 缩容双启动保全维护者系统 → 装官方镜像取得答案 → 装自建镜像正式回答 → 修复 resolute 的 FRR 构建缺陷 → 用**两种方法**把 dut02 配成带完整策略的 fabric 节点。

**最终结论**：能。自建 resolute SONiC 在这块 S5232F 上完整跑起来，ASIC 初始化、硬件转发、BGP 全部正常。

---

## 0.5 前传 — 崩溃会话（c44da5c8）中已完成的有意义工作

本次是该会话的延续。它在崩溃前已完成以下有价值的工作，也直接塑造了本次的谨慎路线：

1. **现状调研** —— 判定 `<DUT-MGMT-IP>` 是一台"半 SONiC"的**裸 .deb 部署**：Ubuntu 26.04 Resolute + kernel 7.0.0-1002-sonic + libsaibcm 11.2.30.5 + opennsl 8.4 + sswsyncd + switchdevd + BIRD 3.2.0 运行中，但**没有 Docker / /etc/sonic / sonic-cfggen / CLI**。不是 ONIE 安装，而是 cloud-init + `firstboot.sh` + PPA `henrymao/ubuntu-nos`。

2. **首次兼容性分析** —— 自建 sonic-broadcom.bin vs S5232F：平台 `x86_64-dellemc_s5232f_c3538-r0` 在 installer 的 `platforms_asic` 里、ASIC 是 TD3、`sai.profile` 引用 `td3-s5232f-32x100G.config.bcm`、kernel/OS 一致；版本增量 libsaibcm 15.2↔11.2、opennsl 15.2↔8.4、platform-modules 1.1↔1.8.1。得出初步结论"可以运行"——但当时只是**静态分析，未真机验证**（本次 §5/§6 才真机坐实）。

3. **增量 SAI 测试 → 交换面事故（关键教训）** —— 为了"不重装就验证硬件兼容"，在**运行中的维护者交换机**上直接装了自建的 opennsl 15.2 + libsaibcm 15.2 内核模块。opennsl 15.2 kmod 本身工作（PCI `14e4:b870` probe、`/proc/bcm/knet` 齐全），但 SAI 三件套版本错配（15.2 lib + 不配套的 kmod/config）**把整个交换面搞断了**——前面板口消失、PortChannel200 NO-CARRIER、`CANCUN CIH: LOAD FAILED`。**这次事故直接塑造了本次的谨慎路线**（不碰运行系统、先做官方镜像对照实验、缩容双启动保全维护者系统），它暴露的 CANCUN 失败也是本次 §2 CANCUN 调研的起点。

4. **恢复** —— 从磁盘找回原始 .deb（`/usr/share/sonic/platform/bcm/*.deb`），restore libsaibcm 11.2 + opennsl 8.4；SAI 初始化失败留下的 hostif 残留只有 reboot 能清。

5. **provenance 调研** —— 摸清机器来历（cloud-init + `firstboot.sh` 读 `/etc/machine.conf` + PPA 装 6 个包；libsaibcm 不在任何 repo、只在磁盘 .deb；⚠️ `/usr/sbin/switchdevd` 是维护者手工放的自建二进制，绝不能 `apt reinstall`）。

6. **配置抓取 + BIRD→FRR 迁移** —— 抓取维护者完整配置（拓扑、BIRD、PortChannel200、BGP），并把 BIRD 3.2.0 迁到 FRR 10.5.1（1:1 复刻，含 `sender-as-path-loop-detection`、`krt_prefsrc`→`set src`、`redistribute connected` 路由图等语义对照）。**这份 BIRD/FRR 配置成为本次 §8 fabric 复现的权威源。**

> 教训（已入记忆 `resolute-lab-switch-sai-swap-incident`）：碰别人的机器前先回答 ① 系统怎么装的 ② 每个包从哪来 ③ 回滚物证在哪；Broadcom SAI 换版本必须 libsaibcm + opennsl + platform-modules **整套一起换**；先翻磁盘再翻 repo；SAI 初始化失败后 reboot 是必要的。

---

## 1. 结果总览

| 阶段 | 结果 |
|---|---|
| CANCUN config.bcm 调研 | 上游 stale bug，全新安装下 `/default/` 兜底生效，无害；23 个 TD3 文件受影响，与我们分支字节一致 |
| 官方 202605 对照实验 | `CANCUN CIH: LOADED 6.15.00`、create_switch OK、4 口 link up |
| 缩容 + 双启动（方案 A） | sda3 缩到 10G，sda4 装 SONiC 堵死 cloud-init growpart；维护者 Ubuntu 真机启动+健康 |
| 自建 resolute 镜像 | 启动成功、CANCUN 同官方、4 口 up、ASIC 35 port 对象 —— **核心问题=能** |
| FRR 构建缺陷修复 | `dplane_fpm_sonic.so` 缺失 → zebra 崩 → 修复重建 → BGP 通、ASIC 215 路由 |
| fabric 复现（config_db.json） | BGP v4 136 / v6 73 Established、硬件转发 |
| 配置为 T0（minigraph） | type=ToRRouter、peerT1=LeafRouter、BGP 136/72、角色策略、ASIC 214 路由 |

---

## 2. 前置调研：CANCUN config.bcm 的上游 stale bug

**现象/风险**：TD3 平台的 `device/*/td3-*.config.bcm` 第 1 行硬编码
`sai_load_hw_config=/etc/bcm/flex/bcm56870_a0_premium_issu/b870.6.4.1/`（SAI 11.2 时代的 CANCUN 版本），
而 `libsaibcm 15.2` 只带 `b870.6.15.0/`。

**机制**（2026-07-25 事故日志实测，SAI 15.2 / SDK 6.5.35 读 6.4.1 文件）：
```
CIH: LOAD FAILED   Ver: UNKONWN.00.00.00     ← parser 镜像严格绑 SDK 版本
CMH/CCH/CEH: LOADED  Ver: 06.04.01           ← 其余组件容忍跨版本
→ soc_mem_write: invalid index 6 for IP_PARSER1_HFE_CONT_PROFILE_TABLE_4
→ bcm_esw_port_init: Entry not found → Failed to create switch
```

**判定**：
- 全树 **23 个** TD3 `config.bcm` 都指向 `b870.6.4.1`，与 `sonic-net/master`、`sonic-net/202605`、`canonical/*` **字节一致** —— 纯上游遗留，非我们分支引入。
- `libsaibcm` 把 `/etc/bcm/flex/**/*.pkg` 登记为 **dpkg conffiles**（升级不删）。这是**裸 .deb 部署模型**（那台被维护的机器）独有的暴露面：旧 6.4.1 文件原地留存被优先加载。
- SONiC 正常镜像里 syncd 容器每次从零构建，容器内只有 `b870.6.15.0` + `default` 软链；config 指向不存在的 6.4.1 时，libsai.so 的兜底串 `Cancun files are not available at "%s", loading default` 会截掉版本段回退到 `default/` → 6.15.0 → CIH 匹配 → 能起来。

这条判断在第 4/5 阶段被真机确证（见下）。

---

## 3. 对照实验准备：官方 202605 镜像

思路：官方 202605 与我们用**同一个 SAI 15.2 pin、同一份字节一致的 stale config.bcm**，所以它在这块硬件上的表现直接判定 CANCUN 兜底是否真生效——这是我们刷自己镜像**之前**的对照实验。

- **来源**：Azure DevOps `dev.azure.com/mssonic` 流水线 id=138（`Azure.sonic-buildimage.official.broadcom`），分支 202605 最新成功构建 `20260725.6`，commit `ec1bb42e41`，SAI pin `15.2.0.0.0.0.11.1`（比我们的 `3.1` 新 8 个 patch，但 CANCUN 载荷逐字节相同）。
- **单文件下载**：downloadUrl 自带 `format=zip`，须重建 URL 用 `format=file&subPath=/target/sonic-broadcom.bin`（subPath 里斜杠别编码）。1.08GB，installer 自带 payload sha1 自检通过。
- **console 通路**：`<CONSOLE-SERVER>` 是 **telnet 协议 + 两级登录** —— 先 console server 认证 `<user>/<CONSOLE-PW>`（认证后打 "Type the hot key to suspend...<CTRL>Z" 横幅），再接到交换机 getty `<user>/<PW>`。驱动脚本 `~/console.py`（处理 telnet IAC、CR-only 换行、`watch`/`login` 模式）。⚠️ console server 单会话。
- **BMC**：`<BMC-IP>` IPMI v2 RAKP 握手失败（不可用，但主线不依赖它——所有 reboot 都能从 OS/ONIE 内部发起，console + GRUB 兜底）。
- **ONIE**：UEFI 有独立 `Boot0004 = ONIE` 项；ONIE grubenv `onie_nos_mode=yes` → 默认菜单是 Rescue（不自动网络装）。ONIE 3.40.1.1-9，kernel 4.9.30-onie+，rescue 起 dropbear（root 空密码）+ udhcpc。

---

## 4. 缩容 + 双启动（方案 A）：保全维护者的 Ubuntu

硬盘 sda（59.6G）被 sda1(256M)+sda2(128M)+sda3(59.3G) 占满，装 SONiC 需要 32G 空闲。选择**不擦维护者的 Ubuntu**，而是缩容 + 双启动。

**踩到的坑**：维护者 Ubuntu 是 cloud-init 部署，`/etc/cloud/cloud.cfg` 有 `growpart` + `resizefs`（`frequency: always`）——**每次启动都把 sda3 扩回填满整盘**。所以"缩容 → 重启回 Ubuntu 验证 → 再装"的顺序行不通。

**规避（方案 A，不改维护者配置）**：一次 ONIE 会话里缩容 + 立即装 SONiC，让 sda4 紧挨 sda3 之后建出来，**物理堵死 growpart 的可扩展空间**。

**缩容手法**（ONIE rescue，SSH `root@<DUT-MGMT-IP>` 空密码，工具在 `/usr/sbin` 但 PATH 只 `/usr/bin:/bin`，须显式 export）：
```
e2fsck -fy /dev/sda3
resize2fs /dev/sda3 2621440          # 2621440 × 4K = 10 GiB
sgdisk -d 3 /dev/sda
sgdisk -n 3:788480:21762047 -t 3:8300 -c 3:UBUNTU-NOS \
       -u 3:<sda3-PARTUUID> /dev/sda   # 起点/名字/PARTUUID 逐项保留
```
UBUNTU-NOS 引导链全按 **LABEL** 寻址（ESP `/EFI/debian/grub.cfg` → search --label → `/grub/grub.cfg` → `root=LABEL=UBUNTU-NOS`），resize2fs 保留 label，故不受影响。

**备份不可再生物**（约 57MB）：`/usr/sbin/switchdevd`（维护者手工放的自建二进制，PPA 里找不回）、`libsaibcm 11.2.30.5 .deb`（不在任何 repo，只在磁盘）、全部配置。落本地 `~/dut02-backup/` + EDA-DIAG。

**验证（真机 test-boot）**：cloud-init 的 `cc_resizefs` **确实运行了**但 `resize2fs` 是空操作（fs 已填满 10G 分区，growpart 因 sda4 挡着扩不动）→ sda3 仍 10G。Ubuntu 干净启动到登录、switchdevd/frr active、PortChannel200 UP、BGP 恢复。**growpart 被 sda4 实测堵死。**

**EFI 修复**：onie-nos-install 抹掉了 `UBUNTU-NOS` 的 EFI 启动项，已用 `efibootmgr` 重建（指向原始 `\EFI\UBUNTU-NOS\grubx64.efi`），BootOrder 设 SONiC 优先、Ubuntu 次之。

**最终分区布局**：
```
sda1 EFI System   256M
sda2 ONIE-BOOT    128M
sda3 UBUNTU-NOS   10G   ← 维护者系统，缩容后完好、可启动
sda4 SONiC-OS     32G   ← 紧挨 sda3，堵死 growpart
（尾部 ~17G 未分配；mmcblk0 = 独立 eMMC EDA-DIAG，不受影响）
```

---

## 5. 装官方镜像 → CANCUN 真机答案

`onie-nos-install /mnt/eda/sonic-staging/sonic-broadcom-202605-20260725.6.bin` → 首启：

```
UNIT0 CANCUN:  CIH/CMH/CCH/CEH/CFH: LOADED  Ver: 06.15.00  SDK Ver: 06.05.35
```

- config.bcm 写死 `b870.6.4.1` 但 SDK 实际加载 **6.15.00**（=default→6.15.0），**CIH LOADED**（非 FAILED）。
- create_switch 成功（ASIC_DB 1 SWITCH + 35 PORT 对象），4 个前面板口 link up，syncd 0 重启。
- **确证**：上游 stale config.bcm 在**全新安装**场景完全无害，兜底真实生效。之前实验机搞断是**增量换 .deb**场景（旧 6.4.1 conffiles 残留被优先加载）。
- 官方镜像与我们自建的 CANCUN 载荷逐字节相同 → 我们镜像的 ASIC 初始化行为与官方一致（此轴排除风险）。

---

## 6. 装自建 resolute 镜像（核心问题的正式回答）

- **制品**：`target/sonic-broadcom.bin`（2.19GB，SAI `15.2.0.0.0.0.3.1`，sha1 `c8968708...`），payload 自检通过。
- **传输**：这条 mgmt 路径高 RTT（373ms）+ 丢包，单流 scp 会被打崩（突发 2.6MB/s，持续降到 0.25MB/s）。**解法=并行 4 流**：本地 `split -d -b 548M` 切 4 片、4 路 scp 并行（各带重试）→ 远端 `cat` 拼接 + sha1 校验。聚合 ~3.8MB/s，2GB 约 30 分钟（单流要 1-2 小时）。
- **安装**：`sonic-installer install` 作为**第二镜像**装入（与官方共存 `/host`，`Next` 自动指向新镜像；回滚 = `sonic-installer set-default <官方>`；secure boot 未强制）。
- **启动验证**（切入自建镜像后）：
  - `Current: SONiC-OS-202605_resolute_sheldon.0-1d988dec`，**Ubuntu 26.04 LTS Resolute Raccoon**，kernel **7.0.0-1002-sonic**（区别于官方 Debian 6.12.41）。
  - `cancun stat` = CIH/CMH/CCH/CEH/CFH **LOADED 06.15.00 SDK 6.5.35**（与官方一致）。
  - create_switch OK（ASIC_DB 1 SWITCH + 35 PORT），CONFIG_DB 34 口，4 前面板口 link up，syncd 0 重启，hwsku `DellEMC-S5232f-C32`。

**→ 原始核心问题「自建 sonic-broadcom 能否在该硬件跑」= 能，真机实证。** 自建与官方唯一差异是 OS 基底（Ubuntu resolute vs Debian trixie）+ 内核，ASIC/CANCUN 行为无差异。

---

## 7. 修复 resolute 的 FRR 构建缺陷（dplane_fpm_sonic 缺失）

灌 fabric 配置时暴露：**自建 resolute 镜像的 BGP 整体起不来**。

**症状**：bgp 容器 `Exited`，容器内 zebra 反复 `exit status 1`：
```
zebra frr_init: loader error: dlopen(dplane_fpm_sonic):
  /usr/lib/x86_64-linux-gnu/frr/modules/zebra_dplane_fpm_sonic.so: cannot open shared object file
```
zebra 被 SONiC 以 `-M dplane_fpm_sonic` 无条件启动，模块缺失即崩。**与 config 无关**（默认 sample 配置一样崩）。

**根因**（逐层验证，非最初推测的链接失败）：
- Jul 24 那版 `frr_10.5.4-sonic-0_amd64.deb` 用的是**旧 dget+quilt 构建流程**（`dget -u frr_10.5.1.dsc` + `QUILT_PATCHES=../patch quilt push -a || true`）——`|| true` **静默吞掉了 patch 0012 应用失败**（该 patch 改 `zebra/subdir.am`，在 Ubuntu stock 10.5.1 源上 hunk 不匹配）。规则没进 subdir.am → autoreconf 生成的 Makefile 无 target → 模块从没编 → deb 缺它（`dh_install` glob 匹配空也不报错）。
- **当前 Makefile 已换成 stg + submodule 流程**（`pushd ./frr` + `stg import -s ../patch/series`，patch 失败硬报错），修复已在仓库里，Jul 24 的 deb 只是旧流程的陈旧产物。

**修复动作**：
```
rm -f target/debs/resolute/frr*.deb
make SONIC_DPKG_CACHE_METHOD=none BLDENV=resolute \
     target/debs/resolute/frr_10.5.4-sonic-0_amd64.deb   # cache off 防吃回旧 deb
# → 新 deb 有 dplane_fpm_sonic.so（96848B）
make SONIC_DPKG_CACHE_METHOD=none BLDENV=resolute target/docker-fpm-frr.gz
# 交换机上部署（不做全镜像重装）：
docker load -i docker-fpm-frr-new.gz
docker tag docker-fpm-frr:latest docker-fpm-frr:202605_resolute_sheldon.0-1d988dec
docker rm -f bgp; systemctl reset-failed bgp; systemctl start bgp
```

**验证**：zebra RUNNING 不崩、FPM `127.0.0.1:2620` ESTABLISHED、BGP v4/v6 Established、内核 FIB 133 条（带 `nhid` + `src=loopback`）、APPL_DB ROUTE_TABLE 209、**ASIC_DB ROUTE_ENTRY 215**（硬件转发通）。

**上游可提项**：给 `sonic-frr` 的 `dh_install` 缺模块加硬失败（治本，防今后再静默漏模块）——虽然 stg 流程已堵住这个具体的洞。

---

## 8. 配置为 fabric 节点 —— 两种方法

维护者原系统跑的是**无策略的裸 eBGP**（BIRD `import all/export all` → 上个 session 已迁 FRR）。权威源：`/etc/bird/bird.conf` + 已验证的 `/etc/frr/frr.conf` + `/etc/netplan/90-nos.yaml`（均在 `~/dut02-backup/` 备份里）。

关键参数：AS 65202、router-id/Loopback0 `<LOOPBACK-V4>`（v6 `2001:db8::af0:fed4/128`）、PortChannel200（Ethernet0+Ethernet4，802.3ad fast）`192.0.2.1/31` + `2001:db8::ac10:1/127`、BGP 邻居 `192.0.2.0` / `2001:db8::ac10:0`（均 AS65201）。基线 BGP v4 136 / v6 73。

### 方法 ① — config_db.json 直接写

- 从交换机默认 config 增量合并：替换 sample 占位（ARISTA T2 邻居 / 10.0.0.x / asn 65100），保留 hwsku-正确的 34 口 PORT/BREAKOUT，加真实的 DEVICE_METADATA(LeafRouter, 65202)、Loopback、PortChannel200、BGP 邻居。
- 修正 2 点（对抗式复核建议）：加 `bgp_adv_lo_prefix_as_128=true`（v6 loopback 以 /128 通告）、`nhopself`/`rrclient` 引号化。
- **对抗式复核**（3 维 workflow：源一致性 / SONiC schema / fabric 安全）：0 blocker，5 warning 全 SAFE_TO_APPLY。确认无路由泄漏（LeafRouter 默认不 redistribute connected/kernel、不发默认路由）、无 MGMT_INTERFACE 不断 SSH。
- `config reload` → **BGP v4 136 / v6 73 Established**、PortChannel200 LACP 与 peerT1 协商、内核 FIB + **ASIC_DB 215 路由**（硬件转发）。

### 方法 ② — minigraph.xml（配成 T0）

目标：把 dut02 语义上建模成正经 SONiC **T0 (ToRRouter)** 节点、跑标准角色策略。

- 写 `dut02-minigraph.xml`（单上行、无服务器 VLAN、peerT1 标为上游 LeafRouter、deployment_id=1）。
- **踩坑：`config load_minigraph` 崩在 `config qos reload`**：`sort_by_port_index` 的 `int(k[8:])` 遇到端口别名 `hundredGigE1/1` → `ValueError`。
- **根因**（逐层挖到底）：
  1. `config load_minigraph`（sonic-utilities `config/main.py:2427`）调 `sonic-cfggen -H -m`——**没带 `-k`**（且 `-m`/`-k` argparse 互斥，`-H`=`--platform-info` 只读平台信息不设 hwsku）→ `args.hwsku=None`。
  2. → `portconfig.get_port_config()` 在 `port_config_file=None` 时**从运行 CONFIG_DB 读 PORT 表建别名映射**（不读 port_config.ini 文件）。
  3. → **致命分歧**：`port_config.ini` 里别名是 `hundredGigE1/1`，而 CONFIG_DB / platform.json（默认配置生成用的）是 **`etp1`**。我 minigraph 用了文件的 `hundredGigE1/1`，load_minigraph 从 CONFIG_DB 拿到的映射表是 `{etp1→Ethernet0}` → 匹配不上 → DEVICE_NEIGHBOR 留了别名 → qos 排序崩。（离线 `sonic-cfggen -m mg.xml -p port_config.ini` 读**文件**别名 hundredGigE1/1 所以能映射，掩盖了分歧。）
- **修复**：minigraph 改用设备实际别名 `etp1/etp2`（`-H -m` 实测映射正确）。
- **次生坑**：load_minigraph 给 100G 口生成了 `fec: rs`，但 peerT1 那侧链路需要**无 FEC** → Ethernet0/4 `oper=down`、LACP Dw、BGP 卡 Active。`config interface fec Ethernet0/4 none` 修好（可用基线里 Ethernet0 无 fec 字段，用硬件默认）。
- **结果**：`config load_minigraph` 无 qos crash，dut02 = type=ToRRouter、deployment_id=1、peerT1=LeafRouter、PortChannel200 LACP Up、BGP v4 136 / v6 72 Established、角色策略生效（peer-group PEER_V4/V6 + route-map FROM/TO_BGP_PEER + `allowas-in 1` + `ALLOW_LIST_DEPLOYMENT_ID`）、`bgp_adv_lo_prefix_as_128=true`、ASIC 214 路由。constants.yml 保持默认（标准角色策略，已含完整 community 方案，未改）。

### 两种方法的关系

两条路最终**产出的都是一份 config_db 喂给 SONiC**——minigraph 只是多了"拓扑 XML → config_db"这层转换（`sonic-cfggen -m`）。minigraph 的 XML schema 命名空间是 `Microsoft.Search.Autopilot.Evolution`，本质是 Azure 内部部署系统吐出的拓扑格式，**设计给编排系统「生成」、不是给人手写**——这解释了为何手写它一路踩坑，而直接写 config_db.json 一把过。SONiC 生态的方向是往 config_db + YANG 收敛，但 minigraph 仍是一等公民（测试床 sonic-mgmt / Azure 生产大量使用）。

---

## 9. 关键产物与当前状态

**交换机当前跑**：方法 ②（T0 minigraph 配置）。

**回滚点**：
- `/etc/sonic/config_db.json.fabric-working` —— 方法 ① 的 LeafRouter fabric config（`config reload` 即切回）
- `/etc/sonic/minigraph.xml` —— 方法 ② 的 T0 minigraph
- `/etc/sonic/config_db.json.bak-sample` —— 装机初的默认 sample
- `sonic-installer set-default SONiC-OS-202605.1174613-ec1bb42e4` —— 切回官方镜像
- BootOrder 里 UBUNTU-NOS / ONIE / EDA-DIAG 都在 —— 可切回维护者 Ubuntu 或 ONIE

**本地产物**：
- `~/console.py` —— console server 两级登录 + telnet IAC 驱动
- `~/dut02-minigraph.xml` —— T0 minigraph（etp1 修复版）
- `~/dut02-backup/` —— 维护者不可再生物备份（switchdevd、libsaibcm 11.2 .deb、配置）
- `~/sonic-official-202605/` —— 官方对照镜像
- `target/debs/resolute/frr_10.5.4-sonic-0_amd64.deb` —— **已修复**（含 dplane_fpm_sonic.so）
- `target/docker-fpm-frr.gz` —— **已修复**的 bgp docker

**写入的记忆**（`.claude/.../memory/`）：`sonic-resolute-td3-cancun-config-stale`、`lab-switch-onie-install-official-202605`、`resolute-frr-dplane-fpm-sonic-missing`、`sonic-load-minigraph-alias-mismatch-crash`；并更新了 `resolute-lab-switch-sai-swap-incident`。

---

## 10. 可提上游 / 待办

1. **TD3 config.bcm stale CANCUN**：23 个文件的 `sai_load_hw_config` 改用 `.../default/`（免疫未来 SAI bump）；删掉 `#18505` 内联进来的多余 `/usr/lib/cancun/` 行（syncd 里根本没有该目录）。
2. **sonic-frr `dh_install` fail-missing**：缺模块加硬失败，防今后静默漏模块。
3. **load_minigraph 端口别名分歧**：治本要么让 `config load_minigraph` 把 hwsku 传进去让 `get_port_config` 读文件，要么修 DellEMC-S5232f-C32 让 `port_config.ini`（hundredGigE1/1）与 platform.json（etp1）别名一致。
4. **PfxSnt 对标**（可选）：SONiC 默认不加 `sender-as-path-loop-detection`，会把学到的路由回送 peerT1（对端按 AS-path loop 拒收，无害）；要 100% 对标维护者的 2/2 需 custom FRR 注入或改模板。
5. **fec 默认**：load_minigraph 给 100G 口默认 `fec rs`，与该 fabric 链路不符——手写 minigraph 走 load_minigraph 后务必检查 `redis-cli -n 4 hget "PORT|Ethernet0" fec`。
