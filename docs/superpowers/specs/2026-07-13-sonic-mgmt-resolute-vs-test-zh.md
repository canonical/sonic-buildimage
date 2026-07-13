# 设计:用 sonic-mgmt sanity 套测试 resolute sonic-vs 构建

**分支:** `202605_resolute_doc`
**工作目录:** `/home/sheldon-qi/sonic-buildimage-resolute`(构建仓库,`202605_resolute` 分支,HEAD `3beabfff4c`)
**日期:** 2026-07-13
**状态:** 设计已批准;实施计划待制定

---

## 1. 背景与目标

SONiC resolute 内核/base 包迁移已交付:`target/sonic-vs.bin` 于 2026-07-13 构建,`os-release` 确认 Ubuntu 26.04,内核 `7.0.0-1002-sonic`(Launchpad PPA),~30 包迁移修复已合入 `202605_resolute` 分支。测试框架容器 `docker-sonic-mgmt.gz`(pytest 9.1.1)同日构建并验证可 load/可 run。

迁移验证此前仅覆盖 **KVM 启动冒烟**(uname、12 核心容器 Up),**从未用 sonic-mgmt 框架做过控制面 / 配置管线层面的回归验证**。本设计定义这第一次正式验证。

**目标:** 用 `docker-sonic-mgmt` 容器驱动 sonic-mgmt pytest 套件,对 resolute `sonic-vs` KVM DUT 跑一组**不依赖 EOS 邻居**的 sanity 测试,确认 resolute 迁移(内核 + base 包 + ~30 包修复)**没有破坏容器健康、配置管线、show 命令、系统服务与数据面接口**。

**非目标:** 完整 T0 拓扑(需 Arista EOS 邻居 VM);BGP/路由类测试;性能/规模;多 ASIC。

## 2. 组件

| 组件 | 来源 | 作用 |
|---|---|---|
| **DUT** | `sonic-vs.img`(resolute `.bin` → qcow2,已就位)+ `platform/vs/sonic.xml` | KVM VM 被测设备,mgmt 口接 virsh default net 走 DHCP,SSH 可达 |
| **测试执行器** | 已构建 `docker-sonic-mgmt` 容器(pytest 9.1.1,2026-07-13) | 挂载 sonic-mgmt repo,`--network host` 跑 ansible + pytest |
| **sonic-mgmt 仓库** | 新 clone `sonic-net/sonic-mgmt` @ `202605`(经 proxy) | 测试代码 + `setup-container.sh` + inventory 模板 |
| **PTF 容器**(仅 Phase 2) | 新构建 `target/docker-ptf.gz` | 流量生成器,cable 到 DUT 前面板口(仅 `test_interfaces` 需要) |

## 3. 架构 / 数据流

```
docker-sonic-mgmt 容器 ──(mgmt 网)──> DUT KVM (sonic-vs.img)
   │  ansible / pytest                       SSH + 配置下发
   └── 挂载 sonic-mgmt repo (202605)

仅 Phase 2:
   PTF 容器 ──(OVS 桥)──> DUT 前面板口 ──> 测试流量 / 计数
```

测试执行器经 mgmt 网对 DUT 做 SSH/ansible,下发配置、采集 show;PTF 容器(Phase 2)经 OVS 桥接到 DUT 前面板口收发测试流量。

## 4. 分阶段执行

设计原则:**先低摩擦高价值,后高摩擦**。Phase 1 覆盖迁移最可能受影响且无需流量面的维度;Phase 2 仅在 Phase 1 绿且时间允许时进行。

### Phase 1 — 核心 sanity(无 PTF,4 项)

1. **启动 DUT:** `virsh create platform/vs/sonic.xml`(`sonic-vs.img` 已就位),等待 12 核心容器 Up + mgmt DHCP。
2. **Clone sonic-mgmt** @ `202605` 到 `~/sonic-mgmt`(带 `https_proxy`)。
3. **配置执行器:** 用已构建的 `docker-sonic-mgmt` 镜像(含 sonic-mgmt 依赖 + 3 个 dataplane/ptf patch)起容器:`docker run --network host -v ~/sonic-mgmt:/data docker-sonic-mgmt`。inventory 配置有两种路径,plan 阶段定:
   - (a) 直接手写最小 inventory(指向 KVM DUT 的 IP/凭据);或
   - (b) 在宿主跑 sonic-mgmt repo 的 `setup-container.sh` 让其接管容器/inventory 配置(注意:标准流程 `setup-container.sh` 是**创建** sonic-mgmt 容器,而我们已有自建镜像,需让它复用而非重建)。
4. **写最小 inventory** 指向 KVM DUT(virsh default net IP + admin/admin 凭据)——若上一步选 (b) 则由 `setup-container.sh` 生成。
5. **`testbed-cli.sh deploy-cfg`** 加载 t0 minigraph(单 ASIC KVM hwsku `x86_64-kvm_x86_64-r0`)。
6. **跑测试**(无 PTF,`--neighbor-type none` 语义):
   - `test_features` — 容器/feature 状态
   - `test_config_reload` — 配置 save/reload 管线
   - `test_show_interface` — 接口 show
   - `test_sonic` — 系统级

### Phase 2 — PTF 流量(仅 Phase 1 绿 + 时间允许)

1. 构建 `target/docker-ptf.gz`(`make target/docker-ptf.gz`,带 proxy)。
2. `testbed-cli.sh deploy-topo` 拉起 OVS 桥 + PTF cabling。
3. 跑 `test_interfaces`(接口计数 / 翻动)。

## 5. 通过标准

- **Phase 1:** 4 项全 PASS = resolute build 控制面 / 配置管线无回归。
- **Phase 2:** `test_interfaces` PASS = 数据面接口计数正常。
- 遇 FAIL:按 `systematic-debugging` 区分 **resolute 迁移回归** vs **sonic-mgmt 测试本身 / 测试床配置问题**(对照见下)。

## 6. 对照基线

某测试 FAIL 且根因不明时,在 `~/sonic-buildimage-202605-clone` 的 `sonic-vs.bin`(非 resolute,trixie 基线)上跑同一测试做 A/B,隔离 resolute 因素。该 clone 的 sonic-vs.bin 日期为 2026-07-03(是否可启动需验证——已存在但本次会话未 boot 过)。

## 7. 风险与回退

- **测试床 friction:** inventory 凭据、KVM mgmt IP 不稳(DHCP)、minigraph 端口数不匹配。回退:逐步简化——先只跑不依赖拓扑的 `test_features` 确认链路通,再扩。
- **基线可启动性:** `202605-clone` 的 sonic-vs.bin 是否能干净启动需验证(已存在但本次未 boot)。
- **proxy 依赖:** clone sonic-mgmt、pip 依赖 `https_proxy=http://192.168.1.210:6152`。
- **Phase 2 cabling:** OVS 桥 / port 绑定 / minigraph 端口映射易错;Phase 2 失败不影响 Phase 1 结论。

## 8. 本地环境约束(继承 handoff)

- 工作树 `Makefile.work` / `slave.mk` / `rules/config.user` 的本地 add-host / proxy 改动**不 commit**(仅本地加速)。
- 测试相关代码修复(如 resolute 专项测试调整)**可 commit 不 push**(调通为止)。
- 构建 PTF(Phase 2)复用已缓存 slave 镜像,带 proxy。

## 9. 产出物

- 本设计文档(已 commit)。
- Phase 1:4 项测试 PASS/FAIL 报告 + 必要的 inventory/minigraph 产物。
- Phase 2(若执行):`test_interfaces` 报告。
- 发现的任何 resolute 回归 → 记录根因 + 修复 commit(不 push)。

## 10. 相关 memory

- `sonic-resolute-vs-build-success.md` — resolute vs 构建成功记录
- `sonic-resolute-launchpad-linux-sonic-abi.md` — 内核 ABI 细节
- `sonic-build-restore.md` — DinD 构建、host 修复
- `handoff-sonic-mgmt-build.md` — docker-sonic-mgmt 构建 handoff(proxy、slave 缓存、add-host 约束)
