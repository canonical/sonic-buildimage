#!/usr/bin/env bash

rm -f /var/run/nat/*

mkdir -p /var/warmboot/nat

if pgrep -x pebble > /dev/null 2>&1; then
    LAYER_FILE="/usr/share/sonic/templates/syslog-layer.yaml"
    pebble add syslog-layer --combine $LAYER_FILE

    pebble start natmgrd
    pebble start natsyncd

    /usr/bin/restore_nat_entries.py
fi
