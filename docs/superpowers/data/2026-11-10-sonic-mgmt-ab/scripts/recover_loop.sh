#!/bin/bash
# usage: recover_loop.sh <label prefix> <count>: run test_memory_checker_recover <count> times, print each outcome
for i in $(seq 1 $2); do
    docker exec --user sheldon-qi sonic-mgmt bash -c "cd /data/sonic-mgmt/tests && ./run_tests.sh -n vms-kvm-t0 -d vlab-01 -f vtestbed.yaml -i ../ansible/veos_vtb -t t0,any -m individual -u -r -p logs/$1-$i -c memory_checker/test_memory_checker.py -e '-k test_memory_checker_recover'" > ~/scratch/mgmt-ab/$1-$i.out 2>&1
    x=~/sonic-mgmt/tests/logs/$1-$i/memory_checker/test_memory_checker.xml
    echo "$1-$i $(grep -o '<testsuite [^>]*' $x 2>/dev/null | grep -oE '(errors|failures|tests)="[0-9]+"' | xargs) $(grep -oE 'message="[^"]{0,90}' $x 2>/dev/null | head -1)"
done
