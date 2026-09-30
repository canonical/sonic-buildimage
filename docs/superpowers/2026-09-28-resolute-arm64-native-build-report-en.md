# arm64 vs on 202605_resolute: native build, ONIE install and boot report

- Dates: 2026-09-28 (build and direct kernel boot on `vera`), 2026-09-29 (rebuild, ONIE install, kexec and kdump on `podler`)
- Baseline: `canonical/202605_resolute` at `d2f9ae8502`, still its tip on 2026-09-29
- Changes: local branch `feat/resolute-arm64-vs`, nine GPG-signed commits (15 files, +56/−6), not pushed; worktree `/home/sheldon-qi/sbi-arm64-native`
- Hosts, both TOR3 lab machines on testflinger reservations that have since ended:
  - `vera` (10.241.5.36): Cavium ThunderX-88XX, 48 cores at one thread per core, 62 GB RAM, 219 GB SSD, Ubuntu 26.04.1 arm64, kernel 7.0.0-34-generic, docker-ce 29.8.1.
  - `podler` (10.241.24.14): single-socket AmpereOne reference platform, 192 Ampere-1a cores, 251 GB RAM, 879 GB NVMe, Ubuntu 26.04 arm64, docker-ce 29.8.1, QEMU 10.2.1.
- Follows: [cross-build probe report](2026-09-23-resolute-arm64-cross-probe-report-en.md)
- This is the English version and the single source of truth; the Chinese version is `-zh.md`

## 0. Bottom line

**A native arm64 build of `target/sonic-vs.bin` works, and the image installs through SONiC's own arm64 ONIE and runs.** Starting from the baseline it needs nine small commits, all in the superproject (§1):

- On podler it builds from a fresh clone in about an hour: 25 minutes for the slave image and 33 for packages, containers and the installer (§2).
- `onie-nos-install` from SONiC's published arm64 ONIE recovery ISO installs it under KVM, and ONIE's own GRUB 2.04 boots it. `show version` reports `Platform: arm64-qemu_armv8a-r0` and `HwSKU: Force10-S6000` (§4).
- 14 containers come up. 32 ports reach APPL_DB, ASIC_DB holds 33 PORT and 69 ROUTE_ENTRY objects, and BGP runs with 32 configured peers.
- `kexec`, loaded the way fast-reboot and warm-reboot load it, boots the shipped kernel, and kdump captures a vmcore (§4.6).
- The only failed units are `watchdog-control` and `system-health`. Both fail on a missing file that only sonic-mgmt's testbed setup writes, in code that is the same on x86 vs (§6).

None of the commits changes what an amd64 build produces, except that `sonic-platform-vs` is now named `_all.deb`.

What is left:

- Three checks in submodules recognise vs only by its x86 platform name, so they miss arm64 vs (§7.1). One shows on every boot: snmp logs an ERR line and the chassis serial number is missing. They are not changed here, because each needs a submodule commit.
- Two x86-only components are left out of the arm64 image: the pmon SSD vendor tools and docker-dash-engine. Neither costs any function (§5).
- To run UEFI under KVM on an arm64 host, the test host needs a newer edk2 than resolute ships (§4.1). This concerns the test host only; the image does not ship edk2.

The cross probe of 2026-09-23 predicted the build result. It needed eight deviations and still stalled at the Docker layer, with only `docker-base` and `docker-dash-engine` built. The native build hit no code failure beyond the ones fixed here.

## 1. Changes

All nine are in `feat/resolute-arm64-vs`, one commit each.

| Commit | Change | Failure it removes |
|---|---|---|
| `7c469ec934` | `sonic-slave-resolute/Dockerfile.j2`: install `gcc-multilib` only on amd64 | Resolute publishes no arm64 `gcc-multilib`, so the slave image stops at that line |
| `f989cb441d` | `platform/vs/rules.mk`: `override TARGET_BOOTLOADER = grub` | `Makefile.work` defaults non-amd64 to uboot, and `build_debian.sh` then needs a `platform/vs/sonic_fit.its` that does not exist |
| `96f264e2b9` | `sonic-platform-vs`: `Architecture: all`, `_all.deb` | The pure-Python package was declared amd64, so `dpkg-buildpackage` produced nothing |
| `13d5623f1c` | `docker-dash-engine`: amd64 only (make rule plus unit file copy) | Its base `p4lang/behavioral-model:latest` exists only for amd64 (§5.2) |
| `2c04ece9e9` | pmon: ship `ssd_tools` and their host wrappers only on amd64 | The prebuilt vendor binaries are x86-64 and i386 (§5.1) |
| `8858c03ecd` | `build_debian.sh`: on non-amd64, install `initramfs-tools busybox-initramfs` | The arm64 initrd had no busybox and could not mount its root (§3) |
| `6de838da5e` | `build_debian.sh`: for vs on arm64, store the kernel as a gzip'd plain Image | ONIE's GRUB 2.04 rejects the EFI zboot kernel (§4.2) |
| `624636d7d3` | arm64 vs builds treat `arm64-qemu_armv8a-r0` as a vs platform | The platform name ONIE reports; without it the image has no HwSKU and swss/syncd stop (§4.3) |
| `d3b6c4c08b` | `platform/vs/platform_arm64.conf`: GRUB and kernel console on the PL011 UART | The installer defaults to an x86 8250 serial port (§4.4) |

Together they change 15 files by +56/−6 lines, with no submodule commit and no gitlink bump. The only new file is `platform_arm64.conf` (6 lines). The two largest pieces are `build_debian.sh` (+17: 3 for initramfs, 14 for the kernel conversion) and the platform alias (6 files, +18/−3). Every change is gated on `CONFIGURED_ARCH` or `CONFIGURED_PLATFORM`, except the `sonic-platform-vs` package name, and nothing else in the tree refers to the old name.

The first five changes came from a static scan that ran 06:08–07:34 UTC on 2026-09-28, during the slave build and before the package build. It was given the first four as already known (from the cross probe's §6), confirmed them, and found the fifth. It ran eight dimension finders over the vs arm64 build closure. Each finding was checked by two adversarial verifiers with different lenses (is the code reached, does the failure really happen). Of 56 findings, 29 were confirmed, 8 contested and 9 refuted; the other 10 went unverified because their verifier calls failed. The real build then hit no code failure the scan had not listed. Its only other failures were on the host and the network: `j2` missing from the PATH, and a transient wget of `TRUSTED_GPG_URLS`.

The last three commits were reviewed through four lenses: amd64 regressions, arm64 runtime, install and upgrade paths, and build robustness. A second agent checked each finding. The design choices in §4.2–§4.4 reflect those findings, and the gaps the review left open are in §7.

## 2. Build

On vera, 2026-09-28:

| Stage | Time (UTC) | Duration | Result |
|---|---|---|---|
| Host preparation and clone | before 06:04 | ~20 min | Clone 21 s; 60 submodules 6 min |
| Slave image (native, 70 steps) | 06:05–about 08:20 | ~2 h 15 min (about 2 h 11 min of Docker build steps) | No failure after the `gcc-multilib` fix |
| Packages, containers, image (`-k`) | 08:25:59–11:41:46 | 3 h 16 min | 216 targets, 0 failed (one earlier attempt died at once on a transient wget of `TRUSTED_GPG_URLS`) |
| Confirmation rebuild after the initramfs fix | 14:05:22–14:52:31 | 47 min | Rootfs and installer only |

The slave image on vera is dominated by serial work that the ThunderX cores run slowly: about 40 minutes of dpkg for one 1,800-package install step (including texlive format generation), a 12-minute `grpcio 1.71.0` source build (no cp314 wheel exists on either arch), about 11 minutes on the final single-threaded `rustc` of `cargo-tarpaulin` (13 minutes for the whole step), and about 20 minutes exporting and unpacking the 15.2 GB image.

On podler, 2026-09-29, from a fresh clone with empty caches:

| Stage | Time (UTC) | Duration | Result |
|---|---|---|---|
| Host setup, clone, submodules | 03:58:31–03:59:36 | ~1 min | Needed a proxy bypass for download.docker.com (§7.3) |
| Slave image | 03:59:36–04:24:42 | 25 min | No failure |
| Packages, containers, image (`-k`) | 04:24:42–04:57:43 | 33 min | 216 targets, 0 failed |
| Rebuild after changing a commit | for example 07:55:45–08:07:31 | 12–14 min | Changed packages and the installer only |

That makes podler about five times faster than vera for the whole build.

Outputs on vera (counted in `target/`, recorded in `verify-v3.txt`): 154 debs (145 arm64, 9 all), 32 wheels, 29 Docker images (26 installed plus 3 layers), and a `sonic-vs.bin` of 1,424,703,471 bytes (1.42 GB) from the confirmation rebuild. The images built on podler are also 1.43 GB. Checks on the vera image, all in `verify-v3.txt`:

- The payload sha1 self-check passes.
- `bash`, `dockerd` and `python3.14` in the rootfs are aarch64 ELF (e_machine `b700`).
- os-release reads Ubuntu 26.04.1 LTS.
- All 26 Docker images in `dockerfs.tar.gz` have `architecture=arm64` in their image config. (A cross build stamps the build host's arch on the final `FROM scratch` stage; a native build does not.)

## 3. The initramfs finding

**Symptom.** The first image booted into the initramfs and stopped with `squashfs: Unknown parameter 'loop'` and then `No init found`.

**Cause.** The arm64 initrd held no busybox. SONiC builds its own `initramfs-tools` 0.142 from Debian source. Built on the Ubuntu slave, its `initramfs-tools-core` only Recommends `busybox-initramfs`, and `files/apt/apt.conf.d/81norecommends` suppresses Recommends. Debian's `busybox` package carries the initramfs hook itself; Ubuntu's does not, because Ubuntu moved the hook into `busybox-initramfs`. Without busybox the initrd falls back to klibc's `mount`, which has no `loop` option and hands it to the kernel as squashfs data. The missing `awk`, `cut` and `gzip` break later SONiC init scripts, but the loop mount is what stops the boot.

**Why amd64 never hit it.** The amd64-only firmware step installs `linux-firmware-misc` and `linux-firmware-intel-misc`. Both declare `Breaks: initramfs-tools (<< 0.142ubuntu8~)`, so apt replaces SONiC's 0.142 with Ubuntu's 0.151ubuntu1. Its `initramfs-tools-core` hard-Depends on `busybox-initramfs`. The same happened on older builds through the `linux-firmware` metapackage, because every split carries that Breaks.

**What this means for amd64.**

- Every amd64 resolute image already runs Ubuntu's unmodified initramfs-tools. The installed files and the initrd `/init` are byte-identical to Ubuntu 0.151ubuntu1.
- The `loop=`/`loopfstype=` root mount that boots vs comes from Ubuntu's own delta in 0.151ubuntu1 (`/init` parses it; `scripts/local` runs `mount -o loop`). It does not come from SONiC's patches.
- `src/initramfs-tools` and its two patches are therefore dead on amd64. The first patch (loop file system) is duplicated by Ubuntu. The second (`loopoffset=`) has no Ubuntu equivalent, but its only user is Arista Aboot (`files/Aboot/boot0.j2:884`), and no resolute target builds Aboot.
- Other SONiC initramfs changes still apply: `files/initramfs-tools/udev.patch`, and the hooks under `/etc/initramfs-tools`.

**The fix** installs Ubuntu's `initramfs-tools` and `busybox-initramfs` directly on the other arches, rather than the firmware splits, so every arch ends up with the initramfs-tools 0.151ubuntu1 and busybox-initramfs that amd64 already gets. The confirmation rebuild shows `initramfs-tools 0.151ubuntu1` and `busybox-initramfs` in the image, and that image boots with no manual changes. Whether to drop the dead source build is a separate decision; this change does not make it.

These statements were checked by an adversarial review (three verifiers per claim and a judge) against the 2026-08-27 amd64 vs rootfs and build log, and the 2026-09-17 amd64 broadcom build log. That broadcom build came from the PR #17 work before its merge, and ran the same two-package firmware line the baseline carries. No amd64 vs image built at the baseline was available.

## 4. ONIE install and boot

The ONIE tests ran on podler under QEMU 10.2.1: `-machine virt,gic-version=3 -accel kvm -cpu host`, 4 vCPUs, 8 GB, a blank 64 GB virtio-scsi disk and user networking. They used:

- **ONIE:** SONiC's `onie-recovery-arm64-qemu_armv8a-r0.iso` from `packages.trafficmanager.net/public/onie/`. It reports version `master-03031019`, built 2022-03-03, with kernel 5.4.86 and GRUB 2.04.
- **Firmware:** `AAVMF_CODE.no-secboot.fd` from qemu-efi-aarch64 2026.05-2ubuntu2 (§4.1).
- **Harness:** `onie-install-test.py` in [data/2026-09-29-arm64-onie-vmtest/](data/2026-09-29-arm64-onie-vmtest/). It embeds ONIE from the ISO onto the blank disk, ejects the ISO, boots ONIE from disk, and runs `onie-nos-install` against the image served over HTTP. It then reboots into SONiC through the GRUB that the installer wrote, waits for the serial login prompt, and after five minutes collects the state over ssh.

The same directory holds the firmware, GRUB, kexec and kdump scripts used below.

### 4.1 UEFI firmware under KVM

- Resolute's edk2 (qemu-efi-aarch64 2025.11-3ubuntu7 and 2025.11-3ubuntu7.2) stops within a second under KVM with `Synchronous Exception at 0x47EFE008`. With the same command, these builds reach ONIE in about 20 seconds: Ubuntu 2024.02-2ubuntu0.9, 2025.02-8ubuntu3.2 and 2026.05-2ubuntu2; Debian 2025.02-8+deb13u1 and 2026.08+ds-2 (`fwvers.sh`).
- The cause is a known upstream regression in the LPA2 support of edk2-stable202511: Debian #1124168 and edk2 #11962. Debian fixed it in 2025.11-5 by reverting three LPA2 commits: 2025.11-4 crashes at the same address, and 2025.11-5 boots. Resolute's 2025.11-3ubuntu7.x predates that revert. The upstream fixes are 1a4c4fb5a7 (FEAT_LPA systems without LPA2) and b8df7d9c8e (early ID map on LPA2-capable CPUs).
- None of `pmu=off`, `gic-version=host` or `-bios QEMU_EFI.fd` avoids it. KVM offers only the `host` and `max` CPUs, and turning off pauth, pmu or steal time on `host` does not help. Under TCG every named CPU model boots the resolute firmware, and only `-cpu max` hangs (`tcgsweep.sh`).
- vera stopped the same way with resolute's firmware (`Synchronous Exception at 0x496C`), which is why §4.7 booted there with a direct kernel load. vera was not retried with a newer firmware, so the same cause is likely but not confirmed.
- To run UEFI on any arm64 KVM host, extract `AAVMF_CODE.no-secboot.fd` from qemu-efi-aarch64 2026.05-2ubuntu2 (`archive.ubuntu.com/ubuntu/pool/main/e/edk2/`) or Debian 2026.08 with `dpkg-deb -x`; nothing needs installing. No Launchpad bug has been filed.

### 4.2 Kernel format

The linux-sonic arm64 `vmlinuz` is an EFI zboot image: a PE wrapper with `zimg` at offset 4 around a zstd-compressed Image. GRUB before 2.12 checks the arm64 Image magic at offset 0x38 and rejects the file with `error: invalid magic number`. Upstream GRUB dropped that check in 69edb31205 (first in 2.12), but every ONIE release through 2026.08 and ONIE master still build GRUB 2.04. An image that ships the zboot kernel as it comes therefore installs from ONIE and then never boots.

Each GRUB below loaded the linux-sonic 7.0.0-1002 kernel in three forms. "Boots" means the kernel printed `Linux version` (`grubrun.sh`, `grubver.sh`, `grubvanilla.sh`):

| GRUB | zboot, as shipped | plain Image | gzip'd Image |
|---|---|---|---|
| ONIE `master-03031019` (2.04) | rejected | boots | boots |
| upstream 2.06 | rejected | boots | boots |
| Ubuntu jammy 2.06-2ubuntu14.8 | rejected | boots | boots |
| Debian bookworm 2.06-13+deb12u2 (fix backported) | boots | boots | boots |
| upstream 2.12 | boots | boots | boots |
| Debian trixie 2.12-9+deb13u2 | boots | boots | boots |
| Ubuntu noble 2.12-1ubuntu7.3 | boots | boots | boots |
| Debian sid 2.14-4 | boots | boots | boots |
| Ubuntu resolute 2.14-2ubuntu1 | boots | boots | boots |

**The fix** (`6de838da5e`) converts the kernel inside `build_debian.sh` for vs on arm64:

- It reads the payload offset, size and compression from the zboot header, cuts the payload out with `dd`, decompresses it, gzips it again and replaces the file under the same name. `build_debian.sh` already stores the pensando kernel gzip'd.
- The installer's `grub.cfg` and everything else that names the file stay as they are. A gzip'd Image works on every GRUB in the table.
- `dd` reads exactly the payload bytes. A `tail | head` pipeline under `pipefail` would exit 141 (SIGPIPE) whenever more than one pipe buffer (64 KiB) follows the payload.
- The conversion is limited to vs. nvidia-bluefield is also arm64 with GRUB, but its BFB packaging needs the PE kernel.
- It skips Secure Boot builds (`SECURE_UPGRADE_MODE` dev or prod). Those sign and verify the PE kernel just before this step, and unwrapping would drop the signature. Secure Boot is not supported on arm64 vs anyway: the installer's shim path looks only for `shimx64.efi` and `grubx64.efi`.
- Checked with a unit test of the block:
  - The output is byte-identical to the Image that booted on podler, and the file keeps mode 0600.
  - A second run changes nothing.
  - Nothing changes on amd64, broadcom arm64, nvidia-bluefield arm64, or vs arm64 with `SECURE_UPGRADE_MODE` dev or prod.

Not taken:

- **Installing the image's own GRUB 2.14 instead of calling ONIE's `grub-install`.** It is a larger installer change, and the embedded stub must also `set prefix=($root)/grub` and carry the 2.14 arm64-efi modules, or `grubenv` stops working.
- **Requiring an ONIE with GRUB 2.12 or later.** No ONIE release has one. ONIE PR #1128 (GRUB 2.14) is unmerged, targets the `onie-modernization-2026` branch, and was tested on x86 only.

An upgrade from inside SONiC (`sonic-installer install`) runs the new image's `install.sh` and does not run `grub-install`, so ONIE's GRUB 2.04 stays for the life of the install. Every later arm64 vs image must keep this conversion.

### 4.3 Platform identity

SONiC's only published arm64 ONIE reports `onie_platform=arm64-qemu_armv8a-r0`. A vs image knows only `x86_64-kvm_x86_64-r0`. An image built without this commit and the console one shows what that costs:

- The installer stops at "Do you still wish to install this image?".
- The booted system has `HwSKU: None`, and `sonic-platform-vs` is not installed.
- Only 7 of the 14 containers run (database, eventd, gbsyncd, gnmi, pmon, sysmgr, teamd), and `bgp.service` fails.

**The fix** (`624636d7d3`) treats `arm64-qemu_armv8a-r0` as another name for the vs platform, in arm64 vs builds only:

- `sonic-device-data` adds `device/arm64-qemu_armv8a-r0` as a symlink to `x86_64-kvm_x86_64-r0` after it generates the vs HwSKU data, so both names share the generated files. Nothing is added to git. The step follows the `vpp` conditional in the same recipe. That package cannot leak across architectures: its cache mode is `none`, and its dependency flags include `CONFIGURED_PLATFORM` and `CONFIGURED_ARCH`.
- `build_image.sh` lists the name in `platforms_asic`, next to the existing `alpinevs` line that does the same for `x86_64-kvm_x86_64-r0`.
- `sonic-platform-vs` is lazily installed for it as well.
- A new `device_info.VS_PLATFORMS` makes `get_system_mac` and `sonic-cfggen` give both names the deterministic vs MAC, and makes `minigraph` keep `tunnel_qos_remap` off on the alias as it does for kvm.
- No `installer.conf` is aliased: the vs one only sets `swiotlb=65536` for multi-asic vs (#6674).

Not taken:

- **A git-tracked symlink under `device/virtual/`.** It would put a fake arm64 platform into every build, amd64 vs and broadcom included. The aboot image's size-reduction step would also crash on it, because `shutil.rmtree` refuses symlinks.
- **Rewriting `onie_platform` to the x86 name at install time.** That comes too late: `install.sh` checks `platforms_asic` at line 113, before it sources `platform.conf` at line 165. It would also record a platform that ONIE never reported.

Checks:

- A stubbed `device_info` gives both names the same deterministic vs MAC and sends other platforms down the non-vs path.
- `minigraph.parse_xml` on the remap-enabled sample graph leaves `tunnel_qos_remap` off for both vs names and on for Dell S6000. Without the change, the alias turned it on.
- A sweep of the running arm64 image looked for other code that depends on the platform name. It covered the host and all 14 containers, both text files and ELF binaries, and all 49 argument-less `device_info` functions. It also ran more than 30 show and utility commands under both names, using the `PLATFORM` environment override. It found three more sites, all in submodules (§7.1).

### 4.4 Console

`installer/default_platform.conf` defaults to an x86 8250 serial console: `serial --port=0x3f8 --speed=9600` for GRUB and `console=ttyS0,9600n8` for the kernel. On QEMU virt, ONIE's GRUB 2.04 prints `serial port 'port3f8' isn't found` and `terminal 'serial' isn't found`. These do not stop the boot, but the kernel console is set to `ttyS0`, which QEMU virt does not have, and kdump inherits that setting.

**The fix** (`d3b6c4c08b`) adds `platform/vs/platform_arm64.conf`, which `build_image.sh` uses as `platform.conf` on arm64:

- GRUB uses only the console terminal. On QEMU virt that is the firmware's EFI console, which is the PL011 UART.
- The kernel gets `console=tty0 console=ttyAMA0,115200n8 quiet`.
- The installed `grub.cfg` then starts with `# serial console: EFI ConOut`, `terminal_input console` and `terminal_output console`.

Also checked in the code, without a run:

- `sonic-installer install` reruns the new image's `install.sh` with this file.
- fast-reboot and soft-reboot take the `linux` line from `grub.cfg`, and the kernel path stays in the same field.
- `rc.local`'s `program_console_speed` and the serial getty both handle `ttyAMA0`.
- kdump copies the console from `/proc/cmdline`.

### 4.5 Result

The branch head, built on podler as `arm64-native.0-a58976d49` and installed from ONIE:

- **Timeline:** ONIE embed at 24 s, ONIE from disk at 47 s (reporting GRUB 2.04), SONiC install done at 112 s, GRUB menu at 120 s, SONiC serial login at 150 s. The installer asks no question.
- **Boot:** the kernel command line carries `console=tty0 console=ttyAMA0,115200n8`. The installed `vmlinuz` starts with `1f 8b`, that is, gzip.
- **Identity:** `show version` gives `SONiC.arm64-native.0-a58976d49`, kernel `7.0.0-1002-sonic`, `Platform: arm64-qemu_armv8a-r0`, `HwSKU: Force10-S6000`, `ASIC: vs`.
- **Platform data:** `/usr/share/sonic/device/arm64-qemu_armv8a-r0` links to `x86_64-kvm_x86_64-r0`, `sonic-platform-vs` 1.0 is installed, and `/host/image-*/platform/` has a directory for the alias.
- **Containers:** bgp, database, eventd, gbsyncd, gnmi, lldp, mgmt-framework, pmon, radv, snmp, swss, syncd, sysmgr, teamd.
- **Data plane:** 32 ports in APPL_DB; 33 PORT and 69 ROUTE_ENTRY objects in ASIC_DB. BGP has router id 10.1.0.1, AS 65100 and 32 configured peers.
- **Health:** `systemctl is-system-running` reports `degraded`. The failed units are `watchdog-control` and `system-health` (§6).

Against an image built without the alias and console commits:

| | Without the last two commits | Branch head |
|---|---|---|
| ASIC-type prompt at install | yes | no |
| GRUB messages | `serial port 'port3f8' isn't found`, `terminal 'serial' isn't found` | none |
| HwSKU | None | Force10-S6000 |
| Containers | 7 | 14 |
| Failed units | bgp, system-health, watchdog-control | system-health, watchdog-control |

`onie-e2e-output.txt` in the data directory is a full harness output.

### 4.6 kexec and kdump

These ran inside the installed SONiC of the image built without the last two commits. Those commits touch only the platform name and the console arguments, which kdump copies from `/proc/cmdline`. Scripts are `kexec-test.sh` and `kdump-test.sh`.

- **Load:** `kexec -l` succeeds with `-a` (the fast-reboot and warm-reboot mode), `-s` (`kexec_file_load`, used when Secure Boot is on) and `-c` (`kexec_load`). All three work for the shipped gzip Image, for the original zboot file and for a raw Image: 9 of 9 with `rc=0` and `kexec_loaded=1`.
- **Jump:** loading the shipped kernel with `-a` and running `kexec -e` boots it. The system comes back with a new boot id, `SONIC_BOOT_TYPE=kexec-test` in `/proc/cmdline` and kernel `7.0.0-1002-sonic`.
- **kdump:** `config kdump enable` and a reboot give `crashkernel=0M-2G:256M,2G-4G:320M,4G-8G:384M,8G-:448M` on the command line, `kexec_crash_loaded=1` and "ready to kdump". A sysrq-c crash brings the system back within about 30 seconds. `/var/crash/202609290601/` then holds a 161 MB dump file, `kdump.202609290601`.

### 4.7 Direct kernel boot on vera

vera ran the first boots, on 2026-09-28, without UEFI (§4.1). The image's kernel, unpacked to a raw Image, was loaded directly by QEMU, and the disk was laid out the way `installer/install.sh` does it. The tools are in [data/2026-09-28-arm64-native-vmtest/](data/2026-09-28-arm64-native-vmtest/). `dockerfs.tar.gz` must be unpacked with `--numeric-owner`, as the installer does. Without it, GNU tar remaps owners through the host's passwd, and the database container's redis loses read access to `/etc/redis/redis.conf`.

With `onie_platform=x86_64-kvm_x86_64-r0` in `machine.conf`, the confirmation image (`arm64-native.0-dirty-20260928.140528`) gave the same results as §4.5, recorded in `v3-serial2.log` and `runtime-v3.txt`:

- The login prompt appeared about 30 seconds after the kernel started, and the last containers about 4–5 minutes after boot.
- The same 14 containers ran, with the same port, ASIC_DB and BGP counts.
- Ethernet0/4/8/12, backed by the VM's four data NICs, were oper up. The other 28 have no NIC behind them and stay oper down, as on any vs VM with fewer NICs than ports.
- Every long-running supervisord process was RUNNING in swss, syncd, database, teamd, lldp, snmp, gnmi, mgmt-framework, bgp and pmon. The only exception was `sharpd` in bgp, which is `STOPPED Not started` by design.

## 5. Components left out on arm64

### 5.1 pmon SSD vendor tools

**Why they are x86 only.** `iSmart` (Innodisk iSMART V3.9.41, 2018, x86-64) and `SmartCmd` (Virtium 1.0.2427, 2017, statically linked i386) are closed-source vendor tools. Mellanox committed them as prebuilt binaries in 2019 (sonic-buildimage #3218) to read extra health data from the Innodisk and Virtium SSDs in its x86 switches. No source exists, and the files have not changed upstream since. Innodisk supplies iSMART only on request and names no CPU architecture. Virtium has published aarch64 builds of other tools (vtView, vtTestCmd, vtSecureCmd), but not of SmartCmd.

**Upstream.** Upstream never excluded them on any architecture, so its ARM images ship the x86 files. On the one ARM box with an Innodisk SSD, the armhf Nokia 7215, that produces an hourly `ERR ... [Errno 8] Exec format error: 'iSmart'`. Issue #21319 has been open since 2025-01. The only response so far is a sonic-mgmt log-analyzer ignore rule for that exact message.

**What arm64 loses: nothing.**

- The binaries do not run on arm64, natively or under qemu-user 10.2. They start under qemu, but qemu does not translate the SG_IO and NVMe ioctls they read the drive with.
- `ssd.py` (sonic-platform-common) always runs `smartctl` first and calls a vendor tool only for a matching model string. If the tool fails, it keeps the smartctl values and logs one error line. smartmontools 7.5 and nvme-cli 2.16 are in resolute arm64 main and already installed in pmon, and smartctl's drive database covers the Innodisk 3IE3/3ME3/3IE4/3ME4 families.
- The arm64 vs disk never matches a vendor model. It is a QEMU virtio-scsi `sda`: stormond's ata/nvme sysfs filter skips it, and smartctl reports no `Device Model:` line for it.
- No arm64 SONiC platform uses an Innodisk or Virtium SATA SSD. The arm64 Nokia 7215 variants use eMMC, and resolute does not build armhf.

**Two related findings.**

- sonic-utilities installs another x86-64 Virtium tool, `vtFA_RTK_5766_v2` (added 2026-05, #4508), on every architecture through its wheel. It runs only in the Mellanox techsupport path, for one Virtium NVMe model, so it is dead weight on arm64 (17.7 KB).
- `SmartCmd` embeds Virtium's software licence: nontransferable, one backup copy, and a duty to protect. SONiC's third-party licence file covers neither tool. That is a question for the amd64 images Canonical builds today, independent of arm64, and should go to legal review.

### 5.2 docker-dash-engine

**Why it is x86 only.** The container is built `FROM p4lang/behavioral-model`. p4lang publishes all 98 tags of that image, and its whole base chain (`p4lang/pi`, `p4lang/third-party`), only for amd64. p4lang's CI builds on x86 runners with no multi-platform setting. This is a publishing choice, not a code limit. The bmv2 source is portable, and the community multi-arch image `kathara/bmv2` runs dash-engine's exact `simple_switch_grpc ... --no-p4` command on podler and serves P4Runtime on port 9559. The only request for arm64 images (p4lang/third-party#47, 2026-09-01) has no reply.

**It does nothing on resolute, on any architecture.**

- dash-engine is an empty bmv2 switch. The DASH pipeline and SAI live in syncd's `syncd_dash`, which programs it over P4Runtime.
- `platform/vs/syncd-vs.mk` builds DASH SAI only when `BLDENV` is bookworm or trixie, so resolute never builds `syncd_dash`.
- The amd64 resolute image therefore already carries a 175 MB dash-engine container, disabled and pinned to an Ubuntu 20.04-based digest, that nothing can drive. Leaving it out on arm64 loses nothing.
- On arm64 the pin does not even apply: `versions-docker` has only an `amd64:` entry, so an arm64 build would float on `:latest`.

**Upstream.**

- Upstream builds no vs image on arm64.
- PR #25591 (a draft) gates dash-engine on `INCLUDE_VS_DASH_SAI`, which defaults to `y`. Under that gate a native arm64 build would still fail at the `FROM`, so an architecture gate is still needed.
- PR #27346 (open) adds an `INCLUDE_VS_DASH_ENGINE` knob.

**What real DPU emulation on arm64 would take.**

- An arm64 bmv2 and PI.
- The p4lang debs, built on resolute and installed in the syncd container as well.
- A multiarch patch for DASH's libsai packaging, which hard-codes `_amd64` names and `x86_64-linux-gnu`.
- DASH SAI enabled for `BLDENV=resolute`.
- An arm64 build of the `p4runtime-sh` image, which sonic-mgmt's DPU setup uses for underlay routes.

No project in that chain runs arm64 CI, so this is worth doing only for a concrete requirement.

Two things could be done on amd64 too:

- Gate dash-engine on DASH SAI actually being built (`INCLUDE_VS_DASH_SAI=y` and `BLDENV` bookworm or trixie). That would also drop the orphaned container from the amd64 resolute image, which is a product decision.
- Bump the p4lang pins in `rules/p4lang.mk`. Two of the three `.dsc` files are gone from OBS, but default builds fetch them from SONiC's web version cache, so this is not urgent.

## 6. Findings that are not arm64 problems

| Finding | Scope |
|---|---|
| `watchdog-control.service` fails: `/etc/sonic/vs_chassis_metadata.json not found` | All vs images and upstream. Nothing in the build creates the file; only sonic-mgmt's virtual-chassis testbed setup writes it. The code matches upstream `sonic-net/202605` and has since #18512 (2024). |
| `system-health.service` fails for the same file | Same cause. `healthd` builds the vs `Chassis` before it reads any platform configuration, so the platform name does not matter. On vera, under the x86 name, the serial logs show it started more than once, but it was not listed as failed when the state was captured. Whether systemd gives up depends on how fast the daemon crashes against the start limit of five starts in ten seconds (inferred). |
| `show version` prints `Distribution: Debian forky/sid` | All resolute images. Ubuntu base-files ships `/etc/debian_version` = `forky/sid`, `build_debian.sh:680` copies it into `sonic_version.yml`, and sonic-utilities prints "Debian " in front of it. Cosmetic. |

## 7. Open items

### 7.1 Submodule checks that miss the arm64 name

Each of these recognises vs only by `x86_64-kvm_x86_64-r0` or the substring `kvm`. The superproject's `VS_PLATFORMS` does not reach them. All three were reproduced on the installed image, comparing the arm64 name with the x86 name on the same image. Upstream `master` and `202605` have the same code, because upstream has no alias. Fixing any of them needs a Canonical commit on the submodule's `202605_resolute` branch and a gitlink bump, so none is changed here.

| Where | Effect on arm64 vs | When |
|---|---|---|
| sonic-utilities `scripts/decode-syseeprom:238,243` (`.*kvm.*`) | See the list below. | Every snmp start |
| sonic-utilities `utilities_common/hft.py:14` (platform allowlist) | `show hft` and `config hft` are not registered ("No such command"). The HFT data plane is gated on SAI capability and still starts; on vs it only emulates the control plane. | Always |
| sonic-platform-daemons `sonic-ycabled/ycable/ycable.py:307` (CONFIG_DB platform `==` the x86 name) | ycabled treats the system as hardware, fails to load `sfputil`, exits four times and ends FATAL in pmon. Nothing reports it. A dual-ToR vs testbed could then not drive mux state (inferred from code). | Only with `subtype: DualToR` |

What goes wrong with `decode-syseeprom`:

- It exits 0 and prints "Failed to read system EEPROM info". Under the x86 name it exits with ENODEV (19), a code added upstream for vs in sonic-utilities #3750.
- snmp's pre-start step (`docker_image_ctl.j2:128-129`) passes that text unquoted to `HSET`, and redis rejects the odd argument count.
- STATE_DB `chassis_serial_number` is then missing instead of "N/A", and SNMP `entPhysicalSerialNum` is empty.
- Each snmp start logs `ERR ... wrong number of arguments for 'hset'`. sonic-mgmt's log analyzer already ignores the other two ERR lines from this path, but not this one.

Suggested fixes:

- **decode-syseeprom:** also treat `asic_type == 'vs'` as having no EEPROM, and keep the `kvm` pattern, because vpp images use the kvm name with `asic_type` vpp. A patched copy on the VM exited with 19, and snmp then wrote "N/A".
- **ycabled:** use `VS_PLATFORMS`, or `asic_type`, which is also upstreamable.
- **HFT:** add the alias to the list, or accept `VS_PLATFORMS`.

The same sweep (§4.3) found no fourth site. `syncd_init_common.sh:642` also tests for `kvm`, but only inside the xsight branch, which vs never takes.

### 7.2 Minor

- The klish build links with `-L`/rpath `/usr/lib/x86_64-linux-gnu` on the native path.
- `files/initramfs-tools/modules.arm` lists `m25p80` and `ar7part`, which the linux-sonic 7.0 arm64 kernel lacks.
- `vtFA_RTK_5766_v2` (§5.1).

### 7.3 Pitfalls

- The top-level `Makefile` builds its targets through a `%::` rule with no prerequisites. If `target/sonic-vs.bin` exists, `make target/sonic-vs.bin` reports "up to date" without looking at `build_debian.sh`. Delete the target to rebuild it.
- `jinjanator` installed with `pip --user` puts `j2` in `~/.local/bin`, which non-interactive shells do not have on their PATH. `build_mirror_config.sh` then writes an empty `sources.list`, and the slave build fails with "no build stage in current context".
- The `sonic-build-hooks` target fetches `TRUSTED_GPG_URLS` with wget on every make run. One transient failure (exit 4) stopped the first attempt on vera.
- On podler, the lab's apt proxy answered `ERR_DNS_FAIL` for `download.docker.com`, so docker-ce would not install. `Acquire::http::Proxy::download.docker.com "DIRECT";` (and the https line) in `/etc/apt/apt.conf.d/` fixes it.
- On an arm64 KVM host, resolute's own edk2 cannot start UEFI guests (§4.1).

## 8. Against the cross probe

| | Cross (2026-09-23, amd64 host) | Native (2026-09-28 and 29, arm64 hosts) |
|---|---|---|
| Code changes | 7 code deviations, plus the emulator swap and the vfs driver | 9 commits |
| Slave image | 8 full attempts plus 3 shadow builds | 1 build per host (an earlier run on vera stopped at once because `j2` was not on the PATH) |
| Furthest point | Dependency frontier at the Docker layer (2 images built) | Image installed from ONIE and running |
| Emulation in the build | qemu-user for every arm64 container and the rootfs | None |
| Docker image labels | Mislabelled amd64 | arm64 |

The cross probe concluded that a native machine removes 19 of 21 failures. The native build confirms that. The two architecture-inherent items it named (the amd64-only vs platform package and the amd64-only dash-engine base) are commits `96f264e2b9` and `13d5623f1c`.

## 9. State

- Branch `feat/resolute-arm64-vs` in the local repository: nine signed commits on top of `d2f9ae8502`, not pushed.
- Both reservations have ended, and the build trees and VMs on vera and podler are gone.
- vera's logs were copied to `/home/sheldon-qi/sbi-arm64-native-logs/`:
  - build logs (`build-configure.log`, `build-bin-attempt1.log`, `build-bin.log`, `rfs-confirm.log`);
  - serial logs of the direct boots that reached login: `v2-serial.log` (first image, replacement initrd), `v3-serial.log` and `v3-serial2.log` (confirmation image), `v3b-serial.log` (confirmation image with `onie_platform=arm64-qemu_armv8a-r0`);
  - `kk3.log` (host kernel booted directly), `fw-aavmf-nosb.log` and `fwtest.out` (UEFI attempts);
  - `runtime-v2.txt`, `runtime-v3.txt`, `verify-v3.txt` and the scripts that produced them;
  - the scan and claim-review results.

  No serial log of the failed first boot (the §3 symptom) was kept.
- Nothing was copied off podler before its reservation ended. The scripts in [data/2026-09-29-arm64-onie-vmtest/](data/2026-09-29-arm64-onie-vmtest/) were recovered from the session record as they ran, and the numbers in §2 and §4 come from their recorded output.
