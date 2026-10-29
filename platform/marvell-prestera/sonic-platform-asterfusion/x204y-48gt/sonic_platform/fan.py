#!/usr/bin/env python3
#
# Name: fan.py, version: 1.0
#
# Description: Module contains the definitions of SONiC platform APIs 
#

try:
    import math
    import os
    from sonic_platform_base.fan_base import FanBase
except ImportError as e:
    raise ImportError(str(e) + "- required module not found")

class Fan(FanBase):

    def __init__(self, index, is_psu_fan=False, psu_index=0):
        self.__index = index
        self.__is_psu_fan = is_psu_fan

        if self.__is_psu_fan:
            self.__psu_index        = psu_index
            self.present_path       = None
            self.psu_fan_speed_path = None
            self.__airflow_dir_attr = None
        else:
            self.fan_id = index
            self.present_path = None
            self.fan_pwm_path = "/sys/bus/i2c/devices/6-0040/X204Y_48GT_FAN/fan{}_outlet_rpm".format(self.fan_id)
            self.__airflow_dir_attr = None

    def __get_attr_value(self, attr_path):

        retval = 'ERR'
        if (not os.path.isfile(attr_path)):
            return retval

        try:
            with open(attr_path, 'r') as fd:
                retval = fd.read()
        except Exception as error:
            logging.error("Unable to open ", attr_path, " file !")

        retval = retval.rstrip(' \t\n\r')
        return retval

##############################################
# Device methods
##############################################

    def get_name(self):
        """
        Retrieves the name of the device

        Returns:
            string: The name of the device
        """
        if self.__is_psu_fan:
            return "PSU{}-FAN{}".format(self.__psu_index, self.__index)
        else:
            return "FAN{}".format(self.fan_id)

    def get_presence(self):
        """
        Retrieves the presence of the device

        Returns:
            bool: True if device is present, False if not
        """
        presence = 'False'
        present_path = self.present_path
        if present_path:
            present_val = self.__get_attr_value(self.present_path)
            if (present_val != 'ERR'):
                if self.__is_psu_fan:
                    if (int(present_val, 2) == 0):
                        presence = 'True'
                else:
                    if (int(present_val, 16) == 0):
                        presence = 'True'
        else:
            presence = 'True'
        return presence

    def get_model(self):
        """
        Retrieves the model number (or part number) of the device

        Returns:
            string: Model/part number of device
        """
        return "N/A"

    def get_serial(self):
        """
        Retrieves the serial number of the device

        Returns:
            string: Serial number of device
        """
        return "N/A"

    def get_status(self):
        """
        Retrieves the operational status of the device

        Returns:
            A boolean value, True if device is operating properly, False if not
        """
        return self.get_presence()

##############################################
# FAN methods
##############################################

    def get_direction(self):
        """
        Retrieves the direction of fan

        Returns:
            A string, either FAN_DIRECTION_INTAKE or FAN_DIRECTION_EXHAUST
            depending on fan direction
        """

        attr_path = self.__airflow_dir_attr

        if attr_path:
            attr_rv = self.__get_attr_value(attr_path)
            if (attr_rv != 'ERR'):
                dir = int(attr_rv)
                if (dir == 0):
                    return "exhaust"
                else:
                    return "intake"
            else:
                raise NotImplementedError
        else:         
            return "exhaust"

    def get_speed(self):
        """
        Retrieves the speed of fan as a percentage of full speed

        Returns:
            An integer, the percentage of full fan speed, in the range 0 (off)
                 to 100 (full speed)
        """
        speed = 0

        if self.__is_psu_fan:
            speed = self.__get_attr_value(self.psu_fan_speed_path)
            speed_val = int(speed, 10)
            if (speed_val >= 0):
                speed = speed_val / 1000
            else:
                speed = 0
        else:
            fan_pwm = self.__get_attr_value(self.fan_pwm_path)
            if (fan_pwm != 'ERR'):
                speed = fan_pwm
            else:
                speed = 0

        return speed

    def get_target_speed(self):
        """
        Retrieves the target (expected) speed of the fan

        Returns:
            An integer, the percentage of full fan speed, in the range 0 (off)
                 to 100 (full speed)
        """
        raise NotImplementedError

    def get_speed_tolerance(self):
        """
        Retrieves the speed tolerance of the fan

        Returns:
            An integer, the percentage of variance from target speed which is
                 considered tolerable
        """
        raise NotImplementedError

    def set_speed(self, speed):
        """
        Sets the fan speed

        Args:
            speed: An integer, the percentage of full fan speed to set fan to,
                   in the range 0 (off) to 100 (full speed)

        Returns:
            A boolean, True if speed is set successfully, False if not
        """
        raise NotImplementedError

    def set_status_led(self, color):
        """
        Sets the state of the fan module status LED

        Args:
            color: A string representing the color with which to set the
                   fan module status LED

        Returns:
            bool: True if status LED state is set successfully, False if not
        """
        raise NotImplementedError

    def get_status_led(self):
        """
        Gets the state of the fan status LED

        Returns:
            A string, one of the predefined STATUS_LED_COLOR_* strings above
        """
        if self.get_status() and self.get_speed() > 0:
            return self.STATUS_LED_COLOR_GREEN
        else:
            return self.STATUS_LED_COLOR_OFF

    def get_fan_info_dict(self):
        fan_info_dict = {}

        fan_info_dict['status'] = self.get_status()
        fan_info_dict['presence'] = self.get_presence()
        fan_info_dict['direction'] = self.get_direction()
        fan_info_dict['speed'] = str(int(self.get_speed())*120)


        return fan_info_dict
