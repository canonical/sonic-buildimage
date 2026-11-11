# sonic-mgmt t0 test list on the Dockerfile and rock vs images of 202605_resolute

- Date: 2026-11-10 to 2026-11-11
- Images, both from `canonical/sonic-buildimage` `202605_resolute` at `7a081af43c`, the same pair as the [A/B report](2026-11-10-sonic-mgmt-resolute-ab-report-en.md):
  - rock + pebble: image version `202605_resolute.0-7a081af43`
  - Dockerfile + supervisord: image version `HEAD.0-7a081af4`
- Test list: the upstream t0 PR test list, 271 files, run through `run_tests.sh -m individual`
- Test code: `canonical/sonic-mgmt` branch `202605_resolute`. The main run used the 19 commits of the design at `031aeb4`. The fixes in §4 add 11 commits, local only (not pushed).
- Testbeds: twelve vms-kvm-t0 testbeds, six per image, each in an LXD virtual machine on the Testflinger machine jasperoid (§1)
- Design: [specs/2026-11-10-sonic-mgmt-ubuntu-rock-compat-design-en.md](specs/2026-11-10-sonic-mgmt-ubuntu-rock-compat-design-en.md)
- Raw results and scripts: [data/2026-11-11-sonic-mgmt-t0-run/](data/2026-11-11-sonic-mgmt-t0-run/)
- This is the English version and the source of truth; the Chinese version is `-zh.md`

## 0. Conclusions

1. All 271 files of the t0 list ran on both images, 3040 test cases each. With the branch at `031aeb4`, the Dockerfile image had 18 failures and the rock image 110.
2. The two images differed in 109 test cases in 37 files. Every one has a cause:
   - 93 cases: sonic-mgmt test code that calls `supervisorctl` directly, assumes a container's entrypoint runs a given command, or runs `python` in a container. The commits in §4 fix them: on the rock image 92 of the 93 now pass or skip as on the Dockerfile image, and the 93rd reaches a rock difference (§5). On the Dockerfile image the fixes change no result; the only changes in the reruns are intermittent failures also seen without them.
   - 1 case: the rock `auto_restart` limitation already reported in the A/B run.
   - 15 cases are not differences: 14 use random parameters that differ between runs, and 1 is a busy loop device on one Dockerfile testbed.
3. Two more rock differences showed up once the tests got past supervisorctl (§5): pebble stops rsyslogd together with the other services when a container stops, so shutdown logs are lost; and the rock eventd has no `/usr/bin/python`. Neither is changed in sonic-mgmt.
4. 16 test cases fail on both images. They are Ubuntu-SONiC or vs-platform issues, not rock issues (§6). They are in the upstream PR test list, so they are expected to pass on the Debian vs image; no Debian image was run here. Loganalyzer also reports the same AppArmor message on both images in most teardowns (§6).

## 1. Setup

| Item | Value |
|---|---|
| Machine | Testflinger jasperoid: 256 threads, 251 GB, NVMe; Ubuntu 26.04 |
| Testbeds | 12 LXD VMs (`ubuntu:26.04`), 18 vCPU, 18 GiB, 140 GiB each; vms-kvm-t0 with cEOS 4.32.5M neighbours |
| Split | 6 shards of 45–46 files; shard N runs the same files on both images |
| Main run | 2026-11-10 23:04 to 2026-11-11 04:53 UTC, both images at once |
| Test time | 25.5 h (rock) and 31.1 h (Dockerfile) of pytest time in 5 h 49 min |

Each VM runs [scripts/tb-bootstrap.sh](data/2026-11-11-sonic-mgmt-t0-run/scripts/tb-bootstrap.sh): packages, add-topo, deploy-mg, then its shard. The file lists are under `shards/`.

Files take from 1 s to 66 min, so file-count shards finish hours apart. A balancer on the host ([scripts/balancer.py](data/2026-11-11-sonic-mgmt-t0-run/scripts/balancer.py)) hands the second half of the slowest shard's unstarted files to a VM of the same image that has finished. It renames the donor's copies so that the donor's `run_tests.sh` skips them; nothing is killed. Five hand-overs moved 39 files (`handoffs.json`). The 12 test modules that other modules import are never handed over: renaming `platform_tests/test_reboot.py` once broke collection of its importers, which cost one file on the donor and the two files of a later hand-over to it; the three were rerun.

## 2. Main run results

| | Passed | Skipped | Failed | Setup error |
|---|---|---|---|---|
| Dockerfile | 1089 | 1933 | 15 | 3 |
| rock | 1001 | 1929 | 44 | 66 |

Counts are test cases by call outcome. A teardown error is counted separately (§6); the full comparison is `compare-main-df-vs-rock.txt`, made by `scripts/analyze.py`.

## 3. Differences between the images

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

## 4. Fixes and their verification

| Commit | Area | Rock cases fixed |
|---|---|---|
| `011a5d3` | `build_signal_command()` / `SonicHost.signal_container_process()`, with unit tests | — |
| `1cb1b22` | snmp_helpers: subagent state from the process table | 15 |
| `d98176b` | dhcp_relay_utils, test_dhcpv6_relay, GCU test_dhcp_relay | 13 |
| `2147e61` | gnmi helpers, gnmi_setup, grpc_fixtures, GNMIEnvironment | 40 |
| `82ecd48` | arp_update and rsyslogd in arp, crm, dualtor, vlan, pc, syslog | 15 |
| `5aae892` | like-bgp entrypoint; fpmsyncd restart | 2 |
| `f977a99` | bmp state | 1 |
| `0239d07` | radvd SIGHUP | 1 |
| `16c9fb7` | thermalctld, lm-sensors, lldpmgrd | 3 |
| `8e0b354` | telemetry event helpers; `python3` for the events publish tool | 2 |
| `5c2f2e4` | program and signal names checked against the whole string | — |

The branch's unit tests pass at each commit (289 tests after `011a5d3`, 293 after `5c2f2e4`).

Verification reran 64 files on both images with the fixes: every file the fixes touch or that uses a changed helper, every file with a rock-only failure, and every file that reached the gnmi cascade. On the rock image these files went from 98 passed, 33 failed and 64 setup errors to 186 passed and 5 failed. The remaining 5 failures:

| Case | Cause |
|---|---|
| `pc/test_po_cleanup` | Rock product: shutdown logs lost (§5) |
| `process_monitoring` | Rock product: `auto_restart` (A/B report) |
| `test_snmp_v2mib`, `test_platform_info` psu, `test_pktgen` | Fail on both images (§6) |

On the Dockerfile image the same files gave the same call outcomes before and after, except for three cases:

- `test_gnoi_system_reboot_cold` failed in the main run and passed after; `test_continuous_reboot` passed in the main run and failed after. Both failures are lldp's critical processes not running 300 s after a reboot, which happened before any fix. The second one ran while the testbed links were down (§7).
- `telemetry/test_events` passed in two reruns and failed in the third: the gNMI subscription saw no `mem-threshold-exceeded` event within its 30 s deadline. The fixes do not touch that path.

An independent review of the commits found no critical problem. It found places where the migrated code read a failed probe as "program absent" and so skipped or passed where the old code failed, a pipeline that used to fail on no match, an SNMP poll that no longer returned early, a teardown check that had become looser, a `docker exec -it` that had never worked under Ansible, and validation that accepted a trailing newline. The commits above include the fixes. The 14 files these fixes touch, including `crm`, `syslog/test_syslog_rate_limit`, `dhcp_relay/test_dhcp_relay` and `telemetry/test_events`, were run again on both images: 50 passed and 15 skipped on each, with no failure (`verify-review-rerun.txt`).

## 5. Rock differences found by this run

**Shutdown logs are lost.** `pc/test_po_cleanup` reloads the configuration and waits for teammgrd's `cleanTeamProcesses` messages, which teammgrd writes when it gets SIGTERM. With the fixes, the test reaches the reload, and on the rock image none of the four messages arrives. On a vs DUT:

| Action | `cleanTeamProcesses` lines in syslog |
|---|---|
| Dockerfile: `systemctl restart teamd` | 20 |
| rock: `systemctl restart teamd` | 0 |
| rock: `pebble stop teammgrd`, rsyslogd running | 10 |

teammgrd cleans up and logs under pebble. When the whole container stops, pebble stops rsyslogd at the same time as the other services, so their last messages are dropped; supervisord stops rsyslogd last by priority. The rock plan in teamd gives rsyslogd no ordering against the other services. The likely fix is in the rock plans: services `after: rsyslogd`, so that pebble stops rsyslogd last. This affects every rock container, not only teamd.

**eventd has no `/usr/bin/python`.** The Dockerfile image's eventd has `python -> python3`; the rock has only `python3`. `telemetry/events/event_utils.py` called `python`; it now calls `python3`, which both images have. Other callers of `python` in a rock would fail the same way.

## 6. Failures on both images

| Cases | Failure | Kind |
|---|---|---|
| 5 in `test_show_platform`, 3 in `test_sfputil`, 1 in `test_platform_info` | vs platform data the tests expect is missing: "Platform x86_64-kvm_x86_64-r0 does not support EEPROM", no `/etc/sonic/vs_chassis_metadata.json`, no pcie file under `/usr/share/sonic/device/x86_64-kvm_x86_64-r0`, no PSU with status OK; `sfputil` and `psuutil status` return 2 | vs platform on Ubuntu-SONiC |
| 4 in `tacacs/test_authorization` | the `/etc/passwd` and tacplus server log checks fail | Ubuntu-SONiC |
| `radv/test_radv_run::test_radv_deployment_id` | radvd still runs after the deployment id is set | Ubuntu-SONiC |
| `snmp/test_snmp_v2mib` | sysDescr does not contain the `Ubuntu forky/sid` the test reads from the DUT | Ubuntu-SONiC (known from the A/B run) |
| `test_pktgen` | its own loganalyzer matches 18 lines, all the AppArmor message below | Ubuntu-SONiC |

**Loganalyzer noise on both images.** Most teardowns in the t0 list fail loganalyzer on `ERR unix_chkpwd: nss_tacplus: /etc/tacplus_nss.conf fopen failed` and `bad config or server line for nss_tacplus`. rsyslogd logs the same pair. sudo's PAM account stack runs `unix_chkpwd`, which resolves the user through nsswitch `passwd: tacplus files`, so `libnss_tacplus` opens `/etc/tacplus_nss.conf`. Ubuntu 26.04's apparmor 5.0.2 enforces the profile `unix-chkpwd`, which allows the NSS libraries but not that file. auditd runs on the image, so each denial goes to `/var/log/audit/audit.log` (3285 on one DUT, one per sudo) rather than to dmesg. Unloading the profile with `apparmor_parser -R` stops the messages. Debian trixie's apparmor 4.1.0 ships the same profile with `flags=(complain)`, and both images install apparmor, which is why the Debian-based image does not log them. [canonical/sonic-buildimage#30](https://github.com/canonical/sonic-buildimage/pull/30) adds `/etc/tacplus_nss.conf r,` as `/etc/apparmor.d/local/unix-chkpwd`. The comparison in this report sets these two lines aside.

## 7. Testbed notes

- Docker on the host set the iptables FORWARD policy to DROP, which left the VMs without network until `lxdbr0` was allowed in `DOCKER-USER`.
- sonic-mgmt's `vm_set` role adds the docker-ce repository with `apt_key` unless a docker apt source exists; Ubuntu 26.04 has no `apt-key`. The VMs use docker-ce from download.docker.com.
- On first install, openvswitch-switch 3.7.1 starts ovsdb-server before the `ovs-vswitchd` alternative exists, and systemd stops retrying; it needs a restart before add-topo.
- At 06:23 on 2026-11-11, unattended-upgrades in every VM restarted openvswitch. The flows add-topo had installed were lost, and every DUT lost its links to the cEOS neighbours. The main run had ended at 04:53. In the verification, 21 files ran wholly or partly after 06:23; their results match the runs before it, except the reboot test in §4. `testbed-cli.sh connect-topo` restores the flows; the bootstrap now disables the upgrade timers.
- A test killed partway through can leave configuration behind. Before this run, on the local testbed, an `acl/test_acl.py` stopped by hand left the table `DATA_INGRESS_IPV4_TEST`, which fails YANG validation, so every later test on that testbed failed in setup.

## 8. Not done

- About 70 lines that run `supervisorctl` on the DUT remain in 34 files outside the t0 list (dualtor, dualtor_mgmt, qos, dash, ha, gnmi_e2e, platform API and others). In the t0 list only two remain, and they only log: the debug output of `arp/test_arp_extended` and the diagnostics of `snmp/test_snmp_lldp`.
- The rock product items (shutdown log ordering, `auto_restart`, eventd `python`) and the Ubuntu-SONiC failures in §6 are left for the product side; only the AppArmor noise has a fix under review (#30).
- The branch is not pushed.
