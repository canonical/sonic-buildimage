#!/usr/bin/env python

#############################################################################
#
# Platform and model specific eeprom subclass, inherits from the base class,
# and provides the followings:
# - the eeprom format definition
# - specific encoder/decoder if there is special need
#############################################################################

try:
    import exceptions
    import binascii
    import time
    import optparse
    import warnings
    import os
    import sys
    from sonic_eeprom import eeprom_base
    from sonic_eeprom import eeprom_tlvinfo
    import subprocess
except ImportError as e:
    raise ImportError (str(e) + "- required module not found")

class board(eeprom_tlvinfo.TlvInfoDecoder):
    _TLV_INFO_MAX_LEN = 2048
    def __init__(self, name, path, cpld_root, ro):
        self.eeprom_path = "/sys/bus/i2c/devices/7-0050/eeprom"
        super(board, self).__init__(self.eeprom_path, 0, '', True)