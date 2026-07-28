#!/bin/bash
# 验证 build-source.sh 为一个包产出的源码包是否正确：
#   - 产出 .dsc 与 _source.changes
#   - 上传清单里没有任何 .deb（PPA 只收 source upload）
#   - SONiC 补丁已追加进 debian/patches/series，顺序与 src/<pkg>/patch/series 一致
#   - 补丁保持「未应用」状态（由 Launchpad builder 在构建时应用）
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

# 版本号必须是 stock + suffix
want_ver="${Q_STOCK_VERSION}${Q_SUFFIX}"
if ! grep -q "^Version: ${want_ver}\$" "$dsc"; then
    echo "FAIL: $dsc Version is not '$want_ver'"; grep '^Version:' "$dsc"; exit 1
fi
echo "ok   version is $want_ver"

# 解包，检查 series 尾部与补丁未应用
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
#   --skip-patches is required: plain `dpkg-source -x` on a 3.0 (quilt)
#   package applies debian/patches/series and creates .pc as part of a normal
#   extraction (dpkg-source(1): --skip-patches "since dpkg 1.14.18" implies
#   applying is the default). Without it this check would fail for any
#   correctly-built quilt package, regardless of whether patches truly ship
#   unapplied in the .dsc/tarball.
dpkg-source --no-check --skip-patches -x "$dsc" "$tmp/src" >/dev/null
grep -vE '^\s*(#|$)' "$Q_PATCH_DIR/series" > "$tmp/want"
tail -n "$(wc -l < "$tmp/want")" "$tmp/src/debian/patches/series" > "$tmp/got"
if ! diff -u "$tmp/want" "$tmp/got"; then
    echo "FAIL: SONiC patches are not appended verbatim at the end of debian/patches/series"; exit 1
fi
echo "ok   $(wc -l < "$tmp/want") SONiC patches appended in order"

if [ -d "$tmp/src/.pc" ]; then
    echo "FAIL: $tmp/src/.pc exists; patches must ship UNAPPLIED"; exit 1
fi
echo "ok   patches ship unapplied"

echo "test-build-source($PKG): all assertions passed"
