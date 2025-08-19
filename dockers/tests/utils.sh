#!/bin/bash

function setup_lxd() {
    if snap list lxd >/dev/null; then
        snap refresh --channel=6/stable lxd
    else
        snap install --channel=6/stable lxd
    fi
    lxd waitready --timeout=180

    # may already initialised if reused
    # https://discuss.linuxcontainers.org/t/how-do-i-know-if-lxd-is-initialized/15473/3
    if [ "$(lxc storage list -f compact | grep -c default)" -eq 0 ]; then
        lxd init --auto
    fi

    echo "net.ipv4.conf.all.forwarding=1" > /etc/sysctl.d/99-forwarding.conf
    systemctl restart systemd-sysctl
    for ipt in iptables iptables-legacy ip6tables ip6tables-legacy; do $ipt --flush; $ipt --flush -t nat; $ipt --delete-chain; $ipt --delete-chain -t nat; $ipt -P FORWARD ACCEPT; $ipt -P INPUT ACCEPT; $ipt -P OUTPUT ACCEPT; done
    systemctl reload snap.lxd.daemon
}

function prepare_environment() {
    apt-get update
    apt-get install -y docker.io pipx j2cli make
    pipx install gdown

    setup_lxd
    snap install rockcraft --classic
}
