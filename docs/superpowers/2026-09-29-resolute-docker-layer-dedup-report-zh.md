# SONiC docker 镜像间的重复文件：实测与硬链接修法

- 日期：2026-09-29
- 测量的镜像（均为 amd64）：
  - resolute broadcom：2026-09-17 增量构建、PR #14 CI 构建（`c05f0e016`）、2026-08-23 从零构建（`2957b9e3`）
  - resolute vs：2026-08-27 构建
  - 官方上游 202605 broadcom：Azure 构建 20260928.6（`6aec5bee6`，build id 1232715）
  - rock 分支的 vs 镜像 `sonic-vs-rock-260929.img.gz`（`202605_resolute_rock.0-dirty-20260926.010724`）
- 改动：本地分支 `feat/dockerfs-hardlink`，在 `d2f9ae8502` 之上一个签名提交 `6dc4a02257`，未推送
- 工具与原始结果：[data/2026-09-29-docker-layer-dedup/](data/2026-09-29-docker-layer-dedup/)
- 本文为中文版；英文版为唯一事实来源（`-en.md`）

## 0. 结论

- **SONiC 的 docker 镜像并没有压成单层。** 每个 Dockerfile 在父镜像之上加一层，共享的父层 overlay2 只存一份（§1）。
- **重复来自兄弟镜像。** 没有共同父层的镜像，各自往自己的层里装同样的文件，例如 syncd 与 gbsyncd、protobuf 和 SAI 库。
  - resolute broadcom：重复 242 MB，占全部层内容的 12%。
  - resolute vs：968 MB，29%，大头是 syncd-vs 和 gbsyncd-vs 带着同一套工具链。
  - 官方上游 broadcom：241 MB，11.8%。上游有同样的问题，量级也一样（§2）。
  - rock 版 vs：3266 MB，57%（§5）。
- **代价在哪里。** gzip 做不了跨文件去重，所以重复部分在 `.bin` 里占压缩后的大小，装机后在盘上占完整大小。
- **修法不需要抽公共父镜像。** 在打包 `dockerfs.tar.gz` 之前对 `overlay2/*/diff` 跑一遍 util-linux `hardlink`，`build_debian.sh` 里加一行即可（§3）。
- **已在 vs 上端到端验证**，方法是重新打包现成镜像，没有重新构建（§4）：
  - `dockerfs.tar.gz` 1025.6 → 742.1 MB，装机后 docker 目录 3356 → 2442 MB。
  - ONIE 装机、启动、copy-up 隔离、`docker save` digest、`restart swss`、`config reload`、`docker rmi` 的表现都与未改动的镜像一致。
- **rock 版 vs 原地重打包：** `img.gz` 3523.7 → 2596.0 MB（−26%）；加 `hardlink -t` 为 2412.3 MB（−32%）。尚未做启动测试（§5）。
- **mtime 限制了能链接多少。** `hardlink` 默认要求 mtime 也相同才合并。把构建期产生的 mtime 钳制到 `SOURCE_DATE_EPOCH`，剩下的几乎都能收回来。这就是可复现构建的角度（§6）。

## 1. 镜像是怎么存的

**层。** 镜像有两种形态：

- **Dockerfile 镜像。**
  - `docker-base-resolute` 以 `FROM scratch` / `COPY --from=base / /` 结尾，因此是 233 MB 的单层。
  - 其余每个 Dockerfile 都以 `FROM $BASE` 开头，通过 `rsync_from_builder_stage` 宏（`dockers/dockerfile-macros.j2:48-50`）加一层，外加一个空的 `rm /cache.tgz` 层。
  - 链条是 base（233 MB）→ config-engine（94 MB）→ swss-layer（32 MB，7 个镜像共用）→ 镜像自己的层。
  - 父层不管有多少镜像叠在上面都只存一份。如果把每个 broadcom 镜像都压成自包含的单层，总量会是 9828 MB，而现在实际存的是 2018 MB。
- **rock 镜像**的形态不同，见 §5。

**存储路径。**

- **`.bin`。** `sonic-*.bin` → `installer/fs.zip` → `dockerfs.tar.gz`。最后这个文件是构建时整个 `/var/lib/docker` 的 pigz tar：overlay2 各层目录加上镜像元数据（`build_debian.sh:954-963`）。
- **装好的盘。** 在装好的盘上（包括 vs 的 `img.gz`），`installer/install.sh:233` 把它解到 `/host/image-<version>/docker`。
- **两种形态都不做跨层去重。**

## 2. 重复了多少

「重复」指普通文件的内容（sha256）已经在层集合里别处出现过的那部分字节。「被遮蔽」指同一镜像中，被上层覆盖的下层文件的字节：它们照样存储，却永远看不到。

| 镜像 | 层内容 | 重复 | 被遮蔽 |
|---|---|---|---|
| resolute broadcom，2026-09-17 增量 | 2018 MB | **242 MB（12.0%）** | 43 MB |
| resolute broadcom，PR #14 CI 构建 | 1986 MB | 227 MB（11.4%） | 19 MB |
| resolute broadcom，2026-08-23 从零 | 1989 MB | 226 MB（11.3%） | 1.5 MB |
| **官方上游 202605 broadcom** | 2043 MB | **241 MB（11.8%）** | 3.6 MB |
| resolute vs，2026-08-27 | 3367 MB | **968 MB（28.7%）** | 未测 |
| rock 版 vs，2026-09-26 | 5711 MB | **3266 MB（57.2%）** | 2.0 MB |

重复的字节是什么（2026-09-17 broadcom）：

- 205.7 MB 是兄弟层或无关层里的同一路径：两个镜像各自装了同一个包。
- 18.4 MB 是同样的内容换了个路径。
- 17.9 MB 是镜像自己的祖先层里已经有了、又复制了一遍的文件。

最大的几项：

| 浪费 | 份数 | 文件 |
|---|---|---|
| 15.8 MB | ×6 | `libprotobuf.so.32` |
| 13.7 MB | ×5 | `libsaimetadata.so` |
| 12.5 MB | ×3 | `libc.a` |
| 10.0 MB | ×3 | `libsystemd-shared-259.so` |
| 9.6 MB | ×4 | `/usr/bin/syncd`（syncd-brcm 加三个 gbsyncd 镜像） |
| 7.2 MB | ×5 | `libsairedis.so` |
| 6.3 MB | ×5 | `/usr/share/misc/pci.ids` |

上游的清单一样，另外还有约 22 份 buildinfo 的 `copyrights.tar.gz`。vs 上 968 MB 里有 770 MB 来自 docker-syncd-vs 和 docker-gbsyncd-vs，两者都带着 LLVM 21、clang、gcc 的 `cc1` 和 gRPC 静态库。

**被遮蔽字节反映版本是否钉住。** 09-17 构建里，`docker-base-resolute` 用的是 09-03 的缓存，config-engine 是 09-17 构建的。其间 apt 升级了 `libc6` 和 `python3.14`，于是 base 层里的旧副本仍存储在新副本之下。CI 构建在一次运行之内也有同样的漂移（19 MB）。上游钉住了 deb 版本，只有 3.6 MB。

**各形态下的代价**，以 09-17 broadcom 构建为例：

- **`.bin`：** `dockerfs.tar.gz` 为 555 MB。把重复存成 tar 链接后是 486 MB，所以重复在压缩后占 69 MB。若用单流 `zstd --long=31`，重复只占 0.2 MB，但这会改变 ONIE 安装器要读的格式。
- **盘上：** 占完整大小，按 4 KiB 块取整后 265 MB。
- **宿主 rootfs：** 宿主 rootfs 里还有 306 MB 与 docker 层中的文件逐字节相同。那是两个独立的压缩包，这些工具链接不了。

## 3. 修法：打包前硬链接

```sh
## Hardlink identical files across docker image layers; tar keeps the links
sudo bash -c "hardlink --respect-xattrs $FILESYSTEM_ROOT/${DOCKERFS_PATH}var/lib/docker/overlay2/*/diff"
```

这一行放在 `build_debian.sh` 里紧挨 `## Compress docker files` 之前。slave 镜像里已经有 util-linux 2.41.3 的 `hardlink`。为什么安全：

- **tar。** GNU tar 把同一 inode 的第二个及以后的名字写成链接条目，ONIE 里的 busybox tar 解包时会还原成链接。
- **overlayfs。** 下层对容器只读。容器里的写、`chmod` 或 `rm` 会把文件 copy-up 到该容器自己的 upper 目录，共享的 inode 不受影响。
- **`docker save`** 从各层的 diff 目录重新生成层 tar，所以层 digest 不变。
- **`docker rmi`** 删的是层目录。一个文件只要还被别的层链接着，inode 就保留。
- **合并规则。** `hardlink` 只合并内容、mode、属主以及（加 `--respect-xattrs` 时）扩展属性都相同的文件。默认还要求 mtime 相同，`-t` 去掉 mtime 检查。
  - 测过的两套层里都没有 `.pyc` 文件，所以 `-t` 不会让字节码缓存失效。
  - 但它确实会让一些文件报告的 mtime 与构建时的不同。

省下多少：

| 镜像 | 测量项 | 之前 | 之后 |
|---|---|---|---|
| resolute broadcom 09-17 | 层占用的 ext4 | 2011 MB | 1790 MB |
| resolute broadcom 09-17 | `dockerfs.tar.gz` | 555 MB | 493 MB（重复全部链接时 486 MB） |
| 官方 202605 broadcom | `dockerfs.tar.gz`，重复全部链接 | 593 MB | 507 MB |
| resolute vs 08-23 | `dockerfs.tar.gz` / 装机后 docker 目录 | 1025.6 / 3356 MB | 742.1 / 2442 MB（§4） |
| rock 版 vs 09-26 | `dockerfs.tar.gz`，默认 / `-t` | 1877 MB | 948 / 765 MB（§5） |

broadcom 的 242 MB 重复里，默认模式链接了 214 MB；官方镜像 241 MB 里链接了 202 MB。其余内容相同但 mtime 不同（§6）。

## 4. vs 上的端到端检查

**方法。**

- **基线镜像。** 2026-08-23 从零构建产出的 `sonic-vs.bin`（`202605_resolute_sheldon.0-2957b9e3`）。
- **硬链接版。** 通过重新打包这个文件得到，没有重新构建（`repack-bin.sh`）：
  - 解出 payload，用 `--numeric-owner` 解开 `dockerfs.tar.gz`，跑 `hardlink`，用 pigz 重新打 tar 并更新 `fs.zip`；
  - 改写 sharch 头里的 `payload_image_size` 和 `payload_sha1`。
- **装机。** 两个镜像都用 `scripts/build_kvm_image.sh` 的本地副本走了真实的 ONIE 装机。副本删掉了 `apt-get` 那一行，VNC 和 SSH 转发只绑 127.0.0.1。
- **健康检查。** 由注入的一次性 systemd 单元（`hlcheck.sh`）完成：结果写到 `/host`，然后关机。交互式串口会话在首次启动时从第二条命令起就不再响应，两个镜像都如此。

**大小。**

| | 未改动 | 硬链接 |
|---|---|---|
| `dockerfs.tar.gz` | 1025.6 MB | 742.1 MB（−27.6%） |
| `sonic-vs.bin` | 2663.9 MB | 2380.4 MB |
| 装机后 `/host/image-*/docker` | 3356 MB | 2442 MB |
| SONiC-OS 分区已用 | 4932 MB | 4017 MB |
| `sonic-vs.img.gz` | 2679.6 MB | 2395.6 MB |

**内容。** 装机后 52,090 个普通文件的内容、mode、属主、mtime 全部一致。唯一的差别是 4,029 个符号链接的 mtime，这是解包再打包的副产物。

**行为**（`result-a.txt` 为硬链接版，`result-b.txt` 为未改动版）：

| 检查项 | 两个镜像 |
|---|---|
| 容器 | 14 个在跑，集合相同（bgp、database、eventd、gbsyncd、gnmi、lldp、mgmt-framework、pmon、radv、snmp、swss、syncd、sysmgr、teamd） |
| ASIC_DB | 33 个 PORT、69 个 ROUTE_ENTRY；PORT_TABLE 里 32 个端口，PortInitDone 已置位 |
| BGP | 配置了 32 个邻居 |
| 失败单元 | `system-health` 和 `watchdog-control`，每个 vs 镜像上都会失败 |
| Copy-up | `/usr/share/misc/pci.ids` 在硬链接版里是一个 inode、5 个链接，在另一个里是 5 个独立 inode。在 swss 里往它末尾追加内容，只改了 swss 里的那份；bgp、lldp、pmon、snmp 以及五个层文件都没变 |
| `docker save` | docker-orchagent、docker-syncd-vs、docker-fpm-frr 的层 sha256 都等于 `rootfs.diff_ids` |
| `systemctl restart swss`，然后 `config reload` | 14 个容器全部恢复，33 个端口，失败单元相同 |
| syslog ERR 行 | 两边消息相同 |

**删除镜像**（`hlcheck2.sh`，`result2-*.txt`）：

- `docker rmi` 掉 feature 未启用的六个镜像（dhcp-relay、macsec、nat、sflow、mux、sonic-otel），删除了 2,731 个层文件，其中 2,075 个是硬链接。
- 剩下的文件里有 4,098 个曾与被删文件共用 inode，内容全部保持原样。
- 其余文件都没有变化。之后 `config reload` 恢复出相同的端口、路由和 BGP 邻居。

## 5. rock 版 vs 镜像

`sonic-vs-rock-260929.img.gz` 包含 28 个镜像：14 个用 rockcraft 打包，14 个仍由 Dockerfile 构建。rock 镜像按 history 里的 `umoci` 和 entrypoint 为 `/usr/bin/pebble` 识别，分别是：

> database、eventd、fpm-frr、iccpd、lldp、macsec、nat、platform-monitor、router-advertiser、sflow、snmp、sonic-gnmi、sonic-mgmt-framework、teamd

**层的形态。** 一个 rock 有五层：

- L0：`ubuntu:26.04` 基础层，100 MB，13 个 rock 共用。
- L1：`/.rock/metadata.yaml`。
- L2：一个装下所有 part 的胖层，117–327 MB。
- L3：pebble 的 layer YAML。
- L4：又一个 `metadata.yaml`。

docker-database 只有三层，也不用共享基础层；它自己带了 62 MB 的基础层内容。

**为什么重复这么高。** rock 之间没有父子关系。每个胖层都 stage 了自己完整的运行时，而 Dockerfile 镜像是从 config-engine 和 swss-layer 各拿一份。3266 MB 重复里有 2286 MB 在 rock 胖层中。有 105 MB 的内容（整套 python3.14、swsscommon、redis-tools）在使用共享基础层的全部 13 个胖层里各有一份。

**混用不一致。** 一个镜像里并行跑着两套打包模式：

- 两条互相不能共享层的基础链；
- 两套进程管理器，rock 里用 pebble，其余用 supervisord。

**原地重打包**（`repack-img.sh`：在挂载的 SONiC-OS 分区上跑 hardlink，`fstrim`，转回 qcow2，gzip）。基线是未改动的盘走同样的转换加 gzip 流程。

| | 未改动 | `hardlink` 默认 | `hardlink -t` |
|---|---|---|---|
| `img.gz` | 3523.7 MB | 2596.0 MB（−26%） | 2412.3 MB（−32%） |
| 折合 `dockerfs.tar.gz` | 1877 MB | 948 MB | 765 MB |
| 盘上 docker 目录 | 5842 MB | 3133 MB | 2511 MB |

这个镜像无论改前改后都还没启动过。

**硬链接后 rock 对比 Dockerfile。** 链接能抹掉两种打包模式之间的大部分差距，但前提是 mtime 一致：

| docker 目录 | 未链接 | 默认 | `-t` |
|---|---|---|---|
| 纯 Dockerfile 的 vs（08-27） | 3366 MB | 2436 MB | 2397 MB |
| rock 版 vs（09-26） | 5843 MB | 3133 MB | 2511 MB |

用 `-t` 时两者只差 114 MB：

- 45 MB 是真实的内容差异：rock 镜像多了 iccpd，而且新了一个月。
- 约 56 MB 是目录开销：rock 镜像多了 13,700 个目录，因为每个胖层都带一整棵目录树，而目录不能硬链接。

用默认模式时两者差 700 MB，几乎全是 pip 在不同时间装进各个 rock 的 site-packages 的 Python 包。

## 6. mtime 与可复现构建

内容相同的文件过不了默认的 mtime 检查，原因有两个：

1. **构建期安装。** 构建过程中写出的文件带着写出时的时间：pip 安装、dpkg 和 debconf 状态、buildinfo。修法是把所有晚于 `SOURCE_DATE_EPOCH` 的 mtime 钳制为它。
2. **版本漂移。** 不同镜像装了同一个包的不同版本。修法是钉住包版本。

每一步能收回多少：

| | 默认模式 | 钳制后 | 上限（`-t`） |
|---|---|---|---|
| resolute broadcom 09-17 | 214 MB | 226 MB | 242 MB |
| resolute broadcom 08-23 从零 | — | 224.8 MB | 225.6 MB |
| 官方 202605 broadcom（版本已钉） | 202 MB | 239 MB | 240 MB |
| rock 版 vs 09-26 | 2669 MB | 3260 MB | 3266 MB |

钳制要在哪里做：

- **Dockerfile 镜像：在 BuildKit 导出时。** 也就是 `SOURCE_DATE_EPOCH` 构建参数加 `rewrite-timestamp=true`；slave 里是 docker 29.6.1 和 buildx 0.35。不能在 rsync 层之前的 builder 阶段做。`rsync` 按大小和 mtime 比较，一个改了内容但大小没变的文件会被静默跳过。
  - `Makefile.work:295-304` 已经定义了 `SOURCE_DATE_EPOCH`（为 SBOM 引入），并导出到 slave 容器里。
  - `slave.mk` 没有把它传给 `docker build`。
- **rock：在 `override-prime` 里。** 在那里把所有晚于 `SOURCE_DATE_EPOCH` 的文件 touch 一遍，就能覆盖占 rock 差距大头的 pip 安装包。

钉版本：上游有 `versions-deb-trixie` 文件和 `MIRROR_SNAPSHOT`，resolute 两样都没有。Ubuntu 上对应的做法是 snapshot.ubuntu.com，它把所有 apt 操作固定到同一个时间点。

钳制和钉版本不是硬链接改动的前提。它们能提高收益，并让结果不再取决于各个镜像碰巧在什么时候构建。

## 7. 未完成

- 硬链接改动是本地提交，还没开 PR。
- rock 镜像还没启动过，链接与否都没有。
- 还没有用 rock 分支合并当前 `202605_resolute` 构建出 vs 镜像，所以它也还没有 A/B。
- 导出时钳制和 `override-prime` 钳制只做了模拟测量（`report2.py`），都没实现。
- broadcom 的数字来自对镜像的分析。没有把链接后的 broadcom 镜像装到硬件或 VM 上。
