#!/bin/bash
# Prepare the reserved machine for the testbed VMs; the last lines are TESTBEDS=, VCPU= and POOL=.
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive
S=/srv/share
sudo apt-get update -q
sudo apt-get install -y -q docker.io zfsutils-linux zstd python3-yaml >/dev/null
sudo snap install lxd 2>/dev/null || sudo snap refresh lxd || true
sudo lxc storage show default >/dev/null 2>&1 || sudo lxd init --auto --storage-backend dir
root_disk=$(lsblk -no PKNAME "$(findmnt -n -o SOURCE /)")
spare=$(lsblk -dbn -o NAME,TYPE,SIZE,ROTA | awk -v r="$root_disk" '$2 == "disk" && $1 != r && $3 >= 200e9 && $4 == 0 {print "/dev/" $1}' | xargs)
if [ -n "$spare" ]; then
    # shellcheck disable=SC2086
    sudo zpool list tbpool >/dev/null 2>&1 || sudo zpool create -f tbpool $spare
    echo $((8 << 30)) | sudo tee /sys/module/zfs/parameters/zfs_arc_max >/dev/null
    sudo lxc storage show tb >/dev/null 2>&1 || sudo lxc storage create tb zfs source=tbpool
    pool=tb
    pool_gb=$(( $(sudo zpool list -Hp -o free tbpool) / 1000000000 ))
else
    pool=default
    pool_gb=$(( $(df -B1 --output=avail /var/snap/lxd/common/lxd/storage-pools/default | tail -1) / 1000000000 ))
fi
# VM memory is shmem on the host and the VM limits nearly fill RAM.
[ -f /swapfile-host ] || { sudo fallocate -l 64G /swapfile-host && sudo chmod 600 /swapfile-host && sudo mkswap /swapfile-host >/dev/null; }
swapon --show | grep -q /swapfile-host || sudo swapon /swapfile-host
# docker sets the FORWARD policy to DROP, which leaves the LXD VMs without network.
sudo iptables -C DOCKER-USER -i lxdbr0 -j ACCEPT 2>/dev/null || sudo iptables -I DOCKER-USER -i lxdbr0 -j ACCEPT
sudo iptables -C DOCKER-USER -o lxdbr0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
    sudo iptables -I DOCKER-USER -o lxdbr0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
sudo mkdir -p $S /srv/queue
sudo chown ubuntu:ubuntu $S
sudo chmod 1777 /srv/queue
proxy=$(cat /etc/apt/apt.conf /etc/apt/apt.conf.d/* 2>/dev/null | grep -oP 'Acquire::http::Proxy "http://\K[^/"]+' | head -1 || true)
[ -n "$proxy" ] || { echo "no apt proxy configured on the host"; exit 1; }
echo "$proxy" > $S/apt-proxy
# add-topo runs docker-ptf with the tag of the sonic-mgmt branch, 202605 at the pinned commit.
for img in docker-sonic-mgmt:latest docker-ptf:202605; do
    sudo docker pull -q sonicdev-microsoft.azurecr.io:443/$img
    sudo docker save sonicdev-microsoft.azurecr.io:443/$img -o $S/${img%%:*}.tar
done
sudo chown ubuntu:ubuntu $S/*.tar
mem=$(free -g | awk '/^Mem:/{print $2}')
cpu=$(nproc)
t=$(( (mem - 16) / 18 ))
if [ $(( cpu / 8 )) -lt $t ]; then t=$(( cpu / 8 )); fi
if [ $(( pool_gb / 40 )) -lt $t ]; then t=$(( pool_gb / 40 )); fi
[ "$t" -ge 1 ] || { echo "machine too small: mem=${mem}G cpu=$cpu pool=${pool_gb}G"; exit 1; }
echo "TESTBEDS=$t"
echo "VCPU=$(( cpu / t ))"
echo "POOL=$pool"
