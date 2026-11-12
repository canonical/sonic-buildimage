#!/bin/bash
# In a privileged LXD container on the arm64 host. usage: tb-bootstrap-arm.sh <shard file|none> <label> [testbed] [duts] [marks]
# Same steps as tb-bootstrap2.sh on amd64; differences are marked. Safe to rerun: steps already done are skipped.
set -eux
SHARD=$1 LABEL=$2 TB=${3:-vms-kvm-t0} DUTS=${4:-vlab-01} MARKS=${5:-t0,any}
U=sheldon-qi H=/home/sheldon-qi S=/srv/share
export DEBIAN_FRONTEND=noninteractive
id $U >/dev/null 2>&1 || useradd -m -s /bin/bash $U
echo "$U ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$U
[ -s $S/apt-proxy ] && echo "Acquire::http::Proxy \"http://$(cat $S/apt-proxy)/\";" > /etc/apt/apt.conf.d/90proxy
install -d -m 0755 /etc/apt/keyrings
[ -s /etc/apt/keyrings/docker.asc ] || curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
# arm64: docker-ce for arm64
cat > /etc/apt/sources.list.d/docker.sources <<'EOS'
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: resolute
Components: stable
Architectures: arm64
Signed-By: /etc/apt/keyrings/docker.asc
EOS
systemctl disable --now apt-daily-upgrade.timer apt-daily.timer unattended-upgrades >/dev/null 2>&1 || true
apt-get update -q
# arm64: qemu-system-arm, plus the packages vm_set's host_setup installs (skipped below)
apt-get install -y -q docker-ce docker-ce-cli containerd.io libvirt-daemon-system libvirt-clients qemu-system-arm \
    openvswitch-switch bridge-utils j2cli sshpass net-tools ethtool python3-pip xz-utils openssh-server ifupdown vlan \
    acl python3-libvirt python3-lxml iproute2 util-linux curl >/dev/null
# arm64: resolute's edk2 2025.11 crashes under KVM (memory: resolute-edk2-2025.11-kvm-fault); use 2026.05
# unpacked, not installed: the package wants a newer qemu (ubuntu-virt >= 11.0.3); host_vars point vm_set here
[ -s /opt/aavmf/usr/share/AAVMF/AAVMF_CODE.no-secboot.fd ] || dpkg-deb -x $S/qemu-efi-aarch64.deb /opt/aavmf
usermod -aG docker,libvirt,kvm $U
# container: libvirt has no AppArmor driver here; the DUT template drops its seclabel (vm_seclabel: false)
grep -q '^security_driver = "none"' /etc/libvirt/qemu.conf || echo 'security_driver = "none"' >> /etc/libvirt/qemu.conf
systemctl enable --now ssh docker libvirtd
systemctl restart libvirtd
systemctl reset-failed ovsdb-server ovs-vswitchd openvswitch-switch || true
systemctl restart openvswitch-switch
ovs-vsctl show >/dev/null
# container: vm_set host_setup would set host-wide sysctls from inside the container and fail; the host sets those,
# the per-namespace ones are set here, and the flag file makes vm_set skip host_setup
for kv in net.bridge.bridge-nf-call-arptables=0 net.bridge.bridge-nf-call-ip6tables=0 net.bridge.bridge-nf-call-iptables=0 \
          net.ipv6.route.max_size=16384 net.ipv4.neigh.default.gc_thresh1=8192 net.ipv6.neigh.default.gc_thresh1=8192 \
          net.ipv4.neigh.default.gc_thresh2=16384 net.ipv6.neigh.default.gc_thresh2=16384 \
          net.ipv4.neigh.default.gc_thresh3=32768 net.ipv6.neigh.default.gc_thresh3=32768; do
    sysctl -q -w $kv || echo "sysctl $kv failed"
done
mkdir -p /opt/sonic-testbed && echo -n 1 > /opt/sonic-testbed/.host_setup_done
setfacl -m u:libvirt-qemu:x $H
# the DUT image is made after the SONiC build; everything above can run before it exists
until [ -s $S/sonic-vs-arm64.img.done ]; do sleep 30; done
for d in sonic-vm/images veos-vm/images; do
    mkdir -p $H/$d
    [ -s $H/$d/sonic-vs.img ] || cp $S/sonic-vs-arm64.img $H/$d/sonic-vs.img
done
# arm64: cEOS 4.32.5M has no arm64 build; cEOSarm 4.35.7.2M (ceos.yml in the tarball points to it)
[ -s $H/veos-vm/images/cEOSarm-lab-4.35.7.2M.tar ] || cp $S/cEOSarm-lab-4.35.7.2M.tar $H/veos-vm/images/
docker image inspect sonicdev-microsoft.azurecr.io:443/docker-sonic-mgmt:latest >/dev/null 2>&1 || docker load -q -i $S/docker-sonic-mgmt.tar
docker image inspect sonicdev-microsoft.azurecr.io:443/docker-ptf:latest >/dev/null 2>&1 || docker load -q -i $S/docker-ptf.tar
docker image inspect publicmirror.azurecr.io:443/debian:trixie >/dev/null 2>&1 || docker load -q -i $S/debian-trixie.tar
# vm_set runs ptf by the 202605 tag, which docker would otherwise pull from the registry as amd64
P=sonicdev-microsoft.azurecr.io:443/docker-ptf
if [ "$(docker image inspect -f '{{.Architecture}}' $P:202605 2>/dev/null)" != arm64 ]; then
    docker rm -f ptf_vms6-1 >/dev/null 2>&1 || true
    docker rmi -f $P:202605 >/dev/null 2>&1 || true
    docker tag $P:latest $P:202605
fi
[ -d $H/sonic-mgmt ] || tar xzf $S/sonic-mgmt.tgz -C $H
chown -R $U:$U $H
ip link show br1 >/dev/null 2>&1 || (cd $H/sonic-mgmt/ansible && ./setup-management-network.sh >/dev/null)
# a setup-container.sh that failed half way leaves a container without the user
if ! { docker start sonic-mgmt >/dev/null 2>&1 && docker exec sonic-mgmt id $U >/dev/null 2>&1; }; then
    docker rm -f sonic-mgmt >/dev/null 2>&1 || true
    # arm64: the registry image is amd64 only; $S/docker-sonic-mgmt.tar is a native build from the same Dockerfile
    su - $U -c "cd $H/sonic-mgmt && ./setup-container.sh -n sonic-mgmt -i sonicdev-microsoft.azurecr.io:443/docker-sonic-mgmt:latest -d /data" | tail -3
fi
tb="cd /data/sonic-mgmt/ansible && ./testbed-cli.sh -t vtestbed.yaml -m veos_vtb"
docker exec --user $U sonic-mgmt bash -c "$tb add-topo $TB password.txt" > $H/add-topo.log 2>&1
docker exec --user $U sonic-mgmt bash -c "$tb deploy-mg $TB veos_vtb password.txt" > $H/deploy-mg.log 2>&1
echo "TESTBED READY $(date -Is)"
[ "$SHARD" = none ] && exit 0
tests=$(cat $S/shards/$SHARD | xargs)
docker exec --user $U sonic-mgmt bash -c "cd /data/sonic-mgmt/tests && ./run_tests.sh -n $TB -d $DUTS \
    -f vtestbed.yaml -i ../ansible/veos_vtb -t $MARKS -m individual -O -p logs/$LABEL -c '$tests'" > $H/run.log 2>&1 || true
echo "RUN DONE $(date -Is)"
