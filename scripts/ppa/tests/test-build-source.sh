#!/bin/bash
# 验证 build-source.sh 为一个包产出的源码包是否正确：
#   - 产出 .dsc 与 _source.changes
#   - 上传清单里没有任何 .deb（PPA 只收 source upload）
#   - SONiC 补丁已追加进 debian/patches/series，顺序与 src/<pkg>/patch/series 一致
#   - 补丁能在零 fuzz 下被 dpkg-source -x 原样应用（Launchpad builder 用的
#     正是 dpkg-source，不是本地开发循环里容忍 fuzz 的 stg import）
set -euo pipefail

PKG="${1:?usage: test-build-source.sh <pkg>}"
cd "$(dirname "$0")/../../.."

# 用 read 而非 eval：DERIVED_DEBS 的值含空格，eval 会把它按词拆开去执行
while IFS='=' read -r k v; do declare "Q_$k=$v"; done \
    < <(make -s -f scripts/ppa/query.mk PKG="$PKG")
OUT="target/source/$PKG"

dsc=$(ls "$OUT"/*.dsc 2>/dev/null | head -1)
[ -n "$dsc" ] || { echo "FAIL: no .dsc in $OUT"; exit 1; }
echo "ok   dsc present: $dsc"

changes=$(ls "$OUT"/*_source.changes 2>/dev/null | head -1)
[ -n "$changes" ] || { echo "FAIL: no _source.changes in $OUT"; exit 1; }
echo "ok   changes present: $changes"

if grep -qE '^\s.*\.deb$' "$changes"; then
    echo "FAIL: $changes lists a .deb; PPAs reject binary uploads"; exit 1
fi
echo "ok   changes contains no .deb"

# 版本号必须是 stock + suffix。逐字段比较而非塞进 grep 正则：$want_ver 里的
# '.' 在 BRE 里是「任意字符」元字符，塞进 grep 模式会让校验比预期宽松。
want_ver="${Q_STOCK_VERSION}${Q_SUFFIX}"
dsc_ver=$(grep '^Version:' "$dsc" | head -1 | sed -e 's/^Version:[[:space:]]*//' -e 's/[[:space:]]*$//')
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
grep -vE '^\s*(#|$)' "$Q_PATCH_DIR/series" > "$tmp/want"
tail -n "$(wc -l < "$tmp/want")" "$tmp/src/debian/patches/series" > "$tmp/got"
if ! diff -u "$tmp/want" "$tmp/got"; then
    echo "FAIL: SONiC patches are not appended verbatim at the end of debian/patches/series"; exit 1
fi
echo "ok   $(wc -l < "$tmp/want") SONiC patches appended in order"

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
