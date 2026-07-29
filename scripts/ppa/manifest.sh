#!/bin/bash
# 打印每个 PPA 候选包的状态表。取代「另建一份 YAML 好一眼看全」的做法：
# 本表 100% 由 rules/*.mk 推导,是产物而非真相,因此不会漂移。
#
# 用法: scripts/ppa/manifest.sh [<pkg>...]     不给参数则列出所有已声明 _VERSION_STOCK 的包
set -euo pipefail
cd "$(dirname "$0")/../.."
# query_pkg(): shared with build-source.sh and test-build-source.sh -- see
# that file's header comment for the bug this replaces.
source scripts/ppa/query-pkg.sh

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
# One package failing to query should not take the rest down with it:
# query_pkg() returns non-zero instead of exiting, we name the package and
# continue so the caller still sees every package that did resolve, and
# $fail carries the failure through to the script's own exit status
# (`manifest.sh a b` with b nonexistent should still print a's row, not
# lose it just because b errored).
fail=0
for p in "${pkgs[@]}"; do
    query_pkg "$p" || { fail=1; continue; }

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
