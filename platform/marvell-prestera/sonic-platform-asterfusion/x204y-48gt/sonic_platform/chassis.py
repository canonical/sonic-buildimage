#!/usr/bin/env python3
#
# Name: chassis.py, version: 1.0
#
# Description: Module contains the definitions of SONiC platform APIs 
#

try:
    import os
    import time
    import sys
    import glob
    from sonic_platform_base.chassis_base import ChassisBase
    from sonic_platform.eeprom import Eeprom
    from sonic_platform.fan import Fan
    from sonic_platform.sfp import Sfp
    from sonic_platform.thermal import Thermal
    from sonic_platform.psu import Psu
except ImportError as e:
    raise ImportError(str(e) + "- required module not found")

SFP_STATUS_INSERTED = '1'
SFP_STATUS_REMOVED = '0'

# SFP PORT numbers
COPPER_PORT_START = 1
COPPER_PORT_END = 48
SFP_PORT_START = 49
SFP_PORT_END = 52

COPPER_TYPE = "COPPER"
SFP_TYPE = "SFP"
QSFP_TYPE = "QSFP"

_port_to_i2c_mapping = {
    0:  -1,
    1:  -1,
    2:  -1,
    3:  -1,
    4:  -1,
    5:  -1,
    6:  -1,
    7:  -1,
    8:  -1,
    9:  -1,
    10: -1,
    11: -1,
    12: -1,
    13: -1,
    14: -1,
    15: -1,
    16: -1,
    17: -1,
    18: -1,
    19: -1,
    20: -1,
    21: -1,
    22: -1,
    23: -1,
    24: -1,
    25: -1,
    26: -1,
    27: -1,
    28: -1,
    29: -1,
    30: -1,
    31: -1,
    32: -1,
    33: -1,
    34: -1,
    35: -1,
    36: -1,
    37: -1,
    38: -1,
    39: -1,
    40: -1,
    41: -1,
    42: -1,
    43: -1,
    44: -1,
    45: -1,
    46: -1,
    47: -1,
    48: 10,
    49: 11,
    50: 12,
    51: 13
}

class Chassis(ChassisBase):

    HOST_REBOOT_CAUSE_PATH = "/host/reboot-cause/"
    REBOOT_CAUSE_FILE = "reboot-cause.txt"
    PREV_REBOOT_CAUSE_FILE = "previous-reboot-cause.txt"

    def __init__(self):
        ChassisBase.__init__(self)
        self.__num_of_fans     = 3
        self.__num_of_sfps     = 52
        self.__num_of_thermals = 1
        self.__num_of_psu = 1

        # Initialize EEPROM
        self._eeprom = Eeprom()

        # Initialize FAN
        self.__num_of_fans = self.__get_num_fan()
        for index in range(1, self.__num_of_fans + 1):
            fan = Fan(index, False, 0)
            self._fan_list.append(fan)

        # Initialize PSU
        for index in range(1, self.__num_of_psu + 1):
            psu = Psu(index)
            self._psu_list.append(psu)

        # Initialize SFP
        eeprom_path = "/sys/bus/i2c/devices/{}-0050/eeprom"
        sfp_present_path = "/sys/bus/i2c/devices/6-0040/X204Y_48GT_SFP/SFP_present"

        for index in range(0, self.__num_of_sfps):
            port_eeprom_path = ''
            port_present_path = ''
            if index < COPPER_PORT_END:
                sfp_type = COPPER_TYPE
            else:
                sfp_type = SFP_TYPE
                port_eeprom_path = eeprom_path.format(_port_to_i2c_mapping[index])
                port_present_path = sfp_present_path

            sfp = Sfp(index, sfp_type, port_eeprom_path, port_present_path)
            self._sfp_list.append(sfp)

        # Initialize THERMAL
        for index in range(0, self.__num_of_thermals):
            thermal = Thermal(index)
            self._thermal_list.append(thermal)

    def __get_num_fan(self):
        fan_num = 0
        fan_num_path = "/sys/bus/i2c/devices/6-0040/X204Y_48GT_FAN/fan_num"
        try:
            with open(fan_num_path, 'r') as num_file:
                fan_num = int(num_file.read(),10)
        except:
            pass
        if fan_num != 2:
            fan_num = self.__num_of_fans
        return fan_num

##############################################
# Device methods
##############################################

    def get_name(self):
        """
        Retrieves the name of the chassis
        Returns:
            string: The name of the chassis
        """
        return "x204y-48gt"

    def get_presence(self):
        """
        Retrieves the presence of the chassis
        Returns:
            bool: True if chassis is present, False if not
        """
        return True

    def get_model(self):
        """
        Retrieves the model number (or part number) of the chassis
        Returns:
            string: Model/part number of chassis
        """
        return self._eeprom.part_number_str()

    def get_serial(self):
        """
        Retrieves the serial number of the chassis
        Returns:
            string: Serial number of chassis
        """
        return self._eeprom.serial_number_str()

    def get_status(self):
        """
        Retrieves the operational status of the chassis
        Returns:
            bool: A boolean value, True if chassis is operating properly
            False if not
        """
        return True

##############################################
# Chassis methods
##############################################

    def get_base_mac(self):
        """
        Retrieves the base MAC address for the chassis

        Returns:
            A string containing the MAC address in the format
            'XX:XX:XX:XX:XX:XX'
        """
        return self._eeprom.base_mac_address()

    def get_serial_number(self):
        """
        Retrieves the hardware serial number for the chassis

        Returns:
            A string containing the hardware serial number for this chassis.
        """
        return self._eeprom.serial_number_str()

    def get_system_eeprom_info(self):
        """
        Retrieves the full content of system EEPROM information for the chassis

        Returns:
            A dictionary where keys are the type code defined in
            OCP ONIE TlvInfo EEPROM format and values are their corresponding
            values.
            Ex. { '0x21':'AG9064', '0x22':'V1.0', '0x23':'AG9064-0109867821',
                  '0x24':'001c0f000fcd0a', '0x25':'02/03/2018 16:22:00',
                  '0x26':'01', '0x27':'REV01', '0x28':'AG9064-C2358-16G'}
        """
        return self._eeprom.system_eeprom_info()

    def get_reboot_cause(self):
        """
        Retrieves the cause of the previous reboot
        Returns:
            A tuple (string, string) where the first element is a string
            containing the cause of the previous reboot. This string must be
            one of the predefined strings in this class. If the first string
            is "REBOOT_CAUSE_HARDWARE_OTHER", the second string can be used
            to pass a description of the reboot cause.
        """
        sw_reboot_cause = ''
        sw_prev_reboot_cause = ''
        reboot_cause_file = self.HOST_REBOOT_CAUSE_PATH + self.REBOOT_CAUSE_FILE
        prev_reboot_cause_file = self.HOST_REBOOT_CAUSE_PATH + self.PREV_REBOOT_CAUSE_FILE

        if os.path.exists(reboot_cause_file):
            with open(reboot_cause_file, 'r') as f:
                sw_reboot_cause = f.read().strip()

        if os.path.exists(prev_reboot_cause_file):
            with open(prev_reboot_cause_file, 'r') as f:
                sw_prev_reboot_cause = f.read().strip()

        if sw_reboot_cause != "Unknown":
            reboot_cause = self.REBOOT_CAUSE_NON_HARDWARE
            description = sw_reboot_cause
        elif sw_prev_reboot_cause != "Unknown":
            reboot_cause = self.REBOOT_CAUSE_NON_HARDWARE
            description = sw_prev_reboot_cause
        else:
            reboot_cause = self.REBOOT_CAUSE_NON_HARDWARE
            description = 'None'
        return (reboot_cause, description)

    @property
    def _get_presence_bitmap(self):

        bits = []
        
        for x in self._sfp_list:
          bits.append(str(int(x.get_presence())))

        rev = "".join(bits[::-1])
        return int(rev,2)

    data = {'present':0}
    def get_transceiver_change_event(self, timeout=0):
        port_dict = {}

        if timeout == 0:
            cd_ms = sys.maxsize
        else:
            cd_ms = timeout

        #poll per second
        while cd_ms > 0:
            reg_value = self._get_presence_bitmap
            changed_ports = self.data['present'] ^ reg_value
            if changed_ports != 0:
                break
            time.sleep(1)
            cd_ms = cd_ms - 1000

        if changed_ports != 0:
            for port in range(0, self.__num_of_sfps):
                # Mask off the bit corresponding to our port
                mask = (1 << (port - 0))
                if changed_ports & mask:
                    if (reg_value & mask) == 0:
                        port_dict[port] = SFP_STATUS_REMOVED
                    else:
                        port_dict[port] = SFP_STATUS_INSERTED

            # Update cache
            self.data['present'] = reg_value
            return True, port_dict
        else:
            return True, {}
        return False, {}

    def get_change_event(self, timeout=0):
        res_dict = {
            'fan': {},
            'module': {},
            'sfp': {},
            'thermal': {},
        }
        ''' get transceiver change event '''
        res_dict['sfp'].clear()
        status, res_dict['sfp'] = self.get_transceiver_change_event(timeout)
        return status, res_dict

    def get_num_fan(self):
        return self.__num_of_fans
