# -*- coding: utf-8 -*-
#!/usr/sbin/env python3

import os
import logging
import common
from swsscommon.swsscommon import ConfigDBConnector, SonicV2Connector, SonicDBConfig

POE_POWER = "power(W)"

def state_db_poe_status_get(state_db, intf_name, status_type):
    """
    Get the port status
    """
    full_table_id = "POE_INFO|" + intf_name
    status = state_db.get(state_db.STATE_DB, full_table_id, status_type)
    if status is None:
        return "N/A"
    return status

def poe_update_percent(PSU_max_power):
    config_db = ConfigDBConnector()
    try:
        config_db.connect()
    except Exception as error:
        return False

    port_dict = config_db.get_table('PORT')
    if not port_dict:
        return False

    state_db = SonicV2Connector(host="127.0.0.1")
    try:
        state_db.connect(state_db.STATE_DB)
    except Exception as error:
        return False

    poe_power_sum = 0

    for interface_name in port_dict.keys():
        POE_power_value = state_db_poe_status_get(state_db, interface_name, POE_POWER)
        if POE_power_value != 'N/A':
            poe_power_sum += float(POE_power_value)

    poe_percent = poe_power_sum * 100 / PSU_max_power
    result = common.writeFile(common.I2C_PREFIX + common.SYS_PATH + 'poe_percent', poe_percent)
