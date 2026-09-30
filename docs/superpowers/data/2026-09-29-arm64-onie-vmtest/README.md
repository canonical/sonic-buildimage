# arm64 vs ONIE install tests (podler, 2026-09-29)

Scripts behind §4 of the [native build report](../../2026-09-28-resolute-arm64-native-build-report-en.md).
They ran on an arm64 KVM host with QEMU 10.2.1, in `~/vmtest`, which held:

- `onie.iso`: `onie-recovery-arm64-qemu_armv8a-r0.iso` from
  `https://packages.trafficmanager.net/public/onie/` (ONIE `master-03031019`, GRUB 2.04);
- `unzboot.py` from [../2026-09-28-arm64-native-vmtest/](../2026-09-28-arm64-native-vmtest/);
- `firmware/AAVMF_CODE.fd` and `firmware/AAVMF_VARS.fd`, copied by `grubk.sh` from the
  qemu-efi-aarch64 2026.05-2ubuntu2 package that `fwvers.sh` unpacks. Resolute's own edk2 2025.11 does not
  start under KVM.

The reservation ended before the files were copied off. The scripts here were recovered from the session
record exactly as they ran, including the later edits to `grubrun.sh` and `grubdrive.py`. None was changed
afterwards, so absolute paths such as `/tmp/gvfuncs.sh` are as used on the host.

| Script | What it does |
|---|---|
| `fwvers.sh` | Download six qemu-efi-aarch64 builds (Ubuntu and Debian), unpack them with `dpkg-deb -x`, and boot the ONIE ISO under KVM with each. PASS means ONIE starts. |
| `tcgsweep.sh` | Boot the resolute firmware and the 2026.05 firmware under TCG with every named CPU model. |
| `grubk.sh` | Set up the firmware, fetch the linux-sonic 7.0.0-1002 arm64 deb, write `Image` and `Image.gz` next to the shipped zboot `vmlinuz`, and put all three on a FAT disk labelled `KDISK`. |
| `grubrun.sh` + `grubdrive.py` | Boot the ONIE ISO, drop to ONIE's own GRUB prompt, and `linux`/`boot` each kernel form from `KDISK`. |
| `grubver.sh` | Build a standalone arm64 GRUB EFI from each distro's `grub-efi-arm64-bin` (bookworm, trixie, sid, jammy, noble, resolute; bullseye would not install) and boot each kernel form with it. |
| `grubvanilla.sh` + `gvfuncs.sh` | The same with upstream GRUB 2.06 and 2.12 built from source. `gvfuncs.sh` is the disk and boot helper cut out of `grubver.sh`. |
| `onie-install-test.py` | End to end: ONIE embeds itself from the ISO onto a blank disk, boots from disk, runs `onie-nos-install` over HTTP, and reboots into SONiC through the GRUB the installer wrote. It then collects the state over ssh. Usage is in the docstring. |
| `kexec-test.sh` | Inside the installed SONiC: `kexec -l` with `-a`, `-s` and `-c` for the shipped gzip Image, the zboot file and a raw Image, then a real `kexec -e` the way fast-reboot loads the kernel. The ssh call that starts `kexec -e` does not detach, so the script stalls after the jump. The new boot was confirmed by hand (new boot id, `SONIC_BOOT_TYPE=kexec-test` in `/proc/cmdline`), and its phase 3 was run again with `kdump-test.sh`. |
| `kdump-test.sh` | `config kdump enable`, reboot, check the crash kernel is loaded, crash with sysrq-c, and list `/var/crash`. |

`onie-e2e-output.txt` is the output of `onie-install-test.py` for the branch without the one-line
`minigraph.py` change. The install of the final branch head printed the same values.
