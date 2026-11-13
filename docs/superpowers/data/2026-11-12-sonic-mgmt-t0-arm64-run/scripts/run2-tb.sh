#!/bin/bash
# On papat: swap a testbed to the arm64 sonic-mgmt branch, reset it with deploy-mg and run its shard
# usage: run2-tb.sh <container> <n>
set -u
V=$1 N=$2 H=/home/sheldon-qi
tb="cd /data/sonic-mgmt/ansible && ./testbed-cli.sh -t vtestbed.yaml -m veos_vtb"
lxc exec $V -- bash -c "
  docker exec ptf_vms6-1 chmod 0755 /etc/init.d/tacacs_plus /ptf_tgen/ptf_tgen.sh
  cd $H && { [ -d sonic-mgmt.main ] || mv sonic-mgmt sonic-mgmt.main; }
  rm -rf $H/sonic-mgmt && tar xzf /srv/share/sonic-mgmt-arm64.tgz -C $H && chown -R sheldon-qi: $H/sonic-mgmt
  [ -f $H/run.log ] && mv $H/run.log $H/run-main.log
  docker exec --user sheldon-qi sonic-mgmt bash -c '$tb deploy-mg vms-kvm-t0 veos_vtb password.txt' > $H/deploy-mg-arm2.log 2>&1
  tests=\$(cat /srv/share/shards/shard-arm-$N | xargs)
  docker exec --user sheldon-qi sonic-mgmt bash -c \"cd /data/sonic-mgmt/tests && ./run_tests.sh -n vms-kvm-t0 -d vlab-01 -f vtestbed.yaml -i ../ansible/veos_vtb -t t0,any -m individual -O -p logs/t0-arm2-$N -c '\$tests'\" > $H/run.log 2>&1
"
echo "$V t0-arm2-$N done $(date -Is)"
