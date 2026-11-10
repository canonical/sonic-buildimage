#!/bin/bash
# deploy-mg vms-kvm-t0 from the given sonic-mgmt dir under /data
repo=${1:-sonic-mgmt}
docker exec --user sheldon-qi sonic-mgmt bash -c "cd /data/$repo/ansible && ./testbed-cli.sh -t vtestbed.yaml -m veos_vtb deploy-mg vms-kvm-t0 veos_vtb password.txt"
echo "deploy-mg rc=$? $(date -Is)"
