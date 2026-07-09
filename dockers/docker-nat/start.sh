#!/usr/bin/env bash

LAYER_FILE="/usr/share/sonic/templates/syslog-layer.yaml"
pebble add syslog-layer --combine $LAYER_FILE
pebble replan

rm -f /var/run/nat/*

mkdir -p /var/warmboot/nat

TZ=$(cat /etc/timezone)
rm -rf /etc/localtime
ln -sf /usr/share/zoneinfo/$TZ /etc/localtime

pebble start natmgrd
pebble start natsyncd

/usr/bin/restore_nat_entries.py