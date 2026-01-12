#!/usr/bin/env bash

LAYER_FILE="/usr/share/sonic/templates/syslog-layer.yaml"
pebble add syslog-layer --combine $LAYER_FILE
pebble replan

TZ=$(cat /etc/timezone)
rm -rf /etc/localtime
ln -sf /usr/share/zoneinfo/$TZ /etc/localtime

pebble start sflowmgrd
pebble start port_index_mapper