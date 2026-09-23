#!/usr/bin/env bash

rm -f /var/run/teamd/*

mkdir -p /var/warmboot/teamd

if pgrep -x pebble > /dev/null 2>&1; then
    LAYER_FILE="/usr/share/sonic/templates/syslog-layer.yaml"
    pebble add syslog-layer --combine $LAYER_FILE
    pebble replan

    pebble start teammgrd
    pebble start teamsyncd
    pebble start tlm_teamd
fi
