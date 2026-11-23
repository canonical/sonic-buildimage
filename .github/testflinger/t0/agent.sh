#!/bin/bash
# Agent side of the resolute t0 job: start the harness detached on the machine, relay progress, fetch the results.
set -u
opts=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o ConnectTimeout=30
      -o ServerAliveInterval=60 -o LogLevel=ERROR)
m=ubuntu@$DEVICE_IP
on() { ssh "${opts[@]}" "$m" "$@"; }
mkdir -p artifacts
scp "${opts[@]}" attachments/test/t0-harness.tar.gz "$m:t0-harness.tar.gz" || exit 1
on 'rm -rf t0 t0-out && mkdir -p t0 t0-out && tar -xzf t0-harness.tar.gz -C t0' || exit 1
# The token reaches the detached harness through stdin and its environment, never a command line.
printf '%s\n' "${GH_TOKEN:-}" | on "read -r GH_TOKEN; export GH_TOKEN REPO='$REPO' ARTIFACT_ID='$ARTIFACT_ID' \
ARTIFACT_DIGEST='$ARTIFACT_DIGEST' SCOPE='$SCOPE'; \
setsid nohup bash t0/run-t0.sh > t0-out/run-t0.log 2>&1 < /dev/null &" || exit 1
seen=0
while :; do
    sleep 60
    finished=no
    on 'test -e t0-out/EXIT' && finished=yes
    if new=$(on "tail -n +$((seen + 1)) t0-out/progress.log 2>/dev/null") && [ -n "$new" ]; then
        printf '%s\n' "$new"
        seen=$((seen + $(printf '%s\n' "$new" | wc -l)))
    fi
    [ "$finished" = yes ] && break
done
for f in results.tar.zst run-meta.json run-t0.log host-setup.log 'tb-*.log'; do
    scp "${opts[@]}" "$m:t0-out/$f" artifacts/ || true
done
rc=$(on 'cat t0-out/EXIT' 2>/dev/null)
exit "${rc:-1}"
