#!/bin/bash
# Boot a DUT disk image once with a fresh NVRAM (UEFI must fall back to the removable path) and report how far it got
cd ~/imgwork
[ -f qemu.pid ] && kill $(cat qemu.pid) 2>/dev/null; rm -f qemu.pid t.log t.err
cp /srv/share/aavmf/usr/share/AAVMF/AAVMF_VARS.fd t-vars.fd
sg kvm -c "qemu-system-aarch64 -machine virt,gic-version=3 -accel kvm -cpu host -smp 4 -m 6144 -pidfile $PWD/qemu.pid -daemonize \
  -drive if=pflash,format=raw,readonly=on,file=/srv/share/aavmf/usr/share/AAVMF/AAVMF_CODE.no-secboot.fd -drive if=pflash,format=raw,file=t-vars.fd \
  -drive file=${1:-sonic-vs-arm64.img},if=virtio,format=qcow2,snapshot=on -netdev user,id=n0 -device e1000,netdev=n0 -device i6300esb \
  -display none -monitor none -serial file:$PWD/t.log" > t.err 2>&1
for i in $(seq 1 90); do sleep 5; grep -aq "sonic login:" t.log 2>/dev/null && break; done
echo "after $((i*5))s"; cat t.err
tr -d "\r" < t.log | strings | grep -aE "BdsDxe|Boot0|SONiC-OS|Linux version|login:|panic|error:|Shell>" | head -10
kill $(cat qemu.pid) 2>/dev/null; rm -f qemu.pid
