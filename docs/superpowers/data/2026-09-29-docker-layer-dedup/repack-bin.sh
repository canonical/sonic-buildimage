#!/bin/bash
# Repack a sonic-*.bin so identical files across docker layers are hardlinked.
# Usage: repack-bin.sh IN.bin OUT.bin SLAVE_IMAGE [hardlink options, e.g. -t]
# SLAVE_IMAGE is any image with `zip` (the sonic-slave-resolute image works); the host needs pigz and util-linux hardlink.
set -euo pipefail
IN=$(realpath "$1"); OUT=$(realpath -m "$2"); SLAVE=$3; shift 3
W=$(mktemp -d -p "$(dirname "$OUT")" repack.XXXXXX)
trap 'sudo rm -rf "$W"' EXIT
cd "$W"

# sharch layout: shell header ending in "exit_marker", then an uncompressed tar of installer/
sed -n '1,/^exit_marker$/p' "$IN" > header
mkdir payload dfs
sed -e '1,/^exit_marker$/d' "$IN" | tar xf - -C payload
unzip -p payload/installer/fs.zip dockerfs.tar.gz > dockerfs.orig.tar.gz

sudo tar xzf dockerfs.orig.tar.gz --numeric-owner -C dfs
sudo bash -c "hardlink --respect-xattrs $* $W/dfs/overlay2/*/diff"
sudo tar -I pigz -cf dockerfs.tar.gz -C dfs .
docker run --rm -u "$(id -u):$(id -g)" -v "$W":/w -w /w "$SLAVE" zip -n .squashfs:.gz payload/installer/fs.zip dockerfs.tar.gz

tar -C payload -cf payload.tar installer
sed -i -e "s/^payload_image_size=.*/payload_image_size=$(stat -c %s payload.tar)/" \
       -e "s/^payload_sha1=.*/payload_sha1=$(sha1sum payload.tar | cut -d' ' -f1)/" header
cat header payload.tar > "$OUT"
chmod +x "$OUT"
echo "dockerfs.tar.gz: $(stat -c %s dockerfs.orig.tar.gz) -> $(stat -c %s dockerfs.tar.gz) bytes"
echo "$(basename "$OUT"): $(stat -c %s "$IN") -> $(stat -c %s "$OUT") bytes"
