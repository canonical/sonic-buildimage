#############################################################################
# FS
#
# Module contains an implementation of SONiC Platform Base API and
# provides the PSUs status which are available in the platform
#
#############################################################################

#import sonic_platform

try:
    from sonic_platform_base.psu_base import PsuBase
    from sonic_platform.thermal import Thermal
    from .helper import APIHelper
except ImportError as e:
    raise ImportError(str(e) + "- required module not found")

I2C_PATH = "/sys/bus/i2c/devices/{}-00{}/"

PSU_NAME_LIST = ["PSU-1", "PSU-2"]
PSU_NUM_FAN = [1, 1]
PSU_HWMON_I2C_MAPPING = {
    0: {
        "bus": 17,
        "addr": "59"
    },
    1: {
        "bus": 13,
        "addr": "5b"
    },
}

PSU_CPLD_I2C_MAPPING = {
    0: {
        "bus": 17,
        "addr": "51"
    },
    1: {
        "bus": 13,
        "addr": "53"
    },
}

NUM_FAN_TRAY = 6


class Psu(PsuBase):
    """Platform-specific Psu class"""

    def __init__(self, psu_index=0):
        PsuBase.__init__(self)
        self.index = psu_index
        self._api_helper = APIHelper()

        bus = PSU_HWMON_I2C_MAPPING[self.index]["bus"]
        addr = PSU_HWMON_I2C_MAPPING[self.index]["addr"]
        self.hwmon_path = I2C_PATH.format(bus, addr)

        bus = PSU_CPLD_I2C_MAPPING[self.index]["bus"]
        addr = PSU_CPLD_I2C_MAPPING[self.index]["addr"]
        self.cpld_path = I2C_PATH.format(bus, addr)
        self.__initialize_fan()
        
    def __initialize_fan(self):
        from sonic_platform.fan import Fan
        self._fan_list.append(
            Fan(NUM_FAN_TRAY + self.index,
                is_psu_fan=True,
                psu_index=self.index))
        self._thermal_list.append(Thermal(is_psu=True, psu_index=self.index))

    def get_voltage(self):
        """
        Retrieves current PSU voltage output
        Returns:
            A float number, the output voltage in volts,
            e.g. 12.1
        """
        val = self._api_helper.read_txt_file(self.hwmon_path + "psu_v_out")
        if val is not None:
            return float(val)/ 1000
        else:
            return 0

    def get_current(self):
        """
        Retrieves present electric current supplied by PSU
        Returns:
            A float number, the electric current in amperes, e.g 15.4
        """
        val = self._api_helper.read_txt_file(self.hwmon_path + "psu_i_out")
        if val is not None:
            return float(val)/1000
        else:
            return 0

    def get_power(self):
        """
        Retrieves current energy supplied by PSU
        Returns:
            A float number, the power in watts, e.g. 302.6
        """
        val = self._api_helper.read_txt_file(self.hwmon_path + "psu_p_out")
        if val is not None:
            return float(val)/1000
        else:
            return 0
        
    def get_powergood_status(self):
        """
        Retrieves the powergood status of PSU
        Returns:
            A boolean, True if PSU has stablized its output voltages and passed all
            its internal self-tests, False if not.
        """
        return self.get_status()

    def set_status_led(self, color):
        """
        Sets the state of the PSU status LED
        Args:
            color: A string representing the color with which to set the PSU status LED
                   Note: Only support green and off
        Returns:
            bool: True if status LED state is set successfully, False if not
        """

        return False  #Controlled by HW

    def get_status_led(self):
        """
        Gets the state of the PSU status LED
        Returns:
            A string, one of the predefined STATUS_LED_COLOR_* strings above
        """
        status=self.get_status()
        if not status:
            return  self.STATUS_LED_COLOR_RED
        
        if status==1:
            return self.STATUS_LED_COLOR_GREEN
        else:
            return self.STATUS_LED_COLOR_RED
        

    def get_temperature(self):
        """
        Retrieves current temperature reading from PSU
        Returns:
            A float number of current temperature in Celsius up to nearest thousandth
            of one degree Celsius, e.g. 30.125
        """
        return self._thermal_list[0].get_temperature()

    def get_temperature_high_threshold(self):
        """
        Retrieves the high threshold temperature of PSU
        Returns:
            A float number, the high threshold temperature of PSU in Celsius
            up to nearest thousandth of one degree Celsius, e.g. 30.125
        """
        return self._thermal_list[0].get_high_threshold()

    def get_voltage_high_threshold(self):
        """
        Retrieves the high threshold PSU voltage output
        Returns:
            A float number, the high threshold output voltage in volts,
            e.g. 12.1
        """
        val = self._api_helper.read_txt_file(self.hwmon_path + "psu_mfr_vout_max")
        if val is not None:
            return float(val)/ 1000
        else:
            return 0

    def get_voltage_low_threshold(self):
        """
        Retrieves the low threshold PSU voltage output
        Returns:
            A float number, the low threshold output voltage in volts,
            e.g. 12.1
        """
        val = self._api_helper.read_txt_file(self.hwmon_path + "psu_mfr_vout_min")
        if val is not None:
            return float(val)/ 1000
        else:
            return 0

    def get_name(self):
        """
        Retrieves the name of the device
            Returns:
            string: The name of the device
        """
        return PSU_NAME_LIST[self.index]

    def get_presence(self):
        """
        Retrieves the presence of the PSU
        Returns:
            bool: True if PSU is present, False if not
        """
        val = self._api_helper.read_txt_file(self.cpld_path + "psu_present")
        if val is not None:
            return val == '1'
        else:
            return False

    def get_status(self):
        """
        Retrieves the operational status of the device
        Returns:
            A boolean value, True if device is operating properly, False if not
        """
        val = self._api_helper.read_txt_file(self.cpld_path + "psu_power_good")
        if val is not None:
            return val == '1'
        else:
            return False

    def get_model(self):
        """
        Retrieves the model number (or part number) of the device
        Returns:
            string: Model/part number of device
        """
        model = self._api_helper.read_txt_file(self.cpld_path + "psu_model_name")
        if model is None:
            return "N/A"
        return model

    def get_serial(self):
        """
        Retrieves the serial number of the device
        Returns:
            string: Serial number of device
        """
        serial = self._api_helper.read_txt_file(self.cpld_path + "psu_serial_number")
        if serial is None:
            return "N/A"
        return serial

    def get_position_in_parent(self):
        """
        Retrieves 1-based relative physical position in parent device. If the agent cannot determine the parent-relative position
        for some reason, or if the associated value of entPhysicalContainedIn is '0', then the value '-1' is returned
        Returns:
            integer: The 1-based relative physical position in parent device or -1 if cannot determine the position
        """
        return self.index+1

    def is_replaceable(self):
        """
        Indicate whether this device is replaceable.
        Returns:
            bool: True if it is replaceable.
        """
        return True

