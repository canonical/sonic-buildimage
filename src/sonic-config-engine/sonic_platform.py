#!/usr/bin/env python
import os
import yaml
import subprocess

DOCUMENTATION = '''
---
module: sonic_platform
version_added: "1.9"
short_description: Retrive platform related facts for a device.
description:
    - Retrieve platform related facts from config files.
'''

def get_machine_info():
    if not os.path.isfile('/host/machine.conf'):
        return None
    machine_vars = {}
    with open('/host/machine.conf') as machine_file:
        for line in machine_file:
            tokens = line.split('=')
            if len(tokens) < 2:
                continue
            machine_vars[tokens[0]] = tokens[1].strip()
    return machine_vars

def get_platform_info(machine_info):
    if machine_info != None:
        if machine_info.has_key('onie_platform'):
            return  machine_info['onie_platform']
        elif machine_info.has_key('aboot_platform'):
            return machine_info['aboot_platform']
    return None

def get_sonic_version_info():
    if not os.path.isfile('/etc/sonic/sonic_version.yml'):
        return None
    data = {}
    with open('/etc/sonic/sonic_version.yml') as stream:
        data = yaml.load(stream)
    return data

def get_system_mac():
    version_info = get_sonic_version_info()

    if (version_info['asic_type'] == 'mellanox'):
        get_mac_cmd = "sudo decode-syseeprom -m"
    else:
        get_mac_cmd = "ip link show eth0 | grep ether | awk '{print $2}'"

    proc = subprocess.Popen(get_mac_cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    (mac, err) = proc.communicate()
    if err:
        return None

    mac = mac.strip()
    
    # Align last byte of MAC if necessary
    if version_info and (version_info['asic_type'] == 'mellanox' or version_info['asic_type'] == 'centec'):
        last_byte = mac[-2:]
        aligned_last_byte = format(int(int(last_byte, 16) & 0b11000000), '02x')
        mac = mac[:-2] + aligned_last_byte
    return mac

