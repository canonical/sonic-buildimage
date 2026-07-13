# sonic-mgmt resolute VS sanity 测试 — 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: 用 superpowers:subagent-driven-development(推荐)或 superpowers:executing-plans 逐任务执行本计划。步骤用复选框(`- [ ]`)语法跟踪。

**目标:** 对 resolute `sonic-vs` KVM DUT 跑一组不依赖邻居的 sonic-mgmt sanity 测试,确认 resolute 迁移没有破坏容器健康、配置管线与 show 命令。

**架构:** 把 resolute `sonic-vs.img` 作为 KVM DUT 启动(mgmt 走 QEMU user-mode networking,SSH 在宿主 3040 端口)。clone `sonic-net/sonic-mgmt` @ `202605`。构建最小 inventory + testbed 定义,指向 `127.0.0.1:3040`。在 `docker-sonic-mgmt` 容器内跑 4 个无邻居的 pytest 模块。Phase 2(PTF)不在本计划范围。

**技术栈:** KVM/QEMU + libvirt(DUT)、`docker-sonic-mgmt`(pytest 9.1.1 执行器)、sonic-mgmt ansible+pytest 框架 @ 分支 `202605`。

## 全局约束

- 构建仓库:`~/sonic-buildimage-resolute`,分支 `202605_resolute`,HEAD `3beabfff4c`。`Makefile.work` / `slave.mk` / `rules/config.user` 的本地 add-host/proxy 改动**不 commit**(仅本地加速)。
- 文档分支 `202605_resolute_doc` 存放 spec/plan 文档(已 commit)。
- 所有网络操作(clone、pip)走 proxy:`https_proxy=http://192.168.1.210:6152`,`no_proxy=archive.ubuntu.com,security.ubuntu.com,10.211.55.9,localhost,127.0.0.1`。
- DUT 凭据:`admin` / `admin`(SONiC 默认);SSH 经 `ssh -p 3040 admin@127.0.0.1`。
- sonic-mgmt 分支必须 `202605`(与构建匹配)。已 clone 到 `~/sonic-mgmt`(HEAD `00c4dac`)。
- 测试相关代码修复可 commit 但调通前**不 push**。
- 双语产出物:本计划产出的每个文档是两个文件(`-en.md` + `-zh.md`),见 memory `user-language-preference`。

## 文件结构

| 文件 | 职责 | 创建/修改 |
|---|---|---|
| `~/kvm-sonic-resolute/sonic.xml` | DUT 启动定义(改写磁盘路径 + 保留 user-mode mgmt + 3040 端口转发) | 创建(从 buildimage 拷贝、改路径) |
| `~/sonic-mgmt/ansible/veos_vtb`(inventory 目录) | 指向 `127.0.0.1:3040` 的 ansible inventory + host/group 变量 | 创建(setup-container.sh 生成 + 手改) |
| `~/sonic-mgmt/ansible/vtestbed.yaml` | KVM DUT 的 testbed 定义行(拓扑 `ptf32`/`t0` 式,无邻居) | 创建 |
| `docs/superpowers/plans/2026-07-13-sonic-mgmt-resolute-vs-test-{en,zh}.md` | 本计划 | 已创建 |

本计划不修改 buildimage 源码(仅测试)。inventory/testbed 文件放在 clone 的 `~/sonic-mgmt` 下(非 buildimage 仓库),以免污染构建树。

---

## 任务 1:启动 resolute sonic-vs DUT 并验证 SSH

**文件:**
- 创建:`~/kvm-sonic-resolute/sonic.xml`
- (无测试文件 — 验证即 SSH 登录)

**接口:**
- 消费:`~/sonic-buildimage-resolute/sonic-vs.img`(已构建)、`~/sonic-buildimage-resolute/platform/vs/sonic.xml`(模板)
- 产出:运行中的 KVM domain `sonic`,可达 `ssh -p 3040 admin@127.0.0.1`,console 在 `telnet 127.0.0.1 7000`

- [ ] **步骤 1:准备 DUT 启动 XML**

```bash
mkdir -p ~/kvm-sonic-resolute
cp ~/sonic-buildimage-resolute/platform/vs/sonic.xml ~/kvm-sonic-resolute/sonic.xml
# 改写硬编码磁盘路径指向 resolute 镜像
sed -i "s#/data/sonic/sonic-buildimage/target/sonic-vs.img#$HOME/sonic-buildimage-resolute/sonic-vs.img#" ~/kvm-sonic-resolute/sonic.xml
grep 'source file' ~/kvm-sonic-resolute/sonic.xml   # 确认路径已指向 /home/sheldon-qi/sonic-buildimage-resolute/sonic-vs.img
```

- [ ] **步骤 2:清除同名旧 domain 后创建**

```bash
sudo virsh destroy sonic 2>/dev/null; sudo virsh undefine sonic 2>/dev/null
sudo virsh create ~/kvm-sonic-resolute/sonic.xml
sudo virsh list --name | grep '^sonic$'   # 预期:sonic
```
预期:`sonic` 在运行列表中。

- [ ] **步骤 3:经 console 等待启动**

```bash
# console 是 telnet 127.0.0.1 7000,等登录提示
( echo ""; sleep 90; ) | telnet 127.0.0.1 7000 2>/dev/null | tail -20
```
预期:输出含 `sonic login:`。若没有,继续等(SONiC 首次启动拉起容器约 2-3 分钟)。

- [ ] **步骤 4:验证宿主 3040 端口 SSH**

```bash
sshpass -p admin ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 3040 admin@127.0.0.1 'show version; show platform summary; docker ps --format "{{.Names}}" | wc -l'
```
预期:SONiC 版本输出 + 平台 `x86_64-kvm_x86_64-r0` + 容器计数 `12`(核心容器)。若 SSH 拒绝,VM 仍在启动——60 秒后重跑步骤 3/4。

- [ ] **步骤 5:确认 resolute 身份(迁移检查点 0)**

```bash
sshpass -p admin ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 3040 admin@127.0.0.1 'cat /etc/os-release | grep -E "PRETTY|VERSION_CODENAME|ID="; uname -r'
```
预期:`PRETTY_NAME="Ubuntu 26.04 LTS"`、`VERSION_CODENAME=resolute`、`ID=ubuntu`、内核 `7.0.0-1002-sonic`。

- [ ] **步骤 6:不 commit**(DUT XML 是产物,在仓库外)。把可用的 SSH 命令记入测试报告备注。

---

## 任务 2:配置 sonic-mgmt 执行器容器 + 最小 inventory

**文件:**
- 修改:`~/sonic-mgmt/ansible/veos_vtb`(inventory 目录,先生成后改)
- 创建:`~/sonic-mgmt/ansible/vtestbed.yaml`(testbed 行)

**接口:**
- 消费:`docker-sonic-mgmt:latest` 镜像(2026-07-13 构建)、任务 1 的运行中 DUT
- 产出:host-pattern `vlab-01` 解析到 `127.0.0.1:3040` 的 inventory + 引用该 host 的 testbed 条目 `vms-kvm-t0`

- [ ] **步骤 1:启动 docker-sonic-mgmt 容器(复用自建镜像)**

```bash
docker run -d --name sonic-mgmt --network host \
  -v ~/sonic-mgmt:/data \
  -e https_proxy=http://192.168.1.210:6152 \
  -e no_proxy=archive.ubuntu.com,security.ubuntu.com,10.211.55.9,localhost,127.0.0.1 \
  docker-sonic-mgmt:latest
docker exec sonic-mgmt bash -c 'echo container-ok; pytest --version'
```
预期:`container-ok` 与 `pytest 9.1.1`。

- [ ] **步骤 2:用 setup-container.sh 生成 inventory 骨架(宿主执行,在仓库内)**

`setup-container.sh` 是宿主侧工具,构建 inventory 目录。先看选项,再生成 `veos_vtb` 式 inventory。

```bash
cd ~/sonic-mgmt
./setup-container.sh -h 2>&1 | head -40   # 读选项:找 -n/--name、-i/--inventory、-k/--ssh-key、镜像复用标志
```
预期:usage 文本列出选项。找出**复用已有镜像**而非拉官方镜像的标志(确保用我们自建的 `docker-sonic-mgmt`)。

- [ ] **步骤 3:运行 setup-container.sh 生成 inventory**

```bash
cd ~/sonic-mgmt
# 用步骤 2 找出的镜像复用标志运行。若 setup-container 坚持拉自己的镜像,改用步骤 4 手建兜底
./setup-container.sh -n sonic-mgmt <镜像复用标志> 2>&1 | tail -20
ls ansible/veos_vtb/ 2>/dev/null | head
```
预期:`ansible/veos_vtb/` 存在且含 `hosts` 文件。若 setup-container 拉了别的镜像且不可接受,放弃它,走步骤 4 兜底。

- [ ] **步骤 4(setup-container 不复用我们镜像时的兜底):手建最小 inventory**

```bash
mkdir -p ~/sonic-mgmt/ansible/veos_vtb
cat > ~/sonic-mgmt/ansible/veos_vtb/hosts <<'EOF'
[lab]
vlab-01

[lab:vars]
ansible_host=127.0.0.1
ansible_port=3040
ansible_user=admin
ansible_password=admin
ansible_ssh_common_args=-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null

[sonic]
vlab-01

[sonic:vars]
ansible_host=127.0.0.1
ansible_port=3040
ansible_user=admin
ansible_password=admin
ansible_ssh_common_args=-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
EOF
```
预期:文件写入。(步骤 3 的产物 OR 步骤 4 的手建,二选一。)

- [ ] **步骤 5:创建 testbed 定义行**

```bash
cat > ~/sonic-mgmt/ansible/vtestbed.yaml <<'EOF'
- conntop: { }
  duts:
    - vlab-01
  tbinfo:
    "comment": "resolute sonic-vs KVM, no EOS neighbors, no PTF (Phase 1 sanity)"
    "group-name": "vms-kvm-t0"
    "host-name-pattern": "vlab-VM[0-9]{2}"
    "ptf": ""
    "ptf_image": ""
    "ptf_ip": ""
    "server": ""
    "topo": "ptf32"      # 无邻居占位;sanity 测试不消费 PTF
    "vm_base": ""
    "dut": ["vlab-01"]
EOF
```
预期:文件写入。(确切 schema 可能需按 conftest 解析调整——任务 3 步骤 2 验证。)

- [ ] **步骤 6:验证 ansible 经 inventory 可达 DUT**

```bash
docker exec sonic-mgmt bash -c 'cd /data && ansible -i ansible/veos_vtb -m ping vlab-01 -u admin -k' <<< 'admin'
```
预期:`vlab-01 | SUCCESS => { ... "ping": "pong" ... }`。若失败,inventory/testbed 形状不对——先修再继续(这是 spec 风险章节的链路层闸门)。

- [ ] **步骤 7:不 commit**(inventory 在 clone 里,非 buildimage 仓库;是本地产物)。

---

## 任务 3:跑 Phase 1 sanity 测试(4 个无邻居模块)

**文件:**
- (无文件改动 — 仅测试执行;报告是备注)

**接口:**
- 消费:运行中 DUT(任务 1)、已配置 inventory+testbed(任务 2)
- 产出:4 个 pytest 模块的 PASS/FAIL

- [ ] **步骤 1:确认确切测试路径存在**

```bash
docker exec sonic-mgmt bash -c 'cd /data/tests && ls -1 test_features.py container_checker/test_container_checker.py autorestart/test_container_autorestart.py config_setup/test_config_setup_boot.py'
```
预期:4 个路径都打印出(无 "No such file")。这些是规划时确认的无邻居模块。

- [ ] **步骤 2:空跑 conftest 收集,验证 inventory/testbed 管线**

```bash
docker exec sonic-mgmt bash -c 'cd /data/tests && pytest --inventory ../ansible/veos_vtb --host-pattern vlab-01 --testbed vms-kvm-t0 --testbed_file ../ansible/vtestbed.yaml --collect-only test_features.py 2>&1 | tail -20'
```
预期:收集到 `test_features.py::test_show_features[vlab-01]`(或类似),无 inventory/testbed 解析错误。若 testbed schema 报错,调整 `vtestbed.yaml` 直到收集成功。

- [ ] **步骤 3:跑 `test_features`**

```bash
docker exec sonic-mgmt bash -c 'cd /data/tests && pytest --inventory ../ansible/veos_vtb --host-pattern vlab-01 --testbed vms-kvm-t0 --testbed_file ../ansible/vtestbed.yaml --log-cli-level info --disable_loganalyzer test_features.py 2>&1 | tail -30'
```
预期:`test_show_features` PASS。验证 show/features 管线——迁移最可能的回归面。

- [ ] **步骤 4:跑 `test_container_checker`**

```bash
docker exec sonic-mgmt bash -c 'cd /data/tests && pytest --inventory ../ansible/veos_vtb --host-pattern vlab-01 --testbed vms-kvm-t0 --testbed_file ../ansible/vtestbed.yaml --log-cli-level info --disable_loganalyzer container_checker/test_container_checker.py 2>&1 | tail -30'
```
预期:PASS——12 核心容器全部 up/healthy。

- [ ] **步骤 5:跑 `test_container_autorestart`**

```bash
docker exec sonic-mgmt bash -c 'cd /data/tests && pytest --inventory ../ansible/veos_vtb --host-pattern vlab-01 --testbed vms-kvm-t0 --testbed_file ../ansible/vtestbed.yaml --log-cli-level info --disable_loganalyzer autorestart/test_container_autorestart.py 2>&1 | tail -30'
```
预期:PASS——无意外容器重启(验证迁移后 systemd/service 层)。

- [ ] **步骤 6:跑 `test_config_setup_boot`**

```bash
docker exec sonic-mgmt bash -c 'cd /data/tests && pytest --inventory ../ansible/veos_vtb --host-pattern vlab-01 --testbed vms-kvm-t0 --testbed_file ../ansible/vtestbed.yaml --log-cli-level info --disable_loganalyzer config_setup/test_config_setup_boot.py 2>&1 | tail -30'
```
预期:PASS——boot 后配置管线就绪。

- [ ] **步骤 7:记录结果。** 每个模块记 PASS/FAIL。若有 FAIL,按 systematic-debugging:抓测试 traceback,判断是 resolute 回归还是测试床产物,根因不清时(按 spec)对 `~/sonic-buildimage-202605-clone` sonic-vs 做 A/B。

- [ ] **步骤 8:除非需要 resolute 专项修复,否则不 commit。** 若对 buildimage 仓库做了修复,在 `202605_resolute` 上 commit(不 push)。

---

## 任务 4:产出测试报告(双语)

**文件:**
- 创建:`~/sonic-buildimage/docs/superpowers/plans/2026-07-13-sonic-mgmt-resolute-vs-test-report-en.md`
- 创建:`~/sonic-buildimage/docs/superpowers/plans/2026-07-13-sonic-mgmt-resolute-vs-test-report-zh.md`

**接口:**
- 消费:任务 1/2/3 结果
- 产出:提交到 `202605_resolute_doc` 的双语报告

- [ ] **步骤 1:写英文报告**

内容:DUT 身份(任务 1 步骤 5 的 os-release/uname)、所选 inventory/testbed 方式(任务 2 步骤 3 vs 4)、逐模块 PASS/FAIL 表(任务 3 步骤 3-6)、FAIL 的根因备注、总体结论(resolute build 控制面/配置管线回归状态)。

- [ ] **步骤 2:写中文报告** — 完整翻译,同结构(不是单文件双语)。

- [ ] **步骤 3:在文档分支 commit**

```bash
cd ~/sonic-buildimage
git checkout 202605_resolute_doc 2>/dev/null
git add docs/superpowers/plans/2026-07-13-sonic-mgmt-resolute-vs-test-report-en.md docs/superpowers/plans/2026-07-13-sonic-mgmt-resolute-vs-test-report-zh.md
git commit -m "docs: add sonic-mgmt resolute vs sanity test report (zh + en)"
```
预期:含两文件的 commit 创建。

---

## 自检备注(给执行者)

- **spec 覆盖:** spec Phase 1(4 项 sanity)= 任务 3(4 个模块)。spec "boot DUT" = 任务 1。spec "clone + setup" = 任务 2。spec "对照基线" = 任务 3 步骤 7(仅 FAIL 时 A/B)。spec Phase 2(PTF)明确排除范围。spec "双语产出物" = 任务 4。
- **测试名修正:** spec 写了 `test_config_reload` / `test_sonic` / `test_show_interface`——这些路径在 sonic-mgmt `202605` **不存在**。本计划替换为已确认存在的无邻居模块(`test_features`、`test_container_checker`、`test_container_autorestart`、`test_config_setup_boot`)。spec 的*意图*(容器健康 + 配置管线 + show)完全覆盖;只是测试名按真实代码树更正。
- **网络修正:** spec 假设 virsh default-net DHCP;真实 `sonic.xml` 用 QEMU user-mode networking + `-redir tcp:3040::22`。故 inventory 指向 `127.0.0.1:3040`,非 192.168.122.x。
- **任务 2 的开放问题:** `setup-container.sh` 能否复用我们自建镜像,在任务 2 步骤 2-3 经验性确认,有不依赖它的手建兜底(步骤 4)。
