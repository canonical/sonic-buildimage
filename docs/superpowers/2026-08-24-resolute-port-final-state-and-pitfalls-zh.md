# 把 SONiC 202605 搬到 Ubuntu 26.04：最终状态，和路上踩的坑

最终状态取自 `202605_resolute_sheldon` 的 `648c8121aa`（2026-08-27 核对），对照基线是 `ba3fb8d5f5`（三条分支与 `sonic-net/202605` 的共同 merge-base）。

有一处要分清：**最后一次完整从零重建是在 `2957b9e3fd` 上做的**（2026-08-23），那之后 `_sheldon` 又前进了 9 个提交到 `648c8121aa`，这 9 个提交**没有经过完整重建验证**。有实质影响的几笔（registry 与 test-skip 上移、FIPS 默认关、flashrom 回退源构建、基础系统镜像源清理）在下面正文里都有交代；另外三笔是卫生性改动——两次 `sonic-utilities` gitlink bump 修 py3.14 的测试和 CLI 插件，以及从 slave 里删掉重复的 `libpam0g-dev`。

文里所有路径和行号都指**构建仓库** `~/sonic-buildimage-resolute` 在那个 commit 上的状态。文档仓库（`~/sonic-buildimage`，分支 `202605_resolute_doc`）里同名文件是上游版本，行号对不上，别在那边按行号找。

---

## 1. 现状

213 个文件，`+2699 / −823`，190 个提交。

2026-08-23 做过一次真正意义上的从零重建，`2957b9e3fd` 这棵树原封不动跑通两个平台，构建期间没有临时改一行代码、没压 job 数、没塞环境变量绕过任何东西。产物是 `target/sonic-vs.bin`（2.5 GB，16:28）和 `target/sonic-broadcom.bin`（2.1 GB，17:38）。

有一处得先交代清楚，否则「跑通」会被读成比实际更强的结论：`BUILD_SKIP_TEST = y`，`slave.mk` 会据此跳过多类包测试。所以「构建期间没塞环境变量绕过任何东西」字面为真，但**测试是被配置跳掉的**，不是全绿通过。

这个设置的位置刚变过。08-23 那轮它在 `rules/config.user` 里（只有 `_sheldon` 带这个文件），`648c8121aa` 把它挪进了受版本控制的 `rules/config`。命令行传 `BUILD_SKIP_TEST=n` 仍然能覆盖。

但**别把它当成所有分支的现状**。这套终态配置目前只在 `_sheldon` 和完整的正式栈 `_real` 上：

```
_mech      DEFAULT_CONTAINER_REGISTRY ?= publicmirror.azurecr.io   INCLUDE_FIPS ?= y   BUILD_SKIP_TEST ?= n
_real      DEFAULT_CONTAINER_REGISTRY =                            INCLUDE_FIPS ?= n   BUILD_SKIP_TEST = y
_sheldon   同 _real
生产分支    同 _mech（还在基线）
```

所以拿 `_mech` 单独构建仍会撞上 registry 那个报错、仍会开 FIPS、仍会跑测试。`_mech` 本来就只是可审阅性的第一层，不是能独立构建的状态。

「从零」的准确含义是**把缓存目录和 `fsroot*` 清空**，不是关掉缓存机制：`rules/config.user` 里 `SONIC_DPKG_CACHE_METHOD` 仍是 `rwcache`（指向 `/var/cache/sonic/artifacts`），ccache 和 docker 层缓存也都开着，只是它们当时是空的，所以每个 deb 都真的重编了一遍。清空的顺序有讲究：`fsroot*` 是 root 属主，得先 `sudo rm` 掉再 `git clean`，否则 clean 会因权限失败。这跟 4.3 里说的 `SONIC_DPKG_CACHE_METHOD=none` 是两件事——后者是在**不清缓存**的前提下绕过它，用来排除「拿回了一个旧 deb」这种怀疑。

镜像里 `os-release` 是 Ubuntu 26.04，内核是 Launchpad 上的 `linux-sonic 7.0.0-1002-sonic`。broadcom 那个装到 Dell S5232F（TD3 / XGS）上跑过：BGP v4 和 v6 都 Established，ASIC_DB 里 215 条路由，端到端通。

改动落在七层，规模很不均匀：`slave.mk` 和 `rules/` 那一层最大，目标 rootfs 那层其实只有几处。

---

## 2. Ubuntu 和 Debian 到底差在哪

刚开始我们以为这是个改 `FROM` 的活。实际卡住我们的东西可以归成五类，其中只有一类是"版本太新"。

**结构性的差异**最麻烦，因为它们不报版本错，只是行为不一样。Ubuntu 把 grub2 拆成 `src:grub2` 和 `src:grub2-unsigned` 两个源码包，`grub-efi-amd64-bin` 出自后者；内核的 modules 是独立的 `linux-modules` deb，而 Debian 打进了 image；`resolvconf` 这个包在 Ubuntu 归档里根本不存在，是 `systemd-resolved` 声明 `Provides/Replaces/Conflicts` 把名字占了；`rsyslog` 和 `hostname` 带 enforce 的 AppArmor profile，Debian 不带。最后这两条一直潜伏到部署上真机才炸出来。

**工具链太新**是最容易预料的一类，也确实最多：GCC 15 默认 C23、Python 3.14 全面执行 PEP 668、cmake 4.x、boost 默认 1.90、doxygen 1.14+、SWIG 4.4。但这一类有个反直觉的地方：不是版本越新越好。boost 我们按 1.88 适配了整整一轮，最后退回 1.83，因为 1.83 才是 trixie 和 bookworm 的默认版本，对齐它子模块里那些 `io_service` 代码才继续能编；1.90 走 header-only 会把迁移面拉得更大。

**Linux 7.0 的内核 API 漂移**只砸在 broadcom 那一层，但砸得很实：`timer` API、`bin_attribute` 的读写回调变成 const、`MODULE_IMPORT_NS` 改成字符串形式、kbuild 的 arch 树布局、objtool、`-fms-extensions`、`i2c_register_spd` 的守卫、`device_find_child`、`GPIOF_*`、`EXPORT_SYMBOL_NS_GPL`，十几类。

**上游把 distro 代号写死成字面量**，这类改动量大但都不难：leaf Dockerfile 的 `ARG BASE` 里是 `trixie` 三个字母，`slave.mk` 里是 per-distro 的容器集合，FIPS 的 makefile 里没有 resolute 的块，apt 源生成器只认 Debian 的组件布局。

**dpkg 和 debhelper 变严**：dpkg 1.23 严格解析 `Maintainer` 字段和 changelog trailer，一堆包的非标准写法过不去；debhelper 把 dbgsym 产成 `.ddeb` 而 SONiC 全流程按 `.deb` 找文件。

---

## 3. 七层

### 3.1 slave 镜像和构建入口

`BLDENV=resolute` 现在是默认的构建环境。`Makefile:9` 加了 `NORESOLUTE ?= 0`，`Makefile:43-44` 据此设 `BUILD_RESOLUTE=1`，`Makefile:70-74` 和 `Makefile:121` 把 `BLDENV=resolute` 递归传下去；`Makefile.work:132-133` 再把它翻成 `SLAVE_DIR = sonic-slave-resolute`。

`sonic-slave-resolute/` 下受版本控制的只有五个文件：862 行的 `Dockerfile.j2`、30 行的 `Dockerfile.user.j2`，加上三个小文件：`buildflags.conf`、`docker.sources`、`pip.conf`。目录里其它东西（`Dockerfile`、各种 `.log`、`files/`、`vcache/`）都是构建产物，不在库里。

`buildflags.conf` 只有一行有效内容，但它是整个 GCC 15 问题的总闸：

```
# 文件第 4 行，实际是一整行，这里为排版折行显示
APPEND CFLAGS -std=gnu17 -Wno-error=incompatible-pointer-types
              -Wno-error=int-conversion -Wno-error=discarded-qualifiers
```

SONiC 里 K&R 风格的函数原型很多，C23 直接拒；另外几个 warning 在 GCC 15 里被提升成 error。这一行把所有走 `dpkg-buildpackage` 的构建拉回 gnu17。这东西一开始是用内联 `sed` 往 Dockerfile 里塞的，`8f4921cb8d` 改成了静态文件。内联 sed 不幂等，静态文件能 review 能 diff。

`pip.conf` 只有 `[global]` 一节、下面一句 `break-system-packages = true`。放成全局配置而不是逐条命令加 flag，是为了让继承这个 base 的所有容器自动带上。有一个例外：`docker-dash-engine` 的 base 是外部的 p4lang 镜像，不继承我们的 `pip.conf`，只能在它自己的 Dockerfile 里显式写。

`docker.sources` 是 deb822 格式，指向 `download.docker.com/linux/ubuntu`。docker-ce 的 Ubuntu 池和 Debian 池是分开的，版本串后缀也从 `~debian.13~` 变成了 `~ubuntu.26.04~`。

然后是那个曾经最容易咬人的 registry 问题。`rules/config` 里 `DEFAULT_CONTAINER_REGISTRY` 的上游默认值是 `publicmirror.azurecr.io`，`Makefile.work:157-158` 在它非空时给它补个尾斜杠当前缀。于是 slave 的 `FROM ubuntu:resolute` 变成 `FROM publicmirror.azurecr.io/ubuntu:resolute`，构建挂在：

```
ERROR: failed to solve: publicmirror.azurecr.io/ubuntu:resolute: not found
```

那个内部镜像站镜的是 Debian，实测查 `ubuntu:resolute` 返回 `no such manifest`，而 `docker.io/ubuntu:resolute` 是存在的。

这条**曾经**是个硬依赖，而且只有 `_sheldon` 上的 `rules/config.user` 把它置空了，所以有同事在正式分支上构建就撞上了。`648c8121aa` 已经把它移进受版本控制的 `rules/config:366`（`DEFAULT_CONTAINER_REGISTRY =`，直接空值），所以在 `_sheldon` 和 `_real` 上不需要再抄任何东西；`_mech` 和生产分支还是老默认值（对照表见第 1 章）。同一个提交也把 `BUILD_SKIP_TEST = y` 放到了 `rules/config:404`。

顺带一句：`rules/config` 是这次才第一次进入 diff 的。在此之前整套移植一行都没碰过它，全部靠 `config.user` 覆盖——这也是为什么正式分支上会缺东西。

留个记录，因为这个坑还会以别的形式出现：当时的绕法是从 `_sheldon` 抄一份 `config.user` 过来，而那条建议本身有个顺序陷阱。`make reset` 跑的是 `git clean -xfdf`（`Makefile.work:767`），`-x` 会连被忽略的文件一起删。`_sheldon` 上这个文件是强制加进版本控制的，`clean` 动不了；抄到正式分支上它只是个 untracked + ignored 的副本，**reset 会把它删掉**。凡是靠"往 ignored 路径放一份本机配置"来解决的问题，都得先想清楚它活不过 `make reset`。

`rules/config.user` 现在还在 `_sheldon` 上，但里面剩下的**有效**设置都是本机相关的东西：`PLATFORM ?= vs`、`SONIC_DPKG_CACHE_METHOD = rwcache`、`SONIC_DPKG_CACHE_SOURCE`、`SONIC_VERSION_CACHE_METHOD = none`、ccache 和 docker 层缓存开关。抄不抄都不影响构建能否起来，抄的话注意 `SONIC_DPKG_CACHE_SOURCE` 指的目录得自己建好给权限。

里面现在有三行是纯粹的空操作，值得单独说，因为它解释了 `?=` 在这套构建系统里为什么容易骗人：`Makefile.work` 先 `include rules/config` 再 `-include rules/config.user`，所以 config.user 里任何跟 `rules/config` 同名的赋值都赶不上趟。`INCLUDE_FIPS ?= y` 拦不住 `rules/config:381` 已经定下的 `?= n`（见 3.5）；`DEFAULT_CONTAINER_REGISTRY =` 和 `BUILD_SKIP_TEST = y` 则是跟 `rules/config:366`、`:404` 重复——这两行是 `648c8121aa` 把设置上移之后留下的。`PLATFORM ?= vs` 反过来是真生效的，因为 `rules/config` 里没定义它；不过还是推荐命令行传 `make PLATFORM=broadcom`，别让本机文件决定构建目标。

apt 源生成那边，`scripts/build_mirror_config.sh` 和 `files/apt/sources.list.j2` 加了 Ubuntu 的组件布局（`main restricted universe multiverse`，以及把 `-updates`、`-security` 当独立 suite），Debian 那套 `main contrib non-free` 用不上。

### 3.2 构建图

这层最大，但目标其实一句话：**在只支持 resolute 的前提下，把 diff 压到最小。**

有个前提要说清楚，否则后面很多取舍看不懂：我们**已经不再要求 trixie 那套还能构建通过**。trixie 的变体之所以原封不动，不是为了让它继续可用，而是动它只会撑大 diff、换不来任何东西。同理，凡是不打包进部署镜像的内容一律用原版——目前没有任何功能性差异，改了纯属噪声。

这条原则解释了后面几处看着像"没清理干净"的东西：grub2 那两个 `.patch` 文件还躺在 `src/grub2/patch/`（3.3）、`mpdecimal` 三个文件都在只是注册行被注释掉（3.3）、`src/libnl3/Makefile` 是 online-deb 化之后的死代码（3.3）、`rules/iproute2.mk` 整段被 `ifeq ($(BLDENV),trixie)` 圈着没人碰（4.4）。它们不是遗漏，是清理本身不划算。

具体做法因此是复制一份改名，而不是就地改 trixie——后者会在每个碰过的文件上留下 diff。

`slave.mk` 里有六组改动，只有路径定义和 `mkdir` 是纯加法，其余都是替换或删依赖：`51-53` 行加了 `RESOLUTE_DEBS_PATH` / `RESOLUTE_FILES_PATH` / `RESOLUTE_PHONY_PATH`，`143-145` 行在 `configure` 目标里 `mkdir -p` 它们；`76` 行 `IMAGE_DISTRO := resolute`；`81` 行的 `$(filter ...)` 列表里加上 resolute；`1015` 行给 platform-modules 的 deb 安装加 `--force-depends`（它们依赖的内核模块在那个时刻还没装上，顺序检查过不去，但依赖后面会被满足，`1014` 是解释这件事的注释）；`1500` 起的 RFS 前置依赖和 `1570` 起的 installer 前置依赖都改成逐个列出拆分后的 grub2 debs，并且把 `LINUX_KBUILD` 整条删掉，因为 Ubuntu 的 `linux-sonic` 不出 kbuild deb。

`IMAGES` 那块没有 resolute 专属分支，这是评审明确要求的形态。resolute 走原有的 `else` 臂，靠 filter-out 把所有旧 distro 的容器集合排掉，resolute 的容器天然落在"默认集合"里：

```make
DOCKER_IMAGES = $(filter-out $(SONIC_JESSIE_DOCKERS) $(SONIC_STRETCH_DOCKERS) \
    $(SONIC_BUSTER_DOCKERS) $(SONIC_BULLSEYE_DOCKERS) $(SONIC_BOOKWORM_DOCKERS) \
    $(SONIC_TRIXIE_DOCKERS),$(SONIC_DOCKER_IMAGES))
```

这一句能成立，靠的是 37 个 `rules/docker-*.mk` 和平台 mk 里做的另一半工作。每个文件都改了两处，第二处才是承重的。拿 `rules/docker-lldp.mk` 举例：

```diff
-$(DOCKER_LLDP)_LOAD_DOCKERS += $(DOCKER_CONFIG_ENGINE_TRIXIE)
+$(DOCKER_LLDP)_LOAD_DOCKERS += $(DOCKER_CONFIG_ENGINE_RESOLUTE)
 ...
-SONIC_TRIXIE_DOCKERS += $(DOCKER_LLDP)
-SONIC_TRIXIE_DBG_DOCKERS += $(DOCKER_LLDP_DBG)
```

上半截是改基座引用（`DOCKER_{CONFIG_ENGINE,BASE,SWSS_LAYER}_TRIXIE` → `…_RESOLUTE`，`rules/` 和 `platform/` 下一共 140 个 `+` 行提到这三个基座变量（其中 3 行是变量自身的定义，137 行是引用），落在 `_LOAD_DOCKERS`、`_DBG_DEPENDS`、`_DBG_IMAGE_PACKAGES` 上的是 108 行）；下半截是把这个容器从 trixie 的注册表里摘出去（`SONIC_TRIXIE_DOCKERS` 和 `SONIC_TRIXIE_DBG_DOCKERS` 各 37 处删除）。

顺序反了后果很重。评审的时候有人提了个 suggestion，说 `slave.mk` 里直接加 `filter-out $(SONIC_TRIXIE_DOCKERS)` 就行。那会儿 `SONIC_TRIXIE_DOCKERS` 里还装着几乎所有 resolute 容器，照那个 suggestion 点一下 "Commit suggestion"，整个镜像的容器会被全部过滤掉。得先摘注册，再加 filter。

摘完之后 `SONIC_TRIXIE_DOCKERS` 里还剩 18 个普通注册加 5 个 debug 注册：trixie 自己的 base 链（`DOCKER_BASE_TRIXIE`、`DOCKER_CONFIG_ENGINE_TRIXIE`、`DOCKER_SWSS_LAYER_TRIXIE`）、syncd 和 gbsyncd 的基座模板，以及一堆 rpc / saiserver / PDE 变体。它跟 3.6 从 broadcom 裁掉的那批**有明显重叠但不是同一个集合**——这里还留着 Marvell Prestera、Marvell Teralynx、Mellanox 的 rpc/saiserver，那些跟 broadcom 无关。两边真正的共同点是：都没在 resolute 上验证过。

resolute 命名的 base 链是三件套，每个都有 `.mk`、`.dep` 和 `dockers/` 目录：`docker-base-resolute`（`ARG BASE={{ prefix }}ubuntu:resolute`）、`docker-config-engine-resolute`、`docker-swss-layer-resolute`。`ARG BASE` 指向这三种变体的 `.j2` 有 38 个（36 个是 leaf，另 2 个是 base 链内部的 config-engine 和 swss-layer）。这个数字不是「改了多少个 `.j2`」：区间内一共动了 51 个 `.j2`，其余那些改的是别的东西。

数这个数字有个陷阱：直接 `grep -rl 'ARG BASE.*resolute' dockers/ platform/` 会得到 71，因为 `dockers/*/Dockerfile` 是渲染产物也在磁盘上。要用 `git grep` 限定到 `.j2`。

平台侧新增了 `platform/template/docker-syncd-resolute.mk` 和 `docker-gbsyncd-resolute.mk`。

这层还有个不报错的坑：从 trixie 复制变体的时候，`.j2` 文件里 `docker_*_trixie_*` 这类**变量名**也得一起改成 `_resolute_`。漏了不会报错，模板会渲染出空值，结果是生成的 Dockerfile 少几行。

### 3.3 包从哪来

采购方式发生变化的包，最后只有三种归宿（没变的那些不在此列，见本节末尾）。

**装 Ubuntu 归档里现成的 deb**（进 `SONIC_ONLINE_DEBS`，不再源构建）：grub2 全家（`GRUB2_COMMON` `GRUB_COMMON` `GRUB_EFI` `GRUB_PC_BIN` `GRUB_EFI_AMD64{,_BIN}` `GRUB_EFI_ARM64{,_BIN}`）、libnl3 全家、内核四件套（`LINUX_HEADERS_COMMON` `LINUX_IMAGE` `LINUX_MODULES` `LINUX_HEADERS`）、`makedumpfile`、`rasdaemon`、`sedutil`。

**`dget` 拉 Ubuntu 源码包、打 SONiC 补丁、再构建**（保留源构建，只把上游从 Debian 换成 Ubuntu）：`bash`、`kdump-tools`、`libteam`、`libyang3`、`lldpd`、`lm-sensors`、`monit`、`openssh`、`socat`。

有三个包容易被顺手归进这一类，实际都不是。`isc-dhcp` 虽然也做了 resolute 构建适配，但它的 `src/isc-dhcp/Makefile:13` 至今还是 `dget -u http://deb.debian.org/...`，源仍在 Debian，只是回到了 SONiC 自己那一版（见 4.4）。`hsflowd`、`psample`、`libyang3-py3` 压根不走 dget：`hsflowd` 是 `git clone` sflow 上游再 checkout tag，`psample` 是 `git clone` Mellanox 的 libpsample，`libyang3-py3` 是 `git clone --depth 1 -b v3.1.0` 拉 CESNET 的 libyang-python。它们的 resolute 改动都只是构建修复。

**从构建图里摘出去**：只有 `mpdecimal` 一个，零消费者的孤儿。注意文件没删——`rules/mpdecimal.mk`、`rules/mpdecimal.dep`、`src/mpdecimal/Makefile` 都还在，只是 `rules/mpdecimal.mk:11` 那行 `SONIC_MAKE_DEBS += $(LIBMPDECIMAL)` 被注释掉了。保留文件的理由见 3.2 开头那条原则。

grub2 走 online deb 是折腾了好几趟才定的。源构建的话，因为 Ubuntu 拆包，得同时构建两个源码包才能拿到 `grub-efi-amd64-bin`；而且不必自己处理签名分发。

关键那一问是"SONiC 到底给 grub 打了什么补丁"。答案是两个，都不碰 grub 的功能代码：`adjust-build-rules-for-debian.patch` 只改 `debian/control` 和 `debian/rules`，是纯打包补丁，停掉源构建之后自然就不需要了；`large-uid-skip-cpio-ustar.patch` 只改 `tests/cpio_test.in`，作用是 uid 大于 2097151 时跳过 `cpio_ustar` 那个测试（ustar 格式表达不了这么大的 uid）。所以换成现成 deb 不丢任何功能。这两个 `.patch` 文件今天还留在 `src/grub2/patch/` 里没删，理由同 3.2 开头那条原则。

有一点别误读：我们取的 `grub-efi-amd64{,-bin}` 来自 `src:grub2-unsigned`（见 `rules/grub2.mk:35-38`），不是 Ubuntu 的签名包本身；签名是另一条 post-install 流程的事（`rules/grub2.mk:5-6` 有说明）。中间在 2.06 和 2.14 之间来回换了两趟，2.06 撞 C23 的 `bool`/`false` 关键字冲突，2.14 撞 overlayfs 不许目录硬链接，最后干脆整个源构建都不要了。

libnl3 值得细看一层。SONiC 自建它的唯一实质理由是一个符号名：`rtnl_route_get_nh_id`，上游 3.12 里叫 `nhid`。逐行核过之后结论是上游 3.12 是**超集**：不只是等价，它还多了 `route_compare()` 里的 `_DIFF(ROUTE_ATTR_NHID,…)` 和属性名表里的对应项。真正需要做的只是在 swss 侧改两行名字。当时就有人指出"改 swss 源码不就得了，可以省一个包的构建"，这话是对的。

内核换成从 Launchpad 直接取，有两个细节值得记：一是必须用 `ppa.launchpadcontent.net/.../pool/` 直连，`+files` 那种 URL 会 302 到 `launchpadlibrarian.net`，那个域名在构建环境里不可达；二是 Ubuntu 的 ABI 串**不带 arch**（Debian 是 `-amd64`），所以 `rules/linux-kernel.mk` 里 `KVERSION` 直接等于 `KVERSION_SHORT`：

```make
KERNEL_VERSION   = 7.0.0
KERNEL_ABISUFFIX = -1002
KERNEL_PKGVERSION = 7.0.0-1002.2
KVERSION ?= $(KVERSION_SHORT)
KERNEL_PPA_URL = https://ppa.launchpadcontent.net/canonical-kernel-team/bootstrap/ubuntu/pool/main/l/linux-sonic
```

`dget` 后面那个 `-u` 不是偷懒。Ubuntu slave 上 `.dsc` 的签名者是个人 key，不在任何可用的 keyring 里，装了 `debian-keyring` 也验不了。上面列的那批 Ubuntu 源构建包全带 `-u`；全仓 `src/**/Makefile` 里 19 处 `dget` 只有 `src/libnl3/Makefile:24` 不带（`git grep -nE '^[[:space:]]*dget' -- 'src/**/Makefile'`），而那个文件已经是 online-deb 化之后留下的死代码。

有两个机制性的东西这层要盯：

`.dep` 文件里的 `SPATH` 不能空。依赖哈希是这么串起来的：各个 `rules/*.dep` 自己用 `git ls-files $(SPATH)` 展开文件清单，`Makefile.cache:650` 再对展开结果跑 `git hash-object`（`655` 只是把这套规则套到各个 deb 集合上）。`.mk` 不提供 `SPATH` 的时候，`git ls-files` 会列出整个仓库，然后撞上 `device/` 里的符号链接和 gitlink，`hash-object` 直接挂。`grub2.dep` 和 `libnl3.dep` 因此加了空 SPATH 守卫。同一类事故还犯过第二次：de-fork `radius.mk` 的时候漏了它的 `.dep`，结果 `src/radius/pam` 的改动不再让缓存失效。`8c7b3b2aaf` 恢复了上游写法。

`SONIC_ONLINE_DEBS` 的安装顺序得自己排。它对每个 deb 逐个跑 `dpkg -i`，不写 `_DEPENDS` 就会出现 `-dev` 包先于运行库安装，然后 dpkg abort。libnl3 就是这么撞上的。

至于 dbgsym：Ubuntu 的 debhelper 把 `DBGSYM_PACKAGE_TYPE` 硬编码成 `'ddeb'`。最终形态是在 slave 的 Dockerfile 里单点 patch `Dh_Lib.pm` 把它改回 `.deb`。这个 patch 本身有点脏（`grep -q ddeb && sed`，不幂等），能成立只因为 slave 总是从 fresh base 重建。在此之前散落在各包里的 `mv …-dbgsym_*.deb` band-aid 全撤了，那些东西还破坏过 `PIPESTATUS`。

### 3.4 子模块

`.gitmodules` 里 16 个 submodule 的 url 从 `sonic-net/*` 改到 `canonical/*`，统一用 https 而不是 ssh。`platform/broadcom/saibcm-modules` 额外把 `branch` 从 `sdk-6.5.35-xgs` 改成 `202605_resolute`。gitlink 有变化的恰好是同一批 16 个：

```
platform/broadcom/saibcm-modules   platform/vpp
src/dhcprelay                      src/sonic-bmp
src/sonic-dash-api                 src/sonic-dash-ha
src/sonic-gnmi                     src/sonic-mgmt-common
src/sonic-mgmt-framework           src/sonic-sairedis
src/sonic-snmpagent                src/sonic-stp
src/sonic-swss                     src/sonic-swss-common
src/sonic-utilities                src/wpasupplicant/sonic-wpa-supplicant
```

`saibcm-modules` 上是八个编号的适配 **commit**（不是 `.patch` 文件，机制见 3.6），从 `0001-resolute-kernel-abi` 到 `0008-resolute-changelog-timestamps`，中间六个是 Linux 7.0 的适配；gitlink 相对 `b9b38791bc` 一共 9 个 commit，第九个是注释清理。

`src/sonic-frr/frr` 是个例外：gitlink 锁在上游 tag（`frr-10.5.4`），构建时用 `stg` 打 85 个补丁。工作树里这个 gitlink 显示 dirty 是正常的，makefile 不消费那个指针。

这层的坑密度是全项目最高的。最危险的那几条会静默丢改动，另外几条会响——但响的地方往往不是真因。

最贵的那条是：子模块分支不跟着超仓一起 rebase，上游修复会无声消失。健康的状态是"子模块分支 = 上游 + 我们的补丁，严格可 ff"。一旦分叉，超仓 rebase 撞 gitlink 冲突的时候我们必须保自己的 commit，上游那边的修复就被挡在外面，而且没有任何机制会报告这件事。"每一个 SAI 计数器都读零"就是这么来的。`sonic-sairedis` 缺了上游一个 commit，那个 commit 的标题直接写着让计数器在 Broadcom 平台上正常工作。发现之后写了 `scripts/submodule-ff-audit.sh`，每次同步上游跑一遍。`sonic-utilities` 当时也处在同样的状态，已经丢了两个真修复。

其余几条：

子模块的本地分支名不等于远端分支名。本地叫 `resolute` 或 `202605`，只有远端叫 `202605_resolute`。

`.gitmodules` 里 canonical 的 url 必须是 https。用 ssh 会让没有 key 的环境直接拉不下来。而且改这个文件要**就地改**。用 append 方式追加新 section 的话，漏掉 `path =` 的那个是孤儿，原来的 section 仍然生效，看着改了实际没改。

`--reference` 克隆会带来 object store 损坏。alternates 一丢，`mgmt-framework`、`swss`、`sairedis` 就缺 blob。修法是 deinit、`rm -rf .git/modules/<name>`、从 origin 重新 clone；注意子模块的 git dir 可能就是 `.git/modules/<name>`，没有 `src/` 前缀。另外 alternates 在 docker build 的容器里没挂载，会报 `unable to normalize alternate object path`，然后取 commit label 那步 fatal 128。这个非致命，SONiC 那步本来就是 best-effort，代价只是镜像少个 git label。

超仓 rebase 会被 untracked 的构建残留打断，而且失败之后 `--continue` 会**假报冲突**（`git ls-files -u` 其实是空的）。可靠的做法是在一个干净的临时 worktree 里 rebase，完成后 `reset --hard` 把分支指过去，主工作树的残留原样留着。

`AGENTS.md` 里写了几条规则，其中最反直觉的是 gitlink 可达性有**三种**状态（上游 commit + 上游 url / Canonical commit 已推到 canonical / Canonical commit 根本没推），而**光看 url 判断不出来**是哪一种。还有一条硬规则：子模块的 Canonical commit 只推到 `canonical/<sub>:202605_resolute`，绝不推 `sonic-net`。

### 3.5 目标 rootfs

这层其实很薄，`build_debian.sh` 里几处版本串和包名，加上 FIPS 的一个决定。

```diff
-DOCKER_VERSION=5:28.5.2-1~debian.13~$IMAGE_DISTRO
-CONTAINERD_IO_VERSION=1.7.28-2~debian.13~$IMAGE_DISTRO
-LINUX_KERNEL_VERSION=6.12.41+deb13
+DOCKER_VERSION=5:29.6.1-1~ubuntu.26.04~$IMAGE_DISTRO
+CONTAINERD_IO_VERSION=2.2.5-1~ubuntu.26.04~$IMAGE_DISTRO
+LINUX_KERNEL_VERSION=7.0.0-1002-sonic
```

装内核那步多带一个 deb，`linux-modules-*` 得和 `linux-image-*` 一起装。docker 的 GPG key 和 apt 源从 `linux/debian` 改到 `linux/ubuntu`。固件包 `firmware-linux-nonfree` 和 `firmware-intel-misc` 在 Ubuntu 不存在，换成 `linux-firmware`。一开始那行后面挂着 `|| true`（理由是 vs 不需要真固件），`484cf5330b` 去掉了——`linux-firmware` 在 resolute 归档里确实存在，装不上就该报错，而不是悄悄跳过。还删掉了 `resolvconf` 这行依赖，为什么删见 3.7。

**FIPS 在 resolute 上是关的**，而且是硬关。`rules/config:381` 现在写 `INCLUDE_FIPS ?= n`，`rules/sonic-fips.mk` 里还加了一道：

```make
ifeq ($(BLDENV) $(INCLUDE_FIPS), resolute y)
$(error INCLUDE_FIPS=y is not supported on resolute)
endif
```

这是 `d314b3b91f` 定的，之前走的是另一条路，那条路值得记下来因为它看起来很合理：FIPS 镜像站上没有 `fips/resolute/` 这棵树，所以最初的做法是复用 trixie 的二进制（同 t64 ABI），靠一个 `FIPS_DOWNLOAD_BLDENV = trixie` 把下载路径指回 `fips/trixie/`。放弃它的原因不是 ABI，是**版本**：trixie 那批 FIPS 二进制里有几个比 resolute 自带的还旧，最刺眼的是 python3.13/libpython3.13——而 resolute 的 rootfs 里根本没有 3.13。既然 FIPS 开着从来没验证过，就干脆用 Ubuntu 自己的 openssl、openssh、python 和 golang。`sonic-fips.mk` 里那些 resolute 分支也一并撤了，现在只剩 trixie 的。

连带的一处：slave 里 golang 从跟着 `golang-go` 改成 pin `golang-1.24-go`，因为 resolute 上 `golang-go` 是 go 1.26。这条也让那段 Dockerfile 不再依赖 `FIPS_*` 变量——那些变量对 resolute 已经是未定义的。

`installer/default_platform.conf` 里是 ONIE installer 的 grub.cfg 内核路径。

`scripts/build_debian_base_system.sh` 那边最近清理过两轮。`943eae7337` 把 `if [ "$IMAGE_DISTRO" == "resolute" ]` 那类分支删了——既然只支持 resolute，debootstrap 的镜像源就无条件指 `archive.ubuntu.com/ubuntu`，apt-list 缓存路径同理，不用再按 distro 分岔。`d5f53658df` 把快照源从 `packages.trafficmanager.net/snapshot`（Debian 快照的镜像）换成 `snapshot.ubuntu.com`，因为前者不覆盖 resolute。这两条都是 3.2 那条原则的正面应用：一旦不再需要兼容 trixie，条件分支本身就是可以删掉的 diff。

### 3.6 broadcom（dell / XGS）

这层的第一个决定不是技术性的：把范围**主动收窄到 dell 和 XGS**。`platform/broadcom/rules.mk` 里注释掉的有 DNX/Jericho 和 legacy Tomahawk 的 SAI、nokia / arista / nexthop / accton / cel / supermicro / ufispace / micas 八家的 kmod（只留 dell）、rpc 和 saiserver 和 PDE 那些容器、以及 `one-aboot.mk`（Arista 的 Aboot 镜像，它还会通过 `DEPENDENT_MACHINE` 把已经删掉的机型再拉回来）。

理由是：只有 dell 平台在 Ubuntu 26.04 上被真机验证过。把没验过的厂商 kmod 留在构建图里，等于给每次内核升级都留一堆没人能测的代码要修。

内核 7.0 的适配分三种手法，按「源码归谁管」分：

**构建时拉取的外部源**（dget 或 clone 下来的）打 `.patch` overlay，因为那棵树每次构建都重新出现，改了也留不住。

**我们自己控制的子模块**直接在子模块分支上提交，再 bump 父仓库的 gitlink。`saibcm-modules` 走的是这条：它上面那八个编号项是 **git commit**，不是 `.patch` 文件——`git ls-files '*.patch'` 在那个子模块里返回 0 个，`b9b38791bc..d4519fdeee` 直接改的是 `debian/rules`、`make/Makefile.linux-kmodule`、几个 `lkm.h` 之类的源码和打包文件。

**在树的源码**直接改源码，不用 sed 或 awk：`platform/broadcom/sonic-platform-modules-dell/**/*.c`（`mc24lc64t.c` 四份、`cls-i2c-mux-pca954x.c`、`fpga_gpio.c`）、`sswsyncd/debian/rules`、`platform/pddf/i2c/**`。这跟上游习惯一致：上游那 11 个 `.patch`/`series` 全在 `src/` 下的拉取型包里，在树源码那边一个都没有。

这层有几个坑：

`BUILD_SKIP_TEST` 不覆盖 debhelper 的 test 阶段，想跳过 vendor 的测试得在它自己的 `debian/rules` 里显式 `override_dh_auto_test`。

`opennsl-dnx` 的头文件 symlink 不幂等：`debian/rules` 用 `[ ! -e ]` 守卫，而 `-e` 对**悬空 symlink 返回假**，于是那条 `ln` 照跑，撞上已存在的链接报 `ln: Already exists`。当时的修法是 `ln -sfn`，扩进一个 overlay patch。不过这是**已经撤销的中间态**：`c57035d7e8` 收窄到 dell/XGS 时把整套 DNX overlay 删了，最终树里那个 patch 不存在。留在这里是因为这类不幂等守卫的坑会换个地方再出现。

`sdklt` 的 `clean` 目标有 `-j16` 并行竞态，竞态对象是 `sdklt/linux/*/generated/` 那些生成目录，`dpkg-buildpackage -j16` 递归下去可能挂住；而 `debian/rules clean` 在从零构建时也会执行。但这个竞态是间歇性的。全新干净的树上 `clean` 目标照样执行，只是那些生成目录还不存在，无从竞争；命中 dpkg 缓存的时候则压根不进 vendor 的 `clean`。08-23 那轮从零重建没复现。准确的说法是"本轮未复现"，不是"已修复"：树里确实既没有 `-j1` 也没有 `.NOTPARALLEL`，退路是命令行压 `SONIC_CONFIG_MAKE_JOBS=1`。

最后一条实用的：多变体构建的时候主 bin 先完成，`sonic-broadcom.bin` 有 `payload_sha1` 自检。它完成之后，依赖它的其它变体如果因为瞬时网络失败，不影响主 bin 的有效性。

### 3.7 运行时

这层的三条改动都是构建全绿、部署到真机才发现功能哑掉的东西，是整个项目里最难提前预料的一类，因为构建系统不给任何信号。（那次巡检一共查出四个缺陷，第四个是 SAI 计数器恒零，真因在子模块 gitlink 陈旧，所以归在 3.4。）

这个镜像上 SONiC 的事件框架是哑的，真因是 Ubuntu 的 `rsyslog` 带 enforce 的 AppArmor profile，Debian 不带。`omprog` 去调 `/usr/bin/rsyslog_plugin` 全部 EACCES，插件进程根本没起来，所以 `/etc/rsyslog.d/*_events.conf` 里的动作不可能产出任何事件。修法是加一个 profile 覆盖，`build_debian.sh` 把它拷到 `/etc/apparmor.d/local/`：

```
/usr/bin/rsyslog_plugin ix,
capability chown,
/etc/sonic/** r,
/var/run/redis/** r,
/usr/share/sonic/** r,
```

`ix` 让插件在同一个 profile 下执行；`capability chown` 是因为 rsyslog 要对自己创建的日志文件应用 `$FileOwner` 和 `$FileGroup`。

顺便说，同一类 AppArmor 坑不止这一个。`comm="hostname"` 在 `/var/lib/dhcp/dhclient.eth0.leases` 上被拒 `file_inherit` 和 `open`。Ubuntu 有个 enforce 的 `/etc/apparmor.d/hostname`，而官方 Debian 镜像那 107 个 profile 里根本没有这一个。以后碰到"某个 helper 无声失败"，先查 AppArmor。

交换机完全没有 DNS。这条的真因比"包没装"深了四层，值得完整写一遍：

Ubuntu 归档里没有真正的 `resolvconf` 包，`systemd-resolved` 声明了 `Provides/Replaces/Conflicts: resolvconf` 把这个名字占了。所以上游那行 `apt-get install resolvconf`（`ba3fb8d5f5:build_debian.sh:381`，最终树里已删）在 Ubuntu 上**成功了**，只是装到的是 resolved。这是第一层。

`/sbin/resolvconf` 于是成了 `resolvectl` 的兼容软链。它支持 `-a` 和 `-d`，但不支持 SONiC 用的 `--disable-updates`、`--enable-updates`、`-u`，也没有 `/run/resolvconf/interface`。这是第二层。

更根本的是第三层：`resolvectl(1)` 明确写了，它的 resolvconf 兼容模式**只在 `/etc/resolv.conf` 是指向 `/run/systemd/resolve/resolv.conf` 的符号链接时**才会更新那个文件，而 SONiC 把它保持成静态文件。所以就算前两层都糊过去，租约里的 DNS 服务器也永远到不了 glibc 的解析器。

第四层是功能性的：SONiC 的 `DNS_OPTIONS`（`search`、`ndots`、`timeout`）在 `resolved.conf` 里**没有任何等价物**，那个文件只有 `DNS=`、`Domains=`、`Cache=`、`ResolveUnicastSingleLabel=`。走 resolved-native 会静默丢掉这个功能。

所以结论是直接渲染 `/etc/resolv.conf`。新增的 `files/image_config/resolv-config/dhclient-enter-hook` 覆盖 `make_resolv_conf()`，自己拼 `search` 和 `nameserver` 行，链路本地地址补 `%interface` 作用域，并且用 `/run/sonic-resolv-static` 这个标记让静态 DNS 配置优先。配套地，`resolv-config.sh` 支持静态 DNS 配置被删除时清掉残留的 nameserver，`interfaces-config.sh` 里那几处 `resolvconf --*-updates` 调用一并清了。

这不是绕过 systemd-resolved。"应用自己写 `/etc/resolv.conf`" 是 resolved 官方支持的四种模式之一，resolved 会自动退成消费者。而且实测机器上 `nsswitch.conf` 是 `hosts: files dns`（没有 `resolve`），glibc 本来就直接走 nss-dns 读 `/etc/resolv.conf`，resolved 在查询路径上根本不参与。

`aaastatsd` 每次 timer 就崩。de-fork 到 Ubuntu 现成的 `libpam-radius-auth 3.0.0-1build1` 之后，它 inotify watch 的 `/etc/pam_radius_auth.d/statistics/` 目录不存在了。那个目录由 SONiC 自建的 `1.4.1-1` 的 `.list` 提供，Ubuntu 新版不再带。查下去发现更严重的问题：Debian 的 1.4.1 带四个 quilt 补丁（chap、peap-mschapv2、nas-ip-address、fix-blastradius），其中 `protocol=chap` 和 `protocol=mschapv2` 在 3.0.0 上会被静默忽略、退回 PAP，服务器要求 CHAP 或 MSCHAPv2 的时候直接认证失败。所以 de-fork 回退了（`d605df6b58`），`.dep` 文件补回来（`8c7b3b2aaf`）。

除这三条，还有 `database_config.json.j2` 里的 `DEV | default("")`（加了说明注释），以及 `src/sonic-eventd/rsyslog_plugin/timestamp_formatter.cpp` 和 `src/systemd-sonic-generator` 的编译适配。

有一条查了半天最后确认**不是**我们的问题：`dmesg.service` 会让 `show system-health sysready-status` 一直是红的。这个 unit 是 Ubuntu 独有，`Type=idle` 而且没有 `RemainAfterExit`，跑完几秒就变 inactive。无害，但等 sysready 的测试会超时。上游 sonic-net 的官方镜像同样是红的，所以这不是 resolute 引入的回归。

---

## 4. 坑

### 4.1 exit 0 骗人

最贵的一条是 frr。Jul 24 那版 deb 构建是成功的，exit 0，三个 deb 都在。部署到 dut02 之后 BGP 起不来，先查了半天配置。配置没问题，是 deb 里少了 `dplane_fpm_sonic.so`。

旧的 Makefile 用 dget+quilt 打补丁，那一行写的是：

```
QUILT_PATCHES=../patch quilt push -a || true
```

patch 0012 改的是 `zebra/subdir.am`。Ubuntu 的 FRR 源上这个 hunk 不匹配，quilt 失败，`|| true` 把失败吞了。`subdir.am` 没拿到模块规则，模块从头到尾没被编译过。

然后第二道网也漏了：`frr.install` 里那一行是个 glob，`dh_install` 默认不带 `--fail-missing`，匹配不到文件就静默跳过。于是 deb 照样打包成功，只是少一个 `.so`。

现在的 Makefile 走 stg，而且 `src/sonic-frr/Makefile` 带 `.SHELLFLAGS += -e`，补丁失败会直接中止构建。cache-off 重建之后模块出现了，部署上去 BGP v4/v6 都 Established，ASIC_DB 215 条路由端到端通。所以 exit 0 在 SONiC 构建里不构成任何保证，要验产物内容。

另外两个包是"构建成功但少东西"的同一种病，只是病灶不同。`lm-sensors` 的 `PROG_EXTRA=sensord` 是功能性的树外变量，丢掉它构建照样成功，只是 `sensord` 不存在，而 `docker-platform-monitor` 要它。`sensord` 这种少产物的问题靠 `dpkg -c` 对比包内容清单能抓到。`librrd-dev` 反过来，是 stock `debian/control` 漏声明的 Build-Depends，本地一直"能编"只因为 slave 镜像预装了它——这类问题 `dpkg -c` 抓不到，它只看产物不看输入依赖，只有在只装了声明依赖的干净环境里构建才会暴露。

还有一个今天还没咬人、但埋着的：slave 的 Dockerfile 里那个 vendor include 带 `ignore missing`，而 `files/sonic-slave-Dockerfile.vendor.j2` 在树里根本不存在。今天它没有消费者。但如果有人把 dbgsym 那个 patch 之类的东西挪进去，故障会表现成某个 src 包在 `mv …-dbgsym_*.deb` 上莫名失败，而没人会想到去查一个不存在的文件。

最后两条是构建图自己把东西吃掉。一个是容器被 `filter-out` 漏掉：改错 3.2 那套集合里的一个，某个容器就安静地不进镜像，而构建 exit 0。验法有两个都不用等部署，拿 `dockerfs.tar.gz` 里的 `repositories.json` 去对 `init_cfg` 的 FEATURE 表，或者对比被 enable 的容器 systemd 服务和实际烧进去的容器镜像；但别用查询 `slave.mk` 变量的办法验，在宿主机上解析 `slave.mk` 极慢，容易挂住。另一个是 gitlink 保旧导致上游修复静默丢，机制见 3.4——它是这一类里后果最重的，因为不只丢一次：只要分叉状态还在，之后每次上游修复都会被挡住。

### 4.2 报错指错了地方

bash 构建失败报 `Could not open bash.pdf`，看起来像文档构建或者某个补丁的问题。实际是**宿主机**的 AppArmor `gs` profile（enforce 状态）拒绝在构建目录里创建文件。修法在宿主机侧加 `local/gs` override，仓库里一行都不用改。这条曾经被误判成 fakeroot 的 "payload not recognized"。那个报错是真的，但它是次要的 IPC 噪声，不是原因。

slave 镜像里 `wget` 什么都没下载、后续步骤缺文件，像是网络问题。真因是开了 `SONIC_VERSION_CACHE`，slave Dockerfile 里的 wget 被静默跳过。所以 `config.user` 里固定 `SONIC_VERSION_CACHE_METHOD = none`。

redis 里显示"路由 0 条"，一度以为 fpmsyncd 或者 orchagent 没工作。真因是 ssh 引号转义让 `--scan --pattern` 的 glob 没展开，是**计数假象**。换 `keys` 干净查：APPL_DB 的 ROUTE_TABLE 有 209 条，ASIC_DB 的 ROUTE_ENTRY 有 215 条。同一个坑在端口计数上也出现过一次（`PORT:1`）。这条提醒的其实是：远程执行里带引号的查询，先在本地验一遍再信它的输出。

TD3 报 `CIH: LOAD FAILED`，上一轮归因成"platform-modules 1.8.1 太旧"，错了。真因是 `libsaibcm` 把 156 个 `/etc/bcm/flex/**/*.pkg` 登记成了 dpkg conffiles，而包升级不会自动清掉这些仍被当作 conffile 保留的旧文件。所以装 SAI 15.2 的时候旧的 `b870.6.4.1/` 目录原地留存，而 `config.bcm` 又显式指向它，新 SDK 就去加载了旧版本的 CANCUN。

`show ip …` 说 "No such command"、`show.plugins.*` 报连字符导入警告，两条都不是 resolute 回归。前者是 db 没就绪或者没有 minigraph；后者是上游的 bug，`import_module` 不接受连字符。另外查 vs 的 rootfs 要看 qcow2 第三分区里的 `image-*/fs.squashfs`，不是 `target/*.squashfs` 那个中间产物。找错文件会得出"文件被 squashfs 丢了"的错结论。

dut 上 flashrom 报 `No chipset found`，一度以为是我们丢了 Dell 的补丁。跟那个补丁无关：真因是内核的 `spi_intel.writeable=0`，描述符本身已经放行了。而且那个补丁靠的是 SMI 后门：往 0xB2 端口发命令让 Dell BIOS 的 SMM 代刷。至于这个包还有没有人用——本超仓里 `flashrom` 只出现在打包相关的位置（`rules/flashrom.*`、`src/flashrom/`、版本清单、`sonic_debian_extension.j2`），一个功能调用点都没有。（它现在又是源构建了，见 4.4；这不改变调用者的状况。）更早一次审计说 `sonic-platform-common` 和厂商平台仓库里的调用者都已经是 `return False` 空桩，那条本轮没有复核，别当定论。

PR 页面上出现 `device/arista` 这些无关文件的 diff，不是有人偷偷改了它们，是 GitHub 陈旧 merge base 造成的显示假象。诊断法是比对 PR 的 `base.sha` 和真实的 `merge-base`。这个必须主动跟 reviewer 说明，否则对方会把那些幽灵条目当成你这个分支真改过的东西。

### 4.3 只有从零构建才暴露

保留缓存的构建会把下面这些全部盖住。

这三个是 7 月那两轮从零构建逼出来的（修复的 author date 都是 2026-07-21），08-23 那次重建时它们已经在树里，那轮只是复验。KVM 那步的本机 `sudo` 会剥掉环境变量，`SONIC_USERNAME` 和 `PASSWD` 传不进 `scripts/build_kvm_image.sh`（它在第 140 行用这两个名字）。修法是显式 `sudo -E env VAR=val …`，`33862dc91c` 落地。注意 `build_image.sh:51` 现在已经是修好的样子，去那一行看不到这个 bug。`opennsl-dnx` 的头文件 symlink 不幂等（机制见 3.6）。`dash-engine` 撞 PEP 668，因为它的 base 是外部镜像、不继承我们的 `pip.conf`。

同一批里还有 `.dep` 空 `SPATH`（机制见 3.3），出自 07-23 那轮 online-deb 从零构建。

还有两条不是 bug 而是操作上的。想在不清缓存的前提下确认某个 deb 真的重编了，得临时传 `SONIC_DPKG_CACHE_METHOD=none`——`config.user` 里那个 `rwcache` 会直接把缓存里的 deb 还原出来（清零的正确姿势见第 1 章）。另外 `sdklt` 那个竞态在缓存命中时压根不进 vendor 的 `clean`，所以"这轮没挂"不等于"修好了"。

最后一个容易被误读的现象：跑一次 vs 会把 19 个 `.flags` 戳从 `broadcom` 改写成 `vs`，deb 本体和 log 都没动。拿 `.flags` 判断"这个 deb 是哪个平台构建的"会被误导。

### 4.4 走过又退回来的路

boost 按 1.88 适配了整整一轮，最后退回 1.83（`aae7dd2ae0`）。理由见第 2 章。

grub2 在 2.06 和 2.14 之间来回换了两趟，最后整个源构建都不要了。理由见 3.3。

dbgsym 试过三种办法：逐包 `mv` band-aid、`noautodbgsym`、`DEB_BUILD_OPTIONS=dbgsym`。全撤了（`001f038067`），换成单点 patch `Dh_Lib.pm`（`d5647e2ef2`）。

force-depends 一开始用 `_DEB_INSTALL_OPTS` 传，那是 sudo 选项位置的误用，`5c6c5909fc` 回退，最终落在 `slave.mk:1015`。

五个包 de-fork 之后又回到源构建，理由各不相同：`lldpd` 是补丁 0001 不能丢（下一节讲）；`libpam-radius-auth` 是四个 quilt 补丁加 PAM 选项（3.7 讲过）；`isc-dhcp` 回到 SONiC 的版本但保留了 resolute 的构建适配；`initramfs-tools` 回退 de-fork，但保留上游那两个独立补丁而不是合成一个；`flashrom` 退回 0.9.7 源构建（`e3f210bccd`），而这一个的理由跟其它四个不同——不是补丁不能丢，恰恰相反，那个 Denverton 补丁按 4.2 的分析已经没有活的调用者，退回的动机是**让 diff 归零**，也就是 3.2 那条原则。而且是字面意义上的归零：`rules/flashrom.mk` 和 `rules/flashrom.dep` 现在与基线逐字节一致，整个包从 diff 里消失了（这也是最终文件数从 214 降到 213 的原因之一，另一处是 `rules/config` 新进来）。回退后验过 `/usr/local/sbin/flashrom` 里有 `DENVERTON` 和 `DENVERTON SBASE` 符号，确认补丁 0002 是真编进去了而不是只应用上。

`iproute2` 常被算成第五个，其实不是同一件事。它相对基线**一个字节都没改**：`rules/iproute2.mk` 仍被 `ifeq ($(BLDENV),trixie)` 整段圈住，`src/iproute2/Makefile:11` 仍从 `deb.debian.org` dget。`e6067ede11` 撤掉的是我们中途给 resolute 加的那段源构建，撤完就还原成上游那个 trixie-gated 的原样——文件和 Debian 源都在，只是 resolute 不构建它。resolute 侧用的是 stock Ubuntu 的 apt 包，第 6 章那条挂起的 EVPN MH 补丁就是这么来的。

broadcom 收窄的时候裁过头一次：`platform/broadcom/rules.mk` 在 `INCLUDE_GBSYNCD` 下 include 的四个 gbsyncd 组件是必须保留的，`a133e5d573` 补回来。

py3.14 的 `pkgutil.get_loader` 被移除，一开始打了 sed 补丁兜底。上游 `sonic-utilities` 修好之后直接删掉（`6744948bc8`），改成 bump gitlink。

还有一笔是主动丢掉的：我们自己那个 `docker-dash-engine` 的 `--break-system-packages` + `pin ==1.4.0`。上游 #28587 恰好也加了 `--break-system-packages`（带旧 base 的回退），合并之后我们那笔成了空 commit，就整个丢掉了，不留"加个 pin 又去掉 pin"的噪声。那个文件现在和 `sonic-net/202605` 逐字节一致。

### 4.5 判断一个包能不能 de-fork

"上游发行版有同名的包"**不是**充分条件。这几条是踩过之后固化下来的。

得看补丁差量，以及 SONiC 实际用到的选项，光看包名会得出错误结论。Debian 的 `libpam-radius-auth` 1.4.1 带四个 quilt 补丁；`lldpd` 那个 `0001-return-error-when-port-does-not-exist` 决定了 `lldpcli` 的返回语义。没有它，`lldpcli` 在找不到端口的时候返回成功，`lldpmgrd` 就判定成功并把待办删掉，结果是那个端口的 LLDP port-id 和 description **永远不会被配置，而且零报错**。这就是 lldpd 回到源构建的原因（`6742869eb9`）。

注释会撒谎，而且是我们自己写错的。`rules/lldpd.mk` 和 `rules/flashrom.mk` 都曾经写着 "all SONiC patches upstreamed"，两句都是假的、都是本分支加上去的。两个包后来都退回了源构建（`6742869eb9` 和 `e3f210bccd`），假注释也随之消失，现在 `rules/lldpd.mk` 写的是准确说明（patch 0001 在 1.0.19 并未上游），`rules/flashrom.mk` 回到基线的 `# flashrom package`。

教训不在这两句注释被修掉，在于它们当初怎么写上去的：de-fork 的时候顺手写下"补丁都上游了"，而没有真的核对补丁内容。核补丁，不要信注释。

基线要看生产分支，不是 PR 分支。`canonical/202605_resolute` 上 `lldpd` 从来就是 Debian 1.0.16 源构建，de-fork 从没合进生产。所以真实的净增量是"Debian 1.0.16 源构建 → Ubuntu 1.0.19 源构建"，不是"从 online deb 改回源构建"。这条判断错过一次，差点写进 commit message。

`SONIC_MAKE_DEBS` 是构建方法的注册表，不是无条件构建清单。真正触发构建的是最终目标（`sonic-vs.bin`）→ docker 的 `_DEPENDS` 链 → 包依赖传递。没有消费者的包即使注册了也不会被 make 触发。这是判定 `mpdecimal` 是孤儿、可以从构建图里摘掉的依据（文件仍保留，见 3.3）。

de-fork 的 commit 不要把中间态和终态塞在一起。`07f2c3c116`、`10047cb0e0`、`84ea013156` 每个都把"改 src 走 Ubuntu dget"和"改用 online deb"合在同一个提交里。回退的时候就会留下一棵夹生的 `src/` 树。

### 4.6 仓库操作和评审

这一层最坑的是两个仓库的 cwd 陷阱。自动化跑命令时每条可能都从默认工作目录起，前一条的 `cd` 不一定还在，于是 cwd 静默回到 `~/sonic-buildimage`（文档仓库）。实际后果发生过两次：一次是整份 `MAKEFILE_LIST` 分析跑错了仓库，结论作废；更糟的一次是 `git commit --amend` 打到了文档仓库，把一个 docs commit 的 message 覆盖成了 lldpd 的文案。还有一次在错的仓库里执行了清理动作。

规则很简单：所有 git 写操作显式写 `git -C <repo>`，不要依赖前一条命令的 `cd`。

两个仓库也不许互相污染。`~/sonic-buildimage` 是上游加一个 `docs/`；`~/sonic-buildimage-resolute` 里绝无 `docs/`。这个约定乱过一次（`202605_resolute_doc_fix` 带进了开发内容），清理起来很费事。

diff 卫生这一块，下面几条是评审反复打回的：

文件末尾有没有换行要跟上游一致，`29dd3fa2fa` 专门做过一轮"恢复上游的 EOF 字节"。

不要为了让补丁的行号好看而重新生成补丁。原话是："换行格式、可选的行号修改、尾部的 patch 生成器，这些都可以保留原来，无非多一些 offset 罢了。"

保留原来的补丁应用模式（quilt 还是 stg），除非那个模式真的不恰当。

不要弃用既有的变量，比如 `LLDPD_VERSION_SUFFIX`。

`ifeq` 之类的地方，能少 diff 就不要加缩进。

删文件有时候比留着更吵。这其实是 3.2 那条原则在评审侧的表现：grub2、libnl3 那些不再使用的文件留着，diff 比删掉更小。

PR 拆分翻车翻在逻辑级重叠，不是文件级。同一个逻辑改动因为是行级修改而散落到几个 PR 里，比两个 PR 碰同一个文件难查得多。

`canonical/202605_resolute` 是生产分支，禁止直接 push，改动只经 PR 合入。历史上有三次一次性显式同意的例外（2026-07-23 重推、07-28 快进、08-17 回退到真 merge-base `ba3fb8d5f5`），此后冻结。这条规则只管超仓，不管子模块。

---

## 5. 三条分支

以下都以 **canonical 远端**为准（本地那几个分支是 07-27 的旧版，见本节末）：

```
sonic-net/202605 ──● ba3fb8d5f5  (共同 merge-base，也是生产分支 canonical/202605_resolute 当前所指)
                   │
                   ├── 202605_resolute_mech  fd5781e4d2   2 commits   105 files  +1526 −234  → PR #7 (1/2)
                   │      └── 202605_resolute_real  c139d173e7  +11 = 13 commits  212 files  +2664 −823  → PR #8 (2/2)
                   │
                   └── 202605_resolute_sheldon  648c8121aa  190 commits  213 files  +2699 −823  ← 最终状态在这里
```

`_mech` 是 `_real` 的祖先。但 `_sheldon` 和 `_real` 不互为祖先：`_sheldon` 是有机的开发史，`_real` 是它的重组产物。

**内容上这两边现在已经追平了。** `canonical/202605_resolute_real` 与 `_sheldon` 的差异只剩**一个文件**、`+35` 行，就是 `rules/config.user` —— 而按惯例那个文件本来就不该出现在正式分支上（见 3.1）。也就是说 `_real` 已经是 `_sheldon` 的完整正式版，没有待 fold 的 delta。

这是 08-26 那次重做的结果。此前 `_real` 停在重组当时的内容，比 `_sheldon` 落后 60 个文件，那时"把 delta fold 回 `_real`"是头号待办。现在这条销掉了。

有个坑要提醒：**本地的 `202605_resolute_mech` / `_real` 是 07-27 的旧版，已经废了。** 两条 `_real` 之间是 13/13 分叉（本地 `d3125f835f` vs 远端 `c139d173e7`），主题和顺序一样但 hash 全不同——远端整条栈在 08-26 被重做过。要看或要改就用 `canonical/` 那份，本地那两个分支只是没清理的残留。

`_mech` 之所以是两个 commit，是评审的硬要求：先复制，再改名。第一笔 `4fe94aa35a` 从 trixie **逐字复制** slave 和 docker-layer 的变体，纯 add，reviewer 可以直接跳过；第二笔 `fd5781e4d2` 在复制出来的文件上做纯 `s/trixie/resolute/`，加上切 base 镜像。

反过来做（一个 commit 里既新建文件又改内容）的话，reviewer 面对的是 105 个文件的整体新增，没法判断哪些是复制、哪些是真改动。当时的评审意见就是"你要改回那种先复制再修改的模式，否则难以审阅"。

配套有个判据陷阱：**"纯机械"不等于"盲目全局替换"**。指向真 Debian 产物的 token 是故意保留的：docker-ce 版本串里的 `~trixie` 后缀、真正表示 Debian 版本的 `DEBIAN_VERSION`，以及当时 `fips/trixie` 那条下载路径（那一条后来随 FIPS 关掉一起撤了，见 3.5，但当时的判断是对的）。但也确实存在该改没改的，比如 `DOCKER_BASE_TRIXIE` 这种变量名。得逐文件看，不能靠一条 sed。

`_real` 那 11 个主题提交是：

```
5c6067e921  adapt the sonic-slave build environment to Ubuntu 26.04
0850b30d04  wire BLDENV=resolute into the build graph
6a62473241  bootstrap the target rootfs on Ubuntu 26.04
54213c56c8  retarget and sync the build-consumed submodules
acb1c7c4ff  procure the kernel, grub2 and libnl3 from Ubuntu archives
d4042c7eb8  fix src package builds for the Ubuntu 26.04 toolchain
530a4fdbf1  broadcom: dell/XGS Linux 7.0 kmod adaptation
011ce882a7  comment hygiene across the resolute changes
739cfc65cd  de-fork src packages to Ubuntu sources
04b35e5415  let rsyslogd run the SONiC event plugin under AppArmor
c139d173e7  render /etc/resolv.conf directly instead of via resolvconf
```

按主题分而不是按层分，是为了让 reviewer 一次只看一件事。主题和本文的分层是多对多的：`d4042c7eb8` 那一笔就同时动到 `dockers/`、`rules/`、`src/bash`、`src/isc-dhcp` 和 `platform/broadcom`，横跨 3.2、3.3 和 3.6。

---

## 6. 没收尾的

都不影响两个 `.bin` 的构建，但接手的人应该知道。

硬件验证面只有**一台**机器。broadcom 镜像启动过的物理设备就是那一台 Dell S5232F，同型号第二台都没试过，别的机型更没有。放在最前面，免得被"已在真机验证"那句话盖过去。

iproute2 的 EVPN MH `bridge-fdb` 补丁被挂起了。`docker-base-resolute.mk` 用的是 stock Ubuntu 的 iproute2，而自建那版（只在 trixie 下构建）带着这个补丁，注释里留的是一句 "restore `_DEPENDS` if needed"。代价是控制面学到的 MAC 和数据面学到的没法区分——那是 Cisco 提的补丁。

`docker-base-resolute.mk` 首行还写着 "based on Debian Trixie"，是复制-改名留下的。按 3.2 的原则，无功能价值又已知错误的注释改回去比留着省事——注意这跟保留 grub2 补丁文件那类不是一回事，那些是**正确**的原样保留，这一处是**错的**。（同类的另一处在 `rules/flashrom.mk`，已随 flashrom 退回源构建一起消失。）

`sdklt` 的 `-j16` clean 竞态在树里没修。08-23 那轮没触发它，所以也没压过 job 数；真撞上的时候退路是命令行传 `SONIC_CONFIG_MAKE_JOBS=1`。

`Dh_Lib.pm` 那个 dbgsym patch 不幂等（`grep -q ddeb && sed`），靠 slave 总从 fresh base 重建才成立。而且 base 并没有被 pin：`sonic-slave-resolute/Dockerfile.j2` 用的是浮动 tag `ubuntu:resolute`，`debhelper` 在第 287 行也是不带版本的 apt 安装。哪天上游 debhelper 变了这个 patch 就可能直接失配，而这恰恰会在从零构建时发生。

broadcom 裁掉的东西在 resolute 上都没有构建覆盖：DNX、legacy-TH、rpc / saiserver / PDE / one-aboot，以及我们这次注释掉的那 8 家厂商 kmod。顺带说清一个容易混的口径：`rules.mk` 里一共 20 行 `platform-modules-*` include，现在只有 dell 一家是启用的——8 家是我们注释掉的，另外 11 家上游本来就没启用。

TD3 的 CANCUN config.bcm 指向旧版本。上游 23 个 TD3 配置文件指向 `b870.6.4.1`（其中 19 个是 `*.config.bcm`，4 个是 `config.bcm.j2` 模板），而 SAI 15.2 只带 6.15.0；而这些仍被 dpkg 当作 conffile 的旧文件不会在升级时被自动清掉，于是装新版会加载到旧 CANCUN。修法是改用 `default/` 并删掉 `/usr/lib/cancun` 那一行。

**resolute 的支持范围就是 amd64。** `rules/linux-kernel.mk:12-14` 那个 `armhf` 分支从上游原样继承、没人碰过，Launchpad 的 `linux-sonic` 也没有对应 feed。按 3.2 那条原则它就该原样留着——它不进镜像、改了没有功能收益。这里列出来只是让接手的人知道范围，不是待办。

原地升级路径未定义。4.2 里 TD3 那个 CANCUN 故障本身就是一次原地升级的失败模式（conffiles 跨 SAI 包版本保留），说明升级路径实际会被走到；但"从 trixie 版镜像原地升到 resolute"这件事是不是目标、有没有测过、还是明确不支持，从来没写。接手的人得先定这个，否则不知道要不要为别的包测升级。

Broadcom 的 SAI 三件套必须整套配对更换。单独换 `libsaibcm` 会搞断交换面。2026-07-25 发生过一次，恢复的时候还发现 hostif 的残留只有 reboot 能清。

PPA 化的归属未定。`202605_resolute_ppa` 上脚手架和首批三个包已经完成，还没开 PR，具体传哪个 PPA 也没定。这个分支的状态要说清：相对它自己的 merge-base 有 40 个提交，但相对 `_sheldon` 是 **40 ahead / 14 behind**——它缺最终状态最后那 14 笔（这个数字随 `_sheldon` 前进而增长，08-23 时是 5），接手之前得先 rebase 或 fold。

---

## 7. 接手先做这三件事

**推进 PR #7 / #8 的评审。** fold 已经在 08-26 做完了（见第 5 章），`_real` 内容上就是 `_sheldon` 的正式版，两个 PR 现在挂的是最新内容。剩下的是评审本身，以及合入生产分支 `canonical/202605_resolute`——它当前还停在基线 `ba3fb8d5f5`，也就是说这套移植一行都还没进生产。顺手把本地那两个 07-27 的旧 `_mech`/`_real` 删掉，免得下次又对着错的分支干活。

**给 iproute2 的 EVPN MH 补丁一个决定**（背景见第 6 章）。要么恢复自建 iproute2 把补丁带回来，要么明确记录放弃这个功能。一句 "if needed" 不算决定。

**补 broadcom 的覆盖面，或者明确写下不补**（现状清单见第 6 章）。要支持第二家平台，那 8 家注释掉的厂商 kmod 得逐个过 Linux 7.0 适配，工作量参考 3.6。

顺带给复现的入口，免得从散落各处的片段里拼命令。完整流程在同目录 `specs/2026-07-21-resolute-clean-rebuild-design-zh.md`，那里还包括 docker 镜像清理、`docker builder prune -af` 和共享 dpkg cache 的清理。下面只是主干：`make reset` 本身不清 `/var/cache/sonic/artifacts`、docker 镜像和 builder cache，别拿它当全清。

```
# reset 依次做：sudo rm -rf fsroot* → git clean -xfdf → git reset --hard，全程无提示
make BLDENV=resolute UNATTENDED=y reset

# 两个平台必须串行：configure 写的是共享的 .platform，
# vs 还在后台跑就去 configure broadcom 会把它改掉。
sg docker -c 'make PLATFORM=vs configure'
sg docker -c 'make PLATFORM=vs target/sonic-vs.img.gz target/sonic-vs.bin' > target/build-vs.log 2>&1

sg docker -c 'make PLATFORM=broadcom configure'
sg docker -c 'make PLATFORM=broadcom target/sonic-broadcom.bin'          > target/build-broadcom.log 2>&1
```

vs 侧那两个 installer 目标互不依赖：`sonic-vs.img.gz`（`platform/vs/kvm-image.mk`，KVM 用）和 `sonic-vs.bin`（`platform/vs/one-image.mk`，ONIE 用）。08-23 那轮两个都出了（`.bin` 16:28，`.img.gz` 16:31），第 1 章引的是 `.bin`，所以上面一条 make 把两个都列上。只要一个的话按需删。

开工前先确认两个宿主机前提，缺了必崩：`lsmod | grep ip_tables` 有输出，`/etc/apparmor.d/local/gs` 存在（后者的来历见 4.2）。

---

## 附录：相关文档与取证范围

同目录里：`2026-07-27-resolute-defect-fixes-and-upstream-state-comparison-zh.md` 是逐组件巡检在役交换机发现四个缺陷的完整过程，本文 3.7 是它的最终状态版；`2026-07-26-dut02-s5232f-validation-report-zh.md` 是 Dell S5232F 的真机验证报告；`resolute-modification-catalog-zh.md` 是 2026-07-06 的主题分类快照，它的基线（`77cfa809d`）已经被后来的 rebase 取代，留着当历史看，别当现状；`resolute-migration-code-review-zh.md` 和 `resolute-vs-migration-report-zh.md` 是早期的缺陷视角评审和 per-package 迁移叙事。`specs/` 和 `plans/` 里是各阶段的设计稿和执行计划。

本文的事实来自五处，可靠性递减：仓库本身（`git diff ba3fb8d5f5..202605_resolute_sheldon`、文件内容、行号，第 3 章几乎全部来自这里）；190 条 commit 历史，尤其是 revert 对和 `_mech`/`_real` 的重组过程；构建产物的大小和时间戳；Claude Code 的 transcript（顶层 19 份 JSONL、约 38 MB，覆盖 2026-07-24 之后，第 4 章大部分根因结论来自这里；连 subagent 的子目录一起算是 71 份、约 63 MB）；以及 `~/.claude/history.jsonl` 里 203 条 prompt，回溯到 2026-07-02，只有人类侧文本（第 5 章那条「先复制再改名」的评审要求、4.6 的 diff 卫生标准出自这里）。

两个已知的取证缺口。一是 `cleanupPeriodDays` 默认 30 天，2026-07-24 之前的 transcript 已被自动清扫，而那段恰好是迁移的主体期，只能靠 commit 历史加 `history.jsonl` 加 `docs/plans|specs` 复原，所以第 4 章里越早期的事故细节越薄；这个值已于 2026-08-24 调到 3650，按当前设置不会再被 30 天策略扫掉。二是凡涉及子模块内部和厂商平台仓库的断言（例如 flashrom 调用者的状态），来自早前审计而非本轮复核，文中已逐处标注。
