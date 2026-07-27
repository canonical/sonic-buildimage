# 通过巡检在役交换机发现的四个 resolute 缺陷，及与上游的全状态对比

**日期**：2026-07-27
**目标设备**：`<DUT-MGMT-IP>`（Dell EMC S5232F-ON，BCM56873 / Trident3，platform `x86_64-dellemc_s5232f_c3538-r0`）
**分支**：`canonical/sonic-buildimage` → `202605_resolute_sheldon`，已 rebase 到 `sonic-net/202605`（`ba3fb8d5f5`）
**承接**：[2026-07-26 dut02 S5232F 验证报告](2026-07-26-dut02-s5232f-validation-report-zh.md)，该报告已确认自建 resolute 镜像能在此硬件上启动并转发。

---

## 1. 结果速览

| 事项 | 结果 |
|---|---|
| 在役交换机全组件巡检 | 14/14 容器健康；4 个真缺陷，5 个疑似项被证伪 |
| 所有 SAI 计数器恒为 0 | **根因是子模块脱离上游**，不是 SAI 版本。已修复并在硬件上验证 |
| SONiC 事件框架完全失效 | Ubuntu 的 rsyslog AppArmor profile 挡住了事件插件。已修复并在硬件上验证 |
| 交换机无 DNS | `resolvconf` 在 Ubuntu 上是虚包。改用 systemd-resolved 官方文档中的「由其它软件包管理」模式 |
| RADIUS 选项被静默忽略 | libpam-radius-auth 的 de-fork 丢掉了四个 SONiC 补丁中的三个。已回滚为源码构建 |
| 子模块严格-ff 审计 | 52 个中有 4 个已分叉；全部零冲突 rebase，审计转绿，且该检查已脚本化 |
| 上游 ↔ 自建，同机同配置 | **无功能差异。** 86 行 diff，全部落在发行版层 |

---

## 2. 范围：逐组件巡检在役交换机

起点是三条命令 —— `docker ps -a`、逐容器 `supervisorctl status`、`show system-health sysready-status`
—— 应要求扩展到全部组件：宿主服务、容器、转发面、平台传感器、管理与遥测面，以及日志。

健康面基线扎实：14/14 容器 Up 且 `RestartCount=0`，41 项 monit 进程检查全 OK，BGP 已建立，
ASIC 转发正常，PSU 与风扇 OK，无 core dump。

有几项看着吓人、实为设计如此，记录在此以免重复排查：`EXITED` 的 supervisor 条目
（`dependent-startup`、`start`、`flushdb`、`swssconfig`、`enable_counters`、`gearsyncd`、
`restore_neighbors`、`chassis_db_init`、`ledinit`、`zsocket`、`waitfor_lldp_ready`）都是一次性脚本；
`bgp:sharpd` 与 `radv:radvd` 是 `autostart=false`；`pmon:pcied` 退出是因为该 platform 在上游就没有
`pcie.yaml`；SNMP 无响应是因为未配置 community；NTP 未同步是因为配置里没有服务器。

---

## 3. 四个缺陷

### 3.1 每一个 SAI 计数器都卡在零

在一台已转发 BGP 流量 16 小时的交换机上，`show interfaces counters` 对每个端口、队列、优先级组和
watermark 都报零。

证据把各层次干净地切开了：

- 内核 netdev 数到了流量（20 个 ping 期间 8462 → 8505 包）；
- Broadcom SDK 自己的计数器与之吻合（`bcmcmd show c`：`CLMIB_RPKT.ce0` = 8515）；
- flex counter 框架是活的 —— `FLEX_COUNTER_GROUP_TABLE:PORT_STAT_COUNTER` 已 enable、轮询周期
  1000 ms，且 `PORT_PHY_ATTR` 组在持续发布带新鲜时间戳的数据；
- 但 `COUNTERS_DB` 里 3990 个 key 无一非零，且任何地方都没有报错。

在同一硬件上启动官方 202605 镜像，计数器正常递增，这证明回归在我们这侧，却无法指认是哪一部分：
那次启动同时换掉了 OS、内核、syncd、sairedis 和 SAI 库。最终靠 git 考古定位。

我们的 `sonic-sairedis` 子模块比上游自己树里记录的 commit 落后两笔，其中一笔正是
[`16ae1ae5`「Smart Counter Poll to allow counters to work properly on Broadcom platforms」（#1995）](https://github.com/sonic-net/sonic-sairedis/pull/1995)：

> `FlexCounter.cpp` 假定所有端口支持相同的计数器能力。这在多数 Broadcom 平台交换机上都会出问题，
> 因为一台交换机上存在不同类型、并不支持同一组计数器的端口。修法是在 `syncd` 初始化阶段动态发现
> 每个接口的能力。

每个细节都对得上：S5232F 是 32×100G QSFP28 混两个 10G SFP+；失效是静默的，因为没有任何调用返回错误，
只是能力假设本身错了；而修复只触及计数器初始化，这正解释了为何 `PORT_PHY_ATTR` 这类走属性读的组照常工作。
我们用于对照的官方镜像带着这笔提交 —— 其 gitlink 恰好就是 `16ae1ae5`。

**SAI 版本是错误的嫌疑对象。** 我们的 pin `libsaibcm 15.2.0.0.0.0.3.1` 从未被我们改动，正是分支点上
上游 202605 所 pin 的版本；上游在 2026-07-24 才升到 `11.1`（#28549），那是一批 CSP 修复的汇总，
changelog 里没有任何形如「XGS 端口统计返回零」的条目；而且 `3.1` 在 202605 上挂了整整一个月，
期间 Broadcom XGS 资格测试套件是通过的。

**这笔提交是怎么丢的**，才是值得内化的部分。2026-07-20 本仓库被 rebase 到上游 `fe5ae5db34` ——
而该 commit 的 `src/sonic-sairedis` gitlink 已经是 `16ae1ae5`。但子模块分支仍停在 2026-07-03。
当超仓 rebase 撞上 gitlink 冲突时，必须保留我们的 commit，否则 resolute 补丁就没了 ——
于是陈旧的 gitlink 被保留，上游修复被静默丢弃。没有任何机制会报告这件事。

### 3.2 SONiC 事件框架从未发布过任何事件

`omprog: failed to execute program '/usr/bin/rsyslog_plugin': Permission denied` —— 16 小时内 2891 次，
且仍在累加。`/var/log/audit/audit.log` 点明了原因：

```
apparmor="DENIED" operation="exec" profile="rsyslogd" name="/usr/bin/rsyslog_plugin" requested_mask="x"
apparmor="DENIED" operation="capable" profile="rsyslogd" capability=0 capname="chown"
```

Ubuntu 的 rsyslog 包带 `/etc/apparmor.d/usr.sbin.rsyslogd` 并处于 enforce，其 `rsyslog.service` 还带着
`ExecStartPre=/usr/lib/rsyslog/reload-apparmor-profile`。Debian 的 rsyslog **完全没有** profile ——
这一点通过在同一台机上挂载官方镜像的 squashfs 得到验证 —— 所以那边宿主 rsyslogd 不受约束，
只有容器内的实例走 `docker-default`。于是六个 `*_events.conf`（bgp、swss、syncd、dhcp_relay、host、
00-sonic）全部失效，同一 profile 还拒绝了 `$FileOwner`/`$FileGroup` 背后的 `chown`。

修法是通过 profile 自带的 `local/` include 做覆盖，这正是 `build_debian.sh` 里已经用于 tcpdump 的机制。
**在交换机上实测很关键**：放开 exec 与 capability 后立刻暴露出第二处拒绝 ——
`/etc/sonic/init_cfg.json`，libswsscommon 在连接事件总线时会打开它 —— 光读 profile 是预测不到的。

### 3.3 交换机完全没有 DNS

`/etc/resolv.conf` 是指向 `/run/resolvconf/` 的悬空软链，`getent hosts` 失败。

`resolvconf` 在 Ubuntu 上**不作为实体包存在** —— 它是一个虚包，由 `systemd-resolved` 声明
`Provides`、`Replaces` 和 `Conflicts`，且至少从 24.04 起就是如此。于是 rootfs 包列表里的
`resolvconf` 被静默地由 systemd-resolved 满足，`/sbin/resolvconf` 变成指向 `resolvectl` 的软链，
而 SONiC 的 `resolv-config.sh` —— 它要用 `--disable-updates`、`--enable-updates`、`-u` 和
`/run/resolvconf/interface/` —— 每一项都失败。`interfaces-config.sh` 的
`resolvconf_updates_disable/restore` 撞的是同一堵墙。Noble 参考分支带着一模一样的潜伏 bug，无人察觉。

改造采用 `systemd-resolved.service(8)` 中记载的 `/etc/resolv.conf` 第四种处理模式：文件「由其它软件包
管理」，resolved 退为消费者而非生产者。由 SONiC 自己渲染该文件，同时也保住了 `DNS_OPTIONS`：
resolved 既表达不了 `ndots` 也表达不了 `timeout`，其 stub 解析器按手册原话「根本不实现 ndots」。
何况镜像本来就走 nss-dns 解析（`hosts: files dns`），resolved 从不在查询路径上。

为 DHCP 场景还需堵住另外两个坑。`resolvectl(1)` 写明其 resolvconf 兼容模式「只在
`/etc/resolv.conf` 是指向 `/run/systemd/resolve/resolv.conf` 的软链、而非静态文件时」才会更新该文件；
而 isc-dhcp-client 自带 `dhclient-enter-hooks.d/resolved-enter`，只要 systemd-resolved 处于 enabled
就直接把 `make_resolv_conf()` 置空。现在由我们自己的钩子写文件，并在镜像中删除 Ubuntu 那对钩子。

### 3.4 RADIUS 丢了四个补丁中的三个

`aaastatsd` 每次定时触发都以 `/etc/pam_radius_auth.d/statistics/` 的 `FileNotFoundError` 崩溃。
目录缺失是因为 `rules/radius.mk` 被 de-fork 成了 Ubuntu 现成的 `libpam-radius-auth 3.0.0-1build1`。

`src/radius/pam` **不是** Debian 的包：它是 SONiC 自己的 `1.4.1-1`，这个版本号在任何发行版归档里都不存在，
基于 Debian 1.4.0 的 packaging 加四个补丁构建。Ubuntu 的 3.0.0 是更新的上游（FreeRADIUS/pam_radius），
四个补丁里只带了一个：

| SONiC 补丁 | 大小 | 上游 3.0.0 是否已有 |
|---|---|---|
| `0004-fix-blastradius` | 12 KB | 有（`require_message_authenticator`） |
| `0003-nas-ip-address-config` | 29 KB | 部分 —— NAS-IP 由 hostname 推导；没有 `nas_ip_address=` 选项，没有 `statistics` |
| `0001-chap-support` | 4 KB | 无 |
| `0002-peap-mschapv2-support` | 135 KB | 无 —— 这也是 SONiC deb 里带 `libeap` 和 `libradius` 动态库的原因 |

`common-auth-sonic.j2` 会传 `privilege_level`、`protocol=<auth_type>`、`retry=`、`nas_ip_address=`
和 `statistics=`。上游 3.0.0 对未识别选项是打日志后继续，所以 PAP 仍能认证 —— 但
`protocol=chap` 和 `protocol=mschapv2` 被静默忽略并退回 PAP，`nas_ip_address=` 被忽略，
统计采集彻底消失。该规则已逐字恢复为上游写法；源码构建从来不是风险，因为 1.4.1-1 的 deb 及其 dbgsym
在 de-fork 落地之前就已经在 resolute 上构建成功过。

---

## 4. 子模块严格-ff 审计

对于 Canonical 改动过的子模块，健康状态的定义是**相对上游的严格 fast-forward**：上游记录的 commit 是
我们 commit 的祖先，我们的补丁重放在其之上。§3.1 展示了分叉的代价，因此对整棵树做了审计，
并把该检查固化为脚本 `scripts/submodule-ff-audit.sh`，在 `AGENTS.md` 中作为「每次与上游同步后必跑」
的步骤被引用。它对每个 gitlink 分类，并额外捕捉两种会让 clone 失败的形态：gitlink 不存在于任何远端、
以及 `.gitmodules` 中非 https 的 URL。

52 个子模块的首次全量运行：36 个与上游完全相同、12 个严格 ff、**4 个已分叉** ——
`sonic-sairedis`（缺 2 笔上游）、`sonic-utilities`（缺 4 笔）、`sonic-swss`（缺 1 笔）、
`sonic-dash-ha`（缺 2 笔）。通过对「我们改的文件集 ∩ 上游改的文件集」求交，事前判定四者均无冲突，
实际 rebase 也确实一个冲突都没有。审计现在报告 36 个相同 + 16 个严格 ff，0 分叉。

同一轮把本仓库 rebase 到当前上游，还顺带白拿了 SAI `3.1 → 11.1` 的升级和更新的
`sonic-platform-common` —— 因为这两个文件都不是我们改动的对象。

---

## 5. 构建、部署与整机验证

按 broadcom 构建出镜像（2.19 GB，`202605_resolute_sheldon.0-d605df6b`），以四路并行流传到交换机
（这条高时延链路上单条 scp 会崩），与已有镜像并存安装并启动。

四项修复在装机镜像上全部成立：

| 修复 | 启动后的证据 |
|---|---|
| 计数器 | `SAI_PORT_STAT_IF_IN_OCTETS` 持续递增；`show interfaces counters` 报出流量；队列计数器非零；syncd 日志出现新的逐口能力发现 |
| 事件 | omprog 错误 0 条，**10** 个 `rsyslog_plugin` 进程（修前只有 1 个），AppArmor 拒绝 0 条，`events_tool -r` 收到事件 |
| DNS | `/etc/resolv.conf` 是带 SONiC 头部的普通文件，`resolv-config.service` 为 active（此前是 `failed`），我们的 dhclient 钩子在位、Ubuntu 的 `resolved`/`resolved-enter` 钩子已移除。`config dns nameserver add` 能渲染出服务器且 `getent` 解析成功 —— 静态路径端到端跑通 |
| RADIUS | `libpam-radius-auth 1.4.1-1` 且带 statistics 目录；`aaastatsd` 不再崩溃 |

重启后的整机状态：14 个容器，BGP v4 136 / v6 73 已建立，215 条 ASIC 路由，PortChannel200 LACP Up。

### DHCP 路径

管理口之所以是静态，仅仅因为手写的那份 T0 minigraph 这么写；于是把它切到 DHCP，以检验改造的另一半：
从运行态配置里删除 `MGMT_INTERFACE`、重启 `interfaces-config`，并预约一次重启作为兜底，以防租约给出
不同地址。并没有 —— 该地址是保留地址 —— `eth0` 以 `dynamic` 起来，两个 dhclient 实例都在运行。

不过该租约**不携带 `domain-name-servers`**（只有 subnet mask、routers、lease time 和 server
identifier），因此钩子正确地没有去动 `/etc/resolv.conf`，而不是把它清空。于是改用 source 钩子并以
dhclient 会设置的同一组环境变量调用 `make_resolv_conf()` 来检验其渲染 —— 这正是 dhclient-script 调用
它的方式：文件写入了 search 域和两个 nameserver，`update-containers` 把它们同步进了容器，
而在静态标记存在时钩子正确地拒绝改动任何东西。

这次验证还揪出了本次工作自身的一个缺陷：动态分支只在 `/etc/resolv.conf` 是软链或缺失时才替换它，
于是静态配置遗留的 nameserver 会跨越切换、并在之后的重启中继续存活。已在 `6d534d9aa1` 修复 ——
静态标记仍在时重置该文件，其余情况保持不动。

管理口**已保留在 DHCP 上**，写入存盘配置并跨重启确认。注意：由于该 DHCP 服务器不下发 DNS，
除非用 `config dns nameserver add` 配一个，交换机将没有 nameserver；另外将来若执行
`config load_minigraph`，静态地址会回来，因为 minigraph 里仍然声明着它。

---

## 6. 全状态对比：上游 sonic-net 对自建

**方法。** 两个镜像跑在同一台交换机、同一份 T0 配置上 —— `sonic-installer install` 会把 `/etc/sonic`
复制到 `/host/old_config`，新镜像首启自动迁移，所以配置一致性是天然的。用一个采集脚本各导出一份
归一化快照（把 pid、uptime、时间戳、字节数归一化掉），覆盖镜像标识、容器及其 supervisor 程序、
feature、sysready、失败单元、DNS、事件与 AppArmor、计数器、转发面、平台、CLI 退出码、监听端口、
关注包清单、以及日志错误直方图。两份快照各约 393 行，差异 86 行。

**每一处差异都落在发行版层。** 内核 `6.12.41+deb13` vs `7.0.0-1002-sonic`；Debian 13 vs Ubuntu 26.04；
apparmor 4.1.0 vs 5.0.0~beta1；chrony 4.6.1 vs 4.8；rsyslog 8.2504 vs 8.2512；monit 5.34.3 vs 5.35.2；
`libpam*` 一族的 Debian 与 Ubuntu 版本号；以及 libnl `3.7.0-0.2+b1sonic1`（上游打过补丁的自建版）
vs `3.12.0-2`（我们有意 de-fork 到发行版原版）。`libpam-radius-auth` 根本没有出现在 diff 里 ——
两边又都是 `1.4.1-1` 了。

**完全一致、并因此了结若干悬案的部分：**

- 整个计数器小节逐字节相同：`port_counters_moving=YES`、`queue_counters_nonzero=1`、
  `flex_counter_groups=24`，以及 **`rif_counter_fields=0`** —— 所以 RIF 计数器为空是上游行为，
  不是 resolute 回归。
- `Hardware: Not OK — Invalid ASIC On-board temperature data, threshold=N/A` 两边都出现，
  确认系统状态灯发琥珀色是上游 Dell 插件的缺口。
- 两个镜像都报 `System is not ready`，但各自因为不同的单元：上游是 `gnoi-shutdown`，我们是 `dmesg`
  （Ubuntu 独有的 unit）。属同一类上游毛病，不是 resolute 独有。

**自建更强的一处：** `show platform summary` 在我们的镜像上报出 Serial `FXN3SR3` 与 Model `0018MY`，
官方镜像是 `N/A` —— 这得益于 rebase 带进来的更新版 `sonic-platform-common`。

**唯一真正属于我们的差异：** monit 的程序检查在启动后收敛更慢。上游在 uptime 8 分钟时已全部 OK；
我们在 9 分钟时仍有 7 项列为 *Not Running*，到 13 分钟才达到 `Services: OK`。属启动延迟而非故障 ——
更早一次 16 小时 uptime 的采集显示一切 OK。

---

## 7. 值得记住的操作陷阱

- **`sonic-installer install` 只保留两个镜像**，并会静默删除最旧的非当前镜像。装第三个镜像时，
  它把官方对照镜像连同 GRUB 项一起删掉了。之所以零代价恢复，仅仅因为官方 `.bin` 仍暂存在 eMMC 的
  EDA-DIAG 分区上（`/mnt/eda/sonic-staging/`，每次重启后需
  `mkdir -p /mnt/eda && mount /dev/mmcblk0p2 /mnt/eda` 重新挂载）。安装前务必确认将被淘汰的是哪一个。
- **悬空的 `/etc/resolv.conf` 会让 `sonic-installer install` 在 `migrate_sonic_packages` 阶段失败**，
  该阶段会执行 `cp /etc/resolv.conf …` 到新镜像的 chroot —— 这是 §3.3 的又一后果，文件恢复为普通文件后
  该故障即消失。
- **替换容器镜像需要三步而不是一步。** `docker load` 会把旧镜像改名占住版本 tag，因此必须重新打版本 tag；
  而 `systemctl restart swss` 只是 `docker start` 已存在的容器，仍会沿用旧镜像。正确顺序是
  `systemctl stop swss` → `docker rm -f syncd` → `systemctl start swss`（`swss.sh` 声明了
  `PEER="syncd"`，停 swss 会连带停 syncd）。
- **顶层 `Makefile` 的 `%::` 规则没有前置依赖**，目标文件存在就会被报告为 "up to date"，
  构建根本不会进入 slave 容器。重建前要删掉 `target/<目标本身>`；只删中间的 deb 是不够的。
- **`/var/log` 是 loop 挂载、跨镜像共享的文件系统**，所以 `audit.log` 和 `syslog` 的历史计数不能作为
  「当前所运行镜像」的证据。
- **子模块分支在本地与远端命名不同**：工作分支叫 `resolute` 或 `202605`，远端分支叫 `202605_resolute`。

---

## 8. 当前状态与遗留项

`202605_resolute_sheldon` 严格基于 `sonic-net/202605`（`ba3fb8d5f5`），其上有 168 笔提交，
其中五笔来自本次工作，全部 GPG 签名：

```
9758a4685f  build: sync the diverged submodules with upstream 202605
d605df6b58  build(resolute): drop the libpam-radius-auth de-fork
56f4735555  fix(resolute): render /etc/resolv.conf directly instead of via resolvconf
08c98ba3d6  fix(resolute): let rsyslogd run the SONiC event plugin under AppArmor
327327cb32  build: add submodule fast-forward audit
```

四个子模块分支在确认各远端恰好停在其 rebase 前的 commit 之后，被 force-push 到
`canonical/<submodule>:202605_resolute`，gitlink 则按 `AGENTS.md` 的要求在推送**之后**才 bump。
生产分支 `canonical/202605_resolute` 未被触碰，也没有向 `sonic-net` 推送任何内容。

遗留：

- **仍未遇到会下发 DNS 的 DHCP 服务器。** 钩子已安装、会被 source、渲染正确，交换机的管理口现在也跑在
  DHCP 上 —— 但该服务器不发 `domain-name-servers`，所以下发传播是用模拟租约而非真实租约验证的。
- **`dmesg.service` 让 sysready 持续为红。** 该 unit 是 Ubuntu 独有，`Type=idle` 且无
  `RemainAfterExit`，跑完数秒即变为 inactive。无害，但等待 sysready 的测试会超时。
  drop-in、mask，或加入监控忽略列表，任一即可闭环。
- **把缺失的三个 pam_radius 补丁前向移植到 3.0.0** 并推给 FreeRADIUS/pam_radius 上游，
  才是真正意义上 de-fork RADIUS 的唯一途径。
