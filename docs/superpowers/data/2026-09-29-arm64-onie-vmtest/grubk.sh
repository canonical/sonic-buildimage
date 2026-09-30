set -e
cd ~/vmtest; mkdir -p firmware grubk
cp fw/u2026.05-2ubuntu2/usr/share/AAVMF/AAVMF_CODE.no-secboot.fd firmware/AAVMF_CODE.fd
cp fw/u2026.05-2ubuntu2/usr/share/AAVMF/AAVMF_VARS.fd firmware/AAVMF_VARS.fd
sudo NEEDRESTART_SUSPEND=1 DEBIAN_FRONTEND=noninteractive apt-get install -y -qq zstd dosfstools mtools >/dev/null 2>&1
cd grubk
[ -s kernel.deb ] || curl -s -o kernel.deb https://ppa.launchpadcontent.net/canonical-kernel-team/bootstrap/ubuntu/pool/main/l/linux-sonic/linux-image-7.0.0-1002-sonic_7.0.0-1002.2_arm64.deb
rm -rf kx && mkdir kx && dpkg-deb -x kernel.deb kx; V=kx/boot/vmlinuz-7.0.0-1002-sonic
python3 ~/vmtest/unzboot.py $V Image >/dev/null; gzip -9 -c Image > Image.gz
rm -f kdisk.img; truncate -s 200M kdisk.img; mkfs.vfat -F 32 -n KDISK kdisk.img >/dev/null
mcopy -i kdisk.img $V ::zboot.efi; mcopy -i kdisk.img Image ::image; mcopy -i kdisk.img Image.gz ::image.gz
mdir -i kdisk.img -b ::
