#!/bin/bash

# Finish `make target/sonic-vs.img.gz` first
rocklist=(
    "dockers/docker-database"
    "dockers/docker-sonic-mgmt-framework"
    "dockers/docker-eventd"
    "dockers/docker-router-advertiser"
    "dockers/docker-lldp"
    "dockers/docker-snmp"
    "dockers/docker-sonic-gnmi"
    "dockers/docker-teamd"
    "dockers/docker-platform-monitor"
    "dockers/docker-macsec"
    "dockers/docker-iccpd"
    "dockers/docker-sflow"
    "dockers/docker-nat"
    "dockers/docker-fpm-frr"
    "dockers/docker-orchagent"
    "dockers/docker-dhcp-relay"
    "dockers/docker-sysmgr"
    # "dockers/docker-dhcp-server"
    # "dockers/docker-stp"
)

# docker-syncd-brcm is platform-specific; only build it for the broadcom platform
if [ "$(cat .platform 2>/dev/null)" = "broadcom" ]; then
    rocklist+=("platform/broadcom/docker-syncd-brcm")
fi

set -x
set -e

APT_CACHER_URL=""

# Point the rock pack steps at a local apt-cacher-ng proxy, so every container
# avoids re-download the same Ubuntu stage-packages. 
# This is an accelerator, not a hard prerequisite: if it cannot be set up, 
# warn and fall back to downloading straight from archive.ubuntu.com. 
ensure_apt_cacher() {
    if ! command -v apt-cacher-ng >/dev/null 2>&1; then
        echo "WARN: apt-cacher-ng not installed; building against archive.ubuntu.com directly." >&2
        echo "      Speed it up with: sudo apt-get install -y apt-cacher-ng" >&2
        return 0
    fi

    # Try to start apt-cacher-ng service. If can't, fallback
    if ! curl -s -o /dev/null --max-time 3 "http://127.0.0.1:3142/"; then
        sudo systemctl start apt-cacher-ng 2>/dev/null \
            || sudo service apt-cacher-ng start 2>/dev/null \
            || true
    fi
    if ! curl -s -o /dev/null --max-time 3 "http://127.0.0.1:3142/"; then
        echo "WARN: could not start apt-cacher-ng; building against archive.ubuntu.com directly." >&2
        return 0
    fi

    local gw
    gw="$(lxc network get lxdbr0 ipv4.address 2>/dev/null | cut -d/ -f1)" || true
    if [ -z "$gw" ]; then
        echo "WARN: could not resolve the LXD bridge gateway; building against archive.ubuntu.com directly." >&2
        return 0
    fi

    # The stock config ships an empty backends_ubuntu, which falls back to a
    # stale country-mirror list that 503s under parallel load; pin the real
    # archive and raise the upstream retry limit. Best-effort, non-fatal.
    sudo sh -c 'printf "http://archive.ubuntu.com/ubuntu\n" > /usr/lib/apt-cacher-ng/backends_ubuntu' 2>/dev/null || true
    if ! grep -q '^DlMaxRetries:' /etc/apt-cacher-ng/acng.conf 2>/dev/null; then
        echo 'DlMaxRetries: 8' | sudo tee -a /etc/apt-cacher-ng/acng.conf >/dev/null 2>&1 || true
    fi
    sudo systemctl reload apt-cacher-ng 2>/dev/null || true

    APT_CACHER_URL="http://${gw}:3142"
}

ensure_apt_cacher

# Print the SONiC labels (manifest, component versions, Tag) of a saved image as NUL-separated --label args
sonic_labels()
{
    local cfg
    cfg=$(tar -xOzf "$1" manifest.json | jq -r '.[0].Config')
    tar -xOzf "$1" "$cfg" | jq -j '.config.Labels // {} | to_entries[]
        | select(.key == "Tag" or (.key | startswith("com.azure.sonic.")))
        | "--label\u0000\(.key)=\(.value)\u0000"'
}

for rockitem in "${rocklist[@]}"
do
    rockname=$(basename $rockitem)
    rockfullname="${rockname}_1.0.0_amd64.rock"
    # Carry over the labels slave.mk put on the Dockerfile image this rock replaces; sonic-package-manager reads them
    mapfile -d '' labels < <(sonic_labels target/${rockname}.gz)
    if [[ ! " ${labels[*]} " == *" com.azure.sonic.manifest="* ]]; then
        echo "target/${rockname}.gz has no SONiC manifest label; build it with make first" >&2
        exit 1
    fi

    mkdir -p $rockitem/debs $rockitem/files $rockitem/python-wheels

    cp target/debs/resolute/*.deb            $rockitem/debs/
    # Note: ONIE recovery *.iso and *.log are host/install artifacts — keep them out
    rsync -a --exclude='*.iso' --exclude='*.log' target/files/resolute/ $rockitem/files/
    cp target/python-wheels/resolute/*.whl   $rockitem/python-wheels/
    cp dockers/docker-base-resolute/etc/rsyslog.conf $rockitem/files/
    echo "export IMAGE_VERSION=$(git rev-parse --abbrev-ref HEAD)-$(git rev-parse HEAD)" > $rockitem/envs

    pushd $rockitem

    rockcraft clean
    if [ -n "$APT_CACHER_URL" ]; then
        http_proxy="$APT_CACHER_URL" rockcraft pack
    else
        rockcraft pack
    fi
    sudo rockcraft.skopeo --insecure-policy copy oci-archive:$rockfullname docker-daemon:$rockname:rock
    echo "FROM $rockname:rock" | docker build "${labels[@]}" -t $rockname:latest -
    docker rmi $rockname:rock
    rm -r ./debs/ ./files/ ./python-wheels/ envs ${rockfullname}

    popd

    pushd target
    docker save $rockname:latest  | pigz -c  >${rockname}.gz
    popd

    docker rmi -f $rockname:latest
done
