#!/bin/bash
# Check that every rock of `build_rocks.sh --list` is still a rock in target/ (OCI entrypoint is pebble),
# i.e. no later make run overwrote it with the Dockerfile/supervisord image.
# Usage: scripts/rock_image_check.sh   (after build_rocks.sh and the image rebuild; needs tar, jq)
set -euo pipefail
cd "$(dirname "$0")/.."

fail=0
checked=0
for name in $(./build_rocks.sh --list); do
    gz="target/${name}.gz"
    if [ ! -f "$gz" ]; then
        # build_rocks.sh skips containers disabled in this build config (e.g. INCLUDE_ICCPD=n) the same way
        echo "SKIP ${name}: ${gz} not built in this config"
        continue
    fi
    cfg=$(tar -xOzf "$gz" manifest.json | jq -r '.[0].Config')
    entrypoint=$(tar -xOzf "$gz" "$cfg" | jq -r '.config.Entrypoint // [] | join(" ")')
    checked=$((checked + 1))
    if [ "$(basename "${entrypoint%% *}")" = "pebble" ]; then
        echo "PASS ${name}: entrypoint '${entrypoint}'"
    else
        echo "FAIL ${name}: entrypoint '${entrypoint}' is not pebble; ${gz} is not a rock"
        fail=1
    fi
done

if [ "$checked" -eq 0 ]; then
    echo "FAIL no rock image found in target/"
    fail=1
fi
exit "$fail"
