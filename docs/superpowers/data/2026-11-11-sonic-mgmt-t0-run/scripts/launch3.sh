#!/bin/bash
# On the host: full t0 list on both images at the final branch code, 6 testbeds per image, balancer for the tail
set -u
for i in $(seq 1 6); do for img in r d; do n=t0$img$i
    sudo lxc launch ubuntu:26.04 $n --vm -s big -c limits.cpu=18 -c limits.memory=18GiB -d root,size=140GiB >/dev/null
    sudo lxc config device add $n share disk source=/srv/share path=/srv/share readonly=true >/dev/null
done; done
for i in $(seq 1 6); do for img in r d; do n=t0$img$i
    for t in $(seq 60); do sudo lxc exec $n -- true 2>/dev/null && break; sleep 5; done
done; done
mkdir -p ~/tb3-logs ~/bal3
python3 - <<'PY'
import json
from pathlib import Path
jobs = {}
for i in range(1, 7):
    for img, short in (("rock", "r"), ("df", "d")):
        jobs["t0%s%d" % (short, i)] = {"image": img, "group": "t0", "label": "t0-%s-%d" % (img, i), "shard": "shard-t0-%d" % i,
                                       "testbed": "vms-kvm-t0", "duts": "vlab-01", "marks": "t0,any", "pytest_extra": ""}
Path.home().joinpath("bal3/config.json").write_text(json.dumps({"jobs": jobs}, indent=1))
PY
for i in $(seq 1 6); do
    setsid nohup sudo lxc exec t0r$i -- bash /srv/share/tb-bootstrap2.sh rock vms-kvm-t0 vlab-01 t0,any shard-t0-$i t0-rock-$i > ~/tb3-logs/t0r$i.log 2>&1 < /dev/null &
    setsid nohup sudo lxc exec t0d$i -- bash /srv/share/tb-bootstrap2.sh df vms-kvm-t0 vlab-01 t0,any shard-t0-$i t0-df-$i > ~/tb3-logs/t0d$i.log 2>&1 < /dev/null &
done
echo "LAUNCHED $(date -Is)"
until [ "$(grep -l "TESTBED READY" ~/tb3-logs/t0*.log 2>/dev/null | wc -l)" = 12 ]; do sleep 60; done
sleep 120
BAL_DIR=~/bal3 setsid nohup python3 /srv/share/balancer2.py > ~/bal3/balancer.out 2>&1 < /dev/null &
echo "BALANCER STARTED $(date -Is)"
