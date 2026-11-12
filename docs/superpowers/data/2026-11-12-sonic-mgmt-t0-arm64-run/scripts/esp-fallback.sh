#!/bin/bash
# Point the UEFI removable-media path of an installed arm64 vs disk at SONiC's GRUB.
# libvirt gives each testbed DUT a blank NVRAM, so firmware boots \EFI\BOOT\BOOTAA64.EFI, which ONIE installed as its own GRUB.
# usage: esp-fallback.sh <disk.qcow2>
set -eu
sudo modprobe nbd max_part=16
sudo qemu-nbd -c /dev/nbd0 "$1"
sleep 2
sudo mkdir -p /mnt/esp
sudo mount /dev/nbd0p1 /mnt/esp
sudo cp /mnt/esp/EFI/SONiC-OS/grubaa64.efi /mnt/esp/EFI/BOOT/BOOTAA64.EFI
sudo cp /mnt/esp/EFI/debian/grub.cfg /mnt/esp/EFI/BOOT/grub.cfg
sync
sudo umount /mnt/esp
sudo qemu-nbd -d /dev/nbd0
