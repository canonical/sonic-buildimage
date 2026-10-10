#!/usr/bin/env bash

# SONiC swss (orchagent) rock init — rock-only (rockcraft.yaml's `start` service
# is its sole consumer; the Docker path keeps ENTRYPOINT docker-init.sh, untouched).
# Reproduces docker-init.j2's config rendering, replaces the supervisord.conf
# render with a dynamic pebble layer, and starts daemons via pebble in the
# order supervisord's dependent_startup_wait_for chain imposed.

mkdir -p /etc/swss/config.d/

CFGGEN_PARAMS=" \
    -d \
    -a "{\"ASIC_VENDOR\":\"${ASIC_VENDOR:-unknown}\"}" \
    -y /etc/sonic/constants.yml \
    -t /usr/share/sonic/templates/orch_zmq_tables.conf.j2,/etc/swss/orch_zmq_tables.conf \
    -t /usr/share/sonic/templates/switch.json.j2,/etc/swss/config.d/switch.json \
    -t /usr/share/sonic/templates/vxlan.json.j2,/etc/swss/config.d/vxlan.json \
    -t /usr/share/sonic/templates/ipinip.json.j2,/etc/swss/config.d/ipinip.json \
    -t /usr/share/sonic/templates/ports.json.j2,/etc/swss/config.d/ports.json \
    -t /usr/share/sonic/templates/ndppd.conf.j2,/etc/ndppd.conf \
    -t /usr/share/sonic/templates/wait_for_link.sh.j2,/usr/bin/wait_for_link.sh \
    -t /usr/share/sonic/templates/pebble-layer.j2,/tmp/swss-layer.yaml \
"
sonic-cfggen $CFGGEN_PARAMS
SWITCH_TYPE=${SWITCH_TYPE:-`sonic-db-cli -s CONFIG_DB HGET 'DEVICE_METADATA|localhost' 'switch_type'`}
chmod +x /usr/bin/wait_for_link.sh

# Executed platform specific initialization tasks.
if [ -x /usr/share/sonic/platform/platform-init ]; then
    /usr/share/sonic/platform/platform-init
fi

# Executed HWSKU specific initialization tasks.
if [ -x /usr/share/sonic/hwsku/hwsku-init ]; then
    /usr/share/sonic/hwsku/hwsku-init
fi

IS_SUPERVISOR=/etc/sonic/chassisdb.conf
USE_PCI_ID_IN_CHASSIS_STATE_DB=/usr/share/sonic/platform/use_pci_id_chassis
ASIC_ID="asic$NAMESPACE_ID"
if [ -f "$IS_SUPERVISOR" ]; then
    if [ -f "$USE_PCI_ID_IN_CHASSIS_STATE_DB" ]; then
        while true; do
            PCI_ID=$(sonic-db-cli -s CHASSIS_STATE_DB HGET "CHASSIS_FABRIC_ASIC_TABLE|$ASIC_ID" asic_pci_address)
            if [ -z "$PCI_ID" ]; then
                sleep 3
            else
                # Update asic_id in CONFIG_DB, which is used by orchagent and fed to syncd
                if [[ $PCI_ID == ????:??:??.? ]]; then
                    sonic-db-cli CONFIG_DB HSET 'DEVICE_METADATA|localhost' 'asic_id' ${PCI_ID#*:}
                    break
                fi
            fi
        done
    fi
fi

# Start a service only if it was rendered into the swss layer.
start_if_defined()
{
    for svc in "$@"; do
        if pebble services "$svc" 2>/dev/null | grep -q "^$svc "; then
            pebble start "$svc" || true
        fi
    done
}

if pgrep -x pebble > /dev/null 2>&1; then
    LAYER_FILE="/usr/share/sonic/templates/syslog-layer.yaml"
    pebble add syslog-layer --combine $LAYER_FILE

    pebble add swss-layer --combine /tmp/swss-layer.yaml

    # gearsyncd is a sub-second one-shot (pushes gearbox config, exits); run inline.
    if [ "$SWITCH_TYPE" != "fabric" ]; then
        /usr/bin/gearsyncd -p /usr/share/sonic/hwsku/gearbox_config.json
    fi

    # orchagent waits for portsyncd:running (rsyslogd:running on fabric asics).
    start_if_defined portsyncd orchagent

    # coppmgrd and swssconfig wait for orchagent:running.
    start_if_defined coppmgrd

    # swssconfig is a one-shot gate: it waits for the host to touch /ready,
    # then loads the config.d JSONs. Everything below waits for swssconfig:exited.
    /usr/bin/swssconfig.sh

    # restore_neighbors is a one-shot (sub-second unless system warm reboot);
    # run it alongside the daemons below, as supervisord did.
    if [ "$SWITCH_TYPE" != "fabric" ]; then
        /usr/bin/restore_neighbors.py &
    fi

    # Original supervisord priority order.
    start_if_defined neighsyncd arp_update vlanmgrd intfmgrd portmgrd fabricmgrd \
        buffermgrd enable_counters tunnel_packet_handler vrfmgrd nbrmgrd \
        vxlanmgrd tunnelmgrd fdbsyncd countersyncd

    # ndppd waits for wait_for_link:exited (a one-shot gate on VLAN interfaces).
    if pebble services ndppd 2>/dev/null | grep -q "^ndppd "; then
        /usr/bin/wait_for_link.sh
        pebble start ndppd || true
    fi

    wait
fi
