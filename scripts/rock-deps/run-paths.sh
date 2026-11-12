#!/bin/bash
# Baseline + dependency collection on one switch: for each path, trace the batch-1 containers with collect.sh,
# then run vs_rock_runtime_check.sh as the baseline verdict. Writes <outdir>/<host>/baseline.md.
# Usage: run-paths.sh <host-label> <outdir> [path...]   paths: hostcmds restart reload cold warm (default: all)
# Needs: collect.sh deps; env ROCKDEPS_SSH / ROCKDEPS_SCP for non-default ssh (e.g. the sonic-vs VM), ROCKDEPS_ROOTFS.
set -uo pipefail

host=$1 outdir=$2
shift 2
paths=("${@:-hostcmds restart reload cold warm}")
read -r -a paths <<< "${paths[*]}"
ctrs=database,radv,eventd,mgmt-framework
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
read -r -a SSH <<< "${ROCKDEPS_SSH:-ssh $host}"
read -r -a SCP <<< "${ROCKDEPS_SCP:-scp -q}"
dest=${ROCKDEPS_SCP_HOST:-$host}
rocks="$("$repo/build_rocks.sh" --list | xargs) docker-syncd-brcm"
mkdir -p "$outdir/$host"
baseline="$outdir/$host/baseline.md"
[ -f "$baseline" ] || printf '# Baseline on %s\n\n| path | collect | runtime check |\n|---|---|---|\n' "$host" > "$baseline"

# /var/tmp, not /tmp: it must survive the warm-reboot path; re-copied before every use
push() { "${SCP[@]}" "$repo/scripts/vs_rock_runtime_check.sh" "$here/hostcmds.sh" "$dest:/var/tmp/" 2>/dev/null; }

declare -A trigger=(
    [hostcmds]="sudo bash /var/tmp/hostcmds.sh"
    [restart]="sudo systemctl restart radv eventd mgmt-framework"
    [reload]="sudo config reload -y"
    [cold]="sudo systemctl restart database"
    [warm]="sudo warm-reboot -v"
)
declare -A settle=([hostcmds]=20 [restart]=240 [reload]=480 [cold]=480 [warm]=600)

for p in "${paths[@]}"; do
    [ -n "${trigger[$p]:-}" ] || { echo "unknown path $p" >&2; exit 2; }
    reboot=0; [ "$p" = warm ] && reboot=1
    push
    if ROCKDEPS_TAG=$p ROCKDEPS_REBOOT=$reboot "$here/collect.sh" "$host" "$ctrs" "$outdir" "${settle[$p]}" \
        "${trigger[$p]}" > "$outdir/$host/collect-$p.log" 2>&1; then c=ok; else c="FAIL (collect-$p.log)"; fi
    push
    "${SSH[@]}" "sudo /var/tmp/vs_rock_runtime_check.sh $rocks" > "$outdir/$host/check-$p.log" 2>/dev/null </dev/null
    v=$(grep -m1 '^RESULT' "$outdir/$host/check-$p.log" || echo "RESULT: no result")
    echo "| $p | $c | ${v#RESULT: } |" >> "$baseline"
    echo "$p: collect $c; $v"
done
