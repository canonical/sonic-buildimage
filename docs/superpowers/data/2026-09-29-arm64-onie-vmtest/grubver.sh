set -u
W=~/vmtest/gv; mkdir -p $W; cd $W
cp ~/vmtest/grubk/kx/boot/vmlinuz-7.0.0-1002-sonic zboot.efi; cp ~/vmtest/grubk/Image image; cp ~/vmtest/grubk/Image.gz image.gz
cat > test.cfg <<'CFG'
set timeout=0
insmod part_gpt
insmod fat
insmod gzio
search --no-floppy --label --set=kd KDISK
source ($kd)/which.cfg
echo "TEST grub=${grub_version:-?} file=$kfile kd=$kd"
if linux ($kd)/$kfile console=ttyAMA0 panic=-1 ; then echo "TEST LOADED" ; boot ; else echo "TEST LOADFAIL" ; fi
CFG
echo "######## build standalone GRUB EFI per distro"
for img in debian:bullseye debian:bookworm debian:trixie debian:sid ubuntu:jammy ubuntu:noble ubuntu:resolute; do
  n=$(echo $img | tr ':' '-')
  docker run --rm -v $W:/w $img bash -c "export DEBIAN_FRONTEND=noninteractive; apt-get update -qq >/dev/null 2>&1; apt-get install -y -qq --no-install-recommends grub-efi-arm64-bin grub-common >/dev/null 2>&1 || { echo INSTALL_FAIL; exit 1; }; v=\$(dpkg-query -W -f '\${Version}' grub-efi-arm64-bin); grub-mkstandalone -O arm64-efi -o /w/$n.efi --modules='part_gpt fat gzio search search_label linux echo configfile' 'boot/grub/grub.cfg=/w/test.cfg' && echo \"$n \$v\"" &
done; wait
ls -la *.efi
mkfsdisk() { out=$1; efi=$2; kfile=$3
  rm -f $out.fat $out; truncate -s 200M $out.fat; mkfs.vfat -F 32 -n KDISK $out.fat >/dev/null
  mmd -i $out.fat ::EFI ::EFI/BOOT; mcopy -i $out.fat $efi ::EFI/BOOT/BOOTAA64.EFI
  mcopy -i $out.fat zboot.efi image image.gz ::; echo "set kfile=$kfile" > $out.which; mcopy -i $out.fat $out.which ::which.cfg
  truncate -s 202M $out; printf 'label: gpt\nstart=2048, size=409600, type=U, name=ESP\n' | sfdisk -q $out; dd if=$out.fat of=$out bs=1M seek=1 conv=notrunc status=none; rm -f $out.fat $out.which; }
run() { efi=$1; kfile=$2; n=${efi%.efi}-$kfile; mkfsdisk $n.img $efi $kfile
  cp ~/vmtest/firmware/AAVMF_VARS.fd $n.vars; rm -f $n.log
  timeout 60 qemu-system-aarch64 -machine virt,gic-version=3 -accel kvm -cpu host -smp 2 -m 2048 -net none \
    -drive if=pflash,format=raw,readonly=on,file=$HOME/vmtest/firmware/AAVMF_CODE.fd -drive if=pflash,format=raw,file=$n.vars \
    -drive file=$n.img,format=raw,if=none,id=d0 -device virtio-blk-pci,drive=d0,bootindex=0 \
    -display none -monitor none -serial file:$n.log >/dev/null 2>&1 &
  Q=$!; R=TIMEOUT
  for i in $(seq 1 55); do sleep 1
    if grep -aq 'Linux version' $n.log; then R=BOOTS; break; fi
    if grep -aq 'TEST LOADFAIL' $n.log; then R="REJECT: $(tr -d '\r' < $n.log | grep -ao 'error: [^.]*' | tail -1)"; break; fi
  done; kill $Q 2>/dev/null; wait $Q 2>/dev/null
  printf '%-22s %-10s %s\n' "${efi%.efi}" "$kfile" "$R"; rm -f $n.img $n.vars; }
echo "######## boot matrix"
for efi in *.efi; do for f in zboot.efi image image.gz; do run $efi $f & done; done; wait
echo "######## grub versions seen"; for l in *.log; do tr -d '\r' < $l | grep -aom1 'TEST grub=[^ ]* file=[^ ]*' ; done | sort | uniq
