#!/usr/bin/env bash

LAYER_FILE="/usr/share/sonic/templates/syslog-layer.yaml"
pebble add syslog-layer --combine $LAYER_FILE
pebble replan

rm -f /var/run/teamd/*

mkdir -p /var/warmboot/teamd

TZ=$(cat /etc/timezone)
rm -rf /etc/localtime
ln -sf /usr/share/zoneinfo/$TZ /etc/localtime

pebble start teammgrd
pebble start tlm_teamd
pebble start teamsyncd