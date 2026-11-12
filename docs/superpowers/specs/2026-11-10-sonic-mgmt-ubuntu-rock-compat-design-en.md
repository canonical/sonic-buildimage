# sonic-mgmt support for Ubuntu (Resolute) SONiC and rock containers — design

- Date: 2026-11-10
- Test repository branch: `canonical/sonic-mgmt` `202605_resolute` (new), based on `sonic-net/sonic-mgmt` `202605` at `36c29fc`
- Images under test: `canonical/sonic-buildimage` `202605_resolute` at `7a081af43c`
  - rock + pebble vs image: CI run 42562456825, artifact `sonic-vs-img`
  - Dockerfile + supervisord vs image: built locally from the same commit
- This English version is the single source of truth; the Chinese version (`-zh.md`) is a translation

## 1. Goal and scope

Run the sonic-mgmt `202605` tests against both build modes of `202605_resolute` — Dockerfile containers under supervisord, and rock containers under pebble — with the same test code. When the two images give different results, the difference must come from the image, not from assumptions in the test harness.

**In scope:**

1. A dual-backend (supervisord / pebble) container process interface in `SonicHost`, and migration of the common helpers listed in §4.5 to it.
2. An OS profile helper, and the call sites that branch on the Debian codename (§5).
3. An A/B run on both images, and classification of every remaining difference (§6).

**Out of scope:** migrating the 134 direct `docker exec <container> supervisorctl` call sites inside individual tests (they move to the new interface test area by test area, later); fixing product-side issues such as the SNMP `sysDescr` text, the missing host `/var/log/frr/bgpd.log` and the image version naming (the A/B run classifies them first); `supervisorctl` on PTF hosts; runtime validation on multi-ASIC, dual-ToR or chassis testbeds (none available); upstreaming to sonic-net.

## 2. Decisions

| Topic | Decision |
|---|---|
| Where compatibility lives | In sonic-mgmt. The images are tested as built |
| Backend detection | Per container, at query time, inside the container. No cache |
| Migration scope | Common helpers and the pid/kill helpers. Direct call sites later, per test area |
| `group:` entries in pebble containers | Read the rendered `[group:X]` sections from `/etc/supervisor/conf.d/*.conf` in the container. A group absent from the rendered conf has no members, as under supervisord; no rendered conf at all fails the check |
| State vocabulary | supervisord state names; the native pebble state is kept alongside |
| OS checks | By Debian base generation, not by codename string |
| Other Ubuntu differences (version naming, SNMP, coreutils, docker 29, Python 3.14, log noise, sshd) | Decided after the A/B run, from its results |
| Local July patches (deploy-mg restarts `ssh.service`, conftest `collect_ignore_glob`) | Not carried. Re-added only if the A/B run shows they are needed |

## 3. Verified facts

Each item below was checked on the images under test; none is inferred.

| Fact | Evidence |
|---|---|
| Rock images ship `/etc/supervisor/critical_processes` and bash, but no `supervisorctl` | 16 `rockcraft.yaml` files stage the file; database, orchagent and fpm-frr render it in their start scripts; the database rock (`base: bare`) stages bash |
| sonic-mgmt decides process health from `docker exec X supervisorctl status`; empty or unrecognised output marks the container unhealthy | `SonicHost.all_critical_process_status()` and `parse_service_status_and_critical_process()` in `tests/common/devices/sonic.py` |
| The same function backs the sanity check and the waits after `config reload` and reboot, so `--skip_sanity` does not avoid it | `check_processes` in `sanity_check/checks.py`; `wait_critical_processes()` in `platform/processes_utils.py` |
| One switch runs both backends: on the rock vs image 16 running containers are rocks; syncd and gbsyncd, and after deploy-mg also bmp and otel, run supervisord | Probe of all running containers, before and after deploy-mg |
| syncd and gbsyncd carry a `pebble` binary but run no pebble daemon, so the presence of the binary does not identify the backend; whether `pebble services` answers does | Same probe |
| `pebble services --format json` returns `name`, `startup`, `current`, `current-since` and no pid. The text output's `Since` column contains spaces (`today at 07:40 UTC`) | docker-teamd rock, pebble 1.33 |
| Each pebble service runs as a direct child of pebble, as the leader of its own process group | Same run: `sleep 1000` service had pid = pgid = 56, ppid 1; all 16 rocks on the vs image |
| `current-since` of an active service is the start time of the process that runs it. Computed with `/proc/stat` btime, which drops the fraction of a second, the gap is 1.000–1.024 s on one boot and 0.178–0.193 s on another; within one container it varies by at most 0.02 s | Both captures; on the t0 DUT `$EPOCHREALTIME` minus `/proc/uptime` is btime + 0.18 s |
| gnmi shares the host PID namespace (`--pid=host`); in the database rock, root cannot read `/proc/1/root` | `docker inspect`; probe on the rock vs image |
| The dhcp-relay rock renders `docker-dhcp-relay.supervisord.conf` into `/etc/supervisor/conf.d/` at start. Its `[group:dhcp-relay]` section exists only when a VLAN has DHCP servers; the Dockerfile image renders the same template | `dockers/docker-dhcp-relay/start.sh` (pebble branch); rendered conf on the rock vs image |
| Without VLAN config the radv rock defines no `radvd` service | Probe of radv |
| Python's `str.splitlines()`, which Ansible uses for `stdout_lines`, also splits on `\x1c`, `\x1d` and `\x1e` | Python documentation; reproduced by a failing probe test |
| Tests read the state from `split()[1]` and the pid from `split()[3]` of a `supervisorctl status` line; pmon daemon tests expect `STOPPED` after a stop | `get_pmon_daemon_status()`; `get_program_info()` / `get_group_program_info()` in `dut_utils.py` and `test_container_autorestart.py`; `tests/platform_tests/daemon/test_*.py` |
| A missing `critical_processes` file means no critical processes: `get_critical_group_and_process_lists()` returns empty lists and success | `tests/common/devices/sonic.py` at `36c29fc` |
| Ubuntu: `VERSION_CODENAME=resolute`, `/etc/debian_version` = `forky/sid`. Debian 202605: `trixie`, `13.5` | Both root filesystems |
| Not different between the two images: sudo (C sudo 1.9.x, not sudo-rs); bash with the plugin patch and `bash_tacplus`; sysctl file `/usr/lib/sysctl.d/90-sonic.conf`; chrony; OpenSSH 10.x; `release: 'none'` in `sonic_version.yml` | Package and file comparison of both root filesystems |

Pebble states observed:

| Situation | `current` | `current-since` |
|---|---|---|
| Running | `active` | set |
| Stopped with `pebble stop` | `inactive` | set |
| Exited 0 with `on-success: ignore` | `inactive` | set |
| Exited 1 with `on-failure: ignore` | `error` | set |
| Waiting to restart | `backoff` | set |
| Never started | `inactive` | absent |

## 4. Component 1: container process interface

### 4.1 Module and data model

New module `tests/common/helpers/container_processes.py`, importable without Ansible (same rule as `ansible/module_utils/sonic_release_utils.py`). It needs the standard library and PyYAML, which docker-sonic-mgmt has.

`ProcessInfo`:

| Field | Meaning |
|---|---|
| `name` | Program name without group |
| `group` | Group name, or `None` |
| `state` | One of `RUNNING`, `STOPPED`, `EXITED`, `FATAL`, `BACKOFF`, `STARTING` |
| `pid` | Container-namespace pid; `-1` when not running or not resolved |
| `raw_state` | The backend's own state word |
| `pid_note` | Why `pid` is `-1` when the process is running |

`full_name` returns `group:name` when there is a group, otherwise `name`.

`ContainerProcesses`: `container`, `backend` (`"supervisord"`, `"pebble"` or `None`), `running`, `processes`, `critical_groups`, `critical_programs`, `critical_parse_ok` (`False` when a `critical_processes` line is malformed), `error`. `get(name, bare=True)` accepts a full name, and also a bare name unless `bare=False`; supervisorctl itself knows a grouped program only by its full name.

Functions: `build_probe_command(container, timeout=None)`, `parse_probe_output(container, rc, stdout, allow_bare_critical=False)`, `build_control_command(container, action, names)`, `critical_process_status(result, groups=None, programs=None, strict=True)`, and `parse_proc_line(line)`. `timeout` puts `timeout <n>` in front of the command. With `strict=False` a malformed `critical_processes` line is skipped instead of failing the container, which is what `all_critical_process_status()` did.

### 4.2 Probe

One command per container: `docker exec <container> bash -c '<script>'`. The command keeps the `docker exec <container>` prefix. The script uses bash builtins only, so it does not depend on which tools each rock stages (the database rock, for example, has no `sed`). It prints sections, each introduced by a line that is exactly `@@<section>@@`:

| Section | Content |
|---|---|
| `backend` | `pebble` if `pebble services` succeeds; else `supervisord` if `supervisorctl` is on `PATH`; else `unknown` |
| `critical` | `/etc/supervisor/critical_processes`, or the marker `@@critical-missing@@` |
| `status` (supervisord) | `supervisorctl status` |
| `services` (pebble) | `pebble services --format json` |
| `plan` (pebble) | `pebble plan` |
| `btime` (pebble) | The boot time from `/proc/stat` |
| `procs` (pebble) | One line per process: pid, ppid, pgid, start time in clock ticks, then argv joined with `\x1f`; a newline inside an argument is written as `\x02` |
| `groups` (pebble) | `/etc/supervisor/conf.d/*.conf` |
| `end` | Marks complete output |

The probe leaves out itself and its subshells. When PID 1 is not pebble, the container shares the host PID namespace, and only processes whose `/proc/<pid>/root` is the container's root are kept. A non-zero exit from `docker exec` means the container is not running.

### 4.3 Parsing rules

**supervisord:** the current rules stay: split each line into name, state and rest; a state outside the six words makes the result invalid; `pid N,` gives the pid when `RUNNING`; `group:name` gives the group.

**pebble:**

| `current` | `state` |
|---|---|
| `active` | `RUNNING` |
| `backoff` | `BACKOFF` |
| `error` | `EXITED` |
| `inactive` | `STOPPED` |

Known limitation: a one-shot service that exited normally shows `STOPPED`, where supervisord shows `EXITED`. One-shot services are not critical, and the existing tests accept either word after a process stops.

A program named in `critical_processes` that pebble does not define is reported `STOPPED` with `raw_state` `undefined`, as supervisord reports a configured program that has not started.

Group membership: each `programs=` list in a `[group:G]` section puts those names in group `G`. A group absent from the rendered conf has no members, as under supervisord. If `critical_processes` names a group and the container has no rendered conf at all, `error` is set.

The pid of a running service is the direct child of pebble that runs it, which is the pid supervisord reports once a wrapper has exec'd its program. Trailing empty arguments, left by programs that rewrite their title, are dropped before matching. The rules below are tried in order; in each, a service takes a child only if that child is its only candidate and no other unresolved service lists the same child:

1. argv equals `shlex.split(command)`.
2. argv equals the command preceded by one or two interpreter arguments: a script run through its shebang (`python3 /usr/bin/bgpcfgd`).
3. The process name — argv[0]'s basename up to the first `:` or space — equals the service name: `orchagent.sh` exec's orchagent; lldpd retitles itself `lldpd: monitor.`.
4. The child's start time plus the container's usual gap is within 0.1 s of the service's `current-since`. This covers wrappers that exec a differently named binary (`gnmi-native.sh` → `telemetry`) and instances that look the same (`redis` and `redis_bmp`).

The usual gap is `current-since` minus the start time, taken over the services rule 1 matched in the same container. It cancels the fraction of a second that btime drops (0.18 s on the t0 DUT). A clock step after boot shifts the gap of everything started before it, so only the largest set of gaps within 0.1 s of each other counts, and its median is the usual gap; when two such sets are equally large there is no usual gap and rule 4 is not used. A rule 3 match is dropped when its own gap disagrees with the usual gap, or when another unclaimed child also fits its start time; rule 4 then decides.

Otherwise `pid` is `-1` and `pid_note` says that no rule matched. In both captures of the rock vs image these rules give every active service a pid of its own.

### 4.4 Control

`build_control_command(container, action, names)`, where `action` is `start`, `stop` or `restart`, produces one command that keeps the `docker exec <container>` prefix and branches inside the container: under pebble it runs `pebble <action>` with the group prefix removed from each name; under supervisord it runs `supervisorctl <action>` with the names unchanged. The return code is 0 on success and non-zero on failure under both backends.

`build_signal_command(container, signal, names)` branches the same way to `pebble signal` or `supervisorctl signal`. The signal is a name such as `SIGHUP` or `HUP`; anything else is rejected before it reaches the shell. Both backends return 1 for a program the container does not define.

### 4.5 SonicHost interface and migrated helpers

New `SonicHost` methods:

- `get_process_table(container)` returns a `ContainerProcesses`.
- `get_process_tables(containers)` runs the probes as one `shell_cmds` batch, each bounded to 60 s, and matches results by position, not by parsing the command string.
- `control_container_process(container, action, names, module_ignore_errors=False)`.
- `signal_container_process(container, signal, names, module_ignore_errors=False)`.
- `os_profile(container=None)` (§5).

The names avoid `dut_utils.get_container_processes()`, an existing helper based on `docker top`.

Helpers moved onto the new interface, with signatures and return values unchanged:

| File | Functions |
|---|---|
| `tests/common/devices/sonic.py` | `get_critical_group_and_process_lists`, `critical_process_status`, `all_critical_process_status`, `start_pmon_daemon`, `stop_pmon_daemon_service`, `get_pmon_daemon_status`, `get_pmon_daemon_states`, `kill_bgpd`, `start_bgpd`, `is_service_running` |
| `tests/common/devices/multi_asic.py` | `modify_syslog_rate_limit`: edits `rsyslog.conf` from the host through `/proc/<pid>/root`, because the database rock has no `sed`, and restarts rsyslogd through the control command |
| `tests/common/helpers/dut_utils.py` | `get_program_info`, `get_group_program_info`, `verify_orchagent_running_or_assert` |
| `tests/common/utilities.py`, `tests/common/helpers/dut_utils.py` | `kill_process_by_pid` refuses a pid that is not positive |
| `tests/autorestart/test_container_autorestart.py` | Its copies of `get_program_info`, `get_group_program_info` and `kill_process_by_pid` are replaced by the `dut_utils` versions; its own running check and program start go through the process table and the control command |
| `tests/process_monitoring/test_critical_process_monitoring.py` | The `supervisorctl start` that restores a stopped critical process |

Behaviour kept from the supervisorctl parsing: pmon's critical lists keep only running programs; `get_program_info()` picks the first program whose name contains the given string. `get_pmon_daemon_status()` of a daemon the container does not have returns `(None, -1)`. `get_pmon_daemon_status()` and `is_service_running()` look a program up with `bare=False`, because the supervisorctl output they parsed named a grouped program only as `group:program`. `all_critical_process_status()` uses `strict=False`. `critical_group_process()` had no other caller and is removed; `parse_service_status_and_critical_process()` stays public and unchanged.

### 4.6 Error handling

| Condition | Result |
|---|---|
| Container not running | `running=False`; critical status `False`, as today |
| Backend `unknown` | `error` set; critical status `False` |
| `critical_processes` missing | No critical processes, as today; the status depends on the other programs being readable |
| Malformed `critical_processes` line | `critical_parse_ok=False`; critical status `False`, as today |
| Critical group in a pebble container with no rendered supervisord conf | `error` names the group; critical status `False` |
| Running process whose pid is not resolved | `pid=-1`, `pid_note` set; the critical status is not affected. `kill_process_by_pid()` refuses a pid that is not positive: `kill -SIGKILL -1` in gnmi, which shares the host PID namespace, kills every process on the switch |
| JSON or YAML that cannot be parsed, pebble output of an unexpected shape, or output without `end` | `error` set; critical status `False` |
| A probe that hangs | `get_process_tables()` bounds each probe with `timeout 60`, because `shell_cmds` drops its own timeout for commands that contain a single quote |

## 5. Component 2: OS profile

New module `tests/common/helpers/os_profile.py`, standard library only.

`parse_os_profile(os_release_text, debian_version_text)` returns `OsProfile(id, version_id, codename, debian_base)`:

- Debian: `debian_base` is its codename.
- Ubuntu: `debian_base` comes from `/etc/debian_version`. `forky/sid` gives `forky`; a numeric value maps by major version (10 `buster`, 11 `bullseye`, 12 `bookworm`, 13 `trixie`, 14 `forky`).
- Any other value gives `debian_base=None`.

`debian_base_at_least(name)` compares in the order `buster < bullseye < bookworm < trixie < forky < duke`, returns `False` when `debian_base` is `None`, and raises `ValueError` for a name outside that list. `is_debian` is true when `ID` is `debian`.

`os_profile_command(container=None)` builds the command that prints both files, and `parse_os_profile_output(stdout)` parses what it prints. The command fails when `/etc/os-release` cannot be read; `/etc/debian_version` is optional, because `os-release` alone identifies Debian. `SonicHost.os_profile(container=None)` runs it on the host, or inside `container` when given, and raises when it fails. A successful host result is cached per `SonicHost` object; container results are not cached.

| Call site | Change | How it is checked |
|---|---|---|
| `tests/memory_checker/test_memory_checker.py` `get_restart_expected_logre` | `debian_base_at_least("bookworm")` selects the systemd log format with the unit name | vs testbed |
| `tests/copp/copp_utils.py` `_install_nano` (syncd container) | `debian_base_at_least("bookworm")` selects the current install path | vs testbed |
| `tests/dualtor/test_mux_port_iptables_entries.py` | `debian_base_at_least("trixie")` | No dual-ToR testbed; `os_profile` unit tests only |

The waits for a DUT to come back match the sshd banner. On Ubuntu it is `SSH-2.0-OpenSSH_10.2p1 Ubuntu-2ubuntu3`, which `OpenSSH_[\w\.]+ Debian` misses: deploy-mg timed out after 600 s, and `reboot()` would time out on every reboot test. All 14 copies of the regex — `tests/common/reboot.py`, six tests, deploy-mg, `reboot_sonic.yml` and the l2-mode, vchassis and nut playbooks — accept `(Debian|Ubuntu)`.

Not changed:

- The saithrift URL rewrite in `tests/test_pretest.py` reads the syncd codename, but it runs only for official Microsoft image versions; other version strings, including those of `202605_resolute` builds, are treated as private and keep the URL as given.
- The sysctl choice in `dut_utils.enable_nat_for_dpus` and `dpu_utils` already takes the right branch on Ubuntu.

## 6. Verification

### 6.1 Unit tests

Files under `tests/common/unit_tests/helpers/`, run with `python3 -m pytest --noconftest --confcutdir=tests/common/unit_tests tests/common/unit_tests/helpers/`. Written before the code they test. Inputs:

- probe output of every running container on the rock vs image, under `tests/common/unit_tests/helpers/data/container_processes/`: `rock-7a081af43c/` without configuration and `rock-7a081af43c-t0/` after deploy-mg; `dockerfile-7a081af43c-t0/` from the Dockerfile vs image after deploy-mg, which the new parser and the old supervisorctl parsing must read the same way;
- the same probe output with btime shifted by a second, and with a clock step between services;
- the `critical_processes` parsing of `36c29fc`, run on the same inputs as the new parser;
- `/etc/os-release` and `/etc/debian_version` from both root filesystems;
- the probe script run locally against stub `pebble` and `supervisorctl` commands;
- constructed cases: unresolved pid, missing group definition, container not running, unknown backend, malformed JSON, truncated output.

The SonicHost methods and the `dut_utils` helpers are loaded with `ast` and run against a fake DUT that serves the captured probe output.

### 6.2 A/B run

A vms-kvm-t0 testbed with cEOS 4.32.5M neighbours on the build host, once per image. Tests: the sanity checks that run around every module, plus `test_pretest.py`, `autorestart`, `platform_tests/daemon`, `memory_checker`, `copp`, `process_monitoring`.

The second round runs the upstream t0 PR test list, 271 files, on both images. It runs on a Testflinger machine, split across twelve testbeds in LXD virtual machines: six shards per image. The test-area call sites it finds are moved onto the same interface, and the files they affect are rerun on both images.

### 6.3 Acceptance criteria

1. The unit tests pass.
2. On the Dockerfile image, every selected test has the same outcome with the new branch as with unmodified upstream `202605`. The refactor must not change the supervisord path.
3. On the rock image, the sanity process check passes on a healthy switch; every entry in every running container's `critical_processes` resolves to a state; every critical process in a rock container has a pid, or a `pid_note` that explains why not.
4. Every result that differs between the two images, and every remaining failure, is assigned to one cause with evidence: version naming, SNMP `sysDescr`, `bgpd.log`, coreutils, docker 29, Python 3.14, log noise, sshd, a real rock difference, or the testbed. `process_monitoring` is expected to fail on the rock image: the rock listener does not raise the periodic alert for `auto_restart` values other than `enabled`.

The classification is written up in this repository and is the input to the next round.

## 7. Branch and commits

`202605_resolute` on `canonical/sonic-mgmt` is upstream `sonic-net/sonic-mgmt` `202605` at `36c29fc`. The changes are draft PR [canonical/sonic-mgmt#2](https://github.com/canonical/sonic-mgmt/pull/2), branch `feat/resolute-ubuntu-rock-compat`: 21 GPG-signed commits in this order, one topic each, each passing the unit tests on its own:

1. The OS profile module, `SonicHost.os_profile()` and their unit tests
2. The OS call sites
3. The sshd banner regex
4. The monit sanity check and memory_checker accepting `Waiting`
5. The container process module (probe, parsing, pid rules, control and signal commands), its unit tests, the captured probe output and the parity tests against the supervisorctl parsing it replaces
6. The `SonicHost` interface, and the common helpers in `sonic.py`, `dut_utils.py` and `multi_asic.py` moved onto it, with their unit tests
7. The test-local helpers in `autorestart` and `process_monitoring`
8. `kill_process_by_pid()` refusing a pid that is not positive
9. The SNMP subagent check
10. dhcp_relay program states and pids
11. The gnmi helpers
12. arp_update and rsyslogd control in arp, crm, dualtor, vlan, pc and syslog
13. The like-bgp container's entrypoint, and the fpmsyncd restart
14. bmp program states
15. The radvd SIGHUP
16. thermalctld, lm-sensors and lldpmgrd
17. The telemetry event helpers
18. arp_update and ycabled in the dualtor tests
19. The qos_sai service control
20. The dhcp_server fixture
21. Two diagnostics that log the process table

The A/B results are in [../2026-11-10-sonic-mgmt-resolute-ab-report-en.md](../2026-11-10-sonic-mgmt-resolute-ab-report-en.md), and the t0 run in [../2026-11-11-sonic-mgmt-t0-run-report-en.md](../2026-11-11-sonic-mgmt-t0-run-report-en.md).

## 8. Risks

| Risk | Handling |
|---|---|
| `current-since` stops being the process start, or two services that need rule 4 start within 0.1 s of each other | Only rule 4 depends on it. On the rock vs image rules 1–3 resolve 70 of the 75 running services before deploy-mg and 65 of 70 after it; in both the other five are redis, redis_bmp, gnmi-native, dialout and rest-server. A child with more than one candidate service is left unmatched, so a miss leaves `pid=-1` with a note; it is not guessed |
| A later pebble changes its JSON output | Output that cannot be parsed, or an unknown state word, sets `error` instead of raising |
| The refactor changes the supervisord path | Acceptance criterion 2 |
| One probe per container per query | No more `docker exec` calls than today (today: two per container) |
