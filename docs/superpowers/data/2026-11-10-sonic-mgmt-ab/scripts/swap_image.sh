#!/bin/bash
# usage: swap_image.sh <qcow2 image>: make it the vms-kvm-t0 DUT image, then deploy-mg with the new branch.
set -u
image=$1; [ -f "$image" ] || { echo "no image $image"; exit 1; }
tb='cd /data/sonic-mgmt/ansible && ./testbed-cli.sh -t vtestbed.yaml -m veos_vtb'
[ "${SKIP_REMOVE:-}" = 1 ] || docker exec --user sheldon-qi sonic-mgmt bash -c "$tb remove-topo vms-kvm-t0 password.txt" > ~/scratch/mgmt-ab/swap-remove.log 2>&1
echo "remove-topo rc=$? $(date -Is)"
# remove-topo deletes the DUT disk; add-topo copies a fresh one from images/
[ -e ~/sonic-vm/disks/sonic_vlab-01.img ] && sudo mv ~/sonic-vm/disks/sonic_vlab-01.img ~/sonic-vm/disks/sonic_vlab-01.img.prev
for d in ~/sonic-vm/images ~/veos-vm/images; do
    cp --reflink=auto "$image" $d/sonic-vs.img || exit 1
done
echo "images swapped $(date -Is)"
docker exec --user sheldon-qi sonic-mgmt bash -c "$tb add-topo vms-kvm-t0 password.txt" > ~/scratch/mgmt-ab/swap-add.log 2>&1
echo "add-topo rc=$? $(date -Is)"
~/scratch/mgmt-ab/deploy_mg.sh sonic-mgmt > ~/scratch/mgmt-ab/deploy-swap.log 2>&1
tail -1 ~/scratch/mgmt-ab/deploy-swap.log
