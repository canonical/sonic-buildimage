#!/usr/bin/env python

#############################################################################
# Celestica
#
# Module contains an implementation of SONiC Platform Base API and
# provides the Chassis information which are available in the platform
#
#############################################################################

try:
    import sys
    import os
    from sonic_platform_base.chassis_base import ChassisBase
    from common import Common
except ImportError as e:
    raise ImportError(str(e) + "- required module not found")


class Chassis(ChassisBase):
    """Platform-specific Chassis class"""

    def __init__(self):
        ChassisBase.__init__(self)
        self._api_common = Common()

        self.__initialize_fan()
        self.__initialize_psu()
        self.__initialize_thermals()

        # self.is_host = self._api_common.is_host()

        # if not self.is_host:
        #     self.__initialize_fan()
        #     self.__initialize_psu()
        #     self.__initialize_thermals()
        # else:
        #     self.__initialize_components()

    def __initialize_fan(self):
        from sonic_platform.fan import Fan

        fan_config_path = self._api_common.get_config_path(Fan.FAN_CONFIG)
        fan_config = self._api_common.load_json_file(fan_config_path)

        if fan_config:
            fan_index = 0
            for drawer_index in range(0, fan_config['drawer_num']):
                for index in range(0, fan_config['fan_num_per_drawer']):
                    fan = Fan(fan_index, drawer_index, conf=fan_config)
                    fan_index += 1
                    self._fan_list.append(fan)

    # def __initialize_sfp(self):
    #     from sonic_platform.sfp import Sfp
    #     for index in range(0, NUM_SFP):
    #         sfp = Sfp(index)
    #         self._sfp_list.append(sfp)
    #     self.sfp_module_initialized = True

    def __initialize_psu(self):
        from sonic_platform.psu import Psu

        psu_config_path = self._api_common.get_config_path(Psu.PSU_CONFIG)
        psu_config = self._api_common.load_json_file(psu_config_path)
        
        if psu_config:
            psu_index = 0
            for index in range(0, psu_config['psu_num']):
                psu = Psu(psu_index, conf=psu_config)
                psu_index += 1
                self._psu_list.append(psu)

    def __initialize_thermals(self):
        from sonic_platform.thermal import Thermal

        thermal_config_path = self._api_common.get_config_path(Thermal.THERMAL_CONFIG)
        thermal_config = self._api_common.load_json_file(thermal_config_path)
        
        thermal_index = 0
        for index in range(0, thermal_config['thermal_num']):
            thermal = Thermal(thermal_index, conf=thermal_config)
            thermal_index += 1
            self._thermal_list.append(thermal)

    # def __initialize_eeprom(self):
    #     from sonic_platform.eeprom import Tlv
    #     self._eeprom = Tlv()

    # def __initialize_components(self):
    #     from sonic_platform.component import Component
    #     for index in range(0, NUM_COMPONENT):
    #         component = Component(index)
    #         self._component_list.append(component)

    # def get_base_mac(self):
    #     """
    #     Retrieves the base MAC address for the chassis
    #     Returns:
    #         A string containing the MAC address in the format
    #         'XX:XX:XX:XX:XX:XX'
    #     """
    #     return self._eeprom.get_mac()

    # def get_serial_number(self):
    #     """
    #     Retrieves the hardware serial number for the chassis
    #     Returns:
    #         A string containing the hardware serial number for this chassis.
    #     """
    #     return self._eeprom.get_serial()

    # def get_system_eeprom_info(self):
    #     """
    #     Retrieves the full content of system EEPROM information for the chassis
    #     Returns:
    #         A dictionary where keys are the type code defined in
    #         OCP ONIE TlvInfo EEPROM format and values are their corresponding
    #         values.
    #     """
    #     return self._eeprom.get_eeprom()

    # def get_reboot_cause(self):
    #     """
    #     Retrieves the cause of the previous reboot
    #     Returns:
    #         A tuple (string, string) where the first element is a string
    #         containing the cause of the previous reboot. This string must be
    #         one of the predefined strings in this class. If the first string
    #         is "REBOOT_CAUSE_HARDWARE_OTHER", the second string can be used
    #         to pass a description of the reboot cause.
    #     """
    #     description = 'None'
    #     reboot_cause = self.REBOOT_CAUSE_HARDWARE_OTHER

    #     reboot_cause_path = (
    #         HOST_REBOOT_CAUSE_PATH + REBOOT_CAUSE_FILE) if self.is_host else PMON_REBOOT_CAUSE_PATH + REBOOT_CAUSE_FILE
    #     prev_reboot_cause_path = (
    #         HOST_REBOOT_CAUSE_PATH + PREV_REBOOT_CAUSE_FILE) if self.is_host else PMON_REBOOT_CAUSE_PATH + PREV_REBOOT_CAUSE_FILE

    #     hw_reboot_cause = self._component_list[0].get_register_value(
    #         RESET_REGISTER)

    #     sw_reboot_cause = self._api_common.read_txt_file(
    #         reboot_cause_path) or "Unknown"
    #     prev_sw_reboot_cause = self._api_common.read_txt_file(
    #         prev_reboot_cause_path) or "Unknown"

    #     if sw_reboot_cause == "Unknown" and (prev_sw_reboot_cause == "Unknown" or prev_sw_reboot_cause == self.REBOOT_CAUSE_POWER_LOSS) and hw_reboot_cause == "0x11":
    #         reboot_cause = self.REBOOT_CAUSE_POWER_LOSS
    #     elif sw_reboot_cause != "Unknown" and hw_reboot_cause == "0x11":
    #         reboot_cause = self.REBOOT_CAUSE_NON_HARDWARE
    #         description = sw_reboot_cause
    #     elif prev_reboot_cause_path != "Unknown" and hw_reboot_cause == "0x11":
    #         reboot_cause = self.REBOOT_CAUSE_NON_HARDWARE
    #         description = prev_sw_reboot_cause
    #     elif hw_reboot_cause == "0x22":
    #         reboot_cause = self.REBOOT_CAUSE_WATCHDOG,
    #     else:
    #         reboot_cause = self.REBOOT_CAUSE_HARDWARE_OTHER
    #         description = 'Unknown reason'

    #     return (reboot_cause, description)

    # ##############################################################
    # ######################## SFP methods #########################
    # ##############################################################

    # def get_num_sfps(self):
    #     """
    #     Retrieves the number of sfps available on this chassis
    #     Returns:
    #         An integer, the number of sfps available on this chassis
    #     """
    #     if not self.sfp_module_initialized:
    #         self.__initialize_sfp()

    #     return len(self._sfp_list)

    # def get_all_sfps(self):
    #     """
    #     Retrieves all sfps available on this chassis
    #     Returns:
    #         A list of objects derived from SfpBase representing all sfps
    #         available on this chassis
    #     """
    #     if not self.sfp_module_initialized:
    #         self.__initialize_sfp()

    #     return self._sfp_list

    # def get_sfp(self, index):
    #     """
    #     Retrieves sfp represented by (1-based) index <index>
    #     Args:
    #         index: An integer, the index (1-based) of the sfp to retrieve.
    #         The index should be the sequence of a physical port in a chassis,
    #         starting from 1.
    #         For example, 1 for Ethernet0, 2 for Ethernet4 and so on.
    #     Returns:
    #         An object dervied from SfpBase representing the specified sfp
    #     """
    #     sfp = None
    #     if not self.sfp_module_initialized:
    #         self.__initialize_sfp()

    #     try:
    #         # The index will start from 1
    #         sfp = self._sfp_list[index-1]
    #     except IndexError:
    #         sys.stderr.write("SFP index {} out of range (1-{})\n".format(
    #                          index, len(self._sfp_list)))
    #     return sfp

    # ##############################################################
    # ####################### Other methods ########################
    # ##############################################################

    # def get_watchdog(self):
    #     """
    #     Retreives hardware watchdog device on this chassis
    #     Returns:
    #         An object derived from WatchdogBase representing the hardware
    #         watchdog device
    #     """
    #     if self._watchdog is None:
    #         from sonic_platform.watchdog import Watchdog
    #         self._watchdog = Watchdog()

    #     return self._watchdog

    # ##############################################################
    # ###################### Device methods ########################
    # ##############################################################

    # def get_name(self):
    #     """
    #     Retrieves the name of the device
    #         Returns:
    #         string: The name of the device
    #     """
    #     return self._api_common.hwsku

    # def get_presence(self):
    #     """
    #     Retrieves the presence of the PSU
    #     Returns:
    #         bool: True if PSU is present, False if not
    #     """
    #     return True

    # def get_model(self):
    #     """
    #     Retrieves the model number (or part number) of the device
    #     Returns:
    #         string: Model/part number of device
    #     """
    #     return self._eeprom.get_pn()

    # def get_serial(self):
    #     """
    #     Retrieves the serial number of the device
    #     Returns:
    #         string: Serial number of device
    #     """
    #     return self.get_serial_number()

    # def get_status(self):
    #     """
    #     Retrieves the operational status of the device
    #     Returns:
    #         A boolean value, True if device is operating properly, False if not
    #     """
    #     return True
