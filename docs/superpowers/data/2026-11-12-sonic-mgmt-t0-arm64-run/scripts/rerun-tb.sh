#!/bin/bash
# On papat: reset one testbed with deploy-mg, then run a file list.
# usage: rerun-tb.sh <container> <label> <shard file> <eval|plain> [reboot]
# eval: sonic-mgmt sees the arm64 vs DUT under the x86 vs platform name (evaluation only); plain: unchanged tree
set -u
V=$1 LABEL=$2 LIST=$3 MODE=$4 REBOOT=${5:-}
H=/home/sheldon-qi
tb="cd /data/sonic-mgmt/ansible && ./testbed-cli.sh -t vtestbed.yaml -m veos_vtb"
if [ -n "$REBOOT" ]; then
    lxc exec $V -- bash -c "sshpass -p password ssh -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null admin@10.250.0.101 'sudo systemd-run --on-active=2 /sbin/reboot' >/dev/null 2>&1"
    sleep 240
fi
lxc exec $V -- bash -c "docker exec --user sheldon-qi sonic-mgmt bash -c '$tb deploy-mg vms-kvm-t0 veos_vtb password.txt' > $H/deploy-mg-$LABEL.log 2>&1"
lxc exec $V -- bash -c "
  if [ $MODE = eval ]; then
    cp /srv/share/eval-sonic_basic_facts.py $H/sonic-mgmt/ansible/library/sonic_basic_facts.py
    cp /srv/share/eval-dut_basic_facts.py $H/sonic-mgmt/ansible/library/dut_basic_facts.py
    chown sheldon-qi: $H/sonic-mgmt/ansible/library/*_basic_facts.py
  fi
  rm -rf $H/sonic-mgmt/tests/_cache
  tests=\$(cat /srv/share/shards/$LIST | xargs)
  docker exec --user sheldon-qi sonic-mgmt bash -c \"cd /data/sonic-mgmt/tests && ./run_tests.sh -n vms-kvm-t0 -d vlab-01 -f vtestbed.yaml -i ../ansible/veos_vtb -t t0,any -m individual -O -p logs/$LABEL -c '\$tests'\" > $H/run-$LABEL.log 2>&1
"
echo "$V $LABEL $MODE done $(date -Is)"
