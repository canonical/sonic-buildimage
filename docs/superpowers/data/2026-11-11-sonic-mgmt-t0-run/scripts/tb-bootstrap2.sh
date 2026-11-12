#!/bin/bash
# usage: tb-bootstrap2.sh <rock|df> <testbed> <duts> <topology marks> <shard file> <label> [deploy-mg args] [vm type] [pytest args]
#   e.g. tb-bootstrap2.sh rock vms-kvm-t1-lag vlab-03 t1,any shard-t1-1 t1-rock-1
#        tb-bootstrap2.sh df vms-kvm-dual-t0 vlab-05,vlab-06 dualtor,any shard-dualtor-1 dualtor-df-1 "" ceos --disable_loganalyzer
#        tb-bootstrap2.sh df vms-kvm-t0-64-32 vlab-02 t0-sonic,any shard-t0sonic-1 t0sonic-df-1 "" vsonic --neighbor_type=sonic
# Safe to rerun: steps already done are skipped.
set -eux
IMG=$1 TB=$2 DUTS=$3 MARKS=$4 SHARD=$5 LABEL=$6 DEPLOY_EXTRA=${7:-} VMTYPE=${8:-ceos} PYTEST_EXTRA=${9:-}
U=sheldon-qi H=/home/sheldon-qi S=/srv/share
export DEBIAN_FRONTEND=noninteractive
# the LXD VM image keeps its 70G root partition on the 140G disk
growpart /dev/sda 1 || true
resize2fs /dev/sda1 || true
# the t1-lag testbed (24 cEOS) grows past 44 GiB over a few hours and the guest OOM-kills; swap takes the slow growth
if ! swapon --show | grep -q /swapfile; then
    fallocate -l 24G /swapfile && chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile
fi
id $U >/dev/null 2>&1 || useradd -m -s /bin/bash $U
echo "$U ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$U
# the lab only reaches the archive through the host's proxy; https goes direct
echo "Acquire::http::Proxy \"http://$(cat $S/apt-proxy)/\";" > /etc/apt/apt.conf.d/90proxy
# vm_set installs docker-ce from download.docker.com (with apt-key, gone in 26.04) unless a docker source exists
install -d -m 0755 /etc/apt/keyrings
[ -s /etc/apt/keyrings/docker.asc ] || curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
cat > /etc/apt/sources.list.d/docker.sources <<'EOF'
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: resolute
Components: stable
Architectures: amd64
Signed-By: /etc/apt/keyrings/docker.asc
EOF
# a daily upgrade restarts openvswitch, which drops the testbed's flows and cuts every DUT link
systemctl disable --now apt-daily-upgrade.timer apt-daily.timer unattended-upgrades >/dev/null 2>&1 || true
apt-get update -q
apt-get install -y -q docker-ce docker-ce-cli containerd.io libvirt-daemon-system qemu-system-x86 openvswitch-switch \
    bridge-utils j2cli sshpass net-tools ethtool python3-pip xz-utils openssh-server >/dev/null
usermod -aG docker,libvirt,kvm $U
systemctl enable --now ssh docker libvirtd
# ovsdb-server first starts before the ovs-vswitchd alternative exists, and systemd stops retrying
systemctl reset-failed ovsdb-server ovs-vswitchd openvswitch-switch || true
systemctl restart openvswitch-switch
ovs-vsctl show >/dev/null
for d in sonic-vm/images veos-vm/images; do
    mkdir -p $H/$d
    [ -s $H/$d/sonic-vs.img ] || cp $S/sonic-vs-$IMG.img $H/$d/sonic-vs.img
done
if [ "$VMTYPE" = ceos ]; then
    [ -s $H/veos-vm/images/cEOS64-lab-4.32.5M.tar ] || xz -dc $S/cEOS64-lab-4.32.5M.tar.xz > $H/veos-vm/images/cEOS64-lab-4.32.5M.tar
fi
docker image inspect sonicdev-microsoft.azurecr.io:443/docker-sonic-mgmt:latest >/dev/null 2>&1 || docker load -q -i $S/docker-sonic-mgmt.tar
docker image inspect sonicdev-microsoft.azurecr.io:443/docker-ptf:latest >/dev/null 2>&1 || docker load -q -i $S/docker-ptf.tar
docker image inspect publicmirror.azurecr.io:443/debian:trixie >/dev/null 2>&1 || docker pull -q publicmirror.azurecr.io:443/debian:trixie
[ -d $H/sonic-mgmt ] || tar xzf $S/sonic-mgmt.tgz -C $H
chown -R $U:$U $H
ip link show br1 >/dev/null 2>&1 || (cd $H/sonic-mgmt/ansible && ./setup-management-network.sh >/dev/null)
if ! docker start sonic-mgmt >/dev/null 2>&1; then
    docker rm -f sonic-mgmt >/dev/null 2>&1 || true
    su - $U -c "cd $H/sonic-mgmt && ./setup-container.sh -n sonic-mgmt -i sonicdev-microsoft.azurecr.io:443/docker-sonic-mgmt:latest -d /data" | tail -3
fi
K=""; [ "$VMTYPE" = ceos ] || K="-k $VMTYPE"
tb="cd /data/sonic-mgmt/ansible && ./testbed-cli.sh -t vtestbed.yaml -m veos_vtb $K"
# neighbour VMs (vsonic) must run before add-topo binds their interfaces; cEOS containers are created by add-topo
[ "$VMTYPE" = ceos ] || docker exec --user $U sonic-mgmt bash -c "$tb start-topo-vms $TB password.txt" > $H/start-vms.log 2>&1
docker exec --user $U sonic-mgmt bash -c "$tb add-topo $TB password.txt" > $H/add-topo.log 2>&1
docker exec --user $U sonic-mgmt bash -c "$tb deploy-mg $TB veos_vtb password.txt $DEPLOY_EXTRA" > $H/deploy-mg.log 2>&1
echo "TESTBED READY $(date -Is)"
# shard "none": only build the testbed; the balancer hands it work
[ "$SHARD" = none ] && exit 0
tests=$(cat $S/shards/$SHARD | xargs)
E=""; [ -z "$PYTEST_EXTRA" ] || E="-e '$PYTEST_EXTRA'"
docker exec --user $U sonic-mgmt bash -c "cd /data/sonic-mgmt/tests && ./run_tests.sh -n $TB -d $DUTS \
    -f vtestbed.yaml -i ../ansible/veos_vtb -t $MARKS -m individual -O -p logs/$LABEL $E -c '$tests'" > $H/run.log 2>&1 || true
echo "RUN DONE $(date -Is)"
