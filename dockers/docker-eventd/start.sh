#!/usr/bin/env bash

LAYER_FILE="/usr/share/sonic/templates/syslog-layer.yaml"
pebble add syslog-layer --combine $LAYER_FILE
pebble replan

if [ "${RUNTIME_OWNER}" == "" ]; then
    RUNTIME_OWNER="kube"
fi

TZ=$(cat /etc/timezone)
rm -rf /etc/localtime
ln -sf /usr/share/zoneinfo/$TZ /etc/localtime

pebble start eventd