#!/usr/bin/python3
# -*- coding: UTF-8 -*-
#   * onboard temperature sensors
#   * FAN trays
#   * PSU
#
import os
import xml.etree.ElementTree as ET
import glob
from fru import *
from fantlv import *



MAILBOX_DIR = "/sys/bus/i2c/devices/"
CONFIG_NAME = "dev.xml"


def byteTostr(val):
    strtmp = ''
    for i in range(len(val)):
        strtmp += chr(val[i])
    return strtmp


def dev_file_read(path, offset, len):
    # 读设备文件
    # @path: 文件路径
    # @offset: 文件的偏移地址
    # @len: 读取的长度
    # 返回值：
    #     成功: 返回读到的字符串
    #     失败: 返回ERR + 失败的msg
    retval = "ERR"
    fd = -1

    if not os.path.exists(path):
        return "%s %s not found" % (retval, path)

    try:
        fd = os.open(path, os.O_RDONLY)
        os.lseek(fd, offset, os.SEEK_SET)
        retval = os.read(fd, len)
    except Exception as e:
        msg = str(e)
        return "%s %s" % (retval, msg)
    finally:
        if fd > 0:
            os.close(fd)
    return retval

def getPMCreg(location):
    retval = 'ERR'
    if (not os.path.isfile(location)):
        return "%s %s  notfound"% (retval , location)
    try:
        with open(location, 'rb') as fd:
            retval = fd.read()
    except Exception as error:
        pass

    retval = byteTostr(retval)
    retval = retval.rstrip('\r\n')
    retval = retval.lstrip(" ")
    return retval
# Get a mailbox register
def get_pmc_register(reg_name):
    retval = 'ERR'
    mb_reg_file = reg_name
    filepath = glob.glob(mb_reg_file)
    if(len(filepath) == 0):
        return "%s %s  notfound"% (retval , mb_reg_file)
    mb_reg_file = filepath[0]        #如果找到多个匹配的路径，默认取第一个匹配的路径。
    if (not os.path.isfile(mb_reg_file)):
        #print mb_reg_file,  'not found !'
        return "%s %s  notfound"% (retval , mb_reg_file)
    try:
        with open(mb_reg_file, 'rb') as fd:
            retval = fd.read()
    except Exception as error:
        pass

    retval = byteTostr(retval)
    retval = retval.rstrip('\r\n')
    retval = retval.lstrip(" ")
    return retval
    
class checktype():
    def __init__(self, test1):
        self.test1 = test1
    @staticmethod
    def check(name,location, bit, value, tips , err1):
        psu_status = int(get_pmc_register(location),16)
        val = (psu_status & (1<< bit)) >> bit
        if (val != value):
            err1["errmsg"] = tips
            err1["code"] = -1
            return -1
        else:
            err1["errmsg"] = "none"
            err1["code"] = 0
            return 0
    @staticmethod
    def getValue(location, bit , value_type):
        value_t = get_pmc_register(location)
        if value_t.startswith("ERR") :
            return value_t
        if (value_type == 1):
            return float('%.1f' % (float(value_t)/1000))
        elif (value_type == 2):
            return float('%.1f' % (float(value_t)/100))
        elif (value_type == 3):
            psu_status = int(value_t,16)
            return (psu_status & (1<< bit)) >> bit
        elif (value_type == 4):
            return int(value_t,10)
        elif (value_type == 5):
            return float('%.1f' % (float(value_t)/1000/1000))
        else:
            return value_t;
#######temp
    @staticmethod
    def getTemp(self, name, location , ret_t):
        ret2 = self.getValue(location + "temp1_input" ," " ,1);
        ret3 = self.getValue(location + "temp1_max" ," ", 1);
        ret4 = self.getValue(location + "temp1_max_hyst" ," ", 1);
        ret_t["temp1_input"] = ret2
        ret_t["temp1_max"] = ret3
        ret_t["temp1_max_hyst"] = ret4
    @staticmethod
    def getLM75(name, location, result):
        c1=checktype
        r1={}
        c1.getTemp(c1, name, location, r1)
        result[name] = r1
##########fanFRU
    @staticmethod
    def decodeBinByValue(retval):
        fru = ipmifru()
        fru.decodeBin(retval)
        return fru
        
    @staticmethod
    def printbinvalue(b):
        index = 0
        print("     ", end="")
        for width in range(16):
            print("%02x " % width, end="")
        print("")
        for i in range(0, len(b)):
            if index % 16 == 0:
                print(" ")
                print(" %02x  " % i, end="")
            print("%02x " % ord(b[i]), end="")
            index += 1
        print("")
        
    @staticmethod
    def getfruValue(val):
        try:
            binval = dev_file_read(val, 0, 256)
            if isinstance(binval, bytes):
                binval = byteTostr(binval)
            if binval.startswith("ERR"):
                return binval
            fanpro = {}
            ret = checktype.decodeBinByValue(binval)
            fanpro['fan_type']  = ret.productInfoArea.productName
            fanpro['hw_version']  = ret.productInfoArea.productVersion
            fanpro['sn']  = ret.productInfoArea.productSerialNumber
            fanpro['fanid']  = ret.productInfoArea.productextra2
            return fanpro
        except Exception as error:
            return "ERR " + str(error)
    
    @staticmethod
    def getslottlvValue(val):
        try:
            binval = checktype.getValue(val, 0 , 0)
            if binval.startswith("ERR"):
                return binval
            slotpro = {}
            slottlv = fan_tlv()
            rets = slottlv.decode(binval)
            slotpro['slot_type']  = slottlv.typename
            slotpro['hw_version']  = slottlv.typehwinfo
            slotpro['sn']  = slottlv.typesn
            slotpro['slotid']  = slottlv.typedevtype
            return slotpro
        except Exception as error:
            return "ERR " + str(error)

    @staticmethod
    def getslotfruValue(val):
        try:
            binval = checktype.getValue(val, 0 , 0)
            if binval.startswith("ERR"):
                return binval
            slotpro = {}
            ret = checktype.decodeBinByValue(binval)
            slotpro['slot_type']  = ret.boardInfoArea.boardProductName
            slotpro['hw_version']  = ret.boardInfoArea.boardextra1
            slotpro['sn']  = ret.boardInfoArea.boardSerialNumber
            return slotpro
        except Exception as error:
            return "ERR " + str(error)

    @staticmethod
    def getpsufruValue(prob_t, root, val):
        try:
            binval = checktype.getValue(val, 0 , 0)
            if binval.startswith("ERR"):
                return binval
            psupro = {}
            ret = checktype.decodeBinByValue(binval)
            psupro['type1']  = ret.productInfoArea.productPartModelName
            psupro['sn']  = ret.productInfoArea.productSerialNumber
            psupro['hw_version'] = ret.productInfoArea.productVersion
            psu_list = status.getDecodValue(root, "psutype")##得到编码值7
            psupro['type1'] = psupro['type1'].strip()
            if psupro['type1'] not in psu_list:
                prob_t['errcode']= -1
                prob_t['errmsg'] = '%s'%  ("电源类型不匹配,请检查电源是否正确!")
            else:
                psupro['type1'] = psu_list[psupro['type1']]
            return psupro
        except Exception as error:
            return "ERR " + str(error)

class status():
    def __init__(self, productname):
        self.productname = productname
        
    @staticmethod
    def getETroot(filename):
        tree = ET.parse(filename)
        root = tree.getroot()
        return root;
    
    @staticmethod
    def getDecodValue(collection, decode):
        decodes = collection.find('decode')
        testdecode = decodes.find(decode)
        test={}
        for neighbor in testdecode.iter('code'):
            test[neighbor.attrib["key"]]=neighbor.attrib["value"]
        return test
    @staticmethod
    def getfileValue(location):
        return checktype.getValue(location," "," ")
    @staticmethod
    def getETValue(a, filename, tagname):
        root = status.getETroot(filename)
        for neighbor in root.iter(tagname):
            prob_t = {}
            prob_t = neighbor.attrib
            prob_t['errcode']= 0
            prob_t['errmsg'] = ''
            for pros in neighbor.iter("property"):
                ret = neighbor.attrib.copy()
                ret.update(pros.attrib)
                if ret.get('e2type') == 'fru' and ret.get("name") == "fru":
                    fruval = checktype.getfruValue(ret["location"])
                    if  isinstance(fruval, str) and fruval.startswith("ERR"):
                        prob_t['errcode']= -1
                        prob_t['errmsg']= fruval
                    else:
                        prob_t.update(fruval)
                    continue
        
                if ret.get("name") == "psu" and ret.get('e2type') == 'fru':
                    psuval = checktype.getpsufruValue(prob_t, root, ret["location"])
                    if  isinstance(psuval, str) and psuval.startswith("ERR"):
                        prob_t['errcode']= -1
                        prob_t['errmsg']= psuval
                    else:
                        prob_t.update(psuval)
                    continue
                        
                if ret.get("name") == "slot" and ret.get('e2type') == 'tlv':
                    slotval = checktype.getslottlvValue(ret["location"])
                    if  isinstance(slotval, str) and slotval.startswith("ERR"):
                        prob_t['errcode']= -1
                        prob_t['errmsg']= slotval
                    else:
                        prob_t.update(slotval)
                    continue
                if ret.get("name") == "slot" and ret.get('e2type') == 'fru':
                    slotval = checktype.getslotfruValue(ret["location"])
                    if  isinstance(slotval, str) and slotval.startswith("ERR"):
                        prob_t['errcode']= -1
                        prob_t['errmsg']= slotval
                    else:
                        prob_t.update(slotval)
                    continue

                if ('type' not in ret.keys()):
                    val = "0";
                else:
                    val = ret["type"]
                if ('bit' not in ret.keys()):
                    bit = "0"; 
                else:
                    bit = ret["bit"]
                s = checktype.getValue(ret["location"], int(bit),int(val))
                if  isinstance(s, str) and s.startswith("ERR"):
                    prob_t['errcode']= -1
                    prob_t['errmsg']= s
                if ('default' in ret.keys()):  ##需要检验
                    rt = status.getDecodValue(root,ret['decode'])##得到编码值7
                    prob_t['errmsg']= rt[str(s)]
                    if str(s) != ret["default"]:
                        prob_t['errcode']= -1
                        break;
                else:
                    if ('decode' in ret.keys()):
                        rt = status.getDecodValue(root,ret['decode'])##得到编码值7
                        if(ret['decode'] == "psutype" and s.replace("\x00","").rstrip() not in rt.keys()):    #电源类型检测
                                prob_t['errcode']= -1
                                prob_t['errmsg'] = '%s'%  ("电源类型不匹配,请检查电源是否正确!")
                        else:
                            s = rt[str(s).replace("\x00","").rstrip()]
                name = ret["name"]
                prob_t[name]=str(s)
            a.append(prob_t)
    @staticmethod
    def getCPUValue(a, filename, tagname):
        root = status.getETroot(filename)
        for neighbor in root.iter(tagname):
            location =  neighbor.attrib["location"]
        L=[]   
        for dirpath, dirnames, filenames in os.walk(location):
            for file in filenames :  
                if file.endswith("input"):  
                    L.append(os.path.join(dirpath, file))
            L =sorted(L,reverse=False)
        for i in range(len(L)):
            prob_t = {}
            prob_t["name"] = getPMCreg("%s/temp%d_label"%(location,i+1))
            prob_t["temp"] = float(getPMCreg("%s/temp%d_input"%(location,i+1)))/1000
            prob_t["alarm"] = float(getPMCreg("%s/temp%d_crit_alarm"%(location,i+1)))/1000
            prob_t["crit"] = float(getPMCreg("%s/temp%d_crit"%(location,i+1)))/1000
            prob_t["max"] = float(getPMCreg("%s/temp%d_max"%(location,i+1)))/1000
            a.append(prob_t)
            
    @staticmethod
    def getFileName():
        return  os.path.dirname(os.path.realpath(__file__)) + "/"+ CONFIG_NAME
    @staticmethod
    def getFan(ret):
        _filename = status.getFileName()
        _tagname = "fan"
        status.getvalue(ret, _filename, _tagname)
    @staticmethod
    def checkFan(ret):
        _filename = status.getFileName()
       # _filename = "/usr/local/bin/" + status.getFileName()
        _tagname = "fan"
        status.getETValue(ret, _filename, _tagname)
    @staticmethod
    def getTemp(ret):
        _filename = status.getFileName()
       #_filename = "/usr/local/bin/" + status.getFileName()
        _tagname = "temp"
        status.getETValue(ret, _filename, _tagname)
    @staticmethod
    def getPsu(ret):
        _filename = status.getFileName()
       # _filename = "/usr/local/bin/" + status.getFileName()
        _tagname = "psu"
        status.getETValue(ret, _filename, _tagname)
        
    @staticmethod
    def getcputemp(ret):
        _filename = status.getFileName()
        _tagname = "cpus" 
        status.getCPUValue(ret, _filename, _tagname)

        
