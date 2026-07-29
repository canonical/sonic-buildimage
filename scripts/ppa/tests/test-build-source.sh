#!/bin/bash
# 验证 build-source.sh 为一个包产出的源码包是否正确：
#   - 产出 .dsc 与 _source.changes
#   - 上传清单里没有任何 .deb（PPA 只收 source upload）
#   - 版本号是 stock 版本 + suffix（<STOCK_VERSION><SUFFIX>）
#   - 只改 debian/* 之外的 SONiC 补丁已追加进 debian/patches/series，顺序与
#     src/<pkg>/patch/series 一致；只改 debian/* 的那部分已被直接焙进树，
#     不出现在 series 里
#   - 补丁能在零 fuzz 下被 dpkg-source -x 原样应用（Launchpad builder 用的
#     正是 dpkg-source，不是本地开发循环里容忍 fuzz 的 stg import）
set -euo pipefail

PKG="${1:?usage: test-build-source.sh <pkg>}"
cd "$(dirname "$0")/../../.."
# patch_class()：与 build-source.sh 共用同一套 debian/ vs 非-debian 判断，
# 不重复实现。
source scripts/ppa/patch-class.sh

# 用 read 而非 eval：DERIVED_DEBS 的值含空格，eval 会把它按词拆开去执行
while IFS='=' read -r k v; do declare "Q_$k=$v"; done \
    < <(make -s -f scripts/ppa/query.mk PKG="$PKG")
OUT="target/source/$PKG"

# nullglob 数组而非 `ls | head -1`：glob 不匹配时 ls 以非零退出，pipefail 下
# 会在这条赋值语句本身就把 errexit 触发掉，永远走不到下面的 FAIL 分支。
shopt -s nullglob
dsc_candidates=("$OUT"/*.dsc)
shopt -u nullglob
[ "${#dsc_candidates[@]}" -gt 0 ] || { echo "FAIL: no .dsc in $OUT"; exit 1; }
dsc="${dsc_candidates[0]}"
echo "ok   dsc present: $dsc"

shopt -s nullglob
changes_candidates=("$OUT"/*_source.changes)
shopt -u nullglob
[ "${#changes_candidates[@]}" -gt 0 ] || { echo "FAIL: no _source.changes in $OUT"; exit 1; }
changes="${changes_candidates[0]}"
echo "ok   changes present: $changes"

if grep -qE '^\s.*\.deb$' "$changes"; then
    echo "FAIL: $changes lists a .deb; PPAs reject binary uploads"; exit 1
fi
echo "ok   changes contains no .deb"

# 版本号必须是 stock + suffix。逐字段比较而非塞进 grep 正则：$want_ver 里的
# '.' 在 BRE 里是「任意字符」元字符，塞进 grep 模式会让校验比预期宽松。
want_ver="${Q_STOCK_VERSION}${Q_SUFFIX}"
# `if cmd; then` 而不是裸的 `x=$(cmd)`：cmd 作为 if 条件时，其非零退出不会
# 触发 errexit，所以 .dsc 里没有 Version: 字段时能落到下面的 FAIL，而不是
# 在这条赋值本身就被 set -e 杀掉（.dsc 不匹配用 grep -m1，本来就没有管道，
# 不需要额外的 head -1）。
if version_line=$(grep -m1 '^Version:' "$dsc"); then
    dsc_ver=$(sed -e 's/^Version:[[:space:]]*//' -e 's/[[:space:]]*$//' <<< "$version_line")
else
    dsc_ver=""
fi
[ -n "$dsc_ver" ] || { echo "FAIL: no Version: field found in $dsc"; exit 1; }
if [ "$dsc_ver" != "$want_ver" ]; then
    echo "FAIL: $dsc Version is '$dsc_ver', not '$want_ver'"; exit 1
fi
echo "ok   version is $want_ver"

# 解包，检查 series 尾部
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
#   --skip-patches here only serves the series-content check below, which
#   just reads debian/patches/series and does not need patches actually
#   applied.
dpkg-source --no-check --skip-patches -x "$dsc" "$tmp/src" >/dev/null
# grep 退出 1（没有匹配行）在这里是合法状态：series 里当前一个生效补丁都没有
# 时就该产出一个空 want，走到下面「0 个补丁」的比较，而不是被 set -e 当成
# 出错杀掉脚本。用 `|| rc=$?` 显式接住退出码，只有 >1（比如 series 文件本身
# 读不到）才是真错误。
rc=0
grep -vE '^\s*(#|$)' "$Q_PATCH_DIR/series" > "$tmp/all_active" || rc=$?
[ "$rc" -le 1 ] || { echo "FAIL: could not read patch series at $Q_PATCH_DIR/series (grep exit $rc)"; exit 1; }

# 只有"只改 debian/* 之外"的补丁才会被追加进 debian/patches/series；
# "只改 debian/*"的补丁已经在 build-source.sh 里直接焙进树本体，不出现在
# series 里。分类用同一份 patch_class()，不在这里另抄一遍判断逻辑。
: > "$tmp/want"
debian_patches=()
upstream_count=0
while IFS= read -r p; do
    [ -n "$p" ] || continue
    case "$(patch_class "$Q_PATCH_DIR/$p")" in
        debian)
            debian_patches+=("$p")
            ;;
        upstream)
            echo "$p" >> "$tmp/want"
            upstream_count=$((upstream_count + 1))
            ;;
        mixed)
            echo "FAIL: $p touches both debian/ and non-debian/ paths; cannot classify for the series check"; exit 1
            ;;
    esac
done < "$tmp/all_active"

tail -n "$(wc -l < "$tmp/want")" "$tmp/src/debian/patches/series" > "$tmp/got"
if ! diff -u "$tmp/want" "$tmp/got"; then
    echo "FAIL: SONiC upstream-only patches are not appended verbatim at the end of debian/patches/series"; exit 1
fi
# `wc -l` here would count comment and blank lines in the series file too
# (the stock portion may carry both), so build/local-only patch counts read
# high. Count meaningful entries with the same grep filter used above for
# $Q_PATCH_DIR/series instead. `grep -c` exits 1 when the count is
# legitimately zero (no match), and that would kill the script here under
# `set -e` if not caught — same `|| rc=$?` / `[ "$rc" -le 1 ]` guard as the
# `all_active` read above.
rc=0
total_series=$(grep -cvE '^\s*(#|$)' "$tmp/src/debian/patches/series") || rc=$?
[ "$rc" -le 1 ] || { echo "FAIL: could not count patch series entries in $tmp/src/debian/patches/series (grep exit $rc)"; exit 1; }
stock_count=$((total_series - upstream_count))
echo "ok   debian/patches/series: $total_series entries ($stock_count stock + $upstream_count SONiC upstream-only appended)"
if [ "${#debian_patches[@]}" -gt 0 ]; then
    echo "ok   ${#debian_patches[@]} SONiC debian/-only patch(es) applied directly instead of appended: ${debian_patches[*]}"
else
    echo "ok   0 SONiC debian/-only patches for $PKG"
fi

# The property that actually matters: a plain `dpkg-source -x` (patches
# applied, the default since dpkg 1.14.18) must succeed against the .dsc we
# just built. `stg import` (used by build-source.sh's local dev loop)
# tolerates patch fuzz; dpkg-source requires zero fuzz. A stale patch or a
# wrong series order fails here, in seconds, instead of only surfacing 18
# minutes into build-clean.sh's real build.
#   (Checking that .pc is absent after a --skip-patches extraction, as a
#   previous version of this test did, asserts nothing: --skip-patches never
#   applies patches so .pc can never appear, and .pc is on dpkg-source's
#   default tar-ignore list regardless. That check could not fail for either
#   a correct or a broken build-source.sh output.)
apply_log="$tmp/apply.log"
if ! dpkg-source --no-check -x "$dsc" "$tmp/applied" >"$apply_log" 2>&1; then
    echo "FAIL: dpkg-source -x could not apply the full patch series with zero fuzz against $dsc"
    cat "$apply_log"
    exit 1
fi
echo "ok   dpkg-source -x applies the full patch series with zero fuzz"

echo "test-build-source($PKG): all assertions passed"
