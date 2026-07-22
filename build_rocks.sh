#!/bin/bash

# Finish `make SONIC_BUILD_JOBS=4 target/sonic-vs.img.gz` first
rocklist=(
    "dockers/docker-database"
)

set -x
set -e

for rockitem in "${rocklist[@]}"
do
    mkdir -p $rockitem/debs
    mkdir -p $rockitem/files
    mkdir -p $rockitem/python-wheels

    cp -r target/debs/resolute/*.deb            $rockitem/debs/
    cp -r target/files/resolute/*               $rockitem/files/
    cp -r target/python-wheels/resolute/*.whl   $rockitem/python-wheels/
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
