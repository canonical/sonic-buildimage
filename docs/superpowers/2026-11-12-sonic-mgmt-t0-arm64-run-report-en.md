# sonic-mgmt t0 test list on the arm64 vs image of 202605_resolute

- Date: 2026-11-12
- Image: `canonical/sonic-buildimage` `202605_resolute` at `7a081af43c` plus the 9 commits of draft PR #18 (`feat/resolute-arm64-vs`, `d3b6c4c08b`). PR #18 is based on the older `d2f9ae8502`; its commits apply to `7a081af43c` without conflict and give the same diff (15 files, +56/−6). The build used that replay, `ddac4b7eec`, which is now the head of PR #18. Image version `test_arm64-vs-on-7a081af43c.0-ddac4b7ee`, Dockerfile mode with supervisord. There is no arm64 rock image: every `rockcraft.yaml` declares `platforms: amd64` only, and `build_rocks.sh` names `_amd64.rock`.
- Baseline: the amd64 Dockerfile image `HEAD.0-7a081af4` of the same commit, final rerun in the [t0 report](2026-11-11-sonic-mgmt-t0-run-report-en.md) §5.
- Test code: [canonical/sonic-mgmt#2](https://github.com/canonical/sonic-mgmt/pull/2) at `7b70925`, plus one local commit for an aarch64 DUT (`sonic-mgmt-aarch64-testbed.patch`, §2). §6 reruns the list with [canonical/sonic-mgmt#3](https://github.com/canonical/sonic-mgmt/pull/3), which adds arm64 vs support to sonic-mgmt.
- Test list: the same 271 files of the upstream t0 PR test list, `run_tests.sh -m individual`.
- Raw results and scripts: [data/2026-11-12-sonic-mgmt-t0-arm64-run/](data/2026-11-12-sonic-mgmt-t0-arm64-run/)
- This is the English version and the source of truth; the Chinese version is `-zh.md`

## 0. Conclusions

1. The arm64 image runs the whole t0 list: 3040 test cases, 1046 passed, 1943 skipped, 35 failed and 16 setup errors, against 1088, 1933, 16 and 3 on amd64. 71 cases differ (§3).
2. None of the 71 is an arm64 functional fault of the image. 45 come from the test side: 14 hash cases with random parameters, 26 cases where sonic-mgmt does not recognise the arm64 vs platform name, and 5 cases of a capture race in a dualtor helper. 19 TACACS cases came from a fault in the arm64 ptf image this run built, 1 from the newer cEOS neighbour, and 2 are intermittent tests (§4).
3. Four reboot cases fail intermittently on arm64. lldp, pmon and snmp start two to three minutes after boot, close enough to the test's 300 s wait that a slower boot misses it (§5).
4. Test cases take a median 1.33 times as long on arm64 as on amd64 (§3).
5. With canonical/sonic-mgmt#3, which makes sonic-mgmt treat the arm64 vs platform as vs, the list gives 1080 passed, 1933 skipped, 24 failed and 3 setup errors: the skipped count matches amd64, and the 26 cases that still differ come from the causes in §4 and §5 or from state an earlier test left on the testbed (§6).
6. sonic-mgmt does not run on arm64 as published. docker-sonic-mgmt and docker-ptf exist for amd64 only, and running them under qemu-user is far too slow. cEOS 4.32.5M has no arm64 build. The DUT needs an aarch64 libvirt domain. §2 lists what this run built or changed.

## 1. Setup

| Item | Value |
|---|---|
| Machine | Testflinger papat: 2 × Ampere Altra Max (Neoverse-N1), 256 cores, 501 GB, one 894 GB NVMe; Ubuntu 26.04 |
| Testbeds | 16 privileged LXD system containers, one vms-kvm-t0 testbed each. Neoverse-N1 has no nested virtualisation, so the DUT VMs use the host's `/dev/kvm` directly instead of running inside LXD VMs as on amd64 |
| DUT | 4 vCPU, 6 GiB, 33 e1000 NICs, `virt` machine with GICv3, UEFI |
| Neighbours | cEOSarm-lab 4.35.7.2M (amd64 baseline: cEOS64-lab 4.32.5M) |
| Split | 16 shards cut by the amd64 file durations; three hand-overs moved 7 files (`handoffs.json`) |
| Build | slave image and `target/sonic-vs.bin` built natively on papat: 46 min for the packages and image |
| Main run | 14:55 to 18:10 UTC |

The DUT disk is made the way `build_kvm_image.sh` makes the amd64 one: SONiC's arm64 ONIE recovery ISO installs `sonic-vs.bin` on a blank 16 GB disk (`scripts/make-vs-img.py`).

## 2. What the arm64 testbed needed

| Item | Problem | What this run did |
|---|---|---|
| UEFI firmware | resolute's edk2 2025.11 crashes under KVM | unpacked qemu-efi-aarch64 2026.05-2ubuntu3; installing it would pull a newer qemu |
| DUT boot | libvirt gives each DUT a blank NVRAM, so the firmware boots the removable path, where ONIE installed its own GRUB; the DUT came up in ONIE Rescue | copied SONiC's `grubaa64.efi` and `grub.cfg` to `\EFI\BOOT` of the disk (`scripts/esp-fallback.sh`). amd64 vs boots through the MBR and does not meet this |
| DUT domain | `sonic.xml.j2` describes an x86 q35 machine | `sonic_aarch64.xml.j2`, chosen by `ansible_architecture`; `stop_sonic_vm.yml` undefines with the `nvram` flag, which libvirt requires for a UEFI domain (`sonic-mgmt-aarch64-testbed.patch`) |
| docker-sonic-mgmt | registry image amd64 only; under qemu-user `ansible --version` takes 25 s against 1.4 s native | native build of the same upstream Dockerfile (upstream `e8bb4d24b`, the image's Tag label); the resolute fork's `sonic_py_common` wheel lacks `sonic_grpc`, so the upstream wheel was rebuilt from the amd64 image's pure-Python files |
| docker-ptf | the tag add-topo uses, `202605`, is amd64 only; under qemu-user `import scapy.all, ptf` takes 20 s against under 1 s | native build of the 202605 Dockerfile (`50b78a3b5`): Go and InfluxDB for arm64; the p4lang and python-saithrift debs (DASH and SAI tests only) left out; an empty `/sonic`, which the SONiC build leaves behind; ptf-py3 (pure Python) taken from the amd64 image. `tacacs_plus` and `ptf_tgen.sh` must keep their executable bit (§4.2) |
| ptf tag | add-topo pulls `docker-ptf:202605` from the registry and overwrites the local image | `ptf_modified: true` in host_vars |
| cEOS | 4.32.5M has no arm64 build | cEOSarm-lab 4.35.7.2M |

Two more details of the container setup: a privileged LXD container's systemd-binfmt clears the host's binfmt table when it boots, and vm_set's host setup writes host-wide sysctls, so the host sets those and the container skips that step.

## 3. Results

| | Passed | Skipped | Failed | Setup error |
|---|---|---|---|---|
| amd64, Dockerfile | 1088 | 1933 | 16 | 3 |
| arm64, Dockerfile | 1046 | 1943 | 35 | 16 |

Counts are test cases by call outcome, as in the t0 report. The full comparison is `compare-main-amd64-vs-arm64.txt`, made by `scripts/analyze2.py`; the 71 differing cases are in `differing-cases-main.txt`.

Over the 208 files that run longer than 30 s on amd64, the median arm64/amd64 time ratio is 1.33 (quartiles 1.23 and 1.43); pytest time totals 38.5 h against 30.9 h.

## 4. Differences and their causes

The 27 files with a differing case, apart from `hash/test_generic_hash`, were run twice more on fresh testbeds: once with sonic-mgmt seeing the DUT's platform as `x86_64-kvm_x86_64-r0` (rerun A, `eval-platform-alias.diff`, evaluation only), once unchanged (rerun B). `rerun-table.txt` has every case of these files in all four runs.

| Cause | Cases | Evidence |
|---|---|---|
| Test parameters drawn at random | 14 | `hash/test_generic_hash`, as in the t0 report |
| sonic-mgmt does not recognise the arm64 vs platform name | 26 | rerun A gives the amd64 outcome, rerun B the arm64 one |
| TACACS server not running in the arm64 ptf image | 19 | §4.2 |
| Capture race in the dualtor traffic helper | 5 | §4.3 |
| Reboot timing | 4 | §5 |
| cEOS 4.35 command syntax | 1 | §4.4 |
| Intermittent | 2 | `dhcpv6_multicast_recv` failed on amd64, as in the t0 report; `telemetry/test_events`, which upstream marks xfail on vs as flaky (sonic-buildimage#19943), failed in the main run and rerun B and passed in rerun A |

### 4.1 Platform name

On arm64 the vs image reports platform `arm64-qemu_armv8a-r0`, an alias of the x86 vs platform that PR #18 adds. sonic-mgmt recognises vs by the literal name `x86_64-kvm_x86_64-r0` in about 49 places: 24 conditions in the mark files, `is_virtual_platform()`, the reboot and platform helpers, and the gnmi helpers. On arm64 each of them takes the hardware branch:

| Cases | amd64 → arm64 |
|---|---|
| 16 in `ecmp/inner_hashing` | passed → skipped; the skip condition lists `x86_64-kvm_x86_64-r0` among the platforms that run |
| 4 `bgp/test_bgp_session`, 2 `bgp/test_bgp_stress_link_flap` | skipped as "not supported on Virtual Switch" → run; 3 fail |
| 2 `lldp/test_lldp` | passed → "eth0 is missing from LLDP table"; vs has no eth0 neighbour and `is_virtual_platform()` allows for that only by name |
| `ip/test_ip_packet` 0xffff checksum | passed → KeyError in `is_mellanox_fanout()`, which returns early by name on vs |
| `platform_tests/test_service_warm_restart` | skipped "not supported for kvm" → setup error |
| `generic_config_updater/test_lo_interface`, 4 `radv`, 4 `snmp_interfaces`, 2 `snmp_memory`, 5 `syslog`, `vlan/test_autostate_disabled` | loganalyzer only, not counted above: these ran on one DUT after a boot on which database.service first read an empty `database_config.json`, which left `process-reboot-cause` in a restart loop. All passed cleanly in both reruns. The latest boot of the other 15 DUTs did not show it |

### 4.2 TACACS

All 19 TACACS cases failed or errored in all three arm64 runs. The test starts the TACACS server in the ptf container with `service tacacs_plus restart`, which answered `tacacs_plus: unrecognized service`. The arm64 ptf build fetched its files through the GitHub contents API, which drops the executable bit, and `/etc/init.d/tacacs_plus` is one of the two executable files in the upstream directory (the other is `ptf_tgen.sh`). The testbed then falls back to local accounts, and every TACACS login fails. This is a fault of this run's harness, not of the image. With the two scripts made executable in the running ptf containers, the nine files that use the TACACS server (the six in `tacacs/`, `generic_config_updater/test_aaa`, `ip/test_mgmt_ipv6_only` and `ssh/test_ssh_limit`) ran again: 44 cases, 22 passed, 18 skipped and 4 failed, the same cases with the same outcomes as on amd64, teardown included (`tacacs-rerun.txt`).

### 4.3 dualtor capture race

The five dualtor failures read "No data could be read!" from scapy. `dump_intf_packets` stops tcpdump in the ptf container with `kill -s 2` and fetches the pcap at once, without waiting for tcpdump to exit. Every one of these failures has a fetch of an empty file (sha1 `da39a3ee…`) in its log, and scapy reports an empty file this way. The same cases pass in other arm64 runs; `active_tor_downstream[ipv6]` failed in all three.

### 4.4 cEOS 4.35

`pc/test_lag_2` lacp_rate sets `lacp rate fast` on the neighbour. cEOS 4.35.7.2M answers `% Invalid input`; the command is now `lacp timer`. sonic-mgmt's `set_interface_lacp_rate_mode` falls back to `lacp timer` when the first command fails or changes nothing, but `eos_config` raises on the failure before that check runs.

## 5. Reboot timing

`platform_tests/test_reboot` (cold over gNOI, warm over gNOI, continuous) and `gnmi/test_gnoi_system_reboot` cold failed with "Not all critical processes are healthy": 300 s after the reboot, lldp-syncd, lldpd and lldpmgrd were not running, and pmon not yet started. The outcome varies between runs: rerun A failed two of the four, rerun B none. On two rebooted DUTs, the kernel and systemd were up 37 and 41 s after boot, and lldp, pmon and snmp, which SONiC starts late, started 166 and 116 s after boot. That leaves the test's 300 s wait little margin on a busy host.

## 6. Rerun with canonical/sonic-mgmt#3

[canonical/sonic-mgmt#3](https://github.com/canonical/sonic-mgmt/pull/3), stacked on #2, adds three commits: the aarch64 DUT domain of §2; a `KVM_PLATFORMS` constant with both names, used by the code checks of §4.1 and by the ptf side of advanced-reboot; and the arm64 name next to the x86 one in 24 mark conditions. Conditions and checks that apply only to VPP are unchanged. All 271 files ran again with it on the same 16 testbeds, after deploy-mg and with the TACACS fix of §4.2 (`compare-pr3-amd64-vs-arm64.txt`, `handoffs-pr3.json`):

| | Passed | Skipped | Failed | Setup error |
|---|---|---|---|---|
| amd64 | 1088 | 1933 | 16 | 3 |
| arm64, #2 only (§3) | 1046 | 1943 | 35 | 16 |
| arm64, #3 | 1080 | 1933 | 24 | 3 |

None of the 26 platform-name cases of §4.1 differs any more, and there are no TACACS differences. The 26 cases that still differ:

| Cases | Cause |
|---|---|
| 14 `hash/test_generic_hash` | random parameters |
| 5 `platform_tests/test_reboot` | "Not all pmon daemons running": a FATAL `platform_api_server` in pmon, left by the main run's `test_techsupport` on that testbed. `start_platform_api_service` writes a python2 command when `import sonic_platform` fails in pmon. pmon installs `sonic_platform` only from a wheel in the platform's device directory, and neither the amd64 nor the arm64 vs image has one there. The pmon container survives deploy-mg, so the entry was still there |
| 2: `test_reboot` warm over gNOI, `gnmi/test_gnoi_system_reboot` cold | reboot timing (§5) |
| 2 dualtor | capture race (§4.3) |
| `pc/test_lag_2` lacp_rate | cEOS 4.35 (§4.4) |
| `dhcpv6_multicast_recv`, `disk/test_disk_exhaustion` | failed on amd64, passed on arm64; both intermittent |

Teardown results and loganalyzer matches beyond the known AppArmor noise are the same as on amd64, apart from the teardowns of the reboot cases.

## 7. Not done

- No arm64 rock image (no arm64 `rockcraft.yaml`).
- The cEOS 4.35 lacp fallback (§4.4) and the dualtor capture race (§4.3) are not fixed in sonic-mgmt.
- The dhcpmon core files seen on two arm64 DUTs also occur on amd64 (Dockerfile and rock), and are not followed up here.
