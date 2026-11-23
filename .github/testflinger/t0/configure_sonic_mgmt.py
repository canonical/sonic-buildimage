#!/usr/bin/env python3
"""Apply the KVM testbed settings of the upstream guide to a sonic-mgmt tree.

usage: configure_sonic_mgmt.py <sonic-mgmt dir> <vm host user> <vm host password>
"""
import re
import sys
from pathlib import Path

PY = "ansible_python_interpreter: /usr/bin/python3"


def set_creds(text, user, password):
    for key, value in (("vm_host_user", user), ("vm_host_password", password), ("vm_host_become_password", password)):
        text, count = re.subn(r"(?m)^%s:.*$" % key, "%s: %s" % (key, value), text)
        if count != 1:
            raise ValueError("expected one %s line, found %d" % (key, count))
    return text


def set_inventory(text, user):
    text = re.sub(r"(?m)^([ \t]+)ansible_user: admin\n(?!\1%s)" % re.escape(PY),
                  lambda m: "%sansible_user: admin\n%s%s\n" % (m.group(1), m.group(1), PY), text)
    return re.sub(r"(?m)^([ \t]+)(ansible_user|vm_host_user): use_own_value$",
                  lambda m: "%s%s: %s" % (m.group(1), m.group(2), user), text)


def set_server(text):
    return text if PY in text else text.rstrip("\n") + "\n\n" + PY + "\n"


def main(root, user, password):
    ansible = Path(root) / "ansible"
    for creds in (ansible / "group_vars/all/creds.yml", ansible / "group_vars/vm_host/creds.yml"):
        creds.write_text(set_creds(creds.read_text(), user, password))
    inventory = ansible / "veos_vtb"
    inventory.write_text(set_inventory(inventory.read_text(), user))
    server = ansible / "host_vars/STR-ACS-VSERV-01.yml"
    server.write_text(set_server(server.read_text()))
    (ansible / "password.txt").write_text("abc\n")


if __name__ == "__main__":
    main(*sys.argv[1:4])
