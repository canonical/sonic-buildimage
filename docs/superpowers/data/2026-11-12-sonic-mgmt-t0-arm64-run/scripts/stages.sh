#!/bin/bash
# On papat: one line per testbed container: bootstrap state and stage
for n in $(seq 1 16); do
    i=$(printf %02d $n)
    lxc exec tb$i -- bash -c '
        r=$(ps -eo args | grep -c "^bash /srv/share/tb-bootstrap-arm.sh" | sed "s/^0$/stop/; s/^[1-9].*/run/")
        L=$(ls -t /root/bootstrap*.log 2>/dev/null | head -1)
        s=$(grep -oE "add-topo|deploy-mg|setup-container|run_tests|TESTBED READY|RUN DONE" $L 2>/dev/null | tail -1)
        f=$(grep -c "^fatal" /home/sheldon-qi/add-topo.log 2>/dev/null)
        rc=$(grep -A3 "PLAY RECAP" /home/sheldon-qi/deploy-mg.log 2>/dev/null | grep -oE "failed=[0-9]+" | sort -u | tr "\n" " ")
        echo "'tb$i' $r ${s:-prep} addtopo_fatal=${f:-0} deploy:${rc:-none}"' 2>/dev/null || echo "tb$i ?"
done
