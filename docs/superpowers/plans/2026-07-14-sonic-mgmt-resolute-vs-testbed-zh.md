# sonic-mgmt resolute VS 测试床 — 实施计划(v2,标准 testbed-cli 流程)

> **For agentic workers:** REQUIRED SUB-SKILL: 用 superpowers:subagent-driven-development(推荐)或 superpowers:executing-plans 逐任务执行。步骤用复选框(`- [ ]`)语法跟踪。

**目标:** 用 sonic-mgmt 官方 KVM 测试床流程搭一个 cEOS 邻居的 T0 拓扑,把 resolute `sonic-vs` 作为 DUT 启动,跑完整 T0 测试套件,验证 resolute(Ubuntu 26.04)迁移。

**架构:** 严格遵循 sonic-mgmt 官方 `README.testbed.VsSetup.md` 流程。DUT 是 KVM VM(`vlab-01`),由 `testbed-cli.sh add-topo` 自动创建;cEOS 邻居是 Docker 容器;PTF 是 Docker 容器;全部经宿主 `br` 管理桥互联。**不用**手动 virsh/XML(`platform/vs/sonic.xml` 模板已过时——机型 `pc-i440fx-1.5` 与 `-redir` 端口转发被新版 QEMU/libvirt 拒绝)。

**技术栈:** KVM/QEMU + libvirt(DUT)、Docker CE(cEOS + PTF 容器)、sonic-mgmt ansible 框架 @ 分支 `202605`、`docker-sonic-mgmt` 作测试执行器容器。

## 全局约束

- 构建仓库:`~/sonic-buildimage-resolute`,分支 `202605_resolute`。resolute `sonic-vs.img` 在 `~/sonic-buildimage-resolute/sonic-vs.img`(5.5GB,root 所有),还需**拷贝**到 `~/sonic-vm/images/` 和 `~/veos-vm/images/` 供 testbed 流程用。
- sonic-mgmt 仓库:`~/sonic-mgmt`,分支 `202605`(HEAD `00c4dac`)。所有 testbed-cli/ansible 命令在 `~/sonic-mgmt/ansible/` 下执行(除非另注)。
- 文档分支 `202605_resolute_doc` 存放 spec/plan。
- 网络操作 proxy(git clone、镜像下载、pip、docker pull):`https_proxy=http://192.168.1.210:6152`,`no_proxy=archive.ubuntu.com,security.ubuntu.com,10.211.55.9,localhost,127.0.0.1`。
- DUT 凭据:裸镜像 `admin`/`YourPaSsWoRd`(rules/config DEFAULT_PASSWORD);`deploy-mg` 加载 minigraph 后变 `admin`/`password`。测试访问用 `password`。
- `Makefile.work`/`slave.mk`/`rules/config.user` 的本地 add-host/proxy 改动**不 commit**(本地加速)。
- 测试相关代码修复可 commit 但调通前**不 push**。
- 双语产出物:本计划产出的每个文档是两个文件(`-en.md` + `-zh.md`)。
- 宿主:47GB RAM,清理后 ~74GB 可用磁盘。T0 需 ≥20GB RAM(满足)。一个测试床磁盘够。

## 文件结构

| 文件/产物 | 职责 | 创建/修改 |
|---|---|---|
| `~/veos-vm/images/` + `~/sonic-vm/images/` | 存 sonic-vs.img + cEOS tar | 创建(宿主) |
| `br` OVS/linux 桥 | 管理网,连 DUT + PTF + cEOS mgmt | setup-management-network.sh 建 |
| `~/sonic-mgmt/ansible/veos_vtb` | ansible inventory:`STR-ACS-VSERV-01` ansible_user = 宿主用户 | 修改 |
| `~/sonic-mgmt/ansible/group_vars/vm_host/creds.yml` | vm_host_user/password = 宿主用户/sudo | 修改 |
| `~/sonic-mgmt/ansible/password.txt` | dummy ansible-vault 密码文件 | 创建 |
| `~/sonic-mgmt/ansible/vtestbed.yaml` | testbed 行 `vms-kvm-t0`(仓库自带;核对/改) | 核对/改 |
| `/etc/sudoers`(宿主) | `<user> ALL=(ALL) NOPASSWD:ALL` 供 ansible | 修改(visudo) |
| `docs/superpowers/plans/2026-07-14-sonic-mgmt-resolute-vs-testbed-{en,zh}.md` | 本计划 | 创建 |

本计划不修改 buildimage 源码(仅测试)。inventory/creds 改动在 clone 的 `~/sonic-mgmt` 里。

---

## 任务 1:准备测试床宿主(桥 + docker + 镜像)

**文件:**
- 修改(宿主):`br` 桥,经 `setup-management-network.sh`
- 创建:`~/veos-vm/images/`、`~/sonic-vm/images/`

**接口:**
- 消费:`~/sonic-mgmt/ansible/setup-management-network.sh`、resolute `sonic-vs.img`、cEOS tar 镜像
- 产出:宿主有 `br` 管理桥、Docker CE 免 sudo、镜像就位

- [ ] **步骤 1:跑宿主 setup 脚本(建 `br` 管理桥 + 装依赖)**

```bash
cd ~/sonic-mgmt/ansible
sudo -H ./setup-management-network.sh 2>&1 | tail -20
```
预期:脚本完成,`br` 桥存在。验证:`ip link show br` 有接口。装包出错就修后重跑。

- [ ] **步骤 2:确认 Docker CE 免 sudo 可用**

```bash
docker info >/dev/null 2>&1 && echo "docker ok (no sudo)" || echo "docker needs sudo — run post-install: sudo usermod -aG docker $USER && re-login"
```
预期:`docker ok (no sudo)`。否则做 post-install 组步骤并重新登录(或 `newgrp docker`),再查。

- [ ] **步骤 3:把 resolute sonic-vs 镜像放到两个 image 目录**

```bash
mkdir -p ~/sonic-vm/images ~/veos-vm/images
sudo cp ~/sonic-buildimage-resolute/sonic-vs.img ~/sonic-vm/images/
sudo cp ~/sonic-buildimage-resolute/sonic-vs.img ~/veos-vm/images/
sudo chown $USER:$USER ~/sonic-vm/images/sonic-vs.img ~/veos-vm/images/sonic-vs.img
ls -la ~/sonic-vm/images/sonic-vs.img ~/veos-vm/images/sonic-vs.img
```
预期:两份拷贝在位,属当前用户(add-topo 需读)。

- [ ] **步骤 4:获取并放置 cEOS 镜像**

从 Arista software-download 页(免费 guest 账户)下 `cEOS64-lab-*.tar.xz`,`unxz` 后把 `.tar` 放 `~/veos-vm/images/`。确认版本与 `ansible/group_vars/vm_host/ceos.yml` 匹配(注意:4.35.0F 不工作,见 doc)。

```bash
# 手动拿到 tar 后(版本按实际调整):
ls -la ~/veos-vm/images/cEOS*.tar 2>/dev/null
cat ~/sonic-mgmt/ansible/group_vars/vm_host/ceos.yml | grep -iE 'image|version' | head
```
预期:cEOS tar 在位,`ceos.yml` 引用匹配版本。版本不符就改 `ceos.yml`。

**阻塞标记:** 步骤 4 需 Arista 提供的 cEOS 镜像。若用户未提供且无法获取,**停并报告**——带邻居 T0 无 cEOS 无法继续。

- [ ] **步骤 5:不 commit**(宿主 setup,在仓库外)。`br` 已起、镜像就位记入报告。

---

## 任务 2:配置 sonic-mgmt 容器 + inventory/creds

**文件:**
- 修改:`~/sonic-mgmt/ansible/veos_vtb`(设 ansible_user)
- 修改:`~/sonic-mgmt/ansible/group_vars/vm_host/creds.yml`(设 vm_host_user/password)
- 创建:`~/sonic-mgmt/ansible/password.txt`
- 修改(宿主):`/etc/sudoers`(visudo)

**接口:**
- 消费:`docker-sonic-mgmt:latest`(自建,pytest 9.1.1)或官方 sonic-mgmt 镜像;`setup-container.sh`
- 产出:运行中的 `sonic-mgmt` 容器(挂 `/data/sonic-mgmt`)、容器免密 SSH 到宿主、宿主 NOPASSWD sudo

- [ ] **步骤 1:用 setup-container.sh 起容器(尽量复用自建镜像)**

```bash
cd ~/sonic-mgmt
./setup-container.sh -h 2>&1 | head -40   # 找镜像复用标志
```
预期:usage 列选项。找出复用已有镜像的标志(用自建 `docker-sonic-mgmt:latest` 而非拉官方)。若 setup-container 坚持拉官方镜像也可(仍是可用执行器)——记下走的哪条。

- [ ] **步骤 2:运行 setup-container.sh**

```bash
cd ~/sonic-mgmt
./setup-container.sh -n sonic-mgmt -d /data <镜像复用标志-若有> 2>&1 | tail -20
docker exec sonic-mgmt bash -c 'ls /data/sonic-mgmt && pytest --version'
```
预期:容器 `sonic-mgmt` 运行,`/data/sonic-mgmt` 挂载,pytest 可用。

- [ ] **步骤 3:改 veos_vtb —— 设宿主登录用户**

在 `~/sonic-mgmt/ansible/veos_vtb` 的 `vm_host_1` 下找 `STR-ACS-VSERV-01`,把 `ansible_user` 设为宿主用户名(如 `sheldon-qi`):

```bash
sed -i "/STR-ACS-VSERV-01:/{n;s/ansible_user: .*/ansible_user: sheldon-qi/}" ~/sonic-mgmt/ansible/veos_vtb
grep -A3 'STR-ACS-VSERV-01' ~/sonic-mgmt/ansible/veos_vtb | head
```
预期:`ansible_user: sheldon-qi`(换成实际宿主用户)。

- [ ] **步骤 4:改 creds.yml —— 设 vm_host 用户/密码**

```bash
sed -i -e 's/^vm_host_user: .*/vm_host_user: sheldon-qi/' \
       -e 's/^vm_host_password: .*/vm_host_password: <宿主-sudo-密码>/' \
       -e 's/^vm_host_become_password: .*/vm_host_become_password: <宿主-sudo-密码>/' \
       ~/sonic-mgmt/ansible/group_vars/vm_host/creds.yml
```
预期:creds 设为宿主用户 + sudo 密码。(宿主若免密 sudo,密码值可留空;下方 visudo 步保证 NOPASSWD。)

- [ ] **步骤 5:建 dummy vault 密码文件**

```bash
echo 'abc' > ~/sonic-mgmt/ansible/password.txt
```
预期:文件创建。

- [ ] **步骤 6:宿主授 NOPASSWD sudo**

```bash
echo "sheldon-qi ALL=(ALL) NOPASSWD:ALL" | sudo tee -a /etc/sudoers.d/sonic-mgmt
sudo visudo -c   # 校验语法
```
预期:`parsed OK`。(`sheldon-qi` 换实际宿主用户。)

- [ ] **步骤 7:验证容器能免密 SSH 到宿主**

```bash
docker exec sonic-mgmt bash -c 'ssh -o StrictHostKeyChecking=no sheldon-qi@172.17.0.1 "echo HOST_OK; sudo whoami"'
```
预期:`HOST_OK` 与 `root`(NOPASSWD sudo 生效)。若 SSH 要密码,setup-container 的 SSH key 步骤需重跑;报 DONE_WITH_CONCERNS 并修 key。

- [ ] **步骤 8:修宿主家目录权限(doc 要求 755)**

```bash
sudo chmod 755 /home/sheldon-qi
```
预期:无输出(成功)。

- [ ] **步骤 9:不 commit**(inventory/creds 是 clone 里的本地产物)。

---

## 任务 3:部署 cEOS T0 拓扑(add-topo)

**文件:**
- 核对/改:`~/sonic-mgmt/ansible/vtestbed.yaml`(确保有 `vms-kvm-t0` 行)

**接口:**
- 消费:宿主桥(任务 1)、sonic-mgmt 容器 + inventory(任务 2)、sonic-vs.img + cEOS 镜像(任务 1)
- 产出:KVM DUT `vlab-01` 运行、4 个 cEOS 邻居容器、PTF 容器、OVS 桥连线

- [ ] **步骤 1:核对/定义 testbed 行**

```bash
grep -A12 'vms-kvm-t0' ~/sonic-mgmt/ansible/vtestbed.yaml | head -15
```
预期:有 `vms-kvm-t0` 条目(`topo: t0`、`dut: [vlab-01]`、`group-name`、`vm_base`、`ptf`、`ptf_image_name`)。没有就按 VsSetup doc "KVM based SONiC DUT" 章示例加。

- [ ] **步骤 2:部署拓扑(cEOS 默认,不需 start-vms)**

```bash
docker exec sonic-mgmt bash -c 'cd /data/sonic-mgmt/ansible && ./testbed-cli.sh -t vtestbed.yaml -m veos_vtb add-topo vms-kvm-t0 password.txt' 2>&1 | tail -30
```
预期:playbook 完成,建出 KVM DUT `vlab-01` + 4 对 cEOS(`net_*`/`ceos_*`)+ PTF。`cached_topologies_path file content is empty` 是正常的。

- [ ] **步骤 3:验证拓扑容器 + DUT**

```bash
docker ps --format '{{.Names}} {{.Image}} {{.Status}}' | grep -E 'ceos_|net_|ptf_'
sudo virsh list --name | grep vlab-01
```
预期:8 个 cEOS/net 容器 + 1 个 ptf 容器运行,`vlab-01` 在列表。

- [ ] **步骤 4:不 commit。** 拓扑就位记入报告。

---

## 任务 4:在 DUT 上部署 minigraph(deploy-mg)

**文件:**
- (无文件改动 —— 向运行中 DUT 推配置)

**接口:**
- 消费:运行中拓扑(任务 3)、`veos_vtb` 的 minigraph 模板
- 产出:DUT 加载完整 t0 配置、mgmt IP 10.250.0.101、admin/password SSH 可用、BGP 邻居配置好

- [ ] **步骤 1:部署 minigraph**

```bash
docker exec sonic-mgmt bash -c 'cd /data/sonic-mgmt/ansible && ./testbed-cli.sh -t vtestbed.yaml -m veos_vtb deploy-mg vms-kvm-t0 veos_vtb password.txt' 2>&1 | tail -25
```
预期:playbook 完成,配置加载到 `vlab-01`。

- [ ] **步骤 2:验证 SSH 到 DUT(密码已是 `password`)**

```bash
sshpass -p password ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null admin@10.250.0.101 'show version; show ip bgp sum' 2>&1 | tail -25
```
预期:SONiC 版本 + BGP 摘要含 4 个 ARISTA 邻居(State/PfxRcd 会话起来后填充)。若 BGP 显示 0/Idle,等 60 秒再查。

- [ ] **步骤 3:确认运行中 DUT 的 resolute 身份**

```bash
sshpass -p password ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null admin@10.250.0.101 'cat /etc/os-release | grep -E "PRETTY|CODENAME|ID="; uname -r'
```
预期:`Ubuntu 26.04 LTS`、`resolute`、`ID=ubuntu`、`7.0.0-1002-sonic`。

- [ ] **步骤 4:不 commit。** DUT 已配置 + resolute 身份确认记入报告。

---

## 任务 5:跑完整 T0 测试套件

**文件:**
- (仅测试执行;报告是产出)

**接口:**
- 消费:完整部署的 T0 测试床(任务 4)
- 产出:T0 测试套件的 PASS/FAIL

- [ ] **步骤 1:先跑单项 sanity 测试(链路闸门)**

```bash
docker exec sonic-mgmt bash -c 'cd /data/sonic-mgmt/tests && ./run_tests.sh -n vms-kvm-t0 -d vlab-01 -c bgp/test_bgp_fact.py -f vtestbed.yaml -i ../ansible/veos_vtb' 2>&1 | tail -30
```
预期:`test_bgp_fact` PASS(doc 的"它能工作"标杆测试)。失败说明测试床不健康——先调试再跑全量。

- [ ] **步骤 2:枚举 T0 测试集**

```bash
# 找标记为 t0 拓扑的测试
docker exec sonic-mgmt bash -c 'cd /data/sonic-mgmt/tests && grep -rl --include="test_*.py" "topology.*t0\|t0" . | head -40'
```
预期:t0 可跑测试文件列表。记下供全量跑。

- [ ] **步骤 3:跑完整 T0 套件(日志写文件;耗时长)**

```bash
docker exec sonic-mgmt bash -c 'cd /data/sonic-mgmt/tests && ./run_tests.sh -n vms-kvm-t0 -d vlab-01 -c <t0-测试列表> -f vtestbed.yaml -i ../ansible/veos_vtb' > ~/t0-full-run.log 2>&1 &
# (步骤 2 的测试列表;后台跑,监控)
```
预期:跑完,有按模块的 PASS/FAIL 摘要。

- [ ] **步骤 4:遇 FAIL 用 systematic-debugging** —— 区分 resolute 回归 vs 测试床/测试本身问题;根因不清时对 202605-clone 非 resolute sonic-vs 做 A/B。

- [ ] **步骤 5:除非需 resolute 专项修复,否则不 commit。**

---

## 任务 6:产出双语测试报告

**文件:**
- 创建:`docs/superpowers/plans/2026-07-14-sonic-mgmt-resolute-vs-testbed-report-en.md`
- 创建:`docs/superpowers/plans/2026-07-14-sonic-mgmt-resolute-vs-testbed-report-zh.md`

**接口:**
- 消费:任务 1–5 结果
- 产出:提交到 `202605_resolute_doc` 的双语报告

- [ ] **步骤 1:写英文报告** —— 宿主 prep 结果、容器/inventory 方式、add-topo 结果、deploy-mg 结果(resolute 身份)、T0 套件逐测试 PASS/FAIL、FAIL 的根因备注、resolute 迁移总体结论。

- [ ] **步骤 2:写中文报告** —— 完整翻译,同结构(两个文件,非混排)。

- [ ] **步骤 3:在文档分支 commit**

```bash
cd ~/sonic-buildimage
git add docs/superpowers/plans/2026-07-14-sonic-mgmt-resolute-vs-testbed-report-en.md docs/superpowers/plans/2026-07-14-sonic-mgmt-resolute-vs-testbed-report-zh.md
git commit -m "docs: add sonic-mgmt resolute vs T0 testbed test report (zh + en)"
```
预期:含两文件的 commit。

---

## 自检备注

- **spec 覆盖:** spec Phase 1(sanity)+ 用户 `/goal` 扩展(带邻居 T0 + 全 T0 套件)都覆盖:任务 1–2 setup、任务 3 拓扑、任务 4 配置、任务 5 测试、任务 6 报告。
- **v1 plan 作废:** v1(手动 virsh + user-mode 端口转发)已删——基于过时的 `platform/vs/sonic.xml` 模板(机型 `pc-i440fx-1.5` 不支持、`-redir` 已移除、libvirt `<protocol>` hostfwd 被静默丢弃)。v2 逐字用官方 `testbed-cli.sh` 流程,源自 `README.testbed.VsSetup.md`。
- **凭据更正:** 裸 sonic-vs admin 密码是 `YourPaSsWoRd`(rules/config DEFAULT_PASSWORD),**非 `admin`**。`deploy-mg` 后变 `password`。v1 plan 的 `admin/admin` 假设错了。
- **开放依赖:** 任务 1 步骤 4(cEOS 镜像)需 Arista 提供的镜像。若无,任务 3(add-topo)无法建邻居——升级给用户。
- **磁盘/内存:** 宿主 74GB 可用 + 47GB RAM(40 可用)。T0 需 ≥20GB RAM(满足)。磁盘够一个测试床。
