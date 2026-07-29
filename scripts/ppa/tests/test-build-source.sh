#!/bin/bash
# Verify that the source package build-source.sh produces for a
# package is correct:
#   - produces a .dsc and a _source.changes
#   - the upload manifest contains no .deb at all (PPAs only accept
#     source uploads)
#   - the version number is stock version + suffix
#     (<STOCK_VERSION><SUFFIX>)
#   - SONiC patches that only touch outside debian/* have been
#     appended to debian/patches/series, in the same order as
#     src/<pkg>/patch/series; the part that only touches debian/* has
#     been baked directly into the tree and does not appear in series
#   - the patches can be applied verbatim by dpkg-source -x with zero
#     fuzz (the Launchpad builder uses dpkg-source itself, not the
#     fuzz-tolerant stg import used in the local dev loop)
set -euo pipefail

PKG="${1:?usage: test-build-source.sh <pkg>}"
cd "$(dirname "$0")/../../.."
# patch_class(): shares the same debian/ vs non-debian judgment with
# build-source.sh, not reimplemented here.
source scripts/ppa/patch-class.sh
# query_pkg(): shared with build-source.sh and manifest.sh -- same
# query/validate implementation, not reimplemented here.
source scripts/ppa/query-pkg.sh

query_pkg "$PKG" || exit 1
OUT="target/source/$PKG"

# A nullglob array rather than `ls | head -1`: when the glob doesn't
# match, ls exits non-zero, and under pipefail that would trigger
# errexit right on this assignment itself, never reaching the FAIL
# branch below.
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

# Unpack (without applying patches), reused by two checks below: 1)
# reading the stock epoch (if any) from the second-newest changelog
# entry; 2) checking the tail composition of series.
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
#   --skip-patches here only serves the epoch and series-content checks
#   below, which just read files under debian/ and do not need patches
#   actually applied.
dpkg-source --no-check --skip-patches -x "$dsc" "$tmp/src" >/dev/null

# The version number must be stock + suffix. Compare it as a plain
# string rather than folding it into a grep regex: the '.' in
# $want_ver is the "any character" metacharacter in a BRE, so putting
# it into a grep pattern would make the check looser than intended.
#
# Some stock packages (e.g. lm-sensors) have a dpkg epoch in
# debian/changelog (e.g. "1:3.6.2-2build1"), and build-source.sh's dch
# --newversion carries it forward unchanged. Here the same epoch is
# read independently from the "second-newest" changelog entry (the
# pristine, unmodified one that comes before the entry dch just
# inserted), to verify against, rather than checking the .dsc's own
# field against itself.
epoch=""
if raw=$(dpkg-parsechangelog -o1 -c1 --show-field Version -l "$tmp/src/debian/changelog" 2>/dev/null); then
    case "$raw" in
        *:*) epoch="${raw%%:*}:" ;;
    esac
fi
want_ver="${epoch}${Q_STOCK_VERSION}${Q_SUFFIX}"
# `if cmd; then` rather than a bare `x=$(cmd)`: when cmd is an if
# condition, its non-zero exit does not trigger errexit, so when the
# .dsc has no Version: field it falls through to the FAIL below
# instead of being killed by set -e right on this assignment (grep -m1
# already has no pipe here, so no extra head -1 is needed).
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

# Check the tail of series
# grep exiting 1 (no matching line) is a legitimate state here: when
# series currently has zero active patches, an empty want should be
# produced, falling through to the "0 patches" comparison below,
# rather than being treated as an error and killing the script under
# set -e. Catch the exit code explicitly with `|| rc=$?`; only >1 (e.g.
# the series file itself being unreadable) is a real error.
rc=0
grep -vE '^\s*(#|$)' "$Q_PATCH_DIR/series" > "$tmp/all_active" || rc=$?
[ "$rc" -le 1 ] || { echo "FAIL: could not read patch series at $Q_PATCH_DIR/series (grep exit $rc)"; exit 1; }

# Only patches that "only touch outside debian/*" get appended to
# debian/patches/series; patches that "only touch debian/*" have
# already been baked directly into the tree itself by build-source.sh
# and do not appear in series. Classification uses the same
# patch_class(), the judgment logic is not duplicated here.
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
        invalid)
            echo "FAIL: $p has no recognized a/-, b/- or /dev/null-shaped diff header; cannot classify it"; exit 1
            ;;
        *)
            echo "FAIL: $p: patch_class printed an unrecognized value"; exit 1
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
