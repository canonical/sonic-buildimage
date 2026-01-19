#!/usr/bin/env bash

source /usr/share/sonic/templates/envs

LAYER_FILE="/usr/share/sonic/templates/syslog-layer.yaml"
pebble add syslog-layer --combine $LAYER_FILE
pebble replan

mkdir -p /etc/supervisor/conf.d

# Generate supervisord router advertiser config, /etc/radvd.conf config file, and
# the script that waits for pertinent interfaces to come up and make it executable
CFGGEN_PARAMS=" \
    -d \
    -t /usr/share/sonic/templates/docker-router-advertiser.supervisord.conf.j2,/etc/supervisor/conf.d/supervisord.conf \
    -t /usr/share/sonic/templates/radvd.conf.j2,/etc/radvd.conf \
    -t /usr/share/sonic/templates/wait_for_link.sh.j2,/usr/bin/wait_for_link.sh \
"
sonic-cfggen $CFGGEN_PARAMS

chmod +x /usr/bin/wait_for_link.sh

TZ=$(cat /etc/timezone)
rm -rf /etc/localtime
ln -sf /usr/share/zoneinfo/$TZ /etc/localtime

# ============= Below is previous start.sh ======================

if [ "${RUNTIME_OWNER}" == "" ]; then
    RUNTIME_OWNER="kube"
fi

CTR_SCRIPT="/usr/share/sonic/scripts/container_startup.py"
if test -f ${CTR_SCRIPT}
then
    ${CTR_SCRIPT} -f radv -o ${RUNTIME_OWNER} -v ${IMAGE_VERSION}
fi

DELOYMENT_ID=$(sonic-cfggen -d -v DEVICE_METADATA.localhost.deployment_id)
DEVICE_TYPE=$(sonic-cfggen -d -v DEVICE_METADATA.localhost.type)
DEVICE_TYPE=$(sonic-cfggen -d -v VLAN_INTERFACE)

vlan_v6_count=0
if [ "$DEPLOYMENT_ID" != "8" ]; then
    if [ -n "$DEVICE_TYPE" ]; then
        if [[ "$DEVICE_TYPE" == *"ToRRouter"* ]] || [[ "$DEVICE_TYPE" == "EPMS" ]] || [[ "$DEVICE_TYPE" == "MgmtTsToR" ]]; then
            if [ -n "$VLAN_INTERFACE" ] && [ "$VLAN_INTERFACE" != "null" ]; then
                while read -r prefix; do
                    # Check if it's an IPv6 addr, simply by looking for colon
                    if [[ "$prefix" == *":"* ]]; then
                        ((vlan_v6_count++))
                    fi
                done < <(echo "$VLAN_INTERFACE" | jq -r '.[].[] | select(type == "string")')
            fi
        fi
    fi
fi

if [ "$vlan_v6_count" -gt 0 ]; then
    /usr/bin/wait_for_link.sh
fi