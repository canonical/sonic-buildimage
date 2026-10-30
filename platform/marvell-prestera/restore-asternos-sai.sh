#!/bin/bash
# Rebuild the vendor mrvllibsai deb from an AsterNOS ONIE installer, for use
# with MRVL_SAI_ASSETS_BASE_URL. The installer is only read as data; nothing
# from it is executed.
#
# usage: restore-asternos-sai.sh <AsterNOS-*.bin> <output dir>
set -euo pipefail

pkg=mrvllibsai
bin=${1:-}
out=${2:-}
[ -f "$bin" ] && [ -d "$out" ] || { echo "usage: $0 <AsterNOS installer .bin> <output dir>" >&2; exit 2; }

die() { echo "error: $*" >&2; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Payload, checked against the sha1 the installer carries in its header
size=$(sed -n -e '/^exit_marker$/q' -e 's/^payload_image_size=\([0-9]*\)$/\1/p' "$bin")
sha1=$(sed -n -e '/^exit_marker$/q' -e 's/^payload_sha1=\([0-9a-f]*\)$/\1/p' "$bin")
[ -n "$size" ] && [ -n "$sha1" ] || die "no payload size or sha1 in $bin"
sed -e '1,/^exit_marker$/d' "$bin" | head -c "$size" > "$work/payload.tar"
echo "$sha1  $work/payload.tar" | sha1sum -c --quiet - || die "payload sha1 mismatch"

tar -xf "$work/payload.tar" -C "$work" installer/fs.zip
unzip -p "$work/installer/fs.zip" dockerfs.tar.gz > "$work/dockerfs"
rm -rf "$work/payload.tar" "$work/installer"

dockerfs() {
    if [ "$(head -c2 "$work/dockerfs" | od -An -tx1 | tr -d ' \n')" = "1f8b" ]; then
        gzip -dc "$work/dockerfs"
    else
        zstd -qdc "$work/dockerfs"
    fi
}

# The image layer that installed the package holds its dpkg record
dockerfs | tar -tv > "$work/listing"
layer=$(awk -v f="/var/lib/dpkg/info/$pkg.list" '{p=$NF} substr(p, length(p)-length(f)+1) == f {print substr(p, 1, length(p)-length(f))}' "$work/listing")
[ -n "$layer" ] && [ "$(echo "$layer" | wc -l)" -eq 1 ] || die "expected one layer with the $pkg dpkg record, found: ${layer:-none}"

info="$layer/var/lib/dpkg/info"
mkdir -p "$work/x"
dockerfs | tar -x -C "$work/x" "$info/$pkg.list" "$info/$pkg.md5sums" "$layer/var/lib/dpkg/status"
list="$work/x/$info/$pkg.list"
md5s="$work/x/$info/$pkg.md5sums"
awk -v p="$pkg" '$0 == "Package: " p {s=1} s && /^$/ {exit} s' "$work/x/$layer/var/lib/dpkg/status" > "$work/stanza"
[ -s "$work/stanza" ] || die "no $pkg entry in the layer's dpkg status"

# Regular files come from md5sums; directories and symlinks from the layer listing
awk -v l="$layer" '{print l "/" $2}' "$md5s" > "$work/want"
: > "$work/dirs"
while read -r path; do
    [ "$path" = "/." ] && continue
    entry=$(awk -v p="$layer$path" '$6 == p || $6 == p "/" {print substr($1, 1, 1); exit}' "$work/listing")
    case "$entry" in
        d) echo "$path" >> "$work/dirs" ;;
        l) echo "$layer$path" >> "$work/want" ;;
        -) grep -qxF "$layer$path" "$work/want" || die "$path is in $pkg.list but not in $pkg.md5sums" ;;
        *) die "$path is in $pkg.list but missing from the layer" ;;
    esac
done < "$list"
dockerfs | tar -x -C "$work/x" -T "$work/want"
(cd "$work/x/$layer" && md5sum -c --quiet "$md5s") || die "files differ from the $pkg md5sums record"

# Repack with the original control fields, minus the dpkg Status
root="$work/root"
mkdir -p "$root/DEBIAN"
while read -r d; do mkdir -p "$root$d"; done < "$work/dirs"
(cd "$work/x/$layer" && sed "s|^$layer/||" "$work/want" | tar -cf - -T -) | tar -xf - -C "$root"
grep -v '^Status:' "$work/stanza" > "$root/DEBIAN/control"
cp "$md5s" "$root/DEBIAN/md5sums"

field() { sed -n "s/^$1: //p" "$root/DEBIAN/control"; }
deb="$out/${pkg}_$(field Version)_$(field Architecture).deb"
dpkg-deb --root-owner-group -Zxz -b "$root" "$deb" > /dev/null

# The result must list exactly what the vendor's dpkg recorded
diff <(sed 's|^/\.$|/|' "$list" | sort) \
     <(dpkg-deb -c "$deb" | awk '{print $6}' | sed -e 's|^\./|/|' -e 's|/$||' -e 's|^$|/|' | sort) > /dev/null ||
    die "$deb does not match $pkg.list"
echo "$deb"
