#!/bin/bash
# Machine side of the resolute t0 run, started detached by agent.sh; everything lands in ~/t0-out.
set -euo pipefail
T0=$(cd "$(dirname "$0")" && pwd)
OUT=$HOME/t0-out S=/srv/share Q=/srv/queue
CEOS=ghcr.io/canonical/sonic-ceos:4.32.5M-1
MGMT_IMAGE=sonicdev-microsoft.azurecr.io:443/docker-sonic-mgmt:latest
START=$(date +%s)
DISPATCH_STOP=$((START + 37800))
HARD_STOP=$((START + 41400))
mkdir -p "$OUT"
: > "$OUT/progress.log"
phase=start phase_start=$START phases="" testbeds=0 time_guard=false
progress() { echo "$(date -u +%FT%TZ) $*" | tee -a "$OUT/progress.log"; }
enter() {
    local now
    now=$(date +%s)
    [ "$phase" = start ] || phases="$phases $phase=$((now - phase_start))"
    phase=$1 phase_start=$now
    progress "phase $phase"
}
finish() {
    local rc=$? failed=$phase
    set +e
    enter packing
    [ ! -d $Q/results ] || sudo tar -C $Q -cf - results | zstd -19 -T0 -q --force -o "$OUT/results.tar.zst"
    RC=$rc PHASE=$failed PHASES="$phases" TESTBEDS=$testbeds TIME_GUARD=$time_guard MGMT=$(cat "$T0/sonic-mgmt.ref") \
        python3 - "$OUT/files.txt" "$OUT/run-meta.json" <<'EOF'
import json, os, socket, sys
from pathlib import Path
files = Path(sys.argv[1]).read_text().split() if Path(sys.argv[1]).exists() else []
Path(sys.argv[2]).write_text(json.dumps({
    "machine": socket.gethostname(), "testbeds": int(os.environ["TESTBEDS"]),
    "artifact_id": os.environ.get("ARTIFACT_ID", ""), "image_sha256": os.environ.get("IMAGE_SHA256", ""),
    "sonic_mgmt": os.environ["MGMT"], "scope": os.environ.get("SCOPE", ""), "files": files,
    "phases": {k: int(v) for k, v in (p.split("=") for p in os.environ["PHASES"].split())},
    "time_guard": os.environ["TIME_GUARD"] == "true", "rc": int(os.environ["RC"]), "phase": os.environ["PHASE"]},
    indent=1))
EOF
    progress "exit $rc"
    echo "$rc" > "$OUT/EXIT"
}
trap finish EXIT
progress "start scope=$SCOPE artifact=$REPO/$ARTIFACT_ID"

enter host-setup
bash "$T0/host-setup.sh" > "$OUT/host-setup.log" 2>&1
TESTBEDS=0 VCPU=0 POOL=default
eval "$(grep -E '^(TESTBEDS|VCPU|POOL)=[A-Za-z0-9_-]+$' "$OUT/host-setup.log")"
testbeds=$TESTBEDS
if [ "$SCOPE" = smoke ] && [ "$testbeds" -gt 2 ]; then testbeds=2; fi
progress "testbeds=$testbeds vcpu=$VCPU pool=$POOL"

enter payload
# GH_TOKEN is the workflow job's own token, read-only for actions and packages; it dies with that job.
zip=$S/sonic-vs-img.zip
for _ in 1 2 3; do
    url=$(curl -fsS -o /dev/null -w '%{redirect_url}' -H @<(printf 'Authorization: Bearer %s\n' "$GH_TOKEN") \
        "https://api.github.com/repos/$REPO/actions/artifacts/$ARTIFACT_ID/zip") || url=""
    if [ -n "$url" ] && curl -fsSL -o "$zip" "$url"; then break; fi
    rm -f "$zip"
    sleep 30
done
echo "${ARTIFACT_DIGEST#sha256:}  $zip" | sha256sum -c -
python3 -m zipfile -e "$zip" $S
rm -f "$zip"
IMAGE_SHA256=$(sha256sum $S/sonic-vs.img.gz | cut -d' ' -f1)
export IMAGE_SHA256
gunzip -f $S/sonic-vs.img.gz
dc=$(mktemp -d -p /dev/shm)
printf '%s' "$GH_TOKEN" | sudo env DOCKER_CONFIG="$dc" docker login ghcr.io -u token --password-stdin >/dev/null
sudo env DOCKER_CONFIG="$dc" docker pull -q $CEOS
sudo rm -rf "$dc"
unset GH_TOKEN
sudo docker tag $CEOS ceosimage:4.32.5M-1
sudo docker save ceosimage:4.32.5M-1 -o $S/ceos.tar
sudo chown ubuntu:ubuntu $S/ceos.tar
rm -rf $S/sonic-mgmt
mkdir -p $S/sonic-mgmt
curl -fsSL --retry 5 "https://codeload.github.com/canonical/sonic-mgmt/tar.gz/$(cat "$T0/sonic-mgmt.ref")" | tar -xz -C $S/sonic-mgmt --strip-components=1
openssl rand -hex 12 > $S/tb-pass
python3 "$T0/configure_sonic_mgmt.py" $S/sonic-mgmt tb "$(cat $S/tb-pass)"
rm -rf $S/t0
cp -a "$T0" $S/t0
rm -f $S/issue-proxy
if [ -s "$T0/issue-states.json" ]; then
    gw=$(sudo lxc network get lxdbr0 ipv4.address | cut -d/ -f1)
    setsid nohup python3 "$T0/issue_states.py" serve --states "$T0/issue-states.json" --host "$gw" --port 8737 \
        > "$OUT/issue-proxy.log" 2>&1 < /dev/null &
    echo "http://$gw:8737" > $S/issue-proxy
fi

enter test-list
if [ "$SCOPE" = smoke ]; then
    cp "$T0/smoke.txt" "$OUT/files.txt"
else
    # run_tests.sh silently drops files under its SKIP_FOLDERS.
    sudo docker run --rm -v $S/sonic-mgmt:/sm:ro -w /sm/.azure-pipelines/impacted_area_testing $MGMT_IMAGE \
        python3 get_test_scripts.py --features "" --location /sm/tests \
        | python3 -c 'import json, sys; print("\n".join(json.load(sys.stdin)["t0_checker"]))' \
        | grep -vE '^(ptftests|acstests|saitests|scripts|k8s|sai_qualify)/' > "$OUT/files.txt"
fi
progress "$(wc -l < "$OUT/files.txt") test files"
sudo rm -rf $Q/pending $Q/claimed $Q/done $Q/finished $Q/results $Q/STOP
mkdir -p $Q/pending $Q/finished
target=auto
if [ "$SCOPE" = smoke ]; then target=1; fi
python3 "$T0/make_chunks.py" "$OUT/files.txt" "$T0/durations.json" $Q/pending $target 480 "$testbeds"

enter testbeds
for i in $(seq 1 "$testbeds"); do
    sudo lxc delete -f tb$i >/dev/null 2>&1 || true
    sudo lxc init ubuntu:26.04 tb$i --vm -s "$POOL" -c limits.cpu="$VCPU" -c limits.memory=18GiB -d root,size=140GiB
    sudo lxc config device add tb$i share disk source=$S path=$S readonly=true
    sudo lxc config device add tb$i queue disk source=$Q path=$Q
    sudo lxc start tb$i
done
for i in $(seq 1 "$testbeds"); do
    for _ in $(seq 120); do sudo lxc exec tb$i -- true 2>/dev/null && break; sleep 5; done
    if ! sudo lxc exec tb$i -- true 2>/dev/null; then
        echo "vm did not boot" > $Q/finished/tb$i
        progress "tb$i did not boot"
        continue
    fi
    setsid nohup sudo lxc exec tb$i -- bash $S/t0/tb-run.sh tb$i > "$OUT/tb-$i.log" 2>&1 < /dev/null &
    # Many lxc exec calls at once fail with "transient scope not created".
    sleep 5
done

enter tests
while :; do
    now=$(date +%s)
    progress "chunks pending=$(ls $Q/pending | wc -l) running=$(ls $Q/claimed | wc -l) done=$(ls $Q/done | wc -l); testbeds finished=$(ls $Q/finished | wc -l)/$testbeds"
    if [ "$(ls $Q/finished | wc -l)" -ge "$testbeds" ]; then break; fi
    if [ "$now" -ge $DISPATCH_STOP ] && [ ! -e $Q/STOP ]; then
        touch $Q/STOP
        time_guard=true
        progress "time guard: no new chunks from now on"
    fi
    if [ "$now" -ge $HARD_STOP ]; then
        progress "hard stop: packing the results that exist"
        break
    fi
    sleep 300
done
if [ "$(ls $Q/done | wc -l)" -eq 0 ]; then
    progress "no chunk finished on any testbed"
    exit 3
fi
