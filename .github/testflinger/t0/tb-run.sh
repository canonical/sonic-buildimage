#!/bin/bash
# One vms-kvm-t0 testbed in an LXD VM, then chunks from /srv/queue; usage: tb-run.sh <label> (as root).
set -euxo pipefail
LABEL=$1
U=tb H=/home/tb S=/srv/share Q=/srv/queue TB=vms-kvm-t0 DUT=vlab-01
R=$Q/results/$LABEL
mkdir -p "$R" $Q/claimed $Q/done $Q/finished
current=""
finish() {
    local rc=$?
    if [ -n "$current" ] && [ -f "$Q/claimed/$current.$LABEL" ]; then
        case $current in
            *.retry) mv "$Q/claimed/$current.$LABEL" "$Q/done/$current.$LABEL" ;;
            *) mv "$Q/claimed/$current.$LABEL" "$Q/pending/$current.retry" ;;
        esac
    fi
    echo "$rc" > "$Q/finished/$LABEL"
}
trap finish EXIT
export DEBIAN_FRONTEND=noninteractive
# The LXD VM image keeps a 70G root partition on the 140G disk.
growpart /dev/sda 1 || true
resize2fs /dev/sda1 || true
if ! swapon --show | grep -q /swapfile; then
    fallocate -l 8G /swapfile && chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile
fi
id $U >/dev/null 2>&1 || useradd -m -s /bin/bash $U
set +x
echo "$U:$(cat $S/tb-pass)" | chpasswd
set -x
echo "$U ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$U
# Without the https line apt sends https through the lab proxy, which cannot resolve download.docker.com.
printf 'Acquire::http::Proxy "http://%s/";\nAcquire::https::Proxy "DIRECT";\n' "$(cat $S/apt-proxy)" > /etc/apt/apt.conf.d/90proxy
# vm_set installs docker-ce with apt-key, gone in 26.04, unless a docker apt source already exists.
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
# A daily upgrade restarts openvswitch, which drops the testbed flows.
systemctl disable --now apt-daily-upgrade.timer apt-daily.timer unattended-upgrades >/dev/null 2>&1 || true
apt-get update -q
apt-get install -y -q docker-ce docker-ce-cli containerd.io libvirt-daemon-system qemu-system-x86 openvswitch-switch \
    bridge-utils j2cli sshpass net-tools ethtool python3-pip python3-yaml xz-utils openssh-server >/dev/null
usermod -aG docker,libvirt,kvm $U
systemctl enable --now ssh docker libvirtd
# ovsdb-server first starts before the ovs-vswitchd alternative exists, and systemd stops retrying.
systemctl reset-failed ovsdb-server ovs-vswitchd openvswitch-switch || true
systemctl restart openvswitch-switch
ovs-vsctl show >/dev/null
mkdir -p $H/sonic-vm/images $H/veos-vm/images
[ -s $H/sonic-vm/images/sonic-vs.img ] || cp $S/sonic-vs.img $H/sonic-vm/images/sonic-vs.img
for t in ceos docker-sonic-mgmt docker-ptf; do docker load -q -i $S/$t.tar; done
docker image inspect publicmirror.azurecr.io:443/debian:trixie >/dev/null 2>&1 || docker pull -q publicmirror.azurecr.io:443/debian:trixie
[ -d $H/sonic-mgmt ] || cp -a $S/sonic-mgmt $H/sonic-mgmt
chown -R $U:$U $H
ip link show br1 >/dev/null 2>&1 || (cd $H/sonic-mgmt/ansible && ./setup-management-network.sh >/dev/null)
docker rm -f sonic-mgmt >/dev/null 2>&1 || true
proxy=""
[ ! -s $S/issue-proxy ] || proxy="-e SONIC_AUTOMATION_PROXY_GITHUB_ISSUES_URL=$(cat $S/issue-proxy)"
su - $U -c "cd $H/sonic-mgmt && ./setup-container.sh -n sonic-mgmt -i sonicdev-microsoft.azurecr.io:443/docker-sonic-mgmt:latest -d /data $proxy" | tail -3
mgmt() { docker exec --user $U sonic-mgmt bash -c "$1"; }
tbcli="cd /data/sonic-mgmt/ansible && ./testbed-cli.sh -t vtestbed.yaml -m veos_vtb"
mgmt "$tbcli add-topo $TB password.txt" > "$R/add-topo.log" 2>&1
mgmt "$tbcli deploy-mg $TB veos_vtb password.txt" > "$R/deploy-mg.log" 2>&1
echo "TESTBED READY $(date -Is)"
run_files() {
    local dir=$1
    shift
    mgmt "cd /data/sonic-mgmt/tests && ./run_tests.sh -n $TB -d $DUT -f vtestbed.yaml -i ../ansible/veos_vtb -t t0,any -e --device_type=vs -m individual -O -p logs/$dir -c '$*'" \
        > "$H/run_tests.log" 2>&1 || true
    mkdir -p "$R/$dir"
    cp -a "$H/sonic-mgmt/tests/logs/$dir/." "$R/$dir/" 2>/dev/null || true
    cp "$H/run_tests.log" "$R/$dir/run_tests.log"
}
while [ ! -e $Q/STOP ]; do
    current=""
    for p in "$Q"/pending/*; do
        [ -e "$p" ] || continue
        c=${p##*/}
        if mv "$p" "$Q/claimed/$c.$LABEL" 2>/dev/null; then current=$c; break; fi
    done
    [ -n "$current" ] || break
    mapfile -t files < "$Q/claimed/$current.$LABEL"
    start=$(date +%s)
    run_files "$current" "${files[@]}"
    echo "$start $(date +%s)" > "$R/$current.time"
    mapfile -t rerun < <(python3 $S/t0/verdict.py rerun-files --chunk-dir "$R/$current" --known $S/t0/known-failures.yaml)
    if [ "${#rerun[@]}" -gt 0 ]; then
        mgmt "$tbcli deploy-mg $TB veos_vtb password.txt" > "$R/$current.deploy-mg.log" 2>&1 || true
        run_files "$current.rerun" "${rerun[@]}"
    fi
    mv "$Q/claimed/$current.$LABEL" "$Q/done/$current.$LABEL"
    current=""
done
echo "QUEUE DONE $(date -Is)"
