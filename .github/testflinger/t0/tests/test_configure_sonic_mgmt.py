import pytest

import configure_sonic_mgmt as cfg

CREDS = ("ptf_host_user: root\n\nvm_host_user: use_own_value\nvm_host_password: use_own_value\n"
         "vm_host_become_password: use_own_value\n\ncsonic_image: docker-sonic-vs\n")
VEOS = """all:
  children:
    lab:
      hosts:
        vlab-01:
          ansible_host: 10.250.0.101

          ansible_password: password
          ansible_user: admin
        vlab-02:
          ansible_user: admin
          ansible_python_interpreter: /usr/bin/python3
vm_host_1:
  hosts:
    STR-ACS-VSERV-01:
      ansible_host: 172.17.0.1
      ansible_user: use_own_value
      vm_host_user: use_own_value
"""
PY = "ansible_python_interpreter: /usr/bin/python3"


def test_set_creds_replaces_the_three_keys():
    out = cfg.set_creds(CREDS, "tb", "s3cret")
    assert "vm_host_user: tb\nvm_host_password: s3cret\nvm_host_become_password: s3cret\n" in out
    assert "use_own_value" not in out and "csonic_image: docker-sonic-vs" in out


def test_set_creds_fails_when_a_key_is_missing():
    with pytest.raises(ValueError):
        cfg.set_creds("vm_host_user: x\n", "tb", "p")


def test_set_inventory_adds_interpreter_once_and_sets_the_server_user():
    out = cfg.set_inventory(VEOS, "tb")
    assert "          ansible_user: admin\n          %s\n        vlab-02:" % PY in out
    assert out.count(PY) == 2
    assert "      ansible_user: tb\n      vm_host_user: tb\n" in out
    assert cfg.set_inventory(out, "tb") == out


def test_set_server_appends_interpreter_once():
    out = cfg.set_server("internal_mgmt_port: True\n")
    assert out == "internal_mgmt_port: True\n\n%s\n" % PY
    assert cfg.set_server(out) == out


def test_main_edits_the_tree(tmp_path):
    a = tmp_path / "ansible"
    (a / "group_vars" / "all").mkdir(parents=True)
    (a / "group_vars" / "vm_host").mkdir(parents=True)
    (a / "host_vars").mkdir()
    (a / "group_vars" / "all" / "creds.yml").write_text(CREDS)
    (a / "group_vars" / "vm_host" / "creds.yml").write_text(CREDS)
    (a / "veos_vtb").write_text(VEOS)
    (a / "host_vars" / "STR-ACS-VSERV-01.yml").write_text("internal_mgmt_port: True\n")
    cfg.main(str(tmp_path), "tb", "pw")
    assert (a / "password.txt").read_text() == "abc\n"
    assert "vm_host_user: tb" in (a / "group_vars" / "vm_host" / "creds.yml").read_text()
    assert PY in (a / "host_vars" / "STR-ACS-VSERV-01.yml").read_text()
