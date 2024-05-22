#!/usr/bin/env python3

"""
    Chassis module config
"""
try:
    import sys
    import os
    import subprocess
    from sonic_py_common import daemon_base
    from swsscommon import swsscommon
    from sonic_py_common.logger import Logger
except ImportError as e:
    raise ImportError(str(e) + " - required module wasn't found")

#
# Constants ====================================================================
#
SYSLOG_IDENTIFIER = 'chassis_module_config.py'
CHASSIS_MODULE= 'CHASSIS_MODULE'
SELECT_TIMEOUT_MSECS = 5000
CHASSIS_MODULE_SET_ADMIN_STATE = '/usr/local/bin/chassis_module_set_admin_state.py'

def main():
    logger = Logger(SYSLOG_IDENTIFIER)
    logger.set_min_log_priority_info()

    # dict
    current_module_state = dict()

    # Connect to STATE_DB and subscribe to chassis-module table notifications
    cfg_db = daemon_base.db_connect("CONFIG_DB")

    sel = swsscommon.Select()
    sst = swsscommon.SubscriberStateTable(cfg_db, CHASSIS_MODULE)
    sel.addSelectable(sst)

    while True:
        (state, c) = sel.select(SELECT_TIMEOUT_MSECS)
        if state == swsscommon.Select.TIMEOUT:
            continue

        (module_name, module_op, module_fvp) = sst.pop()

        state = current_module_state.get(module_name)
        module_fvs = dict(module_fvp)
        new_state = module_fvs.get('admin_status')

        if module_op == 'SET':
            if new_state is None:
                continue

            if state != new_state:
                if new_state == "down":
                    current_module_state[module_name] = "down"
                else:
                    current_module_state.pop(module_name, None)

                if os.path.exists(CHASSIS_MODULE_SET_ADMIN_STATE):
                    subprocess.run(['python3', CHASSIS_MODULE_SET_ADMIN_STATE, module_name, new_state])
                else:
                    logger.log_error("{} doesn't exist.".format(CHASSIS_MODULE_SET_ADMIN_STATE))

        elif module_op == 'DEL':
            if new_state is None:
                new_state = 'up'

            if state != new_state:
                if new_state == "up":
                    current_module_state[module_name] = "up"
                else:
                    current_module_state.pop(module_name, None)

                if os.path.exists(CHASSIS_MODULE_SET_ADMIN_STATE):
                    subprocess.run(['python3', CHASSIS_MODULE_SET_ADMIN_STATE, module_name, new_state])
                else:
                    logger.log_error("{} doesn't exist.".format(CHASSIS_MODULE_SET_ADMIN_STATE))

if __name__ == "__main__":
    main()
