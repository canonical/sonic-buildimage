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
)

set -x
set -e

for rockitem in "${rocklist[@]}"
do
    mkdir -p $rockitem/debs $rockitem/files $rockitem/python-wheels

    cp target/debs/resolute/*.deb            $rockitem/debs/
    # Note: target/files/resolute/ mixes host-side and container-scoped files
    # (host_script.sh etc.). ONIE recovery ISOs and *.log build logs are
    # host/install artifacts, never container content — keep them out.
    rsync -a --exclude='*.iso' --exclude='*.log' target/files/resolute/ $rockitem/files/
    cp target/python-wheels/resolute/*.whl   $rockitem/python-wheels/
    cp dockers/docker-base-resolute/etc/rsyslog.conf $rockitem/files/
    echo "export IMAGE_VERSION=$(git rev-parse --abbrev-ref HEAD)-$(git rev-parse HEAD)" > $rockitem/envs

    pushd $rockitem

    rockname=$(basename $rockitem)
    rockfullname="${rockname}_1.0.0_amd64.rock"
    rockcraft clean
    rockcraft pack
    sudo rockcraft.skopeo --insecure-policy copy oci-archive:$rockfullname docker-daemon:$rockname:latest
    rm -r ./debs/ ./files/ ./python-wheels/ envs ${rockfullname}

    popd

    pushd target
    docker save $rockname:latest  | pigz -c  >${rockname}.gz
    popd

    docker rmi -f $rockname:latest
done
