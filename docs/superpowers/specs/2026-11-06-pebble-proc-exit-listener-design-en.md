# supervisor-proc-exit-listener parity on the pebble/rock path — Design

- **Date:** 2026-11-06
- **Status:** Approved (2026-11-06)
- **Target branch:** `202605_resolute` (rock + pebble path); implemented in a separate PR
- **Scope:** single ASIC; no behaviour change on the Docker + supervisord path

## 1. Background and purpose

On the Docker + supervisord path, most containers (except mgmt-framework, iccpd and a few others, see §6.5) run a
supervisord eventlistener, `supervisor-proc-exit-listener-rs` (`src/sonic-supervisord-utilities-rs`). It:

1. when a critical process (`/etc/supervisor/critical_processes`) exits unexpectedly, writes a syslog line, publishes a
   `sonic-events-host` / `process-exited-unexpectedly` event, and kills supervisord so the container exits and systemd restarts it;
2. acts as the orchagent heartbeat watchdog: writes a WARNING syslog line when the heartbeat goes stale.

The rock + pebble path has no supervisord and no such listener. Today:

- when a critical process exits, the container still exits through `on-failure: shutdown` and is restarted by systemd,
  but **no event is published and the listener's syslog line is not written**;
- the orchagent heartbeat is not checked at all; pebble forwards the heartbeat lines to the host syslog as ordinary stdout
  (about 3200 lines of `<!--XSUPERVISOR:BEGIN-->heartbeat<!--XSUPERVISOR:END-->` per day on dut2).

This design adds both functions so that the externally observable behaviour of the rock path (syslog text, events,
alert cadence) matches the Docker path.

## 2. Goals / non-goals / anti-goals

**Goals**
- Unexpected critical-process exit: the rock path writes the same syslog text as the listener and publishes an event with
  the same source, tag and fields.
- orchagent heartbeat: the rock path writes the stuck alert with the same text, level and cadence as the listener;
  heartbeat lines no longer reach syslog.
- Both functions are provided by one long-running pebble service that reuses the existing Rust code.

**Non-goals**
- `auto_restart` other than `enabled` (recorded as a known defect, §7.1).
- Critical-process entries of the form `group:` (the dhcp-relay case, deferred, §7.4).
- Namespace handling for multi-ASIC / multi-DB / chassis.

**Anti-goals** (technically workable, but counted as failure)
- Changing anything about how the Docker + supervisord path runs.
- Inferring process exits on the host by parsing pebble log text.
- Making rocks depend on Python swsscommon for this (in the eventd rock `import swsscommon` currently fails, §9).

## 3. Constraints

- `orchagent.sh` is shared by the supervisord and pebble paths. Pebble-only logic must sit behind a runtime check, using
  the form already used in `dockers/docker-orchagent/start.sh`: `if pgrep -x pebble > /dev/null 2>&1; then`.
  On the supervisord path the check is false (also false if pgrep is missing), so behaviour is byte-for-byte unchanged.
- No change to the sonic-swss submodule (orchagent keeps printing the original heartbeat marker).
- Every rock already has `libswsscommon.so.0`, the `CONTAINER_NAME` environment variable, a tmpfs `/tmp`, and the
  pebble socket `/var/lib/pebble/default/.pebble.socket` (checked on all 14 running rocks on dut2).
- The database rock has no `/usr/bin/sh` (removed on purpose by chisel), and all rocks will drop sh later; the new
  component must not depend on a shell.

## 4. Behaviour of the existing listener (facts the implementation must match)

All from `src/sonic-supervisord-utilities-rs/src/proc_exit_listener.rs`; event handling and alerting live in the main
loop of `main_with_parsed_args_and_stdin()`.

| Input event | Handling |
|---|---|
| `PROCESS_STATE_EXITED` | Critical process with `expected == 0`: if `auto_restart == enabled` → `info!("Process '{}' exited unexpectedly. Terminating supervisor '{}'")`, publish the event, deinit, SIGTERM the parent supervisord; otherwise add it to `process_under_alerting` |
| `PROCESS_STATE_RUNNING` | Only removes the process from `process_under_alerting` |
| `PROCESS_COMMUNICATION_STDOUT` | Process listed in `watchdog_processes` → record `last_heart_beat = monotonic now` |
| Every loop iteration (poll timeout 1s) | `process_under_alerting`: one ERR `... is not running ...` every 60s; heartbeat past threshold: one WARNING `Process '{}' is stuck in namespace '{}' ({} minutes).` **per iteration**, no rate limit |

Other details:
- Event: source `sonic-events-host`, tag `process-exited-unexpectedly`, fields `process_name` and `ctr_name`
  (constants `EVENTS_PUBLISHER_SOURCE`/`EVENTS_PUBLISHER_TAG`, function `publish_events()`).
- Heartbeat threshold: CONFIG_DB `HEARTBEAT|<proc>` field `alert_interval` (milliseconds), read once at startup;
  default 60s; `0` disables (`load_heartbeat_alert_interval()`, `get_heartbeat_alert_interval()`, constant `ALERTING_INTERVAL_SECS`).
- Tracking starts only after the first heartbeat; no alert if no heartbeat was ever received.
- Namespace: `NAMESPACE_PREFIX` + `NAMESPACE_ID` when both are non-empty, otherwise `host` (`generate_alerting_message()`).
- The syslog tag comes from the `syslog` crate's `get_process_info()`, i.e. the **executable file name**; on the Docker
  path it is `supervisor-proc-exit-listener-rs`.
- orchagent heartbeat: `OrchDaemon::heartBeat()` prints `<!--XSUPERVISOR:BEGIN-->heartbeat<!--XSUPERVISOR:END-->`
  every `heartBeatInterval` (default 10s, set by `-I`, 0 disables), flushed immediately by `endl`
  (`src/sonic-swss/orchagent/orchdaemon.cpp`); it keeps printing while frozen for warm restart (`OrchDaemon::freezeAndHeartBeat()`).
- Downstream consumers: sonic-mgmt matches the stuck alert by the text `Process 'orchagent' is stuck in namespace`
  (`tests/system_health/test_watchdog.py`, `tests/process_monitoring/test_critical_process_monitoring.py`).

**Simplification under the `auto_restart` assumption:** SONiC defaults every feature to `auto_restart = enabled`.
Under that assumption `process_under_alerting` is always empty, `PROCESS_STATE_RUNNING` has no effect, and the
"not running" alert never appears. The pebble version therefore only needs counterparts for EXITED (enabled branch)
and STDOUT.

## 5. Approaches

| | A. Python reporter per rock + bash exec check | **B. Pebble mode in the existing Rust listener (chosen)** | C. Rebuild the supervisord event protocol on pebble |
|---|---|---|---|
| Process exit | Python script calls `pebble services` on SIGTERM | Rust queries the pebble API directly on SIGTERM | Not possible: pebble has no service-state notices (only change-update/custom/warning) |
| Heartbeat | `orchagent.sh` filter + pebble exec check every 10s, each calling `sonic-db-cli` | `orchagent.sh` filter + the same Rust process checks every second | Pebble does not recognise the stdout marker |
| Dependencies | Working python3-swsscommon in every rock (eventd already fails) | libswsscommon (present in every rock) + one deb | — |
| Parity with existing behaviour | Different tag and alert cadence | Text, tag, level, cadence and threshold source all reuse the existing code | — |
| Validated | Both parts spiked on dut2 | Same mechanism as A (same pebble behaviour, same filter), different implementation language | — |

The user chose B on 2026-11-06. Reasons: no Python dependency; shares code and external behaviour with the existing
listener, so sonic-mgmt matching is unaffected; a single process at runtime.

## 6. Design

### 6.1 Overview

```
rock container (pebble PID 1)
├── rsyslogd                                    (already in every rock)
├── proc-exit-listener              ← new pebble service, requires+after rsyslogd
│     /usr/bin/supervisor-proc-exit-listener-rs --pebble
│     ├─ every 1s: check heartbeat-file mtime of watchdog processes → WARNING when stale
│     └─ on SIGTERM: GET /v1/services → error and critical → syslog + event → exit 0
└── orchagent (swss only)
      orchagent.sh under pebble: exec orchagent > >(heartbeat_filter)
      heartbeat_filter: heartbeat line → touch /tmp/orchagent.heartbeat; other lines → passed to pebble unchanged
```

### 6.2 Unexpected critical-process exit

**Trigger chain**
1. Critical services are `on-failure: shutdown` in the pebble plan. When one exits non-zero, pebble's `exited()`, under
   `servicesLock`, first calls `HandleRestart(RestartServiceFailure)` and then sets the service to `stateExited`
   (pebble v1.33.2 `internals/overlord/servstate/handlers.go`, `serviceData.exited()`, the `plan.ActionShutdown`
   branch under `stateRunning`).
2. Daemon shutdown: `Daemon.stopRunningServices()` (`internals/daemon/daemon.go`) → `servicesToStop()` picks only
   services in `starting/running/backoff` (`internals/overlord/servstate/manager.go`).
   **An exited service is not in the stop list, is never stopped, and therefore never goes through the
   `stateExited → stateStopped` transition in `serviceForStop()` (`handlers.go`, `ServiceManager.serviceForStop()`).**
3. Stopped services receive `kill(-pgid, SIGTERM)` and move `running → terminating → stopped` (`handlers.go`,
   `serviceData.stop()`, and the `stateTerminating, stateKilling` branch of `serviceData.exited()`).
   Even if they exit non-zero because of the SIGTERM, they take the `stateTerminating` branch and end up `stopped`, not `exited`.
4. The HTTP API is closed only after all services have stopped (`daemon.go`: `Daemon.Stop()` calls
   `stopRunningServices()` before `d.serve.Shutdown()`).

**State mapping** (`manager.go`, `stateToStatus()`): `exited → error`, `terminating/killing/stopped → inactive`.

**Conclusion:** an `error` status seen by the listener on SIGTERM can only come from a service that exited non-zero on
its own before shutdown. Other critical services stopped by pebble are `inactive` and cannot be misreported. Snapshot
measured on dut2: `{'snmp-subagent': 'error', 'snmpd': 'inactive', ...}` (snmpd was stopped before the listener and is inactive).

**Decision rules**
- `/etc/supervisor/critical_processes` is read only on SIGTERM (see "lazy reading" in §6.4).
  If the file is missing or unparsable: write one WARNING, then `exit(0)`; never crash. If it is empty (e.g. pmon): no query, no log, `exit(0)`.
- `failed = { s | s.current == "error" and s.name is a program: entry of critical_processes }`
- For each failed service: `info!("Process '{}' exited unexpectedly. Terminating supervisor '{}'", name, ctr)`,
  then `publish_events()`; after all of them, `deinit()` and `exit(0)`.
  The text keeps "Terminating supervisor" to match the Docker path, so existing log matching keeps working.
- `failed` is empty (normal stops such as `systemctl stop/restart`, `docker stop`): write nothing, publish nothing,
  `exit(0)`. Verified on dut2.
- "Unexpected" means the same as before: supervisord decides expected by `exitcodes` (default 0); under pebble an exit
  code of 0 goes through `on-success: ignore` → `stopped`, which neither triggers shutdown nor is `error`.

**pebble API access**
- Socket: `$PEBBLE_SOCKET`, otherwise `${PEBBLE:-/var/lib/pebble/default}/.pebble.socket`.
- Request: `GET /v1/services` (HTTP/1.0 over the Unix socket, read until EOF), 2s timeout.
- Response (measured on dut2): `{"type":"sync","status-code":200,"status":"OK","result":[{"name":"snmpd","startup":"disabled","current":"active","current-since":"..."}]}`.
- No `pebble` CLI, no fork.
- Connection failure, timeout or unparsable response: write one ERR, then `exit(0)` (pebble still completes the
  shutdown; only the report is lost).

**Time budget:** pebble's kill-delay for the listener is the default 5s. Two runs on dut2 took 40-50ms from SIGTERM to
the event being published (Python version).

### 6.3 orchagent heartbeat

**orchagent.sh (swss, pebble branch)**

Replace the current last line
```bash
exec /usr/bin/orchagent ${ORCHAGENT_ARGS}
```
with:
```bash
if pgrep -x pebble > /dev/null 2>&1; then
    # pebble has no supervisord stdout-capture: turn heartbeat lines into a file mtime for the watchdog
    HEARTBEAT_FILE=/tmp/orchagent.heartbeat
    rm -f "$HEARTBEAT_FILE"
    heartbeat_filter() {
        trap '' TERM    # keep draining until orchagent closes stdout
        local line
        while IFS= read -r line || [[ -n $line ]]; do
            if [[ $line == '<!--XSUPERVISOR:BEGIN-->heartbeat<!--XSUPERVISOR:END-->' ]]; then
                : > "$HEARTBEAT_FILE"
            else
                printf '%s\n' "$line"
            fi
        done
    }
    exec /usr/bin/orchagent ${ORCHAGENT_ARGS} > >(heartbeat_filter)
fi
exec /usr/bin/orchagent ${ORCHAGENT_ARGS}
```

Key points:
- `> >(heartbeat_filter)` is bash process substitution: bash creates a pipe and runs the filter function in a child
  process; orchagent's stdout is connected to the write end. It is not a redirect to a file: all other stdout still
  reaches the pebble log; the file stays empty and only its mtime is used, so it never grows and needs no rotation.
- Process relationship (measured on dut2): orchagent (pid 159) is the parent of the filter child (pid 189), both in the
  same process group. When pebble stops orchagent, `kill(-pgid)` sends SIGTERM to both; the filter ignores it and exits
  on EOF once orchagent closes stdout.
- `rm -f` makes every orchagent start begin in the "no heartbeat yet" state, matching the listener's "track only after
  the first heartbeat".
- The heartbeat file lives on tmpfs `/tmp` and is cleared when the container restarts.
- On the supervisord path the `if` is false and the original `exec` runs.

**Listener watchdog loop (pebble mode)**
- Every 1s read `/etc/supervisor/watchdog_processes` (optional, `program:` entries; if absent there are no watchdog
  processes, and the cost is one `stat`).
- Each watchdog process has a heartbeat file `/tmp/<process>.heartbeat`.
- When a process's heartbeat file **first appears**, read the CONFIG_DB `HEARTBEAT` table for the threshold (same as the
  existing `load_heartbeat_alert_interval()`) and never again; the file existing means orchagent is running, so the DB
  is available. On read failure use the 60s default.
- Every 1s, `stat` each process's heartbeat file:
  - file missing: not tracked (clear that process's tracking state);
  - mtime differs from the last one seen: set `last_heart_beat = monotonic now`. Recording "when the change was
    observed" on a monotonic clock, instead of subtracting mtime from wall-clock time, avoids false or missed alerts on
    NTP jumps; it matches the existing listener's "time the event was received";
  - `threshold > 0 and now - last_heart_beat >= threshold`: `generate_alerting_message(proc, "stuck", elapsed/60, LOG_WARNING)`.
    One per iteration, same as the existing listener (no rate limit).
- Alert latency: at most about 1s later than the existing listener (the polling interval).

### 6.4 Binary and arguments

- Add a `--pebble` mode to the existing `supervisor-proc-exit-listener-rs` binary in `sonic-supervisord-utilities-rs`;
  no new binary. Reasons: the syslog tag is the executable file name, so it stays `supervisor-proc-exit-listener-rs` as
  on the Docker path; it reuses `get_group_and_process_list`, `generate_alerting_message`, `publish_events` and
  `load_heartbeat_alert_interval`; packaging stays the same deb.
- In pebble mode `--container-name` may be omitted and is taken from the `CONTAINER_NAME` environment variable (pebble
  does not expand variables in `command`; every rock has the variable).
- Without `--pebble`, behaviour is completely unchanged.
- **Lazy reading (differs from the existing listener).** In pebble mode, startup reads no files, connects to no DB and
  creates no EventPublisher; it goes straight into the 1s loop. SIGTERM breaks the loop and runs §6.2. Reasons:
  - the listener starts with rsyslogd, before start.sh (§6.5), but `critical_processes` is rendered during start in swss
    (`dockers/docker-orchagent/start.sh`), bgp (`dockers/docker-fpm-frr/start.sh`) and database
    (`dockers/docker-database/docker-database-init.sh`); reading at startup would exit because the file is missing, or,
    when `docker start` reuses a container, read the previous run's stale file;
  - early in database-rock startup redis is not up, so connecting to ConfigDB at startup would fail or block;
  - the exit-report path needs no DB (FEATURE is not read, §7.1).
- The EventPublisher is created on SIGTERM and deinitialised after use. The Python version did exactly this in the dut2
  experiments: create, publish and deinit took about 30ms, and the event was received on the eventd side (2026-10-29).
- `group:` entries: pebble has no equivalent; ignore them when reading and write one WARNING.
- Names in `critical_processes` that are not in the pebble plan never appear in the query result and are ignored
  without error.

### 6.5 pebble service definition

**Scope: same as the Docker path.** Install only in rocks whose Docker-path supervisord config has
`[eventlistener:supervisor-proc-exit-listener]`: database, dhcp-relay, dhcp-server, eventd, fpm-frr (bgp), lldp,
macsec, nat, orchagent (swss), platform-monitor, router-advertiser, sflow, snmp, sonic-gnmi, sysmgr, teamd,
`platform/broadcom/docker-syncd-brcm*`. dhcp-server is currently commented out in `build_rocks.sh` and not built; it can
be added when it is re-enabled.
**Not installed:** sonic-mgmt-framework, iccpd (the Docker path has none either).

Each of these rocks gets the same definition in the top-level `services:` of its rockcraft.yaml, right after `rsyslogd`:

```yaml
services:
  proc-exit-listener:
    command: /usr/bin/supervisor-proc-exit-listener-rs --pebble
    override: replace
    startup: enabled
    on-success: ignore
    requires: [rsyslogd]
    after: [rsyslogd]
```

- **Both `requires` and `after` are required.** Pebble splits services into lanes by `requires`, and different lanes
  stop in parallel. With only `after`, rsyslogd and the listener are in different lanes, rsyslogd stops first, and all
  listener syslog is lost (dut2 round 2). With both, the stop order is listener → rsyslogd (dut2 round 3: exit-reporter
  stopped at 51.999, rsyslogd at 52.017).
- No `on-failure`: pebble's default is `restart`, so if the listener itself crashes, pebble restarts it without taking
  the container down. The listener must **not** be listed in `critical_processes`.
- The service name has no `supervisor-` prefix because rocks have no supervisord; the binary and deb keep their names.
- Loading: defined in rockcraft.yaml the same way as `rsyslogd`, so rockcraft writes it into the image's own
  `/var/lib/pebble/default/layers/001-rockcraft-*.yaml`; pebble loads it at startup and the listener starts together with
  rsyslogd before start.sh. No extra layer file and no start.sh change are needed. The cost is one identical 8-line block
  in each of the 16 rocks.

### 6.6 Packaging

- **Why the deb is needed:** the rock path has no listener today, so no rockcraft.yaml references the deb; under B it is
  the executable. The deb contains one file, `/usr/bin/supervisor-proc-exit-listener-rs` (`debian/install`), and needs
  only libswsscommon at runtime (present in every rock).
- **How the Docker path installs it:** `rules/docker-config-engine-resolute.mk` lists `$(SONIC_SUPERVISORD_UTILITIES_RS)`
  in the `_DEPENDS` of `docker-config-engine-resolute`, whose Dockerfile installs those debs; service images inherit it
  as their base image, and supervisord.conf starts it as `/usr/bin/supervisor-proc-exit-listener-rs --container-name <ctr>`.
- **How the rock path gets it:** `build_rocks.sh` requires the full image build to have finished (by then the deb has
  been built as a dependency of `docker-config-engine-resolute`), and copies every non-dbg deb from
  `target/debs/resolute/` into each rock's `debs/`. So no `rules/*.mk` change is needed; each rock listed in §6.5 only
  needs `dpkg -x debs/sonic-supervisord-utilities-rs_*.deb ${CRAFT_PART_INSTALL}` in its rockcraft.yaml.
- swss rock: remove the exclusion of `watchdog_processes.j2` in `dockers/docker-orchagent/rockcraft.yaml` and put
  `program:orchagent` at `/etc/supervisor/watchdog_processes` (static content; organize it directly or render it in start.sh).
- The Docker path's supervisord.conf and Dockerfile are unchanged.

## 7. Known defects and limitations

### 7.1 `auto_restart` other than enabled is not supported (known defect)
When `auto_restart` is not `enabled`, the existing listener does not kill supervisord; it keeps the container running
and writes one ERR every 60s, `Process '<p>' is not running in namespace '<ns>' (<n> minutes).`, until the process is
RUNNING again. On the rock path critical services are always `on-failure: shutdown`, so a process exit always takes the
container down; this design **does not implement** that branch:
- on exit it still writes "exited unexpectedly" and publishes the event (FEATURE is not read);
- there is no periodic "not running" alert.

If this is needed later: in pebble mode, read the FEATURE table; when `auto_restart` is not enabled, have start.sh change
the critical services' `on-failure` to `ignore`, and have the listener poll `/v1/services` every second to maintain
`process_under_alerting`, covering the EXITED and RUNNING events.

### 7.2 pebble itself is SIGKILLed
On OOM, `docker kill`, or SIGKILL after kill-delay, the listener gets no SIGTERM and reports nothing. The existing
listener cannot work either when supervisord is killed hard; same class of limitation.

### 7.3 A second exit during the shutdown window
After the first critical service exits and triggers shutdown, a critical service that exits on its own before
`servicesToStop()` takes its snapshot is also `error` and is reported too (which is accurate). A service that exits
after the snapshot takes the terminating branch, becomes `inactive`, and is not reported. The existing listener also
stops reporting further exits once it has killed supervisord.

### 7.4 `group:` entries are not supported
dhcp_relay's `critical_processes` is `group:dhcp-relay`. Pebble has no groups, so such entries are ignored and the
processes behind them are not reported when they exit. This is a real difference from the Docker path, deferred together
with dhcp-relay.

### 7.5 Mismatches that also exist on the Docker path (not defects)
On dut2 (image `8b4c9d5b9`) every rock was checked for "is each name in `critical_processes` in the current pebble plan,
and is it `on-failure: shutdown`". The following mismatches exist on the Docker path too, with the same listener
outcome, so they are **not defects**:
- radv: `radvd` is defined in a separate `radvd-layer.yaml`, which `start.sh` adds with `pebble add` and starts only
  when there is IPv6 VLAN config, matching `docker-router-advertiser.supervisord.conf.j2`, which renders
  `[program:radvd]` only when `vlan_v6.count > 0`. dut2 has no such config, so radvd is not in its plan. The listener
  queries the plan only on SIGTERM (§6.4), so a loaded radvd is reported normally.
- syncd (brcm): `critical_processes` lists `dsserve`, but the Docker path's
  `platform/broadcom/docker-syncd-brcm/supervisord.conf` has no `[program:dsserve]` either.
- pmon: `dockers/docker-platform-monitor/critical_processes` is itself an empty file; both paths are the same.

All other rocks' critical services are in the plan and are all `on-failure: shutdown`.

### 7.6 Other
- The stuck alert is only a WARNING: no event, no restart, same as the existing listener.
- The HEARTBEAT table is read once per container run (when the heartbeat file first appears); changing
  `alert_interval` at runtime needs a container restart, same as the existing listener.
- Multi-ASIC namespaces are not handled (the `NAMESPACE_*` logic is kept as is, unverified).

## 8. Verification

**Unit tests (cargo test)**
- pebble API response parsing and the failed decision: error + critical → reported; inactive/active → not reported;
  not in the critical list → not reported; empty result.
- `critical_processes` missing / empty / containing `group:`: no crash, nothing reported (WARNING for group).
- pebble API unreachable or timing out: write ERR, `exit(0)`.
- Heartbeat: no alert while the file is missing; an mtime change refreshes; alert text and level past threshold;
  threshold 0 disables; 60s default.
- Use a fake Unix socket in a temporary directory to emulate the pebble API.

**dut2 hardware (single ASIC, S5232F)**
1. `kill -9` one critical process of a rock: syslog shows
   `<ctr>#supervisor-proc-exit-listener-rs: Process '<p>' exited unexpectedly. Terminating supervisor '<ctr>'`
   and `EVENT_PUBLISHED ... process-exited-unexpectedly`; in `docker logs` the listener stops before rsyslogd;
   container exit code 10.
2. `systemctl restart <svc>`: none of the above syslog, no event.
3. swss: after restart there are no `XSUPERVISOR` lines in syslog; `/tmp/orchagent.heartbeat` updates every 10s;
   `kill -STOP <orchagent>` for more than 60s produces `Process 'orchagent' is stuck in namespace 'host' (1 minutes).`
   (about one per second), which stops after `kill -CONT`.
4. Event reception: `events_tool -r -n 1` in eventd receives the full `process-exited-unexpectedly` event.

**Docker path regression**
- Without pebble, `orchagent.sh` takes the original `exec`: under supervisord, orchagent's parent and stdout pipe are
  unchanged (`ls -l /proc/<pid>/fd/1` points at supervisord's pipe) and the listener still receives the heartbeat.
- All existing tests of `supervisor-proc-exit-listener-rs` without `--pebble` pass.

## 9. Experiment log (spikes, all cleaned up)

| Date | Image / pebble | What | Result |
|---|---|---|---|
| 2026-10-29 | `dd6d0891a` / v1.33.0 | snmp: Python reporter, `kill -9` a critical process, three rounds of service-dependency changes | Round 3 (requires+after rsyslogd): syslog and event complete; negative test `systemctl restart snmp`: no event |
| 2026-11-05 | `8b4c9d5b9` / v1.33.2 | snmp: same, reading the image's own `critical_processes` | Done 49ms after SIGTERM; `snmp-subagent: error`, `snmpd: inactive`; listener 51.999 → rsyslogd 52.017 |
| 2026-11-05 | `8b4c9d5b9` / v1.33.2 | swss: `orchagent.sh` filter + pebble exec check, `kill -STOP` for 150s | No new heartbeat lines in syslog; first stuck alert 68s after freeze, minutes 1→2; alerts stop after resume; orchagent stop time 2.58s (2.63s baseline) |
| 2026-11-06 | `8b4c9d5b9` / v1.33.2 | Implementation (Rust `--pebble`) deployed into the writable layers of snmp, eventd, database, swss | Listener `active` at start with no restart loop in all 4; `kill -9` of a critical process in snmp/eventd/database → within ~15ms (snmp 16ms, database 13ms) `<ctr>#supervisor-proc-exit-listener-rs: Process '<p>' exited unexpectedly. Terminating supervisor '<ctr>'` and `EVENT_PUBLISHED`, listener stopped before rsyslogd; full event received with `events_tool -o` in eventd; `systemctl restart snmp` → no report; swss: no heartbeat lines in syslog, frozen orchagent → from ~60s one `Process 'orchagent' is stuck in namespace 'host' (1 minutes).` per second, then `(2 minutes)`, stops after resume |

The pebble changes from v1.33.0 to v1.33.2 do not touch service shutdown or the state machine (only logging, metric
names and check-parameter validation).

Side finding (out of scope): in the eventd rock, `python3 -c 'import swsscommon.swsscommon'` fails with
`libpython3.14.so.1.0: cannot open shared object file`.

## 10. Left to the implementer

- Signal handling (`signal-hook` or nix + self-pipe) and how the 1s loop is organised.
- HTTP over the Unix socket (std `UnixStream` + `serde_json`; the latter is already in Cargo.lock and must move from
  dev-dependencies to dependencies).
- The exact list of rockcraft.yaml and rules changes per rock.
