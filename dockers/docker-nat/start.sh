#!/usr/bin/env bash

rm -f /var/run/nat/*

mkdir -p /var/warmboot/nat

if pgrep -x pebble > /dev/null 2>&1; then
    LAYER_FILE="/usr/share/sonic/templates/syslog-layer.yaml"
    pebble add syslog-layer --combine $LAYER_FILE
    pebble replan

    pebble start natmgrd
    pebble start natsyncd
    pebble start restore_nat_entries
fi
