# sonic-mgmt 202605 on the Dockerfile and rock vs images of 202605_resolute: A/B results

- Date: 2026-11-10
- Images, both from `canonical/sonic-buildimage` `202605_resolute` at `7a081af43c`:
  - rock + pebble: CI run 42562456825, artifact `sonic-vs-img`, image version `202605_resolute.0-7a081af43`
  - Dockerfile + supervisord: built locally from the same commit (detached HEAD), image version `HEAD.0-7a081af4`
- Test code: `canonical/sonic-mgmt` branch `202605_resolute`, 11 signed commits on `sonic-net/sonic-mgmt` `202605` `36c29fc`, local only (not pushed). The upstream run uses `36c29fc` unmodified.
- Testbed: vms-kvm-t0 on the build host, cEOS 4.32.5M neighbours, docker-sonic-mgmt with ansible-core 2.20.11. The inventory sets `ansible_python_interpreter: /usr/bin/python3` for the DUT.
- Design: [specs/2026-11-10-sonic-mgmt-ubuntu-rock-compat-design-en.md](specs/2026-11-10-sonic-mgmt-ubuntu-rock-compat-design-en.md)
- Raw results and scripts: [data/2026-11-10-sonic-mgmt-ab/](data/2026-11-10-sonic-mgmt-ab/)
- This is the English version and the source of truth; the Chinese version is `-zh.md`

## 0. Conclusions

1. With the `202605_resolute` branch, the selected sonic-mgmt tests run on both images. Sanity, pretest and posttest pass on both, and autorestart passes for all 13 containers it tests, under pebble and under supervisord.
2. The branch does not change results on the supervisord path. On the Dockerfile image, the branch (R2) and upstream (R3) differ in 8 test cases, and each one is upstream hitting one of two Ubuntu problems the branch fixes: monit 5.35 reporting `Waiting`, and the sshd banner regex.
3. The rock image differs from the Dockerfile image in one test, `process_monitoring::test_monitoring_critical_processes`. With `auto_restart` disabled, the exit of a critical process stops the whole rock container, while supervisord keeps the container's other programs running. This is the limitation PR #28 states.
4. `memory_checker::test_memory_checker_recover` failed on rock and passed in R2, but it fails 5 times out of 5 on the Dockerfile image when run alone. It is a race in the test, not a rock difference.
5. Running the tests exposed six compatibility problems in sonic-mgmt beyond the design. All six are fixed on the branch, each with unit tests (§4).

## 1. Setup

| Run | sonic-mgmt | Image | Time (UTC) |
|---|---|---|---|
| R1b | branch `202605_resolute` | rock | 11:45–12:47 |
| R2 | branch `202605_resolute` | Dockerfile | 12:57–14:54 |
| R3 | upstream `36c29fc` | Dockerfile | 15:05–17:11 |

R1b is the second run on the rock image. The first, R1, found the two autorestart and memory_checker problems fixed in `a6be7f4` and `5d2fbdf`. R2 and R3 run against the same deployment; R3 starts 11 minutes after R2, because memory_checker restarts monit at teardown and upstream rejects the `Waiting` state that follows for 10 minutes (§3.1).

Each run executes, through `run_tests.sh -m individual`, the pretest and posttest plus `autorestart/test_container_autorestart.py`, the seven files of `platform_tests/daemon/`, `memory_checker/test_memory_checker.py`, `copp/test_copp.py` and `process_monitoring/test_critical_process_monitoring.py`.

Two groups give no signal on this testbed: all 28 copp cases are skipped on t0 by their conditional mark ("covered by t1-lag topology"), and all platform daemon cases are skipped on vs.

The image versions differ, so sonic-mgmt guesses release `202605` for the rock image and `unknown` for the Dockerfile image. In the selected tests, only four conditional marks use the release or build version: two in copp, which is skipped anyway, and two in memory_checker and `test_orchagent_heartbeat` with `release in ['202412']`, which is false for both. The naming does not affect this comparison.

## 2. Results

| Module | R1b rock | R2 Dockerfile | R3 Dockerfile, upstream |
|---|---|---|---|
| pretest | 8 pass, 4 skip | 8 pass, 4 skip | 8 pass, 4 skip |
| autorestart | 13 pass, 7 skip | 13 pass, 7 skip | 13 pass, 6 skip, 1 error |
| memory_checker | 3 pass, 1 fail | 4 pass | 4 errors |
| process_monitoring | 1 pass, 1 fail | 2 pass | 2 errors |
| copp | 28 skip | 28 skip | 28 skip |
| platform_tests/daemon | 28 skip | 28 skip | 28 skip |
| posttest | 4 pass, 1 skip | 4 pass, 1 skip | 3 pass, 1 skip, 1 error |

Counts are test cases as `compare.py` merges them: a case that errors at teardown counts once, as an error, whatever its call did. The junit files also count one collection-time skip (`transceiver/oir`) in pretest and posttest, which the table leaves out.

## 3. Differences

### 3.1 R2 against R3: same Dockerfile image, branch against upstream

The 8 cases that differ all pass in R2 and error in R3:

| Case | R3 |
|---|---|
| memory_checker `test_memory_checker`, `test_memory_checker_recover`, `test_monit_reset_counter_failure` | "Monit is not running after restarted!" |
| memory_checker `test_memory_checker_without_container_created` | teardown errors after the same monit wait |
| process_monitoring `test_monitoring_critical_processes`, `test_orchagent_heartbeat` | "DUT vlab-01 did not startup" during sanity recovery |
| autorestart `test_containers_autorestart[telemetry]` | same, at teardown |
| posttest `test_collect_dualtor_logs` | same, at teardown |

Both chains start with monit being restarted, by memory_checker's setup or by a config reload in a teardown. Monit 5.35 then shows `arp_update_checker`, `container_eventd` and `controlPlaneDropCheck` as `Waiting`:

- memory_checker's own `check_monit_running()` gives up after 400 s (fixed on the branch in `5d2fbdf`).
- Upstream's sanity monit check fails, and its recovery reboots the DUT and then waits for the banner `OpenSSH_[\w\.]+ Debian`. The Ubuntu banner is `OpenSSH_10.2p1 Ubuntu-2ubuntu3`, so the wait times out, and every following case errors in recovery (fixed in `db8849b` and `8b57ba6`).

No other case differs, so the refactor leaves the supervisord path unchanged (design §6.3 criterion 2).

### 3.2 R1b against R2: same branch, rock against Dockerfile

Two cases differ.

**`process_monitoring::test_monitoring_critical_processes` — rock difference.** The test disables `auto_restart` on every container, then kills each critical process in turn and expects an alert. In R1 and again in R1b, after `kill -SIGKILL` of zebra in bgp, the next critical process, staticd, read `STOPPED`, and the teardown found the bgp container not running. Rock containers declare critical services `on-failure: shutdown`, so pebble stops the whole container. Under supervisord with `auto_restart` disabled, only the killed program exits, and R2 passes. PR #28 lists `auto_restart` values other than `enabled` as unsupported in rocks. This is a product-side gap; sonic-mgmt is not changed for it.

**`memory_checker::test_memory_checker_recover` — race in the test, not rock.** The test makes gnmi exceed its memory threshold, waits until monit reports one failure, stops the allocation, and expects no restart. The monit rule is `if status == 3 for 2 times within 20 cycles` with a 5 s cycle during the test. In R1b the second check still saw 445 MB and monit restarted gnmi. Run alone on the Dockerfile image, the test failed 5 times out of 5 the same way (`memory_checker_recover-alone-on-dockerfile.txt`); it passed in R2 only within the full module. In a container simulation of the same rule (fail, then clear the condition as soon as monit shows the failure), both monit 5.34.3 (Debian 13) and 5.35.2 (Ubuntu 26.04) fire the action, because the test sees the first result only after the next check has started. Whether the test passes on a Debian vs image was not checked here.

`docker exec gnmi pkill -f time.sleep` also returns -15: gnmi shares the host PID namespace, so pkill kills every process on the switch whose command line contains the pattern, including the shell that ran it. On a reproduction, pkill also killed the allocating process and memory dropped to 78 MiB, so this does not cause the failure. The test ignores the error.

## 4. sonic-mgmt problems found by the runs

| Problem | Evidence | Commit |
|---|---|---|
| 14 copies of the sshd banner regex accept only `Debian` | deploy-mg timed out after 600 s; upstream sanity recovery in R3 | `8b57ba6` |
| Monit 5.35 shows a program checked `every N cycles` as `Waiting` until its first result; sanity rejected it | pretest failed; in containers with a 2 s cycle, 5.34.3 showed `OK` at 2 s and 5.35.2 showed `Waiting` until 18 s | `db8849b` |
| Same in memory_checker's own monit readiness check | all four memory_checker cases errored in R1 | `5d2fbdf` |
| `/proc/stat` btime drops the fraction of a second, so an absolute start-time window misses pebble services | gap of 0.18 s on the deployed DUT against 1.0 s on the first capture; gnmi-native, dialout, rest-server and redis lost their pids | `a9175dc` |
| `modify_syslog_rate_limit()` restarted rsyslogd with supervisorctl and edited the file with the container's sed; the database rock has no sed | pretest `test_disable_rsyslog_rate_limit` failed on every rock | `08d506e` |
| autorestart still ran supervisorctl in two places | all 10 rock containers failed in R1; bmp and syncd passed | `a6be7f4` |

`08d506e` also moves `SonicHost.is_service_running()` and `dut_utils.verify_orchagent_running_or_assert()` off supervisorctl.

## 5. The design's open categories

| Category (design §6.3 criterion 4) | In these runs |
|---|---|
| Version naming | No effect on the selected tests (§1) |
| SNMP `sysDescr`, host `bgpd.log` | Not among the selected tests; product side, left for later |
| Rust coreutils, docker 29, Python 3.14 | No failure in the selected tests traces to them |
| Log noise (loganalyzer, dmesg) | No loganalyzer failure in the selected tests |
| sshd | Banner regex fixed; deploy-mg restarts sshd without the July local patch |
| July conftest `collect_ignore_glob` patch | Not needed when tests are named with `run_tests.sh -c` |

## 6. Not done

- No Debian vs image was available, so `test_memory_checker_recover` was not run against Debian.
- The other test areas: 134 direct `supervisorctl` calls remain in test-area code, copp needs a t1-lag topology, and the platform daemon tests need hardware.
- Multi-ASIC and dual-ToR paths are covered by unit tests only.
- The branch is not pushed, and the product-side items (the rock `auto_restart` gap, SNMP `sysDescr`, `bgpd.log`, image version naming) are left for later.
