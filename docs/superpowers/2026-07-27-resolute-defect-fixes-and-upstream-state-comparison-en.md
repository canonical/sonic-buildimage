# Four resolute defects found by auditing a running switch, and a full-state comparison against upstream

**Date**: 2026-07-27
**Target device**: `<DUT-MGMT-IP>` (Dell EMC S5232F-ON, BCM56873 / Trident3, platform `x86_64-dellemc_s5232f_c3538-r0`)
**Branch**: `canonical/sonic-buildimage` → `202605_resolute_sheldon`, rebased onto `sonic-net/202605` (`ba3fb8d5f5`)
**Continues**: [2026-07-26 dut02 S5232F validation report](2026-07-26-dut02-s5232f-validation-report-en.md), which established that the self-built resolute image boots and forwards on this hardware.

---

## 1. Results at a glance

| Item | Result |
|---|---|
| Component audit of the running switch | 14/14 containers healthy; 4 real defects, 5 suspected ones disproven |
| All SAI counters zero | **Root cause: a submodule that drifted off upstream**, not the SAI version. Fixed and verified on hardware |
| SONiC event framework dead | Ubuntu's rsyslog AppArmor profile blocks the event plugin. Fixed and verified on hardware |
| No DNS on the switch | `resolvconf` is a virtual package on Ubuntu. Reworked onto systemd-resolved's documented "managed by other packages" mode |
| RADIUS options silently ignored | The libpam-radius-auth de-fork dropped three of four SONiC patches. Reverted to the source build |
| Submodule fast-forward audit | 4 of 52 submodules had diverged; all rebased conflict-free, audit now green, and the check is now scripted |
| Upstream ↔ our build, same box, same config | **No functional difference.** An 86-line diff, entirely distribution-level |

---

## 2. Scope: auditing every component of the running switch

The starting point was three commands — `docker ps -a`, `supervisorctl status` in every container, and
`show system-health sysready-status` — widened on request to every component: host services, containers,
data plane, platform sensors, management and telemetry planes, and the logs.

The healthy baseline was solid: 14/14 containers up with `RestartCount=0`, all 41 monit process checks OK,
BGP established, ASIC forwarding, PSUs and fans OK, no core dumps.

Several findings that look alarming turned out to be by design, and are recorded here so they are not
re-investigated: the `EXITED` supervisor entries (`dependent-startup`, `start`, `flushdb`, `swssconfig`,
`enable_counters`, `gearsyncd`, `restore_neighbors`, `chassis_db_init`, `ledinit`, `zsocket`,
`waitfor_lldp_ready`) are one-shot scripts; `bgp:sharpd` and `radv:radvd` are `autostart=false`;
`pmon:pcied` exits because this platform ships no `pcie.yaml` upstream; SNMP does not answer because no
community is configured; and NTP is unsynchronised because the configuration defines no server.

---

## 3. The four defects

### 3.1 Every SAI counter stuck at zero

`show interfaces counters` reported zeros for every port, queue, priority group and watermark, on a
switch that had been forwarding BGP traffic for sixteen hours.

The evidence separated the layers cleanly:

- the kernel netdev counted the traffic (8462 → 8505 packets across 20 pings),
- the Broadcom SDK's own counters agreed with it (`bcmcmd show c`: `CLMIB_RPKT.ce0` = 8515),
- the flex counter framework was alive — `FLEX_COUNTER_GROUP_TABLE:PORT_STAT_COUNTER` enabled at a
  1000 ms interval, and the `PORT_PHY_ATTR` group was publishing fresh timestamped data,
- but every one of the 3990 keys in `COUNTERS_DB` was zero, with no error logged anywhere.

Booting the official 202605 image on the same hardware showed counters advancing normally, which proved
the regression was ours but could not say which part of the image caused it: that boot changed the OS,
the kernel, syncd, sairedis and the SAI library all at once. Git archaeology isolated it.

Our `sonic-sairedis` submodule was two commits behind the commit upstream's own tree recorded, and one of
those two is [`16ae1ae5` "Smart Counter Poll to allow counters to work properly on Broadcom platforms"
(#1995)](https://github.com/sonic-net/sonic-sairedis/pull/1995):

> `FlexCounter.cpp` assumes all ports support the same counter capabilities. This causes issues on most
> Broadcom platform switches as there are different types of ports on a switch that does not support the
> same set of counters. Fix by dynamically discovering what each interface is capable of during
> initialization of `syncd`.

Every detail matches: the S5232F mixes 32×100G QSFP28 with two 10G SFP+ ports; the failure is silent
because no call errors, the capability assumption is simply wrong; and the fix touches only counter
initialisation, which is why attribute-based groups such as `PORT_PHY_ATTR` kept working. The official
image we compared against carries that commit — its gitlink is exactly `16ae1ae5`.

**The SAI version was the wrong suspect.** Our pin, `libsaibcm 15.2.0.0.0.0.3.1`, is untouched by us and
is what upstream 202605 pinned at our branch point; upstream moved to `11.1` on 2026-07-24 (#28549), a
roll-up of CSP fixes whose changelog contains nothing resembling "XGS port statistics return zero", and
`3.1` had been the 202605 pin for a month while the Broadcom XGS qualification suite passed on it.

**How the commit went missing** is the part worth internalising. On 2026-07-20 this repository was rebased
onto upstream `fe5ae5db34` — a commit whose `src/sonic-sairedis` gitlink was already `16ae1ae5`. The
submodule branch, however, stayed based on 2026-07-03. When a parent-repository rebase hits a gitlink
conflict, our commit has to win, or the resolute patches are lost — so the stale gitlink was preserved and
the upstream fix was silently dropped. Nothing reports this.

### 3.2 The SONiC event framework never published anything

`omprog: failed to execute program '/usr/bin/rsyslog_plugin': Permission denied` — 2891 times in sixteen
hours, still accumulating. `/var/log/audit/audit.log` names the cause:

```
apparmor="DENIED" operation="exec" profile="rsyslogd" name="/usr/bin/rsyslog_plugin" requested_mask="x"
apparmor="DENIED" operation="capable" profile="rsyslogd" capability=0 capname="chown"
```

Ubuntu's rsyslog package ships `/etc/apparmor.d/usr.sbin.rsyslogd` and enforces it, and its
`rsyslog.service` carries `ExecStartPre=/usr/lib/rsyslog/reload-apparmor-profile`. Debian's rsyslog ships
no profile at all — verified by mounting the official image's squashfs on the same box — so the host
rsyslogd there runs unconfined and only the container instances are under `docker-default`. All six
`*_events.conf` actions (bgp, swss, syncd, dhcp_relay, host, 00-sonic) were therefore dead, and the same
profile also denied the `chown` behind `$FileOwner`/`$FileGroup`.

The fix is an override through the profile's own `local/` include, the mechanism already used for tcpdump
in `build_debian.sh`. Testing it on the switch mattered: allowing the exec and the capability surfaced a
second denial — `/etc/sonic/init_cfg.json`, which libswsscommon opens while connecting to the event bus —
that no amount of reading the profile would have predicted.

### 3.3 The switch had no DNS at all

`/etc/resolv.conf` was a dangling symlink into `/run/resolvconf/`, and `getent hosts` failed.

`resolvconf` does not exist as a real package in Ubuntu — it is a virtual package that `systemd-resolved`
declares `Provides`, `Replaces` and `Conflicts` on, and it has been that way since at least 24.04. So the
`resolvconf` entry in the rootfs package list is silently satisfied by systemd-resolved, `/sbin/resolvconf`
becomes a symlink to `resolvectl`, and SONiC's `resolv-config.sh` — which drives `--disable-updates`,
`--enable-updates`, `-u` and `/run/resolvconf/interface/` — fails on every one of them.
`interfaces-config.sh` hit the same wall in its `resolvconf_updates_disable/restore` helpers. The Noble
reference branch carries the identical latent bug, unnoticed.

The rework follows the fourth mode of `/etc/resolv.conf` handling documented in
`systemd-resolved.service(8)`, where the file is "managed by other packages" and resolved is its consumer
rather than its provider. SONiC renders the file itself, which also preserves `DNS_OPTIONS`: resolved can
express neither `ndots` nor `timeout`, and its stub resolver, in the manual's own words, "does not
implement [ndots] at all". The image resolves through nss-dns anyway (`hosts: files dns`), so resolved was
never in the lookup path.

Two further traps had to be closed for the DHCP case. `resolvectl(1)` states that its resolvconf
compatibility mode "will only update `/etc/resolv.conf` … when it is a symlink to
`/run/systemd/resolve/resolv.conf`, and not a static file"; and isc-dhcp-client ships
`dhclient-enter-hooks.d/resolved-enter`, which blanks `make_resolv_conf()` outright whenever
systemd-resolved is enabled. Our own hook now writes the file, and that pair of Ubuntu hooks is removed
from the image.

### 3.4 RADIUS lost three of its four patches

`aaastatsd` aborted on every timer with `FileNotFoundError` on `/etc/pam_radius_auth.d/statistics/`. The
directory was missing because `rules/radius.mk` had been de-forked to Ubuntu's stock
`libpam-radius-auth 3.0.0-1build1`.

`src/radius/pam` is not Debian's package: it is SONiC's own `1.4.1-1`, a version that exists in no
distribution archive, built from Debian's 1.4.0 packaging plus four patches. Ubuntu's 3.0.0 is a newer
upstream (FreeRADIUS/pam_radius) that carries exactly one of them:

| SONiC patch | Size | In upstream 3.0.0 |
|---|---|---|
| `0004-fix-blastradius` | 12 KB | Yes (`require_message_authenticator`) |
| `0003-nas-ip-address-config` | 29 KB | Partly — NAS-IP is derived from the hostname; no `nas_ip_address=` option, no `statistics` |
| `0001-chap-support` | 4 KB | No |
| `0002-peap-mschapv2-support` | 135 KB | No — hence the `libeap` and `libradius` shared objects in the SONiC deb |

`common-auth-sonic.j2` passes `privilege_level`, `protocol=<auth_type>`, `retry=`, `nas_ip_address=` and
`statistics=`. Upstream 3.0.0 logs unrecognised options and continues, so PAP still authenticates — but
`protocol=chap` and `protocol=mschapv2` are silently ignored and fall back to PAP, `nas_ip_address=` is
ignored, and statistics collection is gone. The rule was restored verbatim to upstream; the source build
was never a risk, as the 1.4.1-1 deb and its dbgsym had already been built on resolute before the de-fork
landed.

---

## 4. The submodule fast-forward audit

The healthy state for a submodule Canonical has modified is a **strict fast-forward from upstream**: the
commit upstream records is an ancestor of ours, with our commits replayed on top. §3.1 showed what
divergence costs, so the whole tree was audited, and the check is now a script,
`scripts/submodule-ff-audit.sh`, referenced from `AGENTS.md` as a step to run after every upstream sync.
It classifies every gitlink and also catches two failure modes that break a clone: a gitlink that exists
on no remote, and a non-https `.gitmodules` URL.

First full run over 52 submodules: 36 identical to upstream, 12 strict fast-forwards, **4 diverged** —
`sonic-sairedis` (2 upstream commits missing), `sonic-utilities` (4), `sonic-swss` (1) and `sonic-dash-ha`
(2). All four were predicted conflict-free by intersecting the changed-file sets, and all four rebased
without a single conflict. The audit now reports 36 identical + 16 strict fast-forwards, 0 diverged.

Rebasing this repository onto current upstream in the same pass also brought in the SAI `3.1 → 11.1` bump
and a newer `sonic-platform-common` for free, since neither file is one we modify.

---

## 5. Build, deployment and full-system verification

The image was built for broadcom (2.19 GB, `202605_resolute_sheldon.0-d605df6b`), transferred to the
switch as four parallel streams — a single scp stream collapses on this high-latency path — installed
alongside the existing images and booted.

All four fixes hold on the installed image:

| Fix | Evidence after boot |
|---|---|
| Counters | `SAI_PORT_STAT_IF_IN_OCTETS` advancing; `show interfaces counters` reporting traffic; queue counters non-zero; syncd logging the new per-port capability discovery |
| Events | 0 omprog errors, **10** `rsyslog_plugin` processes (one before the fix), 0 AppArmor denials, `events_tool -r` receiving events |
| DNS | `/etc/resolv.conf` a regular file with the SONiC header, `resolv-config.service` active (it used to be `failed`), our dhclient hook present and Ubuntu's `resolved`/`resolved-enter` hooks gone. `config dns nameserver add` renders the server and `getent` resolves — the static path proven end to end |
| RADIUS | `libpam-radius-auth 1.4.1-1` with its statistics directory; `aaastatsd` no longer aborts |

Switch-level state after the reboot: 14 containers, BGP v4 136 / v6 73 established, 215 ASIC routes,
PortChannel200 LACP up.

---

## 6. Full-state comparison: upstream sonic-net versus our build

**Method.** Both images ran on the same switch with the same T0 configuration — `sonic-installer install`
copies `/etc/sonic` to `/host/old_config` and the new image migrates it on first boot, so configuration
parity is automatic. A capture script dumped a normalised snapshot of each (pids, uptimes, timestamps and
byte counts normalised away) covering image identity, containers and their supervisor programs, features,
sysready, failed units, DNS, events and AppArmor, counters, data plane, platform, CLI exit codes,
listeners, packages of interest and a log-error histogram. The two snapshots are ~393 lines each and
differ in 86.

**Every difference is distribution-level.** Kernel `6.12.41+deb13` vs `7.0.0-1002-sonic`; Debian 13 vs
Ubuntu 26.04; apparmor 4.1.0 vs 5.0.0~beta1; chrony 4.6.1 vs 4.8; rsyslog 8.2504 vs 8.2512; monit 5.34.3
vs 5.35.2; the Debian-vs-Ubuntu version strings of the `libpam*` stack; and libnl `3.7.0-0.2+b1sonic1`
(upstream's patched build) vs `3.12.0-2` (our deliberate de-fork to the stock library).
`libpam-radius-auth` does not appear in the diff at all — both are `1.4.1-1` again.

**What is identical, and settles open questions:**

- The whole counters section matches byte for byte: `port_counters_moving=YES`,
  `queue_counters_nonzero=1`, `flex_counter_groups=24`, and **`rif_counter_fields=0`** — so the empty RIF
  counters are upstream behaviour, not a resolute regression.
- `Hardware: Not OK — Invalid ASIC On-board temperature data, threshold=N/A` appears on both, confirming
  the amber system-status LED is an upstream Dell-plugin gap.
- Both images report `System is not ready`, each for a different unit: `gnoi-shutdown` on upstream,
  `dmesg` on ours (an Ubuntu-only unit). The same class of upstream flakiness, not a resolute-only one.

**Where our build is ahead:** `show platform summary` reports Serial `FXN3SR3` and Model `0018MY` on our
image and `N/A` on the official one — a consequence of the newer `sonic-platform-common` the rebase
brought in.

**The one difference that is genuinely ours:** monit's program checks converge more slowly after boot.
Upstream had all of them OK at 8 minutes of uptime; ours still listed 7 as *Not Running* at 9 minutes and
reached `Services: OK` at 13. Startup latency, not a failure — an earlier 16-hour-uptime capture showed
everything OK.

---

## 7. Operational traps worth remembering

- **`sonic-installer install` keeps only two images** and silently deletes the oldest non-current one.
  Installing a third image removed the official reference image, GRUB entry and all. Recovery cost
  nothing only because the official `.bin` was still staged on the eMMC EDA-DIAG partition
  (`/mnt/eda/sonic-staging/`, remount with `mkdir -p /mnt/eda && mount /dev/mmcblk0p2 /mnt/eda` after
  every reboot). Check which image is about to be evicted before installing.
- **A dangling `/etc/resolv.conf` breaks `sonic-installer install`** in `migrate_sonic_packages`, where it
  runs `cp /etc/resolv.conf …` into the new image's chroot — one more consequence of §3.3, and it
  disappeared once the file was a regular file again.
- **Swapping a container image takes three steps, not one.** `docker load` renames the old image onto the
  version tag, so the versioned tag must be re-applied; and `systemctl restart swss` only `docker start`s
  the existing container, which keeps the old image. The sequence is `systemctl stop swss` →
  `docker rm -f syncd` → `systemctl start swss` (`swss.sh` declares `PEER="syncd"`, so stopping swss stops
  syncd too).
- **The top-level `Makefile`'s `%::` rule has no prerequisites**, so an existing target file is reported
  "up to date" and the build never enters the slave container. Remove `target/<the target itself>` before
  rebuilding; deleting the intermediate debs is not enough.
- **`/var/log` is a loop-mounted filesystem shared across images**, so `audit.log` and `syslog` history is
  not evidence about the image currently running.
- **Submodule branches are named differently locally and remotely**: the working branches are `resolute`
  or `202605`, while the remote branch is `202605_resolute`.

---

## 8. Current state and open items

`202605_resolute_sheldon` is strictly based on `sonic-net/202605` (`ba3fb8d5f5`) with 168 commits on top,
five of them from this work, all GPG-signed:

```
9758a4685f  build: sync the diverged submodules with upstream 202605
d605df6b58  build(resolute): drop the libpam-radius-auth de-fork
56f4735555  fix(resolute): render /etc/resolv.conf directly instead of via resolvconf
08c98ba3d6  fix(resolute): let rsyslogd run the SONiC event plugin under AppArmor
327327cb32  build: add submodule fast-forward audit
```

The four submodule branches were force-pushed to `canonical/<submodule>:202605_resolute` after verifying
that each remote sat exactly on its pre-rebase commit, and the gitlinks were bumped only afterwards, as
`AGENTS.md` requires. The production branch `canonical/202605_resolute` was not touched, and nothing was
pushed to `sonic-net`.

Open:

- **The DHCP path of the resolv.conf rework is unverified.** This switch has a statically configured
  management interface, so `dhclient-enter-hooks.d/sonic-resolv` never runs here; it needs a DUT whose
  management interface takes a lease.
- **`dmesg.service` keeps sysready red.** The unit is Ubuntu-only, `Type=idle` with no `RemainAfterExit`,
  so it is inactive within seconds of finishing. Harmless, but tests that wait for sysready will time out.
  A drop-in, a mask, or an entry in the monitor's ignore list would each close it.
- **Forward-porting the three missing pam_radius patches to 3.0.0** — and offering them to
  FreeRADIUS/pam_radius — is the only way to de-fork RADIUS for real.
