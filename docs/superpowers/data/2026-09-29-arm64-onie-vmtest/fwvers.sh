cd ~/vmtest; mkdir -p fw && cd fw
U=http://archive.ubuntu.com/ubuntu/pool/main/e/edk2; D=http://deb.debian.org/debian/pool/main/e/edk2
for x in "u2025.11-3ubuntu7 $U/qemu-efi-aarch64_2025.11-3ubuntu7_all.deb" "u2025.02-8ubuntu3.2 $U/qemu-efi-aarch64_2025.02-8ubuntu3.2_all.deb" "u2024.02-2ubuntu0.9 $U/qemu-efi-aarch64_2024.02-2ubuntu0.9_all.deb" "u2026.05-2ubuntu2 $U/qemu-efi-aarch64_2026.05-2ubuntu2_all.deb" "d2025.02-8+deb13u1 $D/qemu-efi-aarch64_2025.02-8+deb13u1_all.deb" "d2026.08+ds-2 $D/qemu-efi-aarch64_2026.08+ds-2_all.deb"; do
  set -- $x; n=$1; url=$2
  [ -d $n ] || { curl -s -o $n.deb $url && mkdir $n && dpkg-deb -x $n.deb $n; }
done
cd ~/vmtest
run() { name=$1; code=$2
  if [ -z "$code" ]; then printf '%-24s %s\n' "$name" "no AAVMF_CODE found"; return; fi
  cp /usr/share/AAVMF/AAVMF_VARS.fd v-$name.fd; truncate -s $(stat -c %s $code) v-$name.fd 2>/dev/null
  vars=$(dirname $code)/AAVMF_VARS.fd; [ -f $vars ] && cp $vars v-$name.fd
  rm -f f-$name.log
  timeout 90 qemu-system-aarch64 -machine virt,gic-version=3 -accel kvm -cpu host -m 4096 -smp 2 \
    -drive if=pflash,format=raw,readonly=on,file=$code -drive if=pflash,format=raw,file=v-$name.fd \
    -device virtio-scsi-pci -drive file=onie.iso,media=cdrom,if=none,id=cd0,readonly=on -device scsi-cd,drive=cd0 \
    -display none -monitor none -serial file:f-$name.log >/dev/null 2>&1 &
  Q=$!; R=TIMEOUT
  for i in $(seq 1 85); do sleep 1
    grep -aq 'Synchronous Exception' f-$name.log && { R="FAIL($(grep -ao 'Exception at 0x[0-9A-F]*' f-$name.log | head -1))"; break; }
    grep -aqE 'Please press Enter to activate|ONIE: Starting ONIE' f-$name.log && { R=PASS; break; }
  done; kill $Q 2>/dev/null; wait $Q 2>/dev/null
  printf '%-24s %-42s %3ss  %s\n' "$name" "$R" "$i" "$(tr -d '\r' < f-$name.log | grep -aom1 'UEFI firmware (version [^ ]*')"; }
for d in fw/*/; do n=$(basename $d); c=$(find $d -name 'AAVMF_CODE.no-secboot.fd' -o -name 'AAVMF_CODE.fd' -size +1M | head -1); [ -z "$c" ] && c=$(find $d -name 'QEMU_EFI.fd' | head -1); run "$n" "$c"; done
