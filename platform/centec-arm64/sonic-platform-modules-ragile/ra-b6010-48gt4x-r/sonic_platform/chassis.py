
#!/usr/bin/env python

try:
    import time
    import os
    from sonic_platform_base.chassis_base import ChassisBase
    from sonic_platform.eeprom import Eeprom
    from sonic_platform.fan import Fan
    from sonic_platform.thermal import Thermal
    from sonic_platform.fan_drawer import FanDrawer
    from sonic_platform.sfp import Sfp
    from sonic_platform.psu import Psu
    from .component import Component
except ImportError as e:
    raise ImportError(str(e) + "- required module not found")

NUM_FAN_TRAY = 2
NUM_FAN = 4
NUM_THERMAL = 5
NUM_PORT    = 52
NUM_PSU = 2

class Chassis(ChassisBase):

    port_dict = {}
    STATUS_INSERTED = "1"
    STATUS_REMOVED = "0"

    def __init__(self):
        ChassisBase.__init__(self)
        # Initialize EEPROM
        self._eeprom = Eeprom()
        #firmware
        for i in range(0,2):
            self._component_list.append(Component(i))
        # Initialize FAN
        for i in range(NUM_FAN_TRAY):
            fandrawer = FanDrawer(i)
            self._fan_drawer_list.append(fandrawer)
            self._fan_list.extend(fandrawer._fan_list)
        # Initialize THERMAL
        for index in range(0, NUM_THERMAL):
            thermal = Thermal(index)
            self._thermal_list.append(thermal)
        # Initialize SFP
        for index in range(0, NUM_PORT + 1):
            sfp = Sfp(index)
            self._sfp_list.append(sfp)
            if sfp.get_presence():
                self.port_dict[index] = self.STATUS_INSERTED
            else:
                self.port_dict[index] = self.STATUS_REMOVED
        # Initialize PSU
        for index in range(0, NUM_PSU):
            psu = Psu(index)
            self._psu_list.append(psu)

##############################################
# Device methods
##############################################

    def get_name(self):
        """
        Retrieves the name of the chassis
        Returns:
            string: The name of the chassis
        """
        return self._eeprom.modelstr()

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

    def get_revision(self):
        val  = ord(self._eeprom.revision_str())
        test = "{}".format(val)
        return test

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
        return self._eeprom.base_mac_addr()

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
        return (None, None)

    def get_change_event(self, timeout=0):
        """
        Returns a nested dictionary containing all devices which have
        experienced a change at chassis level

        Args:
            timeout: Timeout in milliseconds (optional). If timeout == 0,
                this method will block until a change is detected.

        Returns:
            (bool, dict):
                - bool: True if call successful, False if not;
                - dict: A nested dictionary where key is a device type,
                        value is a dictionary with key:value pairs in the format of
                        {'device_id':'device_event'}, where device_id is the device ID
                        for this device and device_event.
                        The known devices's device_id and device_event was defined as table below.
                         -----------------------------------------------------------------
                         device   |     device_id       |  device_event  |  annotate
                         -----------------------------------------------------------------
                         'fan'          '<fan number>'     '0'              Fan removed
                                                           '1'              Fan inserted

                         'sfp'          '<sfp number>'     '0'              Sfp removed
                                                           '1'              Sfp inserted
                                                           '2'              I2C bus stuck
                                                           '3'              Bad eeprom
                                                           '4'              Unsupported cable
                                                           '5'              High Temperature
                                                           '6'              Bad cable

                         'voltage'      '<monitor point>'  '0'              Vout normal
                                                           '1'              Vout abnormal
                         --------------------------------------------------------------------
                  Ex. {'fan':{'0':'0', '2':'1'}, 'sfp':{'11':'0', '12':'1'},
                       'voltage':{'U20':'0', 'U21':'1'}}
                  Indicates that:
                     fan 0 has been removed, fan 2 has been inserted.
                     sfp 11 has been removed, sfp 12 has been inserted.
                     monitored voltage U20 became normal, voltage U21 became abnormal.
                  Note: For sfp, when event 3-6 happened, the module will not be avalaible,
                        XCVRD shall stop to read eeprom before SFP recovered from error status.
        """

        change_event_dict = {"fan": {}, "sfp": {}, "voltage": {}}

        start_time = time.time()
        forever = False

        if timeout == 0:
            forever = True
        elif timeout > 0:
            timeout = timeout / float(1000)  # Convert to secs
        else:
            print("get_change_event:Invalid timeout value", timeout)
            return False, change_event_dict

        end_time = start_time + timeout
        if start_time > end_time:
            print(
                "get_change_event:" "time wrap / invalid timeout value",
                timeout,
            )
            return False, change_event_dict  # Time wrap or possibly incorrect timeout
        try:
            while timeout >= 0:
                # check for sfp
                sfp_change_dict = self.get_transceiver_change_event()
                # check for fan
                # fan_change_dict = self.get_fan_change_event()
                # check for voltage
                # voltage_change_dict = self.get_voltage_change_event()

                if sfp_change_dict:
                    change_event_dict["sfp"] = sfp_change_dict
                    # change_event_dict["fan"] = fan_change_dict
                    # change_event_dict["voltage"] = voltage_change_dict
                    return True, change_event_dict
                if forever:
                    time.sleep(1)
                else:
                    timeout = end_time - time.time()
                    if timeout >= 1:
                        time.sleep(1)  # We poll at 1 second granularity
                    else:
                        if timeout > 0:
                            time.sleep(timeout)
                        return True, change_event_dict
        except Exception as e:
            print(e)
        print("get_change_event: Should not reach here.")
        return False, change_event_dict

    def get_transceiver_change_event(self):
        current_port_dict = {}
        ret_dict = {}

        # Check for OIR events and return ret_dict
        for index in range(0, NUM_PORT + 1):
            if self._sfp_list[index].get_presence():
                current_port_dict[index] = self.STATUS_INSERTED
            else:
                current_port_dict[index] = self.STATUS_REMOVED

        if len(self.port_dict) == 0:       # first time
            self.port_dict = current_port_dict
            return {}

        if current_port_dict == self.port_dict:
            return {}

        # Update reg value
        for index, status in current_port_dict.items():
            if self.port_dict[index] != status:
                ret_dict[index] = status
                #ret_dict[str(index)] = status
        self.port_dict = current_port_dict
        for index, status in ret_dict.items():
            if int(status) == 1:
                pass
                #self._sfp_list[int(index)].check_sfp_optoe_type()
        return ret_dict

    def get_num_psus(self):
        return len(self._psu_list)

    def get_psu(self, psu_index):
        return self._psu_list[psu_index]

