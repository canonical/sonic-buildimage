#!/bin/bash
# On papat: privileged LXD system containers, one per testbed; DUT VMs use the host's /dev/kvm (no nesting)
# usage: launch-arm.sh <first> <last>    e.g. launch-arm.sh 1 12
set -eu
lxc profile show tb >/dev/null 2>&1 || lxc profile create tb
lxc profile edit tb <<'EOP'
description: sonic-mgmt vms-kvm testbed host
config:
  security.privileged: "true"
  security.nesting: "true"
  raw.lxc: |-
    lxc.apparmor.profile=unconfined
    lxc.cgroup2.devices.allow=a
    lxc.mount.auto=proc:rw sys:rw cgroup:rw
    lxc.cap.drop=
devices:
  kvm:
    type: unix-char
    source: /dev/kvm
    path: /dev/kvm
  tun:
    type: unix-char
    source: /dev/net/tun
    path: /dev/net/tun
  vhost-net:
    type: unix-char
    source: /dev/vhost-net
    path: /dev/vhost-net
  modules:
    type: disk
    source: /usr/lib/modules
    path: /usr/lib/modules
    readonly: "true"
  share:
    type: disk
    source: /srv/share
    path: /srv/share
    readonly: "true"
EOP
for n in $(seq $1 $2); do
    i=$(printf %02d $n)
    lxc info tb$i >/dev/null 2>&1 || lxc launch -q ubuntu:26.04 tb$i -p default -p tb
done
lxc list -c ns4 | head -40
