# Resolute 完全干净从零构建 — 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**目标:** 在 `/home/sheldon-qi/sonic-buildimage-resolute` 执行一次完全干净的端到端从零构建:清理所有累积构建产物(仅保留 git 跟踪的配置、宿主机修复、上游基础镜像),然后从零构建 `sonic-vs.img.gz`,成功后再从零构建 `sonic-broadcom.bin`。

**架构:** 用 SONiC 官方 `make reset` 做仓库级核清(保留所有跟踪文件,清掉 fsroot*/target/src 解压目录并重置子模块),外加显式的 docker 与共享缓存清理,然后两个后台 `make` 构建(日志捕获 + 定时轮询)。broadcom 平台的 22 个修复 commit 已在 `canonical/202605_resolute`(已 push),故 broadcom 重建预期干净——除非出现新的 API 漂移,否则无需新修复。

**技术栈:** SONiC buildimage 的 Makefile.work/slave.mk、Docker CE 29.6.1(默认 DinD `--privileged`)、`sg docker` 用于非登录 shell 的 docker 访问、AppArmor `gs` override + `ip_tables` 宿主机模块作为前置。

## 全局约束

- 构建仓库:`/home/sheldon-qi/sonic-buildimage-resolute`,分支 `202605_resolute`。
- 文档仓库:`/home/sheldon-qi/sonic-buildimage`,分支 `202605_resolute_doc`(resolute 构建分支无 `docs/`,见 AGENTS.md)。
- 构建宿主机:Ubuntu 26.04(ext4 root,内核 7.0.0-27,docker-ce 29.6.1,默认 DinD `--privileged`)。
- docker 命令通过 `sg docker -c '...'` 运行(非登录 shell 需此包装才能访问 docker 组)。
- Git 时序:本次工作期间所有 commit 先只本地(不 push),直到 vs 与 broadcom 两个 build 都通过;然后统一 push(见 spec 7.3)。
- 子模块修复 gitlink 规则(spec 7.2):子模块修复必须在父仓库本地 bump gitlink(父仓库 `git add <sub>`),否则 `make reset` 的 `git submodule update --init` 会 checkout 回旧 gitlink、丢弃修复。
- 任何源码/规则修复遵循 AGENTS.md Editing Rules:最小范围、patch 文件(不直接改外部子模块源)、保留 pin。
- 子模块 commit 只 push 到 `canonical/<sub>:202605_resolute`——绝不 `sonic-net/`(上游,非我们可写)。
- 双语交付物:本计划产出的每份文档是两个文件(`-en.md` + `-zh.md`),英文为事实来源。
- 构建前宿主机修复必须在位:AppArmor `gs` local override(`/etc/apparmor.d/local/gs`)与 `ip_tables` 模块(`lsmod | grep ip_tables`)。
- memory 引用:[[sonic-build-restore]]、[[sonic-build-caches]]、[[sonic-resolute-broadcom-build-success]]、[[sonic-resolute-submodule-object-store-corruption]]。

## 文件结构

| 文件 / 产物 | 职责 | 创建/修改 |
|---|---|---|
| `docs/superpowers/plans/2026-07-21-resolute-clean-rebuild-{en,zh}.md` | 本计划 | 创建(文档仓库) |
| `docs/superpowers/specs/2026-07-21-resolute-clean-rebuild-design-{en,zh}.md` | 本计划实现的 spec | 已创建 |
| `target/build-vs.log` | vs 构建 stdout/stderr(后台) | 创建(构建仓库,reset 会清) |
| `target/build-broadcom.log` | broadcom 构建 stdout/stderr(后台) | 创建(构建仓库) |
| `target/sonic-vs.img.gz` | vs 构建产物(~2G) | 创建(构建仓库) |
| `target/sonic-broadcom.bin` | broadcom 构建产物(~2.3G ONIE installer) | 创建(构建仓库) |
| docker 镜像 / `fsroot*` / `target/` / `/var/cache/sonic/artifacts` | 被清理,非 commit 的产物 | 删除 |
| 源码/规则文件(`rules/*.mk`、`*.j2`、子模块源码) | 仅在构建错误需要时修改(fix-loop,Task 7) | 仅出错时修改 |

本计划不修改任何 buildimage 源码,除非构建错误确实需要(Task 7 fix-loop)。所有清理目标都是构建产物,从不 commit。

---

## Task 1: 安全预检(删任何东西之前的硬门)

**文件:**
- 不修改;在 `/home/sheldon-qi/sonic-buildimage-resolute` 与宿主机上只读验证。

**接口:**
- 消费:resolute 构建仓库(分支 `202605_resolute`)、宿主机的 AppArmor + `ip_tables` 状态。
- 产出:确认干净的 git 工作树、完好的子模块 object store、可达的 gitlink、在位的宿主机修复、免密 sudo——全部 gate 通过后才能跑 Task 2。

- [ ] **Step 1: 确认 git 工作树无会被 `reset --hard` 丢弃的未提交跟踪改动**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
git status -s | grep -vE '^\?\?|^ M src/' || echo "CLEAN (only untracked src/ extractions or fsroot)"
```
期望:`CLEAN (...)`,或仅是未跟踪的 `src/*/` 解压目录 / fsroot(可重建)。若任何跟踪文件显示为 modified(非 src 路径的 ` M`),停止——先处理(stash 或 commit)再继续,因为 `make reset` 会丢弃它。

- [ ] **Step 2: 干跑 `git clean` 预览将删文件(防误伤想留的文件)**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
git clean -xfdf -n > /tmp/clean-preview.txt
wc -l /tmp/clean-preview.txt        # 将删除多少文件
# 完整审查列表(勿截断——本步目的就是抓住列表任意位置想留的文件)
less /tmp/clean-preview.txt         # 或:grep 排除明显可重建的前缀看异常项,如 grep -vE '^(target/|src/|\.pytest_cache)'
```
期望:文件计数(可能数百/数千——target/ + 解压 `src/*/` + `.pytest_cache`)。在 `less` 里审完整列表(或 `grep -v` 掉明显可重建的前缀以浮现异常项)。若出现误删候选(一个你真想留、且非可重建产物的文件),记录并在 Task 2 前解决。**此处不要用 `head`——截断列表违背硬门的目的。**

- [ ] **Step 3: 检查子模块 object store 健康(用全量 `git submodule status` 快速查,仅对异常项针对性 fsck)**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
# git submodule status 遍历所有子模块(含嵌套)且很快;损坏的子模块会显示异常或报错
git submodule status --recursive 2>&1 | tee /tmp/submod-status.txt
echo "--- 异常行(空格/- 前缀之外的报错)---"
grep -iE 'error|fatal|missing|not a git repo|no such' /tmp/submod-status.txt || echo "all submodules OK"
# 仅当上面 grep 命中某个子模块时,对该子模块跑 fsck 定位:
# cd <that-submodule> && git fsck --no-dangling 2>&1 | tail -5
```
期望:`git submodule status --recursive` 列出所有子模块及 commit SHA(空格前缀=已初始化,`-`前缀=未初始化亦无妨——Task 2 会重新 init)。grep 应输出 `all submodules OK`(无 error/fatal/missing)。若某个子模块命中 `missing blob` 等,停止,按 [[sonic-resolute-submodule-object-store-corruption]] 的 deinit + re-clone 修复**那一个**子模块后再继续。不做全量 `foreach fsck`(子模块多,全跑慢,且 `submodule status` 已能快速暴露损坏)。

- [ ] **Step 4: 确认子模块 gitlink 可达(Canonical 改过的子模块已 push)**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
# 列出 URL 指向 canonical 的子模块(这些带 Canonical commit,必须在 canonical/<sub>:202605_resolute 上)
git config -f .gitmodules --get-regexp 'submodule.*.url' | grep -i canonical
```
期望:Canonical fork 的子模块列表。对每个,gitlink commit(来自 `git submodule status`)必须存在于 `canonical/<sub>:202605_resolute`。(broadcom 的 22 个修复 commit 已 push——见 [[sonic-resolute-broadcom-build-success]]——故这些预期可达。)若某个仅本地存在,必须先 push 到 `canonical/<sub>:202605_resolute`,否则 Task 2 的 `git submodule update --init` 无法解析。

- [ ] **Step 5: 确认宿主机修复在位(AppArmor gs + ip_tables 模块)**

```bash
ls /etc/apparmor.d/local/gs && echo "gs override present" || echo "GS OVERRIDE MISSING — bash.pdf build will fail"
lsmod | grep -q ip_tables && echo "ip_tables loaded" || echo "IP_TABLES MISSING — iptables-legacy in DinD will fail"
```
期望:`gs override present` 且 `ip_tables loaded`。任一 MISSING 则先恢复(AppArmor:写 `/etc/apparmor.d/local/gs` 含 `owner file rw /sonic/**,` 与 `owner file rw /var/*/**,`,再 `sudo apparmor_parser -r /etc/apparmor.d/gs`;ip_tables:`echo ip_tables | sudo tee /etc/modules-load.d/ip_tables.conf && sudo modprobe ip_tables`)再继续。

- [ ] **Step 6: 确认免密 sudo(`make reset` 的 `sudo rm -rf fsroot*` 需要)**

```bash
sudo -n true && echo "passwordless sudo OK" || echo "NEEDS passwordless sudo"
```
期望:`passwordless sudo OK`。否则先为构建用户配置 NOPASSWD 再继续。

- [ ] **Step 7: commit 计划文档(仅本地,不 push——见 7.3)**

```bash
cd /home/sheldon-qi/sonic-buildimage
git add docs/superpowers/plans/2026-07-21-resolute-clean-rebuild-en.md docs/superpowers/plans/2026-07-21-resolute-clean-rebuild-zh.md
git commit -m "docs: resolute fully-clean from-scratch build plan (zh + en)"
```
期望:`202605_resolute_doc` 上创建 commit。暂不 push(push 在 Task 7 两个 build 都过后)。

---

## Task 2: 官方 `make reset`(仓库级核清)

**文件:**
- 删除(root 属主):`fsroot.docker.resolute/`(~68G)、`fsroot-broadcom/`、`fsroot-broadcom-dnx/`、`fsroot-broadcom-legacy-th/`、`fsroot-vs/`。
- 删除:`target/`(含 `target/ccache/`、`target/vcache/`)、解压的 `src/*/` 版本目录、`.pytest_cache/`。
- 保留:所有 git 跟踪文件(`rules/config.user`、`AGENTS.md`、`.gitmodules`、源码、git 历史)。

**接口:**
- 消费:Task 1 通过的 gate(干净 git、完好子模块、免密 sudo)。
- 产出:重置后的仓库工作树,无构建产物,子模块按其 gitlink commit 重新初始化。

- [ ] **Step 1: 跑官方 reset(UNATTENDED 跳过 y/N 提示)**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
make BLDENV=resolute UNATTENDED=y reset 2>&1 | tail -40
```
期望:`Reset complete!`。该目标执行 `sudo rm -rf fsroot*` → `git clean -xfdf` → `git reset --hard` → `git submodule foreach` clean+reset+remote update → `git submodule update --init --recursive`。这是慢的部分(子模块重新 init)。

- [ ] **Step 2: 删除 `fsroot*` 通配不匹配的 root 属主大文件(兜底)**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
sudo rm -f dockerfs.tar.gz fs.squashfs fs.zip
sudo rm -rf fsroot*            # 兜底,防 reset 的 sudo 通配漏匹配
ls -la | grep -E 'fsroot|\.tar\.gz|\.squashfs|\.zip'   # 期望无输出
```
期望:`ls | grep` 无输出(所有 root 属主大文件已删)。若有残留,显式删除。

- [ ] **Step 3: 验证跟踪配置在 reset 中存活**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
git status -s | grep -E 'config.user|AGENTS.md|gitmodules' && echo "UNEXPECTED change to tracked config" || echo "tracked config intact"
test -f rules/config.user && head -1 rules/config.user
```
期望:`tracked config intact` 且 `rules/config.user` 仍在(首行是注释)。`rules/config.user` 是 git 跟踪文件,故 `reset --hard` 将其恢复到已提交状态——它必须还在。

- [ ] **Step 4: 验证 target/ 与 fsroot* 已清除**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
du -sh target/ fsroot* 2>/dev/null || echo "target/ and fsroot* absent (good)"
```
期望:`target/ and fsroot* absent (good)`(`du` 因它们已不存在而报错)。

---

## Task 3: docker 清理(测试床容器 + SONiC 构建镜像,保留上游基础镜像)

**文件:**
- 删除(容器,10 个):`ptf_vms6-1`、`sonic-mgmt`、`ceos_vms6-1_VM0100..0103`、`net_vms6-1_VM0100..0103`。
- 删除(镜像,16 个):所有 `sonic-slave-*`(11 个:resolute×3、trixie×4、bookworm×4)、`docker-sonic-mgmt`、`docker-ptf`(本地)、`docker-database`、`docker-macsec`、`docker-dhcp-relay`。
- 保留(上游基础镜像):`ubuntu:*`、`debian:*`、`ceosimage:*`、`multiarch/qemu-user-static`、`alpine`、`p4lang/*`、`publicmirror.azurecr.io/debian:*`、`sonicdev-microsoft.azurecr.io:443/docker-ptf`。

**接口:**
- 消费:Task 2 重置后的仓库(构建期间不再引用这些容器/镜像)。
- 产出:docker daemon 仅剩上游基础镜像 + build cache/dangling 已清,释放约 98G。

- [ ] **Step 1: 停删 10 个测试床容器**

```bash
sg docker -c 'docker rm -f \
  ptf_vms6-1 sonic-mgmt \
  ceos_vms6-1_VM0100 ceos_vms6-1_VM0101 ceos_vms6-1_VM0102 ceos_vms6-1_VM0103 \
  net_vms6-1_VM0100 net_vms6-1_VM0101 net_vms6-1_VM0102 net_vms6-1_VM0103' 2>&1 | tail -15
```
期望:每个容器名打印(已删)。若某容器已不存在,docker 打印 "No such container"——可接受。

- [ ] **Step 2: 删除 16 个 SONiC 构建产物镜像(slave + 本地 testbed + 构建运行时)**

```bash
sg docker -c 'docker rmi -f \
  sonic-slave-resolute-sheldon-qi:d4568f6ea37 \
  sonic-slave-resolute:eee7031281d tmp-sonic-slave-resolute:eee7031281d \
  sonic-slave-trixie:0a98d89ae3c tmp-sonic-slave-trixie:0a98d89ae3c \
  sonic-slave-trixie-sheldon-qi:92fdf9e0a2c sonic-slave-trixie-sheldon-qi:3bf70d08d22 \
  sonic-slave-bookworm:edc8bd76260 tmp-sonic-slave-bookworm:edc8bd76260 \
  sonic-slave-bookworm-sheldon-qi:82749adf7f6 sonic-slave-bookworm-sheldon-qi:db5f4be378a \
  docker-sonic-mgmt:latest docker-ptf:latest \
  docker-database:latest docker-macsec:latest docker-dhcp-relay:latest' 2>&1 | tail -20
```
期望:每个镜像的 SHA 打印(untag/删除)。部分共享 layer,docker 自动去重。若镜像已不存在,出现 "No such image"——可接受。

- [ ] **Step 3: 清 build cache 与 dangling 镜像**

```bash
sg docker -c 'docker builder prune -af' 2>&1 | tail -3
sg docker -c 'docker image prune -f' 2>&1 | tail -3
```
期望:`Total reclaimed space:` 行带可观字节(build cache 约 16G)。若 Step 2 已清掉,dangling 数可能为 0。

- [ ] **Step 4: 验证仅剩上游基础镜像**

```bash
sg docker -c 'docker images' 2>&1 | grep -E 'sonic-slave|docker-(sonic-mgmt|ptf|database|macsec|dhcp)' && echo "UNEXPECTED build image still present" || echo "build images cleared"
sg docker -c 'docker images' 2>&1 | grep -ciE 'ubuntu|debian|ceos|multiarch|alpine|p4lang'
```
期望:`build images cleared`(第一个 grep 空),且第二个 grep 计数非零,确认上游基础镜像(ubuntu/debian/ceos 等)保留。

- [ ] **Step 5: 确认磁盘释放**

```bash
df -h / | tail -1
sg docker -c 'docker system df' 2>&1 | head -6
```
期望:空闲空间比 Task 2/3 前明显增多(fsroot/target/docker/artifacts 合计释放约 114G)。`docker system df` 的 Images 大小现仅反映基础镜像。

---

## Task 4: 清共享 dpkg 缓存 + 清理验证收尾

**文件:**
- 删除:`/var/cache/sonic/artifacts/*`(约 16G dpkg + 版本缓存)。
- 保留:`/var/cache/sonic/artifacts/` 目录本身,以 `root:root` + `777` 重建,供构建重写。

**接口:**
- 消费:Task 2–3(仓库 + docker 已清)。
- 产出:空且权限正确的共享缓存目录;清理阶段(spec §4)全部完成并验证,随后开始构建。

- [ ] **Step 1: 清共享 dpkg 缓存**

```bash
sudo rm -rf /var/cache/sonic/artifacts/*
sudo chown root:root /var/cache/sonic/artifacts
sudo chmod 777 /var/cache/sonic/artifacts
ls -ld /var/cache/sonic/artifacts
```
期望:`drwxrwxrwx ... root root ... /var/cache/sonic/artifacts`——目录在位、空、world-writable,供 DinD 构建重新填充。(此操作也一并清掉 sibling trixie clone 的 dpkg 缓存——它下次构建重新填充,只慢一次,不破坏。)

- [ ] **Step 2: 最终清理验证(spec §4e)**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
echo "--- 仓库产物 ---"
du -sh target/ fsroot* 2>/dev/null || echo "target/ and fsroot* absent"
echo "--- docker 构建镜像 ---"
sg docker -c 'docker images' 2>/dev/null | grep -E 'sonic-slave|docker-(sonic-mgmt|ptf|database|macsec|dhcp)' || echo "no SONiC build images"
echo "--- 共享缓存 ---"
sudo find /var/cache/sonic/artifacts -type f 2>/dev/null | wc -l   # 期望 0
echo "--- 磁盘 ---"
df -h / | tail -1
```
期望:`target/ and fsroot* absent`;`no SONiC build images`;文件计数 `0`;空闲空间反映全部约 114G 已释放。任一检查失败,回 Task 2/3/4-step-1 再查,再开始构建。

- [ ] **Step 3: 复检宿主机修复仍在位(宿主机侧,清理不影响,但构建依赖它)**

```bash
lsmod | grep -q ip_tables && echo "ip_tables loaded" || echo "ip_tables MISSING"
test -f /etc/apparmor.d/local/gs && echo "gs override present" || echo "gs override MISSING"
```
期望:`ip_tables loaded` 且 `gs override present`。(这些在宿主机侧;Task 1 Step 5 已确认——这是构建开始前的廉价复检。)

---

## Task 5: 从零构建 sonic-vs.img.gz(后台 + 轮询)

**文件:**
- 创建:构建仓库内 `target/build-vs.log`、`target/sonic-vs.img.gz`(~2G)。

**接口:**
- 消费:Task 1–4(干净仓库、docker、缓存;宿主机修复在位)。
- 产出:`target/sonic-vs.img.gz` 与构建日志;成功后成为 Task 6 broadcom 构建的前置。若构建错误需要修复,转入 fix-loop(Task 7)而非 broadcom。

- [ ] **Step 1: init + configure vs**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
sg docker -c 'make init' 2>&1 | tail -10
sg docker -c 'make PLATFORM=vs configure' 2>&1 | tail -10
```
期望:`make init` 重新初始化子模块(reset 已做,但无害/廉价);`make configure` 写平台配置。两者退出码 0。

- [ ] **Step 2: 后台启动 vs 构建,捕获日志**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
mkdir -p target
sg docker -c 'make PLATFORM=vs target/sonic-vs.img.gz' > target/build-vs.log 2>&1 &
echo "vs build PID: $!"
```
期望:后台 shell 作业;`target/build-vs.log` 开始接收输出。记下 PID 以备后续 `kill`。

- [ ] **Step 3: 定时轮询构建日志(slave 派生 + 全量重编较慢)**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
tail -15 target/build-vs.log
echo "--- still running? ---"
jobs -l 2>/dev/null; ps aux | grep -c '[m]ake.*sonic-vs'
```
期望:日志显示进度(slave 镜像构建,随后 package/docker 构建)。每约 10–20 分钟重复本步,直到作业完成。`jobs -l` 显示 `Done` 或进程计数降为 0 即构建完成。

- [ ] **Step 4: 完成后验证成功**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
ls -lh target/sonic-vs.img.gz 2>/dev/null && echo "vs image present" || echo "vs image MISSING"
tail -20 target/build-vs.log | grep -iE 'error|fail' && echo "BUILD HAD ERRORS" || echo "log tail clean"
```
期望:`vs image present` 且 `target/sonic-vs.img.gz` 约 2G,`log tail clean`(末 20 行无 ERROR/FAIL)。若出现错误,不要进 broadcom——去 Fix-Loop 子流程(成功后返回此处,再续 Task 6)。

- [ ] **Step 5:(可选,快速 sanity)确认 vs 镜像是 Ubuntu 26.04 resolute**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
# .img.gz 是 gzip 的 raw image;只读挂载根分区读 os-release
TMP=$(mktemp -d); gunzip -c target/sonic-vs.img.gz > "$TMP/vs.img" 2>/dev/null
sudo mkdir -p /mnt/vs-check; sudo losetup -fP "$TMP/vs.img" -o $(sudo fdisk -l "$TMP/vs.img" | awk 'NR>1 && $2=="*"{$1=""} /Linux/{print $2; exit}' | tr -d '*') 2>/dev/null
# 更简单:跳过 losetup,只确认文件存在与大小——完整 os-release 检查可选
ls -lh target/sonic-vs.img.gz
rm -rf "$TMP"
```
期望:`target/sonic-vs.img.gz` 约 2G。os-release 检查是可选机制;权威确认是 broadcom-vs 迁移报告此前已验证 resolute vs 启动 Ubuntu 26.04。本步从简——镜像存在 + 日志干净即可继续。

---

## Task 6: 从零构建 sonic-broadcom.bin(后台 + 轮询)

**文件:**
- 创建:构建仓库内 `target/build-broadcom.log`、`target/sonic-broadcom.bin`(~2.3G ONIE installer)。

**接口:**
- 消费:Task 5 成功的 vs 构建(确认 slave 镜像 + 工具链端到端干净派生)。
- 产出:`target/sonic-broadcom.bin`。broadcom 的 22 个修复 commit 已在 `canonical/202605_resolute`(已 push,见 [[sonic-resolute-broadcom-build-success]]),故本次重建预期干净——除非出现新的 Linux-7.0 API 漂移,否则无需新修复。若错误需要修复,在本 Task Step 4 前去 fix-loop(Task 7)。

- [ ] **Step 1: 构建前确认 broadcom 确切 make 目标**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
# broadcom 设计文档指定 TH3 / standard bin;确认目标名
grep -rn 'sonic-broadcom' Makefile.work slave.mk 2>/dev/null | grep -iE 'target|\.bin' | head -10
# 同时对照 broadcom 构建成功记忆与 broadcom 设计文档
```
期望:找到 `sonic-broadcom.bin`(或平台 standard bin 目标)的 make 目标行。若此前成功构建用的是不同目标(如 TH3 专用 bin),用那个确切目标/标志。在此记录确认的目标:`____________`。

- [ ] **Step 2: configure broadcom**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
sg docker -c 'make PLATFORM=broadcom configure' 2>&1 | tail -10
```
期望:退出码 0,写 broadcom 平台配置。(`make init` 已在 Task 5 跑过;子模块已初始化。)

- [ ] **Step 3: 后台启动 broadcom 构建,捕获日志**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
mkdir -p target
# 用 Step 1 确认的确切目标(下方为默认值;若 Step 1 不同则替换)
sg docker -c 'make PLATFORM=broadcom target/sonic-broadcom.bin' > target/build-broadcom.log 2>&1 &
echo "broadcom build PID: $!"
```
期望:后台作业;`target/build-broadcom.log` 开始接收输出。broadcom 是最慢的构建(opennsl kmod + 18 个 vendor 子模块重建),预期长跑。

- [ ] **Step 4: 定时轮询 broadcom 构建日志**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
tail -15 target/build-broadcom.log
echo "--- still running? ---"
jobs -l 2>/dev/null; ps aux | grep -c '[m]ake.*sonic-broadcom'
```
期望:日志显示进度(slave 复用,随后 opennsl/vendor kmod + syncd + 镜像组装)。每约 10–20 分钟重复。作业显示 `Done` 或进程计数 0 即完成。

- [ ] **Step 5: 完成后验证成功**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
ls -lh target/sonic-broadcom.bin 2>/dev/null && echo "broadcom image present" || echo "broadcom image MISSING"
tail -20 target/build-broadcom.log | grep -iE 'error|fail' && echo "BUILD HAD ERRORS" || echo "log tail clean"
```
期望:`broadcom image present` 且 `target/sonic-broadcom.bin` 约 2.3G,`log tail clean`。若出现错误,去 Fix-Loop 子流程(成功后返回此处,再续 Task 7);若干净,两个构建均已验证,可执行 Task 7 的 push。

---

## Fix-Loop(子流程,任一构建出错时可插入——不是线性的 Task 7)

**这是什么:** Fix-loop 是"分支再返回"的子流程,不是主路径上的顺序 task。主路径是线性的:Task 1 → 2 → 3 → 4 → 5(vs)→ 6(broadcom)→ 7(push)。fix-loop 在 Task 5 或 Task 6 遇到**确实需要源码/规则修复**的构建错误时**打断**当前 task、跑完 4 步,然后**显式返回被打断的那个构建 task**继续主路径。它可能在 vs 阶段(Task 5)触发,也可能在 broadcom 阶段(Task 6)触发——任何需要修复的出错点。

**文件:**
- 修改(仅出错时,父仓库):`rules/*.mk`、`*.j2` 模板、Dockerfile 等——在 `202605_resolute`。
- 修改(仅出错时,子模块):子模块在其 `202605_resolute` 分支上的源码 + 父仓库 gitlink bump。

**接口:**
- 消费:Task 5(vs)或 Task 6(broadcom)的构建错误。
- 产出:已 commit 的修复 + 完整再清理 + 失败目标的从零重建;成功后控制返回被打断的 task。

**触发点:** Task 5 Step 4 或 Task 6 Step 5 中任何打印 `BUILD HAD ERRORS` 的步骤。(瞬时/抖动、无需修复的错误——直接重跑构建,不走 fix-loop。)

- [ ] **FL-1: 按 systematic-debugging 定位根因;按 AGENTS.md Editing Rules 写修复**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
# 检查失败日志段的真实错误(非症状)
tail -60 target/build-vs.log   # 或 target/build-broadcom.log——哪个失败看哪个
```
期望:识别出真实错误(编译/链接/测试/打包失败)。修复遵循 AGENTS.md Editing Rules:最小范围、patch 文件(不直接改外部子模块源)、保留 pin。若"修复"并非真需要(瞬时/抖动),跳过 fix-loop,直接重跑构建。

- [ ] **FL-2: commit 修复(父仓库 OR 子模块 + gitlink bump)**

```bash
# 情况 A — 父仓库修复(rules/*.mk、*.j2、Dockerfile 等):
cd /home/sheldon-qi/sonic-buildimage-resolute
git add <changed-files>
git commit -m "fix: <简洁描述>"

# 情况 B — 子模块修复(子模块的 202605_resolute 分支):
cd /home/sheldon-qi/sonic-buildimage-resolute/<submodule>
git add <changed-files>
git commit -m "fix: <简洁描述>"
cd /home/sheldon-qi/sonic-buildimage-resolute
git add <submodule>          # bump 父仓库 gitlink 到新子模块 commit
git commit -m "fix: bump <submodule> gitlink for <description>"
```
期望:本地创建 commit。情况 B 必须同时有子模块 commit 与父仓库 gitlink bump——否则 `make reset` 的 `git submodule update --init` 会 checkout 回旧 gitlink、丢弃子模块修复(spec 7.1/7.2)。暂不 push(时序见 7.3;本地 `.git` 可达无需 push)。

- [ ] **FL-3: 重跑完整清理(spec §4,全部 4a–4e)——docker(4c)不可跳**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
# 4a: reset
make BLDENV=resolute UNATTENDED=y reset 2>&1 | tail -15
# 4b: root 属主残留
sudo rm -f dockerfs.tar.gz fs.squashfs fs.zip; sudo rm -rf fsroot*
# 4c: docker 清理(不可跳——旧 slave 镜像会掩盖 Dockerfile/子模块修复)
sg docker -c 'docker rmi -f $(sg docker -c "docker images -q sonic-slave-resolute* tmp-sonic-slave-resolute* sonic-slave-resolute-sheldon-qi*" 2>/dev/null) 2>/dev/null; docker builder prune -af; docker image prune -f' 2>&1 | tail -5
# 4d: 共享 dpkg 缓存
sudo rm -rf /var/cache/sonic/artifacts/*; sudo chmod 777 /var/cache/sonic/artifacts
```
期望:reset + 残留 + docker + 缓存全部重清。Step 4c 不可跳:若修复触及 slave Dockerfile 或喂给 slave 的子模块,必须删旧 slave 镜像否则它不会重新派生、修复不生效(spec 7.2 step 3)。

- [ ] **FL-4: 从零重建失败的目标,然后返回主路径**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
# 重跑失败的构建——reset 清了 target/,先 re-init/configure
sg docker -c 'make init'
sg docker -c 'make PLATFORM=<vs|broadcom> configure'         # 哪个失败配哪个
sg docker -c 'make PLATFORM=<vs|broadcom> <target/sonic-vs.img.gz|target/sonic-broadcom.bin>' > target/build-<platform>.log 2>&1 &
```
期望:后台重建,新日志。轮询它(Task 5 Step 3 / Task 6 Step 4)直到完成,再验证(Task 5 Step 4 / Task 6 Step 5)。

**返回点(显式——这是让循环闭合的关键):**
- 若 fix-loop 在 **vs 阶段(Task 5)** 触发且重建通过验证 → **返回 Task 5 Step 5**(vs sanity),然后正常继续 **Task 6**(broadcom 构建)。若 broadcom 之后又出错,在 broadcom 阶段触发新的 fix-loop。
- 若 fix-loop 在 **broadcom 阶段(Task 6)** 触发且重建通过验证 → **返回 Task 6 Step 5**(broadcom 验证),然后正常继续 **Task 7**(最终 push)。
- 若重建**再次失败** → 从 FL-1 重跑 fix-loop(新根因)。循环只有在被打断的构建通过其验证步骤后才退出。**在被打断的构建变绿之前,不得进下一个 task 或 push。**

---

## Task 7: 最终 push(必跑,vs 与 broadcom 都过后)

**文件:**
- push:本次工作累积的本地 commit——文档分支(spec + plan),以及若有 fix-loop 情况 A/B 产生的修复 commit + gitlink bump,在构建仓库 + 子模块上。

**接口:**
- 消费:通过的 vs 构建(Task 5)与通过的 broadcom 构建(Task 6)——两者都不在 fix-loop 中。
- 产出:所有本地 commit push 到 canonical 远端;两个 git 仓库同步。

- [ ] **Step 1: push 文档分支(spec + plan)**

```bash
cd /home/sheldon-qi/sonic-buildimage
git log --oneline origin/202605_resolute_doc..HEAD   # 预览待 push 的本地 commit
git push origin 202605_resolute_doc
```
期望:spec + plan commit(spec 阶段 commit + plan commit)push 到 `canonical/sonic-buildimage:202605_resolute_doc`。验证:`git status` 显示与 origin 同步。

- [ ] **Step 2: push 子模块修复 commit(若有 fix-loop 情况 B 跑过)到 canonical——绝不 sonic-net**

```bash
# 仅当 fix-loop 跑过情况 B——对每个修改过的子模块:
cd /home/sheldon-qi/sonic-buildimage-resolute/<submodule>
git remote -v | grep canonical    # 确认 canonical 远端存在
git push canonical 202605_resolute
cd /home/sheldon-qi/sonic-buildimage-resolute
```
期望:每个修改过的子模块的本地 commit push 到 `canonical/<sub>:202605_resolute`。绝不 push 到 `sonic-net/`(上游,非我们可写——AGENTS.md Submodules)。

- [ ] **Step 3: push 父构建仓库(修复 commit + gitlink bump,若有 fix-loop 跑过)**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
git log --oneline origin/202605_resolute..HEAD   # 预览本地 commit(无需修复则为空)
git push origin 202605_resolute
```
期望:若 fix-loop 创建了父仓库修复 commit(情况 A)或 gitlink bump(情况 B),push 到 `canonical/sonic-buildimage:202605_resolute`。若无需修复(两个构建从一开始就干净),此 push 是 no-op(`Everything up-to-date`)。

- [ ] **Step 4: 最终验证——两个镜像都在,两个日志都干净**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
ls -lh target/sonic-vs.img.gz target/sonic-broadcom.bin
tail -5 target/build-vs.log | grep -iE 'error|fail' && echo "vs log has errors" || echo "vs log clean"
tail -5 target/build-broadcom.log | grep -iE 'error|fail' && echo "broadcom log has errors" || echo "broadcom log clean"
cd /home/sheldon-qi/sonic-buildimage && git status -s | head    # 文档仓库干净(已 push)
cd /home/sheldon-qi/sonic-buildimage-resolute && git status -s | head   # 构建仓库:仅构建产物(未跟踪)
```
期望:两个镜像都在(vs 约 2G,broadcom 约 2.3G);两个日志干净;两个 git 仓库与各自 canonical 远端同步(构建仓库可能显示 `target/` 下未跟踪构建产物,符合预期且从不 commit)。

---

## 完成

`target/sonic-vs.img.gz` 与 `target/sonic-broadcom.bin` 均从完全干净状态构建,所有本地 commit 已 push 到 canonical 远端,resolute 构建链路端到端可复现性验证通过。