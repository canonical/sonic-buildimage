# 审阅 PR #10「重新打开 resolute 包测试」：三方交叉核查与一个被 nocheck 掩盖的真回归

**日期**：2026-09-03
**对象**：`canonical/sonic-buildimage#10`　`build(resolute): re-enable package test suites`
**base / head**：`canonical/202605_resolute` → `canonical/202605_resolute_enable_tests`（merge-base `c037019737`）
**改动**：`.gitignore`、`AGENTS.md`、`rules/config`、`rules/swss.mk`、`slave.mk`、`src/sonic-snmpagent`（gitlink）、`src/sonic-yang-models/tests/yang_model_tests/test_yang_model.py`
**上游对照**：`sonic-net/202605`

---

## 1. 结论速览

建议**修改后合并**。方向正确——`rules/config:404` 的 `BUILD_SKIP_TEST ?= n` 精确还原上游 `sonic-net/202605:rules/config:398`，是干净的 de-fork。但存在三类问题：

1. **`nocheck` 掩盖了一个真回归**：Ubuntu 的默认链接 flag `-Wl,-Bsymbolic-functions` 打掉了 swss 单元测试赖以工作的符号插入机制。这是 Debian→Ubuntu 迁移的直接产物，正是这次迁移应当抓住的那类缺陷。见 §3.2。
2. **`AGENTS.md` 有两条与仓库事实相反的陈述**，且该文件的 Scope 段禁止的内容正是本 PR 新加的内容。见 §3.3、§3.4。
3. **「测试打开了」与「测试真的跑了」之间有缺口**：swss 整包 `nocheck`、chassisd 整套跳过、部分包在开缓存时被静默复用。

§3.3（AGENTS.md 事实错误）是**三方独立收敛**的结论。§3.2（真回归）已由一次受控 A/B 实验坐实：同一个测试二进制只换 `.so`，带 flag 时抛 redis 异常退出 134，剥掉 flag 后 **770 个用例全过**——全程容器里没有 redis。修法是一行，已验证。

**一条重要的降级**：chassisd 那条最初被三个审阅者一致判为「代码与描述冲突」，但补查上游后确认**上游同样从不运行这套测试**（`sonic_chassisd` wheel 只在 `BLDENV=trixie` 下构建，而上游的跳过恰好覆盖 trixie），本 PR 的代码与上游一致、不需要改；实跑也确认 PR 描述的「216 passed / 2 multiprocessing failures」数字是准的。只剩措辞要改。详见 §3.1——这也是本次审阅里「多方一致」仍然会一致地错的一个例子。

---

## 2. 审阅方法与可信度分级

本次用了四轮相互独立的审阅，全部结论由我回原始文件或构建产物复核后才采信：

| 轮次 | 执行者 | 定位 |
|---|---|---|
| 1 | `code-review` skill（max） | 首轮全量，产出 14 条 |
| 2 | Codex `gpt-5.6-sol` effort=low | 独立复审（effort 误用默认值，产出偏薄，见 §9） |
| 3 | Codex `gpt-5.6-sol` effort=xhigh | 独立复审 |
| 4a | fable | 定向核查三条高优结论（被给定命题，有锚定风险） |
| 4b | fable | 完全独立的全量审阅（不透露任何前人结论） |

正文中的标记含义：

- **【三方一致】**——多个审阅者在互不知情下收敛到同一结论，可信度最高
- **【已实测】**——我在真实构建环境或产物上跑过验证
- **[推断]**——从代码语义推出，未直接观测
- **[未证实]**——无法从仓库确定，按字面记录

**一条方法论**：不能因为某条结论来自更强的模型或更高的 effort 就直接采信。§3.2 与 §7 第 3 行是同一模型在两次运行中给出相反答案的例子，判定靠的是回原始文件查链接单元，不是靠比较来源权威性。

---

## 3. 合并前必须处理

### 3.1 `sonic_chassisd` 整套测试被跳过——行为与上游一致，但描述措辞会误导 【三方一致 + 已实测】

> **本条经复核后降级。** 首轮三个审阅者都把它当成「代码与描述冲突」，但补查上游与实跑测试后确认：**上游 `sonic-net/202605` 同样从不运行这套测试**，本 PR 只是把同一行为搬到 resolute，代码是对的。剩下的问题只在 PR 描述的措辞。原始推导保留在下方，降级依据见 §3.1.3、§3.1.4。

#### 3.1.1 机制

`slave.mk:35` 是 `PYTHON_WHEELS_PATH = $(TARGET_PATH)/python-wheels/$(BLDENV)`，`BLDENV=resolute` 使 wheel 目标路径必然含 `resolute`，于是本 PR 新增的分支命中：

```make
if case "$@" in *trixie*sonic_chassisd*|*resolute*sonic_chassisd*) true;; *) false;; esac; then \
    echo "Skipping tests for sonic_chassisd on $(BLDENV) ($@)"; \
elif [ ! "$($*_TEST)" = "n" ] && [ ! "$(BUILD_SKIP_TEST)" = "y" ]; then \
    ... python -m pytest; \
```

命中后只 `echo`，`slave.mk:1107` 起的 pytest 分支永不执行。旁路已穷尽排除：

- `rules/sonic-chassisd.mk` 全文 6 行，无 `_TEST`、无任何测试钩子
- `dockers/*/cli-plugin-tests` 只有 dhcp-relay / dhcp-server / gnmi-sidecar / macsec / restapi-sidecar / telemetry-sidecar 六个目录，均无 chassisd
- `slave.mk`、`rules/`、`dockers/` 中无其他 chassisd pytest 调用

→ **本 PR 构建中 chassisd 用例数确定为 0。**

该跳过在 PR 的**首个提交** `45c3d0ef7f` 就已存在，故本 PR 历史上没有任何一次构建跑过它。

#### 3.1.2 PR 描述里的数字是准的，我们实跑复现了

在 `sonic-slave-resolute` 镜像里装齐 `_DEBS_DEPENDS`（`libyang3`、`libnl-*`、`libswsscommon`、`python3-swsscommon`）与全部 wheel 后跑 `python3 -m pytest`：

```text
FAILED tests/test_chassisd.py::test_daemon_run_smartswitch - AssertionError: ...
FAILED tests/test_chassisd.py::test_daemon_run_supervisor  - AssertionError: ...
=================== 2 failed, 216 passed, 1 warning in 6.64s ===================
```

**216 passed / 2 failed，且这 2 个确实是 multiprocessing 失败**——所以描述里的数字不是编的，作者手工跑过。

失败栈：

```text
scripts/chassisd:1858: in run  →  self.config_manager.task_stop()
sonic_py_common/task_base.py:47: in task_stop  →  self._task_process.join(...)
/usr/lib/python3.14/multiprocessing/process.py:155: AssertionError:
    can only join a started process
```

（我先前用「chassisd 目录 grep `multiprocessing` 零命中」质疑这两个失败，是查错了地方——multiprocessing 来自共享的 `sonic_py_common`，不在 chassisd 自身源码里。更正见 §8。）

#### 3.1.3 上游从不运行这套测试

链条闭合，逐环节可查：

1. `sonic_chassisd` wheel 的唯一消费者是 `rules/docker-platform-monitor.mk:24` 的 `$(DOCKER_PLATFORM_MONITOR)_PYTHON_WHEELS`
2. 而 `rules/docker-platform-monitor.mk:79` 是 `SONIC_TRIXIE_DOCKERS += $(DOCKER_PLATFORM_MONITOR)`，它不在任何 legacy docker 列表里（`SONIC_BOOKWORM_DOCKERS` 等 grep 零命中）
3. → 上游只在 `BLDENV=trixie` 那一趟构建这个 wheel（`Makefile:48-68` 的派发中，bookworm 那趟的 make 目标是字面量 `bookworm`，只有 trixie 那趟建真正的 `$@`）
4. → 上游 `slave.mk:1098` 的 `*trixie*sonic_chassisd*` 覆盖了它被构建的**全部**场景

**所以上游 `sonic-net/202605` 的 chassisd 测试是彻底关着的**，不存在「上游在 bookworm 上跑、只在 trixie 上关」这种部分启用。本 PR 把同一策略搬到 resolute，行为上与上游一致。

#### 3.1.4 上游为什么不开：查到的与查不到的

**查到的：**

- 跳过由上游 `bc13e6afa5` 引入（PR #26002「Support for BMC cards based on Aspeed 2720 - Phase 2」，2026-04-30 合入，Chandrasekaran Swaminathan / chander-nexthop）
- 那是个 58 文件、+1724/−484 的 BMC 平台 PR，**并未改动 `src/sonic-platform-daemons`**，所以失败不是它引入的
- **它没有留下任何理由**：commit message 通篇讲 BMC，一字未提测试跳过；PR #26002 的正文与 33 条评论里 `chassisd` / `skip.*test` / `pytest` 全部零命中
- 根因是 `sonic-py-common` 的一个缺失守卫：`task_base.py` 的 `task_run()` 在 `task_stopping_event` 已置位时提前返回，而 `task_stop()` 无条件调 `self._task_process.join(...)`，对「构造了但未 `start()`」的 `Process` 直接命中 CPython 的断言。`src/sonic-py-common` 是在树目录（非子模块），其 tree hash 在上游 202605 与本 PR 分支上**完全相同**（`1f1ce57acd`），上游同一文件同样没有守卫
- 这两个测试是 2024-12-16 由 sonic-platform-daemons `3fe8841`（#467「Added SmartSwitch support in chassisd and enabling chassisd」）加入的，比上游那次跳过早约 16 个月——不是「新测试当场就坏」

**查不到的 [推断]：** 为什么恰好在 trixie 上开始失败。上游 trixie slave 是 python3.13，bookworm 是 3.11，resolute 是 3.14；代码逐字节相同而结果不同，指向 Python 版本相关的 `multiprocessing` / mock 交互变化，但具体是哪个变更未定位（本地无 py3.11/3.13 对照环境）。

#### 3.1.5 处理

**代码不用改**——上游不开，我们也不必开，而且本 PR 已经和上游一致。

**描述要改**，两处措辞：

1. 「the 2 multiprocessing failures **excluded by the skip**」——skip 排除的是全部 218 个，不是那 2 个。应写成「suite skipped, mirroring upstream's trixie skip (`slave.mk:1098`)」
2. Verification 段不该把「216 passed」列成本次构建的产物，它来自手工运行。应注明是手工验证

**可选的后续**：真要恢复这套覆盖，正确入口是给 `sonic-py-common` 的 `task_stop()` 加一个「是否已 start」的守卫——那是 218 个用例里唯一挡路的东西，且修在共享库里对上游也有价值。这超出本 PR 范围，建议单开 issue。

### 3.2 `rules/swss.mk` 的 `nocheck` 理由不成立，真因是 Ubuntu 默认链接 flag 【已实测】

PR 描述给出的理由是「`p4orch_tests` 需要 redis-server，slave 容器不装，所以 check 永远过不了」「这不是 Debian→Ubuntu 迁移引入的」「redis 依赖是上游设计」。三项反证：

| 检查项 | 结果 |
|---|---|
| 上游 `sonic-slave-trixie/Dockerfile.j2` 有 redis-server 吗 | **没有**。只有 `:137` `libhiredis-dev`、pip 的 redis 客户端与 `mockredispy`，与 resolute 逐条一致 |
| 上游 `rules/swss.mk` 有 `nocheck` 吗 | 没有，也没有 `_DEB_BUILD_PROFILES` |
| 上游 `rules/config:398` | `BUILD_SKIP_TEST ?= n` |
| 上游 CI 覆盖过它吗 | `git grep BUILD_SKIP_TEST -- .azure-pipelines/` **零命中** |

即上游 trixie 在同样没有 redis 的 slave 里执行同一个 p4orch check。真因如下，逐环节在构建产物上验证：

1. **Ubuntu 与 Debian 的 dpkg vendor 差异**
   `/usr/share/perl5/Dpkg/Vendor/Ubuntu.pm:243` 有 `$flags->prepend('LDFLAGS', '-Wl,-Bsymbolic-functions')`；`Debian.pm` 中该字符串 **0 命中**。

2. **flag 确实进了链接命令**
   `target/debs/resolute/libswsscommon_1.0.0_amd64.deb.log:583`（`.so` 的 libtool link 行）带该 flag，全日志 16 处。

3. **后果：库内调用无法被插入**
   从 deb 解出 `libswsscommon.so.0.0.0`，`readelf -rW` 显示 294 个 `JUMP_SLOT` 重定位，**其中名为 `swss::` 的符号数为 0**（全部是 `_Znam`、`freeReplyObject`、`__errno_location` 这类外部符号）。也就是说所有库内 `swss::` 函数调用在链接期就绑定到库自身定义，不经 PLT。

   > 判据陷阱：`readelf -r` 会把类型名截断成 `R_X86_64_JUMP_SLO`（无尾部 `T`），`grep JUMP_SLOT` 会得到假零。正确判据是「JUMP_SLOT 中 `swss` 符号计数为 0」，不是「JUMP_SLOT 总数为 0」。

4. **触发链**
   `orchagent/p4orch/tests/test_main.cpp:211` 调 `swss::Logger::linkToDb` → `logger.cpp:159` → `:161 linkToDbWithOutput` → `:126 DBConnector db("CONFIG_DB", 0)`（真构造）→ `dbconnector.cpp:606` 抛出 `"Unable to connect to redis (unix-socket) - "`，与 PR 报告的错误文本**逐字一致**。

5. **fake 为何失效**
   `fake_dbconnector.cpp:38` 定义的正是 `DBConnector(const std::string&, unsigned int, bool)`，但它依赖 PLT 插入**库内部**那次调用；`-Bsymbolic-functions` 把这条路堵死。

这是**通用性破坏**，不是 p4orch 的特例：`tests/mock_tests/mock_dbconnector.cpp` 用的是同一套符号插入把戏，同样会被打掉。

#### 3.2.1 受控 A/B 实验：修法已验证，redis 根本不需要

上面第 5 步原本是推断。现在做成了单变量实验并跑通——**只编一次测试二进制，然后只换 `.so`**（剥不剥 flag 不改 ABI 与 SONAME，可直接替换）：

给 swss-common 的 `debian/rules` 在 `include /usr/share/dpkg/default.mk` **之前**插一行（必须在 include 前，否则 `dpkg-buildflags` 已算完 flag）：

```make
export DEB_LDFLAGS_MAINT_STRIP = -Wl,-Bsymbolic-functions
```

重编后先看链接层面的变化：

| 指标 | 原版 | 剥掉 flag |
|---|---|---|
| 构建日志中 `Bsymbolic-functions` 命中 | 16 | **0** |
| `.so` 里 `swss::` 符号的 `JUMP_SLOT` 跳板数 | **0** | **351** |
| 其中 `DBConnector` 构造函数 | 0 | **7** |

再用同一个 `p4orch_tests` 二进制，在**同一个容器、全程没有任何 redis 服务**的条件下，只切 `LD_LIBRARY_PATH`：

```text
── A 对照组（原版 .so，带 -Bsymbolic-functions）
terminate called after throwing an instance of 'std::system_error'
  what():  Unable to connect to redis (unix-socket) - No such file or directory(1): Cannot assign requested address
退出码: 134   (SIGABRT)

── B 实验组（剥掉 flag 的 .so）
[==========] 770 tests from 16 test suites ran. (70 ms total)
[  PASSED  ] 770 tests.
  YOU HAVE 3 DISABLED TESTS
退出码: 0
```

**结论坐实了三件事：**

1. **真因就是这个链接 flag。** 单变量、同二进制、同容器，只有 `.so` 不同，结果从 SIGABRT 变成全绿。
2. **redis 从头到尾不需要。** B 组 770 个用例全过，容器里没有 redis-server、没有 socket。PR 描述里「requires redis-server to run」「The redis dependency is upstream design」两句都是错的。
3. **修法有效且成本是一行。** 用例数也自洽：先前静态统计到 773 处 `TEST_F`/`TEST(`，减去 3 个 `DISABLED`，恰好 770。

这同时反过来支持了「上游 Debian 侧本来是过的」——`Debian.pm` 不加这个 flag，fake 就能生效。（仍未在 Debian 构建产物上直接观测 [推断]，但 A/B 已经把因果锁死在 flag 上。）

#### 3.2.2 处理

**首选：一行，只动超仓，净增 0 行，可以就放在本 PR 里。**

`DEB_LDFLAGS_MAINT_STRIP` 是 `dpkg-buildflags` **从环境读**的，`debian/rules` 里的 `export` 只是把它送进环境的一种方式。而 `slave.mk:938/939`（`SONIC_DPKG_DEBS` 的 recipe）本来就把 `${$*_BUILD_ENV}` 前置到 `dpkg-buildpackage` 命令行——`swss-common` 正是 `SONIC_DPKG_DEBS`（`rules/swss-common.mk:16`）。所以不需要碰子模块：

```diff
  # rules/swss-common.mk
+ $(LIBSWSSCOMMON)_BUILD_ENV = DEB_LDFLAGS_MAINT_STRIP="-Wl,-Bsymbolic-functions"

  # rules/swss.mk —— 删掉本 PR 新加的这行
- $(SWSS)_DEB_BUILD_OPTIONS = nocheck
```

**净差 0 行**（一行换一行）、**零子模块提交**、**零 gitlink bump**。`_BUILD_ENV` 是现成机制，仓库里已有 10+ 处先例（`platform/*/libsaithrift-dev.mk`、`platform/broadcom/sai-modules.mk` 等）。

已验证：`debian/rules` 保持与仓库逐字节一致（`diff -q` 确认），只经环境变量重编 swss-common，产出与改 `debian/rules` 那条路**完全相同**——构建日志 Bsymbolic 命中 0、`swss::` JUMP_SLOT 跳板 351、DBConnector 构造 7 个，且 `hardening=+all` 未受影响（`.so` 仍带 `BIND_NOW`）。

> 变体选择：`DEB_LDFLAGS_STRIP`（构建者通道）在语义上比 `DEB_LDFLAGS_MAINT_STRIP`（维护者通道）更贴合「我们是构建方」的身份，两者在 `dpkg-buildflags --get LDFLAGS` 层面产出一致。但完整重编只在 `MAINT_STRIP` 上跑过，所以推荐先用它；换 `STRIP` 需要再验一次。

**次选（若坚持改在包内）**：给 swss-common 的 `debian/rules` 在 `include /usr/share/dpkg/default.mk` 之前加那一行。这条路要按 AGENTS.md 的 Submodules 规则走——先提交到 `canonical/sonic-swss-common:202605_resolute`，再 bump gitlink，且得单开 PR。好处是对上游也有价值（Ubuntu 上所有靠符号覆盖的 C++ 单测都受同一影响，`tests/mock_tests/mock_dbconnector.cpp` 用的是同一套把戏），代价是流程重得多。**建议：先用超仓一行解锁测试，再把包内修法作为上游贡献单独推进。**

**若本 PR 不做**：至少删掉描述里那两句因果断言，换成指向本节的说明与 TODO。保留 `nocheck` 本身可以接受，但不能带着错误的理由留在仓库里。

**这个改法的代价，以及为什么可以接受。** `DEB_LDFLAGS_MAINT_STRIP` 作用于整个包，所以**出厂的 `libswsscommon.so` 也会失去这个 flag**，不只是测试时。两个后果：

- 库内自家函数调用多一层 PLT 间跳。理论上有开销，实践中可忽略——这是绝大多数发行版库的常态。
- 运行时 `swss::` 符号变得可被外部覆盖。这既是测试需要的，也确实是行为变化。

关键在于：**这不是引入分歧，而是消除分歧。** Debian 的 `Dpkg/Vendor/Debian.pm` 本来就不加这个 flag，所以上游 Debian trixie 出厂的 `libswsscommon.so` 一直是「有 PLT 跳板、可被覆盖」的形态。剥掉它之后，resolute 的库和上游 Debian 的库在这一点上一致；不剥反而是 resolute 独有的偏差——而这个偏差是 Ubuntu 的 vendor 默认值悄悄带进来的，没人主动选择过。

按同样的逻辑，这一行也可以考虑放到 slave 镜像的全局构建 flag 里（参见 [slave 镜像全局构建标志覆盖](2026-08-24-resolute-port-final-state-and-pitfalls-zh.md) 记录的既有做法），使所有自建 C++ 包都恢复 Debian 语义。但那影响面大得多，需要单独评估，不应搭在本 PR 或 swss-common 的修复上。

### 3.3 `AGENTS.md` 两条「已知偏差」与仓库事实相反 【三方一致】

`AGENTS.md:36-38` 新增（base 中无此段）：

> libnl3 uses injected API aliases instead of upstream's `rtnl_route_get_nhid`; flashrom and sedutil were de-forked to stock Ubuntu debs

| 陈述 | 仓库实际 |
|---|---|
| libnl3 用注入的 API 别名 | **说反了。** `rules/libnl3.mk:3-5` 的注释明文写着改用 `SONIC_ONLINE_DEBS` 拉原生 Ubuntu 3.12.0-2，「SONiC's only patch (nh-id alias) is obsolete — sonic-swss now uses the stock `rtnl_route_get_nhid` spelling」；`:61` 走 ONLINE_DEBS；swss gitlink `5328b765` 的 `fpmsyncd/routesync.cpp:2201` 确实用 stock 拼写。`src/libnl3/patch/0003-Adding-support-for-RTA_NH_ID-attribute.patch` 是无人消费的死文件 |
| flashrom 已 de-fork 成原生 deb | **不成立。** `rules/flashrom.mk:10` 是 `SONIC_MAKE_DEBS += $(FLASHROM)`，0.9.7 源构建，`src/flashrom/patch/series` 有 3 个补丁。**同一 PR 的 `.gitignore:141 src/flashrom/flashrom-*/` 自证其为源构建** |
| sedutil 已 de-fork | 属实（`rules/sedutil.mk:8` `SONIC_ONLINE_DEBS`） |

`AGENTS.md` 是给后续 AI 与人的指令文件，错误陈述会直接误导下一次修改。

### 3.4 `AGENTS.md` 的 Scope 段禁止的内容，正是本 PR 新加的内容

`AGENTS.md:5-7`（从旧文件 `:3-8` 照搬）明令：

> limited to durable build, editing, and review practices; do not duplicate plans, **progress tracking**, design rationale, or migration reports here

而 `:22-43` 新增的正是这类内容：「the migration is complete」「Platform enablement is limited to `vs` … and `broadcom`」「FIPS is unsupported」以及整个 known-deviations 块。核查确认这几条状态断言在旧文件里 grep 不到，是本 PR 新引入的。

§3.3 那两条错误正属这类状态内容——状态写进「持久规则」文件必然腐化，这里是当场就错。**删掉整个 known-deviations 块比逐条改对更符合该文件自己的规矩。**

**合并成一个动作**：删掉 `:22-43` 的状态块（顺带解掉 §3.3 的两处事实错误），再按 §3.5 把那句 gitlink 判据加回去。一删一加，`AGENTS.md` 就只剩持久规则。

### 3.5 `AGENTS.md` 丢了一句 gitlink 判据 【已逐行核对两版原文】

重写整体是收紧的，还新增两条好规则（同步用 rebase 而非 ff + `scripts/submodule-ff-audit.sh`；`.gitmodules` 必须 https 且就地改 section）。真正的损失只有一句。

base `:79-94` 枚举了 gitlink commit 的三种状态——① 上游 commit + 上游 URL（canonical 没改过该子模块）；② Canonical commit，已推到 `canonical/<sub>:202605_resolute`（`sonic-net/` 上不存在，URL 必须指 canonical）；③ Canonical commit **还没推**（只在本地工作树，任何 clone 都初始化不了）——并给出判据：**「The state is not determined by the URL alone」**。

新版 `:71-74` 保留了「该推哪里」（非上游 commit → canonical，绝不 `sonic-net/`），丢的是「**怎么知道自己在哪个状态**」。这是实操差别：URL 写着 `sonic-net/` 并不意味着 gitlink 是上游 commit，②③ 都能顶着上游 URL 存在，而 ③ 会让 clone 直接失败——这个坑已经踩过一次（见 [四个 resolute 缺陷及与上游全状态对比](2026-07-27-resolute-defect-fixes-and-upstream-state-comparison-zh.md) 的子模块章节）。

**处理**：把那句判据加回去即可，三态枚举可省。这与 §3.4 是同一个动作——该文件该留的是这类持久判据，而不是会腐化的状态清单。

（另有三条与 gitlink 无关的护栏也被删了：内核 ABI 保护、迁移不确定时参照 `feature_noble_build` 的 Bookworm→Noble、以及「英文文档是 source of truth」+ 5 条权威文档链接。是否恢复可独立决定。）

---

## 4. 便宜且该做

### 4.1 `slave.mk:889` 的 per-package 选项缺口——**上游同病，本 PR 不背这个锅** 【已核对上游】

> **本条经复核后降级。** 我最初把它写成「地雷、且本 PR 让它更近了」，并断言「p4lang-pi 的 check 在此环境已知会失败」。核对上游与构建产物后：缺口在上游**逐字相同**，上游默认值也一样，而那句 p4lang-pi 的断言**没有任何依据，已撤回**。

**缺口本身是真的。** 两条 deb 构建 recipe 能力不对称：

| 路径 | 我们的行 | 上游对应行 | 传的 `DEB_BUILD_OPTIONS` |
|---|---|---|---|
| `SONIC_DPKG_DEBS` | `slave.mk:938/939` | `:932/933` | `"${DEB_BUILD_OPTIONS_GENERIC} ${$*_DEB_BUILD_OPTIONS}"` |
| `SONIC_MAKE_DEBS` | `slave.mk:889` | `:883` | `"${DEB_BUILD_OPTIONS_GENERIC}"` ——**无 per-package 部分** |

所以 `rules/swss.mk` 那种 `$(PKG)_DEB_BUILD_OPTIONS = nocheck` 写法，用在 53 个 `SONIC_MAKE_DEBS` 包上会被**静默忽略**——不报错、不生效。这个静默是它值得修的主要理由。

**但上游处境完全相同，不是本 PR 造成的：**

- 上游 `slave.mk:883` 与我们 `:889` **同样没有** `${$*_DEB_BUILD_OPTIONS}`
- 上游 `rules/config:398` 也是 `BUILD_SKIP_TEST ?= n`——**上游同样没有全局 `nocheck` 兜底**
- 本 PR 的 `slave.mk` 改动只有 3 行（`bookworm trixie` → 加 `resolute`、chassisd 跳过），**没碰 `:889`**

也就是说：上游带着同一个缺口、同一个默认值，跑着它全部 53 个 MAKE_DEBS 包的 check。本 PR 只是把 resolute 恢复到上游的默认状态。

**撤回的断言。** 我原先写「p4lang-pi 的 check 在此环境已知会失败」，据此说这是活跃地雷。实际：`target/debs/resolute/` 下 `p4lang*` / `dash-sai*` / `libpi*` **全部为空——从未在 resolute 上构建过**，因此不存在「已知会失败」的证据。而在上游 trixie 上，`syncd-vs.mk:7` 的 `bookworm trixie` 过滤是命中的，所以 `DASH_SAI`（`rules/dash-sai.mk:13`，正是 `SONIC_MAKE_DEBS`）连同 p4lang-pi 一直在上游构建图里、且 check 开着——上游过得去。

**仍然成立的那半句**：`syncd-vs.mk:7` 用的 `bookworm trixie` 过滤模式，与本 PR 在 `slave.mk:1102` 改的是同一个模式。若将来有人为一致性把 `resolute` 也加进 `syncd-vs.mk:7`，DASH_SAI 一族会进入 resolute 的构建图；届时若某个包的 check 在 Ubuntu 上失败（如同 §3.2 的 swss），**将没有 per-package 出口可用**。这是「以后可能咬人」，不是「现在有 bug」。

**处理**：仍建议加那一行，理由是消除静默忽略、与 `:938/939` 对齐；一行、当前零行为变化（没有 MAKE_DEBS 包设置该变量）。但**这是上游共有的既存缺口，属于可选的顺手改进，不该作为本 PR 的合并条件**——真要修，修在上游更合适。

### 4.2 `.gitignore` 覆盖不全 【已实测】

本 PR 新增 `.gitignore:59` 的 `sonic-slave*/files/`，用来忽略构建时渲染出来的 apt 配置。但**生成这些文件的脚本覆盖三类镜像，而这条规则只覆盖一类**。

`scripts/prepare_docker_buildinfo.sh:46` 的守卫：

```sh
if [[ "$IMAGENAME" == sonic-slave-* ]] || [[ "$IMAGENAME" == docker-base-* ]] || [[ "$IMAGENAME" == docker-ptf ]]; then
    ...
    mkdir -p "${DOCKERFILE_PATH}/files/apt/apt.conf.d"
```

三个分支都会在各自的 `${DOCKERFILE_PATH}` 下创建 `files/apt/apt.conf.d/`。而 `sonic-slave*` 只是其中一支——`docker-base-*` 在 `dockers/` 下，`docker-ptf` 也在 `dockers/` 下，两者都不匹配 `sonic-slave*/files/`。

用 PR 的 `.gitignore` 跑 `git check-ignore -v --no-index` 实测：

| 路径 | 结果 |
|---|---|
| `sonic-slave-resolute/files/apt/apt.conf.d/apt-clean` | 命中 `.gitignore:59` ✓ |
| `dockers/docker-base-resolute/files/apt/apt.conf.d/apt-clean` | **NOT IGNORED** |
| `dockers/docker-ptf/files/apt/apt.conf.d/apt-clean` | **NOT IGNORED** |

**后果**：这两类镜像构建后会留下未跟踪文件，`git status` 变脏；若有人 `git add -A`，渲染产物会被提交进仓库。这正是本 PR 想解决的问题，只是漏了三分之二。

**修法**：把规则改成覆盖三类，例如加两条

```
dockers/docker-base-*/files/
dockers/docker-ptf/files/
```

**一处需要精确的地方**：`docker-ptf-sai` **不受影响**。脚本用的是精确相等 `== docker-ptf`（不是 `docker-ptf*`），所以 `docker-ptf-sai` 走不到那个分支，不会生成该目录——规则不必也不应该用 `docker-ptf*` 通配，否则会掩盖别的东西。

### 4.3 `src/sonic-bmpcfgd/.gitignore` 应新建，而非往根文件加条目

仓库有 **40 个** `src/<pkg>/.gitignore`。遍历所有带 `setup.py` 的 `src/*` 目录后确认：**`src/sonic-bmpcfgd` 是全仓唯一没有 `.gitignore` 的在树 Python 包**。样板见 `src/sonic-py-common/.gitignore`（`*.egg-info/`、`build/`、`dist/`、`.eggs/`…）。

```diff
 # 从根 .gitignore 移除
-src/sonic-bmpcfgd/build/
-src/sonic-bmpcfgd/*.egg-info

 # 新建 src/sonic-bmpcfgd/.gitignore，照抄 src/sonic-py-common/.gitignore
+*.egg-info/
+build/
+dist/
```

其余四条具名解压目录（`src/flashrom/flashrom-*/`、`src/libyang3-py3/libyang-python/`、`src/rdb-cli/librdb/`、`src/sonic-eventd/eventdb`）留在根文件可接受——它们是「拉取型源」的解压残留，与包内 build 产物不同类。

> 这一条我在首轮判错过，理由与更正见 §8。

### 4.4 `src/sonic-eventd/Makefile:114` 的 `clean` 漏了 `$(EVENTDB_TARGET)`

该行列了 `EVENTD_TARGET`、`OBJS`、`EVENTD_TOOL`、`TOOL_OBJS`、`RSYSLOG-PLUGIN_*`、`EVENTD_TEST`、`TEST_OBJS`、`EVENTDB_TEST`、`EVENTDB_TEST_OBJS`、`RSYSLOG-PLUGIN_TEST`、`C_DEPS`——**唯独漏了 `EVENTDB_TARGET`**（定义在 `:11`，即 `eventdb`，由 `:50` 链接产出）。`dpkg-buildpackage -tc` 会执行 clean，补一个变量残留即消。上游 `sonic-net/202605` 同样漏。

**这比往 `.gitignore` 加条目正确**——后者只是把一个未清理的二进制藏起来。

---

## 5. 构建缓存（中低，条件性）【三方一致】

`BUILD_SKIP_TEST` 不参与任何缓存键：

- `Makefile.cache:110` 的 `SONIC_COMMON_FILES_LIST` 仅 `.platform rules/functions Makefile.cache`，**不含 `rules/config`**
- `Makefile.cache:112` 的 `SONIC_COMMON_FLAGS_LIST` 为 `RECIPE_VER / PLATFORM / ARCH / BLDENV / MIRROR_URLS / MIRROR_SECURITY_URLS / DEBUGGING_ON / PROFILING_ON / ENABLE_SYNCD_RPC`，**不含 `BUILD_SKIP_TEST`**

完整链路已走通：缓存文件名 `<pkg>-<DEP_MOD_SHA>-<MOD_HASH>.tgz`（`:280`/`:329`）← `MOD_HASH` 由 `.flags` + `.dep.sha` + `.smdep.smsha` 三者 hash（`:205-211`）← `_DEP_FLAGS := $(SONIC_COMMON_FLAGS_LIST)`（`:456`）写入 `<pkg>.flags`（`:466`、`:553-554`）。磁盘实物印证：

```console
$ cat target/python-wheels/resolute/sonic_chassisd-1.0-py3-none-any.whl.flags
1 broadcom amd64 resolute
```

`rules/sonic-utilities.dep` 与 `rules/swss.dep` 也逐行印证同一结论。

**三点收窄，都不是纯负面：**

1. **默认路径不受影响。** `rules/config:156` 是 `SONIC_DPKG_CACHE_METHOD ?= none`，只在显式开缓存时发生。（本机未跟踪的 `rules/config.user` 恰好设了 `rwcache`，所以本地开发环境里这个场景是激活的，见 §9。）
2. **不是空操作。** 本 PR 使三类包自然失效并真跑了测试——swss（`rules/swss.dep:3` 的 `DEP_FILES` 含 `rules/swss.mk`）、sonic-yang-models（`.dep` 里 `SMDEP_FILES := $(addprefix $(SPATH)/,$(shell cd $(SPATH) && git ls-files))` 含被改的测试文件，并经 `DEP_MOD_SHA` 传导到 sonic-yang-mgmt、sonic-utilities、libswsscommon）、asyncsnmp（gitlink 变了）。会被静默跳过的只是输入未变的包：sonic-platform-common、sonic-host-services、sonic-py-common、sonic-config-engine，以及 libyang3 / lldpd / sonic-fib 的 deb check 和未变 docker 的 cli-plugin-tests。
3. **`Makefile.cache` 与 `sonic-net/202605` 逐字节相同**（`git diff` 无输出）。上游自己的 `SONIC_CACHE_RECIPE_VER_BASELINE := 348388b6…` 也已 ≠ 上游 `slave.mk` blob `7048fd87`，即「守卫陈旧」是与上游共有的既存状态，不该记在本 PR 头上。

**建议改为：先定目标，再选做法。**

| 目标 | 做法 | 代价 |
|---|---|---|
| 产物必须经过测试 | 把 `BUILD_SKIP_TEST` 加进 `SONIC_COMMON_FLAGS_LIST` | `=y` / `=n` 两种构建不再共享缓存；偏离 `Makefile.cache:71-80` 的上游设计 |
| 只要守卫别一直报警 | 按该文件自己的规则（`:90-92`）把 baseline 更新到 `a7de9659ce`，**不** bump `RECIPE_VER` | 无 |

无论选哪种，PR 描述的 Verification 段都该标明哪些 suite 是本次真跑、哪些可能来自缓存。

---

## 6. 低 / 需在描述中说明

### 6.1 resolute wheel 后端从 `setup.py bdist_wheel` 换成 `python -m build -n` 【已实测】

`slave.mk:1102` 把 `resolute` 加进 `$(filter bookworm trixie,$(BLDENV))` 的连带效果，不只是打开测试。PR 前 resolute 落到 `else` 分支走 `setup.py bdist_wheel`（磁盘日志 `sonic_chassisd-*.whl.log:51` 有 `running bdist_wheel`），PR 后走 `slave.mk:1112` 的 `python3 -m build -n`。slave 镜像里 `build 1.4.0` 的 help 原文确认默认行为是先建 sdist、再从 sdist 建 wheel。

**但风险实测为零。** 在真 slave 镜像里用 `python3 -m build -n` 重建并逐条比对 wheel 文件清单：

| 包 | 旧（bdist_wheel） | 新（-m build） | 缺失 | 多出 |
|---|---|---|---|---|
| sonic-chassisd | 15 | 15 | 0 | 0 |
| sonic-config-engine | 15 | 15 | 0 | 0 |
| sonic-host-services | 33 | 33 | 0 | 0 |
| sonic-platform-common | 186 | 186 | 0 | 0 |
| sonic-utilities | 1049 | 1049 | 0 | 0 |

sdist 往返是无损的。**只需在描述里补一句说明这个连带效果**，不是风险。

### 6.2 yang 负例断言的版本敏感性——**非缺陷，按维护者决定结案** 【已实测两个版本】

> **本条经维护者决定关闭。** 我最初把它列为「脆化 + 与上游分叉」的低优问题。维护者明确：**resolute 分支不再维护对上游 libyang 版本的兼容**。据此两条理由都不成立（见下方「为什么不成立」）。机制说明保留，因为「为什么报错文本变了」本身是有用的参考。

**改动内容**就是两个字典项：

```diff
-            'DateTime': ['Invalid date-and-time'],
-            'IPv4': ['Failed to convert IPv4 address'],
+            'DateTime': ['Unsatisfied pattern', r'\d{4}-\d{2}-\d{2}T'],
+            'IPv4': ['Unsatisfied pattern', r'25[0-5])\.){3}'],
```

`test_yang_model.py` 喂故意非法的数据给 YANG 模型，检查报错文本符合预期；`:234` 的匹配是纯子串 AND：

```python
elif (sum(1 for str in eStr if str not in s) == 0):
```

**为什么报错文本变了。** 用 `yanglint 3.13.6` 喂个非法时间戳，实际输出：

```text
libyang err : Unsatisfied pattern - "not-a-date" does not conform to
"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[\+\-]\d{2}:\d{2})". (/demo:c/ts)
```

**libyang 把 pattern 本身回显进了报错。** 3.13.6 的类型插件在尝试转换**之前**先校验 pattern（`src/plugins_types/date_and_time.c:112` 调 `lyplg_type_validate_patterns`），所以报错从「按 date-and-time 解析失败」变成「不符合这条 pattern，pattern 是……」。旧断言自然不再是子串——**本 PR 的改动是必需且正确的。**

两版对照（取 libyang 上游源码实测）：

| | `lyplg_type_validate_patterns` | 报错文本 |
|---|---|---|
| **v3.12.2**（上游 SONiC 所钉） | `date_and_time.c` 0 处、`ipv4_address_no_zone.c` 0 处 | `ipv4_address_no_zone.c:97` = `"Failed to convert IPv4 address \"%s\"."` |
| **v3.13.6**（`rules/libyang3.mk:13` 所钉） | `date_and_time.c:112` 1 处 | `Unsatisfied pattern - ... does not conform to ...` |

注意：**3.12.2 的报错文本正是本 PR 删掉的旧断言**——两版行为差异确凿。

#### 为什么两条原始理由都不成立

1. **「与上游分叉、共享文件在上游会失败」** —— 不适用。resolute 不维护对上游 libyang 版本的兼容，因此「在 3.12.2 上失败」是预期而非缺陷；2 行的有意分叉在本分支的分叉总量里属噪声级别。
2. **「断言耦合第三方模型的正则文本，26 个用例脆化」** —— 判重了。DateTime 那段正则来自 libyang 自带的 `models/ietf-yang-types@2013-07-15.yang:302`（我们 `yang-models/` 下 144 个文件全是 `sonic-*`、零个 `ietf-*`），但 `rules/libyang3.mk:13` 用 `SONIC_MAKE_DEBS` **显式钉住 3.13.6**，所以该文本只可能在我们主动 bump libyang 时变化。那是受控事件，届时用例报红正是测试应有的行为——属版本敏感断言，不是脆化。

#### 唯一残留（不建议处理）

`r'25[0-5])\.){3}'` 括号不配对，读起来像坏掉的正则。它实际只作纯子串使用，而 `yang-models/sonic-types.yang:30` 回显出的 pattern 中确实含这一段，功能无误。纯可读性，不值得动。

### 6.3 `src/sonic-snmpagent` 子模块：泄漏确实是本次提交引入的 【已核对提交 diff】

**直接回答：是我们引入的。** 不是继承上游的既有问题。

gitlink 本身合规：`.gitmodules` 为 canonical HTTPS，`955facf` 仅在 `canonical/sonic-snmpagent:202605_resolute` 可达，`529cd5d..955facf` 为严格 ff（1 个提交）。

那个提交 `955facf fix(tests): use new_event_loop() for py3.14 compatibility` 只有 2 行改动、动了 2 个文件，都是同一个机械替换 `get_event_loop()` → `new_event_loop()`：

| 文件 | 改动前 | 改动前是否有 `close()` | 改动后状态 |
|---|---|---|---|
| `tests/test_rfc1213.py` | `:71` `get_event_loop()` | **有**，`:73` `loop.close()` | 正确——拥有并关闭 |
| `tests/test_agent.py` | `:20` `get_event_loop()` | **无**（全文 0 处 `close()`） | **泄漏** |

**语义变化就是泄漏的来源。** `get_event_loop()` 返回的是解释器隐式创建的 loop，调用方不拥有它，不关闭是惯例；`new_event_loop()` 则**把所有权交给调用方**，不关就泄漏，并在 `ResourceWarning` 打开时报 unclosed event loop。所以：

- 改动**前**：`test_agent.py` 没有自己拥有的 loop，无需 `close()`，没有问题
- 改动**后**：它拥有一个新 loop 且从不关闭 → **新增的资源泄漏**

这是同一个 2 行提交内部的**不对称**：`test_rfc1213.py` 恰好本来就有 `close()`（`:71-73` 把调用点夹在中间），所以替换后是对的；`test_agent.py` 没有，替换后就漏了。作者对两个文件做了同样的机械替换，只有一个文件本来具备配套条件。

**影响有限但不为零**：在 `-W error` 或 pytest `filterwarnings = error` 下，`ResourceWarning` 会变成失败，且因为 GC 时机不定，**失败会归属到当时正在跑的任意用例上**，很难查。当前配置下只是告警。

**修法**：`test_agent.py` 补一个 `event_loop.close()`（或用 `try/finally`），与同提交的 `test_rfc1213.py` 对齐。

**另一处：提交信息不准确。** 子模块提交写「Python 3.12 removed the implicit creation」——3.12 只是加了弃用告警，**3.14 才 raise**。父仓提交信息写的 3.14 是对的，子模块这条应改。

顺带证伪该提交信息里的一个担忧：它提到「`Agent` 内部还会调 `get_event_loop()`」。实测 `ax_interface/` 与 `sonic_ax_impl/` 两个生产代码目录中 `get_event_loop` **零命中**（`new_event_loop`/`get_event_loop` 全仓只出现在那 2 个测试文件里），所以不存在功能影响，纯粹是资源泄漏。

### 6.4 范围蔓延

`64aae6026d docs: update AGENTS.md`（+82 / −163，整篇重写，commit body 为空）与「re-enable tests」无关，违反本 PR 自己 `AGENTS.md` 里的「Keep changes minimal and scoped」。建议拆成独立 PR。

### 6.5 验证只覆盖 broadcom

`BUILD_SKIP_TEST` 是全局开关，而 `AGENTS.md:31-33` 并列声明 `vs` 同为支持平台，vs 侧的 check 阶段未验证。

### 6.6 force-rewrite 陈述

`AGENTS.md:16-18` 沿用了「上游 date-named 分支 can be force-rewritten with an identical tree，所以用 `git merge-base` 确认」。此说法与已结案的取证相反（见 [2026-08-31 工作流取证](2026-08-31-sonic-202605-workflow-forensics-zh.md)：上游 Activity API 显示 194 次 `pr_merge` + 1 次 `branch_creation`，`force_push` 为 0；分叉源于我们自己在 2026-07-06 就地跑的 `git filter-repo --force`）。非本 PR 引入（旧 `:171` 已有），但整篇重写时是纠正它的最好时机。

### 6.7 琐碎

- `AGENTS.md:10-11`：段落正文后紧跟 `## Branches`，缺空行
- `.gitignore:52` 的旧条目 `installer/x86_64/platforms/` 与 `build_image.sh:78-83` 实际使用的 `./installer/platforms/` 已不符（上游同，属既有死条目，加新条目时可顺手替换而非并存）

---

## 7. 明确排除的误报

以下曾在各轮审阅中被提出，核查后确认**不是问题**。记录在此以免后续重复讨论。

| 曾被提出 | 排除依据 |
|---|---|
| `nocheck` 废掉 10 个测试二进制 | `tests` 已被 swss `296b9cc7` 移出 SUBDIRS（`Makefile.am:1` 的注释与该提交的 diff 均确认）；`tests/mock_tests` 被 `configure.ac:175` 的 `AM_COND_IF([HAVE_SAI],[],[AC_CONFIG_FILES([tests/mock_tests/Makefile])])` 挡住——deb 构建必有 libsai。唯一可达是 `orchagent/Makefile.am:11` 的 `p4orch/tests`（16 个 `*_test.cpp`、773 处 `TEST_F`/`TEST(`） |
| `nocheck` 使测试代码的编译错误也被掩盖 | 构建日志证伪：`Making all in p4orch/tests` 1 次、`-o p4orch_tests` 链接 2 次、`make check` **0 次**。`p4orch_tests` 是 `noinst_PROGRAMS`，由 `dh_auto_build` 编译，`nocheck` 只挡 `dh_auto_test`（`debian/rules` 无 `override_dh_auto_test`） |
| p4orch 测试自身的 `DBConnector("APPL_DB", 0)` 需要 redis | `p4orch_test.cpp:200` 匹配的是 `fake_dbconnector.cpp:38`，而该文件就在 `Makefile.am:62` 的 `p4orch_tests_SOURCES` 里——同一可执行文件内、来自测试自身编译单元的调用在静态链接期绑到 fake 定义，不走 PLT、不碰 redis。`ZmqServer("endpoint")` 同理（`fake_zmqserver.cpp` 在 `:70`）。**问题只出在库内部那次调用，见 §3.2** |
| `tests/` 与 `mock_tests` 需要真 redis | `tests/mock_tests/mock_dbconnector.cpp:18-40` 用 `calloc` 伪造 `redisContext` 并 `socket(AF_UNIX, SOCK_DGRAM, 0)`，从不连接；根 `tests/` 的三个程序（`swssnet_ut` / `request_parser_ut` / `quoted_ut`）`DBConnector` 计数全为 0。sonic-swss standalone CI（`.azure-pipelines/build-template.yml:120-125`）装 redis 的原因 [未证实]，但不是为了 deb check |
| `?= n` 仍可被命令行/环境覆盖，是缺陷 | 这是 `?=` 的定义，且与上游 `rules/config:398` 一字不差 |
| 「only enabled build environment」与 `Makefile` 矛盾 | 原文自己点名了 `NOTRIXIE=1`、`NOBOOKWORM=1`，而 `Makefile:7-8` 的 `?= 1` 正是该含义，不构成矛盾 |
| 交叉构建路径受影响 | `Makefile.work:176-178` 需显式设置 `CROSS_BLDENV`；resolute 只启用 `vs` 与 `broadcom` 两个 amd64 平台，无人走该路径，且本 PR 未触碰 |
| gitlink 不合规 | 见 §6.3 |
| `AGENTS.md` 缺空行触发 markdownlint MD022 | 全库无 markdownlint 配置或 workflow，无 linter 会报 |
| 包级 artifact 放根 `.gitignore` 符合仓库惯例 | **首轮我判错**，见 §4.3 与 §8 |
| 其他 deb 的 check 会因 `=n` 需要 redis 而炸 | swss-common `tests/Makefile.am:1` 是 `bin_PROGRAMS += tests/tests`，无 `TESTS`；sonic-eventd `debian/rules` 是裸 `dh`，其 `Makefile:38` 的 `test` 只链接测试二进制不执行 |

---

## 8. 审阅过程中的自我更正

留档，因为这些错误的产生方式比结论本身更值得记住。

1. **「包级 artifact 放根文件符合惯例」判错。** 依据是根文件里有 `src/sonic-frr/.sonic-frr-patch-*.sha1` 与 `src/**/debian/*`——但那是跨包通配和一个特例，不是这类产物的主导模式。实际有 40 个每包 `.gitignore`，`sonic-bmpcfgd` 是全仓唯一例外。**教训：判定「惯例」要数样本，不能挑一两个例子。**
2. **「`tests/` 与 `mock_tests` 确实要 redis」说错。** 那两处也是纯 mock。此更正反而加强了 §3.2 的根因——被打掉的是通用的符号插入机制。
3. **中途报出「零 JUMP_SLOT」是假零。** `readelf -r` 把类型名截断成 `R_X86_64_JUMP_SLO`。**教训：对工具输出做 grep 计数前，先看一眼原始输出长什么样。**
4. **p4orch 规模数字写错。** 说「24 个 `*_test.cpp`」，实际是 16 个文件、773 个用例；24 是 `grep ^TEST(` 的行数被当成了文件数。
5. **§4.1 的定性摇摆两次。** 先说「活跃 bug」（漏了 `INCLUDE_VS_DASH_SAI ?= y` 默认开这条路径），后说「潜在」（又漏了它被 `syncd-vs.mk:7` 挡住），最终定为「地雷」。
6. **`python -m build` 的丢文件风险先断言后证伪。** 机制正确，影响实测为零；「`setuptools_scm` 的 git file-finder 失败正是丢文件的条件」这条推论无证据支撑，已撤回。**教训：机制成立不等于后果发生，能测就去测。**
7. **chassisd 那条整体写重了，且质疑的方式也错了。** 三个审阅者独立收敛到「代码与描述冲突」，我照单采纳，但少问了一句「上游开了吗」——补查后发现上游同样不运行（§3.1.3），代码根本不用改。另外我用「chassisd 目录 grep `multiprocessing` 零命中」去质疑「2 个 multiprocessing 失败」，是查错了地方：multiprocessing 来自共享的 `sonic_py_common/task_base.py`，不在被测包自身源码里；实跑结果与描述完全吻合。**两条教训：（一）「多方一致」不构成正确性证据，三方可以一致地漏掉同一个前置问题；（二）在 fork 里挑上游继承来的行为之前，先确认上游的状态是什么。**

---

## 9. 操作提醒

**本地 `rules/config.user` 会静默盖掉本 PR 的默认值。** 该文件在 `.gitignore:8` 内、未被跟踪，但在 `Makefile.work:154` 与 `slave.mk:165` 于 `rules/config` **之后** `-include`，且以硬 `=` 写着 `BUILD_SKIP_TEST = y`。合入后 `?= n` 在这类环境里不生效，「合了就有测试」不自动成立。同一文件设了 `SONIC_DPKG_CACHE_METHOD = rwcache`，所以 §5 描述的场景在本地开发环境是激活的。

**调用 Codex 时显式指定 effort。** `~/.codex/config.toml` 的 `model_reasoning_effort = "low"` 会被 `codex exec` 继承。本次第 2 轮因此跑成了 low，产出明显偏薄（3 条，其中 1 条是过度解读）。`codex exec -m gpt-5.6-sol -c model_reasoning_effort="xhigh"` 才是想要的；运行日志头部会打印 `reasoning effort:`，可据此确认。另注：`humanize` 插件的 `ask-codex.sh` 包装脚本会传 `--full-auto`，codex-cli 0.149.1 不识别该参数而直接退出（exit 2），需绕过包装直接调 `codex exec`。

---

## 10. 附录

### 10.1 可直接提给作者的最小集

若只提三条，选这三条：

1. **§3.2** `nocheck` 的理由不成立，真因是 Ubuntu 的 `-Wl,-Bsymbolic-functions`；A/B 实验已证实修法可行——**只动超仓一行、净差 0 行**，恢复 770 个用例，且不需要 redis
2. **§3.3** `AGENTS.md` libnl3 / flashrom 两条写反（三方一致，且 PR 自己的 `.gitignore` 自证）
3. **§4.1** `slave.mk:889` 补一行 `${$*_DEB_BUILD_OPTIONS}`（一行成本，拆掉一颗地雷）

§3.1（chassisd）只需改描述措辞，可以放在同一条评论里带过，不必单列。

### 10.2 关键取证命令

```sh
R=/home/sheldon-qi/sonic-buildimage-resolute

# §3.1.3 上游只在 trixie 下构建 chassisd wheel，故其跳过覆盖全部场景
git -C $R grep -n SONIC_CHASSISD_PY3 sonic-net/202605 -- rules/ platform/ dockers/
git -C $R show sonic-net/202605:rules/docker-platform-monitor.mk | grep -nE 'TRIXIE_DOCKERS|PYTHON_WHEELS'

# §3.1.2 实跑 chassisd 测试（容器内需 root 装 deb 依赖）
#   装 libyang3 / libnl-* / libswsscommon / python3-swsscommon 再 ldconfig，
#   pip 装 target/python-wheels/resolute/*.whl 与 ".[testing]"，然后 python3 -m pytest -q
#   期望：2 failed, 216 passed

# §3.2 链接 flag 的 vendor 差异
grep -n Bsymbolic /usr/share/perl5/Dpkg/Vendor/Ubuntu.pm
grep -c Bsymbolic /usr/share/perl5/Dpkg/Vendor/Debian.pm     # 期望 0

# §3.2 后果：JUMP_SLOT 中没有库自身符号
dpkg-deb -x $R/target/debs/resolute/libswsscommon_1.0.0_amd64.deb /tmp/swsc
readelf -rW /tmp/swsc/usr/lib/x86_64-linux-gnu/libswsscommon.so.0.0.0 \
  | grep JUMP_SLO | grep -c 4swss                             # 期望 0

# §3.2.1 受控 A/B：剥掉 flag 重编 swss-common，再用同一个测试二进制换 .so 跑
#   在 debian/rules 的 `include /usr/share/dpkg/default.mk` 之前插入：
#       export DEB_LDFLAGS_MAINT_STRIP = -Wl,-Bsymbolic-functions
#   DEB_BUILD_OPTIONS=nocheck DEB_BUILD_PROFILES=nopython2 \
#     dpkg-buildpackage -rfakeroot -b -Pnopython2 -us -uc
#   readelf -rW common/.libs/libswsscommon.so.0.0.0 | grep JUMP_SLO | grep -c 4swss   # 期望 351
#   LD_LIBRARY_PATH=<orig|fixed> ./orchagent/p4orch/tests/p4orch_tests
#   期望：orig 抛 redis 异常退出 134；fixed 输出 770 tests PASSED 退出 0
#   等效的超仓改法（debian/rules 零改动，实测同样得 351 跳板）：
#     DEB_LDFLAGS_MAINT_STRIP="-Wl,-Bsymbolic-functions" dpkg-buildpackage ...
#     即 rules/swss-common.mk 里 $(LIBSWSSCOMMON)_BUILD_ENV = DEB_LDFLAGS_MAINT_STRIP=...

# §5 缓存键实物
cat $R/target/python-wheels/resolute/sonic_chassisd-1.0-py3-none-any.whl.flags

# §4.2 gitignore 覆盖
git -C $R show canonical/202605_resolute_enable_tests:.gitignore > /tmp/g
cd $R && git -c core.excludesFile=/tmp/g check-ignore -v --no-index \
  dockers/docker-base-resolute/files/apt/apt.conf.d/apt-clean

# §4.3 每包 gitignore 惯例
git -C $R ls-files | grep -cE '^src/[^/]+/\.gitignore$'
for p in $(ls $R/src); do [ -f "$R/src/$p/setup.py" ] && \
  [ ! -f "$R/src/$p/.gitignore" ] && echo "缺: src/$p"; done

# §6.1 wheel 内容对比（在 slave 镜像里 python3 -m build -n 后比对 namelist）
```

### 10.3 相关文档

- [Resolute 移植最终状态与坑](2026-08-24-resolute-port-final-state-and-pitfalls-zh.md)
- [四个 resolute 缺陷及与上游全状态对比](2026-07-27-resolute-defect-fixes-and-upstream-state-comparison-zh.md)
- [`202605` 工作流认定与「历史被重写」误判取证](2026-08-31-sonic-202605-workflow-forensics-zh.md)（§6.6 引用）
- [Resolute 迁移代码评审](resolute-migration-code-review-zh.md)
