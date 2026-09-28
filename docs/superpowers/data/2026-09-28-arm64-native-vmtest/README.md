# arm64 vs boot-test tools

Used on an arm64 KVM host whose UEFI firmware does not boot under KVM, so the image is booted with a
direct kernel load instead of ONIE + GRUB.

- `vera-setup.sh` — host prerequisites (docker-ce, jinjanator, overlay/ip_tables, AppArmor gs override).
- `unzboot.py <vmlinuz> <out>` — unpack an EFI zboot kernel to a raw arm64 Image. Ubuntu's arm64 kernels are
  zstd zboot, and QEMU `-kernel` only unpacks gzip zboot.
- `mkraw.sh <sonic-vs.bin> <out.raw> <onie_platform>` — lay a disk out the way `installer/install.sh` does
  (GPT, ext4 labelled `SONiC-OS`, `image-<ver>/{fs.squashfs,boot,docker,platform}`, `machine.conf`) and write
  `<out>.Image`, `<out>.initrd`, `<out>.cmdline`. `INITRD_OVERRIDE=<file>` swaps the initrd. Unpacks with
  `tar --numeric-owner`, as the installer does; without it GNU tar remaps owners through the host's
  passwd and the database container's redis loses access to `/etc/redis/redis.conf`.
- `bootraw.sh <base> <serial-log>` — boot `<base>.raw` under KVM with the virt machine, GICv3, a management
  NIC forwarded to host port 3041 and four socket-backed front-panel NICs.
- `sercmd.py <socket> <timeout> <cmd>` — log in on the serial console (admin / YourPaSsWoRd) and run a
  command.
