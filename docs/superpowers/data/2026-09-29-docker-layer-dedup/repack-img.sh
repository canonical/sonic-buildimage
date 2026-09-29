#!/bin/bash
# Hardlink identical docker-layer files in place on an installed sonic-vs disk (qcow2, gzipped) and write a new img.gz.
# Usage: repack-img.sh IN.img.gz OUT.img.gz [hardlink options, e.g. -t]; NOHL=1 skips hardlink (same-pipeline baseline).
set -euo pipefail
IN=$(realpath "$1"); OUT=$(realpath -m "$2"); shift 2
W=$(mktemp -d -p "$(dirname "$OUT")" repack.XXXXXX)
LOOP=
cleanup() { mountpoint -q "$W/mnt" && sudo umount "$W/mnt"; [ -n "$LOOP" ] && sudo losetup -d "$LOOP"; rm -rf "$W"; }
trap cleanup EXIT

pigz -dc "$IN" > "$W/in.qcow2"
qemu-img convert -O raw "$W/in.qcow2" "$W/disk.raw"
rm "$W/in.qcow2"
LOOP=$(sudo losetup -f -P --show "$W/disk.raw")
PART=$(sudo blkid -o device -t LABEL=SONiC-OS "$LOOP"p*)
mkdir "$W/mnt"
sudo mount "$PART" "$W/mnt"
[ -n "${NOHL:-}" ] || sudo bash -c "hardlink --respect-xattrs $* $W/mnt/image-*/docker/overlay2/*/diff"
sudo du -s --block-size=1M "$W"/mnt/image-*/docker | cut -f1 | sed 's/^/docker dir MB: /'
# Release freed blocks as holes so the qcow2 conversion drops them
sudo fstrim "$W/mnt"
sudo umount "$W/mnt"
sudo losetup -d "$LOOP"; LOOP=
qemu-img convert -O qcow2 "$W/disk.raw" "$W/out.qcow2"
pigz -c "$W/out.qcow2" > "$OUT"
echo "$(basename "$OUT"): $(stat -c %s "$OUT") bytes"
