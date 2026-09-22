# resolute SONiC 的 chisel 工作：简报

**日期**：2026-09-22
**读者**：需要两分钟内掌握全局的人。完整依据、逐包清单与操作细节见[工作蓝图](2026-09-21-resolute-sonic-chisel-blueprint-zh.md)
**一句话**：把 SONiC 容器用到的 Ubuntu 包切成 chisel slice。约 68 个包，分三批按「谁需要它」推进；写切片与推上游是两件事，不要绑在一起排期。

---

## 现在在哪

**已经在做。** jy5275 向 `canonical/chisel-releases` 提了 20 个 PR、覆盖 15 个包，**19 个 open、0 合入**，最早的挂了 53 天。

fork 也已经有了：[github.com/jy5275/chisel-releases](https://github.com/jy5275/chisel-releases)，当天仍在推送。配方可以先从它消费 slice，不必等上游。

---

## 规模

30 个容器用到 475 个 deb，其中 **416 个**在 Ubuntu 归档、属于 chisel 的作用域。上游已经切好约 64%（可进 rock 的 328 个里有 209 个）。

**剩下约 68 个要我们写。**

---

## 五个 epic

前三个按「谁需要这个包」分批，这也是推进顺序——底层先切，上层才有的用。

| # | Epic | 范围 | 人周 |
|--:|---|---|--:|
| 1 | **core** | 4 个核心 rock（database、eventd、mgmt-framework、router-advertiser）依赖的 14 个包 | 2 |
| 2 | **common** | 两个公共层（docker-config-engine、docker-swss-layer）依赖的 22 个包，所有叶子容器都要用 | 2 |
| 3 | **leaf** | 其余叶子容器依赖的约 32 个包 | 2 |
| 4 | **改配方** | 让 rockcraft 从 chisel-release 取包而不是 Ubuntu 归档；在 rock 里建必要的 Linux 用户 | 1 |
| 5 | **推上游** | 把 PR 合进 upstream。在那之前配方先消费我们自己的 fork，不被上游评审阻塞 | 1 |

### 为什么是这个顺序

- **core 先做**，因为这四个 rock 已经迁移完毕，它们的 `install-unchiselled-packages` 是实测出来的需求，不是推算的。做完就能直接验证一个完整的 rock。
- **common 第二**，它命中所有叶子容器——这一批不到位，后面每个容器都会卡在同一批包上。
- **leaf 最后**，数量最多但每个只影响自己，可以并行也可以分批。

### 排期上要注意的三点

**依赖决定批内顺序。** chisel 解析 `essential:`，被依赖的包必须先合入。典型的：`rsyslog` 要等 `libestr0` 和 `libfastjson4`，`rsyslog-relp` 要等 `librelp0`。按名字排会踩空。

**epic 1 和 2 有约 4 个包重叠**（`libpython3.14`、`python3-yaml`、`python3-redis`、`python3-cffi-backend` 既在公共层里，又被四个核心 rock 直接用到）。谁先做就归谁，不要重复计入工作量。

**epic 5 的时长不由我们决定。** `ubuntu-26.04` 每周只合入 1.9 个 PR，且已积压 39 个。1 人周指的是我们这边的操作量，不是上游合入所需的日历时间。

---

## 两件事分开看

**写切片**（epic 1–3）没有外部依赖，整套流程有官方 skill，AI 可自主执行，量级是**周**。

**推上游**（epic 5）由上游评审吞吐决定，量级是**月**，而且它**不阻塞任何交付**——epic 4 让配方从我们的 fork 取包，rock 照常能出。

把两者绑在一起排期，会得出「要等大半年」这种错误结论。

---

## 还需要决定的

**怎么让上游动起来。** 19 个 PR 零合入说明继续投放没用。可以等走到 epic 5 再处理，但那时要有答案：是推动已提的、还是谈一个评审安排、还是接受部分包长期留在 fork。实测老手的合入延迟是生手的六分之一，所以前几个 PR 要又小又干净。

**不在这个 roadmap item 里的**：53 个自建包和 6 个第三方包 chisel 管不了，它们走 PPA 还是 superdistro 由别的 item 追踪，这里不用管。
