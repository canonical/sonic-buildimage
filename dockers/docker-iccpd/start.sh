#!/usr/bin/env bash
set -e

ICCPD_CONF_PATH=/etc/iccpd

rm -rf $ICCPD_CONF_PATH
mkdir -p $ICCPD_CONF_PATH

sonic-cfggen -d -t /usr/share/sonic/templates/iccpd.j2 > $ICCPD_CONF_PATH/iccpd.conf

mkdir -p /var/sonic
echo "# Config files managed by sonic-config-engine" > /var/sonic/config_status

if pgrep -x pebble > /dev/null 2>&1; then
    LAYER_FILE="/usr/share/sonic/templates/syslog-layer.yaml"
    pebble add syslog-layer --combine $LAYER_FILE
    pebble replan

    pebble start iccpd
fi

