#!/usr/bin/env bash

LAYER_FILE="/tmp/syslog-layer.yaml"

echo "
log-targets:
  host-syslog:
    override: replace
    type: syslog
    location: udp://127.0.0.1:514/
    services: [all]
" > $LAYER_FILE

echo "File created: $LAYER_FILE"
echo "Service Dependency: $DEPENDENCY"
echo "---"
pebble add syslog-layer --combine $LAYER_FILE
pebble replan

mkdir -p /var/sonic
echo "# Config files managed by sonic-config-engine" > /var/sonic/config_status

TZ=$(cat /etc/timezone)
rm -rf /etc/localtime
ln -sf /usr/share/zoneinfo/$TZ /etc/localtime
