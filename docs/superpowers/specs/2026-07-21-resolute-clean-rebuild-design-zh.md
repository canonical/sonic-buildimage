# Resolute 完全干净从零构建 — 设计

- 日期:2026-07-21
- 作用仓库:`/home/sheldon-qi/sonic-buildimage-resolute`(分支 `202605_resolute`)
- 构建宿主机:Ubuntu 26.04(ext4 root,内核 7.0.0-27,docker-ce 29.6.1,默认 DinD `--privileged`)
- 目标:端到端从零复现一次构建(vs 先 → broadcom 后),验证整条链路可复现,并释放此前累积的构建产物磁盘占用
- 相关文档:[broadcom 平台构建支持设计](2026-07-20-broadcom-platform-build-support-design-zh.md)、[迁移设计](2026-07-03-sonic-202605-resolute-migration-design-zh.md)
- 本文为中文版;英文版为唯一事实来源(`-en.md`)

## 1. 目标与范围

执行一次**完全干净**的从零构建:清理所有构建产物,仅保留必要配置与上游基础镜像;然后从零构建 `sonic-vs.img.gz`,成功后再从零构建 `sonic-broadcom.bin`。

清理深度按用户决策:连 slave 镜像、ccache、共享 dpkg 缓存(`/var/cache/sonic/artifacts`)一起清——即"从零复现"的字面含义。测试床容器与所有 SONiC slave 镜像一并清除;但保留上游基础镜像(debian/ubuntu/ceosimage/multiarch 等,非我们构建)。

**不在范围内:** 本设计不修改任何源码或构建规则;若构建过程中遇到必须修改的错误,见第 7 节的修复循环策略。

## 2. 保留清单(不动)

| 类别 | 内容 | 保留原因 |
|---|---|---|
| 仓库配置 | `rules/config.user`、`AGENTS.md`、`.gitmodules`、所有源码、git 历史与分支 | 均为 git 跟踪文件;`make reset` 的 `git clean`/`git reset --hard` 不触及跟踪文件 |
| 宿主机修复 | AppArmor `gs` local override(`/etc/apparmor.d/local/gs`)、`ip_tables` 模块(`/etc/modules-load.d/ip_tables.conf`) | 位于宿主机,reset 不触及;且为重建必需(分别解决 bash.pdf 写入与 iptables-legacy) |
| 上游基础镜像 | `ubuntu:resolute`/`:noble`、`debian:*` 全系列、`ceosimage:*`、`multiarch/qemu-user-static`、`alpine`、`publicmirror.azurecr.io/debian:*`、`p4lang/behavioral-model`、`sonicdev-microsoft.azurecr.io:443/docker-ptf` | 非 SONiC 构建产物,从零重建会按需重新 pull;按用户决策保留 |
| 备份 | memory 目录中的 `sonic-config.user` 备份 | 离仓库存放,不受任何清理影响 |

## 3. 安全预检(删任何东西之前的硬门)

执行第 4 节清理前,必须全部通过:

1. **git 干净度** — `git status` 确认无未提交的跟踪文件改动会被 `reset --hard` 丢弃。当前工作树仅有可重建的解压 `src/*/` 与 fsroot 产物(安全)。若存在未提交的跟踪改动,先处理(stash 或 commit)再继续。
2. **`git clean -xfdf -n` 干跑** — 列出将被删除的未跟踪/忽略文件,人工确认无误伤。
3. **子模块健康** — `git submodule status` 抽查,确认 object store 完好(近期 vs/broadcom 构建成功 → 应完好;若报 missing blob,按 [[sonic-resolute-submodule-object-store-corruption]] 的 deinit + re-clone 修复后再继续)。
4. **子模块 gitlink 可达性** — 确认 Canonical 改过的子模块 gitlink commit 均已 push 到 `canonical/<sub>:202605_resolute`(否则 `git submodule update --init` 失败)。
5. **宿主机修复在位** — `lsmod | grep ip_tables` 有输出 + `/etc/apparmor.d/local/gs` 存在;缺失则先补(否则重建必崩)。
6. **sudo 免密** — `sudo -n true` 成功(`make reset` 内 `sudo rm -rf fsroot*` 需要)。

## 4. 清理流程

### 4a. 官方 reset(仓库级核清)

```
make BLDENV=resolute UNATTENDED=y reset
```

效果:`sudo rm -rf fsroot*`(含 68G `fsroot.docker.resolute` 及各 `fsroot-broadcom*` / `-dnx` / `-legacy-th` / `-vs`)→ `git clean -xfdf`(清 `target/` 含 ccache/vcache、解压 `src/*/`、`.pytest_cache`)→ `git reset --hard` → 子模块 `clean` + `reset --hard` + `remote update` + `update --init --recursive`。**保留所有 git 跟踪文件。**

### 4b. root 属主残留兜底

reset 的 `fsroot*` 通配不匹配非 fsroot 前缀的根下大文件,显式删除并验证:

```
sudo rm -f dockerfs.tar.gz fs.squashfs fs.zip
sudo rm -rf fsroot*                  # 兜底,防 reset 的 sudo 通配漏匹配
ls -la | grep -E 'fsroot|\.tar\.gz|\.squashfs|\.zip'    # 应无输出
```

### 4c. docker 清理(停删测试床 + 删 SONiC 构建镜像,保留上游基础镜像)

先停删 10 个测试床容器,再删除 SONiC 构建产物镜像(slave + 本地 testbed 镜像 + 构建产出的运行时镜像),保留上游基础镜像:

```
# 停删测试床容器(10 个)
docker rm -f ptf_vms6-1 sonic-mgmt \
  ceos_vms6-1_VM0100 ceos_vms6-1_VM0101 ceos_vms6-1_VM0102 ceos_vms6-1_VM0103 \
  net_vms6-1_VM0100 net_vms6-1_VM0101 net_vms6-1_VM0102 net_vms6-1_VM0103

# 删除 SONiC 构建产物镜像(slave 11 个 + testbed/运行时 5 个)
docker rmi -f \
  sonic-slave-resolute-sheldon-qi:d4568f6ea37 \
  sonic-slave-resolute:eee7031281d tmp-sonic-slave-resolute:eee7031281d \
  sonic-slave-trixie:0a98d89ae3c tmp-sonic-slave-trixie:0a98d89ae3c \
  sonic-slave-trixie-sheldon-qi:92fdf9e0a2c sonic-slave-trixie-sheldon-qi:3bf70d08d22 \
  sonic-slave-bookworm:edc8bd76260 tmp-sonic-slave-bookworm:edc8bd76260 \
  sonic-slave-bookworm-sheldon-qi:82749adf7f6 sonic-slave-bookworm-sheldon-qi:db5f4be378a \
  docker-sonic-mgmt:latest docker-ptf:latest \
  docker-database:latest docker-macsec:latest docker-dhcp-relay:latest

# build cache + dangling
docker builder prune -af
docker image prune -f
```

**不删:** `sonicdev-microsoft.azurecr.io:443/docker-ptf`、`ceosimage:*`、`debian:*`、`ubuntu:*`、`multiarch/*`、`alpine`、`p4lang/*`、`publicmirror.azurecr.io/debian:*`。

### 4d. 共享 dpkg 缓存全清

```
sudo rm -rf /var/cache/sonic/artifacts/*
sudo chown root:root /var/cache/sonic/artifacts && sudo chmod 777 /var/cache/sonic/artifacts   # 恢复权限供构建重写
```

说明:dpkg 缓存键为 commit hash,文件名不含分支标签,**无法可靠地按 resolute/trixie 选择性清理**;故全清。此目录与 sibling trixie clone(`sonic-buildimage-202605-clone`)共享,清空会一并丢掉 trixie 的 dpkg 缓存——下次 trixie 构建重新填充,只慢一次,不破坏。

### 4e. 验证清理结果

```
du -sh target/ fsroot* /var/cache/sonic/artifacts   # target/ 与 fsroot* 不存在或空;artifacts 空
docker images | grep -E 'sonic-slave|docker-(sonic-mgmt|ptf|database|macsec|dhcp)'   # 应无输出
df -h                                                # 确认释放约 114G
```

## 5. 构建流程(vs → broadcom,后台 + 定时查进度)

从零构建耗时较长(slave 重新派生 + 子模块全量重编)。后台运行、日志捕获、周期性查进度。

```
# vs(先跑通链路验证)
sg docker -c 'make init'
sg docker -c 'make PLATFORM=vs configure'
sg docker -c 'make PLATFORM=vs target/sonic-vs.img.gz' > target/build-vs.log 2>&1 &   # 后台

# vs 成功后 → broadcom(真实硬件镜像)
sg docker -c 'make PLATFORM=broadcom configure'
sg docker -c 'make PLATFORM=broadcom target/sonic-broadcom.bin' > target/build-broadcom.log 2>&1 &
```

broadcom 的确切 make 目标与标志,执行时对照 broadcom 构建成功记忆与 [broadcom 平台构建支持设计](2026-07-20-broadcom-platform-build-support-design-zh.md)(TH3/standard bin)确认。定时回来 `tail` 两个 log 查进度与错误。

## 6. 验证

- **vs:** `ls -lh target/sonic-vs.img.gz`(约 2G)+ 解压查 os-release 确认 Ubuntu 26.04。
- **broadcom:** `ls -lh target/sonic-broadcom.bin`(约 2.3G ONIE installer)。
- 两个 build.log 末尾无 ERROR、退出码 0。

## 7. 修复循环策略(硬策略)

若构建过程中遇到错误且**确实需要修改源码或构建规则**,遵循下述循环。此策略对 vs 与 broadcom 两个 build 均适用——可复现原理相同。

### 7.1 为什么必须 commit(技术必需,非风格要求)

`make reset` 包含 `git reset --hard` + `git clean -xfdf` + `git submodule foreach 'git reset --hard'` + `git submodule update --init --recursive`。因此:

- **任何未提交改动都会被 reset 擦掉**——修了不 commit,重新清理等于把修复也清掉。
- **子模块修复更要走完整 gitlink 流程**:`git submodule update --init` 会把子模块 checkout 到父仓库 gitlink 指向的 commit。子模块内 commit 但未 bump 父仓库 gitlink → `update --init` checkout 回旧 gitlink,修复被丢弃。

### 7.2 修复循环

1. **定位并修复** — 遇到构建错误时,先按 systematic-debugging 思路定位根因;修改遵循 AGENTS.md 的 Editing Rules(最小范围、patch 文件而非直接改外部源、保留 pin 等)。
2. **提交修复**(分两种情况):
   - **父仓库改动**(`rules/*.mk`、`*.j2` 模板、Dockerfile 等):直接 commit 到 `202605_resolute`。
   - **子模块改动**:按 AGENTS.md Submodules 节——子模块内 commit 到其 `202605_resolute` 分支 → push `canonical/<sub>:202605_resolute`(**绝不 push `sonic-net/`**)→ 父仓库 `git add <sub>` bump gitlink → commit 父仓库。**只有父仓库 gitlink 指向新 commit,reset 后重建才真带上修复。**
3. **执行完整清理** — 重新跑第 4 节全部(4a–4e),不跳过。其中 4c(docker 清理)不可跳过:若修复触及 slave Dockerfile 或喂给 slave 的子模块,不清掉旧 slave 镜像它就不会重新派生、修复不会生效。
4. **从零重建** — 重新跑第 5 节构建。

"修改→commit→完整清理→重建"是从零可复现的硬保证:commit 让修复进 git、reset 不丢它、clean rebuild 验证它在干净环境真实有效。

## 8. 风险与回滚

- **`make reset` 的 `reset --hard` 不可逆** — 第 3 节预检是硬门;git 不干净则中止,不执行清理。
- **slave 派生阶段崩溃(bash.pdf / iptables)** — 先查宿主机修复(第 3 节第 5 项)是否真在位。
- **子模块 `update --init` 报 missing blob** — 按 [[sonic-resolute-submodule-object-store-corruption]] 的 deinit + re-clone 修复。
- **dpkg 缓存全清影响 sibling trixie clone** — 仅多花一次构建时间,不破坏(见 4d)。
