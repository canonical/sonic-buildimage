# SONiC 202605 → Ubuntu Resolute 迁移实施计划（中文）

> **For agentic workers:** REQUIRED SUB-SKILL: 使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实施。步骤用 checkbox（`- [ ]`）跟踪。

**目标：** 在 `~/sonic-buildimage-resolute` 把 SONiC 202605 构建链从 Debian trixie 迁到 Ubuntu resolute（26.04），以 vs 为目标，done-bar = vs 镜像 KVM 启动 + SONiC smoke 通过。

**架构：** 把 resolute 作为新 BLDENV 增量接入（方案 A），专用仓库内设为默认且唯一启用。5 阶段：slave → host OS → 容器 base → vs 容器 → 组装+boot。所有 `rules/*.mk` 源码构建原样保留。trixie 路径保留作对照组。

**技术栈：** GNU Make、Jinja2（j2）、Docker、debootstrap、apt、KVM/libvirt。

## 全局约束

- Ubuntu **必须** 26.04 / resolute，所有 fallback 在 resolute 体系内换实现，绝不退到 26.04 之前。
- 内核 ABI 后缀 `+deb13-sonic`、版本 `6.12.41+deb13` **不改**（procure 预编译内核）。
- k8s/cri（cri-dockerd、kubelet、kubeadm、kubectl、kubernetes-cni、cri-tools）在 resolute 上**跳过**，backlog。
- FIPS：首选复用 trixie FIPS Go binary；fallback `INCLUDE_FIPS=n` 用 Ubuntu 官方 resolute golang-go + openssl。
- Docker 版本：若 resolute 无 `docker-ce 5:28.5.2`，用 Docker 公司当前在 resolute suite 可用版本，**钉死精确版本号**（不用 `stable` 元包、不跟 latest）。
- 工作目录：所有路径相对 `~/sonic-buildimage-resolute`。
- 对话用中文；本计划另出英文版 `*-en.md`。

---

## 文件结构

**新建：**
- `sonic-slave-resolute/Dockerfile.j2`（自 `sonic-slave-trixie/Dockerfile.j2`）— slave 构建容器
- `sonic-slave-resolute/docker.sources` — slave 内 docker apt 源
- `sonic-slave-resolute/pip.conf`、`no-check-valid-until` 等（随 trixie 复制）
- `dockers/docker-base-resolute/Dockerfile.j2`（自 `dockers/docker-base-bookworm/Dockerfile.j2`）— 容器 base 层
- `rules/docker-base-resolute.mk`（自 `rules/docker-base-bookworm.mk`）— base 容器构建规则
- `rules/config.user` — 仓库本地构建配置（INCLUDE_FIPS 等）

**修改：**
- `Makefile` — 加 `NORESOLUTE`、默认 catch-all → `BLDENV=resolute`、禁 bookworm/trixie
- `Makefile.work:132` — `SLAVE_DIR` 加 resolute 分支
- `slave.mk:73` — `IMAGE_DISTRO := resolute`
- `slave.mk:78` — ENABLE_PY2 过滤加 `resolute`
- `scripts/build_mirror_config.sh` — Ubuntu mirror 默认 URL
- `files/apt/sources.list.j2` — resolute suite/组件分支
- `build_debian.sh:30-32` — docker/containerd 版本 + 内核版本
- `build_debian.sh:233` — docker apt 源
- `build_debian.sh:277-279` — 跳过 cri-dockerd
- `scripts/build_debian_base_system.sh:30,40,46,82` — debootstrap resolute + 缓存路径
- `rules/linux-kernel.mk` — procure 预编译（不源码构建）

---

### Task 1: 初始化 ~/sonic-buildimage-resolute 仓库

**Files:**
- Create: `~/sonic-buildimage-resolute/`（整个仓库）

**Interfaces:**
- Produces: 一个干净 git 工作树，branch `resolute`，所有后续 Task 在此进行。

- [ ] **Step 1: 本地 reference clone**

```bash
cd ~
git clone --reference ~/sonic-buildimage -b 202605 https://github.com/sonic-net/sonic-buildimage.git ~/sonic-buildimage-resolute
cd ~/sonic-buildimage-resolute
```

预期：clone 快速完成（本地对象共享）。

- [ ] **Step 2: 初始化 submodules**

```bash
cd ~/sonic-buildimage-resolute
make -C . 2>/dev/null; true   # 触发 submodule 初始化前先确认 .gitmodules
git submodule update --init --recursive --reference ~/sonic-buildimage 2>&1 | tail -5
```

预期：submodule 检出完成（可能耗时，--reference 复用本地对象）。

- [ ] **Step 3: 建 resolute 分支并配置 git 身份**

```bash
cd ~/sonic-buildimage-resolute
git config user.email "sheldon-qi@local"
git config user.name "sheldon-qi"
git checkout -b resolute
```

预期：在 `resolute` 分支。

- [ ] **Step 4: 验证基线干净**

```bash
cd ~/sonic-buildimage-resolute
git status --short | head
git log --oneline -1
```

预期：`git status` 空（或仅 untracked），HEAD 指向 202605 最新 commit。

- [ ] **Step 5: Commit（无内容变更，仅建分支）**

```bash
cd ~/sonic-buildimage-resolute
git commit --allow-empty -m "chore: start resolute migration branch"
```

---

### Task 2: Phase 0 spike a — 确认 Docker resolute 版本字符串

**Files:**
- 无文件改动；产出结论记录到 Task 3 的 config.user。

**Interfaces:**
- Produces: `DOCKER_VERSION` / `CONTAINERD_IO_VERSION` 的精确字符串，供 Task 7（slave）和 Task 9（host OS）使用。

- [ ] **Step 1: 查 Docker 官方 apt 仓库 resolute suite 的可用 docker-ce 版本**

```bash
# 临时容器查 resolute 上 docker ce 的可用版本
docker run --rm ubuntu:resolute bash -c '
  apt-get update -qq &&
  apt-get install -y -qq ca-certificates curl gnupg >/dev/null &&
  install -m 0755 -d /etc/apt/keyrings &&
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg &&
  chmod a+r /etc/apt/keyrings/docker.gpg &&
  echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu resolute stable" > /etc/apt/sources.list.d/docker.list &&
  apt-get update -qq &&
  apt-cache policy docker-ce containerd.io | head -30
'
```

预期：列出 resolute suite 的 `docker-ce` 候选版本。

- [ ] **Step 2: 判定版本字符串**

若 `5:28.5.2-1~ubuntu.26.04~resolute`（或 Docker 对 resolute 的命名）存在 → 钉该字符串。
若 5:28.5.2 不存在但其他 docker-ce 版本存在 → 钉**当前可用**的精确版本字符串（含 epoch 与 `~ubuntu...~resolute` 后缀）。

记录结论，例如：
```
DOCKER_VERSION=5:28.5.2-1~ubuntu.26.04~resolute   # 或实际可用版本
CONTAINERD_IO_VERSION=1.7.28-2~ubuntu.26.04~resolute
```

- [ ] **Step 3: 若 Docker 完全无 resolute suite**

若 `apt-cache policy` 无任何 resolute 候选 → 确认 Docker 是否用其他 suite 名（如 `noble` 兼容、或 `resolute` 暂未上线）。仍无则按 R1 fallback：用 Ubuntu 官方 `docker.io` 包（`apt-cache policy docker.io`），钉其精确版本。本步**不**改文件，仅记录结论到下一步的 config.user 注释。

---

### Task 3: Phase 0 spike b — 确认预编译 SONiC 内核 .deb 路径

**Files:**
- 无文件改动；产出路径供 Task 10 使用。

**Interfaces:**
- Produces: BUILD_PUBLIC_URL 上 202605 预编译内核 .deb 的下载路径模板。

- [ ] **Step 1: 查 BUILD_PUBLIC_URL 默认值**

```bash
cd ~/sonic-buildimage-resolute
grep -nE 'BUILD_PUBLIC_URL' rules/config | head
```

预期：`BUILD_PUBLIC_URL ?= https://packages.trafficmanager.net/public`。

- [ ] **Step 2: 探测内核预编译 .deb 路径**

```bash
# 探测可能的内核预编译路径（base on rules/linux-kernel.mk 的包名 + 现有 version cache 习惯）
BASE=https://packages.trafficmanager.net/public
for p in linux-image-6.12.41+deb13-sonic linux-headers-6.12.41+deb13-sonic linux-kbuild-6.12.41+deb13; do
  echo "== $p =="
  curl -sI "$BASE/.../$p" 2>/dev/null | head -1   # 路径需结合实际目录结构确认
done
```

预期：找到 HTTP 200 的 .deb 路径模板，或确认无预编译。

- [ ] **Step 3: 判定 fallback**

若找到预编译路径 → 记录路径模板，Task 10 用 procure 方式。
若无预编译 → 记录"fallback：resolute 上源码构建 linux-kernel.mk（`+resolute` ABI）"，Task 10 改为源码构建路径。

---

### Task 4: Phase 0 spike c — 确认 debootstrap resolute 可用性

**Files:**
- 无文件改动；结论供 Task 11 使用。

**Interfaces:**
- Produces: debootstrap resolute 是否可用 + keyring 路径。

- [ ] **Step 1: 查 debootstrap 是否带 resolute 脚本**

```bash
ls /usr/share/debootstrap/scripts/ | grep -iE 'resolute|noble' || echo "no resolute script"
```

预期：有 `resolute` 脚本（或符号链接）。

- [ ] **Step 2: 试 debootstrap resolute（沙盒）**

```bash
sudo debootstrap --variant=minbase --arch=amd64 resolute /tmp/debootstrap-test-resolute http://archive.ubuntu.com/ubuntu/ 2>&1 | tail -15
```

预期：成功（或报 keyring 缺失 → Step 3）。

- [ ] **Step 3: 若缺 keyring**

```bash
# 导入 Ubuntu keyring
sudo apt-get install -y ubuntu-keyring 2>/dev/null || \
  curl -fsSL https://archive.ubuntu.com/ubuntu/project/ubuntu-archive-keyring.gpg | sudo tee /usr/share/keyrings/ubuntu-archive-keyring.gpg
# 重试 debootstrap with --no-check-gpg 作为备选验证
sudo rm -rf /tmp/debootstrap-test-resolute
sudo debootstrap --no-check-gpg --variant=minbase --arch=amd64 resolute /tmp/debootstrap-test-resolute http://archive.ubuntu.com/ubuntu/ 2>&1 | tail -5
```

预期：rootfs 生成，`/tmp/debootstrap-test-resolute/etc/os-release` 显示 Ubuntu 26.04。

- [ ] **Step 4: 清理沙盒**

```bash
sudo rm -rf /tmp/debootstrap-test-resolute
```

---

### Task 5: Makefile — 加 NORESOLUTE 并设为默认

**Files:**
- Modify: `Makefile:7-9`（NO* 标志区）
- Modify: `Makefile:38-44`（BUILD_* 区）
- Modify: `Makefile:65-68`（catch-all 默认）

**Interfaces:**
- Produces: 默认 `make` → `BLDENV=resolute`；bookworm/trixie 默认禁用。

- [ ] **Step 1: 加 NORESOLUTE 标志，禁 bookworm/trixie**

把：
```makefile
NOBOOKWORM ?= 0
NOTRIXIE ?= 0
```
改为：
```makefile
NOBOOKWORM ?= 1
NOTRIXIE ?= 1
NORESOLUTE ?= 0
```

- [ ] **Step 2: 加 BUILD_RESOLUTE 标志**

在 `BUILD_TRIXIE` 块后加：
```makefile
ifeq ($(NORESOLUTE),0)
BUILD_RESOLUTE=1
endif
```

- [ ] **Step 3: catch-all 默认改 resolute**

把：
```makefile
ifeq ($(NOTRIXIE), 0)
	$(MAKE_WITH_RETRY) BLDENV=trixie -f Makefile.work $@
endif

	BLDENV=bookworm $(MAKE) -f Makefile.work docker-cleanup
```
改为：
```makefile
ifeq ($(NORESOLUTE), 0)
	$(MAKE_WITH_RETRY) BLDENV=resolute -f Makefile.work $@
endif

	BLDENV=resolute $(MAKE) -f Makefile.work docker-cleanup
```

- [ ] **Step 4: 底部分发块加 resolute（若存在 BUILD_TRIXIE 分发）**

定位 `$(if $(BUILD_TRIXIE),BLDENV=trixie ...)` 那行，后加：
```makefile
	$(if $(BUILD_RESOLUTE),BLDENV=resolute $(MAKE) -f Makefile.work $@,)
```

- [ ] **Step 5: 验证 make 解析**

```bash
cd ~/sonic-buildimage-resolute
make -n sonic-slave-build 2>&1 | grep -iE 'BLDENV=resolute|BLDENV=trixie' | head
```
预期：出现 `BLDENV=resolute`，不出现 trixie 默认分发。

- [ ] **Step 6: Commit**

```bash
git add Makefile
git commit -m "build: add NORESOLUTE, default BLDENV to resolute"
```

---

### Task 6: Makefile.work + slave.mk — SLAVE_DIR 与 IMAGE_DISTRO

**Files:**
- Modify: `Makefile.work:132`（SLAVE_DIR 分支）
- Modify: `slave.mk:73`（IMAGE_DISTRO）
- Modify: `slave.mk:78`（ENABLE_PY2 过滤）

**Interfaces:**
- Produces: `BLDENV=resolute` → `SLAVE_DIR=sonic-slave-resolute`；`IMAGE_DISTRO=resolute`。

- [ ] **Step 1: SLAVE_DIR 加 resolute 分支**

在 `Makefile.work` 的：
```makefile
ifeq ($(BLDENV), trixie)
SLAVE_DIR = sonic-slave-trixie
```
前插入：
```makefile
ifeq ($(BLDENV), resolute)
SLAVE_DIR = sonic-slave-resolute
else ifeq ($(BLDENV), trixie)
SLAVE_DIR = sonic-slave-trixie
```

- [ ] **Step 2: IMAGE_DISTRO 改 resolute**

把 `slave.mk:73`：
```makefile
IMAGE_DISTRO := trixie
```
改为：
```makefile
IMAGE_DISTRO := resolute
```

- [ ] **Step 3: ENABLE_PY2 过滤加 resolute**

把 `slave.mk:78`：
```makefile
ifneq ($(filter bullseye bookworm trixie,$(BLDENV)),)
```
改为：
```makefile
ifneq ($(filter bullseye bookworm trixie resolute,$(BLDENV)),)
```

- [ ] **Step 4: 验证**

```bash
cd ~/sonic-buildimage-resolute
grep -n 'resolute' Makefile.work slave.mk | head
```
预期：resolute 分支/赋值都在。

- [ ] **Step 5: Commit**

```bash
git add Makefile.work slave.mk
git commit -m "build: map BLDENV=resolute to sonic-slave-resolute, IMAGE_DISTRO=resolute"
```

---

### Task 7: 新建 sonic-slave-resolute/（FROM ubuntu:resolute + docker 源）

**Files:**
- Create: `sonic-slave-resolute/Dockerfile.j2`（自 `sonic-slave-trixie/Dockerfile.j2`）
- Create: `sonic-slave-resolute/docker.sources`（自 `sonic-slave-trixie/docker.sources`）
- Copy: `sonic-slave-resolute/pip.conf`、`sonic-jenkins-id_rsa.pub` 等

**Interfaces:**
- Consumes: Task 2 的 DOCKER_VERSION 字符串。
- Produces: `sonic-slave-resolute/Dockerfile.j2`，`FROM ubuntu:resolute`。

- [ ] **Step 1: 复制 trixie slave 目录为 resolute**

```bash
cd ~/sonic-buildimage-resolute
cp -a sonic-slave-trixie sonic-slave-resolute
ls sonic-slave-resolute/
```

- [ ] **Step 2: Dockerfile.j2 基础镜像换 ubuntu:resolute**

在 `sonic-slave-resolute/Dockerfile.j2`，把所有 `debian:trixie` 改为 `ubuntu:resolute`：
```bash
sed -i 's|debian:trixie|ubuntu:resolute|g' sonic-slave-resolute/Dockerfile.j2
grep -n 'FROM' sonic-slave-resolute/Dockerfile.j2 | head
```
预期：`FROM {{ prefix }}ubuntu:resolute`。

- [ ] **Step 3: docker.sources 换 ubuntu**

把 `sonic-slave-resolute/docker.sources` 的 `https://download.docker.com/linux/debian` 改为 `https://download.docker.com/linux/ubuntu`：
```bash
sed -i 's|download.docker.com/linux/debian|download.docker.com/linux/ubuntu|' sonic-slave-resolute/docker.sources
cat sonic-slave-resolute/docker.sources
```

- [ ] **Step 4: 钉版 docker 版本字符串（用 Task 2 结论）**

编辑 `sonic-slave-resolute/Dockerfile.j2` 第 674 行附近，把：
```
docker-ce=5:28.5.2-1~debian.13~trixie docker-ce-cli=5:28.5.2-1~debian.13~trixie containerd.io=1.7.28-2~debian.13~trixie docker-buildx-plugin=0.26.1-1~debian.13~trixie docker-compose-plugin=2.39.1-1~debian.13~trixie
```
替换为 Task 2 确认的 resolute 版本字符串（示例，按实际填）：
```
docker-ce=<DOCKER_VERSION> docker-ce-cli=<DOCKER_VERSION> containerd.io=<CONTAINERD_IO_VERSION> docker-buildx-plugin=<实际resolute版本> docker-compose-plugin=<实际resolute版本>
```

- [ ] **Step 5: FIPS Go 拉取路径保持 trixie（不变）**

确认 `sonic-slave-resolute/Dockerfile.j2` 中 `BUILD_PUBLIC_URL }}/fips/trixie/` 路径**不改**：
```bash
grep -n 'fips/trixie' sonic-slave-resolute/Dockerfile.j2
```
预期：路径仍在（复用 trixie FIPS binary，per FIPS 设计）。

- [ ] **Step 6: Commit**

```bash
git add sonic-slave-resolute
git commit -m "build: add sonic-slave-resolute (FROM ubuntu:resolute, ubuntu docker repo)"
```

---

### Task 8: apt 源生成器 + sources.list.j2 — Ubuntu mirror/组件

**Files:**
- Modify: `scripts/build_mirror_config.sh`（默认 mirror URL）
- Modify: `files/apt/sources.list.j2`（resolute 分支）

**Interfaces:**
- Produces: `build_mirror_config.sh` 对 resolute 生成 Ubuntu sources.list；`sources.list.j2` 支持 resolute 组件。

- [ ] **Step 1: build_mirror_config.sh 默认 mirror 改 Ubuntu（resolute）**

在 `scripts/build_mirror_config.sh` 的默认 URL 区，加 resolute 分支。把：
```bash
DEFAULT_MIRROR_URLS=http://debian-archive.trafficmanager.net/debian/
DEFAULT_MIRROR_SECURITY_URLS=http://debian-archive.trafficmanager.net/debian-security/
```
后接：
```bash
if [ "$DISTRIBUTION" == "resolute" ]; then
    DEFAULT_MIRROR_URLS=http://archive.ubuntu.com/ubuntu/
    DEFAULT_MIRROR_SECURITY_URLS=http://security.ubuntu.com/ubuntu/
fi
```
（armhf/arm64 用 `ports.ubuntu.com`，仿现有 armhf 逻辑补一条 resolute+arm 分支。）

- [ ] **Step 2: sources.list.j2 加 resolute 组件分支**

把 `files/apt/sources.list.j2` 开头：
```jinja
{% if DISTRIBUTION == 'bookworm' or DISTRIBUTION == 'trixie' -%}
{%- set nonfree_component='non-free-firmware' -%}
{%- else -%}
{%- set nonfree_component='non-free' -%}
{%- endif %}
```
改为：
```jinja
{% if DISTRIBUTION == 'resolute' -%}
{%- set components='main universe multiverse restricted' -%}
{%- set nonfree_component='' -%}
{%- elif DISTRIBUTION == 'bookworm' or DISTRIBUTION == 'trixie' -%}
{%- set components='main contrib non-free-firmware' -%}
{%- set nonfree_component='non-free-firmware' -%}
{%- else -%}
{%- set components='main contrib non-free' -%}
{%- set nonfree_component='non-free' -%}
{%- endif %}
```
并把模板体里的 `main contrib {{ nonfree_component }}` 替换为 `{{ components }}`。security suite 走 `resolute-security`（已在通用 `-security` 分支覆盖，确认 resolute 命中 else 分支用 `{{ DISTRIBUTION }}-security`）。

- [ ] **Step 3: Commit**

```bash
git add scripts/build_mirror_config.sh files/apt/sources.list.j2
git commit -m "build: apt source generator + template support Ubuntu resolute"
```

---

### Task 9: build_debian.sh — docker 版本 + apt 源 + 内核版本

**Files:**
- Modify: `build_debian.sh:30-32`（版本号）
- Modify: `build_debian.sh:233`（docker apt 源）

**Interfaces:**
- Consumes: Task 2 的 DOCKER_VERSION；Task 3 的内核 procure 结论。
- Produces: host OS 用 resolute docker 版本 + ubuntu docker 源；内核版本不变。

- [ ] **Step 1: docker/containerd 版本换 resolute**

把 `build_debian.sh:30-31`：
```bash
DOCKER_VERSION=5:28.5.2-1~debian.13~$IMAGE_DISTRO
CONTAINERD_IO_VERSION=1.7.28-2~debian.13~$IMAGE_DISTRO
```
改为（用 Task 2 实际字符串，去掉 `~debian.13~`，用 `~ubuntu.26.04~`）：
```bash
DOCKER_VERSION=5:28.5.2-1~ubuntu.26.04~$IMAGE_DISTRO
CONTAINERD_IO_VERSION=1.7.28-2~ubuntu.26.04~$IMAGE_DISTRO
```

- [ ] **Step 2: 内核版本行不改（确认）**

`build_debian.sh:32` `LINUX_KERNEL_VERSION=6.12.41+deb13` **保持不变**：
```bash
grep -n 'LINUX_KERNEL_VERSION=' build_debian.sh
```
预期：`6.12.41+deb13`（procure 预编译，ABI 不改）。

- [ ] **Step 3: docker apt 源换 ubuntu**

把 `build_debian.sh:233`：
```bash
deb [arch=$CONFIGURED_ARCH] https://download.docker.com/linux/debian $IMAGE_DISTRO stable
```
改为：
```bash
deb [arch=$CONFIGURED_ARCH] https://download.docker.com/linux/ubuntu $IMAGE_DISTRO stable
```

- [ ] **Step 4: Commit**

```bash
git add build_debian.sh
git commit -m "build: host OS docker version + apt repo on ubuntu resolute"
```

---

### Task 10: 内核 — procure 预编译（Task 3 路径）或 fallback 源码构建

**Files:**
- Modify: `rules/linux-kernel.mk`（按 Task 3 结论：procure 或源码构建）

**Interfaces:**
- Consumes: Task 3 的内核路径结论。
- Produces: 内核 .deb 由 procure 获取（不源码构建），或 resolute 上源码构建。

- [ ] **Step 1: 按 Task 3 结论分支**

**若 Task 3 找到预编译路径** → 在 `rules/linux-kernel.mk` 顶部把源码构建改为 download 现成 .deb（参考现有 `$(BUILD_PUBLIC_URL)` download 模式，如其他 rules 里的 `wget` + `dpkg -i`）。具体：把 `$(LINUX_KERNEL)_SRC_PATH = $(SRC_PATH)/sonic-linux-kernel` 这类源码构建改为 procure 目标，下载 `linux-image-6.12.41+deb13-sonic_*_amd64.deb` 等。

**若 Task 3 无预编译** → 保留源码构建，但确认在 resolute slave 上能构建（`KERNEL_ABISUFFIX=+deb13` 不改，或按需 `+resolute`）。本 plan 默认走 procure，fallback 见 spec R2。

- [ ] **Step 2: 验证内核 .deb 可获得**

```bash
cd ~/sonic-buildimage-resolute
make -n linux-kernel 2>&1 | grep -iE 'wget|dpkg|buildpackage' | head
```
预期：procure 路径出现 wget/dpkg，或源码路径出现 buildpackage。

- [ ] **Step 3: Commit**

```bash
git add rules/linux-kernel.mk
git commit -m "build: procure prebuilt SONiC kernel .deb for resolute (ABI +deb13-sonic unchanged)"
```

---

### Task 11: build_debian_base_system.sh — debootstrap resolute + 缓存路径

**Files:**
- Modify: `scripts/build_debian_base_system.sh:30`（mirror URL）
- Modify: `scripts/build_debian_base_system.sh:82`（apt-list 缓存路径）

**Interfaces:**
- Consumes: Task 4 的 debootstrap/keyring 结论。
- Produces: rootfs 从 Ubuntu mirror debootstrap resolute。

- [ ] **Step 1: mirror URL 改 Ubuntu**

把 `scripts/build_debian_base_system.sh:30`：
```bash
MIRROR_URL=http://deb.debian.org/debian
```
改为（按 resolute）：
```bash
MIRROR_URL=http://archive.ubuntu.com/ubuntu
```

- [ ] **Step 2: apt-list 缓存路径改 Ubuntu**

把 `scripts/build_debian_base_system.sh:82`：
```bash
APTDEBIAN="$APTLIST/deb.debian.org_debian_dists_${DISTRO}_main_binary-${CONFIGURED_ARCH}_Packages"
```
改为：
```bash
APTDEBIAN="$APTLIST/archive.ubuntu.com_ubuntu_dists_${DISTRO}_main_binary-${CONFIGURED_ARCH}_Packages"
```

- [ ] **Step 3: 若 Task 4 需 keyring，补 debootstrap 的 keyring/gpg 参数**

若 Task 4 Step 3 需 `--no-check-gpg` 或指定 keyring，在 `scripts/build_debian_base_system.sh` 的 debootstrap 调用处加：
```bash
--no-check-gpg   # 或 --keyring=/usr/share/keyrings/ubuntu-archive-keyring.gpg
```
（仅当 Task 4 确认需要时。）

- [ ] **Step 4: Commit**

```bash
git add scripts/build_debian_base_system.sh
git commit -m "build: debootstrap resolute from Ubuntu mirror, fix apt-list cache path"
```

---

### Task 12: build_debian.sh — 跳过 k8s/cri

**Files:**
- Modify: `build_debian.sh:242-280`（k8s/cri 安装段）

**Interfaces:**
- Produces: vs 构建跳过 cri-dockerd/kubelet/kubeadm/kubectl/kubernetes-cni/cri-tools。

- [ ] **Step 1: 定位 k8s/cri 段**

```bash
cd ~/sonic-buildimage-resolute
sed -n '240,285p' build_debian.sh
```
确认 cri-dockerd、kubelet 等安装块的范围。

- [ ] **Step 2: 用条件守卫跳过 resolute 的 k8s/cri**

把 k8s/cri 安装段包进条件（保留逻辑供 backlog 恢复）：
```bash
if [ "$IMAGE_DISTRO" != "resolute" ]; then
    # ... 原 cri-dockerd / kubelet / kubeadm / kubectl / kubernetes-cni / cri-tools 安装 ...
fi
```
确认 `cri-dockerd_...debian-${IMAGE_DISTRO}_amd64.deb` 那行（`build_debian.sh:278`）在守卫内。

- [ ] **Step 3: 验证守卫生效**

```bash
grep -n 'IMAGE_DISTRO.*resolute' build_debian.sh | head
```
预期：k8s/cri 段被 `!= resolute` 守卫包住。

- [ ] **Step 4: Commit**

```bash
git add build_debian.sh
git commit -m "build: skip k8s/cri on resolute (vs stage), backlog"
```

---

### Task 13: rules/config.user — FIPS 与构建配置

**Files:**
- Create: `rules/config.user`

**Interfaces:**
- Produces: 本地构建配置（INCLUDE_FIPS、PLATFORM=vs 等）。

- [ ] **Step 1: 写 config.user**

```bash
cat > rules/config.user <<'EOF'
# resolute migration local config
INCLUDE_FIPS ?= y
PLATFORM ?= vs
EOF
```

- [ ] **Step 2: 若 Task 7/Phase 1 FIPS binary 装失败，切 fallback**

（本步在 Phase 1 执行时若 FIPS Go 装不进才改）：
```bash
sed -i 's/INCLUDE_FIPS ?= y/INCLUDE_FIPS ?= n/' rules/config.user
```

- [ ] **Step 3: Commit**

```bash
git add rules/config.user
git commit -m "build: local config.user for resolute vs (FIPS=y default, fallback n)"
```

---

### Task 14: Phase 1 验证 — sonic-slave-resolute 构建

**Files:**
- 无文件改动；执行构建验证。

**Interfaces:**
- Consumes: Task 5–8、13。
- Produces: Phase 1 退出结论（slave 镜像可用 + FIPS 结论）。

- [ ] **Step 1: 构建 sonic-slave-resolute**

```bash
cd ~/sonic-buildimage-resolute
make sonic-slave-build BLDENV=resolute 2>&1 | tee /tmp/slave-build-resolute.log | tail -30
```
预期：构建成功产出 sonic-slave-resolute 镜像。若 FIPS Go 装失败（glibc/ABI 冲突）→ 走 Task 13 Step 2 fallback（`INCLUDE_FIPS=n`）后重试。

- [ ] **Step 2: 验证镜像 OS**

```bash
docker run --rm sonic-slave-resolute bash -c "cat /etc/os-release | head -3"
```
预期：`Ubuntu 26.04...` / `resolute`。

- [ ] **Step 3: 验证代表性源码构建 inside slave**

```bash
cd ~/sonic-buildimage-resolute
make -C target/linux/libswsscommon BLDENV=resolute 2>&1 | tail -10 || \
  make libswsscommon BLDENV=resolute 2>&1 | tail -10
```
预期：libswsscommon .deb 产出（或对应 make target 成功）。

- [ ] **Step 4: 记录 FIPS 结论**

确认 FIPS 走哪条路径（on 复用 trixie binary / fallback off），写入 commit 或备忘：
```bash
echo "FIPS status: <on/off> on $(date)" >> docs/superpowers/plans/fips-status.txt
```

- [ ] **Step 5: Commit（若 config.user 改了 fallback）**

```bash
git add rules/config.user docs/superpowers/plans/fips-status.txt 2>/dev/null
git commit -m "build: phase 1 verified, FIPS status recorded" || echo "nothing to commit"
```

---

### Task 15: Phase 2 验证 — vs host OS 镜像

**Files:**
- 无文件改动；执行构建验证。

**Interfaces:**
- Consumes: Task 9–13。
- Produces: Phase 2 退出结论（vs 镜像文件 + rootfs resolute）。

- [ ] **Step 1: 构建 vs 镜像**

```bash
cd ~/sonic-buildimage-resolute
make PLATFORM=vs BLDENV=resolute one-image 2>&1 | tee /tmp/vs-image-resolute.log | tail -30
```
预期：产出 vs 镜像文件（如 `target/sonic-vs.bin`）。若内核 procure 失败 → 走 Task 10 fallback（源码构建）。

- [ ] **Step 2: 验证 rootfs 是 resolute**

```bash
# 解包或挂载 vs 镜像，检查 rootfs 的 os-release（具体命令依镜像格式）
mkdir -p /tmp/vs-rootfs-check
# 示例：若为 squashfs，unsquashfs 后查
sudo unsquashfs -d /tmp/vs-rootfs-check/rootfs target/sonic-vs.squashfs 2>/dev/null && \
  cat /tmp/vs-rootfs-check/rootfs/etc/os-release | head -3
```
预期：`Ubuntu 26.04`。

- [ ] **Step 3: 验证 docker/内核/apt 源配置**

```bash
cat /tmp/vs-rootfs-check/rootfs/etc/apt/sources.list | head
ls /tmp/vs-rootfs-check/rootfs/boot/vmlinuz-* 2>/dev/null
```
预期：apt 源指向 archive.ubuntu.com；内核 `vmlinuz-6.12.41+deb13-sonic-*`。

- [ ] **Step 4: 清理**

```bash
sudo rm -rf /tmp/vs-rootfs-check
```

---

### Task 16: Phase 3 — docker-base-resolute 容器 base 镜像

**Files:**
- Create: `dockers/docker-base-resolute/Dockerfile.j2`（自 `dockers/docker-base-bookworm/Dockerfile.j2`）
- Create: `rules/docker-base-resolute.mk`（自 `rules/docker-base-bookworm.mk`）

**Interfaces:**
- Produces: `docker-base-resolute.gz`，`FROM ubuntu:resolute`。

- [ ] **Step 1: 复制 bookworm base 为 resolute**

```bash
cd ~/sonic-buildimage-resolute
cp -a dockers/docker-base-bookworm dockers/docker-base-resolute
cp rules/docker-base-bookworm.mk rules/docker-base-resolute.mk
```

- [ ] **Step 2: Dockerfile.j2 base 换 ubuntu:resolute**

把 `dockers/docker-base-resolute/Dockerfile.j2` 里 `debian:bookworm` 改 `ubuntu:resolute`：
```bash
sed -i 's|debian:bookworm|ubuntu:resolute|g' dockers/docker-base-resolute/Dockerfile.j2
grep -n 'ARG BASE' dockers/docker-base-resolute/Dockerfile.j2 | head
```

- [ ] **Step 3: docker-base-resolute.mk 重命名符号**

把 `rules/docker-base-resolute.mk` 里 `BOOKWORM`/`bookworm` 替换为 `RESOLUTE`/`resolute`，`SONIC_BOOKWORM_DOCKERS` → `SONIC_RESOLUTE_DOCKERS`：
```bash
sed -i 's/BOOKWORM/RESOLUTE/g; s/bookworm/resolute/g' rules/docker-base-resolute.mk
# 修正文件内引用的 DOCKER_BASE_BOOKWORM = docker-base-bookworm.gz 等
grep -n 'RESOLUTE\|resolute' rules/docker-base-resolute.mk | head
```

- [ ] **Step 4: 构建 base 镜像**

```bash
make docker-base-resolute BLDENV=resolute 2>&1 | tail -15
```
预期：产出 `docker-base-resolute.gz`。

- [ ] **Step 5: 验证**

```bash
docker run --rm $(docker load -i target/docker-base-resolute.gz 2>&1 | sed 's/.*: //') bash -c "cat /etc/os-release | head -2"
```
预期：`Ubuntu 26.04`。

- [ ] **Step 6: Commit**

```bash
git add dockers/docker-base-resolute rules/docker-base-resolute.mk
git commit -m "build: add docker-base-resolute (FROM ubuntu:resolute)"
```

---

### Task 17: Phase 4 — vs 容器服务镜像切 resolute base

**Files:**
- Modify: vs 相关 `dockers/docker-sonic-vs/Dockerfile.j2`、`dockers/docker-syncd-vs/Dockerfile.j2`、`dockers/docker-gbsyncd-vs/Dockerfile.j2` 等
- Modify: 对应 `rules/*-vs.mk` 接入 `SONIC_RESOLUTE_DOCKERS`

**Interfaces:**
- Consumes: Task 16 的 docker-base-resolute。
- Produces: vs 容器镜像基于 docker-base-resolute。

- [ ] **Step 1: 列出 vs 相关容器**

```bash
cd ~/sonic-buildimage-resolute
ls platform/vs/*.mk
grep -rlE 'docker-base-bookworm|DOCKER_BASE_BOOKWORM' platform/vs dockers 2>/dev/null | head
```

- [ ] **Step 2: 各 vs Dockerfile.j2 的 base 切 resolute**

对每个 vs 容器 Dockerfile.j2，把 `FROM ...docker-base-bookworm` / `ARG BASE=...bookworm` 切到 `docker-base-resolute`：
```bash
# 示例 docker-sonic-vs
sed -i 's|docker-base-bookworm|docker-base-resolute|g; s|debian:bookworm|ubuntu:resolute|g' \
  dockers/docker-sonic-vs/Dockerfile.j2 \
  platform/vs/docker-syncd-vs/Dockerfile.j2 \
  platform/vs/docker-gbsyncd-vs/Dockerfile.j2 2>/dev/null
```
（逐文件确认实际 FROM/ARG 写法，按需调整。）

- [ ] **Step 3: rules 接入 SONIC_RESOLUTE_DOCKERS**

把 vs 相关 `rules/*.mk` / `platform/vs/*.mk` 里 `SONIC_BOOKWORM_DOCKERS +=` 改为 `SONIC_RESOLUTE_DOCKERS +=`，或新增 resolute 分支：
```bash
grep -rl 'SONIC_BOOKWORM_DOCKERS' platform/vs rules | xargs sed -i 's/SONIC_BOOKWORM_DOCKERS/SONIC_RESOLUTE_DOCKERS/g'
```

- [ ] **Step 4: 构建 vs 容器镜像**

```bash
make docker-sonic-vs BLDENV=resolute 2>&1 | tail -15
make docker-syncd-vs BLDENV=resolute 2>&1 | tail -15
```
预期：各 vs 容器镜像构建成功。

- [ ] **Step 5: Commit**

```bash
git add dockers platform/vs rules
git commit -m "build: vs containers switch to docker-base-resolute"
```

---

### Task 18: Phase 5 — vs 镜像组装 + KVM boot + smoke（done-bar）

**Files:**
- 无文件改动；执行最终验证。

**Interfaces:**
- Consumes: Task 14–17。
- Produces: done-bar 结论（vs 启动 + smoke 通过）。

- [ ] **Step 1: 组装 vs 镜像**

```bash
cd ~/sonic-buildimage-resolute
make PLATFORM=vs BLDENV=resolute 2>&1 | tee /tmp/vs-final-resolute.log | tail -30
```
预期：产出可启动 vs 镜像（`.bin` / `.img`）。

- [ ] **Step 2: KVM 启动 vs**

按 `platform/vs/README.vsvm.md` 流程，用 libvirt/kvm 启动 vs 镜像：
```bash
sudo virsh create platform/vs/sonic.xml 2>/dev/null || \
  echo "按 README.vsvm.md 启动 vs VM"
```
预期：VM 启动到 SONiC 登录提示。

- [ ] **Step 3: SONiC smoke**

登录 vs VM 后执行：
```bash
config load_minigraph -y
show version
show ip intf
docker ps
```
预期：`config load_minigraph` 成功；`show version` 输出正常（distro 反映 resolute）；`show ip intf` 正常；syncd/swss/bgpp 等容器 `docker ps` 健康（Up）。

- [ ] **Step 4: trixie-vs 对照**

在 `BLDENV=trixie` 路径构建并 boot trixie-vs，重复 Step 3，对比输出一致性：
```bash
# （trixie 路径仍在 repo 内可用）
make PLATFORM=vs BLDENV=trixie ...   # 对照构建
```
预期：resolute-vs 与 trixie-vs smoke 行为一致。

- [ ] **Step 5: 记录结论**

```bash
echo "vs done-bar (KVM boot + smoke): PASS on resolute, $(date)" >> docs/superpowers/plans/done-bar-status.txt
git add docs/superpowers/plans/done-bar-status.txt
git commit -m "test: vs resolute boot+smoke done-bar passed"
```

---

### Task 19: Goal-2 研究交付物（并行轨道，不阻塞）

**Files:**
- Create: `docs/superpowers/specs/category-c-catalog-zh.md`
- Create: `docs/superpowers/specs/category-c-catalog-en.md`

**Interfaces:**
- Produces: Category-C 包的 verdict 表（不改源码构建）。

- [ ] **Step 1: 生成 catalog 模板**

对每个 Category-C 包（bash, iproute2, libnl3, libyang3, thrift, lldpd, openssh, monit, lm-sensors, ifupdown2, initramfs-tools, grub2, kdump-tools, redis, swig），查 `rules/<pkg>.mk` 的 patch 原因 + `src/<pkg>/patch/` + resolute apt 版本：

```bash
cd ~/sonic-buildimage-resolute
for pkg in bash iproute2 libnl3 libyang3 thrift lldpd openssh monit lm-sensors ifupdown2 initramfs-tools grub2 kdump-tools redis swig; do
  echo "=== $pkg ==="
  ls rules/$pkg.mk src/$pkg/patch/ 2>/dev/null | head
done
docker run --rm ubuntu:resolute bash -c "apt-cache policy $pkg 2>/dev/null | head -3" < /dev/null
```

- [ ] **Step 2: 填 verdict 表（zh+en）**

每包一行：包名 | 当前 patch 原因 | resolute apt 版本 | verdict（safe-to-swap / needs-patch-port / keep-source-build）。写入 `docs/superpowers/specs/category-c-catalog-zh.md` 与 `-en.md`。

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/specs/category-c-catalog-*.md
git commit -m "docs: Goal-2 Category-C package swap catalog (zh+en)"
```
