# arm64 vs 交叉构建探路 实施计划

> **给代理执行者:** 必需子技能:用 superpowers:subagent-driven-development(推荐)或 superpowers:executing-plans 逐任务执行本计划。步骤用复选框(`- [ ]`)语法跟踪。

**目标:** 在 amd64 宿主机上用交叉编译路径推进 `PLATFORM=vs PLATFORM_ARCH=arm64` 构建,收集完整失败清单并分类,据此判断是否需要一台原生 arm64 机器。

**架构:** 独立 git worktree + 独立 dpkg 缓存,三级闸门顺序推进(环境 → 交叉 slave 镜像 → 全量 `-k` 收集)。零代码改动:两处已知 amd64 假设分别用命令行变量绕过和由交叉路径天然跳过。

**技术栈:** SONiC buildimage 构建系统(`Makefile` / `Makefile.work` / `slave.mk`)、`CROSS_BLDENV=1` 交叉路径、Docker + `multiarch/qemu-user-static` binfmt、Ubuntu 26.04 resolute。

**设计依据:** [arm64 vs 交叉构建探路设计](../specs/2026-09-23-resolute-arm64-vs-cross-probe-design-zh.md)(英文版 `-en.md` 为唯一事实来源)

## 全局约束

- 探路期间**零代码改动**。发现任何失败一律只记录、不修复。
- 只写 `/home/sheldon-qi/sbi-arm64-probe`;主工作树 `/home/sheldon-qi/sonic-buildimage-resolute` 与共享缓存 `/var/cache/sonic/artifacts` 不得被写入。
- `canonical/202605_resolute` 是生产分支,本计划不 push 任何分支。探路分支 `probe/arm64-vs-cross` 仅存本地。
- 可用盘低于 30 GB 立即停止并清理,不得跑到写满。
- 闸门二未过则**不进入**闸门三,直接下结论。
- 闸门三出现"修一个冒三个"的长尾特征,停止收集,以已有样本作结论。
- 每条失败归入且仅归入一类:**A 交叉专有** / **B 架构固有** / **C 移植假设**。

---

### 任务 1: 探路工作树与缓存隔离

**文件:**
- 创建:`/home/sheldon-qi/sbi-arm64-probe/`(worktree,分支 `probe/arm64-vs-cross`)
- 创建:`/home/sheldon-qi/sbi-arm64-probe/rules/config.user`(gitignored,不提交)
- 创建:`/var/cache/sonic/artifacts-arm64/`(隔离的 dpkg 缓存)

**接口:**
- 消费:无(首个任务)
- 产出:探路工作树路径 `/home/sheldon-qi/sbi-arm64-probe`,后续所有任务在此目录内执行;磁盘基线数字记入日志供任务 4 的停止条件比对。

- [ ] **步骤 1: 创建 worktree**

`202605_resolute` 已被主工作树占用,git 不允许同一分支被两个 worktree 检出,因此新建探路分支:

```bash
git -C /home/sheldon-qi/sonic-buildimage-resolute worktree add \
  -b probe/arm64-vs-cross /home/sheldon-qi/sbi-arm64-probe 202605_resolute
```

预期:输出 `Preparing worktree (new branch 'probe/arm64-vs-cross')` 与 `HEAD is now at 2c0e2bc031`。

- [ ] **步骤 2: 填充子模块**

构建需要子模块源码。对象已在共享的 `.git/modules/` 内,这一步是本地检出,不走网络。

```bash
cd /home/sheldon-qi/sbi-arm64-probe && git submodule update --init --recursive
```

预期:一系列 `Submodule path '...': checked out '<sha>'`;不出现 `fatal: unable to access` 之类的网络错误。

- [ ] **步骤 3: 验证子模块完整**

```bash
cd /home/sheldon-qi/sbi-arm64-probe
git submodule status --recursive | wc -l
git submodule status | grep -c '^-' || true
```

预期:第一条输出 `60`;第二条输出 `0`(前缀 `-` 表示未初始化)。若第二条非 0,列出未初始化项并停下——子模块 object store 可能损坏,按既有处置(deinit + 删 `.git/modules/<name>` + 从 origin 重新克隆)修复后再继续。

- [ ] **步骤 4: 建立隔离的 dpkg 缓存目录**

```bash
sudo mkdir -p /var/cache/sonic/artifacts-arm64
sudo chmod 777 /var/cache/sonic/artifacts-arm64
ls -ld /var/cache/sonic/artifacts-arm64
```

预期:`drwxrwxrwx`。

- [ ] **步骤 5: 写入探路专用 config.user**

`rules/config.user` 是 gitignored 的,新 worktree 里不存在,必须显式写入。与主工作树的差别只有缓存路径一行:

```bash
cat > /home/sheldon-qi/sbi-arm64-probe/rules/config.user <<'EOF'
# arm64 交叉构建探路专用配置。与主工作树的唯一差别是 dpkg 缓存目录隔离。

PLATFORM ?= vs

# 从 Docker Hub 直接拉基础镜像,不走微软内部镜像站(其无 Ubuntu resolute)
DEFAULT_CONTAINER_REGISTRY =

SONIC_CONFIG_USE_CCACHE = y
BUILD_SKIP_TEST = y
SONIC_CONFIG_USE_DOCKER_CACHE = y

# 隔离:arm64 产物不得进入 amd64 的键空间
SONIC_DPKG_CACHE_METHOD = rwcache
SONIC_DPKG_CACHE_SOURCE = /var/cache/sonic/artifacts-arm64

SONIC_VERSION_CACHE_METHOD = none
SONIC_VERSION_CACHE_SOURCE = /var/cache/sonic/artifacts-arm64/vcache
EOF
```

注意此处**不设** `INCLUDE_FIPS`:`rules/config:381` 已给出 `INCLUDE_FIPS ?= n`,而 `rules/config.user` 在其后被 include,`?=` 对已定义变量是空操作。resolute 上 `INCLUDE_FIPS=y` 会被 `rules/sonic-fips.mk` 的 `$(error)` 直接拒绝。

- [ ] **步骤 6: 验证缓存隔离生效**

```bash
grep -n "artifacts" /home/sheldon-qi/sbi-arm64-probe/rules/config.user
```

预期:只出现 `artifacts-arm64`,不出现裸的 `/var/cache/sonic/artifacts`。若出现裸路径,改正后重跑本步骤。

- [ ] **步骤 7: 记录磁盘基线**

```bash
df -h / | tail -1
du -sh /var/cache/sonic/artifacts
docker system df
```

把三条输出记入探路日志。任务 4 的停止条件(可用盘 < 30 GB)以此为基准。

---

### 任务 2: 闸门一 —— 模拟环境

**文件:**
- 修改:宿主机 binfmt_misc 注册表(内核运行时状态,非文件)
- 创建:`/tmp/arm64-probe-gate1.log`

**接口:**
- 消费:任务 1 的工作树与磁盘基线
- 产出:一个可用的 aarch64 binfmt handler。闸门二的 `--platform=linux/arm64` 容器构建依赖它。

- [ ] **步骤 1: 前置条件预检**

```bash
mount | grep -c binfmt_misc
sudo -n true && echo "sudo OK"
df --output=avail -BG / | tail -1
docker version --format '{{.Server.Version}}'
```

预期:第一条 ≥ 1(binfmt_misc 已挂载);第二条输出 `sudo OK`;第三条 ≥ 60G;第四条输出 docker 服务端版本。任一不满足则停下处理,不继续。

- [ ] **步骤 2: 注册 binfmt handler**

用与构建系统完全相同的命令(`Makefile.work:457` 的 `DOCKER_MULTIARCH_CHECK`),避免探路与正式构建走不同路径:

```bash
docker run --rm --privileged multiarch/qemu-user-static --reset -p yes --credential yes 2>&1 | tee /tmp/arm64-probe-gate1.log
```

预期:输出若干 `Setting /usr/bin/qemu-<arch>-static as binfmt interpreter for <arch>`。

- [ ] **步骤 3: 验证 aarch64 handler 已启用**

```bash
ls /proc/sys/fs/binfmt_misc/ | grep qemu-aarch64
head -1 /proc/sys/fs/binfmt_misc/qemu-aarch64
```

预期:第一条输出 `qemu-aarch64`;第二条输出 `enabled`。

- [ ] **步骤 4: 冒烟测试 —— 真跑一个 arm64 容器**

这是闸门一的真实判据。前三步只证明注册表被写了,这一步证明模拟链路端到端通。

```bash
docker run --rm --platform=linux/arm64 ubuntu:resolute uname -m
```

预期:输出 `aarch64`。

若此步失败:闸门一未过。结论是环境层就不通,记录错误后停止整个探路,不进入任务 3。

- [ ] **步骤 5: 记录结果**

把步骤 3、4 的输出追加进 `/tmp/arm64-probe-gate1.log`。

---

### 任务 3: 闸门二 —— 交叉 slave 镜像

**文件:**
- 创建:`/home/sheldon-qi/sbi-arm64-probe/.arch`、`.platform`(由 `slave.mk:150-151` 写出)
- 创建:`/tmp/arm64-probe-gate2.log`
- 创建:docker 镜像 `sonic-slave-resolute-march-arm64-<user>`

**接口:**
- 消费:任务 2 的 binfmt handler
- 产出:交叉 slave 镜像与已写定的 `.arch=arm64` / `.platform=vs`。任务 4 的构建在此镜像内运行,且因 `.arch` 已存在,后续 make 调用无需再传 `PLATFORM_ARCH`。

- [ ] **步骤 1: 执行 configure**

该目标经 `Makefile.work` 的 `%::` 通配规则,会先做 multiarch 检查、拉起 `march` dockerd(`--storage-driver=vfs`,data-root `/var/lib/march/docker`),再构建交叉 slave 镜像,最后在容器内运行 `slave.mk` 的 `configure`。

```bash
cd /home/sheldon-qi/sbi-arm64-probe
BLDENV=resolute CROSS_BLDENV=1 \
  make configure PLATFORM=vs PLATFORM_ARCH=arm64 2>&1 | tee /tmp/arm64-probe-gate2.log
```

预期:退出码 0。耗时以十分钟计(交叉工具链与大量 `-dev` 包的安装)。

- [ ] **步骤 2: 确认走的是交叉路径而非 qemu 路径**

```bash
grep -E "CROSS_BUILD_ENVIRON|MULTIARCH_QEMU_ENVIRON" /tmp/arm64-probe-gate2.log | head -4
```

预期:`CROSS_BUILD_ENVIRON` 为 `y`、`MULTIARCH_QEMU_ENVIRON` 为 `n`。若相反,说明 `CROSS_BLDENV` 没生效(见 `Makefile.work:176`),停下查明再继续——否则后面测的是另一条路。

- [ ] **步骤 3: 验证镜像存在**

```bash
docker images --format '{{.Repository}}:{{.Tag}}' | grep march-arm64
```

预期:至少一行,形如 `sonic-slave-resolute-march-arm64-<user>:<tag>`。

- [ ] **步骤 4: 验证交叉工具链可用**

```bash
IMG=$(docker images --format '{{.Repository}}:{{.Tag}}' | grep march-arm64 | head -1)
docker run --rm "$IMG" aarch64-linux-gnu-gcc --version | head -1
```

预期:输出 aarch64 交叉 gcc 的版本行。

- [ ] **步骤 5: 验证 configure 落盘**

```bash
cat /home/sheldon-qi/sbi-arm64-probe/.arch
cat /home/sheldon-qi/sbi-arm64-probe/.platform
```

预期:分别输出 `arm64` 与 `vs`。

- [ ] **步骤 6: 失败时的处置**

若步骤 1 非 0 退出:从日志尾部取首个真实错误,记录为清单第一条并分类。已预判的风险点是 `sonic-slave-resolute/Dockerfile.j2` 交叉分支中的 `apt-mark hold g++-10-$gcc_arch` / `gcc-10-$gcc_arch` —— resolute 的 gcc 默认为 15,不存在 10 版本的交叉包,这属 **C 类**。

按全局约束,此处**不修复**。闸门二未过即停止探路,以"交叉路在本机不通"作结论,不进入任务 4。

---

### 任务 4: 闸门三 —— 全量失败收集

**文件:**
- 创建:`/tmp/arm64-probe-gate3.log`(完整构建日志)
- 创建:`/tmp/arm64-probe-failures.txt`(失败目标清单)
- 修改:`/home/sheldon-qi/sbi-arm64-probe/target/`(构建产物与逐包日志)

**接口:**
- 消费:任务 3 的交叉 slave 镜像与 `.arch` / `.platform`
- 产出:`/tmp/arm64-probe-failures.txt`,任务 5 的分类依据;逐包细节在 `target/<pkg>.log`。

- [ ] **步骤 1: 启动全量收集构建**

两个变量是本步骤的关键,都来自设计文档:

- `TARGET_BOOTLOADER=grub` 覆盖 `Makefile.work:127` 给非 amd64 的 `uboot` 默认。否则 `build_debian.sh:799` 会去找不存在的 `platform/vs/sonic_fit.its`,`set -e` 直接终止。命令行变量优先级高于 makefile 赋值,且 `SONIC_BUILD_INSTRUCTION` 显式透传该变量进容器。
- `SONIC_BUILD_VARS="-k"` 把 keep-going 送进容器内那层 make。`MAKEFLAGS` 不在 `DOCKER_RUN` 的 `-e` 列表里因而穿不透;但 `Makefile:15` 会把 `SONIC_BUILD_VARS` 并入 `SONIC_OVERRIDE_BUILD_VARS`,后者在 `Makefile.work:673` 被拼到容器内 make 的命令行尾部,而 GNU make 允许标志出现在命令行任意位置。

```bash
cd /home/sheldon-qi/sbi-arm64-probe
BLDENV=resolute CROSS_BLDENV=1 \
  make TARGET_BOOTLOADER=grub SONIC_BUILD_VARS="-k" target/sonic-vs.bin 2>&1 \
  | tee /tmp/arm64-probe-gate3.log
```

预期:构建推进并在多处失败后继续(keep-going 生效),最终以非 0 退出。以小时计。

- [ ] **步骤 2: 确认 keep-going 真的生效**

```bash
grep -c "not remade because of errors" /tmp/arm64-probe-gate3.log
```

预期:≥ 1。若为 0 且构建在首个错误处即终止,说明 `-k` 没送达;此时回到步骤 1 检查 `SONIC_BUILD_VARS` 拼写,不要改用手工重建命令行的办法绕过——那会引入变量不一致。

- [ ] **步骤 3: 盘位与缓存污染检查**

构建期间每隔一段时间执行,或在构建结束后立即执行:

```bash
df --output=avail -BG / | tail -1
find /var/cache/sonic/artifacts -maxdepth 1 -newermt '-2 hours' | head
du -sh /var/cache/sonic/artifacts-arm64
```

第一条低于 30G 立即中断构建并清理 `/var/lib/march/docker`(vfs 无层共享,是主要占用方),按全局约束处置。

第二条**必须无输出**:amd64 共享缓存在探路期间不应有任何新写入。一旦有输出,说明隔离失效(多半是 `config.user` 未被读取或被覆盖),立即中断构建,查明后再决定是否重来——继续跑会污染主构建的缓存键空间。

第三条只作记录,反映探路自身的缓存增长。

- [ ] **步骤 4: 提取失败清单**

`-k` 会在结尾打印未能完成的目标,这是权威清单:

```bash
grep -E "^make.*\*\*\*|not remade because of errors" /tmp/arm64-probe-gate3.log \
  | tee /tmp/arm64-probe-failures.txt
wc -l /tmp/arm64-probe-failures.txt
```

预期:输出若干行并记录总数。

- [ ] **步骤 5: 为每条失败定位根因**

逐包日志在 `target/` 下,比控制台输出更可读:

```bash
ls -t /home/sheldon-qi/sbi-arm64-probe/target/*.log | head -20
```

对清单中每个失败目标,读对应 `target/<pkg>.log` 的尾部 40 行,提炼一句根因。全部记入 `/tmp/arm64-probe-failures.txt`。

- [ ] **步骤 6: 长尾停止条件检查**

若步骤 5 显示失败呈"修一个冒三个"的连锁特征(大量失败互为前置依赖、根因同源),停止继续收集,以已有样本作结论。探路的价值在判断,不在穷尽。

---

### 任务 5: 分类与结论报告

**文件:**
- 创建:`/home/sheldon-qi/sonic-buildimage/docs/superpowers/2026-09-23-resolute-arm64-cross-probe-report-zh.md`
- 创建:`/home/sheldon-qi/sonic-buildimage/docs/superpowers/2026-09-23-resolute-arm64-cross-probe-report-en.md`

**接口:**
- 消费:`/tmp/arm64-probe-failures.txt` 与各 `target/<pkg>.log`
- 产出:探路的最终交付物——带分类的失败清单与"是否需要原生 arm64 机器"的结论。

- [ ] **步骤 1: 逐条分类**

对清单每条失败,判定 A / B / C 并写明依据:

- **A 交叉专有** —— 只在交叉编译下发生。判据:报错涉及 `-a arm64` 未被 `debian/rules` 处理、`configure` 猜错 host 三元组、wheel 无 aarch64 预编译轮子而就地编译失败、cross venv 路径错。**原生 arm64 机器会消除这一类。**
- **B 架构固有** —— arm64 本身缺东西。判据:上游只发布 amd64 的镜像或包。已知成员:`p4lang/behavioral-model:latest` 只有 amd64,`platform/vs/onie.mk` 的 ONIE recovery ISO 只有 x86_64。
- **C 移植假设** —— `202605_resolute` 自己引入的 amd64 假设。已知成员:`sonic-slave-resolute/Dockerfile.j2:575` 的 `gcc-multilib`(交叉路径不执行,故本次未撞上)。

- [ ] **步骤 2: 统计占比并得出结论**

按设计文档的决策规则:A 类占失败主体 → 值得弄原生机器,那一整类会免费消失;B/C 占主体 → 弄了机器也要做同样的代码改动,不如就地改。

- [ ] **步骤 3: 写报告(中英两份)**

报告放在 `docs/superpowers/` 根目录,与既有的验证报告同级(例如 `2026-07-26-dut02-s5232f-validation-report-{zh,en}.md`)。两份内容完整对应,不是摘要与全文的关系。每份包含:

1. 探路实际走到哪一级闸门、耗时、资源占用
2. 完整失败清单表:失败目标 / 报错要点 / A、B、C 分类 / 分类依据
3. 三类占比
4. 结论:原生 arm64 机器的必要性
5. 若结论为需要,附机器规格要求(核数、内存、盘、网络可达性)

不写文档自身的修订史。

- [ ] **步骤 4: 提交报告**

文档仓库是 `/home/sheldon-qi/sonic-buildimage`(分支 `202605_resolute_doc`),与构建仓库是两个不同的检出。必须用 `git -C` 显式指定,否则可能误提交到另一个仓库:

```bash
git -C /home/sheldon-qi/sonic-buildimage add \
  docs/superpowers/2026-09-23-resolute-arm64-cross-probe-report-zh.md \
  docs/superpowers/2026-09-23-resolute-arm64-cross-probe-report-en.md
git -C /home/sheldon-qi/sonic-buildimage commit -m "docs(resolute): report the arm64 vs cross-build probe results"
git -C /home/sheldon-qi/sonic-buildimage log -1 --format='%h %G? %s'
```

预期:末条输出以 `G`(签名有效)标记。该仓库已配置 `commit.gpgsign=true`。

- [ ] **步骤 5: 清理探路资源**

结论产出后,按需释放:

```bash
df -h / | tail -1
docker images --format '{{.Repository}}:{{.Tag}}' | grep march-arm64
```

探路 worktree、`probe/arm64-vs-cross` 分支、`/var/cache/sonic/artifacts-arm64`、march dockerd 数据目录是否保留,取决于下一步是否继续做 arm64——保留与否交由人决定,本步骤只报告占用,不擅自删除。
