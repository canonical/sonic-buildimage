# 202605_resolute 上的 arm64 vs：交叉构建探路报告

- 日期：2026-09-23
- 作用仓库：`/home/sheldon-qi/sonic-buildimage-resolute`，分支 `202605_resolute`，基线 `2c0e2bc031`
- 探路工作树：`/home/sheldon-qi/sbi-arm64-probe`，本地分支 `probe/arm64-vs-cross`，所有改动未提交
- 构建宿主机：Ubuntu 26.04，x86_64，16 核 / 47 GB 内存
- 设计与计划：[探路设计](specs/2026-09-23-resolute-arm64-vs-cross-probe-design-zh.md)、[探路计划](plans/2026-09-23-resolute-arm64-vs-cross-probe-zh.md)
- 本文为中文版；英文版为唯一事实来源（`-en.md`）

## 0. 问题与结论

要回答的不是"能不能构建出 arm64 vs 镜像"，而是**"arm64 SONiC 值不值得专门弄一台原生 arm64 构建机"**。探路在 amd64 宿主机上用 SONiC 的交叉编译路径（`CROSS_BLDENV=1`）推进 `PLATFORM=vs PLATFORM_ARCH=arm64` 构建，推到走不动为止，并按唯一判据给每条失败分类：换成原生 arm64 构建，它还会不会出现？

**结论：值得，应该弄一台原生 arm64 机器。**

- 探路在 SONiC 本身找到 **21 条失败，其中 19 条只是因为交叉编译才存在**，换原生机器就消失。另外 2 条是架构固有问题，怎么构建都得改代码，但都是小改动。
- 上游没人维护交叉路径，它在任何现行发行版上都跑不通：hold `gcc-10` 包、装 `python3-distutils`、在环境变量设好之前就跑 `rustup`、通过 `ARG` 传 `--platform`。这些写法在现代发行版上已经多年构建不过了。要让它跑通，等于自己维护一份 SONiC 交叉基础设施的分叉。
- 越过探路停下的前沿，静态扫描还能查出**至少 8 处交叉专有的构建依赖缺口，外加一处结构性的 Python 冲突**，而且这些都还没碰到容器层。失败是一轮冒一个，看不到头。
- 速度是次要理由：光是 arm64 rootfs 就花了 47 分钟，几乎全在 qemu 下（`mkinitramfs` 每次 shell 调用都要起一个模拟进程）。原生构建以全速跑完这一步。

探路**没有**验证原生构建能不能真的出 `.bin`。§6 列出了原生路径预计要做的事，但没有原生构建来背书。

## 1. 走到了哪一步

| 闸门 | 结果 |
|---|---|
| 一 模拟环境 | 通过。注册了 `aarch64` handler，arm64 容器能跑。 |
| 二 交叉 slave 镜像 | 8 轮全量 + 3 轮影子构建后通过：`sonic-slave-resolute-march-arm64`（16.8 GB），`aarch64-linux-gnu-gcc` 15.2.0。用了 5 处代码破例、1 次模拟器替换、补了 1 个缺失的配置项。 |
| 三 全量收集（`-k`） | 4 轮推到依赖前沿，建出了 **78 个 deb（其中 31 个是编译出的 arm64 二进制包）、6 个 wheel、完整的 arm64 rootfs（`rfs.squashfs`，733 MB，内核 `7.0.0-1002-sonic`）和 2 个容器镜像**。用了 2 处代码破例。下一层出现了"修一个冒一个"的规律，按计划的长尾规则停止收集，剩下的改用静态枚举。 |

闸门三里，一条交叉专有失败挡住了整个容器层：`libswsscommon` 依赖 `python3-libyang`（arm64），而它装不进 slave 的 amd64 Python（§3.2 G3-8）。连锁是 swss-common → python3-swsscommon → 所有 SONiC Python wheel → `docker-config-engine` → **除 `docker-base` 和 `docker-dash-engine` 以外的每一个 SONiC 容器**。

## 2. 分类

| 类 | 含义 | 条数 |
|---|---|---|
| **A** | 交叉专有，原生构建会消除 | **19** |
| **B** | 架构固有，怎么构建都要改代码 | **2** |
| **Q** | 模拟器缺陷（qemu 版本） | 1 |
| **E** | 本机环境 | 3 |

来源（上游失修、resolute 移植、Ubuntu 打包）和类别是两个独立维度。好几条 A 类出自 resolute 移植，但只在交叉路径上才咬人。

## 3. 发现

### 3.1 闸门二：交叉 slave 镜像（`sonic-slave-resolute/Dockerfile.j2`）

| # | 失败 | 来源 | 类 |
|---|---|---|---|
| G2-1 | `apt-mark hold g++-10-$gcc_arch` / `gcc-10-…`：包不存在 | 上游。trixie、bookworm、bullseye 三个 slave 里是一模一样的行，现行发行版都不带 gcc-10。 | A |
| G2-2 | `python3-distutils`、`libpython2.7-dev`、`libbind-export-dev`、`libiptc0` 不存在 | 上游。Debian trixie 上这四个也都没有。 | A |
| G2-3 | `python3.13` / `python3.13-dev` 不存在（resolute 是 3.14） | resolute 移植（trixie 上有） | A |
| G2-4 | `libcurl4-openssl-dev` 的 amd64 与 arm64 在 `/usr/bin/curl-config` 上冲突 | Ubuntu 打包。同版本两份文件只差一处：`curl-config --configure` 里嵌的 `--package-metadata` 分别是 `"architecture":"amd64"` 和 `"arm64"`。Debian 的两份逐字节相同。值得给 Launchpad 报 bug。 | A |
| G2-5 | `apt install python-is-python3` 拒绝执行：Unmet dependencies | 上游。前面用 `dpkg --force-all` 装 arm64 的 `python3.14-dev`、`libgirepository1.0-dev` 留下了依赖破损，apt 拒绝在破损系统上操作。 | A |
| G2-6 | `rustup target add aarch64-unknown-linux-gnu`：没有默认工具链 | 上游。这一步在 `ENV RUSTUP_HOME` 之前执行，rustup 去 `/root/.rustup` 里找。 | A |
| G2-7 | `docker run`：Duplicate mount point `/var/lib/docker` | 上游配置。交叉/qemu 构建必须设 `SONIC_SLAVE_DOCKER_DRIVER=vfs`，上游 CI 设了（`.azure-pipelines/azure-pipelines-build.yml:49-50`），README 从没提。 | A |
| Q-1 | arm64 Python 3.14 随机段错误：pip 构建依赖"0 lines of output"，py3compile `status code -11` | `Makefile.work:457` 硬编码的 `multiarch/qemu-user-static` 7.2.0（镜像 2023-01，项目已停更） | Q |

**Q-1 的 A/B 测试**：16 路并发，每路执行 40 次 `python3.14 -c "import importlib.util, json, email, asyncio"`，同一个镜像层：

| qemu | 次数 | 段错误 |
|---|---|---|
| multiarch 7.2.0（SONiC 硬编码） | 2560 | **7**（约 1/366） |
| tonistiigi/binfmt `qemu-v9.2.2` | 3840 | **0** |

串行跑 60 次，两个版本都不崩；要有并发才崩。假如两个版本崩溃率相同，7 次崩溃全落在 7.2.0 那份样本里的概率约 0.16%。**偶发崩溃是旧 qemu 的缺陷，不是模拟这件事本身的属性。**换版本后，100 步的 slave 构建一次跑完。

### 3.2 闸门三：包与镜像构建

| # | 目标 | 根因 | 类 |
|---|---|---|---|
| G3-1 | bash | 构建期工具 `mkbuiltins.c` 被 `aarch64-linux-gnu-gcc` 编译，撞上 GCC 15 默认的 C23：`'bool' cannot be defined via 'typedef'`。同一份源码在 resolute amd64 上能编，Ubuntu 也原生构建了 arm64 的 bash。 | A |
| G3-2 | hsflowd | host-sflow 把 `-std=gnu99` 写进了 `$(CC)`。原生编译命令是 `gcc -std=gnu99 …`；交叉时覆盖 CC 把这个选项丢了，GCC 15 退回 C23，`typedef uint32_t bool;` 报错。 | A |
| G3-3 | sflowtool | configure 用宿主 `gcc` 配上 arm64 的 `dpkg-buildflags`（`-mbranch-protection=standard`），该 gcc 报"无法识别的选项" | A |
| G3-4 | monit | `patch/cross-compile-changes.patch` 只在交叉路径打，而且已经打不进 Ubuntu 的 monit 5.35.2-3。移植把源从 Debian 换成了 Ubuntu，这个补丁没跟着刷新。 | A |
| G3-5 | lldpd | 缺构建依赖 `libsnmp-dev`（arm64）。从 trixie 起 snmpd 改用发行版包（`rules/snmpd.mk:5`），交叉 slave 的 `:arm64` 清单一直没补上它。 | A |
| G3-6 | libdashapi | 缺构建依赖 `libprotobuf-dev (>= 3.21.12)`（arm64） | A |
| G3-7 | libnexthopgroup | `Build-Depends: python3` 没写 `:any`，交叉构建要求 arm64 的 Python | A |
| G3-8 | python3-libyang（arm64）安装 | 依赖 arm64 的 `python3 (>= 3.14~)`，而 slave 里的 Python 是 amd64。**这一条挡住了整个容器层（§1）。** | A |
| G3-9 | systemd-sonic-generator | `aarch64 ld: cannot find -lboost_system`。交叉 `:arm64` 清单装的是不带版本号的 `libboost-*-dev`，在 resolute 上解析成默认的 1.90（已核实：`libboost-filesystem1.90-dev:arm64`），而 Boost 从 1.89 起删掉了 `boost_system` 桩库。移植把原生清单钉到了 1.83，交叉清单没钉。 | A |
| G3-10 | sonic-platform-vs | "binary build with no binary artifacts found"。上游写死了 `sonic-platform-vs_…_amd64.deb`、`Architecture: amd64` 和平台 `x86_64-kvm_x86_64-r0`：**上游把 vs 设计成只支持 x86_64 KVM。**原生构建一样失败。 | **B** |
| G3-11 | docker-base-resolute | `ARG BASE=--platform=linux/arm64 ubuntu:resolute` + `FROM $BASE` → BuildKit 报"failed to parse stage name"。BuildKit 不会把 `ARG` 里的标志展开进 `FROM`，而这个 Dockerfile 离不开 BuildKit（`RUN --mount=type=bind,from=base`）。trixie、bookworm 的模板写法完全相同。 | A |
| G3-12 | docker-base-resolute（修复后） | 建成了，但**标签错了**：内容是真 aarch64（`/usr/bin/bash` 的 e_machine 为 `b700`），镜像配置却写着 `architecture=amd64`，因为最终的 `FROM scratch` 阶段没带平台。派生镜像会继承这个标签。 | A |
| G3-13 | docker-dash-engine | **静默的错架构产物。**构建成功，但基础镜像 `p4lang/behavioral-model:latest` 只有 amd64 版。日志拉的是 `noble/multiverse amd64 Packages`，镜像配置写着 `architecture=amd64`。arm64 构建不报任何错，会一路塞进 `sonic-vs.bin`，到设备上报 exec format error。 | **B** |
| G3-14 | libswsscommon | 缺构建依赖 `libhiredis-dev`（arm64） | A |

### 3.3 没越过的前沿（静态扫描）

每轮构建只多暴露一个缺失的交叉构建依赖，所以探路停止逐轮构建，改在交叉 slave 里对全部 70 个在树 `debian/control` 跑 `dpkg-checkbuilddeps -a arm64 -Pcross,nocheck`，这和 `dpkg-buildpackage` 内部的检查相同。70 个里有 25 个有缺口。去掉 SONiC 自建的依赖（真实构建时会先 `-install`）以及不在 `sonic-vs.bin` 闭包里的包（gobgp/`dh-systemd`、ptf/`python-all`、freeradius、frr 的 gcc-plugins、只在 trixie 构建的 redfish）之后，剩下：

- **交叉清单里缺的发行版 arm64 开发包**：`libhiredis-dev`、`libprotobuf-dev`、`libprotobuf-c-dev`、`libsnmp-dev`、`libxxhash-dev`、`liblua5.1-0`、`libboost-serialization1.83-dev`（外加只有 redfish 用的 `libjsoncpp-dev`）
- **结构性冲突**：`Build-Depends: python3 / python3-all / python3-all-dev` 没写 `:any`，要求 arm64 Python；frr 的 `python3-dev:native` 满足不了，因为交叉 slave 用 `--force-all` 装了 `python3-dev:arm64`，把 amd64 那份挤掉了。交叉 slave 在"装哪个架构的 Python"上跟自己打架。

机理：交叉 slave 的 `:arm64` 包清单是**手工维护的第二份构建依赖集**。上游把 snmpd、hiredis、protobuf 改成用发行版包之后，没人同步它。原生构建的构建依赖来自 amd64 构建也在用的那唯一一份清单，这份清单一直是最新的。

### 3.4 本机环境（与 SONiC、arm64 都无关）

| # | 现象 | 原因 |
|---|---|---|
| E-1 | rootfs 的 `apt-get update` → `https://mirrors.tuna.tsinghua.edu.cn/...` 证书校验失败 | `/etc/hosts` 把 `ports.ubuntu.com`、`archive.ubuntu.com` 都指到本地镜像站 `192.168.10.32`，后者对 `ports` 请求 302 重定向到 tuna 的 HTTPS，而刚建好的 minbase rootfs 还没装 `ca-certificates`。用 `MIRROR_URLS=http://archive.ubuntu.com/ubuntu/` 绕过。 |
| E-2 | debootstrap 里一个 wget 挂了 15 分钟，0 字节 | 本地镜像站瞬时挂起。wget 默认读超时 900 秒，超时后重试恢复。 |
| E-3 | BuildKit：`lookup auth.docker.io on 10.211.55.1:53: i/o timeout` | 瞬时 DNS 超时。仓库 token 是 slave 容器里的客户端会话去取的，所以走的是容器的 DNS。 |

E-1 还顺带暴露了一处真实的不一致：对 arm64，`scripts/build_debian_base_system.sh` 让 debootstrap 用 `archive.ubuntu.com`，`scripts/build_mirror_config.sh` 却写 `ports.ubuntu.com`。Ubuntu 26.04 已统一归档（`dists/resolute/Release` 的 `Architectures:` 行包含 arm64），只用 `archive.ubuntu.com` 就够了。

## 4. 时间与资源

| 阶段 | 耗时 | 说明 |
|---|---|---|
| 交叉 slave 镜像（最后一次全量） | 约 40 分钟 | 11:32–12:12Z；每次 `configure` 都从第 6 步重建，因为 `sonic-build-hooks` 每次运行都重新生成 `buildinfo` |
| 闸门三第 1 轮 | 24 分钟 | 包层 |
| 闸门三第 2 轮 | 49 分钟 | 光 arm64 rootfs 就 46 分 51 秒，几乎全在 qemu 下（`mkinitramfs` 每次 shell 调用起一个模拟进程） |
| 闸门三第 3 轮 | 13 分钟 | qemu 下构建 `docker-base` |
| 闸门三第 4 轮 | 4 分钟 | 推到 libswsscommon 的构建依赖 |

可用盘从 161 GB 降到 72 GB。march dockerd 用 `--storage-driver=vfs`，层之间不共享：2.9 GB 的镜像占了 26 GB 盘（约 9 倍），`/var/lib/march/docker` 涨到 35 GB。slave 镜像 16.8 GB。整个探路期间，amd64 共享 dpkg 缓存零写入。

## 5. 如果坚持走交叉路径

动 SONiC 之前，有三件事是前提：

1. **换掉 qemu 7.2.0。**注册 `tonistiigi/binfmt:qemu-v9.2.2`，并在 make 命令行上传 `DOCKER_MULTIARCH_CHECK=true`；否则每次 make 都会重新注册 7.2.0（`Makefile.work:702`）。
2. **设 `SONIC_SLAVE_DOCKER_DRIVER = vfs`**，否则 `docker run` 会因重复挂载失败。
3. **给 vfs 留足盘。**至少预留 150 GB；探路用掉 89 GB，还没碰到容器层。

然后是 19 条 A 类（其中 9 条已在探路中绕过，见 §7；G3-8 只是强行装上），§3.3 里至少 8 处依赖缺口，以及 Python 双架构冲突。Python 冲突是设计问题，不是缺哪个包：交叉 slave 既要 amd64 的 Python 来跑构建工具，又要 arm64 的 Python 头文件和扩展来链接，而 Debian 打包不允许两个架构的 `python3-dev` 同时装。

## 6. 原生路径预计要做的事（未验证）

以下在探路前就已查实，但探路没有实际走到：

- `sonic-slave-resolute/Dockerfile.j2:575` 无条件装 `gcc-multilib`，而 resolute 的 arm64 根本没发布这个包。只有原生路径会执行这一行。（C 类：resolute 移植假设。）
- `Makefile.work:127` 对所有非 amd64 架构都给 `TARGET_BOOTLOADER=uboot`。不在 `platform/vs/rules.mk` 里加 `override TARGET_BOOTLOADER=grub`（先例：`platform/nvidia-bluefield/rules.mk:21`），`build_debian.sh:799` 就会去找不存在的 `platform/vs/sonic_fit.its`。
- G3-10（vs 平台包只支持 amd64）和 G3-13（dash-engine 基础镜像只有 amd64）。
- `sonic-vs.img.gz` 依然建不了：`platform/vs/onie.mk` 里的 ONIE recovery ISO 只有 x86_64 版。arm64 现实可行的目标是 `target/sonic-vs.bin`。

架构层面的编译问题很少见，有证据：78 个 deb 里，31 个 arm64 二进制包（约 18 个源码包，涵盖 C、Go——sonic-mgmt-framework/common——和 Rust——sonic-nettools）是真正为 aarch64 编译出来的，全部编译通过；其余是下载的现成包（内核、libnl、grub 等）或 arch:all。这次探路中没有一条失败是 arm64 代码本身的问题。

**机器要求**：16 核以上、48 GB 以上内存、200 GB 以上磁盘。原生构建不需要 vfs，也不需要 march dockerd。需要能访问 `archive.ubuntu.com` / `ports.ubuntu.com`、`ppa.launchpadcontent.net`（linux-sonic 内核，arm64 包已发布）、Docker Hub、GitHub、PyPI、`download.docker.com`，并且需要 amd64 构建已经依赖的那两项宿主修复（AppArmor `gs` 覆盖、`ip_tables` 模块）。

## 7. 探路改动与现状

全部在 `/home/sheldon-qi/sbi-arm64-probe`，未提交。完整 diff 见 [data/2026-09-23-arm64-cross-probe-deviations.patch](data/2026-09-23-arm64-cross-probe-deviations.patch)。

| # | 文件 | 改动 | 解决 |
|---|---|---|---|
| 1 | `sonic-slave-resolute/Dockerfile.j2` | 删掉 `g++-10` / `gcc-10` 的 hold | G2-1 |
| 2 | 同上 | `python3.13` → `python3.14`（两处）；去掉 `python3-distutils`、`libpython2.7-dev`、`libbind-export-dev`、`libiptc0` | G2-2、G2-3 |
| 3 | 同上 | 在那一个安装 RUN 前后用 `dpkg` 的 `path-exclude=/usr/bin/curl-config` | G2-4 |
| 4 | 同上 | `python-is-python3` 改为 `apt-get download` + `dpkg -i` | G2-5 |
| 5 | 同上 | `rustup target add` 前加 `RUSTUP_HOME=$RUST_ROOT` | G2-6 |
| 6 | 宿主 binfmt（运行时状态） | aarch64 handler 换成 `tonistiigi/binfmt:qemu-v9.2.2`，并传 `DOCKER_MULTIARCH_CHECK=true` | Q-1 |
| 7 | `dockers/docker-base-resolute/Dockerfile.j2` | `--platform` 从 `ARG BASE` 挪进 `FROM`（只改 arm64 交叉分支） | G3-11 |
| 8 | `slave.mk:1018` | 交叉路径安装 `python3-libyang_*` 时加 `--force-depends` | G3-8 |

`rules/config.user`（gitignored）里另外有：隔离的 dpkg 缓存 `/var/cache/sonic/artifacts-arm64`、`SONIC_SLAVE_DOCKER_DRIVER = vfs`，以及 `DOCKER_BUILDER_USER_MOUNT` 的四个挂载。这些挂载只是因为探路跑在 linked worktree 里才需要：它的 `.git` 指向主仓库，而 slave 容器没挂主仓库；子模块的 gitfile 是相对路径，构建又把树挂在 `/sonic`。普通克隆完全不需要。探路还 unset 了 60 个探路私有子模块仓库里的 `core.worktree`。

闸门三的构建命令：

```bash
cd /home/sheldon-qi/sbi-arm64-probe
BLDENV=resolute CROSS_BLDENV=1 make TARGET_BOOTLOADER=grub \
  SONIC_BUILD_VARS="-k MIRROR_URLS=http://archive.ubuntu.com/ubuntu/ MIRROR_SECURITY_URLS=http://archive.ubuntu.com/ubuntu/" \
  DOCKER_MULTIARCH_CHECK=true target/sonic-vs.bin
```

`SONIC_BUILD_VARS` 是进入容器内那层 make 的唯一通道：`Makefile:15` 把它并进 `SONIC_OVERRIDE_BUILD_VARS`，`Makefile.work:673` 把后者拼到容器内的命令行尾部。`MIRROR_URLS` 走这条路而不写进 `config.user`，是为了不让它进入 slave 镜像按内容计算的哈希标签，避免 slave 重建。

日志在探路工作树的 `probe-logs/` 下（各闸门日志、进度账本、`dpkg-checkbuilddeps` 输出、qemu 压测脚本）；逐包日志在 `target/` 下。

探路顺带在主仓库发现两件事，与探路本身无关：

- 15 个子模块的 `.gitmodules` 指向 `canonical`，而 `.git/config` 里缓存的 `submodule.<name>.url` 仍指向 `sonic-net`。任何新建的 worktree 或克隆初始化子模块都会失败（sonic-gnmi：`not our ref`）。修法是 `git submodule sync --recursive`，尚未执行。
- 这台机器的 `find` 是 `bfs`，不认 `-newermt '-2 hours'`；计划里的污染检查要改用 ISO 时间。
