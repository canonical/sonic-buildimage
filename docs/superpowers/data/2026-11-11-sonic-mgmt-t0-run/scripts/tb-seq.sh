#!/bin/bash
# usage: tb-seq.sh <rock|df>
# One VM, three small topologies in turn: dualtor, then t0 with two VLANs, then t0-64-32 with vSONiC neighbours.
set -eux
IMG=$1 U=sheldon-qi H=/home/sheldon-qi S=/srv/share
MACSEC="--neighbor_type=sonic --enable_macsec --macsec_profile=128_SCI,256_XPN_SCI"
cli() { docker exec --user $U sonic-mgmt bash -c "cd /data/sonic-mgmt/ansible && ./testbed-cli.sh -t vtestbed.yaml -m veos_vtb $*"; }
run() {  # <testbed> <duts> <marks> <shard> <label> [pytest args]
    tests=$(cat $S/shards/$4 | xargs)
    E=""; [ -z "${6:-}" ] || E="-e '$6'"
    docker exec --user $U sonic-mgmt bash -c "cd /data/sonic-mgmt/tests && ./run_tests.sh -n $1 -d $2 \
        -f vtestbed.yaml -i ../ansible/veos_vtb -t $3 -m individual -O -p logs/$5 $E -c '$tests'" > $H/run-$5.log 2>&1 || true
    echo "STAGE DONE $5 $(date -Is)"
}
# stage 1: dualtor, through the common bootstrap (installs the VM, add-topo, deploy-mg, runs the shard)
bash $S/tb-bootstrap2.sh $IMG vms-kvm-dual-t0 vlab-05,vlab-06 dualtor,any shard-dualtor-1 dualtor-$IMG-1 "" ceos --disable_loganalyzer
echo "STAGE DONE dualtor-$IMG-1 $(date -Is)"
cli remove-topo vms-kvm-dual-t0 password.txt > $H/remove-dualtor.log 2>&1
# stage 2: t0 with the two-VLAN configuration
cli add-topo vms-kvm-t0 password.txt > $H/add-topo-t0.log 2>&1
cli deploy-mg vms-kvm-t0 veos_vtb password.txt -e vlan_config=two_vlan_a > $H/deploy-mg-t0.log 2>&1
run vms-kvm-t0 vlab-01 t0,any shard-t02vlans-1 t02vlans-$IMG-1
cli remove-topo vms-kvm-t0 password.txt > $H/remove-t0.log 2>&1
# stage 3: t0-64-32 with vSONiC neighbours, which must run before add-topo binds them
cli -k vsonic start-topo-vms vms-kvm-t0-64-32 password.txt > $H/start-vms-t0sonic.log 2>&1
cli -k vsonic add-topo vms-kvm-t0-64-32 password.txt > $H/add-topo-t0sonic.log 2>&1
cli -k vsonic deploy-mg vms-kvm-t0-64-32 veos_vtb password.txt > $H/deploy-mg-t0sonic.log 2>&1
run vms-kvm-t0-64-32 vlab-02 t0-sonic,any shard-t0sonic-1 t0sonic-$IMG-1 "$MACSEC"
echo "SEQ DONE $(date -Is)"
