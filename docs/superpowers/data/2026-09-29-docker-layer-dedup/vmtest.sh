#!/bin/bash
# Boot-test helper for installed sonic-vs disks.
#   vmtest.sh inject DISK RAW SCRIPT  convert DISK (qcow2) to RAW unless RAW exists; install SCRIPT as a one-shot unit in the image's rw overlay
#   vmtest.sh boot RAW CONSOLE [SECS] boot RAW under KVM (33 NICs, as the vs testbed expects) until the guest powers off
#   vmtest.sh fetch RAW DIR           copy /host/hlcheck*.txt out of RAW into DIR
set -euo pipefail
HERE=$(dirname "$(realpath "$0")")

with_host() {  # with_host RAW CMD...: run CMD with $M set to the mounted SONiC-OS partition
    local raw=$1; shift
    local L; L=$(sudo losetup -f -P --show "$raw")
    M=$(mktemp -d)
    sudo mount "$(sudo blkid -o device -t LABEL=SONiC-OS "$L"p*)" "$M"
    "$@" || true
    sudo umount "$M"; sudo losetup -d "$L"; rmdir "$M"
}

do_inject() {
    local rw; rw=$(echo "$M"/image-*/rw)
    sudo install -D -m 755 "$1" "$rw/usr/local/bin/hlcheck.sh"
    sudo install -D -m 644 "$HERE/hlcheck.service" "$rw/etc/systemd/system/hlcheck.service"
    sudo mkdir -p "$rw/etc/systemd/system/multi-user.target.wants"
    sudo ln -sf /etc/systemd/system/hlcheck.service "$rw/etc/systemd/system/multi-user.target.wants/hlcheck.service"
    echo "injected $(basename "$1") into $(basename "$(dirname "$rw")")"
}

do_fetch() {
    sudo sh -c "cp $M/hlcheck*.txt '$1'/ && chown $(id -u):$(id -g) '$1'/hlcheck*.txt"
    ls -l "$1"/hlcheck*.txt
}

case $1 in
inject)
    [ -e "$3" ] || qemu-img convert -O raw "$2" "$3"
    with_host "$3" do_inject "$(realpath "$4")" ;;
boot)
    args=(-enable-kvm -cpu host -m 6144 -smp 4 -drive "file=$2,if=virtio,format=raw" -display none -monitor none -vga none
          -serial "file:$3" -device pci-bridge,id=br1,chassis_nr=1)
    for i in $(seq 0 32); do
        # i440fx has too few slots for 33 NICs; put the upper half behind a bridge
        b=""; [ "$i" -ge 16 ] && b=",bus=br1"
        net="user,id=n$i,restrict=on"; [ "$i" -eq 0 ] && net="user,id=n0"
        args+=(-netdev "$net" -device "e1000,netdev=n$i$b")
    done
    timeout "${4:-3600}" qemu-system-x86_64 "${args[@]}"; echo "$(basename "$2") qemu exit=$? $(date +%T)" ;;
fetch)
    mkdir -p "$3"
    with_host "$2" do_fetch "$(realpath "$3")" ;;
*) echo "usage: see header" >&2; exit 2 ;;
esac
