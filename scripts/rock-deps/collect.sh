#!/bin/bash
# Trace which files SONiC containers exec/open on a switch while a trigger runs, plus export their rootfs and pebble plan.
# Usage: collect.sh <host-label> <ctr[,ctr...]> <outdir> <seconds> [trigger-cmd]
#        env: ROCKDEPS_SSH (ssh command prefix, default "ssh <host-label>"), ROCKDEPS_TAG (default run),
#             ROCKDEPS_REBOOT=1 (trigger reboots the switch; wait for it), ROCKDEPS_IMAGE (default rockdeps-bpftrace:1),
#             ROCKDEPS_ROOTFS=0 (skip the rootfs export, e.g. over a slow link)
# Needs: local docker with ROCKDEPS_IMAGE (bpftrace inside), ssh access with docker on the switch; idempotent per tag.
set -euo pipefail

host=$1 ctrs=$2 outdir=$3 seconds=$4 trigger=${5:-}
tag=${ROCKDEPS_TAG:-run}
image=${ROCKDEPS_IMAGE:-rockdeps-bpftrace:1}
read -r -a SSH <<< "${ROCKDEPS_SSH:-ssh $host}"
here=$(cd "$(dirname "$0")" && pwd)
rdir=/var/tmp/rockdeps
IFS=, read -r -a containers <<< "$ctrs"

r() { "${SSH[@]}" "$@" 2>/dev/null; }

wait_ssh() {
    local i
    for i in $(seq 120); do r true </dev/null && return 0; sleep 10; done
    echo "switch $host not reachable after 20 min" >&2; return 1
}

wait_tracer() {  # tracer attached after the latest BOOT marker; fail fast if bpftrace reported an error
    local i
    for i in $(seq 60); do
        r "sudo awk '/^BOOT/{b=0} /^BEGIN/{b=1} END{exit !b}' $rdir/raw.txt" && return 0
        if r "sudo awk '/^BOOT/{e=0} /^ERROR/{e=1} END{exit !e}' $rdir/raw.txt"; then
            r "sudo grep -m3 ^ERROR $rdir/raw.txt" >&2; return 1
        fi
        sleep 5
    done
    echo "tracer did not attach on $host" >&2; return 1
}

# The tracer has --restart=unless-stopped (to survive a reboot trigger); never leave it behind
trap 'r docker rm -f rockdeps-trace >/dev/null 2>&1 || true' EXIT

ids() { for c in "${containers[@]}"; do r docker inspect -f '{{.Id}}' "$c" || true; done; }

# 1. tracer image and script on the switch
r docker image inspect "$image" >/dev/null || docker save "$image" | "${SSH[@]}" docker load
r "sudo mkdir -p $rdir && sudo rm -f $rdir/raw.txt"
"${SSH[@]}" "sudo tee $rdir/trace.bt >/dev/null" < "$here/trace.bt"

before=$(ids)

# 2. start the tracer; it restarts with dockerd after a reboot and appends a new BOOT segment
r docker rm -f rockdeps-trace >/dev/null || true
r docker run -d --name rockdeps-trace --privileged --pid=host --cgroupns=host --restart=unless-stopped \
    --stop-signal=SIGINT --stop-timeout=60 -v /sys:/sys -v $rdir:/out "$image" sh -c \
    "'echo BOOT \$(cat /proc/sys/kernel/random/boot_id) >> /out/raw.txt;
      for d in /sys/fs/cgroup/system.slice/docker-*.scope; do echo \"CGROUP \$(stat -c %i \$d) \${d#/sys/fs/cgroup}\"; done >> /out/raw.txt;
      exec bpftrace /out/trace.bt >> /out/raw.txt 2>&1'" >/dev/null
wait_tracer

# 3. trigger
if [ -n "$trigger" ]; then
    if [ "${ROCKDEPS_REBOOT:-0}" = 1 ]; then
        r "nohup sh -c 'sleep 2; $trigger' >/dev/null 2>&1 &" </dev/null || true
        for _ in $(seq 60); do r true </dev/null || break; sleep 5; done
        wait_ssh
        wait_tracer
    else
        "${SSH[@]}" "$trigger" </dev/null || echo "WARN trigger exited $?" >&2
    fi
fi
sleep "$seconds"

# 4. stop the tracer (SIGINT makes bpftrace print its maps) and fetch the raw log
r docker stop rockdeps-trace >/dev/null
r docker rm rockdeps-trace >/dev/null
after=$(ids)
mkdir -p "$outdir/$host"
raw="$outdir/$host/raw-$tag.txt"
r "sudo cat $rdir/raw.txt" > "$raw"

# 5. split per container: keep map entries whose cgroup id belongs to that container's docker scope
for c in "${containers[@]}"; do
    d="$outdir/$host/$c"
    mkdir -p "$d"
    cids=$(printf '%s\n%s\n' "$before" "$after" | grep -v '^$' | sort -u | tr '\n' ' ')
    for cid in $cids; do
        [ "$(r docker inspect -f '{{.Name}}' "$cid" || true)" = "/$c" ] || continue
        awk -v scope="docker-$cid.scope" '
            /^BOOT/ { delete cg }
            /^CGROUP / { cg[$2] = $3 }
            /^@[xo]\[[0-9]+, .*\]: [0-9]+$/ {
                kind = substr($0, 2, 1); s = $0
                sub(/^@[xo]\[/, "", s); id = s; sub(/,.*/, "", id)
                sub(/^[0-9]+, /, "", s); sub(/\]: [0-9]+$/, "", s)
                if (index(cg[id], scope)) print (kind == "x" ? "EXEC " : "OPEN ") s
            }' "$raw"
    done | sort -u > "$d/trace-$tag.txt"
    if [ "${ROCKDEPS_ROOTFS:-1}" = 1 ] && [ ! -s "$d/rootfs.tar" ]; then
        r "docker export $c | gzip -1" | gunzip > "$d/rootfs.tar.part" && mv "$d/rootfs.tar.part" "$d/rootfs.tar"
    fi
    r docker exec "$c" pebble plan > "$d/plan.yaml" || r docker exec "$c" supervisorctl status > "$d/plan.yaml" || true
    echo "$c: $(wc -l < "$d/trace-$tag.txt") paths -> $d/trace-$tag.txt"
done
