#!/usr/bin/env bash

if [ -f /usr/share/sonic/templates/envs ]; then
    source /usr/share/sonic/templates/envs
fi

if pgrep -x pebble > /dev/null 2>&1; then
    IN_PEBBLE=1
    SUPERVISORD_CONF="/etc/supervisor/conf.d/docker-dhcp-relay.supervisord.conf"
    PEBBLE_LAYER="/tmp/dhcp-relay-layer.yaml"

    # On the supervisord path docker_init.sh renders these; a rock has no such
    # entrypoint, so render them here.
    # 1. pebble layer with the per-VLAN relay agents / monitors
    # 2. supervisord config: not run by anything, but dhcprelayd parses it to
    #    learn the expected dhcrelay/dhcpmon command lines
    # 3. wait_for_intf.sh, which waits for all interfaces to come up
    # 4. port-to-alias name map
    mkdir -p /etc/supervisor/conf.d/
    sonic-cfggen -d \
        -t /usr/share/sonic/templates/pebble-layer.j2,$PEBBLE_LAYER \
        -t /usr/share/sonic/templates/docker-dhcp-relay.supervisord.conf.j2,$SUPERVISORD_CONF \
        -t /usr/share/sonic/templates/wait_for_intf.sh.j2,/usr/bin/wait_for_intf.sh \
        -t /usr/share/sonic/templates/port-name-alias-map.txt.j2,/tmp/port-name-alias-map.txt
    chmod +x /usr/bin/wait_for_intf.sh
fi

if [ "${RUNTIME_OWNER}" == "" ]; then
    RUNTIME_OWNER="kube"
fi

CTR_SCRIPT="/usr/share/sonic/scripts/container_startup.py"
if test -f ${CTR_SCRIPT}
then
    ${CTR_SCRIPT} -f dhcp_relay -o ${RUNTIME_OWNER} -v ${IMAGE_VERSION}
fi

keys=$(sonic-db-cli COUNTERS_DB keys "DHCPV4_COUNTER_TABLE:*")
for key in $keys; do
    sonic-db-cli COUNTERS_DB del "$key"
done

# If our supervisor config has entries in the "dhcp-relay" group...
if [ -n "$IN_PEBBLE" ]; then
    HAS_RELAY_GROUP=$(grep -c '^\[group:dhcp-relay\]' $SUPERVISORD_CONF)
else
    HAS_RELAY_GROUP=$(supervisorctl status | grep -c "^dhcp-relay:")
fi
if [ $HAS_RELAY_GROUP -gt 0 ]; then
    # Wait for all interfaces to come up and be assigned IPv4 addresses before
    # starting the DHCP relay agent(s). If an interface the relay should listen
    # on is down, the relay agent will not start. If an interface the relay
    # should listen on is up but does not have an IP address assigned when the
    # relay agent starts, it will not listen or send on that interface for the
    # lifetime of the process.
    /usr/bin/wait_for_intf.sh
fi

if [ -n "$IN_PEBBLE" ]; then
    LAYER_FILE="/usr/share/sonic/templates/syslog-layer.yaml"
    pebble add syslog-layer --combine $LAYER_FILE
    pebble replan

    # Relay agents (dhcp4relay/dhcp6relay/isc-dhcpv4-relay-*) and dhcpmon-*,
    # in the order they appear in the rendered layer
    RELAY_SERVICES=$(python3 -c 'import sys, yaml; print(*((yaml.safe_load(open(sys.argv[1])) or {}).get("services") or {}))' $PEBBLE_LAYER)
    if [ -n "$RELAY_SERVICES" ]; then
        pebble add dhcp-relay-layer --combine $PEBBLE_LAYER
        pebble replan

        # dhcpmon waits for the relay agents (supervisord dependent_startup_wait_for)
        for svc in $RELAY_SERVICES; do
            case $svc in dhcpmon-*) ;; *) pebble start $svc ;; esac
        done
        for svc in $RELAY_SERVICES; do
            case $svc in dhcpmon-*) pebble start $svc ;; esac
        done
    fi

    pebble start dhcprelayd
fi
