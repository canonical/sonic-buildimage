# Validating the self-built resolute SONiC on Dell S5232F, fixing an FRR build defect, and configuring it as a fabric node

**Date**: 2026-07-26
**Target device**: `<DUT-MGMT-IP>` (Dell EMC S5232F-ON, BCM56873 / Trident3, platform `x86_64-dellemc_s5232f_c3538-r0`)
**Constraint**: This is someone else's maintained lab switch (Henry Mao / Canonical, deployed via cloud-init + PPA `henrymao/ubuntu-nos`). All work was non-destructive and kept a rollback path to the maintainer's original system.

---

## 0. Background and the core question

Continuing from a prior session (`c44da5c8`) that had crashed on context overflow. The user's original core question was:

> **Can the locally-built `sonic-broadcom.bin` actually run on this hardware?**

Answering it drove a full end-to-end arc: CANCUN pre-research → control experiment with the official image → shrink + dual-boot to preserve the maintainer's system → install the official image to get the answer → install the self-built image to answer definitively → fix the resolute FRR build defect → configure dut02 as a policy-complete fabric node using **two methods**.

**Bottom line**: Yes. The self-built resolute SONiC runs fully on this S5232F — ASIC init, hardware forwarding, and BGP all work.

---

## 0.5 Precursor — meaningful work done in the crashed session (c44da5c8)

This work continues that session. Before it crashed, it had completed the following valuable work, which directly shaped the careful approach taken here:

1. **State survey** — determined that `<DUT-MGMT-IP>` is a "half-SONiC" **bare-.deb deployment**: Ubuntu 26.04 Resolute + kernel 7.0.0-1002-sonic + libsaibcm 11.2.30.5 + opennsl 8.4 + sswsyncd + switchdevd + BIRD 3.2.0 running, but **no Docker / /etc/sonic / sonic-cfggen / CLI**. Not ONIE-installed, but cloud-init + `firstboot.sh` + PPA `henrymao/ubuntu-nos`.

2. **First compatibility analysis** — self-built sonic-broadcom.bin vs S5232F: platform `x86_64-dellemc_s5232f_c3538-r0` is in the installer's `platforms_asic`, the ASIC is TD3, `sai.profile` references `td3-s5232f-32x100G.config.bcm`, kernel/OS match; version deltas libsaibcm 15.2↔11.2, opennsl 15.2↔8.4, platform-modules 1.1↔1.8.1. Tentative conclusion "it can run" — but that was **static analysis only, unverified on hardware** (proven on hardware only in §5/§6 here).

3. **Incremental SAI test → switching-fabric incident (key lesson)** — to "verify hardware compat without a reinstall", it installed the self-built opennsl 15.2 + libsaibcm 15.2 kernel modules directly on the **live maintainer's switch**. The opennsl 15.2 kmod itself worked (PCI `14e4:b870` probe, `/proc/bcm/knet` present), but the SAI-trio version mismatch (15.2 lib + non-matching kmod/config) **broke the entire switching fabric** — front-panel ports gone, PortChannel200 NO-CARRIER, `CANCUN CIH: LOAD FAILED`. **This incident directly shaped the careful approach here** (don't touch the running system; run a control experiment with the official image first; shrink + dual-boot to preserve the maintainer's system), and the CANCUN failure it surfaced seeded the §2 CANCUN research.

4. **Recovery** — recovered the original .debs from disk (`/usr/share/sonic/platform/bcm/*.deb`), restored libsaibcm 11.2 + opennsl 8.4; the hostif residue left by the SAI init failure could only be cleared by a reboot.

5. **Provenance investigation** — established how the machine was built (cloud-init + `firstboot.sh` reads `/etc/machine.conf` + PPA installs 6 packages; libsaibcm is in no repo, only the on-disk .deb; ⚠️ `/usr/sbin/switchdevd` is a maintainer-placed custom binary, must never be `apt reinstall`ed).

6. **Config capture + BIRD→FRR migration** — captured the maintainer's full config (topology, BIRD, PortChannel200, BGP), and migrated BIRD 3.2.0 to FRR 10.5.1 (a 1:1 port, including `sender-as-path-loop-detection`, `krt_prefsrc`→`set src`, `redistribute connected` route-maps). **This BIRD/FRR config became the authoritative source for the §8 fabric reproduction here.**

> Lesson (captured in memory `resolute-lab-switch-sai-swap-incident`): before touching someone else's box, answer (1) how the system was installed, (2) where each package came from, (3) where the rollback evidence is; a Broadcom SAI version change must swap libsaibcm + opennsl + platform-modules **as a set**; check disk before repo; a reboot is mandatory after a SAI init failure.

---

## 1. Results at a glance

| Phase | Result |
|---|---|
| CANCUN config.bcm research | Upstream stale bug; the `/default/` fallback saves it on a fresh install (harmless). 23 TD3 files affected, byte-identical to our branch. |
| Official 202605 control experiment | `CANCUN CIH: LOADED 6.15.00`, create_switch OK, 4 ports link up |
| Shrink + dual-boot (approach A) | sda3 shrunk to 10G; sda4 (SONiC) blocks cloud-init growpart; maintainer's Ubuntu boots and is healthy |
| Self-built resolute image | Boots; CANCUN identical to official; 4 ports up; 35 ASIC port objects — **core question = YES** |
| FRR build-defect fix | `dplane_fpm_sonic.so` missing → zebra crash → rebuilt → BGP up, ASIC 215 routes |
| Fabric reproduction (config_db.json) | BGP v4 136 / v6 73 Established, hardware forwarding |
| Configured as T0 (minigraph) | type=ToRRouter, peerT1=LeafRouter, BGP 136/72, role policy, ASIC 214 routes |

---

## 2. Pre-research: the upstream stale CANCUN config.bcm bug

**Symptom / risk**: TD3 `device/*/td3-*.config.bcm` files hardcode line 1 as
`sai_load_hw_config=/etc/bcm/flex/bcm56870_a0_premium_issu/b870.6.4.1/` (the SAI-11.2-era CANCUN version),
while `libsaibcm 15.2` ships only `b870.6.15.0/`.

**Mechanism** (from a 2026-07-25 incident log, SAI 15.2 / SDK 6.5.35 reading 6.4.1 files):
```
CIH: LOAD FAILED   Ver: UNKONWN.00.00.00     <- parser image is strictly bound to the SDK version
CMH/CCH/CEH: LOADED  Ver: 06.04.01           <- other components tolerate cross-version
-> soc_mem_write: invalid index 6 for IP_PARSER1_HFE_CONT_PROFILE_TABLE_4
-> bcm_esw_port_init: Entry not found -> Failed to create switch
```

**Verdict**:
- All **23** TD3 `config.bcm` files point at `b870.6.4.1`, and are **byte-identical** to `sonic-net/master`, `sonic-net/202605`, and `canonical/*` — a pure upstream artifact, not introduced by our branch.
- `libsaibcm` registers `/etc/bcm/flex/**/*.pkg` as **dpkg conffiles** (never removed on upgrade). This exposure only bites the **bare-.deb deployment model** (the maintained box): the old 6.4.1 files persist on disk and are loaded preferentially.
- In a normal SONiC image the syncd container is built from scratch each time and contains only `b870.6.15.0` + a `default` symlink. When config points at the non-existent 6.4.1, libsai.so's fallback (`Cancun files are not available at "%s", loading default`) trims the version segment and falls back to `default/` → 6.15.0 → CIH matches → boots.

This verdict was confirmed on real hardware in phases 4/5 below.

---

## 3. Control-experiment prep: the official 202605 image

Rationale: the official 202605 uses **the same SAI 15.2 pin and the same byte-identical stale config.bcm** as ours, so its behavior on this hardware directly decides whether the CANCUN fallback truly works — a control experiment run **before** flashing our own image.

- **Source**: Azure DevOps `dev.azure.com/mssonic` pipeline id=138 (`Azure.sonic-buildimage.official.broadcom`), branch 202605, latest successful build `20260725.6`, commit `ec1bb42e41`, SAI pin `15.2.0.0.0.0.11.1` (8 patch levels ahead of our `3.1`, but with byte-identical CANCUN payload).
- **Single-file download**: the artifact downloadUrl carries `format=zip`; rebuild the URL with `format=file&subPath=/target/sonic-broadcom.bin` (do not URL-encode the slashes in subPath). 1.08 GB; the installer's own payload sha1 self-check passed.
- **Console path**: `<CONSOLE-SERVER>` is **telnet with two-stage login** — first the console server (`<user>/<CONSOLE-PW>`, which prints "Type the hot key to suspend...<CTRL>Z"), then the switch getty (`<user>/<PW>`). Driver script `~/console.py` (handles telnet IAC negotiation, CR-only line endings, `watch`/`login` modes). Note: the console server allows a single session.
- **BMC**: `<BMC-IP>` IPMI v2 RAKP handshake fails (unusable, but the main line doesn't depend on it — every reboot can be triggered from the OS/ONIE, with console + GRUB as fallback).
- **ONIE**: UEFI has a standalone `Boot0004 = ONIE` entry; ONIE grubenv `onie_nos_mode=yes` → default menu is Rescue (no auto network install). ONIE 3.40.1.1-9, kernel 4.9.30-onie+; rescue starts dropbear (root, empty password) + udhcpc.

---

## 4. Shrink + dual-boot (approach A): preserve the maintainer's Ubuntu

Disk sda (59.6G) was fully consumed by sda1(256M)+sda2(128M)+sda3(59.3G); installing SONiC needs 32G free. We chose **not to wipe the maintainer's Ubuntu**, and instead shrink + dual-boot.

**Gotcha**: the maintainer's Ubuntu is cloud-init-deployed, and `/etc/cloud/cloud.cfg` has `growpart` + `resizefs` (`frequency: always`) — **every boot re-grows sda3 to fill the whole disk**. So "shrink → reboot to Ubuntu to verify → then install" does not work.

**Workaround (approach A, no change to the maintainer's config)**: shrink and install SONiC in a single ONIE session so that sda4 is created immediately after sda3, **physically blocking growpart's growable space**.

**Shrink procedure** (ONIE rescue, SSH `root@<DUT-MGMT-IP>` empty password; tools live in `/usr/sbin` but PATH is only `/usr/bin:/bin`, so export explicitly):
```
e2fsck -fy /dev/sda3
resize2fs /dev/sda3 2621440          # 2621440 x 4K = 10 GiB
sgdisk -d 3 /dev/sda
sgdisk -n 3:788480:21762047 -t 3:8300 -c 3:UBUNTU-NOS \
       -u 3:<sda3-PARTUUID> /dev/sda   # preserve start/name/PARTUUID
```
The UBUNTU-NOS boot chain is entirely LABEL-addressed (ESP `/EFI/debian/grub.cfg` → search --label → `/grub/grub.cfg` → `root=LABEL=UBUNTU-NOS`); resize2fs preserves the label, so the chain is unaffected.

**Backed up the irreplaceable bits** (~57 MB): `/usr/sbin/switchdevd` (a hand-placed custom binary not recoverable from the PPA), the `libsaibcm 11.2.30.5 .deb` (in no repo, only on disk), and all config. Stored locally in `~/dut02-backup/` and on EDA-DIAG.

**Verification (real test-boot)**: cloud-init's `cc_resizefs` **did run**, but `resize2fs` was a no-op (the fs already fills the 10G partition, and growpart can't expand because sda4 is in the way) → sda3 stays 10G. Ubuntu booted cleanly to login; switchdevd/frr active; PortChannel200 UP; BGP recovered. **growpart is empirically blocked by sda4.**

**EFI fix**: onie-nos-install removed the `UBUNTU-NOS` EFI boot entry; recreated it with `efibootmgr` (pointing at the original `\EFI\UBUNTU-NOS\grubx64.efi`), and set BootOrder to SONiC first, Ubuntu second.

**Final partition layout**:
```
sda1 EFI System   256M
sda2 ONIE-BOOT    128M
sda3 UBUNTU-NOS   10G   <- maintainer's system, intact and bootable after shrink
sda4 SONiC-OS     32G   <- immediately after sda3, blocking growpart
(~17G unallocated at the end; mmcblk0 = separate eMMC EDA-DIAG, untouched)
```

---

## 5. Install the official image → the CANCUN answer on hardware

`onie-nos-install /mnt/eda/sonic-staging/sonic-broadcom-202605-20260725.6.bin` → first boot:

```
UNIT0 CANCUN:  CIH/CMH/CCH/CEH/CFH: LOADED  Ver: 06.15.00  SDK Ver: 06.05.35
```

- config.bcm hardcodes `b870.6.4.1`, but the SDK actually loaded **6.15.00** (= default→6.15.0), **CIH LOADED** (not FAILED).
- create_switch succeeded (ASIC_DB: 1 SWITCH + 35 PORT objects), 4 front-panel ports link up, syncd 0 restarts.
- **Confirmed**: the upstream stale config.bcm is entirely harmless on a **fresh install** — the fallback works. The earlier lab incident was the **incremental .deb-swap** scenario (stale 6.4.1 conffiles loaded preferentially).
- The official image's CANCUN payload is byte-identical to our self-built one → our image's ASIC init behavior equals the official's (this axis is de-risked).

---

## 6. Install the self-built resolute image (definitive answer to the core question)

- **Artifact**: `target/sonic-broadcom.bin` (2.19 GB, SAI `15.2.0.0.0.0.3.1`, sha1 `c8968708...`), payload self-check passed.
- **Transfer**: this mgmt path has high RTT (373 ms) + loss; a single scp stream collapses (bursts to 2.6 MB/s, sustains down to 0.25 MB/s). **Fix = parallel streams**: locally `split -d -b 548M` into 4 parts, 4 parallel scp streams (each with retry) → remote `cat` reassembly + sha1 check. Aggregate ~3.8 MB/s, ~30 min for 2 GB (vs 1–2 hours single-stream).
- **Install**: `sonic-installer install` as a **second image** (coexists with the official one in `/host`; `Next` auto-points to the new image; rollback = `sonic-installer set-default <official>`; secure boot not enforced).
- **Boot verification** (after switching into our image):
  - `Current: SONiC-OS-202605_resolute_sheldon.0-1d988dec`, **Ubuntu 26.04 LTS Resolute Raccoon**, kernel **7.0.0-1002-sonic** (vs the official's Debian 6.12.41).
  - `cancun stat` = CIH/CMH/CCH/CEH/CFH **LOADED 06.15.00 SDK 6.5.35** (identical to official).
  - create_switch OK (ASIC_DB 1 SWITCH + 35 PORT), CONFIG_DB 34 ports, 4 front-panel ports link up, syncd 0 restarts, hwsku `DellEMC-S5232f-C32`.

**→ The original core question "can the self-built sonic-broadcom run on this hardware" = YES, proven on hardware.** The only difference between ours and the official is the OS base (Ubuntu resolute vs Debian trixie) + kernel; ASIC/CANCUN behavior is identical.

---

## 7. Fix the resolute FRR build defect (missing dplane_fpm_sonic)

Loading the fabric config exposed: **the self-built resolute image's BGP won't come up at all.**

**Symptom**: the bgp container `Exited`; inside it, zebra repeatedly `exit status 1`:
```
zebra frr_init: loader error: dlopen(dplane_fpm_sonic):
  /usr/lib/x86_64-linux-gnu/frr/modules/zebra_dplane_fpm_sonic.so: cannot open shared object file
```
SONiC starts zebra with `-M dplane_fpm_sonic` unconditionally, so a missing module crashes it. **Unrelated to config** (the default sample config crashes the same way).

**Root cause** (verified layer by layer — not the link failure I first guessed):
- The Jul 24 `frr_10.5.4-sonic-0_amd64.deb` was built with the **old dget+quilt flow** (`dget -u frr_10.5.1.dsc` + `QUILT_PATCHES=../patch quilt push -a || true`) — the `|| true` **silently swallowed the failed apply of patch 0012** (which edits `zebra/subdir.am`, whose hunk doesn't match the Ubuntu stock 10.5.1 source). The build rule never reached subdir.am → the autoreconf-generated Makefile had no target → the module was never compiled → the deb lacks it (`dh_install`'s empty glob doesn't error).
- **The current Makefile already switched to the stg + submodule flow** (`pushd ./frr` + `stg import -s ../patch/series`, which fails hard on a patch error), so the fix was already in the repo; the Jul 24 deb was just a stale artifact of the old flow.

**Fix actions**:
```
rm -f target/debs/resolute/frr*.deb
make SONIC_DPKG_CACHE_METHOD=none BLDENV=resolute \
     target/debs/resolute/frr_10.5.4-sonic-0_amd64.deb   # cache off to avoid reusing the stale deb
# -> new deb contains dplane_fpm_sonic.so (96848 B)
make SONIC_DPKG_CACHE_METHOD=none BLDENV=resolute target/docker-fpm-frr.gz
# Deploy on the switch (no full image reinstall):
docker load -i docker-fpm-frr-new.gz
docker tag docker-fpm-frr:latest docker-fpm-frr:202605_resolute_sheldon.0-1d988dec
docker rm -f bgp; systemctl reset-failed bgp; systemctl start bgp
```

**Verification**: zebra RUNNING (no crash), FPM `127.0.0.1:2620` ESTABLISHED, BGP v4/v6 Established, kernel FIB 133 routes (with `nhid` + `src=loopback`), APPL_DB ROUTE_TABLE 209, **ASIC_DB ROUTE_ENTRY 215** (hardware forwarding works).

**Upstream-worthy**: add fail-missing to `sonic-frr`'s `dh_install` so a missing module fails the build (root-cause guard against silent module drops), even though the stg flow already closes this specific hole.

---

## 8. Configuring the fabric node — two methods

The maintainer's original system ran **policy-free plain eBGP** (BIRD `import all/export all` → migrated to FRR in a prior session). Authoritative sources: `/etc/bird/bird.conf` + the validated `/etc/frr/frr.conf` + `/etc/netplan/90-nos.yaml` (all in the `~/dut02-backup/` backup).

Key parameters: AS 65202, router-id/Loopback0 `<LOOPBACK-V4>` (v6 `2001:db8::af0:fed4/128`), PortChannel200 (Ethernet0+Ethernet4, 802.3ad fast) `192.0.2.1/31` + `2001:db8::ac10:1/127`, BGP peers `192.0.2.0` / `2001:db8::ac10:0` (both AS65201). Baseline BGP v4 136 / v6 73.

### Method 1 — write config_db.json directly

- Merged incrementally onto the switch's default config: replaced the sample placeholders (ARISTA T2 neighbors / 10.0.0.x / asn 65100), kept the hwsku-correct 34-port PORT/BREAKOUT, and added the real DEVICE_METADATA (LeafRouter, 65202), Loopback, PortChannel200, and BGP neighbors.
- Fixed 2 items (from adversarial review): added `bgp_adv_lo_prefix_as_128=true` (advertise the v6 loopback as /128), and quoted `nhopself`/`rrclient`.
- **Adversarial review** (3-dimension workflow: source-fidelity / SONiC schema / fabric safety): 0 blockers, 5 warnings, all SAFE_TO_APPLY. Confirmed no route leak (a LeafRouter default doesn't redistribute connected/kernel or originate a default route) and no MGMT_INTERFACE (so SSH survives).
- `config reload` → **BGP v4 136 / v6 73 Established**, PortChannel200 LACP negotiated with peerT1, kernel FIB + **ASIC_DB 215 routes** (hardware forwarding).

### Method 2 — minigraph.xml (configure as a T0)

Goal: model dut02 semantically as a proper SONiC **T0 (ToRRouter)** node running standard role policy.

- Wrote `dut02-minigraph.xml` (single uplink, no server VLAN, peerT1 classified as upstream LeafRouter, deployment_id=1).
- **Gotcha: `config load_minigraph` crashes in `config qos reload`**: `sort_by_port_index`'s `int(k[8:])` hits the port alias `hundredGigE1/1` → `ValueError`.
- **Root cause** (dug all the way down):
  1. `config load_minigraph` (sonic-utilities `config/main.py:2427`) invokes `sonic-cfggen -H -m` — **without `-k`** (and `-m`/`-k` are argparse-mutually-exclusive; `-H` = `--platform-info` only reads platform info, does not set hwsku) → `args.hwsku=None`.
  2. → with `port_config_file=None`, `portconfig.get_port_config()` **builds the alias map by reading the PORT table from the running CONFIG_DB** (not from the port_config.ini file).
  3. → **fatal mismatch**: `port_config.ini`'s alias is `hundredGigE1/1`, but CONFIG_DB / platform.json (used by the default config generation) uses **`etp1`**. My minigraph used the file's `hundredGigE1/1`; load_minigraph's map from CONFIG_DB is `{etp1→Ethernet0}` → no match → DEVICE_NEIGHBOR keeps the raw alias → qos sort crashes. (Offline `sonic-cfggen -m mg.xml -p port_config.ini` reads the **file** alias hundredGigE1/1 and thus maps correctly, masking the mismatch.)
- **Fix**: the minigraph uses the device's actual alias `etp1/etp2` (`-H -m` then maps correctly, verified).
- **Secondary gotcha**: load_minigraph generated `fec: rs` on the 100G ports, but the link to peerT1 needs **no FEC** → Ethernet0/4 `oper=down`, LACP Dw, BGP stuck Active. `config interface fec Ethernet0/4 none` fixed it (the working baseline's Ethernet0 has no fec field and uses the hardware default).
- **Result**: `config load_minigraph` with no qos crash; dut02 = type=ToRRouter, deployment_id=1, peerT1=LeafRouter, PortChannel200 LACP Up, BGP v4 136 / v6 72 Established, role policy active (peer-group PEER_V4/V6 + route-map FROM/TO_BGP_PEER + `allowas-in 1` + `ALLOW_LIST_DEPLOYMENT_ID`), `bgp_adv_lo_prefix_as_128=true`, ASIC 214 routes. constants.yml kept at defaults (standard role policy; it already contains the full community scheme; unchanged).

### How the two methods relate

Both paths ultimately **produce a config_db that is fed to SONiC** — minigraph just adds a "topology XML → config_db" translation layer (`sonic-cfggen -m`). The minigraph XML schema namespace is `Microsoft.Search.Autopilot.Evolution`; it is essentially the topology format emitted by Azure's internal deployment system, **designed to be generated by an orchestrator, not hand-written** — which is exactly why hand-writing it hit repeated gotchas while writing config_db.json directly worked in one shot. The SONiC ecosystem is converging toward config_db + YANG, but minigraph is still a first-class citizen (heavily used by the sonic-mgmt testbed and Azure production).

---

## 9. Key artifacts and current state

**Switch currently runs**: Method 2 (the T0 minigraph config).

**Rollback points**:
- `/etc/sonic/config_db.json.fabric-working` — Method 1's LeafRouter fabric config (`config reload` to switch back)
- `/etc/sonic/minigraph.xml` — Method 2's T0 minigraph
- `/etc/sonic/config_db.json.bak-sample` — the default sample from install time
- `sonic-installer set-default SONiC-OS-202605.1174613-ec1bb42e4` — switch back to the official image
- BootOrder still has UBUNTU-NOS / ONIE / EDA-DIAG — can switch back to the maintainer's Ubuntu or ONIE

**Local artifacts**:
- `~/console.py` — console-server two-stage login + telnet IAC driver
- `~/dut02-minigraph.xml` — T0 minigraph (etp1-fixed)
- `~/dut02-backup/` — maintainer's irreplaceable files (switchdevd, libsaibcm 11.2 .deb, config)
- `~/sonic-official-202605/` — the official control image
- `target/debs/resolute/frr_10.5.4-sonic-0_amd64.deb` — **fixed** (contains dplane_fpm_sonic.so)
- `target/docker-fpm-frr.gz` — the **fixed** bgp docker

**Memories written** (`.claude/.../memory/`): `sonic-resolute-td3-cancun-config-stale`, `lab-switch-onie-install-official-202605`, `resolute-frr-dplane-fpm-sonic-missing`, `sonic-load-minigraph-alias-mismatch-crash`; and updated `resolute-lab-switch-sai-swap-incident`.

---

## 10. Upstream-worthy / TODO

1. **TD3 config.bcm stale CANCUN**: change the 23 files' `sai_load_hw_config` to `.../default/` (immune to future SAI bumps); drop the redundant `/usr/lib/cancun/` line inlined by `#18505` (that directory doesn't exist in the syncd container anyway).
2. **sonic-frr `dh_install` fail-missing**: fail the build on a missing module to prevent future silent module drops.
3. **load_minigraph port-alias mismatch**: the proper fix is either to let `config load_minigraph` pass the hwsku so `get_port_config` reads the file, or to fix DellEMC-S5232f-C32 so `port_config.ini` (hundredGigE1/1) and platform.json (etp1) agree on aliases.
4. **PfxSnt parity** (optional): SONiC's default doesn't add `sender-as-path-loop-detection`, so it re-advertises learned routes back to peerT1 (which peerT1 rejects via AS-path loop — harmless); 100% parity with the maintainer's 2/2 needs a custom FRR injection or a template change.
5. **fec default**: load_minigraph defaults the 100G ports to `fec rs`, which doesn't match this fabric link — after running load_minigraph on a hand-written minigraph, always check `redis-cli -n 4 hget "PORT|Ethernet0" fec`.
