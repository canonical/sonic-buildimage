#!/bin/bash
# Pull every testbed's tests/logs (no pcaps), its run logs and the balancer state into results/<stamp>/raw/
J=ubuntu@<arm64-host>; SSHO="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=30 -o ServerAliveInterval=15 -o ServerAliveCountMax=8"
D=~/scratch/mgmt-ab/arm/results/$(date -u +%m%d-%H%M); mkdir -p $D/raw
timeout 1500 ssh $SSHO $J 'mkdir -p ~/col; rm -f ~/col/*; for n in $(seq 1 16); do v=tb$(printf %02d $n)
    sudo lxc exec $v -- tar czf - -C /home/sheldon-qi/sonic-mgmt/tests --exclude="*.pcap" logs > ~/col/$v.tgz 2>/dev/null
    sudo lxc exec $v -- bash -c "cd /home/sheldon-qi && tar czf - *.log 2>/dev/null; true" > ~/col/$v-runlogs.tgz
done; cp ~/bal/state.json ~/bal/balancer.log ~/col/ 2>/dev/null; ls ~/col | wc -l'
for i in 1 2 3; do timeout 1500 scp -q $SSHO "$J:col/*" $D/raw/ && break; sleep 20; done
for f in $D/raw/*.tgz; do gzip -t $f 2>/dev/null || echo "BAD $f"; done
for n in $(seq 1 16); do v=tb$(printf %02d $n); mkdir -p $D/raw/$v; tar xzf $D/raw/$v.tgz -C $D/raw/$v 2>/dev/null; done
echo "collected into $D $(date -Is)"
