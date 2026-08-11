#! /bin/bash

if [ "${RUNTIME_OWNER}" == "" ]; then
    RUNTIME_OWNER="kube"
fi

if pgrep -x pebble > /dev/null 2>&1; then
    LAYER_FILE="/usr/share/sonic/templates/syslog-layer.yaml"
    pebble add syslog-layer --combine $LAYER_FILE
    pebble replan
fi

CTR_SCRIPT="/usr/share/sonic/scripts/container_startup.py"
if test -f ${CTR_SCRIPT}
then
    ${CTR_SCRIPT} -f radv -o ${RUNTIME_OWNER} -v ${IMAGE_VERSION}
fi

if pgrep -x pebble > /dev/null 2>&1; then
    # Render radvd config and wait_for_link script from Jinja2 templates
    sonic-cfggen -d -t /usr/share/sonic/templates/radvd.conf.j2 > /etc/radvd.conf
    sonic-cfggen -d -t /usr/share/sonic/templates/wait_for_link.sh.j2 > /usr/bin/wait_for_link.sh
    chmod +x /usr/bin/wait_for_link.sh

    # Router advertiser should only run on ToR (T0) devices which have
    # at least one VLAN interface with an IPv6 address assigned.
    # Same condition as docker-router-advertiser.supervisord.conf.j2 lines 48-60.
    # Uses sonic-db-cli to query CONFIG_DB directly (robust, no Jinja2 one-liner).
    DEVICE_TYPE=$(sonic-db-cli CONFIG_DB HGET "DEVICE_METADATA|localhost" "type" 2>/dev/null)
    START_RADVD=false
    if echo "${DEVICE_TYPE}" | grep -qE "ToRRouter|^EPMS$|^MgmtTsToR$"; then
        for key in $(sonic-db-cli CONFIG_DB KEYS "VLAN_INTERFACE|*" 2>/dev/null); do
            # VLAN_INTERFACE keys: VLAN_INTERFACE|Vlan1000 or VLAN_INTERFACE|Vlan1000|fc02:1000::1/64
            # IPv6 prefixes contain ":" — check the third field
            prefix=$(echo "$key" | cut -d'|' -f3-)
            if echo "$prefix" | grep -q ":"; then
                START_RADVD=true
                break
            fi
        done
    fi

    if [ "${START_RADVD}" = "true" ]; then
        # pebble start returns when the service is active, not when it exits.
        # radvd.conf sets IgnoreIfMissing on, so radvd safely waits for interfaces.
        pebble start wait_for_link
        pebble start radvd
    fi
fi
