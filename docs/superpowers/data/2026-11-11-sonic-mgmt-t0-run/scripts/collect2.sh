#!/bin/bash
# Pull every VM's whole logs dir (no pcaps) into raw/tbN/, plus the balancer state, then assemble main/ and verify/
J=ubuntu@<testflinger-host>; SSHO="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=30"
T=~/scratch/mgmt-ab/tf; mkdir -p $T/raw
timeout 900 ssh $SSHO $J 'rm -rf ~/raw; mkdir -p ~/raw; for i in $(seq 1 12); do
    sudo lxc exec tb$i -- tar czf - -C /home/sheldon-qi/sonic-mgmt/tests --exclude="*.pcap" logs > ~/raw/tb$i.tgz 2>/dev/null
done; cp ~/bal/state.json ~/bal/balancer.log ~/raw/'
scp -q $SSHO "$J:raw/*" $T/raw/ && for i in $(seq 1 12); do rm -rf $T/raw/tb$i; mkdir -p $T/raw/tb$i; tar xzf $T/raw/tb$i.tgz -C $T/raw/tb$i; done
python3 -I $T/assemble.py $T
