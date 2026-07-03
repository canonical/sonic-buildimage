# SONiC 202605 → Ubuntu Resolute 迁移设计（中文）

- **日期：** 2026-07-03
- **仓库：** 新建 `~/sonic-buildimage-resolute`（基于 upstream `202605`）
- **目标平台：** `vs`（虚拟交换机，软件 SAI，无厂商 SDK 二进制）
- **约束：** Ubuntu **必须** 26.04 / resolute，无退路（所有 fallback 必须在 resolute 体系内换实现，绝不退到 26.04 之前）

## 1. 目标

1. **换源为主（Goal 1）：** SONiC 构建链路从 Debian trixie 换到 Ubuntu resolute，使用 Ubuntu 同名包。所有 `rules/*.mk` 源码构建原样保留。
2. **非官方源包调研（Goal 2）：** 产出研究交付物 —— 对 Category-C 包（bash、iproute2、libnl3、libyang3、thrift、lldpd、openssh、monit、lm-sensors、ifupdown2、initramfs-tools、grub2、kdump-tools、redis、swig 等）逐包给出 verdict（safe-to-swap / needs-patch-port / keep-source-build）。**本次迁移不改源码构建。**
3. **顺序：先宿主再容器** —— 验证为 5 阶段：slave → host OS → 容器 base → vs 容器 → 组装+boot。
4. **以 vs 为目标：** done-bar = vs 镜像在 KVM 启动 + SONiC smoke 通过。

## 2. 方案选型

采用**方案 A —— 把 resolute 作为新的 BLDENV 增量接入**，并在专用仓库内设为**默认且唯一启用的 BLDENV**（禁用 bookworm/trixie）。

理由：复刻 SONiC 自己加 trixie 的模式；改动可 diff、可回退；trixie 路径保留作对照组；契合"几乎就是换源"。弃方案 B（最小覆盖，语义混乱、硬编码改不干净）与方案 C（抽象发行版层，对 vs 实验过重）。

## 3. "换源"核心切入点表

| # | 文件 | Debian (trixie) | resolute |
|---|------|-----------------|----------|
| **构建系统配置** | | | |
| 1 | [Makefile](Makefile) | `NOTRIXIE?=0`，catch-all → `BLDENV=trixie` | 增 `NORESOLUTE?=0`；默认 catch-all → `BLDENV=resolute`；设 `NOBOOKWORM=1 NOTRIXIE=1` |
| 2 | [Makefile.work:132](Makefile.work#L132) | `ifeq($(BLDENV),trixie) SLAVE_DIR=sonic-slave-trixie` | 增 `else ifeq($(BLDENV),resolute) SLAVE_DIR=sonic-slave-resolute` |
| 3 | [slave.mk:73](slave.mk#L73) | `IMAGE_DISTRO := trixie` | `IMAGE_DISTRO := resolute` |
| 4 | [slave.mk](slave.mk) ENABLE_PY2 过滤 | `bullseye bookworm trixie` | 增 `resolute` |
| **apt 源生成器（slave + host OS 共享）** | | | |
| 5 | [build_mirror_config.sh](scripts/build_mirror_config.sh) | `...debian-archive.../debian/` | Ubuntu mirror：`archive.ubuntu.com/ubuntu/`（amd64）、`ports.ubuntu.com/`（arm） |
| 6 | [files/apt/sources.list.j2](files/apt/sources.list.j2) | suite `trixie`/`-updates`/`-security`；组件 `main contrib non-free-firmware` | suite `resolute`/`-updates`/`-security`；组件 `main universe multiverse restricted`；security 走 `archive.ubuntu.com`；按需裁 `deb-src` |
| **slave 容器** | | | |
| 7 | [sonic-slave-trixie/Dockerfile.j2](sonic-slave-trixie/Dockerfile.j2) → 新 `sonic-slave-resolute/` | `FROM debian:trixie` | `FROM ubuntu:resolute` |
| 8 | sonic-slave `docker.sources` | `download.docker.com/linux/debian` | `download.docker.com/linux/ubuntu` |
| 9 | sonic-slave 钉版 docker | `docker-ce=5:28.5.2-1~debian.13~trixie` | resolute suite（见 Phase 0 spike a） |
| **主机 OS 镜像** | | | |
| 10 | [build_debian.sh:30-31](build_debian.sh#L30) | `~debian.13~$IMAGE_DISTRO` | `~ubuntu.26.04~$IMAGE_DISTRO`（依赖 spike a） |
| 11 | [build_debian.sh:32](build_debian.sh#L32) + [linux-kernel.mk:4](rules/linux-kernel.mk#L4) | `LINUX_KERNEL_VERSION=6.12.41+deb13`，`KERNEL_ABISUFFIX=+deb13` | **不改**（procure 预编译内核，ABI 沿用 `+deb13-sonic`） |
| 12 | [build_debian.sh:233](build_debian.sh#L233) | `download.docker.com/linux/debian $IMAGE_DISTRO stable` | `download.docker.com/linux/ubuntu resolute stable` |
| 13 | [build_debian_base_system.sh:30,40,46](scripts/build_debian_base_system.sh#L30) | `debootstrap ... $IMAGE_DISTRO ... http://deb.debian.org/debian` | debootstrap `resolute` from Ubuntu mirror（需 Ubuntu keyring + resolute 脚本） |
| 14 | [build_debian.sh:278](build_debian.sh#L278) | `cri-dockerd_...debian-${IMAGE_DISTRO}_amd64.deb` | **跳过**（k8s/cri backlog） |
| 15 | [build_debian_base_system.sh:82](scripts/build_debian_base_system.sh#L82) | `deb.debian.org_debian_dists_...` 缓存路径 | Ubuntu mirror 路径 `archive.ubuntu.com_ubuntu_dists_...` |
| **容器 base 镜像** | | | |
| 16 | [dockers/docker-base-bookworm/Dockerfile.j2](dockers/docker-base-bookworm/Dockerfile.j2) → 新 `docker-base-resolute/` | `ARG BASE=...debian:bookworm` | `...ubuntu:resolute` |
| 17 | 新 `rules/docker-base-resolute.mk` | `SONIC_TRIXIE_DOCKERS` | `SONIC_RESOLUTE_DOCKERS` |

## 4. 阶段化（5 阶段，每阶段硬门控）

### Phase 0 — 仓库初始化与 resolute BLDENV 接线（不构建）
- `git clone --reference ~/sonic-buildimage`（branch `202605`）→ `~/sonic-buildimage-resolute`；init submodules；建 `resolute` 分支。
- 加 `BLDENV=resolute` 管线：[Makefile](Makefile)、[Makefile.work](Makefile.work) `SLAVE_DIR` 分支、[slave.mk:73](slave.mk#L73)、ENABLE_PY2 过滤。
- Day-0 spike（并行，不阻塞）：
  - (a) 确认 Docker 是否发布 resolute 的 `docker-ce 5:28.5.2` + 精确版本字符串；若无 resolute build，确认改用 Ubuntu 官方 `docker.io` 包（仍在 resolute）。
  - (b) 确认 `BUILD_PUBLIC_URL` 是否提供 202605 预编译 SONiC 内核 .deb + 路径。
  - (c) debootstrap resolute 可用性 + Ubuntu keyring。
- **退出标准：** `make` 可解析，`BLDENV=resolute` 被选中，尚未拉源。

### Phase 1 — sonic-slave-resolute（构建容器，"宿主"层）
- 新 `sonic-slave-resolute/`（自 `sonic-slave-trixie/`）：`FROM ubuntu:resolute`，Ubuntu apt 源，`docker.sources` → `download.docker.com/linux/ubuntu`，钉版 docker 用 spike a 结论。
- 解决 apt 包名迁移：trixie→resolute 改名/移除包（`libgoogle-perftools4t64`、`librrd8t64`、`libcurl4t64`、`python3.13`→resolute python、`libthrift-0.19.0t64`、`libgrpc++1` 等）逐个映射。
- **FIPS：** 首选照原样从 `BUILD_PUBLIC_URL/fips/trixie/` 拉 trixie FIPS Go 装进 resolute slave；**fallback（若 glibc/ABI 冲突）= `INCLUDE_FIPS=n`，用 Ubuntu 官方 resolute 的 golang-go + openssl**（仍在 resolute，标技术债）。
- **退出标准：** `make sonic-slave-build BLDENV=resolute` 产出 sonic-slave-resolute 镜像；`docker run` 进去 `/etc/os-release` = Ubuntu 26.04；代表性源码构建（如 libswsscommon）跑通；FIPS 结论已定（on / fallback-off）。

### Phase 2 — SONiC 宿主 OS 镜像（build_debian.sh）
- [build_debian.sh:30-31](build_debian.sh#L30) docker/containerd 版本 `~ubuntu.26.04~resolute`（spike a）。
- [build_debian.sh:233](build_debian.sh#L233) docker apt 源 → `linux/ubuntu resolute`。
- **内核：procure 预编译 SONiC 内核 .deb**（spike b），`6.12.41+deb13-sonic` 沿用不改名；不源码构建 [rules/linux-kernel.mk](rules/linux-kernel.mk)。fallback = 在 resolute 上用 resolute 工具链源码构建（`+resolute` ABI）。
- [build_debian_base_system.sh](scripts/build_debian_base_system.sh) debootstrap `resolute` from Ubuntu mirror。
- **k8s/cri 跳过**（cri-dockerd/kubelet/kubeadm/kubectl/kubernetes-cni/cri-tools 条件跳过）→ backlog。
- apt 源生成器复用 Phase 1 改好的 Ubuntu mirror + sources.list.j2。
- **退出标准：** `make ... one-image PLATFORM=vs BLDENV=resolute` 产出 vs 镜像文件；rootfs `/etc/os-release` = Ubuntu 26.04。

### Phase 3 — 容器 base 镜像
- 新 `dockers/docker-base-resolute/Dockerfile.j2`（`FROM ubuntu:resolute`）、`rules/docker-base-resolute.mk`、`SONIC_RESOLUTE_DOCKERS`。
- **退出标准：** `docker-base-resolute.gz` 构建成功；`docker run` 进去 `/etc/os-release` = Ubuntu 26.04；base 层 apt 源/组件正确。

### Phase 4 — vs 相关容器服务镜像
- vs 用到的容器 Dockerfile.j2 base 切到 `docker-base-resolute`：docker-sonic-vs、docker-syncd-vs、docker-gbsyncd-vs、docker-router-advertiser、docker-dhcp-relay、docker-config-engine-resolute 等。
- 各 `rules/*-vs.mk` / `docker-*-resolute.mk` 接入 `SONIC_RESOLUTE_DOCKERS`。
- **退出标准：** vs 涉及的容器镜像全部构建成功；`docker run` 各容器能起。

### Phase 5 — vs 镜像组装 + KVM boot + smoke（done-bar）
- `make ... one-image PLATFORM=vs BLDENV=resolute` 产出 vs 镜像。
- KVM 启动 + SONiC smoke：`config load_minigraph -y`、`show version`、`show ip intf`、syncd/swss/bgpp 等容器 `docker ps` 健康。
- trixie-vs 作对照组，行为一致。

## 5. Goal-2 研究交付物（并行轨道，不阻塞 Phase 0–5）

- 产物：`docs/.../category-c-catalog-zh.md` + `-en.md`。
- 每包一行：包名、当前 patch 原因、resolute apt 版本、verdict（safe-to-swap / needs-patch-port / keep-source-build）。
- 源码构建不改。
- 结论来自背景调研（Category A/B/D/E 不可替换；Category C 是现实迁移目标；grpc/protobuf 的 `ifeq($(BLDENV),bookworm)` 守卫是 SONiC 自己"distro 跟上就丢源码构建"的现成范式）。

## 6. FIPS

- `INCLUDE_FIPS` 保持 `=y`。
- sonic-slave-resolute 的 FIPS Go 拉取段 `wget .../fips/trixie/...` 路径里的 `trixie` 保留不变（BUILD_PUBLIC_URL 无 resolute 目录），照原样从 `/fips/trixie/` 拉 trixie golang-go.deb + src.deb。
- **首选：** trixie FIPS Go 装进 resolute slave，能构建 + Go 二进制能跑 → 继续，标技术债。
- **fallback（ABI 冲突时）：** `INCLUDE_FIPS=n`，改用 Ubuntu 官方 resolute golang-go + 标准 openssl（仍在 resolute，不退版本）。FIPS 合规后置 backlog。
- Phase 1 退出前必须拿到 FIPS 结论（on / fallback-off）。

## 7. 风险登记表

| # | 风险 | 触发 | 缓解 / fallback（均在 resolute 体系内） |
|---|------|------|----------------------------------------|
| R1 | Docker 未发 resolute 的 `docker-ce 5:28.5.2`，版本字符串不存在 | Phase 0 spike a | 确认 resolute 命名钉版；若真无 resolute build，**改用 Ubuntu 官方 `docker.io` 包**（resolute，不退版本） |
| R2 | BUILD_PUBLIC_URL 无预编译 SONiC 内核 .deb | Phase 0 spike b | 在 resolute 上用 resolute 工具链源码构建（`+resolute` ABI） |
| R3 | debootstrap 无 resolute 脚本 / 缺 keyring | Phase 2 | 手动导入 Ubuntu keyring + `--no-check-gpg`；或用 Ubuntu 云镜像 `ubuntu:resolute` 作 base 替代 debootstrap（仍在 resolute） |
| R4 | cri-dockerd 无 resolute build，k8s 段失败 | Phase 2 | **既定决策：vs 阶段条件跳过** k8s/cri；backlog |
| R5 | trixie FIPS Go `.deb` 在 resolute 上 glibc/ABI 冲突 | Phase 1 | **fallback：`INCLUDE_FIPS=n`**，用 Ubuntu 官方 resolute golang-go + openssl；标技术债 |
| R6 | apt 包名迁移失败（`t64` 后缀包改名/不存在） | Phase 1 | 逐个映射到 resolute 包名；缺失则评估是否仍需；进 Goal-2 catalog |
| R7 | `python3.13`/`python3-distutils`/`python3-pip` 在 resolute 是别版 | Phase 1 | 对齐 resolute python 版本，更新 [sonic-slave-resolute](sonic-slave-trixie/Dockerfile.j2#L69) `python3.13` 字样 |
| R8 | Ubuntu 无 `non-free-firmware` 等价物 | Phase 2/3 | vs 不需厂商固件，缺失不阻塞；记录受影响包 |
| R9 | debootstrap apt-list 缓存路径硬编码 `deb.debian.org_debian_dists_` | Phase 2 | 改为 `archive.ubuntu.com_ubuntu_dists_` |
| R10 | sources.list.j2 的 Ubuntu suite 语义差异（security mirror、部分无 deb-src） | Phase 1/2 | 加 resolute 分支：security 走 `archive.ubuntu.com`，组件 `main universe multiverse restricted` |

## 8. 验证方法

- **对照组：** 全程保留 `BLDENV=trixie` 可用路径，trixie-vs 作预期输出基线。resolute-vs 出问题先在 trixie-vs 复现/对照，区分"resolute 回归" vs "环境问题"。
- **Phase 1：** `make sonic-slave-build BLDENV=resolute` 成功；`docker run` `/etc/os-release` = Ubuntu 26.04；代表性源码构建跑通；FIPS 结论已定。
- **Phase 2：** `make ... one-image PLATFORM=vs BLDENV=resolute` 产镜像；rootfs `/etc/os-release` = Ubuntu 26.04；docker/内核/apt 源均为 resolute。
- **Phase 3：** `docker-base-resolute.gz` 构建成功；`docker run` `/etc/os-release` = Ubuntu 26.04。
- **Phase 4：** vs 容器镜像全构建成功；`docker run` 各容器能起。
- **Phase 5：** KVM 启动；smoke 通过（`config load_minigraph -y`、`show version`、`show ip intf`、容器健康）；与 trixie-vs 对照一致。

## 9. Backlog（vs 之后）
- FIPS 合规工具链（resolute 版 Go + openssl FIPS）。
- k8s/cri 在 resolute 上落地（cri-dockerd 替代或 Ubuntu 原生路径）。
- Goal-2 catalog 中 needs-patch-port / safe-to-swap 的包实际替换（按 grpc/protobuf 范式）。
