#!/bin/bash
# List host-side `docker exec <container> ...` call sites that can hit the batch-1 containers: literal targets in the
# set, plus variable targets (${DOCKERNAME}, database$DEV, loops over all containers). Review the output by hand.
# Usage: scripts/rock-deps/host-callers.sh [container-regex] > host-callers.txt   (default: database|radv|eventd|mgmt-framework)
# Needs: checkout with submodules initialised, grep, awk.
set -euo pipefail
cd "$(dirname "$0")/../.."

ctr=${1:-database|radv|eventd|mgmt-framework}
dirs=(files dockers src/sonic-utilities src/sonic-host-services src/sonic-py-common src/sonic-config-engine
      src/sonic-platform-daemons src/sonic-mgmt-framework src/sonic-gnmi src/sonic-sysmgr)
existing=()
for d in "${dirs[@]}"; do [ -d "$d" ] && existing+=("$d"); done

grep -rnIE --exclude-dir=.git --exclude-dir=tests --exclude-dir=test --exclude='*.md' --exclude='*.txt' \
    -e "docker( +-H +[^ ]+)? +exec" -e "['\"]docker['\"], *['\"]exec['\"]" "${existing[@]}" |
awk -v ours="^(${ctr})$" '
    {
        line = $0
        if (match(line, /docker( +-H +[^ ]+)? +exec( +-[-a-zA-Z=]+)* +[^ ]+/)) {        # shell form
            n = split(substr(line, RSTART, RLENGTH), w, / +/); t = w[n]; gsub(/["\047]/, "", t)
        } else if (match(line, /["\047]exec["\047](, *["\047]-[-a-zA-Z=]+["\047])*, *[^,\]]+/)) {  # python list form
            n = split(substr(line, RSTART, RLENGTH), w, /, */); t = w[n]
            if (t ~ /^["\047]/) { gsub(/["\047]/, "", t) } else { t = "$" t }               # bare name = variable
        } else next
        base = t; sub(/\$.*/, "", base)                                                    # database$DEV -> database
        if (t ~ ours || base ~ ours || (t ~ /[$({]/ && base == "")) print
    }' | sort -u
