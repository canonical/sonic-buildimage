# sw1 的 ONIE 判定与迁移到 resolute 的方案

**日期**：2026-09-09
**对象**：`sw1`（`<SW1-MGMT-IP>`，Dell EMC S5232F-ON / TD3，platform `x86_64-dellemc_s5232f_c3538-r0`，lab fabric 节点，AS 65302）
**性质**：**只读勘察 + 方案**。本文没有对 sw1 做任何写操作，磁盘、配置、NVRAM 全未触碰。
**前置阅读**：[ONIE 多引导机制与装机 SOP](2026-09-09-onie-multiboot-and-ubuntu-sonic-install-sop-zh.md)（四层引导模型、`sonic-installer` 陷阱、并行传输手法）

---

## 结论速览

| 问题 | 答案 |
|---|---|
| sw1 是不是 ONIE 装的？ | **是**，而且是标准的教科书式 ONIE 装机 |
| 和 dut02 一样吗？ | **不一样，而且简单得多**。dut02 原本不是 ONIE 装的（cloud-init + PPA 裸 .deb），所以需要缩容 + 双启动；sw1 不需要 |
| 迁移可行吗？ | 可行。平台、空间、DB 迁移链、ONIE 兜底四项已逐一验证 |
| 推荐路径 | `sonic-installer install` 装成**第二镜像**，不走 ONIE 重装 |
| 能直接动手吗？ | **不能**。三个阻断项必须先解决：悬空的 `resolv.conf`、没有 console 恢复路径、设备归属确认 |

---

## 1 · 判定：sw1 是标准 ONIE 装机

七项证据，全部来自本次只读勘察：

| 判据 | sw1 实测 | 含义 |
|---|---|---|
| `/host/machine.conf` | 完整 `onie_*` 变量集：`onie_boot_reason=install`、`onie_version=3.40.1.1-9`、`onie_platform=x86_64-dellemc_s5232f_c3538-r0`、`onie_exec_url=http://<IMG-SRC>:8080/sonic-broadcom.bin` | **决定性证据**——这个文件由 ONIE 装机脚本生成 |
| 分区布局 | `sda1` EFI 256M / `sda2` **ONIE-BOOT** 128M / `sda3` SONiC-OS 32G；尾部 **27.3 GiB 未分配** | 标准 ONIE 布局，且没有第三方 NOS 分区 |
| EFI 引导项 | `Boot0005* SONiC-OS`(BootCurrent) / `Boot0004* ONIE` / `Boot0000* EDA-DIAG` | ONIE 入口健在 |
| `/host/grub/grub.cfg` | `saved_entry`/`next_entry`/`onie_entry` 三变量块齐全 + 三个 menuentry：`SONiC-OS-feat_dhcp-rock.0-b2f3ebaf9`、`EDA-DIAG`、`ONIE` | 层 2 完好，一次性进 ONIE 可用 |
| `/EFI/debian/grub.cfg` | `search --no-floppy --label --set=root SONiC-OS` | 单 NOS，**不存在 dut02 那种入口争抢** |
| 镜像槽 | 只有一个：`/host/image-feat_dhcp-rock.0-b2f3ebaf9`（618 MB） | 第二槽空着 |
| EDA-DIAG | 独立 eMMC `mmcblk0p2`（3.5G，PARTUUID 与 sda 不同） | 可作暂存区，且不受 sda 操作影响 |

**与 dut02 的关键差别**：dut02 上要做缩容 + 双启动，是因为那台机器原本**不是** ONIE 装的——它是别人用 cloud-init + PPA 铺的裸 .deb Ubuntu，整块盘被一个根分区占满，且 cloud-init 的 `growpart` 每次开机把分区扩回去。sw1 完全没有这些：磁盘本来就是 ONIE 分好的，`/host` 里预留了双镜像空间，还有 27.3 GiB 尾部空闲。**SOP 里"阶段 2 缩容 + 双启动"整章对 sw1 不适用。**

---

## 2 · 迁移可行性评估

### 2.1 已验证的绿灯

- **平台匹配**——离线拆自建 `.bin` 的 payload 验到 `x86_64-dellemc_s5232f_c3538-r0` 确实在 `installer/platforms_asic` 里；`device/dell/x86_64-dellemc_s5232f_c3538-r0` 也在 resolute 树内（broadcom 收敛到 dell/XGS 之后仍保留）。
- **同硬件已有真机实证**——dut02 就是 S5232F/TD3，自建 resolute broadcom 镜像在其上完整跑通（CANCUN CIH–CFH `LOADED 06.15.00`、create_switch OK、前面板口 link up）。sw1 与之同型号同 HwSKU（`DellEMC-S5232f-C32`）。
- **空间充足**——`/host` 32G 中 27G 可用；自建镜像 2.03 GiB。第二槽空着，**不会淘汰任何东西**。
- **DB 迁移链完整**——sw1 当前 schema 是 `version_202405_01`，我们的 resolute 是 202605。`db_migrator.py` 的链路逐跳齐全且 `CURRENT_VERSION = 'version_202605_01'`：

  ```
  202405_01 → 202405_02 → 202411_01 → 202411_02 → 202505_01 → 202511_01 → 202605_01
  ```

  逐跳看实际动作，**对这台盒子几乎都是空转**：每跳重复的 `check_has_sonic_dhcpv4_relay_flag()` 分支不成立；`migrate_ipinip_tunnel()`（202405_02）这台没有 IPinIP 隧道；`migrate_ipinip_tunnel_ecn_mode_mellanox()`（202511_01）是 **mellanox-only**，broadcom 不进；真正会动东西的只有 `migrate_flex_counter_delay_status_removal()`（202505_01）。**配置迁移风险低。**
- **ONIE 兜底在**——ONIE 3.40.1.1-9，与 dut02 同版本，rescue 里 dropbear + udhcpc 拿同一个 mgmt IP、root 空密码 SSH 的手法可直接复用（SOP 层 1 有完整清单）。
- **Secure Boot 未启用**——`mokutil --sb-state` 回 "This system doesn't support Secure Boot"，不构成障碍。

### 2.2 阻断项（动手前必须解决）

**① 悬空的 `/etc/resolv.conf` 会让 `sonic-installer install` 失败**

实测：

```
/etc/resolv.conf -> /run/resolvconf/resolv.conf     （目标不存在）
getent hosts archive.ubuntu.com  → rc=2             （DNS 全断）
```

`sonic-installer install` 的 `migrate_sonic_packages` 阶段要把 `/etc/resolv.conf` 复制进新镜像的 chroot，**悬空即失败**——dut02 上原样踩过这个坑。

这不是 sw1 的偶发故障，而是 Ubuntu-port 的**结构性回归**：Ubuntu 归档里没有真正的 `resolvconf` 包（`systemd-resolved` 用 `Provides/Replaces/Conflicts` 占了这个名字），而 SONiC 镜像照旧建那条符号链接。我们的 resolute 已经修了，sw1 跑的 `feat_dhcp-rock` 构建没有。**所以这个坑在装机前必须手工绕过，装完之后由新镜像自己解决。**

**② 没有 console 恢复路径**

dut02 有 console server（`<CONSOLE-SERVER>:7011`，两级登录）。**sw1 没有已知的端口映射**——该 console server 地址本身 ping 得通，但对应 sw1 的端口未知。

这条不是形式主义：360 ms 高延迟远程装机，一旦新镜像不起、或起来了但 mgmt 口没配上，**没有 console 就只能靠人到现场**。ONIE rescue 是半张网（它能 DHCP 到同一个 mgmt IP，dut02 实证），但前提是还能进到 ONIE。**必须先落实 console，再动手。**

**③ 设备归属未确认**

这是别人的**活跃** lab 设备：9/4 有人跑过 `config save` 并重启（当前 uptime 5 天，config_db mtime `2026-09-04 10:01:45` 与之吻合），9/8 有来自另一网段的 admin 登录。迁移会换掉整个 OS，**需要 owner 明确同意**。

### 2.3 风险（不阻断，但要写进验收基线）

- **配置缺陷会原样带过去。** sw1 的 `config_db.json` 有若干已实测确认的缺陷：Po205 把八个口收进一个 LAG（规划是四个 leaf 各两口）、Po204–208 的 v6 地址掉了一位（`ac1:` 应为 `ac11:`）、j18/j19 两条邻居行本身写错。**迁移不是修这些的时机**——一次只改一个变量。但由此推出一条硬约束：**验收基线必须用"迁移前实测值"，不能用规划值**，否则会把陈年配置缺陷误判成迁移引入的回归。
- **迁移前的基线本身就是残缺的**（这反而降低风险）：v4 11 个 peer / **4 个 Established**，v6 6 个 peer，**73** 条 ASIC 路由，12 个容器。北向不通——`agg-sw1` / `agg-sw2` 两个上行 peer 都停在 `Active`，上行口光功率呈对称残缺（每个上行 LAG 一口有光一口全黑），且已用 A/B 实测排除 FEC 因素、判定问题在对端。**这台目前没有在承载南北向流量。**
- **`config_db.json.save` 不是回滚点**——那是 18 257 字节的出厂样例（`hostname: sonic` / `bgp_asn: 65100`）。真正的正本是 `/etc/sonic/config_db.json`，46 610 字节，mtime `2026-09-04 10:01:45`。
- **两镜像上限**——装完就满了。此后再装第三个镜像会**静默淘汰**最旧的非当前镜像（机制见 SOP 层 3）。
- **⚠️ 原镜像没有可用的重装源。** 机器上**没有任何 `.bin` 残留**；`machine.conf` 记的 `onie_exec_url` 指向 `http://<IMG-SRC>:8080/sonic-broadcom.bin`，该主机 ping 得通但 **8080 端口 10 秒内无响应**；同批的 sw2 当前 SSH 连不上，暂时不能当备份源。**这意味着"ONIE 重装回原样"这条最后的退路目前是断的**——缓解办法见 §4 阶段 0。

---

## 3 · 推荐方案：第二镜像并存

**用 `sonic-installer install`，不要用 `onie-nos-install`。**

| | `sonic-installer install`（推荐） | `onie-nos-install` |
|---|---|---|
| 对现有镜像 | 保留，作为一键回滚 | **重建 SONiC-OS 分区，全抹** |
| 对配置 | 自动 `cp /etc/sonic` → `/host/old_config`，新镜像首启迁移 | 丢失 |
| 对 EFI 项 | 不动 | 会动（dut02 上抹掉过别的 NOS 的项） |
| 回滚 | `set-default` + reboot，一条命令 | 需要原 `.bin`——**目前没有** |
| 当前是否可行 | 第二槽空着，不淘汰任何东西 | 可行但不可逆 |

在原镜像重装源已断（§2.3）的前提下，**保住现有镜像槽是唯一的回滚保障**，这一条本身就否决了 ONIE 重装路线。

---

## 4 · 执行步骤

### 阶段 0 · 前置（不满足就不要开始）

1. **落实 console** —— 拿到 sw1 的 console server 端口并**实测登录一次**。这是唯一能在新镜像不起时看到 grub 菜单的手段。
2. **拿到 owner 同意** —— 明确迁移窗口和"可以重启几次"。
3. **备份现有镜像目录**（缓解 §2.3 的重装源断链）——只有 618 MB，本地和 EDA-DIAG 各存一份：
   ```bash
   sudo mount /dev/mmcblk0p2 /mnt/eda && sudo mkdir -p /mnt/eda/backup
   sudo tar czf /mnt/eda/backup/image-feat_dhcp-rock.tar.gz -C /host image-feat_dhcp-rock.0-b2f3ebaf9
   sudo cp /host/grub/grub.cfg /mnt/eda/backup/grub.cfg.pre-migration
   ```
   这不是可引导的 `.bin`，但足以在 grub 项或镜像目录被破坏时原地恢复。
4. **取基线快照**（验收要用，且这台机器状态会变——跨天必须重取）：
   ```bash
   sudo cp /etc/sonic/config_db.json ~/config_db.json.pre-migration
   stat -c "%y %s" /etc/sonic/config_db.json          # 期望 2026-09-04 10:01:45 / 46610
   sudo sonic-installer list; redis-cli -n 4 hget "VERSIONS|DATABASE" VERSION
   docker ps -q | wc -l                                # 基线 12
   vtysh -c "show bgp ipv4 summary" > ~/base-bgp4.txt  # 基线 v4 11 peers / 4 Established
   vtysh -c "show bgp ipv6 summary" > ~/base-bgp6.txt  # 基线 v6 6 peers
   redis-cli -n 1 --scan --pattern "ASIC_STATE:SAI_OBJECT_TYPE_ROUTE_ENTRY:*" | wc -l   # 基线 73
   show interfaces status > ~/base-intf.txt
   ```

### 阶段 1 · 修 `/etc/resolv.conf`（阻断项 ①）

```bash
sudo rm -f /etc/resolv.conf                       # 先删悬空符号链接，不能直接重定向覆盖
printf 'nameserver <DNS-1>\nnameserver <DNS-2>\n' | sudo tee /etc/resolv.conf
getent hosts <任意可解析域名> && echo OK
```

记入回滚清单（这是我们引入的临时改动）。装完新镜像后，resolute 侧的 `resolv-config.service` 会接管，届时这个文件应当是"带 SONiC 头部的普通文件"。

### 阶段 2 · 传镜像（2.03 GiB，360 ms 链路）

单流 scp 会在这条链路上崩。用 SOP 阶段 4 的并行 4 流 + 按大小续传，聚合 ~3.8 MB/s：

```bash
split -d -b 548M /home/sheldon-qi/sonic-buildimage-resolute/target/sonic-broadcom.bin ~/rparts/rpart-
# 4 路并行 scp 到 /host/staging/，各带重试；完成后远端 cat 拼接 + sha1 校验
```

落在 `/host/staging/`（27G 可用，绰绰有余）。装前最后核一次 sha1，并核对 installer 自带的 `payload_sha1` 自检。

### 阶段 3 · 装第二镜像

```bash
sudo sonic-installer list                 # 确认仍只有 1 个镜像（不会淘汰任何东西）
df -h /host
yes | sudo sonic-installer install /host/staging/sonic-broadcom.bin
sudo sonic-installer list                 # 期望：两镜像并存，Next = resolute
```

装完**先不要急着重启**——确认 `Next` 指对了、`/host/old_config` 里有配置副本。

### 阶段 4 · 切换

```bash
sudo reboot
```

**同时盯 console**（阶段 0 落实的那条）。首启会跑 `db_migrator` 的 6 跳，比平常慢；SONiC 的 monit 收敛本来就要十几分钟，不要在前 15 分钟内下"失败"的结论。

### 阶段 5 · 验收

```bash
sudo sonic-installer list | grep Current                       # = resolute 版本串
uname -r                                                        # 期望 7.0.0-1002-sonic
grep VERSION= /etc/os-release                                   # 期望 Ubuntu 26.04 Resolute
redis-cli -n 4 hget "VERSIONS|DATABASE" VERSION                 # 期望 version_202605_01（证明 6 跳走完）
docker ps -q | wc -l                                            # ≥ 12
redis-cli -n 1 --scan --pattern "ASIC_STATE:SAI_OBJECT_TYPE_ROUTE_ENTRY:*" | wc -l   # ≥ 73
vtysh -c "show bgp ipv4 summary" | tail -3                      # Established ≥ 4
bcmcmd "cancun stat"                                            # CIH/CMH/CCH/CEH/CFH LOADED 06.15.00
ls -l /etc/resolv.conf; systemctl is-active resolv-config       # 普通文件 + active
show system-health detail | grep -A2 Services                   # 用这个，不要数 grep -c OK
```

**逐项对基线，不对规划值。** 北向本来就不通、Po205 本来就是八成员——这些在迁移后依然如此才是正确结果。

---

## 5 · 回滚矩阵

| 故障层级 | 回滚动作 | 前提 |
|---|---|---|
| 新镜像起来了但业务不对 | `sudo sonic-installer set-default SONiC-OS-feat_dhcp-rock.0-b2f3ebaf9` + reboot | SSH 可达 |
| 新镜像起不来 / mgmt 不通 | console → grub 菜单手选旧镜像 | **console（阶段 0）** |
| grub 都进不去 | UEFI `Boot0004` → ONIE rescue → 挂 `sda3` 改 grubenv / 恢复 grub.cfg | ONIE rescue 能 DHCP 到 mgmt IP |
| 镜像目录或 grub 项被破坏 | 从 EDA-DIAG 解回 `image-feat_dhcp-rock.tar.gz` + `grub.cfg.pre-migration` | 阶段 0 第 3 步 |
| 配置需要回退 | `sudo cp ~/config_db.json.pre-migration /etc/sonic/config_db.json && sudo config reload -y` | 阶段 0 第 4 步 |
| 彻底救不回 | ONIE 重装原镜像 | **目前无源，见 §2.3——这条退路是断的** |

---

## 6 · 未决问题（动手前逐条落实）

1. **console server 到 sw1 的端口映射** —— 阻断项，必须实测登录成功。
2. **owner 同意与迁移窗口** —— 阻断项。
3. **原镜像 `.bin` 的来源** —— `<IMG-SRC>:8080` 已无响应、sw2 当前连不上。要么找到 owner 手里的原始 `.bin`，要么接受"回滚上限是镜像目录级恢复，没有 ONIE 重装退路"这一事实并写进变更单。
4. **迁移后是否顺带修配置缺陷** —— 建议**不要**在同一个窗口做。先证明"同一份配置在新镜像上表现一致"，再单独开窗口修 Po205 / v6 笔误。

---

## 附录 · 本次勘察的原始证据

全部为只读命令，未对 sw1 做任何写操作：

- `/host/machine.conf`、`lsblk`、`sudo blkid`、`sudo sgdisk -p /dev/sda`、`sudo efibootmgr`
- `sudo sonic-installer list`、`du -sh /host/image-*`、`df -h /host`
- `sudo grep -aE "^menuentry|next_entry|onie_entry" /host/grub/grub.cfg`
- 只读挂 `sda1` 读 `/EFI/debian/grub.cfg`（已 `umount`）
- `ls -l /etc/resolv.conf`、`getent hosts`、`redis-cli -n 4 hget "VERSIONS|DATABASE" VERSION`
- `show platform summary`、`sonic-package-manager list`、`mokutil --sb-state`
- `vtysh -c "show bgp ipv{4,6} summary"`、`docker ps -q | wc -l`、ASIC 路由计数
- 本地：`sed -e '1,/^exit_marker$/d' target/sonic-broadcom.bin | tar -xO installer/platforms_asic`、`src/sonic-utilities/scripts/db_migrator.py:1355-1445`

相关记忆：`lab-sw1-ubuntu-sonic`（该机既往全部实测结论）、`onie-multiboot-four-layer-model`、`resolute-broadcom-build-success`、`resolute-dut02-component-health-audit`
