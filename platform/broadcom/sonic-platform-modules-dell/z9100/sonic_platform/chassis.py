#!/usr/bin/env python

#############################################################################
# DELLEMC
#
# Module contains an implementation of SONiC Platform Base API and
# provides the platform information
#
#############################################################################

try:
    import os
    from sonic_platform_base.chassis_base import ChassisBase
    from sonic_platform.sfp import Sfp
except ImportError as e:
    raise ImportError(str(e) + "- required module not found")


class Chassis(ChassisBase):
    """
    DELLEMC Platform-specific Chassis class
    """

    HWMON_DIR = "/sys/devices/platform/SMF.512/hwmon/"
    HWMON_NODE = os.listdir(HWMON_DIR)[0]
    MAILBOX_DIR = HWMON_DIR + HWMON_NODE
    EEPROM_I2C_MAPPING = {
        0: [9, 18], 1: [9, 19], 2: [9, 20], 3: [9, 21],
        4: [9, 22], 5: [9, 23], 6: [9, 24], 7: [9, 25],
        8: [8, 26], 9: [8, 27], 10: [8, 28], 11: [8, 29],
        12: [8, 31], 13: [8, 30], 14: [8, 33], 15: [8, 32],  # Remapped 4 entries
        16: [7, 34], 17: [7, 35], 18: [7, 36], 19: [7, 37],
        20: [7, 38], 21: [7, 39], 22: [7, 40], 23: [7, 41],
        24: [6, 42], 25: [6, 43], 26: [6, 44], 27: [6, 45],
        28: [6, 46], 29: [6, 47], 30: [6, 48], 31: [6, 49]
    }
    PORT_I2C_MAPPING = {
        # 0th Index = i2cLine, 1st Index = portIdx in i2cLine
        0: [14, 0], 1: [14, 1], 2: [14, 2], 3: [14, 3],
        4: [14, 4], 5: [14, 5], 6: [14, 6], 7: [14, 7],
        8: [14, 8], 9: [14, 9], 10: [14, 10], 11: [14, 11],
        12: [15, 0], 13: [15, 1], 14: [15, 2], 15: [15, 3],
        16: [15, 4], 17: [15, 5], 18: [15, 6], 19: [15, 7],
        20: [15, 8], 21: [15, 9], 22: [16, 0], 23: [16, 1],
        24: [16, 2], 25: [16, 3], 26: [16, 4], 27: [16, 5],
        28: [16, 6], 29: [16, 7], 30: [16, 8], 31: [16, 9]
    }

    reset_reason_dict = {}
    reset_reason_dict[11] = ChassisBase.REBOOT_CAUSE_POWER_LOSS
    reset_reason_dict[33] = ChassisBase.REBOOT_CAUSE_WATCHDOG
    reset_reason_dict[44] = ChassisBase.REBOOT_CAUSE_NON_HARDWARE
    reset_reason_dict[55] = ChassisBase.REBOOT_CAUSE_NON_HARDWARE

    power_reason_dict = {}
    power_reason_dict[11] = ChassisBase.REBOOT_CAUSE_POWER_LOSS
    power_reason_dict[22] = ChassisBase.REBOOT_CAUSE_THERMAL_OVERLOAD_CPU
    power_reason_dict[33] = ChassisBase.REBOOT_CAUSE_THERMAL_OVERLOAD_ASIC
    power_reason_dict[44] = ChassisBase.REBOOT_CAUSE_INSUFFICIENT_FAN_SPEED

    def __init__(self):
        PORT_START = 0
        PORT_END = 31
        PORTS_IN_BLOCK = (PORT_END + 1)

        # sfp.py will read eeprom contents and retrive the eeprom data.
        # It will also provide support sfp controls like reset and setting
        # low power mode.
        # We pass the eeprom path and sfp control path from chassis.py
        # So that sfp.py implementation can be generic to all platforms
        eeprom_base = "/sys/class/i2c-adapter/i2c-{0}/i2c-{1}/{1}-0050/eeprom"
        sfp_ctrl_base = "/sys/class/i2c-adapter/i2c-{0}/{0}-003e/"
        for index in range(0, PORTS_IN_BLOCK):
            eeprom_path = eeprom_base.format(self.EEPROM_I2C_MAPPING[index][0],
                                             self.EEPROM_I2C_MAPPING[index][1])
            sfp_control = sfp_ctrl_base.format(self.PORT_I2C_MAPPING[index][0])
            sfp_node = Sfp(index, 'QSFP', eeprom_path, sfp_control,
                           self.PORT_I2C_MAPPING[index][1])
            self._sfp_list.append(sfp_node)

    def get_pmc_register(self, reg_name):
        # On successful read, returns the value read from given
        # reg_name and on failure returns 'ERR'
        rv = 'ERR'
        mb_reg_file = self.MAILBOX_DIR + '/' + reg_name

        if (not os.path.isfile(mb_reg_file)):
            return rv

        try:
            with open(mb_reg_file, 'r') as fd:
                rv = fd.read()
        except Exception as error:
            rv = 'ERR'

        rv = rv.rstrip('\r\n')
        rv = rv.lstrip(" ")
        return rv

    def get_reboot_cause(self):
        """
        Retrieves the cause of the previous reboot
        """
        reset_reason = int(self.get_pmc_register('smf_reset_reason'))
        power_reason = int(self.get_pmc_register('smf_poweron_reason'))

        # Reset_Reason = 11 ==> PowerLoss
        # So return the reboot reason from Last Power_Reason Dictionary
        # If Reset_Reason is not 11 return from Reset_Reason dictionary
        # Also check if power_reason, reset_reason are valid values by
        # checking key presence in dictionary else return
        # REBOOT_CAUSE_HARDWARE_OTHER as the Power_Reason and Reset_Reason
        # registers returned invalid data
        if (reset_reason == 11):
            if (power_reason in self.power_reason_dict):
                return (self.power_reason_dict[power_reason], None)
        else:
            if (reset_reason in self.reset_reason_dict):
                return (self.reset_reason_dict[reset_reason], None)

        return (ChassisBase.REBOOT_CAUSE_HARDWARE_OTHER, "Invalid Reason")
