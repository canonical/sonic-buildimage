#!/bin/bash
# On papat (arm64, as ubuntu with passwordless sudo): docker for the SONiC build, amd64 binfmt for the
# amd64-only testbed images, LXD system containers for the testbeds
set -eux
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -q
sudo apt-get install -y -q docker.io docker-buildx python3-pip git make jq xz-utils zstd pigz qemu-system-arm qemu-utils mtools dosfstools \
    python3-pexpect sshpass >/dev/null
sudo usermod -aG docker,kvm ubuntu
pip3 install --user --quiet --break-system-packages jinjanator
# SONiC build needs (memory: sonic-build-restore): AppArmor gs override, ip_tables loaded
printf '  owner file rw /sonic/**,\n  owner file rw /var/*/**,\n' | sudo tee /etc/apparmor.d/local/gs >/dev/null
sudo apparmor_parser -r /etc/apparmor.d/gs || true
sudo mkdir -p /var/cache/sonic/artifacts/vcache && sudo chmod -R 777 /var/cache/sonic/artifacts
# docker-ptf, docker-sonic-mgmt and cEOS are amd64 only; the F flag lets the containers use the host's qemu
# registered through binfmt.d: any systemd-binfmt restart (apt triggers one) drops entries registered by hand
id=$(sudo docker create tonistiigi/binfmt:qemu-v9.2.2)
sudo docker cp $id:/usr/bin/qemu-x86_64 /usr/local/bin/qemu-x86_64-static
sudo docker rm $id >/dev/null
printf ':qemu-x86_64:M::\\x7fELF\\x02\\x01\\x01\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x02\\x00\\x3e\\x00:\\xff\\xff\\xff\\xff\\xff\\xfe\\xfe\\x00\\xff\\xff\\xff\\xff\\xff\\xff\\xff\\xff\\xfe\\xff\\xff\\xff:/usr/local/bin/qemu-x86_64-static:POCF\n' | sudo tee /etc/binfmt.d/qemu-x86_64.conf >/dev/null
sudo systemctl restart systemd-binfmt
cat /proc/sys/fs/binfmt_misc/qemu-x86_64 | head -5
# testbed containers cannot load modules: load them here
for m in ip_tables ip6_tables iptable_nat iptable_filter iptable_mangle iptable_raw ip6table_filter ip6table_nat ip6table_mangle \
         nf_nat nf_conntrack xt_conntrack xt_MASQUERADE xt_addrtype xt_mark xt_comment xt_multiport xt_nat br_netfilter \
         openvswitch 8021q bonding team team_mode_loadbalance team_mode_lacp vxlan tun vhost_net veth macvlan macvtap dummy \
         ebtables ebtable_filter ebtable_nat nf_tables nft_compat loop sch_netem ipip ip6_tunnel ip_gre ip6_gre; do
    sudo modprobe $m 2>/dev/null || echo "module $m not available"
done
echo ip_tables | sudo tee /etc/modules-load.d/ip_tables.conf >/dev/null
# sysctls that are not per network namespace (vm_set host_setup sets them per testbed host)
sudo sysctl -q -w kernel.pty.max=8192 kernel.pid_max=4194304 fs.inotify.max_user_instances=62800 \
    fs.inotify.max_user_watches=4194304 net.core.rmem_max=509430500 net.core.rmem_default=31457280 \
    kernel.keys.maxkeys=20000 kernel.keys.maxbytes=2000000 fs.aio-max-nr=1048576 vm.max_map_count=1048576
sudo snap install lxd 2>/dev/null || sudo snap refresh lxd || true
sudo lxd init --auto
sudo usermod -aG lxd ubuntu
# docker sets the FORWARD policy to DROP, which leaves the LXD containers without network
sudo iptables -C DOCKER-USER -i lxdbr0 -j ACCEPT 2>/dev/null || sudo iptables -I DOCKER-USER -i lxdbr0 -j ACCEPT
sudo iptables -C DOCKER-USER -o lxdbr0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
    sudo iptables -I DOCKER-USER -o lxdbr0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
sudo mkdir -p /srv/share/shards && sudo chown -R ubuntu:ubuntu /srv/share
grep -rh "Proxy" /etc/apt/apt.conf.d/ 2>/dev/null | head -2
echo HOST SETUP DONE
