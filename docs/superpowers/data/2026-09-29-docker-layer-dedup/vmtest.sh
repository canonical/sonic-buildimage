#!/bin/bash
# Boot-test helper for installed sonic-vs disks (qcow2 or raw; changed in place).
#   vmtest.sh inject DISK SCRIPT        install SCRIPT as a one-shot unit in the image's rw overlay
#   vmtest.sh boot DISK CONSOLE [SECS]  boot DISK under KVM (33 NICs, as the vs testbed expects) until the guest powers off
#   vmtest.sh fetch DISK DIR            copy /host/hlcheck*.txt out of DISK into DIR
set -euo pipefail
HERE=$(dirname "$(realpath "$0")")
. "$HERE/attach.sh"

with_host() {  # with_host DISK CMD...: run CMD with $M set to the mounted SONiC-OS partition
    attach_disk "$1"; shift
    M=$(mktemp -d)
    sudo mount "$(sonic_os_part)" "$M"
    local rc=0; "$@" || rc=$?
    sudo umount "$M"; detach_disk; rmdir "$M"
    return $rc
}

do_inject() {
    # rw/ does not exist before first boot, so glob only the image directory
    local img; img=$(echo "$M"/image-*)
    [ -d "$img" ] || { echo "no image-* directory under $M" >&2; return 1; }
    local rw=$img/rw
    sudo install -D -m 755 "$1" "$rw/usr/local/bin/hlcheck.sh"
    sudo install -D -m 644 "$HERE/hlcheck.service" "$rw/etc/systemd/system/hlcheck.service"
    sudo mkdir -p "$rw/etc/systemd/system/multi-user.target.wants"
    sudo ln -sf /etc/systemd/system/hlcheck.service "$rw/etc/systemd/system/multi-user.target.wants/hlcheck.service"
    echo "injected $(basename "$1") into $(basename "$img")"
}

do_fetch() {
    sudo sh -c "cp $M/hlcheck*.txt '$1'/ && chown $(id -u):$(id -g) '$1'/hlcheck*.txt"
    ls -l "$1"/hlcheck*.txt
}

case $1 in
inject)
    with_host "$2" do_inject "$(realpath "$3")" ;;
boot)
    fmt=$(qemu-img info --output=json "$2" | python3 -c 'import json,sys; print(json.load(sys.stdin)["format"])')
    args=(-enable-kvm -cpu host -m 6144 -smp 4 -drive "file=$2,if=virtio,format=$fmt" -display none -monitor none -vga none
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
