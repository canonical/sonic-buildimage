#!/usr/bin/env bash

if [ "${RUNTIME_OWNER}" == "" ]; then
    RUNTIME_OWNER="kube"
fi

if [ -f /usr/share/sonic/templates/envs ]; then
    source /usr/share/sonic/templates/envs
fi

# This script is to basicly check for if this starting-container can be allowed
# to run based on current state, and owner & version of this starting container.
# If allowed, update feature info in state_db and then processes in supervisord.conf
# after this process can start up.
CTR_SCRIPT="/usr/share/sonic/scripts/container_startup.py"
if test -f ${CTR_SCRIPT}
then
    ${CTR_SCRIPT} -f dhcp_server -o ${RUNTIME_OWNER} -v ${IMAGE_VERSION}
fi

if pgrep -x pebble > /dev/null 2>&1; then
    # A rock has no docker_init.sh, so do its work here
    mkdir -p /etc/kea/ /run/kea /var/log/kea /var/lib/kea
    chmod 750 /run/kea
    # Clean up stale ready flag from previous run
    rm -f /tmp/dhcpservd_ready

    LAYER_FILE="/usr/share/sonic/templates/syslog-layer.yaml"
    pebble add syslog-layer --combine $LAYER_FILE

    pebble start dhcpservd
    # Wait (up to 120s) for dhcpservd to register its SIGUSR1 handler, so kea-dhcp4
    # does not signal it too early. Runs inline: it can exit within a second, which
    # pebble would treat as a failed service start.
    /usr/bin/wait_for_dhcpservd.sh
    pebble start kea-dhcp4
fi
