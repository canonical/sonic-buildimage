#!/bin/bash

SSD_FW_UPGRADE="/host/ssd_fw_upgrade"

if [ -e $SSD_FW_UPGRADE/GPIO7_high ]; then
    systemctl start --no-block s6100-ssd-monitor.timer
    exit 0
fi

if [ -e $SSD_FW_UPGRADE/GPIO7_low ] || [ -e $SSD_FW_UPGRADE/GPIO7_error ]; then
    exit 0
fi

[ ! -d $SSD_FW_UPGRADE ] && mkdir $SSD_FW_UPGRADE

SSD_UPGRADE_LOG="$SSD_FW_UPGRADE/upgrade.log"

SMART_CMD=`smartctl -a /dev/sda`

SSD_FW_VERSION=$(echo "$SMART_CMD" | grep "Firmware Version" | awk '{print $NF}')
SSD_MODEL=$(echo "$SMART_CMD" | grep "Device Model" | awk '{print $NF}')

if [ -e $SSD_FW_UPGRADE/GPIO7_pending_upgrade ]; then
    if [ $SSD_FW_VERSION == "S141002C" ] || [ $SSD_FW_VERSION == "S16425c1" ]; then
        # If SSD Firmware is not upgraded
        exit 0
    fi
fi

echo "$0 `date` SSD FW upgrade logs post reboot." >> $SSD_UPGRADE_LOG

iSMART="/usr/local/bin/iSMART_64"
iSMART_OPTIONS="-d /dev/sda"
iSMART_CMD=`$iSMART $iSMART_OPTIONS`

SSD_UPGRADE_STATUS1=`io_rd_wr.py --set --val 06 --offset 210; io_rd_wr.py --set --val 09 --offset 211; io_rd_wr.py --get --offset 212`
SSD_UPGRADE_STATUS1=$(echo "$SSD_UPGRADE_STATUS1" | awk '{print $NF}')

SSD_UPGRADE_STATUS2=`io_rd_wr.py --set --val 06 --offset 210; io_rd_wr.py --set --val 0A --offset 211; io_rd_wr.py --get --offset 212`
SSD_UPGRADE_STATUS2=$(echo "$SSD_UPGRADE_STATUS2" | awk '{print $NF}')

if [ $SSD_UPGRADE_STATUS1 == "2" ]; then
    rm -rf $SSD_FW_UPGRADE/GPIO7_*
    touch $SSD_FW_UPGRADE/GPIO7_error

    echo "$0 `date` Upgraded to unknown version after first mp_64 upgrade." >> $SSD_UPGRADE_LOG

elif [ $SSD_UPGRADE_STATUS2 == "2" ];then
    rm -rf $SSD_FW_UPGRADE/GPIO7_*
    touch $SSD_FW_UPGRADE/GPIO7_error

    echo "$0 `date` Upgraded to unknown version after second mp_64 upgrade." >> $SSD_UPGRADE_LOG

elif [ $SSD_FW_VERSION == "S141002G" ] || [ $SSD_FW_VERSION == "S16425cG" ]; then
    # If SSD Firmware is upgraded
    GPIO_STATUS=$(echo "$iSMART_CMD" | grep GPIO | awk '{print $NF}')

    if [ $GPIO_STATUS != "0x01" ];then
        logger -p user.crit -t DELL_S6100_SSD_MON "The SSD on this unit is faulty and does not support reboot."
        logger -p user.crit -t DELL_S6100_SSD_MON "If a reboot is required, please perform a soft-/fast-/warm-reboot."
        rm -rf $SSD_FW_UPGRADE/GPIO7_*
        touch $SSD_FW_UPGRADE/GPIO7_low
        echo "$0 `date` The SSD on this unit is faulty and does not support cold reboot." >> $SSD_UPGRADE_LOG
        echo "$0 `date` If a reboot is required, please perform a soft-/fast-/warm-reboot." >> $SSD_UPGRADE_LOG

    else
        rm -rf $SSD_FW_UPGRADE/GPIO7_*
        touch $SSD_FW_UPGRADE/GPIO7_high
    fi

    systemctl start --no-block s6100-ssd-monitor.timer

    if [ $SSD_UPGRADE_STATUS1 == "0" ]; then
        if [ $SSD_MODEL  == "3IE" ];then
            echo "$0 `date` SSD FW upgraded from S141002C to S141002G in first mp_64." >> $SSD_UPGRADE_LOG
        else
            echo "$0 `date` SSD FW upgraded from S16425c1 to S16425cG in first mp_64." >> $SSD_UPGRADE_LOG
        fi
    elif [ $SSD_UPGRADE_STATUS2 == "1" ]; then
        echo "$0 `date` SSD entered loader mode in first mp_64 and upgraded to latest version after second mp_64." >> $SSD_UPGRADE_LOG
    fi

else
    if [ $SSD_UPGRADE_STATUS1 == "ff" ] && [ $SSD_UPGRADE_STATUS2 == "ff" ]; then
        rm -rf $SSD_FW_UPGRADE/GPIO7_*
        touch $SSD_FW_UPGRADE/GPIO7_pending_upgrade

        echo "$0 `date` SSD upgrade didn’t happened." >> $SSD_UPGRADE_LOG

    elif [ $SSD_UPGRADE_STATUS1 == "1" ]; then
        rm -rf $SSD_FW_UPGRADE/GPIO7_*
        touch $SSD_FW_UPGRADE/GPIO7_low
        logger -p user.crit -t DELL_S6100_SSD_MON "The SSD on this unit is faulty and does not support reboot."
        logger -p user.crit -t DELL_S6100_SSD_MON "If a reboot is required, please perform a soft-/fast-/warm-reboot."

        echo "$0 `date` SSD entered loader mode in first mp_64 upgrade." >> $SSD_UPGRADE_LOG

        if [ $SSD_UPGRADE_STATUS2 == "0" ]; then
            echo "$0 `date` SSD entered loader mode in first mp_64 and recovered back to older version in second mp_64." >> $SSD_UPGRADE_LOG
        fi
    fi

fi

echo "$0 `date` SMF Register 1 = $SSD_UPGRADE_STATUS1" >> $SSD_UPGRADE_LOG
echo "$0 `date` SMF Register 2 = $SSD_UPGRADE_STATUS2" >> $SSD_UPGRADE_LOG
echo "$SMART_CMD" >> $SSD_UPGRADE_LOG
echo "$iSMART_CMD" >> $SSD_UPGRADE_LOG
sync
# Clearing the upgrade status
io_rd_wr.py --set --val 06 --offset 210; io_rd_wr.py --set --val 09 --offset 211; io_rd_wr.py --set --val ff --offset 213
io_rd_wr.py --set --val 06 --offset 210; io_rd_wr.py --set --val 0A --offset 211; io_rd_wr.py --set --val ff --offset 213
