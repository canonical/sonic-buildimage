# sonic-mgmt t0 test list on the Dockerfile and rock vs images of 202605_resolute

- Date: 2026-11-10 to 2026-11-12
- Images, both from `canonical/sonic-buildimage` `202605_resolute` at `7a081af43c`, the same pair as the [A/B report](2026-11-10-sonic-mgmt-resolute-ab-report-en.md):
  - rock + pebble: image version `202605_resolute.0-7a081af43`
  - Dockerfile + supervisord: image version `HEAD.0-7a081af4`
- Test lists: the upstream t0 PR test list, 271 files, run through `run_tests.sh -m individual`; also the dualtor, t0-2vlans and t0-sonic lists (§8)
- Test code: [canonical/sonic-mgmt#2](https://github.com/canonical/sonic-mgmt/pull/2), branch `feat/resolute-ubuntu-rock-compat`, 21 signed commits on `sonic-net/sonic-mgmt` `202605` `36c29fc`, at `7b70925`. The first run (§2, §3) used the process framework and common helpers only, before the call-site commits 9–21.
- Testbeds: vms-kvm testbeds in LXD virtual machines on the Testflinger machine jasperoid (§1)
- Design: [specs/2026-11-10-sonic-mgmt-ubuntu-rock-compat-design-en.md](specs/2026-11-10-sonic-mgmt-ubuntu-rock-compat-design-en.md)
- Raw results and scripts: [data/2026-11-11-sonic-mgmt-t0-run/](data/2026-11-11-sonic-mgmt-t0-run/)
- This is the English version and the source of truth; the Chinese version is `-zh.md`

## 0. Conclusions

1. At the final code, all 271 files of the t0 list ran on both images, 3040 test cases each, and the two images differ in 18 cases (§5). 14 are not differences (random test parameters), 2 are intermittent on either image, and 2 are rock product issues: the `auto_restart` limitation already reported in the A/B run, and shutdown logs lost because pebble stops rsyslogd with the other services (§6). Teardown and loganalyzer results are the same on both images.
2. The first run, before the call-site commits, differed in 109 cases in 37 files (§3). 93 came from sonic-mgmt test code that calls `supervisorctl` directly, assumes a container's entrypoint runs a given command, or runs `python` in a container; commits 9–21 fix them (§4).
3. The dualtor, t0-2vlans and t0-sonic lists give identical results on the two images (§8).
4. 18 test cases fail on both images. They are Ubuntu-SONiC, vs-platform or testbed issues, not rock issues (§7). They are in the upstream PR test list, so they are expected to pass on the Debian vs image; no Debian image was run here. Loganalyzer also reports the same AppArmor message on both images in most teardowns (§7); canonical/sonic-buildimage#30 fixes it.

## 1. Setup

| Item | Value |
|---|---|
| Machine | Testflinger jasperoid: 256 threads, 251 GB, NVMe; Ubuntu 26.04 |
| Testbeds | 12 LXD VMs (`ubuntu:26.04`), 18 vCPU, 18 GiB, 140 GiB each; vms-kvm-t0 with cEOS 4.32.5M neighbours |
| Split | 6 shards of 45–46 files; shard N runs the same files on both images |
| First run | 2026-11-10 23:04 to 2026-11-11 04:53 UTC, both images at once |
| Final rerun | 2026-11-12 02:50 to 08:44 UTC, both images at once (§5) |
| Test time, first run | 25.5 h (rock) and 31.1 h (Dockerfile) of pytest time in 5 h 49 min |

Each VM runs [scripts/tb-bootstrap.sh](data/2026-11-11-sonic-mgmt-t0-run/scripts/tb-bootstrap.sh): packages, add-topo, deploy-mg, then its shard. The file lists are under `shards/`.

Files take from 1 s to 66 min, so file-count shards finish hours apart. A balancer on the host ([scripts/balancer.py](data/2026-11-11-sonic-mgmt-t0-run/scripts/balancer.py)) hands the second half of the slowest shard's unstarted files to a VM of the same image that has finished. It renames the donor's copies so that the donor's `run_tests.sh` skips them; nothing is killed. Five hand-overs moved 39 files (`handoffs.json`). The 12 test modules that other modules import are never handed over: renaming `platform_tests/test_reboot.py` once broke collection of its importers, which cost one file on the donor and the two files of a later hand-over to it; the three were rerun.

## 2. First run results

| | Passed | Skipped | Failed | Setup error |
|---|---|---|---|---|
| Dockerfile | 1089 | 1933 | 15 | 3 |
| rock | 1001 | 1929 | 44 | 66 |

Counts are test cases by call outcome. A teardown error is counted separately (§7); the full comparison is `compare-main-df-vs-rock.txt`, made by `scripts/analyze.py`.

## 3. Differences in the first run

| Cause | Cases | Files |
|---|---|---|
| gnmi helpers: supervisorctl status/stop/restart; the rock then shuts the gnmi container down | 40 | 10 |
| arp_update and rsyslogd control through supervisorctl | 16 | 6 |
| SNMP subagent check through supervisorctl | 15 | 10 |
| dhcp_relay program state and pid through supervisorctl | 13 | 2 |
| pmon and lldp program control through supervisorctl | 3 | 2 |
| like-bgp container started with a command after the image | 2 | 1 |
| telemetry event helpers: supervisorctl, and `python` in eventd | 2 | 1 |
| bmp program state through supervisorctl | 1 | 1 |
| radvd SIGHUP through supervisorctl | 1 | 1 |
| Rock product: critical services `on-failure: shutdown` against `auto_restart` | 1 | 1 |
| Not a difference: `hash/test_generic_hash` draws random parameters | 14 | 1 |
| Not a difference: `losetup` found the loop device busy on one Dockerfile testbed | 1 | 1 |
| Total | 109 | 37 |

The supervisorctl failures look different from test to test:

- The command fails and the test stops (arp, crm, dualtor, radv, monit, platform_info).
- The failure is read as "not running yet", and the test waits out its timeout. The SNMP subagent check waited 300 s in each of 16 cases, so a test that never touches a process failed with "Timeout waiting for SNMP facts".
- A shell pipeline hides the exit status. In `generic_config_updater/test_dhcp_relay` the pid comes out empty, and the test fails later at `ps -p`.
- The test ignores the error and goes on without the step (vlan restarts arp_update, bgp_port_disable restarts fpmsyncd).
- The failure leads to a rock-only cascade. The gnmi helpers do not stop gnmi-native before killing its process, so pebble's `on-failure: shutdown` stops the gnmi container. Later gnmi tests then fail with "The 'gnmi' container does not exist", and monit's container_checker alerts reach the loganalyzer of unrelated tests (the 11 extra rock lines in `iface_namingmode`).

`bgp/test_bgp_command` starts a second container with `docker run docker-database:latest sleep infinity`. The rock entrypoint is `pebble enter`, which does not run a command given after the image, so the container exits at once. `--entrypoint /bin/sleep` gives the same idle container from either image.

## 4. Fixes

| # | Commit | Area | Rock cases fixed in the first run's list |
|---|---|---|---|
| 5, 6 | `e6af484`, `7536a03` | Includes `build_signal_command()` and `SonicHost.signal_container_process()` | — |
| 9 | `d6bdb02` | snmp_helpers: subagent state from the process table | 15 |
| 10 | `7d418e2` | dhcp_relay_utils, test_dhcpv6_relay, GCU test_dhcp_relay | 13 |
| 11 | `5284ceb` | gnmi helpers, gnmi_setup, grpc_fixtures, GNMIEnvironment | 40 |
| 12 | `6bc47ef` | arp_update and rsyslogd in arp, crm, dualtor, vlan, pc, syslog | 15 |
| 13 | `6f16cd2` | like-bgp entrypoint; fpmsyncd restart | 2 |
| 14 | `fa0c72e` | bmp state | 1 |
| 15 | `603ce6a` | radvd SIGHUP | 1 |
| 16 | `d407932` | thermalctld, lm-sensors, lldpmgrd | 3 |
| 17 | `6d39a82` | telemetry event helpers; `python3` for the events publish tool | 2 |
| 18 | `f55a879` | arp_update and ycabled in the dualtor list (§8) | — |
| 19 | `33a574b` | qos_sai: radvd, arp_update, lacpd | — (hardware only) |
| 20 | `f9f14d7` | dhcp_server fixture | — (hardware only) |
| 21 | `7b70925` | two diagnostics that only log | — |

The branch's unit tests pass at each commit, 294 at the last one.

The first fixes were checked by rerunning 64 files on both images: every file the fixes touch or that uses a changed helper, every file with a rock-only failure, and every file that reached the gnmi cascade. On the rock image these files went from 98 passed, 33 failed and 64 setup errors to 186 passed and 5 failed, the 5 being the rock product issues and failures on both images (`verify-before-after-rock.txt`).

Three independent reviews of the commits found no critical problem. They found places where the migrated code read a failed probe as "program absent" and so skipped or passed where the old code failed, a pipeline that used to fail on no match, an SNMP poll that no longer returned early, a teardown check that had become looser, a `docker exec -it` that had never worked under Ansible, validation that accepted a trailing newline, and three call sites reached on hardware only (commits 19–21). The commits include the fixes. The files they touch were run again on both images, with no failure and the same results on both (`verify-review-rerun.txt`, `audit-fix-rerun.txt`).

## 5. Full rerun at the final code

All 271 files ran again on both images, on 12 testbeds, with shards cut by the file durations of the first run (`shards-final-rerun/`); three hand-overs moved 12 files (`handoffs-final-rerun.json`). The code was commits 1–18; the files changed by commits 19–21 were run afterwards on both images, with 23 passed and 343 skipped on each, as in the full rerun (`audit-fix-rerun.txt`).

| | Passed | Skipped | Failed | Setup error |
|---|---|---|---|---|
| Dockerfile | 1088 | 1933 | 16 | 3 |
| rock | 1085 | 1935 | 17 | 3 |

The cases that differ (`compare-final-rerun-df-vs-rock.txt`):

| Cases | Dockerfile → rock | Kind |
|---|---|---|
| 14 in `hash/test_generic_hash` | present on one image only | Not a difference: the test draws random parameters, so the case names differ; per test function the outcomes match |
| `process_monitoring::test_monitoring_critical_processes` | passed → failed | Rock product: `auto_restart` (A/B report) |
| `pc/test_po_cleanup` | passed → failed | Rock product: shutdown logs lost (§6) |
| `dhcp_relay/test_dhcp_pkt_recv` dhcpv6 multicast | failed → passed | Intermittent: no packet with the expected transaction id |
| `telemetry/test_events` | passed → xfail | Intermittent: upstream marks it xfail on vs (sonic-buildimage#19943); it passed on rock in the earlier reruns |

Teardown results and loganalyzer matches beyond the known AppArmor noise are the same on both images. The 18 cases that fail on both images are in §7.

## 6. Rock differences found by these runs

**Shutdown logs are lost.** `pc/test_po_cleanup` reloads the configuration and waits for teammgrd's `cleanTeamProcesses` messages, which teammgrd writes when it gets SIGTERM. With the fixes, the test reaches the reload, and on the rock image none of the four messages arrives. On a vs DUT:

| Action | `cleanTeamProcesses` lines in syslog |
|---|---|
| Dockerfile: `systemctl restart teamd` | 20 |
| rock: `systemctl restart teamd` | 0 |
| rock: `pebble stop teammgrd`, rsyslogd running | 10 |

teammgrd cleans up and logs under pebble. When the whole container stops, pebble stops rsyslogd at the same time as the other services, so their last messages are dropped; supervisord stops rsyslogd last by priority. The rock plan in teamd gives rsyslogd no ordering against the other services. The likely fix is in the rock plans: services `after: rsyslogd`, so that pebble stops rsyslogd last. This affects every rock container, not only teamd.

**eventd has no `/usr/bin/python`.** The Dockerfile image's eventd has `python -> python3`; the rock has only `python3`. `telemetry/events/event_utils.py` called `python`; it now calls `python3`, which both images have. Other callers of `python` in a rock would fail the same way.

## 7. Failures on both images

| Cases | Failure | Kind |
|---|---|---|
| 5 in `test_show_platform`, 3 in `test_sfputil`, 1 in `test_platform_info` | vs platform data the tests expect is missing: "Platform x86_64-kvm_x86_64-r0 does not support EEPROM", no `/etc/sonic/vs_chassis_metadata.json`, no pcie file under `/usr/share/sonic/device/x86_64-kvm_x86_64-r0`, no PSU with status OK; `sfputil` and `psuutil status` return 2 | vs platform on Ubuntu-SONiC |
| 4 in `tacacs/test_authorization` | the `/etc/passwd` and tacplus server log checks fail | Ubuntu-SONiC |
| `radv/test_radv_run::test_radv_deployment_id` | the radvd check after setting the deployment id fails | Ubuntu-SONiC |
| `snmp/test_snmp_v2mib` | sysDescr does not contain the `Ubuntu forky/sid` the test reads from the DUT | Ubuntu-SONiC (known from the A/B run) |
| `test_pktgen` | its own loganalyzer matches 18 lines, all the AppArmor message below | Ubuntu-SONiC |
| `disk/test_disk_exhaustion` | the DUT forwards a packet count outside the expected range while the disk is full | Ubuntu-SONiC or vs; also seen on the t1-lag testbeds |
| `syslog/test_logrotate::test_logrotate_full_partition_no_archives_cleanup` | `losetup` finds the loop device busy at setup | Testbed |

**Loganalyzer noise on both images.** Most teardowns in the t0 list fail loganalyzer on `ERR unix_chkpwd: nss_tacplus: /etc/tacplus_nss.conf fopen failed` and `bad config or server line for nss_tacplus`. rsyslogd logs the same pair. sudo's PAM account stack runs `unix_chkpwd`, which resolves the user through nsswitch `passwd: tacplus files`, so `libnss_tacplus` opens `/etc/tacplus_nss.conf`. Ubuntu 26.04's apparmor 5.0.2 enforces the profile `unix-chkpwd`, which allows the NSS libraries but not that file. auditd runs on the image, so each denial goes to `/var/log/audit/audit.log` (3285 on one DUT, one per sudo) rather than to dmesg. Unloading the profile with `apparmor_parser -R` stops the messages. Debian trixie's apparmor 4.1.0 ships the same profile with `flags=(complain)`, and both images install apparmor, which is why the Debian-based image does not log them. [canonical/sonic-buildimage#30](https://github.com/canonical/sonic-buildimage/pull/30) adds `/etc/tacplus_nss.conf r,` as `/etc/apparmor.d/local/unix-chkpwd`. The comparison in this report sets these two lines aside.

## 8. Other vs topologies

The upstream PR test lists for the dualtor, t0-2vlans and t0-sonic topologies ran on one testbed per image, in turn (`compare-other-topologies.txt`):

| List | Testbed | rock | Dockerfile |
|---|---|---|---|
| dualtor, 22 files | vms-kvm-dual-t0, two DUTs | 61 passed, 137 skipped, 6 failed | 61 passed, 137 skipped, 6 failed |
| t0-2vlans, 3 files | vms-kvm-t0 with `vlan_config=two_vlan_a` | 2 passed, 6 skipped | 2 passed, 6 skipped |
| t0-sonic, 8 files | vms-kvm-t0-64-32, vSONiC neighbours, `--enable_macsec` | 45 passed, 11 skipped | 45 passed, 11 skipped |

No case differs once the DUT name, which dualtor tests pick at random, is set aside. The 6 dualtor failures are the same on both images: four IPv6 failed-neighbour cases in `arp/test_arp_dualtor`, and two in `dualtor/test_mux_port_iptables_entries`, which find a DOCKER chain in the IPv4 nat table that the test does not expect on Ubuntu-SONiC. Before commit 18 the rock image also failed `arp_dualtor`, `test_standalone_tunnel_route` and `test_switchover_faulty_ycable` on direct supervisorctl calls.

t1-lag is out of scope. About two thirds of its 224 files ran before it was stopped: of the 1531 cases both images completed, one differed, an intermittent lldp start-up after reboot on the Dockerfile image.

## 9. Testbed notes

- Docker on the host set the iptables FORWARD policy to DROP, which left the VMs without network until `lxdbr0` was allowed in `DOCKER-USER`.
- sonic-mgmt's `vm_set` role adds the docker-ce repository with `apt_key` unless a docker apt source exists; Ubuntu 26.04 has no `apt-key`. The VMs use docker-ce from download.docker.com.
- On first install, openvswitch-switch 3.7.1 starts ovsdb-server before the `ovs-vswitchd` alternative exists, and systemd stops retrying; it needs a restart before add-topo.
- At 06:23 on 2026-11-11, unattended-upgrades in every VM restarted openvswitch. The flows add-topo had installed were lost, and every DUT lost its links to the cEOS neighbours. The first run had ended at 04:53. In the reruns of the fixed files, 21 files ran wholly or partly after 06:23; their results match the runs before it, except one reboot test. `testbed-cli.sh connect-topo` restores the flows; the bootstrap now disables the upgrade timers.
- A test killed partway through can leave configuration behind. Before this run, on the local testbed, an `acl/test_acl.py` stopped by hand left the table `DATA_INGRESS_IPV4_TEST`, which fails YANG validation, so every later test on that testbed failed in setup.
- An LXD VM's memory is shared memory on the host, and the guest page cache fills it to the limit within minutes, so the limits must add up to less than the host RAM. A vms-kvm-t1-lag testbed (24 cEOS neighbours) needs more than 44 GiB after a few hours. Giving six VMs 240 GiB on the 251 GB host made the host kill one of them; a host swap file and a smaller ZFS ARC avoid it.
- One Testflinger provisioning failed on repeated MAAS API errors; resubmitting the job worked.

## 10. Not done

- About 70 lines that run `supervisorctl` on the DUT remain in test areas outside these lists (dualtor_mgmt, qos, dash, ha, gnmi_e2e, platform API and others), among them the Mellanox dynamic-buffer script.
- Multi-ASIC paths are covered by unit tests only; t1-lag, multi-asic, t2 and VPP topologies were not run.
- The rock product items (shutdown log ordering, `auto_restart`, eventd `python`) and the Ubuntu-SONiC failures in §7 are left for the product side; only the AppArmor noise has a fix under review (#30).
