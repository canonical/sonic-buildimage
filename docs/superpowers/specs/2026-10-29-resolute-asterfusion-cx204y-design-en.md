# Asterfusion CX204Y-48GT on Resolute SONiC — Design

- Date: 2026-10-29
- Build branch: `feat/resolute-cx204y` (new), based on `feat/resolute-arm64-vs` at `d3b6c4c08b` (draft PR #18, the only branch that builds arm64 Resolute images)
- Target hardware: Asterfusion CX204Y-48GT-M-S — Marvell AlleyCat5X (98DX35xx) SoC with its integrated Cortex-A55 (arm64), 48 × 1G RJ45 + 4 × 25G SFP28, 4 GB RAM, 32 GB eMMC, U-Boot with UEFI (`bootefi`)
- Related documents: [arm64 native build report](../2026-09-28-resolute-arm64-native-build-report-en.md), [arm64 vs cross-build probe design](2026-09-23-resolute-arm64-vs-cross-probe-design-en.md)
- This English version is the source of truth; the Chinese version (`-zh.md`) mirrors it in full

## 1. Goal and Scope

Produce a Resolute (Ubuntu 26.04) SONiC ONIE installer that installs and boots on the CX204Y-48GT and, with the vendor SAI enabled for internal testing, forwards traffic on all 52 ports.

**Out of scope:** other Asterfusion models; PoE and PTP features; building the kernel; changing any existing submodule; making the community Marvell SAI drive the CX204Y (it lacks the board's ASK XML); deciding where vendor binaries are stored; upstreaming.

## 2. Decisions

| Topic | Decision |
|---|---|
| Kernel | Use the arm branch's prebuilt linux-sonic `7.0.0-1002` unchanged. Build only two out-of-tree modules: `mvcpss` and `x204y-48gt` |
| Source location | All CX204Y sources live in this repository; no new submodule |
| Vendor baseline | Device configuration and platform scripts come from AsterNOS firmware `V6.1R006P002`; C sources the firmware lacks come from `asternos_patches@105a124` |
| Review structure | Verbatim imports and adaptations are separate commits |
| Platform scope | On Resolute, the `marvell-prestera` arm64 image supports only the CX204Y and boots through GRUB |
| Vendor binaries | Internal testing only. Not committed; consumed through a SAI override switch |

## 3. Established Facts

All items were verified before this design; none are inferred.

| Item | Finding | Evidence |
|---|---|---|
| Vendor firmware | `AsterNOS-Campus-V6.1R006P002-arm64.bin`, built 2026-10-10 from `release/V6.1R006`: Debian 12.15, kernel `6.1.0-29-2-arm64` | `sonic_version.yml` in `fs.squashfs` |
| Vendor boot chain | U-Boot `bootcmd=run bootefi` → `fatload mmc 0:1` → GRUB on the ESP → `devicetree` + raw Image + initrd. Partitions: p1 ESP (vfat, 512 MB), p2 ONIE (512 MB), p3 OS. GRUB installed with `--no-nvram`; boot target set with `fw_setenv` | Vendor `install.sh` |
| Community FIT path | Unusable with the Ubuntu kernel: the raw Image is 69.3 MiB. In the AC5X FIT layout it overlaps the initrd by 5.3 MiB, and it exceeds the 64 MiB `CONFIG_SYS_BOOTM_LEN` of Marvell's U-Boot 2020.10 | QEMU + U-Boot 2025.10 test; `sonic_fit.its` |
| Vendor SAI | `mrvllibsai 1.16.1-2` (Maintainer `jenkins@asterfusion.com`, CPSS 4.5.4). `sai_query_api_version` returns 11601. `NEEDED libpython3.11.so.1.0`, used only by the xpShell debug CLI | Disassembly; dpkg record in the syncd layer |
| Python dependency | Load-time only: the sole SAI entry is `SAI_SWITCH_ATTR_SWITCH_SHELL_ENABLE`, which syncd sets only with `-d`, and `marvell-prestera` does not pass it. With a stub library, `dlopen(RTLD_NOW)` succeeds on Resolute arm64 userland (glibc 2.43, libnl 3.12) and all 13 syncd entry points resolve | qemu-user load test |
| SAI ABI gap | 1.16.1 → 1.18.1 only appends methods to `ipmc_group` and `port`; syncd references neither. The library lacks `sai_query_stats_st_capability` and `sai_tam_telemetry_get_data`, which syncd guards with `#ifdef`, so syncd must be built against this library | SAI header diff; `VendorSai.cpp` |
| Vendor package recoverable | The syncd layer keeps `var/lib/dpkg/info/mrvllibsai.{list,md5sums}` plus the status stanza. All 144 files are present and md5-identical to the record | md5 check of the extracted layer |
| `mvcpss` | The community `mrvl-prestera` copy (CPSS 4.3.13, gitlink `5607a8b7cd`) builds on 7.0 unchanged. Its ioctl header matches the vendor's, and the vendor itself pairs a 4.3.12 module with 4.5.4 userland. The vendor's own copy does not build on 7.0 | Kbuild in a container against 7.0 |
| CPLD driver | `x204y-48gt.c` builds on 7.0 after a two-line change (i2c `probe`/`remove` signatures). The shipped module has three attributes absent from the public source: `device_type`, `fan_num`, `poe_percent` | Kbuild; module strings |
| Device tree | The vendor's dtb uses Marvell SDK bindings (`ac5-gpio`, `ac5-wd`, `mv_dma`, `ac5-pcie`) that even the vendor's 6.1 kernel has no drivers for. A mainline-binding DTS builds cleanly; every `dtbs_check` finding also appears on mainline boards (the RD board's, plus the undocumented `marvell,reg-init` that CN9130 ClearFog also uses) | `vmlinuz` strings; `dtbs_check` |
| Kernel readiness | The arm64 initrd already carries `sdhci-xenon-driver`, `sdhci-pltfm` and `mmc_block` (`MODULES=most`); `SERIAL_8250_DW=y`; `MODULE_SIG_FORCE` is off | `lsinitramfs`; kernel config |

## 4. Branch and Commit Structure

Commits are GPG-signed, in this order:

1. **Verbatim import — firmware.** Device directory `device/asterfusion/arm64-asterfusion_cx204y_48gt_d-r0/` (all four SKUs) from `fs.squashfs`; `asterProcess/`, the systemd unit, `sensors`, `platform_api_mgnt.sh` and `asterfusion_x204y_48gt_sensors.py` from the platform deb; `sonic_platform/*.py` unpacked from its wheel. Excluded: `rsmu_ctl`, both `.ko` files, the wheel itself. The commit message records the firmware md5 and each file's path inside the installer.
2. **Verbatim import — `asternos_patches@105a124`.** Only what the firmware lacks: `x204y-48gt.c`, `x204y-48gt.h`, the module `Makefile`, `setup.py`.
3. **Verbatim import — Linux v7.0.** `ac5-98dx25xx.dtsi`, `ac5-98dx35xx.dtsi`, and the `arm-gic.h`, `irq.h`, `gpio.h` dt-bindings headers.
4. **Adaptations**, one topic per commit (§5).

Files keep the layout of `asternos_patches` under `platform/marvell-prestera/sonic-platform-asterfusion/x204y-48gt/`, so each verbatim commit can be compared directly against its source.

## 5. Components

| Unit | Location | Role | Depends on |
|---|---|---|---|
| A. Device directory | `device/asterfusion/arm64-asterfusion_cx204y_48gt_d-r0/` | Port map, HwSKUs, `sai.profile`, buffer/QoS templates | Firmware import |
| B. Platform source package | `platform/marvell-prestera/sonic-platform-asterfusion/` | One source package, two debs. **B1** (lazy, CX204Y only): `x204y-48gt.ko`, `mvcpss.ko`, the `sonic_platform` wheel, `asterProcess` and its unit. **B2** (installed at image build): the dtb in `/boot`, because GRUB reads it before first boot completes | `mvcpss` source copied at build time from the `mrvl-prestera` submodule, as `sonic-platform-marvell` does; linux-sonic `7.0.0-1002` headers |
| C. DTS | `dts/` inside B | Board DTS plus the verbatim mainline dtsi; built with `cpp` + `dtc` (present in the Resolute slave) | The board DTS carries the SONiC-only nodes (`prestera`, SMC watchdog, `ac5-ehci`); the dtsi stays unmodified |
| D. Build rules | `platform/marvell-prestera/*.mk`, `build_debian.sh` | arm64 `TARGET_BOOTLOADER = grub`; drop the Nokia and RD includes; `one-image.mk` installs B1 and B2 only; syncd image moves to the Resolute base in place, as Broadcom did; the zboot → gzip step extends from `vs` to `vs` or `marvell-prestera` (not all arm64: nvidia-bluefield's BFB needs the PE kernel) | arm branch |
| E. Installer | `platform/marvell-prestera/platform_arm64.conf` (replaced), `installer/default_platform.conf` | The platform file overrides only `demo_install_uefi_grub`: `grub-install --no-nvram`, then `fw_setenv` sets `efi_image`, `bootefi` and `bootcmd` in place of `efibootmgr`. The shared file gains an optional `GRUB_DEVICETREE`; when set, the menu entry adds a `devicetree` line, and other platforms are unaffected | ONIE's `fw_setenv` and `/etc/fw_env.config` |
| F. Binary hook | `sai.mk`, restore script, stub package | §6 | — |

Boot flow:

```
U-Boot (bootcmd=run bootefi) → GRUB on the ESP → devicetree + gzip Image + initrd (sdhci-xenon)
  → systemd → x204y_48gt-platform-init.service (asterProcess)
       ├─ modprobe mvcpss, x204y-48gt, optoe …
       └─ instantiate optoe2 on the SFP mux channels
  → pmon installs the sonic_platform wheel → syncd loads the SAI
```

`asterProcess` creates the i2c muxes and EEPROM with `new_device`, but the DTS already declares them. An adaptation commit removes those entries and keeps only the SFP `optoe2` ones. DTS aliases pin the bus numbers to the vendor's, so platform paths (`6-0040`, `7-0050`, buses 10–13) are unchanged.

## 6. Binary Dependency

SONiC's established pattern keeps binaries out of git: a `.mk` file pins a version and download URL (`SONIC_ONLINE_DEBS`), and an empty-by-default variable lets builders point at an alternate source (Mellanox `MLNX_SDK_ASSETS_BASE_URL`, nvidia-bluefield `SDK_ASSETS_BASE_URL`). This design follows that pattern.

- **Override switch.** `sai.mk` keeps the community `mrvllibsai 1.17.1-13` as its default, so the build always completes. Setting `MRVL_SAI_ASSETS_BASE_URL` and `MRVL_SAI_ASSETS_VERSION` in `rules/config.user` switches to another deb. syncd is then built against it, which settles the two missing optional functions. The include order of `config.user` and `sai.mk` must be confirmed during implementation.
- **Restore script (committed; reads data only, never runs vendor code).** Input: an AsterNOS `.bin`. Steps: verify the installer's payload sha1; unpack `fs.zip` and the zstd `dockerfs`; locate the layer holding the `mrvllibsai` dpkg record; collect the files from `.list`; verify every file against `.md5sums`; rebuild the deb from the original status fields. Output: `mrvllibsai_1.16.1-2_arm64.deb`, with name, version and maintainer unchanged. Any missing file or md5 mismatch is a hard error.
- **Python stub, packaged separately.** A small source package in this repository builds `libpython3.11.so.1.0`, whose 18 functions abort with their name if ever called. It joins syncd's build dependencies and container only when the override is set. It is needed at build time because syncd's configure links `-lsai`, and the linker must resolve the library's `NEEDED` entry.
- **Storage.** The deb's hosting location is deferred; the design does not depend on it.

Every other artifact is built from source.

## 7. Known Gaps

| Gap | Effect | Handling |
|---|---|---|
| Public CPLD source lacks `device_type`, `fan_num`, `poe_percent` | `asterProcess` writes fail; `sensors` cannot read the fan count | Request the current source from Asterfusion under GPL. Meanwhile ensure the failed writes do not stop the service; guard them if they do |
| Community SAI lacks the CX204Y ASK XML | With the default SAI, syncd does not initialize on the CX204Y | Expected; internal testing uses the override |
| PoE manager `API_BT_Share_workspace` and PTP tool `rsmu_ctl` are binary-only | No PoE or PTP on SKUs that have them | Not imported; 48GT-M-S unaffected |
| Firmware `default_sku` is `CX204Y-48GT-M-SWP4` (PoE SKU) | A non-PoE unit boots with the PoE SKU; port maps are identical | Decide after reading the unit's EEPROM: change the default or port `sku_setup` |
| ONIE platform name, ONIE GRUB fragment (`50_onie_grub`), `fw_env.config`, ESP mount point | Installer assumptions may not hold | Settle from the hardware survey; the installer must fail loudly, never install half-way |

## 8. Verification

**Stage 0 — offline (x86 host).** Build both modules against 7.0 headers; build the dtb and run `dtbs_check`; run the restore script on the firmware and confirm all 144 md5s pass and `dpkg-deb -c` matches `.list`; repeat the qemu-user load test with the restored deb plus the stub package; syntax-check the installer; boot QEMU + U-Boot `qemu_arm64` through `bootefi` → GRUB `devicetree` (virt dtb as stand-in) → gzip Image → initrd.

**Stage 1 — native arm64 build (vera or a testflinger host).** Build `PLATFORM=marvell-prestera PLATFORM_ARCH=arm64` twice: default SAI, and override on. Check that `fs.zip` `boot/` holds the gzip kernel and the CX204Y dtb; the modules' vermagic is `7.0.0-1002-sonic`; the syncd image is Resolute-based; and with the override, syncd omits the two optional functions and the stub is in the container.

**Stage 2 — hardware.**
1. Survey in ONIE before installing: `onie-sysinfo -p`, `fw_printenv` (save the full U-Boot environment first, since `bootcmd` will change), `/etc/fw_env.config`, GRUB version, ESP mount, `sgdisk -p /dev/mmcblk0`, the EEPROM SKU. Use the results to close §7.
2. Install and boot: serial log; eMMC, USB, management port, i2c muxes and RTC probe; `mvcpss` and `x204y-48gt` load; the platform service starts; `show platform` reports fans, PSU, temperatures and SFP presence.
3. With the vendor SAI: syncd starts, the 48 × 1G and 4 × 25G ports come up, basic L2 and L3 forwarding works.
4. Recovery: ONIE rescue, the original AsterNOS `.bin`, and the saved U-Boot environment.

**Milestone.** Stages 0 and 1 pass; on hardware the image installs from ONIE, boots into SONiC, shows platform devices, and forwards with the vendor SAI. Until hardware is available, the milestone ends at Stage 1.

## 9. Provenance

| Source | Identifier |
|---|---|
| AsterNOS firmware | `AsterNOS-Campus-V6.1R006P002-arm64.bin`, md5 `baa645bd66b2fd922064707ce81139a4`, payload sha1 `4a8dc1d145fa3939d8c45f941a3f74b3ebb21d52` |
| Asterfusion patches | `github.com/asterfusion/asternos_patches` branch `202311`, commit `105a124a61b639db9299794d79838f111aca4dd7` |
| Linux | `linux-7.0.tar.xz` from kernel.org, sha256 `bb7f6d80b387c757b7d14bb93028fcb90f793c5c0d367736ee815a100b3891f0` |
| CPSS kernel module | submodule `platform/marvell-prestera/mrvl-prestera` at `5607a8b7cd65cd4892a4fdcf7101ca13c214e48a` (CPSS_4.3.13_016) |
| Base branch | `feat/resolute-arm64-vs` at `d3b6c4c08b25ead9f744fd7ca724e2cfd1110441` |
