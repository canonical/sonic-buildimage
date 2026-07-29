#!/bin/bash
# 打印每个 PPA 候选包的状态表。取代「另建一份 YAML 好一眼看全」的做法：
# 本表 100% 由 rules/*.mk 推导,是产物而非真相,因此不会漂移。
#
# 用法: scripts/ppa/manifest.sh [<pkg>...]     不给参数则列出所有已声明 _VERSION_STOCK 的包
set -euo pipefail
cd "$(dirname "$0")/../.."

pkgs=("$@")
if [ ${#pkgs[@]} -eq 0 ]; then
    # 不能只 grep _DSC_URL：rules/iproute2.mk 也定义了 IPROUTE2_DSC_URL,但那
    # 是它自己直接下载上游 .dsc 用的,跟本设计「stock 版本 + PPA 后缀切换」
    # 的登记方式无关(它用 *_VERSION,不用 *_VERSION_STOCK,query.mk 对它会
    # 报 "expected exactly 1 main deb, got \"\"")。_VERSION_STOCK 才是 PPA
    # 候选包共有、且只有它们才有的标记。
    mapfile -t pkgs < <(grep -l '_VERSION_STOCK' rules/*.mk | sed 's|rules/||; s|\.mk$||' | sort)
fi

printf '%-14s %-6s %-24s %-14s %s\n' PACKAGE MODE STOCK-VERSION SUFFIX DEBS
# 一个包查询失败不应连累其余包：报错点名该包并继续,让调用者仍能看到所有
# 查得到的包,同时靠 $fail 让脚本整体以非零退出码收尾（`manifest.sh a b`
# 里 b 不存在时,a 的那一行不该因为 b 的报错就消失）。
fail=0
for p in "${pkgs[@]}"; do
    # 每次迭代前先清空上一个包的 Q_*,这样一旦本次 query.mk 失败或漏报某个
    # key,就不会把上一个包的旧值当成本次结果打印出来(这正是本脚本原先的
    # bug：process substitution 里失败的 make 退出码对 set -e 不可见,而
    # declare 只会赋值不会清空,于是失败的迭代原样重印了上一行)。
    unset -v Q_PKG Q_MODE Q_STOCK_VERSION Q_DSC_URL Q_SUFFIX Q_PATCH_DIR \
        Q_MAIN_DEB Q_DERIVED_DEBS Q_SOURCE Q_PPA_POOL_URL

    q_out=""
    q_rc=0
    q_out=$(make -s -f scripts/ppa/query.mk PKG="$p" 2>&1) || q_rc=$?
    if [ "$q_rc" -ne 0 ]; then
        echo "$p: query.mk failed:" >&2
        printf '%s\n' "$q_out" | sed 's/^/    /' >&2
        fail=1
        continue
    fi
    while IFS='=' read -r k v; do declare "Q_$k=$v"; done <<< "$q_out"

    missing=""
    for req in PKG MODE STOCK_VERSION SUFFIX MAIN_DEB DERIVED_DEBS; do
        var="Q_$req"
        [ -n "${!var+x}" ] || missing="$missing $req"
    done
    if [ -n "$missing" ]; then
        echo "$p: query.mk did not report:$missing" >&2
        fail=1
        continue
    fi

    ndebs=$(( 1 + $(echo "$Q_DERIVED_DEBS" | wc -w) ))
    printf '%-14s %-6s %-24s %-14s %s\n' \
        "$Q_PKG" "$Q_MODE" "$Q_STOCK_VERSION" "$Q_SUFFIX" "$ndebs"
    if [ "${VERBOSE:-}" = "1" ]; then
        for d in $Q_MAIN_DEB $Q_DERIVED_DEBS; do
            printf '    %s\n' "$d"
        done
    fi
done

exit "$fail"
