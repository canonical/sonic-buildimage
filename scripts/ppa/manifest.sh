#!/bin/bash
# Print a status table for every PPA-candidate package. Replaces the
# approach of maintaining a separate YAML for an at-a-glance view: this
# table is 100% derived from rules/*.mk -- it's a derived artifact, not
# a second source of truth, so it can't drift.
#
# Usage: scripts/ppa/manifest.sh [<pkg>...]     with no args, lists every package that declares _VERSION_STOCK
set -euo pipefail
cd "$(dirname "$0")/../.."
# query_pkg(): shared with build-source.sh and test-build-source.sh -- see
# that file's header comment for the bug this replaces.
source scripts/ppa/query-pkg.sh

pkgs=("$@")
if [ ${#pkgs[@]} -eq 0 ]; then
    # Can't just grep for _DSC_URL: rules/iproute2.mk also defines
    # IPROUTE2_DSC_URL, but that one is used for downloading its own
    # upstream .dsc directly and has nothing to do with this design's
    # "stock version + PPA suffix switch" registration scheme (it uses
    # *_VERSION, not *_VERSION_STOCK, so query.mk reports "expected
    # exactly 1 main deb, got \"\"" for it). _VERSION_STOCK is the
    # marker that PPA candidate packages -- and only they -- carry.
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
