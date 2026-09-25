#!/usr/bin/env bash

if pgrep -x pebble > /dev/null 2>&1; then
    LAYER_FILE="/usr/share/sonic/templates/syslog-layer.yaml"
    pebble add syslog-layer --combine $LAYER_FILE
    pebble replan

    pebble start sflowmgrd
    pebble start port_index_mapper
fi