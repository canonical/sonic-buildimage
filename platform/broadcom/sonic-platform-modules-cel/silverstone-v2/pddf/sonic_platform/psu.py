#!/usr/bin/env python
# @Company ：Celestica
# @Time    : 2023/6/13 13:46
# @Mail    : yajiang@celestica.com
# @Author  : jiang tao
try:
    from sonic_platform_pddf_base.pddf_psu import PddfPsu
    import re
    import os
    from . import helper
except ImportError as e:
    raise ImportError(str(e) + "- required module not found")

PSU_STATUS_INFO_CMD = "i2cget -y -f 100 0x0d 0x60"


class Psu(PddfPsu):
    """PDDF Platform-Specific PSU class"""

    def __init__(self, index, pddf_data=None, pddf_plugin_data=None):
        PddfPsu.__init__(self, index, pddf_data, pddf_plugin_data)
        self.helper = helper.APIHelper()

    @staticmethod
    def get_capacity():
        return 550

    @staticmethod
    def get_type():
        return 'AC'

    def get_status(self):
        """
        Get PSU1/2 power ok status by iic command
        return: True or False
        """
        status, res = self.helper.run_command(PSU_STATUS_INFO_CMD)
        if not status:
            return False
        psu_status = (bin(int(res, 16)))[-2:]
        psu_power_ok_index = 0 if self.psu_index == 1 else 1
        psu_power_ok = self.plugin_data['PSU']['psu_power_good']["i2c"]['valmap'][psu_status[psu_power_ok_index]]
        return psu_power_ok

    def get_presence(self):
        """
        Get PSU1/2 present status by iic command
        return: True or False
        """
        status, res = self.helper.run_command(PSU_STATUS_INFO_CMD)
        if not status:
            return False
        psu_status = (bin(int(res, 16)))[-4:-2]
        psu_present_index = 0 if self.psu_index == 1 else 1
        psu_present = self.plugin_data['PSU']['psu_present']["i2c"]['valmap'][psu_status[psu_present_index]]
        return psu_present

    @staticmethod
    def get_revision():
        """
        Get PSU HW Revision by read psu eeprom data.
        return: HW Revision or 'N/A'
        """
        return "N/A"

    @staticmethod
    def get_voltage_high_threshold():
        """
        Retrieves the high threshold PSU voltage output
        Returns:
            A float number, the high threshold output voltage in volts,
            e.g. 12.1
        """
        return 13.5

    @staticmethod
    def get_voltage_low_threshold():
        """
        Retrieves the low threshold PSU voltage output
        Returns:
            A float number, the low threshold output voltage in volts,
            e.g. 12.1
        """
        return 11.4

    @staticmethod
    def get_maximum_supplied_power():
        """
        Retrieves the maximum supplied power by PSU
        Returns:
            A float number, the maximum power output in Watts.
            e.g. 1200.1
        """
        return 1500
