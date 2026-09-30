#!/bin/bash
# Print the size figures compared in the report for one variant.
# Usage: measure.sh NAME IMAGE.bin DISK (installed qcow2, or .img.gz of one; "-" for .bin figures only)
set -euo pipefail
. "$(dirname "$(realpath "$0")")/attach.sh"
NAME=$1 BIN=$(realpath "$2") DISK=$(realpath -m "$3")
W=$(mktemp -d -p "$(dirname "$BIN")" measure.XXXXXX)
DEV=
cleanup() { mountpoint -q "$W/m" && sudo umount "$W/m"; [ -n "$DEV" ] && detach_disk; rm -rf "$W"; }
trap cleanup EXIT
MB() { echo "scale=1; $1 / 1000000" | bc; }

sed -e '1,/^exit_marker$/d' "$BIN" | tar xf - -C "$W" installer/fs.zip
dfs=$(unzip -l "$W/installer/fs.zip" dockerfs.tar.gz | awk 'NR==4 {print $1}')
sq=$(unzip -l "$W/installer/fs.zip" fs.squashfs | awk 'NR==4 {print $1}')
binfig="dockerfs.tar.gz $(MB "$dfs") MB | fs.squashfs $(MB "$sq") MB | .bin $(MB "$(stat -c %s "$BIN")") MB"
[ "$3" = - ] && { echo "$NAME: $binfig"; exit 0; }
case $DISK in
*.gz) gz=$(stat -c %s "$DISK"); pigz -dc "$DISK" > "$W/d.img"; DISK=$W/d.img ;;
*)    gz=$(pigz -c "$DISK" | wc -c) ;;
esac
attach_disk "$DISK" ro
mkdir "$W/m"
sudo mount -o ro,noload "$(sonic_os_part)" "$W/m"
D=$(echo "$W"/m/image-*/docker)
part=$(df --block-size=1M "$W/m" | awk 'NR==2 {print $3}')
ddu=$(sudo du -s --block-size=1M "$D" | cut -f1)
links=$(sudo find "$D/overlay2" -type f -links +1 | wc -l)
echo "$NAME: $binfig | docker dir $ddu MB | SONiC-OS used $part MB | img.gz $(MB "$gz") MB | files with nlink>1: $links | $(basename "$(dirname "$D")")"
