#!/bin/bash -e

mkdir -p /etc/swss/config.d/

sonic-cfggen -m /etc/sonic/minigraph.xml -y /etc/sonic/sonic_version.yml -t /usr/share/sonic/templates/ipinip.json.j2 > /etc/swss/config.d/ipinip.json
sonic-cfggen -m /etc/sonic/minigraph.xml -y /etc/sonic/sonic_version.yml -t /usr/share/sonic/templates/mirror.json.j2 > /etc/swss/config.d/mirror.json
