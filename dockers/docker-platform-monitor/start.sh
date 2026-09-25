#!/usr/bin/env bash

# SONiC pmon rock init. This script is rock-only: rockcraft.yaml's `start` service is 
# its only consumer - no supervisord/Dockerfile path shares this script. Preserves 
# runtime logic of docker_init.j2 and replaces supervisord.conf rendering with a 
# dynamic pebble layer.

SENSORS_CONF_FILE="/usr/share/sonic/platform/sensors.conf"
FANCONTROL_CONF_FILE="/usr/share/sonic/platform/fancontrol"

MODULAR_CHASSISDB_CONF_FILE="/usr/share/sonic/platform/chassisdb.conf"
PLATFORM_ENV_CONF_FILE="/usr/share/sonic/platform/platform_env.conf"

HAVE_SENSORS_CONF=0
HAVE_FANCONTROL_CONF=0
IS_MODULAR_CHASSIS=0
# Default use python3 version
SONIC_PLATFORM_API_PYTHON_VERSION=3

if [ -e /usr/share/sonic/hwsku/pmon_daemon_control.json ];
then
    PMON_DAEMON_CONTROL_FILE="/usr/share/sonic/hwsku/pmon_daemon_control.json"
else
    PMON_DAEMON_CONTROL_FILE="/usr/share/sonic/platform/pmon_daemon_control.json"
fi

declare -r EXIT_SUCCESS="0"

if [ "${RUNTIME_OWNER}" == "" ]; then
    RUNTIME_OWNER="kube"
fi

source /usr/share/sonic/templates/envs

CTR_SCRIPT="/usr/share/sonic/scripts/container_startup.py"
if test -f ${CTR_SCRIPT}
then
    ${CTR_SCRIPT} -f pmon -o ${RUNTIME_OWNER} -v ${IMAGE_VERSION}
fi

mkdir -p /var/sonic
echo "# Config files managed by sonic-config-engine" > /var/sonic/config_status

# If this platform has synchronization script, run it
if [ -e /usr/share/sonic/platform/platform_wait ]; then
    /usr/share/sonic/platform/platform_wait
    EXIT_CODE="$?"
    if [ "${EXIT_CODE}" != "${EXIT_SUCCESS}" ]; then
        exit "${EXIT_CODE}"
    fi
fi

# If the Python 3 sonic-platform package is not installed, try to install it
python3 -c "import sonic_platform" > /dev/null 2>&1 || pip3 show sonic-platform > /dev/null 2>&1
if [ $? -ne 0 ]; then
    SONIC_PLATFORM_WHEEL="/usr/share/sonic/platform/sonic_platform-1.0-py3-none-any.whl"
    echo "sonic-platform package not installed, attempting to install..."
    if [ -e ${SONIC_PLATFORM_WHEEL} ]; then
       pip3 install --break-system-packages ${SONIC_PLATFORM_WHEEL}
       if [ $? -eq 0 ]; then
          echo "Successfully installed ${SONIC_PLATFORM_WHEEL}"
       else
          echo "Error: Failed to install ${SONIC_PLATFORM_WHEEL}"
       fi
    else
       echo "Error: Unable to locate ${SONIC_PLATFORM_WHEEL}"
    fi
fi

# Platform-specific build-time branches (mellanox/aspeed/nvidia-bluefield) are out of
# scope for this branch (vs/broadcom only), so no runtime platform branch is needed.

if [ -e $SENSORS_CONF_FILE ]; then
    HAVE_SENSORS_CONF=1
    mkdir -p /etc/sensors.d
    PSU_SENSORS_CONF_UPDATER="/usr/share/sonic/platform/psu_sensors_conf_updater"
    if [ -e $PSU_SENSORS_CONF_UPDATER ]; then
        source $PSU_SENSORS_CONF_UPDATER
        update_psu_sensors_configuration $SENSORS_CONF_FILE
        if [ -f /tmp/sensors.conf ]; then
            SENSORS_CONF_FILE="/tmp/sensors.conf"
        fi
    fi
    /bin/cp -f $SENSORS_CONF_FILE /etc/sensors.d/sensors.conf
fi

if [ -e $FANCONTROL_CONF_FILE ]; then
    HAVE_FANCONTROL_CONF=1
    rm -f /var/run/fancontrol.pid
    /bin/cp -f $FANCONTROL_CONF_FILE /etc/
fi

if [ -e $PLATFORM_ENV_CONF_FILE ]; then
    source $PLATFORM_ENV_CONF_FILE
fi

if [ -e $MODULAR_CHASSISDB_CONF_FILE ] && [[ $disaggregated_chassis -ne 1 ]]; then
    IS_MODULAR_CHASSIS=1
fi

# Determine if this pmon instance is running on the Switch BMC.
# switch_bmc=1 is set in platform_env.conf on BMC systems.
IS_SWITCH_BMC=0
if [ -e $PLATFORM_ENV_CONF_FILE ]; then
    bmc_val=$(grep -s '^switch_bmc=' $PLATFORM_ENV_CONF_FILE | cut -d= -f2 | tr -d '[:space:]')
    if [[ "$bmc_val" == "1" ]]; then
        IS_SWITCH_BMC=1
    fi
fi

confvar="{\"HAVE_SENSORS_CONF\":$HAVE_SENSORS_CONF, \"HAVE_FANCONTROL_CONF\":$HAVE_FANCONTROL_CONF, \"API_VERSION\":$SONIC_PLATFORM_API_PYTHON_VERSION, \"IS_MODULAR_CHASSIS\":$IS_MODULAR_CHASSIS, \"IS_SWITCH_BMC\":$IS_SWITCH_BMC}"

LAYER_FILE="/usr/share/sonic/templates/syslog-layer.yaml"
pebble add syslog-layer --combine $LAYER_FILE
pebble replan

# Render the daemon layer from the same template conditions supervisord used,
# then inject it as a dynamic pebble layer.
PEBBLE_LAYER_TEMPLATE="/usr/share/sonic/templates/pebble-layer.j2"
if [ -e $PMON_DAEMON_CONTROL_FILE ]; then
    sonic-cfggen -d -j $PMON_DAEMON_CONTROL_FILE -a "$confvar" -t $PEBBLE_LAYER_TEMPLATE > /tmp/pmon-layer.yaml
else
    sonic-cfggen -d -a "$confvar" -t $PEBBLE_LAYER_TEMPLATE > /tmp/pmon-layer.yaml
fi
pebble add pmon-layer --combine /tmp/pmon-layer.yaml
pebble replan

# delay is a one-shot gate (advanced/warm reboot); start it and wait until it
# exits before bringing up the daemons that depended on "delay:exited".
if pebble services delay 2>/dev/null | grep -q '^delay '; then
    pebble start delay
    while pebble services delay 2>/dev/null | grep -q '^delay.*active'; do sleep 1; done
fi

# Start each daemon that was rendered into the layer, in original priority order.
for svc in bmcctld chassisd chassis_db_init lm-sensors fancontrol ledd xcvrd ycabled psud syseepromd thermalctld pcied sensormond stormond; do
    if pebble services "$svc" 2>/dev/null | grep -q "^$svc "; then
        pebble start "$svc" || true
    fi
done