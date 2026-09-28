# arm64 vs on 202605_resolute: native build and boot report

- Date: 2026-09-28
- Baseline: `canonical/202605_resolute` at `d2f9ae8502`
- Changes: local branch `feat/resolute-arm64-vs` (6 GPG-signed commits, not pushed), worktree `/home/sheldon-qi/sbi-arm64-native`
- Build host: `vera` (10.241.5.36, TOR3 lab, reserved for about 18 hours). Cavium ThunderX-88XX, 48 cores at one thread per core, 62 GB RAM, 219 GB SSD, Ubuntu 26.04.1 arm64, kernel 7.0.0-34-generic, docker-ce 29.8.1.
- Follows: [cross-build probe report](2026-09-23-resolute-arm64-cross-probe-report-en.md)
- This is the English version and the single source of truth; the Chinese version is `-zh.md`

## 0. Bottom line

**A native arm64 build of `target/sonic-vs.bin` works.** Starting from the baseline it needed **six small changes, and the resulting image boots under KVM**:

- 14 containers come up.
- All 32 front-panel ports are programmed from CONFIG_DB through APPL_DB into ASIC_DB (33 SAI port objects, the CPU port included). The four backed by the VM's data NICs are oper up.
- 69 routes sit in ASIC_DB.
- BGP (FRR 10.5.4) runs with 32 configured peers.
- The only failed unit is `watchdog-control`, which fails the same way on every vs image, amd64 included (§5).

The cross probe of 2026-09-23 predicted this. It needed eight deviations and still stalled at the Docker layer, with only `docker-base` and `docker-dash-engine` built. The native build hit no code failure beyond the ones already fixed. Four of the six changes were predicted by the cross probe's §6 and confirmed by a static scan, which ran while the slave image built and added the fifth. The sixth surfaced only when the image booted, and it exposed something about amd64 as well (§3).

Two things remain open:

- **The ONIE + GRUB install path was not tested.** On this ThunderX host the UEFI firmware raises a synchronous exception under KVM before it reaches ONIE, so the image was booted by loading its kernel directly (§4).
- **An arm64 vs image has no platform identity of its own.** When it is installed from the real arm64 ONIE (`arm64-qemu_armv8a-r0`), the platform package is not installed and swss/syncd stop. This needs a naming decision (§6).

## 1. Changes

All six are in `feat/resolute-arm64-vs`, one commit each. None changes what an amd64 build does, except that the amd64 `sonic-platform-vs` package is now named `_all.deb`; nothing else in the tree refers to the old name.

| Commit | Change | Failure it removes |
|---|---|---|
| `7c469ec934` | `sonic-slave-resolute/Dockerfile.j2`: install `gcc-multilib` only on amd64 | Resolute publishes no arm64 `gcc-multilib`, so the slave image stops at that line |
| `f989cb441d` | `platform/vs/rules.mk`: `override TARGET_BOOTLOADER = grub` | `Makefile.work` defaults non-amd64 to uboot, and `build_debian.sh` then needs a `platform/vs/sonic_fit.its` that does not exist |
| `96f264e2b9` | `sonic-platform-vs`: `Architecture: all`, `_all.deb` | The pure-Python package was declared amd64, so `dpkg-buildpackage` produced nothing |
| `13d5623f1c` | `docker-dash-engine`: amd64 only (make rule plus unit file copy) | Its base `p4lang/behavioral-model:latest` exists only for amd64 |
| `2c04ece9e9` | pmon: ship `ssd_tools` and their host wrappers only on amd64 | The prebuilt `iSmart` (x86-64) and `SmartCmd` (i386) binaries would land unrunnable in the arm64 image |
| `8858c03ecd` | `build_debian.sh`: on non-amd64, install `initramfs-tools busybox-initramfs` | The arm64 initrd had no busybox and could not mount its root (§3) |

The static scan ran 06:08–07:34 UTC, during the slave build and before the package build. It was given the first four changes as already known (from the cross probe's §6), confirmed them, and found the fifth. It ran eight dimension finders over the vs arm64 build closure. Each finding was checked by two adversarial verifiers with different lenses (is the code reached, does the failure really happen). Of 56 findings, 29 were confirmed, 8 contested and 9 refuted; the other 10 went unverified because their verifier calls failed. The confirmed build-stopping findings were exactly the first four changes; the pmon one was confirmed as a silent wrong-architecture file. The real build then hit no code failure the scan had not listed. Its only other failures were on the host and the network: `j2` missing from the PATH, and a transient wget of `TRUSTED_GPG_URLS`.

## 2. Build

| Stage | Time (UTC) | Duration | Result |
|---|---|---|---|
| Host preparation and clone | before 06:04 | ~20 min | Clone 21 s; 60 submodules 6 min |
| Slave image (native, 70 steps) | 06:05–about 08:20 | ~2 h 15 min (about 2 h 11 min of Docker build steps) | No failure after the `gcc-multilib` fix |
| Packages, containers, image (`-k`) | 08:25:59–11:41:46 | 3 h 16 min | 216 targets, 0 failed (one earlier attempt died at once on a transient wget of `TRUSTED_GPG_URLS`) |
| Confirmation rebuild after the initramfs fix | 14:05:22–14:52:31 | 47 min | Rootfs and installer only |

The slave image is dominated by serial work that the ThunderX cores run slowly: about 40 minutes of dpkg for one 1,800-package install step (including texlive format generation), a 12-minute `grpcio 1.71.0` source build (no cp314 wheel exists on either arch), about 11 minutes on the final single-threaded `rustc` of `cargo-tarpaulin` (13 minutes for the whole step), and about 20 minutes exporting and unpacking the 15.2 GB image.

Outputs (counted in `target/`, recorded in `verify-v3.txt`): 154 debs (145 arm64, 9 all), 32 wheels, 29 Docker images (26 installed plus 3 layers), and a `sonic-vs.bin` of 1,424,703,471 bytes (1.42 GB) from the confirmation rebuild. Checks on that image, all in `verify-v3.txt`:

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

## 4. How the image was booted

- `/dev/kvm` works (the host runs at EL2 with GICv3), but the edk2 firmware does not start under KVM on this ThunderX. `AAVMF_CODE.no-secboot.fd`, `AAVMF_CODE.fd` and `QEMU_EFI.fd`, with `pmu=off` and with one vCPU, all stop at once with `Synchronous Exception at 0x496C`. Under TCG the firmware banner prints and then nothing happens for more than nine minutes. So neither ONIE, the SONiC installer, nor GRUB could run here.
- Loading a kernel directly works under KVM. Ubuntu's arm64 kernels (the host's and SONiC's `7.0.0-1002-sonic`) are EFI zboot images compressed with zstd, and QEMU `-kernel` only unpacks gzip zboot. The kernel was therefore unpacked to a raw Image first.
- The disk was laid out the way `installer/install.sh` does it: GPT, ext4 labelled `SONiC-OS`, `image-<version>/{fs.squashfs,boot,docker,platform}`, and a `machine.conf`. The kernel command line was the installer's GRUB line with `console=ttyAMA0`.
- The tools are in [data/2026-09-28-arm64-native-vmtest/](data/2026-09-28-arm64-native-vmtest/). `dockerfs.tar.gz` must be unpacked with `--numeric-owner`, as the installer does. Without it, GNU tar remaps owners through the host's passwd, and the database container's redis loses read access to `/etc/redis/redis.conf`.

Results on the confirmation image (`build_version` `arm64-native.0-dirty-20260928.140528`), with `machine.conf` set to `onie_platform=x86_64-kvm_x86_64-r0` (the only platform the image knows). Recorded in `v3-serial2.log` and `runtime-v3.txt`:

- The login prompt appears about 30 seconds after the kernel starts. The last containers (lldp, snmp, mgmt-framework) are up about 4–5 minutes after boot.
- Containers: bgp, database, eventd, gbsyncd, gnmi, lldp, mgmt-framework, pmon, radv, snmp, swss, syncd, sysmgr, teamd.
- Ports: 32 in APPL_DB, all 32 admin up. Ethernet0/4/8/12, which map to the VM's four data NICs, are oper up. The other 28 have no NIC behind them and stay oper down, as on any vs VM with fewer NICs than ports.
- ASIC_DB: 33 PORT, 69 ROUTE_ENTRY, 34 ROUTER_INTERFACE, 672 QUEUE, 416 SCHEDULER_GROUP objects.
- BGP: FRRouting 10.5.4, router id 10.1.0.1, AS 65100, 32 peers configured.
- supervisord in swss, syncd, database, teamd, lldp, snmp, gnmi, mgmt-framework, bgp and pmon: every long-running process is RUNNING, and the one-shot programs (`start`, `dependent-startup`, `swssconfig` and the like) have EXITED. The only exception is `sharpd` in bgp, which is `STOPPED Not started` by design.
- The management NIC gets 10.0.2.15 from QEMU's DHCP server (`DHCPACK of 10.0.2.15 from 10.0.2.2`).

The first image, before the initramfs fix, gave the same results when booted with a replacement initrd (`runtime-v2.txt`).

## 5. Findings that are not arm64 problems

| Finding | Scope |
|---|---|
| `watchdog-control.service` fails: `/etc/sonic/vs_chassis_metadata.json not found` | All vs images and upstream. Nothing in the build creates the file; only sonic-mgmt's virtual-chassis testbed setup writes it. The code matches upstream `sonic-net/202605` and has since #18512 (2024). |
| `show version` prints `Distribution: Debian forky/sid` | All resolute images. Ubuntu base-files ships `/etc/debian_version` = `forky/sid`, `build_debian.sh:680` copies it into `sonic_version.yml`, and sonic-utilities prints "Debian " in front of it. Cosmetic. |

## 6. Open items for arm64

Confirmed by the boot test:

- **Platform identity.** Booted with `onie_platform=arm64-qemu_armv8a-r0`, which is what the only arm64 ONIE SONiC publishes (`onie-recovery-arm64-qemu_armv8a-r0.iso`) reports:
  - `show platform summary` gives `HwSKU: None`.
  - `sonic-platform-vs` is not installed, because the lazy-install directory is only `x86_64-kvm_x86_64-r0`.
  - swss and syncd stop, and `bgp` and `featured` fail.

  The static scan's proposed fix is a git-tracked symlink `device/virtual/arm64-qemu_armv8a-r0 -> x86_64-kvm_x86_64-r0`, a matching symlink in `src/sonic-device-data`, and that platform added to `$(VS_PLATFORM_MODULE)_PLATFORM`. It needs a decision on the arm64 vs platform name, and it was not built.

From the static scan, not reachable on this host:

- **Kernel format under ONIE.** ONIE's GRUB 2.04 does not recognise the zstd EFI zboot kernel ("invalid magic number"). The scan found three ways out:
  - At build time, unwrap the zboot kernel into a plain gzip'd arm64 Image, which GRUB 2.04 accepts. This is the smallest change and needs no installer change; a verifier checked that the result is accepted.
  - Have the installer install the image's own GRUB 2.14 (`grub-mkstandalone` for arm64-efi) instead of running ONIE's `grub-install`. The embedded stub must also `set prefix=($root)/grub` and ship the 2.14 arm64-efi modules, or `grubenv` stops working.
  - Require an ONIE built with GRUB 2.12 or later.
- **Console defaults.** `installer/default_platform.conf` defaults to an x86 8250 serial console (`serial --port=0x3f8`, `console=ttyS0`). arm64 needs a `platform/vs/platform_arm64.conf` for PL011 (`ttyAMA0`).
- Minor, and not in the way of booting:
  - The klish build links with `-L`/rpath `/usr/lib/x86_64-linux-gnu` on the native path.
  - `sonic-utilities` installs a prebuilt x86-64 `vtFA_RTK_5766_v2`.
  - `files/initramfs-tools/modules.arm` lists `m25p80` and `ar7part`, which the linux-sonic 7.0 arm64 kernel lacks.

Pitfalls met on the way, useful to anyone repeating this:

- The top-level `Makefile` builds its targets through a `%::` rule with no prerequisites. If `target/sonic-vs.bin` exists, `make target/sonic-vs.bin` reports "up to date" without looking at `build_debian.sh`. Delete the target to rebuild it.
- `jinjanator` installed with `pip --user` puts `j2` in `~/.local/bin`, which non-interactive shells do not have on their PATH. `build_mirror_config.sh` then writes an empty `sources.list`, and the slave build fails with "no build stage in current context".
- The `sonic-build-hooks` target fetches `TRUSTED_GPG_URLS` with wget on every make run. One transient failure (exit 4) stopped the first attempt.

## 7. Against the cross probe

| | Cross (2026-09-23, amd64 host) | Native (2026-09-28, arm64 host) |
|---|---|---|
| Code changes | 7 code deviations, plus the emulator swap and the vfs driver | 6 commits |
| Slave image | 8 full attempts plus 3 shadow builds | 1 build (an earlier run stopped at once because `j2` was not on the PATH) |
| Furthest point | Dependency frontier at the Docker layer (2 images built) | Image built and booted |
| Emulation in the build | qemu-user for every arm64 container and the rootfs | None |
| Docker image labels | Mislabelled amd64 | arm64 |

The cross probe concluded that a native machine removes 19 of 21 failures. The native build confirms that. The two architecture-inherent items it named (the amd64-only vs platform package and the amd64-only dash-engine base) are commits `96f264e2b9` and `13d5623f1c`.

## 8. State

- Branch `feat/resolute-arm64-vs` in the local repository, six signed commits on top of `d2f9ae8502`, not pushed.
- `vera` holds the build tree `~/sonic-buildimage` (branch `arm64-native`, the same six changes, uncommitted), both images, and the test disks under `~/vmtest`. It was reserved for about 18 hours from 05:45 UTC on 2026-09-28.
- Logs copied to `/home/sheldon-qi/sbi-arm64-native-logs/`:
  - build logs (`build-configure.log`, `build-bin-attempt1.log`, `build-bin.log`, `rfs-confirm.log`);
  - serial logs of the SONiC boots that reached login: `v2-serial.log` (first image, replacement initrd), `v3-serial.log` and `v3-serial2.log` (confirmation image), `v3b-serial.log` (confirmation image with `onie_platform=arm64-qemu_armv8a-r0`);
  - `kk3.log` (host kernel booted directly), `fw-aavmf-nosb.log` and `fwtest.out` (UEFI attempts);
  - `runtime-v2.txt`, `runtime-v3.txt`, `verify-v3.txt` and the scripts that produced them;
  - the scan and claim-review results.

  No serial log of the failed first boot (the §3 symptom) was kept.
