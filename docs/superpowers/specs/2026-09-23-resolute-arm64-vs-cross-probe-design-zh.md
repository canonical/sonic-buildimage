# Resolute arm64 vs 交叉构建探路 — 设计

- 日期:2026-09-23
- 作用仓库:`/home/sheldon-qi/sonic-buildimage-resolute`(分支 `202605_resolute`,基线 `2c0e2bc031`)
- 探路工作树:`/home/sheldon-qi/sbi-arm64-probe`(独立 worktree,不污染主工作树)
- 构建宿主机:Ubuntu 26.04,x86_64,16 核 / 47 GB 内存 / 162 GB 可用盘
- 目标:判断"要不要为 arm64 SONiC 去弄一台原生 arm64 机器",而不是产出镜像
- 相关文档:[完全干净从零构建设计](2026-07-21-resolute-clean-rebuild-design-zh.md)、[迁移设计](2026-07-03-sonic-202605-resolute-migration-design-zh.md)
- 本文为中文版;英文版为唯一事实来源(`-en.md`)

## 1. 目标与范围

在 amd64 宿主机上用 SONiC 的交叉编译路径(`CROSS_BLDENV=1`)推进一次 `PLATFORM=vs PLATFORM_ARCH=arm64` 构建,推到走不动为止,收集**完整的失败清单**并分类。

这是探路,不是交付镜像。产出物是一份带分类的失败清单和一条结论:原生 arm64 机器对这件事有多必要。

**不在范围内:** 不修任何包级失败、不改 build graph 去掉组件、不追求产出 `target/sonic-vs.bin`。所有修复决策留到分类结论出来之后。

## 2. 判据:失败三分类

每一条失败归入且仅归入一类。分类决定结论。

| 类 | 定义 | 换原生 arm64 机器是否消除 |
|---|---|---|
| **A 交叉专有** | 只在交叉编译下发生:`debian/rules` 不支持 `-a arm64`、`configure` 猜错 host、wheel 无 aarch64 轮子需就地编译、cross venv 路径问题 | **是**,原生构建根本不走这条代码路径 |
| **B 架构固有** | arm64 本身缺东西:上游只发 amd64 镜像/包、二进制产物只有 x86_64 版本 | **否**,换机器一样要改代码 |
| **C 移植假设** | `202605_resolute` 自己引入的 amd64 假设 | **否**,是我们的欠账 |

决策规则:A 类占失败主体 → 值得去弄原生机器,因为那一整类失败会免费消失;B/C 占主体 → 弄了机器也要做同样的代码修改,不如就地改。

## 3. 已验证的事实基线

以下均在本次设计前实测确认,不是推断。

| 项 | 结论 | 证据 |
|---|---|---|
| 内核 | linux-sonic 7.0.0-1002.2 的 arm64 `linux-image` / `linux-modules` / `linux-headers` 均已 Published | Launchpad API 查 `canonical-kernel-team/bootstrap` PPA;`rules/linux-kernel.mk` 的 URL 本就按 `CONFIGURED_ARCH` 参数化 |
| apt 源 | Ubuntu 26.04 归档已统一,`archive.ubuntu.com` 同时服务 arm64,**不需要 ports.ubuntu.com** | `dists/resolute/Release` 的 `Architectures: amd64 amd64v3 arm64 armhf i386 ppc64el riscv64 s390x` |
| ONLINE_DEB | `rules/*.mk` 里硬编码 `archive.ubuntu.com` 的 pool URL 对 arm64 照样可下 | grub2-common / libnl-3-200 / sedutil 的 arm64 deb 均 range 请求成功 |
| 基础镜像 | `ubuntu:resolute` 含 arm64 | Docker Hub manifest list |
| grub | `rules/grub2.mk` 已有 arm64 分支;`grub-efi-arm64`(`-bin`) 2.14-2ubuntu1 存在 | 分支内代码 + pool 实测 |
| slave 依赖 | `qemu-system-x86`、`libboost1.83-dev`、`libthrift-0.22.0`、`golang-1.24-go`、`libwtmpdb-dev`、`python3-dacite`、`perl-modules-5.40` 的 arm64 均有;`docker-ce` / `containerd.io` 钉死版本的 arm64 均有 | Launchpad API;`download.docker.com` 的 `dists/resolute/stable/binary-arm64` |
| 交叉工具链 | `crossbuild-essential-arm64`、`gcc-aarch64-linux-gnu`、`dpkg-cross` 在 resolute amd64 上都有 | Launchpad API |
| 交叉支持深度 | 63 个文件消费 `CROSS_BUILD_ENVIRON`,含 35 个 `src/*/Makefile`、dpkg-cross 配置、Rust 交叉目标 `aarch64-unknown-linux-gnu`、Python 交叉 venv | 仓库内检索 |
| FIPS | resolute 上被 `rules/sonic-fips.mk` 的 `$(error)` 硬挡,不构成额外变量 | 分支内代码 |
| `MIRROR_SNAPSHOT` | 默认 `n`,快照路径不参与 | `rules/config:337` |

已知的 **B/C 类**(探路前就确定的,不必等清单):

- **B**:`platform/vs/docker-dash-engine/Dockerfile.j2` 的基础镜像 `p4lang/behavioral-model:latest` **只有 amd64**(manifest list 确认),而它被 `platform/vs/docker-dash-engine.mk` 无条件加入 `SONIC_INSTALL_DOCKER_IMAGES`。
- **B**:`platform/vs/onie.mk` 钉的 ONIE recovery ISO 只有 `x86_64` 版,因此 `sonic-vs.img.gz`(KVM 镜像)在 arm64 上不可能产出;arm64 的唯一现实目标是 `target/sonic-vs.bin`。
- **C**:`sonic-slave-resolute/Dockerfile.j2:575` 无条件装 `gcc-multilib`,而 resolute 的 arm64 根本没发布这个包。**交叉模式下该行走 else 分支不执行**,所以本次探路不会撞上;但非交叉路径上它是硬阻塞。

## 4. 隔离

探路在独立 git worktree `/home/sheldon-qi/sbi-arm64-probe` 进行,理由:

1. `make configure` 会写 `.arch` / `.platform`,就地跑会把主工作树的 amd64 配置改掉。
2. `DOCKER_ROOT` 是 `fsroot.docker.$(BLDENV)`,两种架构同名同路径,会互相覆盖。
3. `target/` 共用,arm64 产物会混进现有 amd64 产物。

共享 dpkg 缓存(`/var/cache/sonic/artifacts`,当前 14 GB)在探路期间另指一个目录,避免 arm64 产物混入 amd64 的键空间。

## 5. 三级闸门

逐级推进,任一级卡住就地判定并记录,不硬闯。

### 5.1 闸门一:环境

装 `qemu-user-static`,注册 binfmt,起 march dockerd。注意**交叉模式也需要这一套**:`Makefile.work:434` 的条件是 `MULTIARCH_QEMU_ENVIRON` 或 `CROSS_BUILD_ENVIRON` 任一为 `y`,因为 rootfs 与各 docker 镜像仍是 arm64 容器,里面的 dpkg/postinst 要靠 qemu-user 执行。交叉编译省的是编译时间,省不掉这套环境。

march dockerd 用 `--storage-driver=vfs`(无层共享,吃盘)、data-root `/var/lib/march/docker`。开跑前确认盘量,过程中盯住。

通过判据:binfmt 注册了 aarch64 handler,march dockerd 起来且 socket 可用。

### 5.2 闸门二:交叉 slave 镜像

```
BLDENV=resolute CROSS_BLDENV=1 make configure PLATFORM=vs PLATFORM_ARCH=arm64
```

产出 `sonic-slave-resolute-march-arm64`(amd64 基底 + aarch64 交叉工具链)。这是第一道真闸门 —— slave 起不来,后面全是空谈。

已预判的风险点:`sonic-slave-resolute/Dockerfile.j2` 的交叉分支里有 `apt-mark hold g++-10-$gcc_arch` / `gcc-10-$gcc_arch`,而 resolute 的 gcc 默认为 15,不存在 10 版本的交叉包。此处若失败,归 **C 类**。

通过判据:镜像构建成功,容器内 `aarch64-linux-gnu-gcc --version` 可执行。

### 5.3 闸门三:全量收集

目标是一轮跑完拿到完整失败清单,而不是"失败—修—再跑"的串行发现。

`-k`(keep-going)无法穿透到容器内:外层 `make` 的 `MAKEFLAGS` 不在 `DOCKER_RUN` 的 `-e` 列表里,而容器内是一次全新的 `$(MAKE) -f slave.mk` 调用。做法是:

1. 用 `make -n` 干跑,抓出 `Makefile.work:575` 的 `SONIC_BUILD_INSTRUCTION` 实际展开的完整命令行(含 `PLATFORM` / `PLATFORM_ARCH` / `CROSS_BUILD_ENVIRON` / `TARGET_BOOTLOADER` 等全部变量)。
2. 用 `make ... sonic-slave-bash`(`Makefile.work:736`)进容器。
3. 在容器内执行同一条命令行,插入 `-k`,目标 `target/sonic-vs.bin`。

全程留日志。构建并发按 `SONIC_CONFIG_BUILD_JOBS` 现有设置,不为探路调参。

通过判据:跑到不再产生新的失败种类为止。

## 6. 零代码绕过

探路阶段预期代码改动为零,以下两项用命令行变量处理而非改文件:

- `TARGET_BOOTLOADER=grub` —— `Makefile.work:127` 对非 amd64 一律给 `uboot`,于是 `build_debian.sh:799` 会去找不存在的 `platform/vs/sonic_fit.its`,`set -e` 直接死。命令行变量优先级高于 makefile 赋值,且 `SONIC_BUILD_INSTRUCTION` 把 `TARGET_BOOTLOADER` 显式透传进容器,所以从最外层传一次即可贯通。长期正解是在 `platform/vs/rules.mk` 加 `override TARGET_BOOTLOADER=grub`(先例:`platform/nvidia-bluefield/rules.mk:21`),但那是探路之后的事。
- `gcc-multilib` —— 交叉模式下本就不执行,无需处理。

`docker-dash-engine` 不预先绕开,让它在清单里如实体现为一条 B 类失败。

## 7. 产出物

1. 完整失败清单,每条含:失败的目标、报错要点、A/B/C 分类、分类依据。
2. 一条结论:原生 arm64 机器的必要性,由 A 类占比支撑。
3. 若结论是"需要原生机器",附机器规格要求(核数/内存/盘/网络可达性)。

## 8. 风险与放弃条件

- **盘**:vfs 无层共享,arm64 容器与 rootfs 会显著吃盘。低于 30 GB 可用时停下清理,不硬撑到写满。
- **共享缓存污染**:靠第 4 节的缓存目录隔离防住;若发现 amd64 缓存被动过,立刻停。
- **闸门二即卡死**:若交叉 slave 镜像修不动,说明连起跑线都没到。此时直接给结论——在这台机器上交叉路不通,只剩原生机器或纯 qemu 两条路——不再推进闸门三。
- **长尾无边界**:若闸门三的失败清单出现明显的"修一个冒三个",停止收集,以已有样本作结论。探路的价值在于判断,不在于穷尽。
