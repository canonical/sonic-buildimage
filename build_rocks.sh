#!/bin/bash

# Finish `make SONIC_BUILD_JOBS=4 target/sonic-vs.img.gz` first
rocklist=("dockers/docker-nat" \
		"dockers/docker-mux" \
		"dockers/docker-database" \
		"dockers/docker-orchagent" \
		"dockers/docker-sonic-gnmi" \
		"dockers/docker-platform-monitor" \
		"dockers/docker-teamd" \
		"dockers/docker-dhcp-relay" \
		"dockers/docker-router-advertiser" \
		"dockers/docker-macsec" \
		"dockers/docker-fpm-frr" \
		"dockers/docker-sonic-mgmt-framework" \
		"dockers/docker-lldp" \
		"dockers/docker-eventd" \
		"dockers/docker-sflow" \
		"dockers/docker-snmp" \
		"platform/vs/docker-syncd-vs" \
		"platform/vs/docker-gbsyncd-vs"\
		"platform/broadcom/docker-syncd-brcm")

cp files/rsyslog/00-load-omprog.conf target/files/noble/
cp files/rsyslog/rsyslog.conf target/files/noble/
cp files/supervisor/supervisord.conf target/files/noble/

for rockitem in "${rocklist[@]}"
do
    mkdir -p $rockitem/debs
    mkdir -p $rockitem/files
    mkdir -p $rockitem/python-wheels

    cp -r target/debs/noble/*  $rockitem/debs/
    cp -r target/files/noble/* $rockitem/files/
    cp -r target/python-wheels/noble/* $rockitem/python-wheels/

    pushd $rockitem

    rockname=$(basename $rockitem)
    rockfullname="${rockname}_1.0.0_amd64.rock"
    rockcraft clean
    rockcraft pack -v
    sudo skopeo  --insecure-policy copy oci-archive:$rockfullname docker-daemon:$rockname:latest
    rm -r $rockitem/debs/ $rockitem/files/ $rockitem/python-wheels/

    popd

    pushd target
    docker save $rockname:latest  | pigz -c  >${rockname}.gz
    popd 

    docker rmi -f $rockname:latest

done

