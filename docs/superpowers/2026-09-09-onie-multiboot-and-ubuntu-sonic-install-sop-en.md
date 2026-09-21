# ONIE multi-boot mechanics and an Ubuntu SONiC installation SOP

**Date**: 2026-09-09
**Applies to**: x86_64 UEFI whitebox switches (validated here on a Dell EMC S5232F-ON, `x86_64-dellemc_s5232f_c3538-r0`)
**Sources**: the actual 2026-07-26 working session on dut02 (423 commands) plus `installer/default_platform.conf`
**Relationship to other docs**: the [2026-07-26 validation report](2026-07-26-dut02-s5232f-validation-report-en.md) records *what we did*; this document records *how the mechanism works* and *how to do it next time*.

---

# Part 1 · Background: how ONIE supports multi-boot

ONIE is often mistaken for "a USB stick that installs the box". It is in fact a **permanently resident, firmware-level boot environment** — it does not go away once a NOS is installed. Boot decisions on the machine are spread across **four layers**, each with its own notion of a default entry and its own one-shot override, and none of them aware of the others. Nearly every boot incident comes from changing one layer while believing you changed the whole system.

```
┌─ Layer 0  UEFI NVRAM ──────────────────────────────────────┐
│  BootOrder / BootNext / BootCurrent                        │
│  each entry = (partition PARTUUID, path to an EFI binary)  │
└───────────────┬────────────────────────────────────────────┘
                │ firmware loads some grubx64.efi
┌───────────────▼─ Layer 1  each loader's entry grub.cfg ────┐
│  ESP (sda1) /EFI/{onie,UBUNTU-NOS,SONIC-OS,debian}/        │
│  ⚠ /EFI/debian/grub.cfg is a shared entry point several    │
│    NOSes fight over                                        │
└───────────────┬────────────────────────────────────────────┘
                │ configfile jumps to a partition's full grub.cfg
┌───────────────▼─ Layer 2  the NOS's own grub menu ─────────┐
│  saved_entry (sticky) / next_entry (one-shot) / onie_entry │
└───────────────┬────────────────────────────────────────────┘
                │ if the selected entry is SONiC
┌───────────────▼─ Layer 3  SONiC's dual image slots ────────┐
│  /host/image-<ver>/ ; sonic-installer list/set-default     │
└─────────────────────────────────────────────────────────────┘
```

## Layer 0 · UEFI NVRAM

The firmware holds an ordered table of boot entries. Measured on dut02 after both OSes were installed:

```
BootCurrent: 0006
BootOrder: 0006,0000,0004,0005,0001,0002,0003
Boot0000* UBUNTU-NOS  HD(1,GPT,b966357b-…,0x800,0x80000)/File(\EFI\UBUNTU-NOS\grubx64.efi)
Boot0004* ONIE: Open Network Install Environment
                      HD(1,GPT,b966357b-…,0x800,0x80000)/File(\EFI\ONIE\GRUBX64.EFI)
Boot0005* EDA-DIAG    HD(1,GPT,40f9e57a-…,0x800,0x40000)/File(\EFI\EDA-DIAG\GRUBX64.EFI)
Boot0006* SONiC-OS    HD(1,GPT,b966357b-…,0x800,0x80000)/File(\EFI\SONIC-OS\GRUBX64.EFI)
```

Note that `Boot0005` carries a **different** PARTUUID from the other three — EDA-DIAG lives on the ESP of a separate eMMC (`mmcblk0`), not on `sda1`. Shrinking or repartitioning `sda` therefore cannot touch it, which also makes it an ideal image staging area.

Operations:

| Goal | Command |
|---|---|
| Change the sticky order | `efibootmgr -o 0006,0000,0004,0005,…` |
| Boot a given entry once | `efibootmgr -n 0000` |
| Create an entry | `efibootmgr -c -d /dev/sda -p 1 -L "UBUNTU-NOS" -l "\\EFI\\UBUNTU-NOS\\grubx64.efi"` |
| Delete an entry | `efibootmgr -b 0000 -B` |

⚠️ **`onie-nos-install` mutates this layer.** After installing the official SONiC image, the entire `Boot0000 UBUNTU-NOS` entry was gone (the `sda3` partition and filesystem were untouched — only the NVRAM entry disappeared). The ONIE installer does contain logic that clears EFI variables by volume label (`create_demo_uefi_partition()` iterates `efibootmgr | grep -e "$demo_volume_label" -e "$legacy_volume_label"` and deletes them with `-B`), but `UBUNTU-NOS` should not match `SONiC-OS`; a likelier culprit is the uninstall stage ONIE runs before installing (`onie/tools/lib/onie/onie-uninstaller-common`) cleaning up "old NOS" boot entries. **We never pinned down the exact line**, so the operational rule is not "understand it" but: **always check `efibootmgr` after installing, and recreate with `-c` / reorder with `-o` if something is missing.**

## Layer 1 · The entry grub.cfg, and the fight over `/EFI/debian`

Every `grubx64.efi` has a `prefix` compiled into it that decides where it reads its configuration from. The Debian-family convention — which includes Ubuntu *and* SONiC — is **`/EFI/debian`**. The ESP on dut02:

```
/EFI/onie/grubx64.efi
/EFI/UBUNTU-NOS/grubx64.efi
/EFI/SONiC-OS/grubx64.efi
/EFI/debian/grub.cfg          ← only one copy, shared by all of them
```

SONiC's ONIE installer **unconditionally overwrites** that shared entry point (`installer/default_platform.conf:567-579`; the comment in the source literally reads "Make a first grub config file that located in default debian path"):

```sh
cat <<EOF > $tmp_config
search --no-floppy --label --set=root $demo_volume_label   # SONiC-OS
set prefix=(\$root)'/grub'
configfile \$prefix/grub.cfg
EOF
mkdir -p /boot/efi/EFI/debian/
cp $tmp_config /boot/efi/EFI/debian/grub.cfg
```

**Consequence**: once SONiC is installed, even if the firmware boots `Boot0000 (UBUNTU-NOS)`, that `grubx64.efi` reads `/EFI/debian/grub.cfg`, which now says `search --label SONiC-OS` — so it lands in SONiC's grub on `sda4`. **The entry you picked at layer 0 does not necessarily determine which OS you end up in.** This is the least intuitive property of a dual-NOS box.

(`Boot0005 EDA-DIAG` is immune: its grubx64.efi lives on the other disk's ESP and its prefix does not point into `sda1`.)

## Layer 2 · The NOS grub's three jump variables

The `/host/grub/grub.cfg` SONiC generates opens with this block (`installer/default_platform.conf:521-537`):

```sh
if [ -s $prefix/grubenv ]; then load_env; fi
if [ "${saved_entry}" ]; then set default="${saved_entry}"; fi
if [ "${next_entry}" ]; then
    set default="${next_entry}"; unset next_entry; save_env next_entry
fi
if [ "${onie_entry}" ]; then
    set next_entry="${default}"          # remember where we were headed
    set default="${onie_entry}"          # go to ONIE this time
    unset onie_entry; save_env onie_entry next_entry
fi
```

The three variables mean different things:

| Variable | Meaning | Written by |
|---|---|---|
| `saved_entry` | sticky default | `grub-set-default` |
| `next_entry` | one-shot, cleared once consumed | `grub-reboot` / `grub-editenv … set next_entry=` |
| `onie_entry` | one-shot boot into ONIE, **and automatically arranges to come back next time** | SONiC's "reboot into ONIE" path |

The Ubuntu NOS side works the same way via `next_entry`. Its grub root is **`/grub/`**, not `/boot/grub/` (because `root=LABEL=UBUNTU-NOS` and the grub directory sits at the partition root):

```bash
sudo grub-editenv /grub/grubenv set next_entry=ONIE && sudo reboot
```

Its menu has three entries, the last two of which chainload:

```
menuentry 'Ubuntu NOS 1.0.0'   → linux /boot/vmlinuz root=LABEL=UBUNTU-NOS …
menuentry 'EDA-DIAG'           → chainloader /EFI/EDA-DIAG/grubx64.efi   (hd2,gpt1)
menuentry ONIE                 → chainloader /EFI/onie/grubx64.efi       (hd0,gpt1)
```

⚠️ **Two traps that actually bit us:**

1. **`save_env` could not write back on this machine's ext4.** After setting `next_entry=ONIE` and booting into ONIE, the variable was **not consumed**, meaning every subsequent reboot would land in ONIE again with no way back to Ubuntu. grubenv is a fixed **1024-byte** format (25-byte header plus `#` padding) and cannot be edited line-wise. The fix at the time was to mount `sda3` read-write from inside ONIE, back up the file, and **rewrite a clean empty grubenv block wholesale**.
2. **A leftover `onie_entry` makes the boot destination disagree with the `BootNext` you set.** We set `efibootmgr -n 0000` (Ubuntu) and landed in ONIE, with `BootCurrent` genuinely reporting `0000`. The cause was a stale `onie_entry` in the grubenv at the *end* of the chain, on `sda4`. No amount of statically reading grub.cfg explains this — **you have to watch one real boot over the console**, which is the only way to observe the layer-1/layer-2 interaction.

## Layer 3 · SONiC's dual images

SONiC keeps multiple images side by side as directories inside its own `sda4` (`/host`, label `SONiC-OS`):

```
/host/image-202605.1174613-ec1bb42e4/
/host/image-202605_resolute_sheldon.0-1d988dec/
```

```
$ sudo sonic-installer list
Current: SONiC-OS-202605.1174613-ec1bb42e4          ← running now
Next:    SONiC-OS-202605_resolute_sheldon.0-1d988dec ← next boot
Available: …
```

**Why only two images survive** has an exact answer in the source. `sonic-installer install` takes the `install_env = "sonic"` branch, and when it builds the new grub.cfg it lifts only the menuentry of the image **currently running** out of the old one (`installer/default_platform.conf:552-555`):

```sh
old_sonic_menuentry=$(cat /host/grub/grub.cfg | sed "/^menuentry '${demo_volume_label}-${running_sonic_revision}'/,/}/!d")
onie_menuentry=$(cat /host/grub/grub.cfg | sed "/menuentry ONIE/,/}/!d")
```

The new grub.cfg is: new image entry + `$old_sonic_menuentry` + `$onie_menuentry`. A third image's menuentry simply falls outside what gets lifted, so it **disappears silently**. The same snippet explains why the ONIE entry survives arbitrarily many `sonic-installer install` runs — it is explicitly lifted and carried forward.

The same `install_demo_os()` function is reused across three scenarios (`install_env` = `onie` / `sonic` / `build`): a first install from ONIE, an install from a running SONiC, and generation at build time. Only the `install_env = "onie"` branch appends ONIE's own grub fragment `$onie_root_dir/grub.d/50_onie_grub` to the menu — **that is how the ONIE menuentry originally enters SONiC's grub**, after which the `sed` above propagates it from generation to generation.

> The only difference on the resolute branch is the kernel filename: `installer/default_platform.conf:599,604` use `vmlinuz-7.0.0-1002-sonic` / `initrd.img-7.0.0-1002-sonic` (upstream is `vmlinuz-6.12.41+deb13-sonic-${arch}`). Note that Ubuntu's ABI string carries no arch suffix.

## ONIE's own mode machine

ONIE lives permanently on `sda2` (label `ONIE-BOOT`, 128 MB, ext4) with its own grub and five menu entries:

```
onie_menu_install    "ONIE: Install OS"
onie_menu_rescue     "ONIE: Rescue"
onie_menu_uninstall  "ONIE: Uninstall OS"
onie_menu_update     "ONIE: Update ONIE"
onie_menu_embed      "ONIE: Embed ONIE"
set fallback="${onie_menu_rescue}"
```

Which one is chosen is decided by two grubenv variables (the comment below is quoted from the grub.cfg on `sda2`):

```sh
if   [ "$onie_mode" = "install"   ] ; then set default="${onie_menu_install}"
elif [ "$onie_mode" = "uninstall" ] ; then set default="${onie_menu_uninstall}"; reset_onie_mode
elif [ "$onie_mode" = "update"    ] ; then set default="${onie_menu_update}"
elif [ "$onie_mode" = "embed"     ] ; then set default="${onie_menu_embed}"
elif [ "$onie_mode" = "rescue"    ] ; then set default="${onie_menu_rescue}";    reset_onie_mode
elif [ "$onie_mode" = "diag"      ] ; then set default="${diag_menu}";           reset_onie_mode
else
   if [ "$onie_nos_mode" = "yes" ] ; then set default="${onie_menu_rescue}"; fi   # a NOS is installed
fi
```

Precedence: `onie_mode` (one-shot; `uninstall`/`rescue`/`diag` clear themselves via `reset_onie_mode`) > `onie_nos_mode` (sticky marker) > default install. The chosen mode reaches ONIE's initramfs on the kernel command line as `boot_reason=$onie_boot_reason`.

**dut02 measured `onie_nos_mode=yes`** — on a box that already has a NOS, entering ONIE lands in **Rescue**, and it will not go install something off the network. That is desirable (no accidental wipes), but it means you cannot assume "reboot into ONIE" starts an installation.

ONIE's own mode tools live in `/mnt/onie-boot/onie/tools/bin/`: `onie-boot-mode`, `onie-nos-mode`, `onie-fwpkg`, `onie-fw-version`, `onie-version`. SONiC itself calls `onie-boot-mode -q -o install` when installing a DIAG partition (`default_platform.conf:546`).

**What the rescue environment gives you** (measured on dut02, ONIE 3.40.1.1-9 / kernel 4.9.30-onie+): it starts `dropbear` and `udhcpc`, DHCP hands it the **same** mgmt IP as the normal system, and `root` logs in over SSH with an **empty password** — far more reliable than the serial console. But:

- `PATH` is only `/usr/bin:/bin`, while `resize2fs`/`e2fsck`/`sgdisk`/`parted`/`partprobe` all live in `/usr/sbin`, so you **must** `export PATH=/usr/sbin:/sbin:/usr/bin:/bin`
- `reboot` is at `/sbin/reboot`, also outside PATH
- there is no `grub-editenv` and no `strings`
- dropbear emits a wall of security warnings on every command; scripts need `grep -vE "WARNING:|vulnerable|decrypt later|…"`

**Do not guess.** Before entering ONIE, unpack its initrd and see exactly what is in there:

```bash
xzcat onie-initrd.xz | cpio -t | grep -E "resize2fs|e2fsck|sgdisk|parted|dropbear|udhcpc"
xzcat onie-initrd.xz | cpio -idm && grep "^root" etc/shadow    # confirm the empty password
```

## "Boot into X next time" quick reference

| Destination | Where to do it | How |
|---|---|---|
| Another EFI entry (once) | any OS | `efibootmgr -n <NNNN>` |
| Another EFI entry (sticky) | any OS | `efibootmgr -o <new order>` |
| ONIE (once) | Ubuntu NOS | `grub-editenv /grub/grubenv set next_entry=ONIE` |
| ONIE (once, auto-return) | SONiC | set `onie_entry` (layer-2 logic fills `next_entry` for you) |
| Another SONiC image (sticky) | SONiC | `sonic-installer set-default <ver>` |
| ONIE in Install rather than Rescue | ONIE / NOS | `onie-boot-mode -o install`, or pick it in the ONIE menu |

**Always troubleshoot outside-in**: `efibootmgr` for `BootCurrent` → what `/EFI/debian/grub.cfg` points at → whether the target partition's grubenv holds a stale `next_entry`/`onie_entry` → and only then the NOS internals. Any layer can override the intent of the one above it. **When static analysis does not add up, watch one real boot on the console instead of continuing to guess.**

---

# Part 2 · Installation SOP

Scenario: a production switch that already runs somebody else's NOS with a full disk, onto which a self-built Ubuntu SONiC must be installed **without destroying the existing system**, keeping a rollback path.

> Placeholders throughout: `<DUT-MGMT-IP>`, `<PW>`, `<CONSOLE-SERVER>`, `<CONSOLE-PW>`, `<sda3-PARTUUID>`. Substitute before running.

## Stage 0 · Reconnaissance (questions to answer before installing anything)

1. **Does the image match the platform?** Verify offline by unpacking the `.bin`, not after installing:
   ```bash
   sed -e '1,/^exit_marker$/d' sonic-xxx.bin | tar -xO installer/platforms_asic | grep -i <platform keyword>
   grep -a -m2 -oE "payload_sha1=[a-f0-9]+|image_version=[^\"]*" sonic-xxx.bin
   ```
2. **What does the boot chain look like?** `efibootmgr -v`; mount `sda1` read-only and inspect `/EFI/*`; mount `sda2` read-only and read ONIE's grub.cfg and grubenv (`onie_nos_mode`).
3. **Can you get into ONIE rescue, and what is in there?** Pull the initrd locally and `cpio -t` it (see above).
4. **What on the existing system is irreplaceable?** Things that exist only on the disk and cannot be re-fetched from any repository. On dut02 that was the `switchdevd` binary and the `libsaibcm 11.2` `.deb`.
   ```bash
   tar czf preserve.tar.gz /usr/share/sonic/platform /usr/sbin/switchdevd \
       /etc/machine.conf /etc/netplan /etc/frr /var/lib/cloud/instance/user-data.txt
   # plus text snapshots of dpkg -l / sgdisk -p / ip route / systemctl list-unit-files
   ```
5. **Does the existing system rewrite the disk at boot?** cloud-init's `growpart` + `resizefs` (`frequency: always`) will **re-expand the root partition to fill the whole disk on every boot**. Check `/etc/cloud/cloud.cfg` and `/var/log/cloud-init.log`. This single fact dictates the ordering in stage 2.

## Stage 1 · Stage the image

Put it on storage **unrelated to the disk you are about to modify**. On dut02 that was the EDA-DIAG partition of the separate eMMC:

```bash
sudo mount /dev/mmcblk0p2 /mnt/eda && sudo mkdir -p /mnt/eda/sonic-staging
scp sonic-xxx.bin admin@<DUT-MGMT-IP>:/mnt/eda/sonic-staging/
ssh … 'sha1sum /mnt/eda/sonic-staging/*.bin'      # compare both ends
```

Two benefits: neither the shrink nor the install ever touches it, and it lets you recover for free when an image is later evicted by `sonic-installer`. ⚠️ It needs remounting with `mount /dev/mmcblk0p2 /mnt/eda` after every reboot.

## Stage 2 · Shrink + dual-boot, inside a single ONIE session

**The ordering is non-negotiable: the shrink and the install must complete within one ONIE session, with no reboot back into the original system in between.** Otherwise `growpart` undoes the shrink on that reboot and the work is wasted (non-destructively — just wasted). Let the new partition be created immediately after the old one so it **physically blocks the space growpart would expand into**.

```bash
# one-shot jump into ONIE from the original system
sudo grub-editenv /grub/grubenv set next_entry=ONIE && sudo reboot

# ONIE rescue: SSH as root with an empty password, same mgmt IP
export PATH=/usr/sbin:/sbin:/usr/bin:/bin
grep sda3 /proc/mounts || echo "sda3 unmounted, safe to touch"
e2fsck -fy /dev/sda3
resize2fs /dev/sda3 2621440                    # 2621440 × 4K = 10 GiB
sgdisk -d 3 /dev/sda
sgdisk -n 3:788480:21762047 -t 3:8300 -c 3:UBUNTU-NOS -u 3:<sda3-PARTUUID> /dev/sda
partprobe /dev/sda
```

**None of the four `sgdisk -n` arguments is optional**: the start sector (must equal the original), the partition name, the type code, and the PARTUUID. Deleting and recreating without them yields a brand-new partition, and anything addressing it by PARTUUID breaks. dut02's boot chain addresses everything by **LABEL** (`/EFI/debian/grub.cfg` → `search --label` → `root=LABEL=UBUNTU-NOS`), and `resize2fs` preserves the filesystem label, so it was unaffected — **but that is a property of this machine, not a general rule; confirm how your target addresses things first.**

Verification (all four must pass before proceeding):

```bash
sgdisk -v /dev/sda                                              # GPT self-check
sgdisk -i 3 /dev/sda | grep -iE "unique GUID|name|First sector" # all three identifiers
blkid /dev/sda3                                                 # LABEL/UUID still there
e2fsck -fn /dev/sda3                                            # read-only recheck
```

## Stage 3 · Install

```bash
mount /dev/mmcblk0p2 /mnt/eda
sha1sum /mnt/eda/sonic-staging/sonic-xxx.bin        # last checksum before committing
onie-nos-install /mnt/eda/sonic-staging/sonic-xxx.bin
```

The box reboots into the new system automatically. **Run three checks immediately:**

```bash
sudo sgdisk -p /dev/sda | grep -E "^ *[0-9]"        # ① no gap between sda3 and sda4 — the only proof the approach holds
sudo dumpe2fs -h /dev/sda3 | grep -i "Filesystem state"   # ② the old system's fs is clean
sudo efibootmgr                                      # ③ is the old system's EFI entry still there?
```

③ will most likely be **gone** (see the warning under layer 0). Recreate and reorder:

```bash
sudo efibootmgr -c -d /dev/sda -p 1 -L "UBUNTU-NOS" -l "\\EFI\\UBUNTU-NOS\\grubx64.efi"
sudo efibootmgr -o 0006,0000,0004,0005,0001,0002,0003      # new NOS first, original second
```

**Prove on real hardware that the original system still boots** — this is the only evidence that the operation was non-destructive; the partition table alone does not prove it:

```bash
sudo efibootmgr -n 0000 && sudo reboot
```

Then **watch the console** to see where it actually goes. This step is exactly where we caught a "set Ubuntu, landed in ONIE" case caused by a stale `onie_entry`, which static analysis could not have revealed. Once inside, confirm `growpart` is genuinely blocked:

```bash
sudo sgdisk -p /dev/sda | tail -4                   # partition still 10G
sudo dumpe2fs -h /dev/sda3 | grep "Block count"     # fs still 2621440
sudo grep -iE "growpart|resize" /var/log/cloud-init.log | tail
# expected: cc_resizefs did run, but resize2fs was a no-op
```

## Stage 4 · Transfer the self-built image over a high-latency link

A single scp stream collapses on a 373 ms RTT path with packet loss (bursts to 2.6 MB/s, sustains 0.25 MB/s; 2 GB takes 1–2 hours). **Four parallel streams, per-chunk retry, and size-based resume** aggregate to ~3.8 MB/s, so 2 GB takes about 30 minutes:

```bash
split -d -b 548M target/sonic-broadcom.bin ~/rparts/rpart-

push(){ local f=$1 sz=$(stat -c%s ~/rparts/$f)
  for t in 1 2 3 4 5 6; do
    have=$(ssh $H "stat -c%s /host/staging/$f 2>/dev/null"); have=${have:-0}
    [ "$have" -ge "$sz" ] && { echo "$f DONE"; return 0; }   # never resend a finished chunk
    scp $SSHOPT ~/rparts/$f $H:/host/staging/$f && return 0
    sleep 4
  done; return 1; }

for f in rpart-00 rpart-01 rpart-02 rpart-03; do push $f & done; wait
ssh $H 'cd /host/staging && cat rpart-0{0,1,2,3} > image.bin && rm -f rpart-* && sha1sum image.bin'
```

`ServerAliveInterval=15 ServerAliveCountMax=8` in `SSHOPT` is mandatory; without it a stalled stream is never declared failed. The reverse direction (switch → build host) is even slower — use `ssh + dd skip_bytes` to resume:

```bash
HAVE=$(stat -c%s "$LOCAL"); ssh $H "dd if=$REMOTE bs=1M skip=$HAVE iflag=skip_bytes" >> "$LOCAL"
```

## Stage 5 · Install the second SONiC image

```bash
sudo sonic-installer list                        # ⚠ first confirm which image is about to be evicted
df -h /host                                      # enough space?
yes | sudo sonic-installer install /host/staging/image.bin
sudo sonic-installer list                        # both images present, Next = the new one
sudo reboot
```

Three known failure modes:

- **Only two images are kept.** Installing a third makes the oldest non-current image **disappear silently** (source-level reason under layer 3). On dut02 this is how the official reference image and its GRUB entry were lost — recovery was free only because the `.bin` was still staged on the eMMC.
- **A dangling `/etc/resolv.conf` makes the install fail in `migrate_sonic_packages`**, which does `cp /etc/resolv.conf` into the new image's chroot.
- `sonic-installer install` copies `/etc/sonic` to `/host/old_config` and the new image migrates it on first boot — **so configuration parity comes for free in an A/B comparison**, a property worth exploiting deliberately.

Rollback: `sudo sonic-installer set-default <old version>` and reboot.

## Stage 6 · Acceptance

```bash
sudo sonic-installer list | grep Current
uname -r; grep VERSION= /etc/os-release          # confirm the new image is really the one running
show interfaces status | head
sudo docker ps --format '{{.Names}}' | wc -l
show system-health detail | grep -A2 Services    # use this; do not count grep -c OK
```

To judge whether the ASIC came up (Broadcom): `bcmcmd "cancun stat"` and check that CIH/CMH/CCH/CEH/CFH are `LOADED`; `redis-cli -n 1 keys "ASIC_STATE:SAI_OBJECT_TYPE_PORT:*" | wc -l` for port objects.

**A forensic trap across images**: `/var/log` is a loop-mounted filesystem **shared between images**, so historical counts in `syslog`/`audit.log` are not evidence about the image currently running.

---

## Appendix · Provenance

- Working session: `~/.claude/projects/-home-sheldon-qi-sonic-buildimage/3a4812fc-94ff-4203-b4c4-fae5331ca491.jsonl` (2026-07-26 02:33 → 07-27 14:17, 423 Bash calls); the preceding crashed session is `c44da5c8-…`
- grub generation logic: `installer/default_platform.conf:465-639` (entry cfg `567-579`, the three variables `521-537`, dual images `552-555`, ONIE fragment `608-611`, resolute kernel paths `599/604`)
- ONIE mode machine: `/grub/grub.cfg:175-230` on the target's `sda2`, plus `onie/tools/`
- Related memories: `lab-switch-onie-install-official-202605`, `lab-switch-10-240-36-51-provenance`, `resolute-lab-switch-sai-swap-incident`
