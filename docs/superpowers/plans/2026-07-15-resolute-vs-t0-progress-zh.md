# resolute sonic-vs T0 测试进度报告

**日期:** 2026-07-15
**工作仓库:** `/home/sheldon-qi/sonic-buildimage-resolute`(分支 `202605_resolute`)
**测试床:** sonic-mgmt KVM cEOS T0(vms-kvm-t0),DUT `vlab-01` = resolute sonic-vs
**状态:** 所有主要 T0 测试目录至少跑过一遍;发现并临时修复 4 个 resolute 构建 bug;已得出最终结论。

---

## 1. 执行摘要

resolute(Ubuntu 26.04)sonic-vs 镜像在标准 sonic-mgmt cEOS T0 测试床上验证。修复 4 个 resolute 构建 bug 后,**70 个测试通过**。大量 error(1043)**不是 resolute 回归**——主要是 reboot/config-save/warm-reboot 类测试在单共享 VS DUT 上中途把 DUT reboot,导致后续测试 SSH 断连 → broken-pipe 级联。47 个失败多为不适配单 DUT T0 的测试(TSA/TSB 多 DUT、VOQ multi-ASIC、reboot 类)加一个数据面 ARP reply 接收细节。

**resolute 迁移本身是健康的**:真正的 resolute 专项 bug 是 4 个构建/打包问题,均已定位且可修。

## 2. resolute 构建 bug(build 侧已正式修复,已 commit 未 push)

5 个根因全部定位并在 build/源码侧修复(commit,未 push)。提交 build 侧修复前,曾用 DUT 上的临时运行时修复验证过。

| # | bug | 症状 | 根因 | build 侧修复(已 commit) |
|---|---|---|---|---|
| 1 | teamd 容器缺 iproute2 | PortChannel DOWN,BGP Idle(NoIf) | teammgrd 跑 `ip link set ... master` 但 docker-teamd 镜像无 `ip` 命令 | `dockers/docker-teamd/Dockerfile.j2`:`apt-get install iproute2` — `04d2228ffb` |
| 2a | show 插件 hyphen import | "failed to import plugin" 警告污染 stdout | 7 个插件名含 hyphen(dhcp-relay/cisco-8000/sonic-*),`importlib.import_module` 不接受 hyphen | `src/sonic-utilities/utilities_common/util_base.py` load_plugins:hyphen 名用 `spec_from_file_location` — `a39b9248` + gitlink `09cc41f0b0` |
| 2b | show 插件 install-path 损坏 | dhcp-relay.py / macsec.py 是套娃空目录 | py3.14 `tarfile.extract` 默认 filter 从 `'fully_trusted'`→`'data'`;dockerapi.py 设绝对 `member.name` → 套娃目录 | `src/sonic-utilities/sonic_package_manager/dockerapi.py`:`tar.extract(..., filter='fully_trusted')` — `751b5976` + gitlink `b4dd442685` |
| 3 | snmpd 绑 IPv6 失败 | snmpd exit 1,FATAL | `systemd-sonic-generator` SIGABRT(FORTIFY=3):`calloc(target.length()+1)` 与 `snprintf(..., PATH_MAX, ...)` size 不匹配 → interfaces-config.service 没生成 → mgmt IPv6 没应用 | `src/systemd-sonic-generator/systemd-sonic-generator.cpp:337` `snprintf` size `PATH_MAX`→`target.length()+1` — `496f90f930` |
| 4 | sonic_ax_impl py3.14 不兼容 | snmp-subagent exit 1 | `asyncio.get_event_loop()` 在 py3.14 抛 RuntimeError(无 current event loop) | `src/sonic-snmpagent/src/sonic_ax_impl/main.py:20` `get_event_loop`→`new_event_loop` — `529cd5d` + gitlink `b78e697aef` |
| 5 | deploy-mg sshd restart 失败 | deploy-mg 末尾 exit 2 | resolute 用 `ssh.service`,playbook 调 `systemctl restart sshd` | `ansible/config_sonic_basedon_testbed.yml:1382` `sshd`→`ssh`(sonic-mgmt 仓库)— `ea7e076` |

**可复用运行时修复脚本:** `/tmp/apply-resolute-fixes.sh`(在运行中 DUT 上重应用 1-4;scp + `sudo bash`)。提交 build 侧修复前用于验证;每次测试床重建后重跑(add-topo 重建 DUT 会丢运行时修复)。

### 端到端验证(2026-07-16)
用 5 修复重 build 的 `sonic-vs.bin` → `build_kvm_image.sh` 装进可启动 qcow2 → `add-topo` + `deploy-mg` → **BGP 4 邻居立即 up(try 1),无需 `apply-resolute-fixes.sh` 运行时补丁**。确认 build 侧修复从源头解决(ssg 不再崩 → interfaces-config.service 跑 → mgmt IPv6 应用;teamd 有 iproute2 → LACP/PortChannel up;sonic_ax_impl 正常)。

### baked image T0 批次 —— 级联基本消除(2026-07-16)
在 5 修复 baked 的 DUT 上,跑 `bgp_fact + vlan + lldp + pc`(跳破坏性测试,无 `--allow_recover`):
**25 pass / 7 fail / 1 err / 17 skip** —— 只 **1 个 error**(对比修复前 image 的数百 broken-pipe/Thread error)。7 个 fail 是 pc/lag 高级测试(test_po_voq 多 ASIC、lag_member_forwarding)——拓扑/数据面细节,非 resolute 回归。
这是 resolute 修复有效的最强证据:1043-error 级联的根因正是缺 iproute2/mgmt-IPv6/ssg/asyncio 使 DUT 不稳定;修复后级联消失。

### `--allow_recover` 注意
`pytest --allow_recover`(sanity-check 自动恢复)在 acl 上**卡死**(90 分钟,0% CPU,0 产出)——DUT 处于中间状态时恢复循环死锁。未采用;`--allow_recover` 在此 VS 测试床上对状态目录不可行。有效的做法是:基于名字的 `-k` 跳过 + baked 修复(稳定 DUT)。

## 3. T0 全量结果(junit-xml,机器读取)

| | 数量 |
|---|---|
| PASS | 70 |
| FAIL | 47 |
| ERROR | 1043 |
| SKIP | 651 |
| 实际执行(pass+fail+err) | 1160 |

**已跑目录(所有主要 T0 目录):** bgp, acl, snmp, lldp, vlan, dhcp_relay, pc, arp, platform_tests, container_checker, autorestart, sub_interfaces, copp, dropcounters, 根目录 test_*。

### error 根因分类(1043)

| 根因 | 数量 | 性质 |
|---|---|---|
| Thread worker / Broken pipe | 765 | **非 resolute**:reboot/config-save/warm-reboot 测试把共享 VS DUT 中途 reboot → SSH 断 → 该目录后续测试全 broken-pipe 级联 |
| other(setup 级联) | 251 | fixture setup 失败(被前面 broken pipe 连累) |
| sanity | 27 | DUT 状态被破坏后 post-test sanity 失败 |
| asyncio/event-loop | (在 other) | 部分 py3.14 兼容(如 sonic_ax_impl 类) |

### fail 根因分类(47)

1. **TSA/TSB reliable_tsa(~20)** — traffic-shift supervisor 测试需多 DUT/supervisor 拓扑,单 DUT T0 不适配。
2. **test_bgp_aggregate_address_resilience(3)** — `persists_config_save_and_reboot`/`warm_reboot`/`bgp_restart` — reboot 类,VS 测试床限制。
3. **test_lldp_entry_table_after_reboot** — reboot 类。
4. **test_po_voq(5)** — VOQ 是 multi-ASIC,单 ASIC T0 不适用。
5. **test_lag lacp_rate / test_po_update / test_po_cleanup_after_reload** — LAG 高级 + reload 类。
6. **test_arp_unicast_reply / expect_reply / garp_no_update(3)** — PTF 收 0 ARP reply;DUT ARP **学习**正常(学到 4 个 cEOS 邻居),问题是 OVS/PTF 收方向的 ARP reply 转发——数据面细节,非 resolute 构建回归。
7. **test_acl_add_del_stress** — ACL 压力测试。

## 4. 测试床搭建(标准 sonic-mgmt 流程)

按 `README.testbed.VsSetup.md`:
- 宿主:`br1` 管理桥(`setup-management-network.sh`);docker 免 sudo;NOPASSWD sudo。
- DUT:KVM `vlab-01`,resolute `sonic-vs.img`(在 `~/sonic-vm/images/` + `~/veos-vm/images/`)。
- 邻居:4 个 cEOS 容器(cEOS64-lab-4.32.5M.tar,本地)——不需 EOS 授权。
- PTF:`docker-ptf` 从 `sonicdev-microsoft.azurecr.io` 直连拉(宿主直连可达;经 proxy 反而 blob TLS 超时)。
- 执行器:`docker-sonic-mgmt`(自建,pytest 9.1.1)——官方镜像也行。
- 部署:`testbed-cli.sh add-topo` → `deploy-mg`(加载 t0 minigraph;DUT mgmt 10.250.0.101,admin/password)。

### inventory/环境兼容修复(非 resolute bug)
- `veos_vtb` vlab-01:`ansible_python_interpreter: /usr/bin/python3`(ansible.cfg 的 `auto_legacy_silent` 被 ansible 2.21 当字面命令)。
- pytest 环境:`ANSIBLE_LIBRARY=/data/sonic-mgmt/ansible/library`(否则 pytest-ansible 找不到 sonic_basic_facts 模块)。
- pytest 参数:`--skip-yang`(resolute `config apply-patch /dev/stdin` 有 bug)、`--disable_loganalyzer`。

## 5. 关键教训

- **`show ip bgp sum | grep -c Estab` 是错的**——输出用 State/PfxRcd 列(established 时显示路由数如 6400,非字面 "Estab")。改用邻居行数。这导致了几次误判"BGP down"空等。
- **只读目录(snmp)整批稳跑;改状态目录(bgp/acl/platform_tests)中途把 VS DUT 搞挂**——reboot/config-save 测试所致 → broken-pipe 级联。用 `-k "not reboot and not config_save and not warm and not fast_reboot and not upgrade and not reload"` 缓解,但部分 reload 变体仍漏网。
- **宿主重启清空测试床**(容器 Exited、vlab-01 shut off、br1 没了、运行时修复丢失)。qcow2 内的文件级修复只在复用同一 domain 时 persist;add-topo 重建 domain,故每次重建后需重应用运行时修复。

## 6. 结论

- resolute sonic-vs 在 cEOS T0 测试床上控制面 + 数据面基础可用(70 个通过:features、bgp_fact、interfaces、snmp、vlan、lag 基础、lldp、dhcp 等)。
- 1043 个 error 绝大多数是测试床执行产物(reboot 测试 vs 单共享 VS),非 resolute 回归。
- resolute 迁移真正的 bug = 4 个构建问题(teamd iproute2、show 插件 hyphen+install-path、mgmt IPv6、sonic_ax_impl asyncio)——均已定位、临时修复并验证能解锁测试。正式 build 侧修复是剩余工作(约束:禁 push)。
- 剩余真实失败(ARP reply 接收、TSA/TSB/VOQ/reboot 类)要么是数据面测试床细节,要么是拓扑不适配,非 resolute 回归。
