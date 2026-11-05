#!/bin/bash
# On a booted SONiC VS switch: rock images must run under pebble with healthy services and clean logs,
# every other container under supervisord. Prints one PASS/FAIL line per container.
# Usage (on the switch): sudo ./vs_rock_runtime_check.sh <rock image name>...   (names from build_rocks.sh --list)
# Needs: docker, sonic-db-cli, config. READY_TIMEOUT is 900s and SETTLE is 60s; both are fixed. Exit 1 on any FAIL.
set -uo pipefail

READY_TIMEOUT=900
SETTLE=60

# Features disabled by default whose containers are rocks; enabled so their rocks run
OPTIONAL_FEATURES=(nat sflow macsec dhcp-relay)
DEFECTS='ImportError|Traceback|cannot open shared object file|undefined symbol|bad interpreter:|panic'

# "<container> <service>" allowed in pebble error state on VS: pmon chassis_db_init has no chassis to init
ALLOWED_ERRORS=("pmon chassis_db_init")

# "<container>|<ERE>": final line of a known benign traceback; each match cancels one Traceback
BENIGN_TRACEBACKS=("gnmi|UndefinedError: 'GNMI' is undefined")

if [ "$#" -le 0 ]; then
    echo "usage: $0 <rock image name>..." >&2
    exit 2
fi

ROCKS=("$@")
failures=0

pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; failures=$((failures + 1)); }

# wait_for <timeout s> <description> <command...>: poll every 10 s; return 1 on timeout
wait_for() {
    local timeout=$1 desc=$2 waited=0
    shift 2
    until "$@" >/dev/null 2>&1; do
        if [ "$waited" -ge "$timeout" ]; then
            echo "WARN timed out after ${timeout}s waiting for ${desc}"
            return 1
        fi
        sleep 10
        waited=$((waited + 10))
    done
    echo "INFO ${desc} after ${waited}s"
}

# Every enabled feature has a running container; featured.timer starts the delayed ones 
# (snmp, lldp, pmon, ...) ~100 s after boot. 
features_up() {
    local keys key
    keys=$(sonic-db-cli CONFIG_DB KEYS 'FEATURE|*') && [ -n "$keys" ] || return 1
    for key in $keys; do
        case "$(sonic-db-cli CONFIG_DB HGET "$key" state)" in
            enabled|always_enabled) container_running "${key#FEATURE|}" || return 1 ;;
        esac
    done
}
container_running() { [ -n "$(docker ps -q --filter "name=^$1\$" --filter status=running)" ]; }
is_rock() { local r; for r in "${ROCKS[@]}"; do [ "$r" = "$1" ] && return 0; done; return 1; }

# Extract image name: docker-lldp:20260101.1 -> docker-lldp
extract_image_name() { local i; i=$(docker inspect -f '{{.Config.Image}}' "$1"); i=${i%%[:@]*}; echo "${i##*/}"; }

# Process names inside a container; Docker requires PID in the selected ps fields.
has_process() {
    local container_name="$1" process_name="$2" processes
    if ! processes=$(docker top "${container_name}" -eo pid,comm 2>&1); then
        printf '%s\n' "$processes" >&2
        return 1
    fi
    awk -v process="${process_name}" 'NR > 1 && $2 == process { found=1 } END { exit !found }' <<< "$processes"
}

# Whether any tag of an image repository is present on the switch
has_image() { [ -n "$(docker images -q "$1")" ]; }

check_rock() {
    local c=$1 services bad svc state allowed logs tb benign entry other
    if ! services=$(docker exec "$c" pebble services 2>&1); then
        fail "$c: rock, but 'pebble services' failed: $services"
        return
    fi
    has_process "$c" pebble || { fail "$c: rock, but no pebble process"; return; }
    has_process "$c" supervisord && { fail "$c: rock, but supervisord is running"; return; }

    # If any service in error/backoff state (and not in ALLOWED_ERRORS list) -> FAIL!
    bad=""
    while read -r svc _ state _; do
        case "$state" in error|backoff) ;; *) continue ;; esac
        allowed=0
        for entry in "${ALLOWED_ERRORS[@]}"; do [ "$entry" = "$c $svc" ] && allowed=1; done
        [ "$allowed" -eq 1 ] || bad+=" ${svc}=${state}"
    done < <(echo "$services" | tail -n +2)
    [ -z "$bad" ] || { fail "$c: pebble services in error/backoff:${bad}"; echo "$services"; return; }

    # Each rock must have active rsyslogd
    echo "$services" | awk '$1 == "rsyslogd" && $3 == "active" {f=1} END {exit !f}' \
        || { fail "$c: rsyslogd is not active"; echo "$services"; return; }

    # Check pebble log
    logs=$(docker exec "$c" pebble logs -n=all 2>&1)
    other=$(echo "$logs" | grep -E "$DEFECTS" | grep -v Traceback)
    tb=$(echo "$logs" | grep -c Traceback)
    benign=0
    for entry in "${BENIGN_TRACEBACKS[@]}"; do
        [ "${entry%%|*}" = "$c" ] && benign=$((benign + $(echo "$logs" | grep -cE "${entry#*|}")))
    done
    if [ -n "$other" ] || [ "$tb" -gt "$benign" ]; then
        fail "$c: defect markers in pebble logs (tracebacks=$tb, benign=$benign)"
        echo "$logs" | grep -E -B2 -A8 "$DEFECTS" | head -60
        return
    fi
    pass "$c: rock under pebble, services healthy, logs clean"
}

check_supervisord() {
    local c=$1 image_name=$2
    has_process "$c" pebble && { fail "$c ($image_name): not in rocklist, but pebble is running"; return; }
    if has_process "$c" supervisord && docker exec "$c" supervisorctl pid >/dev/null 2>&1; then
        pass "$c ($image_name): supervisord"
    else
        fail "$c ($image_name): not in rocklist, but supervisord is not running"
    fi
}

wait_for "$READY_TIMEOUT" "all enabled features running" features_up \
    || fail "not all enabled features reached running state within ${READY_TIMEOUT}s"

# Enable optional features: nat/sflow/iccpd/macsec/...
for f in "${OPTIONAL_FEATURES[@]}"; do
    feature=${f//-/_}
    has_image "docker-$f" || { echo "INFO feature $f: no image, skipped"; continue; }
    config feature state "$feature" enabled
    wait_for 300 "container $feature running" container_running "$feature" || true
done
echo "INFO settling ${SETTLE}s"
sleep "$SETTLE"

docker ps --format '{{.Names}}\t{{.Status}}\t{{.Image}}'
declare -A seen
for c in $(docker ps --format '{{.Names}}' | sort); do
    image_name=$(extract_image_name "$c")
    if is_rock "$image_name"; then
        seen[$image_name]=1
        check_rock "$c"
    else
        check_supervisord "$c" "$image_name"
    fi
done

# For each rock from build_rocks.sh, if it's packed into SONiC installer, 
# it must be launched. Otherwise it's considered an error.
for r in "${ROCKS[@]}"; do
    [ -n "${seen[$r]:-}" ] && continue
    if has_image "$r"; then
        fail "$r: image is on the switch but no running container uses it"
    else
        echo "SKIP $r: image not in this switch image"
    fi
done

echo "pebble processes host-wide: $(pgrep -cx pebble || true)"
if [ "$failures" -gt 0 ]; then
    echo "RESULT: ${failures} check(s) FAILED"
    exit 1
fi
echo "RESULT: all checks passed"
