# SONiC 202605_resolute 正式化重整 —— 实施方案

> **给自动化执行者：** 必用子技能：用 superpowers:subagent-driven-development 或 superpowers:executing-plans 按任务逐条执行。步骤用复选框（`- [ ]`）跟踪。每个提交都 GPG 签名；只有在开发者对本方案 sign-off 之后才可改写历史。
>
> **注：英文版 `...-en.md` 是 source of truth，本中文版为对应翻译。**

**目标：** 把杂乱的 `202605_resolute` 构建分支，在**纯净上游 `sonic-net/202605`** 基础上，重建成一条干净、可审阅的提交历史（新分支 `202605_resolute_clean`），按 PR 大小的单元组织，达到可正式化状态。

**架构：** 用**文件组重放（file-group replay）**，不是 commit rebase。从 `sonic-net/202605@fe5ae5db` 起一条新分支；对每个 PR 单元，把该组文件的**最终树状态**从 `202605_resolute` 取过来（`git checkout 202605_resolute -- <files>`），做 GPG 签名提交。构建环境 / docker 层变体用 **fork（逐字节拷贝 trixie）→ adapt（适配）** 两提交模式，让审阅者看到的是真实的 ~176 行 delta，而不是 ~1.2K 行「新增」。Submodule 保留 **15 个 MUST-FORK** 的 canonical gitlink，把 `sonic-linux-kernel` + `dhcpmon` **回退到上游**。`rules/config.user` 全程不纳入。**Broadcom 是最后一个 PR。** 最终树与「已测试的 resolute tip（减去有意的 delta）」做断言校验，并以一次 smoke 构建作为收口门槛。

**技术栈：** git（+ GPG 签名）、SONiC make 构建（`BLDENV=resolute`）、bash。

## 全局约束

- **基点：** `sonic-net/202605` @ `fe5ae5db34`（每次运行重新 fetch）。**绝不 push 到 `sonic-net`。**
- **Canonical 改动集基准（manifest）：** resolute 的 fork 点 `67a348840b`。`git diff --name-only 67a348840b 202605_resolute` = 315 文件 = 恰好是 Canonical 的改动。
- **每个提交 GPG 签名：** `commit.gpgsign=true` 已配；key `521ED6CE84B5C2B2BAF7AAEA90E19370EEEF6873`；作者/提交者 `Sheldon Qi <sheldon.qi@canonical.com>`。显式用 `git commit -S`。
- **每个提交带 co-author trailer：** `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`。
- **Canonical submodule 提交**只存在于 `canonical/<sub>:202605_resolute`；15 个 MUST-FORK gitlink 已在那里且可达（已验证）。**无需 submodule rebase**——保留现有（已测试）的 fork commit。
- **`.gitmodules`：** URL 用 `https`（绝不 ssh）；就地改每个 `[submodule "<name>"]` 段；每段保留 `path =`。
- **`rules/config.user` 绝不出现**在 `202605_resolute_clean` 的任何提交里（它被 `.gitignore:8` 覆盖、是本机本地配置）。
- **Broadcom**（`platform/broadcom/**`）是**最后一个** PR。
- **暂存纪律：** 只暂存目标路径；**绝不在仓库根 `git add -A`**（工作树里有 ~88 个构建产物条目）。
- **仓库：** 所有操作在 `/home/sheldon-qi/sonic-buildimage-resolute`。计划文档在主仓库的 `202605_resolute_doc` 分支。
- **非破坏性：** 不修改 `202605_resolute`；干净历史是一条**新分支**。开发者决定前不 push 任何东西。
- **shell 不持久：** shell 函数/变量在不同命令调用之间**不保留**；但磁盘上的 `/tmp/reso_buckets.txt`、`/tmp/fork_map.txt`（任务 0）会保留。每个任务的 shell 开头都重新定义辅助函数：`files() { grep "^$1"$'\t' /tmp/reso_buckets.txt | cut -f2; }`。

## 相对「已测试的 `202605_resolute` tip」的有意 delta（最终断言里应当出现的）

因为基点是**当前**上游（fe5ae5db，比 fork 点领先约 17 天），且我们丢掉 3 样东西，所以 `git diff 202605_resolute_clean 202605_resolute` 预期**只**显示：
1. `rules/config.user` —— resolute 有、clean 没有（已丢弃）。
2. `src/dhcpmon`、`src/sonic-linux-kernel` —— clean 指向上游；resolute 指向（较旧上游 / 死掉的 canonical fork）。
3. resolute 从未碰过、而上游这 17 天前进了的 ~9 个文件（`.azure-pipelines/...UpgrateVersion.yml`、`dockers/docker-ptf/Dockerfile.j2`、`platform/broadcom/sonic-platform-modules-arista` gitlink、`src/sonic-frr/patch/0115-*`、`0116-*`、`series`、`src/sonic-platform-common` gitlink、`src/sonic-yang-mgmt/sonic_yang_ext.py`、`.../test_sonic_yang.py`）—— clean 带上游更新版，resolute 是旧版。

这个清单之外的任何文件出现在该 diff 里，就是重整的 **BUG**，定稿前必须排查。

---

## 分支模型 —— 每 PR 一条、stack 起来

产出一**叠（stack）分支**，每个 PR 一条、各自基于前一条——**不是单条分支**：

`sonic-net/202605` → `202605_resolute_pr01` → `202605_resolute_pr02` → … → `202605_resolute_pr08`

- 任务 0 从 `sonic-net/202605` 建 `202605_resolute_pr01`；PR-1 的提交落在它上面。
- 之后每个任务 N（N≥2）**开头**用 `git checkout -b 202605_resolute_pr0N` 从当前 tip（=上一个 PR 分支）拉出，再做本 PR 的提交。
- PR N 的可审 diff = `git diff 202605_resolute_pr0(N-1) 202605_resolute_pr0N`（pr01 对 `sonic-net/202605`）。
- 栈顶 `202605_resolute_pr08` 含完整历史。**本文档凡写 `202605_resolute_clean` 之处，一律读作栈顶 `202605_resolute_pr08`。**
- PR→分支→任务：pr01=任务1 构建环境；pr02=任务2 submodule；pr03=任务3 内核；pr04=任务4 公共 docker；**pr05=任务5 src 包（含 bash 5.3 plugin 移植 `4174a0650e` + socat `5b94e4511a`）**；pr06=任务6 grub2（`2db1d3f95d`）；pr07=任务7 其它平台；pr08=任务8 Broadcom（最后）。
- 开发者显式授权前，不 push、不建 PR。

---

## 任务 0：准备 —— fetch 基点、建分支、生成 manifest

**文件：**
- 创建（临时）：`/tmp/reso_manifest.txt`、`/tmp/reso_buckets.txt`、`/tmp/fork_map.txt`
- 分支：`202605_resolute_clean`

- [ ] **步骤 1：fetch 基点 + 核对 tip**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
git fetch sonic-net 202605
git rev-parse --short sonic-net/202605 202605_resolute   # 预期 fe5ae5db34 / 4174a0650e
```
预期：`sonic-net/202605` = `fe5ae5db34`，`202605_resolute` = `4174a0650e`（Phase A socat/grub/bash 已提交）。

- [ ] **步骤 2：生成 Canonical 改动集 manifest（315 文件）**

```bash
git diff --name-only 67a348840b 202605_resolute | sort > /tmp/reso_manifest.txt
wc -l /tmp/reso_manifest.txt   # 预期 315
```

- [ ] **步骤 3：把每个 manifest 文件分入 PR 组**（broadcom 最后）

```bash
awk '{
  f=$0
  if (f==".gitmodules") g="G09_submodules";
  else if (f ~ /^src\/[^\/]+$/) g="G09_submodules";
  else if (f=="src/sonic-linux-kernel") g="G03_kernel";
  else if (f=="AGENTS.md") g="G01_build_env";
  else if (f ~ /^sonic-slave-resolute\//) g="G01_build_env";
  else if (f=="Makefile"||f=="Makefile.work"||f=="build_debian.sh"||f=="build_image.sh"||f=="slave.mk"||f=="rules/config.user"||f=="installer/default_platform.conf") g="G01_build_env";
  else if (f ~ /^scripts\/build_/) g="G01_build_env";
  else if (f ~ /^files\/(apt|build_templates|dsc)\//) g="G01_build_env";      # PR-7 折进 PR-1
  else if (f ~ /^dockers\/docker-(base|config-engine|swss-layer)-resolute\//) g="G02_variants";
  else if (f ~ /^rules\/docker-.*-resolute\./) g="G02_variants";
  else if (f ~ /^dockers\/.*Dockerfile\.j2$/||f ~ /^dockers\/dockerfile-macros/||f ~ /^dockers\/docker-database\/database_config/) g="G04_common_dockers";
  else if (f ~ /^rules\/docker-/) g="G04_common_dockers";
  else if (f ~ /^rules\/linux-kernel/) g="G03_kernel";
  else if (f=="platform/vpp") g="G09_submodules";
  else if (f ~ /^platform\/broadcom\//) g="G09z_broadcom";
  else if (f ~ /^platform\//) g="G07_other_platforms";
  else if (f ~ /grub2/) g="G06_grub2";
  else if (f ~ /^rules\/sonic-fips/) g="G05_src_pkgs";
  else if (f ~ /^rules\//) g="G05_src_pkgs";
  else if (f ~ /^src\//) g="G05_src_pkgs";
  else g="G99_UNASSIGNED";
  print g"\t"f
}' /tmp/reso_manifest.txt | sort > /tmp/reso_buckets.txt
echo "UNASSIGNED (必须为 0):"; grep -c '^G99' /tmp/reso_buckets.txt
cut -f1 /tmp/reso_buckets.txt | sort | uniq -c
```
预期：`UNASSIGNED = 0`。辅助函数：`files() { grep "^$1"$'\t' /tmp/reso_buckets.txt | cut -f2; }`。

- [ ] **步骤 4：生成 fork→trixie 对应表（供 PR-1 种子用）**

```bash
: > /tmp/fork_map.txt
for f in $(files G02_variants) $(grep -E '^G01_build_env\t(sonic-slave-resolute/)' /tmp/reso_buckets.txt | cut -f2); do
  case "$f" in
    sonic-slave-resolute/*)                cp="sonic-slave-trixie/${f#sonic-slave-resolute/}";;
    dockers/docker-base-resolute/*)        cp="dockers/docker-base-trixie/${f#dockers/docker-base-resolute/}";;
    dockers/docker-config-engine-resolute/*) cp="dockers/docker-config-engine-trixie/${f#dockers/docker-config-engine-resolute/}";;
    dockers/docker-swss-layer-resolute/*)  cp="dockers/docker-swss-layer-trixie/${f#dockers/docker-swss-layer-resolute/}";;
    rules/docker-base-resolute.*)          cp="rules/docker-base-trixie.${f##*.}";;
    rules/docker-config-engine-resolute.*) cp="rules/docker-config-engine-trixie.${f##*.}";;
    rules/docker-swss-layer-resolute.*)    cp="rules/docker-swss-layer-trixie.${f##*.}";;
    *) cp="";;
  esac
  [ -n "$cp" ] && git cat-file -e "sonic-net/202605:$cp" 2>/dev/null && printf '%s\t%s\n' "$f" "$cp" >> /tmp/fork_map.txt
done
wc -l /tmp/fork_map.txt   # copy 派生的变体文件（预期 ~20-24）
```

- [ ] **步骤 5：从基点建干净分支**

```bash
git checkout -b 202605_resolute_pr01 sonic-net/202605
git submodule sync >/dev/null 2>&1 || true
```
预期：在 `202605_resolute_pr01`（栈底）上，树 == `sonic-net/202605`。

---

## 任务 1（PR-1）：resolute 构建环境 + docker 层变体 + rootfs 镜像组装

**目标：** Ubuntu 26.04 构建器镜像、三个 resolute docker 层镜像、BLDENV 接线、目标 rootfs 的 apt/extension 配置——用 `fork(逐字节) → adapt` 两提交模式，让评审面是 ~176 行 delta，而不是 ~1.2K 行新增。

**文件：** 组 `G01_build_env` + `G02_variants`（排除 `rules/config.user`）。copy 派生文件见 `/tmp/fork_map.txt`。

**接口 —— 产出：** `sonic-slave-resolute/` 构建器；`docker-{base,config-engine,swss-layer}-resolute` 层镜像 + 其 `rules/*.mk,.dep`；`BLDENV=resolute` 接入 `Makefile`/`Makefile.work`/`slave.mk`。被 PR-4（service docker FROM 这些）、PR-7、PR-8 消费。

- [ ] **步骤 1：种子提交 —— resolute 变体作为 trixie 的逐字节拷贝**

```bash
cd /home/sheldon-qi/sonic-buildimage-resolute
while IFS=$'\t' read -r reso trixie; do
  mkdir -p "$(dirname "$reso")"
  git show "sonic-net/202605:$trixie" > "$reso"
done < /tmp/fork_map.txt
git add -- $(cut -f1 /tmp/fork_map.txt)
git commit -S -F - <<'EOF'
build(resolute): fork trixie build env + layer images -> resolute (verbatim copy)

Seed sonic-slave-resolute/ and docker-{base,config-engine,swss-layer}-resolute
with content byte-identical to their sonic-slave-trixie / docker-*-trixie
counterparts at this base, so the following commit's diff is the Ubuntu-26.04
adaptation only. Verify triviality:
  git show -C -C HEAD   # renders each file as a copy from trixie

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
```

- [ ] **步骤 2：验证种子确为 trixie 的纯拷贝**

```bash
while IFS=$'\t' read -r reso trixie; do
  diff <(git show "sonic-net/202605:$trixie") "$reso" >/dev/null || echo "NOT-IDENTICAL: $reso"
done < /tmp/fork_map.txt
echo "seed check done（无 NOT-IDENTICAL 行 = 通过）"
```
预期：无输出行 → 每个种子文件都等于其 trixie 对应文件。

- [ ] **步骤 3：适配提交 —— 取 resolute 真实内容 + 新文件 + 接线（丢 config.user）**

```bash
FILES=$( (files G01_build_env; files G02_variants) | grep -v '^rules/config.user$' | sort -u )
git checkout 202605_resolute -- $FILES
git add -- $FILES
git status --short -- rules/config.user   # 必须为空（绝不暂存）
git commit -S -F - <<'EOF'
build(resolute): adapt build env + layer images to Ubuntu 26.04

Wire BLDENV=resolute into the top-level dispatch and slave.mk build graph; add
the Ubuntu 26.04 sonic-slave-resolute builder and the base/config-engine/
swss-layer resolute docker layer images; retarget the target rootfs apt
sources (one-line /etc/apt/sources.list; deb822 not used, matching Noble +
debootstrap 1.0.142) and the sonic_debian_extension / DSC install hooks.
rules/config.user (host-local, .gitignore-covered) is intentionally excluded.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
```

- [ ] **步骤 4：验证 PR-1 树与 resolute 一致（除 config.user）**

```bash
for f in $FILES; do
  git diff --quiet 202605_resolute -- "$f" || echo "MISMATCH: $f"
done
echo "PR-1 内容校验完成（无 MISMATCH = 通过）"
git cat-file -e HEAD:rules/config.user 2>/dev/null && echo "BUG: config.user 存在" || echo "config.user 不存在 OK"
```
预期：无 `MISMATCH`，`config.user 不存在 OK`。

---

## 任务 2（PR-2）：Submodule 指针 —— 15 个 MUST-FORK，de-fork linux-kernel + dhcpmon

**目标：** 把 15 个 MUST-FORK submodule 指向其 Canonical fork（URL + gitlink），`sonic-linux-kernel` + `dhcpmon` 保持上游。地基级：早落，因为后续 PR 会把这些 submodule 编成 deb。

**文件：** `.gitmodules` + 15 个 MUST-FORK gitlink（`src/sonic-swss-common`、`src/sonic-swss`、`src/sonic-sairedis`、`src/sonic-snmpagent`、`src/sonic-utilities`、`src/sonic-mgmt-framework`、`src/sonic-mgmt-common`、`src/wpasupplicant/sonic-wpa-supplicant`、`src/dhcprelay`、`src/sonic-gnmi`、`src/sonic-bmp`、`src/sonic-dash-api`、`src/sonic-dash-ha`、`src/sonic-stp`、`platform/vpp`）。**不改：** `src/sonic-linux-kernel`、`src/dhcpmon`（保持基点=上游）。

**接口 —— 产出：** 父仓库 gitlink 指向 `canonical/<sub>:202605_resolute` tip（state-2、可达）。被每个构建 PR 消费。

- [ ] **步骤 1：从 resolute 取 15 个 MUST-FORK gitlink**

```bash
MUST_FORK="src/sonic-swss-common src/sonic-swss src/sonic-sairedis src/sonic-snmpagent src/sonic-utilities src/sonic-mgmt-framework src/sonic-mgmt-common src/wpasupplicant/sonic-wpa-supplicant src/dhcprelay src/sonic-gnmi src/sonic-bmp src/sonic-dash-api src/sonic-dash-ha src/sonic-stp platform/vpp"
git checkout 202605_resolute -- $MUST_FORK
```

- [ ] **步骤 2：取 resolute 的 .gitmodules，就地把 linux-kernel 回退上游**

```bash
git checkout 202605_resolute -- .gitmodules
# 仅把 sonic-linux-kernel 的 URL 改回上游（dhcpmon 在 resolute 的 .gitmodules 里已经是 sonic-net）
git config -f .gitmodules submodule.sonic-linux-kernel.url https://github.com/sonic-net/sonic-linux-kernel
grep -n 'sonic-linux-kernel' -A2 .gitmodules   # 确认 sonic-net URL、path= 完好
```
预期：`sonic-linux-kernel` URL = `https://github.com/sonic-net/sonic-linux-kernel`，`dhcpmon` = sonic-net。`src/sonic-linux-kernel` 与 `src/dhcpmon` 的 gitlink 保持基点（上游）值——绝不对它们 `git checkout 202605_resolute`。

- [ ] **步骤 3：提交前的可达性 + hygiene 断言**

```bash
# .gitmodules hygiene
test "$(grep -cE 'url *= *(ssh://|git@)' .gitmodules)" = 0 && echo "https OK"
s=$(grep -c '^\[submodule' .gitmodules); p=$(grep -cE '^\s*path *=' .gitmodules); test "$s" = "$p" && echo "path= OK ($s)"
# 每个 MUST-FORK gitlink 在其 canonical remote 可达
for m in $MUST_FORK; do
  sha=$(git ls-tree HEAD "$m" | awk '{print $3}')
  url=$(git config -f .gitmodules --get-regexp 'url' | grep -i "$(basename "$m")" | awk '{print $2}')
  git ls-remote "$url" | grep -q "$sha" && echo "REACHABLE $m" || echo "UNREACHABLE(试 refspec) $m $sha $url"
done
```
预期：`https OK`、`path= OK (52)`、每个 MUST-FORK `REACHABLE`（若因 GitHub ref 截断导致精确 grep 落空，用 `git ls-remote <url> refs/heads/202605_resolute` 复核）。全部可达前**不要提交**。

- [ ] **步骤 4：提交 submodule PR（原子）**

```bash
git add -- .gitmodules $MUST_FORK
git commit -S -F - <<'EOF'
build(resolute): retarget submodules to Canonical forks; keep kernel+dhcpmon upstream

Point 15 build-consumed submodules at canonical/<sub>:202605_resolute (each
carries a required, upstream-absent resolute toolchain fix: C++17, py3.14,
cmake>=3.5, go-redis, SWIG 4.4, dpkg-strict metadata). .gitmodules URLs are
https and edited in place. sonic-linux-kernel is de-forked (kernel is procured
prebuilt from the Launchpad PPA; the submodule is not built) and dhcpmon stays
upstream (unchanged by Canonical). All 15 fork gitlinks verified reachable on
their canonical remote.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
```

- [ ] **步骤 5：（执行期、远端破坏性——需开发者显式放行）删除废弃的 canonical fork 分支**

de-fork 的 submodule（`sonic-linux-kernel`；`dhcpmon` 若曾有）会废弃其 `canonical/<sub>:202605_resolute` fork 分支。等 stack 取代 `202605_resolute` 之后，删掉每个 fork 分支（本地 + 远端）。这是**远端破坏性**操作，还会让**旧** `202605_resolute` 父仓库的 linux-kernel gitlink 在 canonical 上不可达——**仅在开发者确认旧分支已被取代后**才做。

```bash
# 探测
for sub in sonic-linux-kernel sonic-dhcpmon; do
  git ls-remote https://github.com/canonical/$sub refs/heads/202605_resolute 2>/dev/null | grep -q . \
    && echo "EXISTS: canonical/$sub:202605_resolute（待删候选）" \
    || echo "none:   canonical/$sub:202605_resolute"
done
# 仅在开发者放行后删除：
#   git push git@github.com:canonical/sonic-linux-kernel.git --delete 202605_resolute
#   git -C src/sonic-linux-kernel branch -D 202605_resolute 2>/dev/null || true
```

---

## 任务 3（PR-3）：内核采购（Launchpad PPA）+ rootfs ABI

**文件：** `G03_kernel` 减去 `src/sonic-linux-kernel`（该 gitlink 保持上游、靠排除处理）：`rules/linux-kernel.mk`、`rules/linux-kernel.dep`。

- [ ] **步骤 1：取内核 rules（不取 submodule gitlink）**

```bash
KFILES=$(files G03_kernel | grep -v '^src/sonic-linux-kernel$')
git checkout 202605_resolute -- $KFILES
git add -- $KFILES
git commit -S -F - <<'EOF'
build(resolute): procure linux-sonic 7.0.0-1002 kernel from Launchpad PPA

Fetch the prebuilt linux-sonic 7.0.0-1002 image/modules/headers debs via
SONIC_ONLINE_DEBS from the canonical-kernel-team PPA instead of building the
kernel from source; drop the now-inert source-build path.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
```

- [ ] **步骤 2：验证**

```bash
for f in $KFILES; do git diff --quiet 202605_resolute -- "$f" || echo "MISMATCH $f"; done; echo done
```
预期：无 MISMATCH。

---

## 任务 4（PR-4）：公共 service docker → resolute 基镜像

**文件：** `G04_common_dockers`（~59 个 `dockers/*/Dockerfile.j2` + `rules/docker-*.mk` 的 trixie→resolute 基镜像改名 + 几处运行时修复）。

- [ ] **步骤 1：取 + 提交**

```bash
DFILES=$(files G04_common_dockers)
git checkout 202605_resolute -- $DFILES
git add -- $DFILES
git commit -S -F - <<'EOF'
build(resolute): rebase common service dockers onto resolute layer images

Retarget the shared service-docker Dockerfile.j2 base images and their
rules/docker-*.mk from the trixie layer images to the resolute ones, plus the
resolute runtime fixes (rsync /etc/hosts exclude, teamd iproute2, libxml2-16,
database DEV default).

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
```

- [ ] **步骤 2：验证** —— `for f in $DFILES; do git diff --quiet 202605_resolute -- "$f" || echo "MISMATCH $f"; done; echo done` → 无 MISMATCH。

---

## 任务 5（PR-5）：src 包构建修复（含 Phase A socat + bash）

**文件：** `G05_src_pkgs`（src 包的 rules/*.mk + `src/**` 非 submodule 源码：bash、socat、libnl3、libyang3(+py3)、isc-dhcp、kdump-tools、makedumpfile、openssh、lldpd、radius、rasdaemon、sflow、systemd-sonic-generator、sonic-fib、sonic-eventd、sonic-fips 等）。此组已包含 Phase A 的 `socat`（5b94e4511a）与 `bash`（4174a0650e）内容，因为 `202605_resolute` 里就有。

- [ ] **步骤 1：取 + 提交**

```bash
SFILES=$(files G05_src_pkgs)
git checkout 202605_resolute -- $SFILES
git add -- $SFILES
git commit -S -F - <<'EOF'
build(resolute): src package build fixes for the Ubuntu 26.04 toolchain

Rebuild core libs and tools from Ubuntu source with GCC15/LTO/cmake4/dpkg-1.23
compat: bash (plugin patch ported to 5.3, restores bash-tacplus), socat
(enable_readline), libnl3, libyang3(+py3), isc-dhcp, openssh, lldpd, radius,
rasdaemon, sflow, systemd-sonic-generator, sonic-fib, and dget-based source
fetch with dbgsym tolerance; FIPS reuses trixie binaries (INCLUDE_FIPS-gated).

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
```
*可选更细拆分（视 reviewer 偏好）：core-libs / dget-fetch / toolchain-compat / FIPS 分开提交——相应拆 `$SFILES`。*

- [ ] **步骤 2：验证** —— `for f in $SFILES; do git diff --quiet 202605_resolute -- "$f" || echo "MISMATCH $f"; done; echo done` → 无 MISMATCH。

---

## 任务 6（PR-6）：grub2（Ubuntu 拆分；含 Phase A grub 修复）

**文件：** `G06_grub2` —— `rules/grub2.mk`、`src/grub2/**`、`src/grub2-unsigned/**`（含 Phase A 删死行 `patch-overlayfs-ln.sh`，2db1d3f95d）。

- [ ] **步骤 1：取 + 提交**

```bash
GFILES=$(files G06_grub2)
git checkout 202605_resolute -- $GFILES
git add -- $GFILES
git commit -S -F - <<'EOF'
build(resolute): split grub2 into src:grub2 + src:grub2-unsigned for Ubuntu

Ubuntu splits grub-efi-amd64(-bin) into src:grub2-unsigned; build both from the
Ubuntu pool via dget. The harmless 'ln: hard link not allowed for directory'
staging warning does not affect the produced .debs and needs no patch (the lost
patch-overlayfs-ln.sh call is removed).

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
```

- [ ] **步骤 2：验证** —— `for f in $GFILES; do git diff --quiet 202605_resolute -- "$f" || echo "MISMATCH $f"; done; echo done` → 无 MISMATCH。

---

## 任务 7（PR-7）：其它（非 Broadcom）平台

**文件：** `G07_other_platforms` —— `platform/{components,marvell-prestera,marvell-teralynx,mellanox,nokia-vs,nvidia-bluefield,pddf,template,vpp,vs}/…`（trixie→resolute docker 基镜像改名 + nokia init + pddf gpio Linux-7.0 修复）。注意：只有 `platform/vs/**` 被已测试的 vs 构建真正演练过；Marvell/Mellanox/NVIDIA 在本次迁移里是 rebase 但未构建。

- [ ] **步骤 1：取 + 提交**

```bash
PFILES=$(files G07_other_platforms)
git checkout 202605_resolute -- $PFILES
git add -- $PFILES
git commit -S -F - <<'EOF'
build(resolute): rebase non-broadcom platform dockers onto resolute base

Retarget syncd/gbsyncd/saiserver docker variants for vs (tested), Marvell
Prestera/Teralynx, Mellanox/NVIDIA-BlueField and gearbox platforms onto the
resolute config-engine layer, plus nokia 7215 init and the pddf multifpgapci
gpio Linux-7.0 API fix. Non-vs vendors are rebased for consistency but were not
built in this migration.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
```
*可选拆分：`platform/vs/**`（已测试）单独一提交，vs 其它厂商改名（未验证）另一提交。vpp 去留是未决点（默认：保留）。*

- [ ] **步骤 2：验证** —— `for f in $PFILES; do git diff --quiet 202605_resolute -- "$f" || echo "MISMATCH $f"; done; echo done` → 无 MISMATCH。

---

## 任务 8（PR-8，最后）：Broadcom 平台（Linux 7.0 kmod 适配）

**文件：** `G09z_broadcom` —— 全部 `platform/broadcom/**`（129 文件、~9.3K 行：`saibcm-modules{,-dnx,-legacy-th}.patch/**`、`sswsyncd`、`rules.mk`、`docker-syncd-brcm*`、`docker-saiserver-brcm*`、`docker-pde`，以及 18 个 `sonic-platform-modules-*.patch/**`）。

**粒度（默认；这是唯一标记为待最终评审的部分）：** saibcm 3 提交（按源树）+ 1 个 docker 变体提交 + 18 个 per-vendor kmod 提交，或收拢成更少。下面默认 = 18 厂商 per-vendor（7.9K 行、审阅友好），saibcm 合 1 提交。

- [ ] **步骤 1：Broadcom docker 变体 + saibcm + sswsyncd**

```bash
BRD_CORE=$(files G09z_broadcom | grep -E '^platform/broadcom/(saibcm-modules|sswsyncd|rules\.mk|docker-syncd-brcm|docker-saiserver-brcm|docker-pde)')
git checkout 202605_resolute -- $BRD_CORE
git add -- $BRD_CORE
git commit -S -F - <<'EOF'
build(broadcom): saibcm-modules Linux 7.0 kmod patch series + docker variants

saibcm-modules{,-dnx,-legacy-th} Linux 7.0 kmod compat patch series (kernel
ABI, kbuild, from_timer, MODULE_IMPORT_NS, etc.), sswsyncd C++ buildflags, and
retarget the broadcom syncd/saiserver/pde docker variants to the resolute
config-engine layer.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
```

- [ ] **步骤 2：per-vendor kmod 提交（18）**

```bash
for v in accton alphanetworks arista cel dell delta ingrasys inventec juniper micas mitac nexthop nokia quanta ragile ruijie tencent ufispace; do
  VF=$(files G09z_broadcom | grep -E "^platform/broadcom/sonic-platform-modules-$v\.patch/")
  [ -z "$VF" ] && continue
  git checkout 202605_resolute -- $VF
  git add -- $VF
  git commit -S -F - <<EOF
build(broadcom): $v platform kmods Linux 7.0 API-drift patch series

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
done
```

- [ ] **步骤 3：验证所有 broadcom 文件已落地**

```bash
for f in $(files G09z_broadcom); do git diff --quiet 202605_resolute -- "$f" || echo "MISMATCH $f"; done; echo done
```
预期：无 MISMATCH。

---

## 任务 9：最终验证 + smoke 构建（门槛）

- [ ] **步骤 1：与已测试 resolute tip 做全树断言**

```bash
git diff --name-only 202605_resolute_clean 202605_resolute | sort > /tmp/clean_vs_reso.txt
cat /tmp/clean_vs_reso.txt
```
预期：**只**有上面「有意 delta」列出的那些 —— `rules/config.user`、`src/dhcpmon`、`src/sonic-linux-kernel`，以及 ~9 个上游前进文件。**其它任何东西 = 重整 bug，继续前先修。**

- [ ] **步骤 2：提交数量 / 结构 sanity**

```bash
git log --oneline sonic-net/202605..202605_resolute_clean | cat
git log --format='%G?' sonic-net/202605..202605_resolute_clean | sort | uniq -c   # 全部 'G'
```
预期：~10 个 PR 单元提交（+18 broadcom = ~28 总数），每个都是 GPG `G`。

- [ ] **步骤 3：config.user 确实从所有提交中消失**

```bash
git log -p sonic-net/202605..202605_resolute_clean -- rules/config.user | head   # 预期空
```
预期：空（从未引入）。

- [ ] **步骤 4：smoke 构建**（吸收了上游 17 天对 ~9 文件的变更——必须重验）

```bash
flock /tmp/sonic-pkgbuild.lock make BLDENV=resolute SONIC_DPKG_CACHE_METHOD=none target/sonic-vs.bin 2>&1 | tail -40
ls -la target/sonic-vs.bin
```
预期：`target/sonic-vs.bin` 构建成功。（更快的门槛：先构建被那 ~9 个上游 delta 触及的代表性包，例如因两个新 frr 补丁而先建 `target/debs/resolute/sonic-frr_*`，再整镜像。）

- [ ] **步骤 5：交接 —— 不要 push**

把分支、提交列表、`git diff` 断言结果、smoke 构建结果报告给开发者。push / force-push / 建 PR 是单独的、需开发者授权的步骤（落地决定为：本地干净分支，之后再推）。

---

## 自审

- **spec 覆盖：** 315 个 manifest 文件每一个都恰好映射到一个 PR 组（任务 0 步骤 3 断言 `UNASSIGNED = 0`）；任务 1–8 各自 `git checkout` 其组，任务 9 断言整树。Phase A 修复（socat/grub/bash）通过 resolute 树状态进入 PR-5/PR-6。`config.user` 靠排除处理（无需删除提交）。
- **基点上移风险：** ~9 个上游前进文件被有意取上游（基点）版本；任务 9 步骤 1 恰好白名单这些，步骤 4 smoke 构建捕捉任何交互（尤其两个新 frr 补丁 + arista/platform-common gitlink）。
- **submodule 合规：** 任务 2 在提交**前**断言 https + path= + 每个 fork 可达；linux-kernel/dhcpmon 的 de-fork 靠排除 + 一处就地 URL 改；不做 rebase（复用现有 fork commit）。全程不 push sonic-net。
- **已定：** vpp **保留**（作为 MUST-FORK submodule 留在 PR-2）。Broadcom 先作为**一条巨型 PR**（`pr08`，19 commit，~9.3K 行）；拆成 stacked 子 PR 留到以后再议。bash **不单拆**——在 PR-5（`pr05`）里。
