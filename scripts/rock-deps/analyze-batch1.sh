#!/bin/bash
# Re-run analyze.py for the batch-1 containers (database radv eventd mgmt-framework) from the collected traces.
# Usage: scripts/rock-deps/analyze-batch1.sh <chisel-release dir> <out dir> [container...]   (from sonic-buildimage root)
# Needs: ~/.cache/rockdeps/{dut2,vs}/<ctr>/trace-*.txt, vs/<ctr>/rootfs.tar, contents/resolute-Contents-amd64.gz
set -euo pipefail
RELEASE=${1:?chisel-release dir}; OUT=${2:?out dir}; shift 2
CACHE=${ROCKDEPS_CACHE:-$HOME/.cache/rockdeps}
declare -A DIR=([database]=docker-database [radv]=docker-router-advertiser [eventd]=docker-eventd
                [mgmt-framework]=docker-sonic-mgmt-framework)
# Paths that only run on configurations the traced devices do not have (static review instead)
declare -A EXTRA=([radv]=/usr/sbin/radvd)
mkdir -p "$OUT"
for c in "${@:-database radv eventd mgmt-framework}"; do
    for ctr in $c; do
        git show "HEAD:dockers/${DIR[$ctr]}/rockcraft.yaml" > "$OUT/$ctr.head-rockcraft.yaml"
        python3 "$(dirname "$0")/analyze.py" --rootfs "$CACHE/vs/$ctr/rootfs.tar" \
            --trace "$CACHE"/dut2/"$ctr"/trace-*.txt "$CACHE"/vs/"$ctr"/trace-*.txt \
            --contents "$CACHE/contents/resolute-Contents-amd64.gz" --chisel-release "$RELEASE" \
            --recipe "$OUT/$ctr.head-rockcraft.yaml" --extra-roots "${EXTRA[$ctr]:-}" --out "$OUT/$ctr.md"
        echo "$ctr -> $OUT/$ctr.md"
    done
done
