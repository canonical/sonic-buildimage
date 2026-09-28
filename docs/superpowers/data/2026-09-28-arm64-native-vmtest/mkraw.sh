#!/bin/bash
# usage: mkraw.sh <sonic-vs.bin> <out.raw> <onie_platform>
# Lays the image out exactly as installer/install.sh does, then extracts a raw kernel for qemu -kernel.
set -euo pipefail
BIN=$1 OUT=$2 PLAT=$3
W=$(mktemp -d /var/tmp/mkraw.XXXX)
sed -e '1,/^exit_marker$/d' "$BIN" | tar xf - -C "$W"
INST=$W/installer
VER=$(grep -m1 '^image_version=' $INST/install.sh | cut -d'"' -f2)
echo "image_version=$VER"
rm -f "$OUT"; truncate -s 24G "$OUT"
printf 'label: gpt\ntype=linux, name=SONiC-OS\n' | sfdisk -q "$OUT"
LOOP=$(sudo losetup -fP --show "$OUT")
sudo mkfs.ext4 -q -L SONiC-OS ${LOOP}p1
UUID=$(sudo blkid -s UUID -o value ${LOOP}p1)
M=$W/mnt; mkdir -p $M; sudo mount ${LOOP}p1 $M
trap 'sudo umount $M 2>/dev/null; sudo losetup -d $LOOP 2>/dev/null' EXIT
D=$M/image-$VER; sudo mkdir -p $D/docker $D/platform
sudo unzip -q -o $INST/fs.zip -x platform.tar.gz dockerfs.tar.gz -d $D
sudo sh -c "unzip -op $INST/fs.zip dockerfs.tar.gz | tar xz --numeric-owner -f - -C $D/docker"
sudo sh -c "unzip -op $INST/fs.zip platform.tar.gz | tar xz --numeric-owner -f - -C $D/platform"
printf 'onie_platform=%s\nonie_arch=arm64\nonie_machine=qemu_armv8a\nonie_switch_asic=qemu\n' "$PLAT" | sudo tee $M/machine.conf >/dev/null
[ -n "${INITRD_OVERRIDE:-}" ] && echo "initrd override: $INITRD_OVERRIDE"
K=$(sudo sh -c "ls $D/boot/vmlinuz-*" | head -1); I=$(sudo sh -c "ls $D/boot/initrd.img-*" | head -1)
sudo cp $K $W/vmlinuz; sudo cp ${INITRD_OVERRIDE:-$I} ${OUT%.raw}.initrd; sudo chown $(id -u) $W/vmlinuz ${OUT%.raw}.initrd
python3 $(dirname $0)/unzboot.py $W/vmlinuz ${OUT%.raw}.Image
echo "root=UUID=$UUID rw console=tty0 console=ttyAMA0,115200n8 net.ifnames=0 biosdevname=0 loop=image-$VER/fs.squashfs loopfstype=squashfs apparmor=1 security=apparmor varlog_size=4096 usbcore.autosuspend=-1" > ${OUT%.raw}.cmdline
sudo du -sh $D; ls $D; ls $D/boot
sudo umount $M; sudo losetup -d $LOOP; trap - EXIT; sudo rm -rf "$W"
cat ${OUT%.raw}.cmdline
