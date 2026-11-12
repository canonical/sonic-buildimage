#!/bin/bash
# On papat: launch tb01..tb16 and start each one's bootstrap on its shard; the balancer takes over afterwards
set -u
bash /srv/share/launch-arm.sh 1 16 >/dev/null
for n in $(seq 1 16); do
    i=$(printf %02d $n)
    for k in $(seq 1 60); do lxc exec tb$i -- systemctl is-system-running 2>/dev/null | grep -qE "running|degraded" && break; sleep 2; done
    # no pgrep guard: it would match this bash -c command line itself
    lxc exec tb$i -- bash -c "[ -e /root/bootstrap.log ] || setsid nohup bash /srv/share/tb-bootstrap-arm.sh shard-arm-$n t0-arm-$n > /root/bootstrap.log 2>&1 < /dev/null &"
    echo "tb$i started $(date -Is)"
    sleep 5
done
