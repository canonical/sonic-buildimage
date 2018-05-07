#!/usr/bin/env python
#
# Copyright (C) 2018 Inventec, Inc.
# 
# Editor: James Huang ( Huang.James@inventec.com )
#  
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

"""
Usage: %(scriptName)s [options] command object

Auto detecting the transceiver and set the correct if_type value

options:
    -h | --help     : this help message
    -d | --debug    : run with debug mode
   
"""

try:
    import os
    import commands
    import sys, getopt
    import logging
    import re
    import time
    import datetime
    import syslog
    from sfputil import SfpUtil
    from sonic_sfp.bcmshell import bcmshell
    
except ImportError as e:
    raise ImportError("%s - required module not found" % str(e))

DEBUG = False
args = []
INV_REDWOOD_PLATFORM = "SONiC-Inventec-d7032-100"
INV_CYPRESS_PLATFORM = "SONiC-Inventec-d7054"
INV_SEQUOIA_PLATFORM = "SONiC-Inventec-d7264"

transceiver_type_dict = { 
                          "FCBG110SD1C03": "SR",
                          "FCBG110SD1C05": "SR",
                          "FTLX8571D3BCL": "SR",
                          "FTLX8574D3BCL": "SR",
                          "AFBR-709DMZ": "SR",
                          "AFBR-709SMZ": "SR",
                          "FTLX8571D3BCV": "SR",
                          "FTLX1471D3BCL": "SR",
                          "FTLX1871M3BCL": "SR",
                          "FTLF8536P4BCL": "SR",
                          "FCBG125SD1C05": "SR",
                          "FCBG125SD1C30": "SR",
                          "FCBG410QB1C03-1E": "SR4",
                          "FCBG4100QB1C030-1E": "SR4",
                          "885350163": "SR4",
                          "88535017": "SR4",
                          "FTL410QE2C": "SR4",
                          "FTL410QD3C": "SR4",
                          "FTL410QD2C": "SR4",
                          "AFBR-79E3PZ": "SR4",
                          "AFBR-79Q4Z": "SR4",
                          "FTL4C1QE1C": "SR4",
                          "FTLC9551REPM": "SR4",
                          "FTLC1151RDPL": "SR4",
                          "DAC-010SS-X50" : "KR",
                          "DAC-010QQ-X50": "KR4",
                          "DAC-040QS-007": "KR4",
                          "DAC-040QQ-007": "KR4",
                          "DAC-040QQ-005": "KR4",
                          "DAC-040QS-005": "KR4",
                          "NDAAFF-0001": "KR4",
                          "L0HQF001-SD-R": "KR4",
                          "DAC-Q28/Q28-28-01": "KR4",
                          "NDAAFF-0003": "KR4",
                          "NDAQGF0001": "KR4",
                          "L0HQF003-SD-R": "KR4",
                          "NDAQGJ-0003": "KR4",
                          "L0HQF004-SD-R": "KR4",
                          "L0HSF006-SD-R": "KR",
                          "L0HSF007-SD-R": "KR",
                          "L0HSF008-SD-R": "KR",
                          "L0HQF009-SD-R": "KR4"
                        }
 
initial_command = []

def show_help():
    print __doc__ % {'scriptName' : sys.argv[0].split("/")[-1]}
    sys.exit(0)

def log_message( string ):
    syslog.openlog("transceiver_monitor", syslog.LOG_PID, facility=syslog.LOG_DAEMON)
    syslog.syslog(syslog.LOG_NOTICE, string)

class BCMUtil(bcmshell):

    port_to_bcm_mapping = dict()         
    sal_config_list = dict()
    eagle_list = []
    platform = None
    
    def get_platform(self):
        if self.platform is None:
            self.platform = os.popen("uname -n").read().strip()
        return self.platform
    
    def get_port_to_bcm_mapping(self):  
        if self.port_to_bcm_mapping is None:
            return dict()
        else:
            return self.port_to_bcm_mapping     
    
    def show_port_to_bcm_mapping(self):  
        print self.port_to_bcm_mapping
    
    def get_eagle_port(self):
        return self.eagle_list
        
    def parsing_eagle_port(self):
        name = self.get_platform()
        if name is not None:
            if name == INV_REDWOOD_PLATFORM:
                self.eagle_list = [66,100]
            elif name == INV_CYPRESS_PLATFORM:
                self.eagle_list = [66,100]
            elif name == INV_SEQUOIA_PLATFORM:
                self.eagle_list = [66,100]
            else:
                self.eagle_list = []
                
    def get_sal_config_list(self):
        return self.sal_config_list

    def show_sal_config_list(self):
        print self.sal_config_list
        
    def initial_sal_config_list( self ):
        content = self.run("config")  
        for line in content.split("\n"):
            ConfigObject = re.search(r"portmap\_(?P<bcm_id>\d+)\=(?P<lane_id>\d+)\:\d+",line)
            if ConfigObject is not None:   
                if int(ConfigObject.group("bcm_id")) not in self.get_eagle_port():
                    self.get_sal_config_list()[int(ConfigObject.group("bcm_id"))]={"lane": int(ConfigObject.group("lane_id")), "speed": None, "portname": None} 
                
    def parsing_port_list(self):
        content = self.run("ps")
        count = 0
        for line in content.split("\n"):
            PSObject = re.search(r"(?P<port_name>(xe|ce)\d+)\(\s*(?P<bcm_id>\d+)\).+\s+(?P<speed>\d+)G",line)
            if PSObject is not None:
                if int(PSObject.group("bcm_id")) not in self.get_eagle_port():                    
                    if self.get_sal_config_list().has_key(int(PSObject.group("bcm_id"))):
                        self.get_sal_config_list()[int(PSObject.group("bcm_id"))]["portname"] = PSObject.group("port_name")
                        self.get_sal_config_list()[int(PSObject.group("bcm_id"))]["speed"] = int(PSObject.group("speed"))*1000
                        self.port_to_bcm_mapping[count] = int(PSObject.group("bcm_id"))
                        count = count +1
                
    
    def execute_command(self, cmd):
        self.cmd(cmd)

class TransceiverUtil(SfpUtil):     
    
    transceiver_port_mapping = dict()
    
    def get_transceiver_port_mapping(self):
        return self.transceiver_port_mapping
        
    def show_transceiver_port_mapping(self):
        print self.transceiver_port_mapping        
       
    def get_bcm_port_name(self, index):
        if self.transceiver_port_mapping.has_key(index) and bcm_obj.get_sal_config_list().has_key(self.transceiver_port_mapping[index]["bcm"]):
            return bcm_obj.get_sal_config_list()[self.transceiver_port_mapping[index]["bcm"]]["portname"]            
        else:
            return ""
                
    def get_port_to_i2c_mapping(self):
        if self.port_to_i2c_mapping is None:
            return dict()
        else:
            return self.port_to_i2c_mapping
    
    def show_port_to_i2c_mapping(self):
        print self.port_to_i2c_mapping
        
    def get_eeprom_partNum(self, portNum):
        tempdict = dict()
        tempdict = self.get_eeprom_dict(portNum)
        self.get_eeprom_partNum_from_parser_eeprom_dict(tempdict)
    
    def get_eeprom_dict_info(self, portNum): 
        return self.get_eeprom_dict(portNum) 
                
    def get_eeprom_partNum_from_parser_eeprom_dict(self, tempdict ):
        if tempdict is not None:
            if tempdict["interface"]["data"].has_key("VendorPN"):
               return tempdict["interface"]["data"]["VendorPN"]
            elif tempdict["interface"]["data"].has_key("Vendor PN"):
                return tempdict["interface"]["data"]["Vendor PN"]
            else:
                return None
        else:
            return None
            
    def get_transceiver_type(self, pn ):
        if pn is not None:
            if transceiver_type_dict.has_key(pn.upper()):
                return transceiver_type_dict[pn.upper()]
            else:
                return None    

    def set_transceiver_type( self, portNum, pn ):
        type = self.get_transceiver_type( pn )
        if type is not None:             
            if bcm_obj.get_platform() == INV_SEQUOIA_PLATFORM:
                speed = bcm_obj.get_sal_config_list()[self.transceiver_port_mapping[portNum]["bcm"]]["speed"]
                bcm_obj.execute_command( "port %s if=%s speed=%d" % ( self.get_bcm_port_name(portNum), type, speed ) )
            else:
                bcm_obj.execute_command( "port %s if=%s" % ( self.get_bcm_port_name(portNum), type ) )
            #print "Detecting port {0} need to change interface type {1} ({2})".format(self.get_bcm_port_name(portNum), type, self.get_transceiver_port_mapping()[portNum]["pn"])
            log_message("Detecting port {0} need to change interface type {1} ({2})".format(self.get_bcm_port_name(portNum), type, self.get_transceiver_port_mapping()[portNum]["pn"]) )
    
    def initial_transceiver_port_mapping(self):
        for index in self.get_port_to_i2c_mapping().keys():
            if self.transceiver_port_mapping.has_key(index) is False :
                i2cValue = self.get_port_to_i2c_mapping()[index]
                bcmValue = bcm_obj.get_port_to_bcm_mapping()[index]
                self.transceiver_port_mapping[index]={"i2c": i2cValue, "bcm": bcmValue , "pn": None}
            
    def set_power_mode_for_QSFP(self):
        for index in self.get_port_to_i2c_mapping().keys():
            if index >= self.qsfp_port_start and index <= self.qsfp_port_end :
                self.set_low_power_mode(index, False)

def main():
    try:
        global DEBUG  
        global transceiver_obj
        global bcm_obj
        
        initalNotOK = True
        retestCount = 0 
        while initalNotOK :
            try:                
                transceiver_obj = TransceiverUtil()
                bcm_obj = BCMUtil()
                initalNotOK = False
            except Exception, e:               
                log_message("Exception. The warning is {0}, Retry again ({1})".format(str(e),retestCount) )                    
                retestCount = retestCount + 1
            time.sleep(5)
         
        log_message( "Object initialed successfully" )  

        options, args = getopt.getopt(sys.argv[1:], 'hd', ['help',
                                                           'debug'
                                                              ])
        for opt, arg in options:
            if opt in ('-h', '--help'):
                show_help()
            elif opt in ('-d', '--debug'):            
                DEBUG = True
                logging.basicConfig(level=logging.INFO)
            else:
                logging.info("no option")
 
        # Before loop, You could execute specific command to initial chip
        for cmd_index in initial_command :
            bcm_obj.execute_command(cmd_index)
        
        # Initial the sal config list
        bcm_obj.parsing_eagle_port()
        bcm_obj.initial_sal_config_list()
        bcm_obj.parsing_port_list()                 
        # bcm_obj.show_port_to_bcm_mapping()                 
        # bcm_obj.show_sal_config_list()
        
        # Initial the transceiver_obj 
        transceiver_obj.initial_transceiver_port_mapping()       
        # transceiver_obj.show_transceiver_port_mapping()
                          
        transceiver_obj.set_power_mode_for_QSFP()

        while 1 :
            if bcm_obj.get_platform() == INV_SEQUOIA_PLATFORM:
                bcm_obj.parsing_port_list()  
            for index in transceiver_obj.get_port_to_i2c_mapping().keys():
                info = transceiver_obj.get_eeprom_dict_info(index)
                value = transceiver_obj.get_eeprom_partNum_from_parser_eeprom_dict(info)
                if transceiver_obj.get_transceiver_port_mapping().has_key(index) is not False and transceiver_obj.get_transceiver_port_mapping()[index]["pn"] <> value:
                    transceiver_obj.get_transceiver_port_mapping()[index]["pn"] = value
                    transceiver_obj.set_transceiver_type(index,value)    
                    #transceiver_obj.show_transceiver_port_mapping()            
            time.sleep(1)

    except (Exception, KeyboardInterrupt) as e:
        log_message("Terminating this python daemon ({0})".format(e))   
        syslog.closelog()
        del transceiver_obj
        del bcm_obj

if __name__ == "__main__":
    main()




