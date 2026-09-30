cd ~/vmtest/grubk
one() { name=$1; file=$2
  cp ../firmware/AAVMF_VARS.fd v-$name.fd; rm -f $name.ser $name.log
  qemu-system-aarch64 -machine virt,gic-version=3 -accel kvm -cpu host -smp 2 -m 4096 -net none \
    -drive if=pflash,format=raw,readonly=on,file=../firmware/AAVMF_CODE.fd -drive if=pflash,format=raw,file=v-$name.fd \
    -device virtio-scsi-pci -drive file=../onie.iso,media=cdrom,if=none,id=cd0,readonly=on -device scsi-cd,drive=cd0,bootindex=0 \
    -drive file=kdisk.img,format=raw,if=none,id=kd0,readonly=on -device virtio-blk-pci,drive=kd0,bootindex=1 \
    -display none -monitor none -chardev socket,id=s0,path=$PWD/$name.ser,server=on,wait=off,logfile=$PWD/$name.log -serial chardev:s0 &
  Q=$!
  echo "================ $name ($file)"
  timeout 200 python3 ../grubdrive.py $PWD/$name.ser "ls" "insmod fat" "search --no-floppy --label --set=kd KDISK" "echo kd=\$kd" "linux (\$kd)/$file console=ttyAMA0 panic=-1" "boot"
  kill $Q 2>/dev/null; wait $Q 2>/dev/null
}
one zboot zboot.efi
one raw image
one gz image.gz
