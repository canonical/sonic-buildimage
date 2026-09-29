# Sourced helper: attach_disk FILE [ro] sets DEV to a block device with partitions (loop for raw, nbd for qcow2); detach_disk undoes it.
attach_disk() {
    local fmt ro=${2:-}
    fmt=$(qemu-img info --output=json "$1" | python3 -c 'import json,sys; print(json.load(sys.stdin)["format"])')
    if [ "$fmt" = raw ]; then
        DEV=$(sudo losetup -f -P ${ro:+-r} --show "$1")
    else
        sudo modprobe nbd max_part=16
        for DEV in /dev/nbd{0..15}; do [ -e "/sys/block/${DEV#/dev/}/pid" ] || break; done
        sudo qemu-nbd ${ro:+--read-only} -f "$fmt" -c "$DEV" "$1"
        for _ in $(seq 50); do ls "$DEV"p* >/dev/null 2>&1 && break; sleep 0.2; done
    fi
}
detach_disk() {
    case $DEV in
    /dev/loop*) sudo losetup -d "$DEV" ;;
    /dev/nbd*)  sudo qemu-nbd -d "$DEV" >/dev/null ;;
    esac
    DEV=
}
sonic_os_part() { sudo blkid -o device -t LABEL=SONiC-OS "$DEV"p*; }
