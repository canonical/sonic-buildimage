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
2. An OS profile helper, and the four call sites that branch on the Debian codename (§5).
3. An A/B run on both images, and classification of every remaining difference (§6).

**Out of scope:** migrating the 134 direct `docker exec <container> supervisorctl` call sites inside individual tests (they move to the new interface test area by test area, later); fixing product-side issues such as the SNMP `sysDescr` text, the missing host `/var/log/frr/bgpd.log` and the image version naming (the A/B run classifies them first); `supervisorctl` on PTF hosts; runtime validation on multi-ASIC, dual-ToR or chassis testbeds (none available); upstreaming to sonic-net.

## 2. Decisions

| Topic | Decision |
|---|---|
| Where compatibility lives | In sonic-mgmt. The images are tested as built |
| Backend detection | Per container, at query time, inside the container. No cache |
| Migration scope | Common helpers and the pid/kill helpers. Direct call sites later, per test area |
| `group:` entries in pebble containers | Read the rendered `[group:X]` sections from `/etc/supervisor/conf.d/*.conf` in the container. A group with no readable definition fails the check |
| State vocabulary | supervisord state names; the native pebble state is kept alongside |
| OS checks | By Debian base generation, not by codename string |
| Other Ubuntu differences (version naming, SNMP, coreutils, docker 29, Python 3.14, log noise, sshd) | Decided after the A/B run, from its results |
| Local July patches (deploy-mg restarts `ssh.service`, conftest `collect_ignore_glob`) | Not carried. Re-added only if the A/B run shows they are needed |

## 3. Verified facts

Each item below was checked before this design; none is inferred.

| Fact | Evidence |
|---|---|
| Rock images ship `/etc/supervisor/critical_processes` and bash, but no `supervisorctl` | 16 `rockcraft.yaml` files stage the file; database, orchagent and fpm-frr render it in their start scripts; the database rock (`base: bare`) stages bash |
| sonic-mgmt decides process health from `docker exec X supervisorctl status`; empty or unrecognised output marks the container unhealthy | `SonicHost.all_critical_process_status()` and `parse_service_status_and_critical_process()` in `tests/common/devices/sonic.py` |
| The same function backs the sanity check and the waits after `config reload` and reboot, so `--skip_sanity` does not avoid it | `check_processes` in `sanity_check/checks.py`; `wait_critical_processes()` in `platform/processes_utils.py` |
| `pebble services --format json` returns `name`, `startup`, `current`, `current-since` and no pid. The text output's `Since` column contains spaces (`today at 07:40 UTC`) | Run against the docker-teamd rock, pebble 1.33 |
| Each pebble service runs as a direct child of pebble, as the leader of its own process group; its argv equals the service command when the program does not exec | Same run: `sleep 1000` service had pid = pgid = 56, ppid 1 |
| One switch runs both backends: on the rock vs image 17 containers are rocks; syncd, mux, stp, dhcp-server and the others run supervisord | `build_rocks.sh --list` |
| The dhcp-relay rock renders `docker-dhcp-relay.supervisord.conf` into `/etc/supervisor/conf.d/` at start, including `[group:dhcp-relay] programs=dhcprelayd,...` | `dockers/docker-dhcp-relay/start.sh` (pebble branch) |
| Tests read the state from `split()[1]` and the pid from `split()[3]` of a `supervisorctl status` line; pmon daemon tests expect `STOPPED` after a stop | `get_pmon_daemon_status()`; `get_program_info()` / `get_group_program_info()` in `dut_utils.py` and `test_container_autorestart.py`; `tests/platform_tests/daemon/test_*.py` |
| Ubuntu: `VERSION_CODENAME=resolute`, `/etc/debian_version` = `forky/sid`. Debian 202605: `trixie`, `13.5` | Both root filesystems |
| Not different between the two images: sudo (C sudo 1.9.x, not sudo-rs); bash with the plugin patch and `bash_tacplus`; sysctl file `/usr/lib/sysctl.d/90-sonic.conf`; chrony; OpenSSH 10.x; `release: 'none'` in `sonic_version.yml` | Package and file comparison of both root filesystems |

Pebble states observed in the same run:

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

New module `tests/common/helpers/container_processes.py`, standard library only, importable without Ansible (same rule as `ansible/module_utils/sonic_release_utils.py`).

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

`ContainerProcesses`: `container`, `backend` (`"supervisord"`, `"pebble"` or `None`), `running`, `processes`, `critical_groups`, `critical_programs`, `critical_file_found`, `error`. `get(name)` accepts a full or a bare name.

Functions: `build_probe_command(container)`, `parse_probe_output(container, rc, stdout)`, `build_control_command(container, action, names)`, and the per-backend parsers they call.

### 4.2 Probe

One command per container: `docker exec <container> bash -c '<script>'`. The command keeps the `docker exec <container>` prefix. The script uses bash builtins only, so it does not depend on which tools each rock stages (the database rock, for example, has no `sed`). It prints sections, each introduced by a marker line `@@<section>@@`:

| Section | Content |
|---|---|
| `backend` | `pebble` if `pebble services` succeeds; else `supervisord` if `supervisorctl` is on `PATH`; else `unknown` |
| `critical` | `/etc/supervisor/critical_processes`, or the marker `@@critical-missing@@` |
| `status` (supervisord) | `supervisorctl status` |
| `services` (pebble) | `pebble services --format json` |
| `plan` (pebble) | `pebble plan` |
| `procs` (pebble) | One line per process: pid, ppid, pgid, then argv joined with `\x1f` (read with `mapfile -d ''` from `/proc/<pid>/cmdline`) |
| `groups` (pebble) | The `[group:...]` sections of `/etc/supervisor/conf.d/*.conf` |

A non-zero exit from `docker exec` means the container is not running.

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

Group membership: each `programs=` list in a `[group:G]` section puts those names in group `G`.

The pid of a running service is resolved in this order; the first rule that gives exactly one process wins:

1. In the process group of a pebble child whose argv equals `shlex.split(command)`: the process whose argv[0] basename equals the service name. This finds the named program behind a wrapper, for example orchagent behind `orchagent.sh`, which matches what supervisord reports after the wrapper's `exec`.
2. The pebble child whose argv equals `shlex.split(command)`.
3. The pebble child, leader of its own process group, whose argv[0] basename equals the command's argv[0] basename.

Otherwise `pid` is `-1` and `pid_note` names the rule that failed. The `plan` section is YAML; the parser uses PyYAML, which docker-sonic-mgmt already has.

### 4.4 Control

`build_control_command(container, action, names)`, where `action` is `start`, `stop` or `restart`, produces one command that keeps the `docker exec <container>` prefix and branches inside the container: under pebble it runs `pebble <action>` with the group prefix removed from each name; under supervisord it runs `supervisorctl <action>` with the names unchanged. The return code is 0 on success and non-zero on failure under both backends.

### 4.5 SonicHost interface and migrated helpers

New `SonicHost` methods:

- `get_container_processes(container)` returns a `ContainerProcesses`.
- `get_containers_processes(containers)` runs the probes as one `shell_cmds` batch and matches results by position, not by parsing the command string.
- `control_container_process(container, action, names, module_ignore_errors=False)`.

Helpers moved onto the new interface, with signatures and return values unchanged:

| File | Functions |
|---|---|
| `tests/common/devices/sonic.py` | `get_critical_group_and_process_lists`, `critical_group_process`, `critical_process_status`, `all_critical_process_status`, `start_pmon_daemon`, `stop_pmon_daemon_service`, `get_pmon_daemon_status`, `get_pmon_daemon_states`, `kill_bgpd`, `start_bgpd` |
| `tests/common/helpers/dut_utils.py` | `get_program_info`, `get_group_program_info` |
| `tests/autorestart/test_container_autorestart.py` | `get_program_info`, `get_group_program_info` |
| `tests/process_monitoring/test_critical_process_monitoring.py` | the `supervisorctl start` that restores a stopped critical process |

`parse_service_status_and_critical_process()` stays public and unchanged for any other caller.

### 4.6 Error handling

| Condition | Result |
|---|---|
| Container not running | `running=False`; critical status `False`, as today |
| Backend `unknown` | `error` set; critical status `False` |
| `critical_processes` missing | Same as today: the lists cannot be read, status `False` |
| `group:` entry with no readable definition in a pebble container | Status `False`; `error` names the group |
| Running process whose pid is not resolved | `pid=-1`, `pid_note` set; the critical status is not affected |
| JSON or YAML that cannot be parsed | `error` set; critical status `False` |

## 5. Component 2: OS profile

New module `tests/common/helpers/os_profile.py`, standard library only.

`parse_os_profile(os_release_text, debian_version_text)` returns `OsProfile(id, version_id, codename, debian_base)`:

- Debian: `debian_base` is its codename.
- Ubuntu: `debian_base` comes from `/etc/debian_version`. `forky/sid` gives `forky`; a numeric value maps by major version (10 `buster`, 11 `bullseye`, 12 `bookworm`, 13 `trixie`, 14 `forky`).
- Any other value gives `debian_base=None`.

`debian_base_at_least(name)` compares in the order `buster < bullseye < bookworm < trixie < forky < duke`, and returns `False` when `debian_base` is `None`.

`SonicHost.os_profile(container=None)` reads `/etc/os-release` and `/etc/debian_version` on the host, or inside `container` when given. The host result is cached per `SonicHost` object; container results are not cached.

| Call site | Change | How it is checked |
|---|---|---|
| `tests/memory_checker/test_memory_checker.py` `get_restart_expected_logre` | `debian_base_at_least("bookworm")` selects the systemd log format with the unit name | vs testbed |
| `tests/copp/copp_utils.py` `_install_nano` (syncd container) | `debian_base_at_least("bookworm")` selects the current install path | vs testbed |
| `tests/test_pretest.py` saithrift URL | Rewrite the URL only when the syncd container is Debian | Not reached on vs; unit test only |
| `tests/dualtor/test_mux_port_iptables_entries.py` | `debian_base_at_least("trixie")` | No dual-ToR testbed; unit test only |

The sysctl choice in `dut_utils.enable_nat_for_dpus` and `dpu_utils` already takes the right branch on Ubuntu and is not changed.

## 6. Verification

### 6.1 Unit tests

New files under `tests/common/unit_tests/helpers/`, run with `python3 -m pytest --noconftest --confcutdir=tests/common/unit_tests tests/common/unit_tests/helpers/`. Written before the code they test. Inputs:

- probe output captured from both VMs, stored under `tests/common/unit_tests/helpers/data/`;
- `/etc/os-release` and `/etc/debian_version` from both root filesystems;
- constructed cases: unresolved pid, missing group definition, container not running, unknown backend, malformed JSON.

### 6.2 A/B run

A vms-kvm-t0 testbed with cEOS 4.32.5M neighbours on the build host, once per image. Tests: the sanity checks that run around every module, plus `test_pretest.py`, `autorestart`, `platform_tests/daemon`, `memory_checker`, `copp`, `process_monitoring`.

### 6.3 Acceptance criteria

1. The unit tests pass.
2. On the Dockerfile image, every selected test has the same outcome with the new branch as with unmodified upstream `202605`. The refactor must not change the supervisord path.
3. On the rock image, the sanity process check passes on a healthy switch; every entry in every running container's `critical_processes` resolves to a state; every critical process in a rock container has a pid, or a `pid_note` that explains why not.
4. Every result that differs between the two images, and every remaining failure, is assigned to one cause with evidence: version naming, SNMP `sysDescr`, `bgpd.log`, coreutils, docker 29, Python 3.14, log noise, sshd, a real rock difference, or the testbed. `process_monitoring` is expected to fail on the rock image: the rock listener does not raise the periodic alert for `auto_restart` values other than `enabled`.

The classification is written up in this repository and is the input to the next round.

## 7. Branch and commits

`202605_resolute` on `canonical/sonic-mgmt`, from `sonic-net/sonic-mgmt` `202605` at `36c29fc`. GPG-signed commits in this order:

1. OS profile module and its unit tests
2. The four OS call sites
3. Container process module and its unit tests
4. `SonicHost` interface
5. Common helpers in `sonic.py` and `dut_utils.py`
6. Test-local helpers in `autorestart` and `process_monitoring`

Pushing the branch needs a separate go-ahead.

## 8. Risks

| Risk | Handling |
|---|---|
| Wrappers or `exec` change the argv of a pebble service | The three pid rules in §4.3; anything unresolved is reported, not guessed |
| A later pebble changes the JSON fields | Missing fields set `error` with the field name instead of raising |
| The refactor changes the supervisord path | Acceptance criterion 2 |
| One probe per container per query | No more `docker exec` calls than today (today: two per container) |
