#!/bin/bash
# Re-compress dockerfs inside a sonic-*.bin with pigz, keeping the tar stream byte for byte (undoes BUILD_REDUCE_IMAGE_SIZE's pzstd only).
# Usage: recompress-bin.sh IN.bin OUT.bin SLAVE_IMAGE
set -euo pipefail
IN=$(realpath "$1"); OUT=$(realpath -m "$2"); SLAVE=$3
W=$(mktemp -d -p "$(dirname "$OUT")" recompress.XXXXXX)
trap 'rm -rf "$W"' EXIT
cd "$W"

sed -n '1,/^exit_marker$/p' "$IN" > header
mkdir payload
sed -e '1,/^exit_marker$/d' "$IN" | tar xf - -C payload
unzip -p payload/installer/fs.zip dockerfs.tar.gz > dockerfs.orig
case $(head -c 4 dockerfs.orig | od -An -tx1 | tr -d ' ') in
1f8b*)            echo "already gzip" >&2; exit 1 ;;
28b52ffd|502a4d18) zstd -dc dockerfs.orig | pigz -c > dockerfs.tar.gz ;;
*)                echo "unknown dockerfs compression" >&2; exit 1 ;;
esac
docker run --rm -u "$(id -u):$(id -g)" -v "$W":/w -w /w "$SLAVE" zip -n .squashfs:.gz payload/installer/fs.zip dockerfs.tar.gz

tar -C payload -cf payload.tar installer
sed -i -e "s/^payload_image_size=.*/payload_image_size=$(stat -c %s payload.tar)/" \
       -e "s/^payload_sha1=.*/payload_sha1=$(sha1sum payload.tar | cut -d' ' -f1)/" header
cat header payload.tar > "$OUT"
chmod +x "$OUT"
echo "dockerfs: $(stat -c %s dockerfs.orig) -> $(stat -c %s dockerfs.tar.gz) bytes; tar sha256 $(zstd -dc dockerfs.orig | sha256sum | cut -c1-16) -> $(pigz -dc dockerfs.tar.gz | sha256sum | cut -c1-16)"
echo "$(basename "$OUT"): $(stat -c %s "$IN") -> $(stat -c %s "$OUT") bytes"
