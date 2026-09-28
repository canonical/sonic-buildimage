#!/bin/bash
# usage: bootraw.sh <base> <serial-log>   (base = path without .raw)
B=$1 LOG=$2
exec qemu-system-aarch64 -machine virt,gic-version=3 -accel kvm -cpu host -smp 4 -m 8192 \
  -kernel $B.Image -initrd $B.initrd -append "$(cat $B.cmdline)" \
  -drive file=$B.raw,if=virtio,format=raw \
  -netdev user,id=m0,hostfwd=tcp::3041-:22 -device virtio-net-pci,netdev=m0 \
  -netdev socket,id=f1,listen=:31001 -device virtio-net-pci,netdev=f1 \
  -netdev socket,id=f2,listen=:31002 -device virtio-net-pci,netdev=f2 \
  -netdev socket,id=f3,listen=:31003 -device virtio-net-pci,netdev=f3 \
  -netdev socket,id=f4,listen=:31004 -device virtio-net-pci,netdev=f4 \
  -display none -monitor unix:$B.mon,server,nowait \
  -chardev socket,id=s0,path=$B.ser,server=on,wait=off,logfile=$LOG,logappend=on -serial chardev:s0
