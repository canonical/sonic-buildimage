#!/bin/bash
# usage: run_ab.sh <sonic-mgmt dir under /data> <label> [tests...]
# Runs the A/B test list on vms-kvm-t0 from the sonic-mgmt container; logs go to <repo>/tests/logs/<label>.
repo=$1; label=$2; shift 2
tests="$*"
[ -n "$tests" ] || tests="autorestart/test_container_autorestart.py platform_tests/daemon/test_chassisd.py platform_tests/daemon/test_fancontrol.py platform_tests/daemon/test_ledd.py platform_tests/daemon/test_pcied.py platform_tests/daemon/test_psud.py platform_tests/daemon/test_sensord.py platform_tests/daemon/test_syseepromd.py memory_checker/test_memory_checker.py copp/test_copp.py process_monitoring/test_critical_process_monitoring.py"
echo "start $label $(date -Is) repo=$repo"
docker exec --user sheldon-qi sonic-mgmt bash -c "cd /data/$repo/tests && ./run_tests.sh -n vms-kvm-t0 -d vlab-01 -f vtestbed.yaml -i ../ansible/veos_vtb -t t0,any -m individual -O -p logs/$label -c '$tests'"
echo "end $label rc=$? $(date -Is)"
