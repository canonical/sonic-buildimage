#!/bin/bash

BUILDINFO_PATH=src/sonic-build-hooks

BUILDINFO_CONFIG=$BUILDINFO_PATH/buildinfo/config/buildinfo.config

mkdir -p $BUILDINFO_PATH/buildinfo/config

echo "export MIRROR_SNAPSHOT=$MIRROR_SNAPSHOT" >> $BUILDINFO_CONFIG
echo "export PACKAGE_URL_PREFIX=$PACKAGE_URL_PREFIX" > $BUILDINFO_CONFIG
echo "export SONIC_VERSION_CONTROL_COMPONENTS=$SONIC_VERSION_CONTROL_COMPONENTS" >> $BUILDINFO_CONFIG
echo "export SONIC_VERSION_CACHE=${SONIC_VERSION_CACHE}" >> $BUILDINFO_CONFIG
echo "export SONIC_VERSION_CACHE_SOURCE=${SONIC_VERSION_CACHE_SOURCE}" >> $BUILDINFO_CONFIG
echo "export DISTRO=${DISTRO}" >> $BUILDINFO_CONFIG
