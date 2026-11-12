#!/bin/bash
# On the big host (as ubuntu, passwordless sudo): LXD on a ZFS stripe of the two spare NVMe disks, docker images in /srv/share
set -eux
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -q
sudo apt-get install -y -q docker.io zfsutils-linux >/dev/null
sudo snap install lxd 2>/dev/null || sudo snap refresh lxd || true
# stripe every NVMe disk except the one holding /; never touch the root disk
root_disk=$(lsblk -no PKNAME "$(findmnt -n -o SOURCE /)")
spare=$(lsblk -dn -o NAME,TYPE | awk -v r="$root_disk" '$2 == "disk" && $1 ~ /^nvme/ && $1 != r {print "/dev/" $1}')
[ -n "$spare" ] && [ -n "$root_disk" ]
echo "root disk $root_disk, pool disks: $spare"
sudo zpool list tbpool 2>/dev/null || sudo zpool create -f tbpool $spare
# keep the ZFS ARC small: the testbed VMs need the memory
echo $((8 << 30)) | sudo tee /sys/module/zfs/parameters/zfs_arc_max >/dev/null
# VM memory is shmem on the host; the sum of the VM limits nearly fills RAM, so give the host swap
[ -f /swapfile-host ] || { sudo fallocate -l 64G /swapfile-host && sudo chmod 600 /swapfile-host && sudo mkswap /swapfile-host >/dev/null; }
swapon --show | grep -q /swapfile-host || sudo swapon /swapfile-host
sudo lxd init --auto
sudo lxc storage show big >/dev/null 2>&1 || sudo lxc storage create big zfs source=tbpool
# docker sets the FORWARD policy to DROP, which leaves the LXD VMs without network
sudo iptables -C DOCKER-USER -i lxdbr0 -j ACCEPT 2>/dev/null || sudo iptables -I DOCKER-USER -i lxdbr0 -j ACCEPT
sudo iptables -C DOCKER-USER -o lxdbr0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
    sudo iptables -I DOCKER-USER -o lxdbr0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
sudo usermod -aG lxd,docker ubuntu
sudo mkdir -p /srv/share/shards && sudo chown -R ubuntu:ubuntu /srv/share
# the VMs reach the archive through the same apt proxy as the host
grep -rhoP 'Acquire::http::Proxy "http://\K[^/"]+' /etc/apt/apt.conf.d/ | head -1 > /srv/share/apt-proxy
[ -s /srv/share/apt-proxy ]
for img in docker-sonic-mgmt docker-ptf; do
    sudo docker pull -q sonicdev-microsoft.azurecr.io:443/$img:latest
    sudo docker save sonicdev-microsoft.azurecr.io:443/$img:latest -o /srv/share/$img.tar
done
sudo chown ubuntu:ubuntu /srv/share/*.tar
echo "HOST SETUP DONE $(date -Is)"
