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

    # "dockers/docker-dhcp-server"
    "dockers/docker-dhcp-relay"

    "dockers/docker-sysmgr"
    # "dockers/docker-stp"
)

# docker-syncd-brcm is platform-specific; only build it for the broadcom platform
if [ "$(cat .platform 2>/dev/null)" = "broadcom" ]; then
    rocklist+=("platform/broadcom/docker-syncd-brcm")
fi

set -x
set -e

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
    rockcraft pack
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
