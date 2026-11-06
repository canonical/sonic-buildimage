# pebble-mode supervisor-proc-exit-listener Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give rock/pebble containers the same critical-process-exit report and orchagent heartbeat watchdog that `supervisor-proc-exit-listener-rs` provides under supervisord.

**Architecture:** Add a `--pebble` mode to the existing Rust binary (new module `pebble_mode.rs`, existing listener code untouched). It runs as a pebble service in each rock: a 1s loop checks heartbeat-file mtimes; on SIGTERM it queries the pebble API over the Unix socket and reports critical services in `error`. `orchagent.sh` gains a pebble-only branch that turns heartbeat stdout lines into a file mtime.

**Tech Stack:** Rust 2021 (cargo 1.86 in `sonic-slave-resolute`), `swss-common` crate, `serde_json`, `libc`; bash; rockcraft/pebble v1.33.2.

**Spec:** `docs/superpowers/specs/2026-11-06-pebble-proc-exit-listener-design-en.md` (branch `202605_resolute_doc`, worktree `~/repos/sonic-buildimage-doc`). Read it before any task.

## Global Constraints

- Docker + supervisord path behaviour must not change: `proc_exit_listener.rs` stays byte-identical; the binary without `--pebble` runs `proc_exit_listener::main_with_args` exactly as today; `orchagent.sh` pebble logic sits behind `if pgrep -x pebble > /dev/null 2>&1; then`.
- Exit log text: `Process '<p>' exited unexpectedly. Terminating supervisor '<ctr>'` (INFO).
- Stuck alert: reuse `generate_alerting_message(process, "stuck", minutes, Severity::LOG_WARNING)`; one per 1s tick while stale, no rate limit; threshold from CONFIG_DB `HEARTBEAT|<proc>` `alert_interval` (ms), default 60s, `0` disables.
- Event: reuse `publish_events(&EventPublisher, process, ctr)` with publisher `EventPublisher::new("sonic-events-host")`, created on SIGTERM only, `deinit()` after.
- Pebble mode reads nothing at startup (no files, no DB, no publisher). `critical_processes` read on SIGTERM; `watchdog_processes` read every tick; `HEARTBEAT` read once, when a heartbeat file first appears.
- Paths: critical `/etc/supervisor/critical_processes`; watchdog `/etc/supervisor/watchdog_processes`; heartbeat file `/tmp/<process>.heartbeat`; socket `$PEBBLE_SOCKET`, else `${PEBBLE:-/var/lib/pebble/default}/.pebble.socket`.
- Pebble API: `GET /v1/services`, HTTP/1.0, read to EOF, 2s timeout. Failure → one ERR log, report nothing, exit 0.
- Missing / unparsable `critical_processes` → one WARNING, exit 0; empty → no query, no log, exit 0. `group:` entries ignored with one WARNING.
- Container name: `--container-name`, else env `CONTAINER_NAME`.
- Service definition (every rock in scope): name `proc-exit-listener`, `command: /usr/bin/supervisor-proc-exit-listener-rs --pebble`, `startup: enabled`, `on-success: ignore` (`on-failure` omitted, pebble default `restart`), `requires: [rsyslogd]`, `after: [rsyslogd]`.
- Rocks in scope: database, dhcp-relay, eventd, fpm-frr, lldp, macsec, nat, orchagent, platform-monitor, router-advertiser, sflow, snmp, sonic-gnmi, sysmgr, teamd (under `dockers/docker-*`), and `platform/broadcom/docker-syncd-brcm`. Not: sonic-mgmt-framework, iccpd, dhcp-server (not built).
- No new shell dependency inside rocks (database has no `/usr/bin/sh`; all rocks will lose it).
- No file line numbers in docs or comments.
- Git: per the user's rule, changes stay in the worktree uncommitted. Every "Commit" step below is replaced by `git status --short` showing the expected files; do not commit or push.

## Review Focus

1. Pebble answers with non-200 or a body that is not the expected JSON (e.g. `{"type":"error",...}`) → treated as API failure, nothing reported, no panic. Test in Task 2.
2. Pebble socket accepts but never answers → `query_services` returns error within ~2s, not a hang past kill-delay. Test in Task 2.
3. `critical_processes` with blank lines, surrounding spaces, or a last line without newline (teamd's file) → entries still parsed. Test in Task 2.
4. Listener started before rsyslogd's `/dev/log` exists → process exits non-zero and pebble restarts it until it is up; it must end `active`, not stuck in backoff. Checked on dut2 in Task 7.
5. Heartbeat file deleted and recreated (orchagent restart in-container) → tracking restarts from "first seen" without re-reading CONFIG_DB. Test in Task 3.

---

### Task 1: Workspace and build environment

**Files:**
- Create: worktree `~/repos/sonic-buildimage-pel` on new local branch `feat/pebble-proc-exit-listener` from `origin/202605_resolute`

**Interfaces:**
- Produces: `target/debs/resolute/libswsscommon_1.0.0_amd64.deb` and `libswsscommon-dev_1.0.0_amd64.deb` in the main tree `~/repos/sonic-buildimage`; the command `SLAVE_CARGO` used by later tasks:
  ```bash
  # run from ~/repos/sonic-buildimage-pel; $1 = shell command run in src/sonic-supervisord-utilities-rs
  docker run --rm -v ~/repos/sonic-buildimage-pel:/sonic -v ~/repos/sonic-buildimage/target/debs/resolute:/debs:ro \
    -w /sonic/src/sonic-supervisord-utilities-rs sonic-slave-resolute:<tag> bash -c \
    "apt-get install -y -qq /debs/libswsscommon_1.0.0_amd64.deb /debs/libswsscommon-dev_1.0.0_amd64.deb >/dev/null && $1"
  ```

- [ ] **Step 1:** In the main tree, `git fetch origin && git worktree add -b feat/pebble-proc-exit-listener ../sonic-buildimage-pel origin/202605_resolute`. Then in the worktree `git submodule update --init src/sonic-swss-common` (add `--reference` to the main tree's module if slow).
- [ ] **Step 2:** In the main tree (submodules already initialised, HEAD equals `origin/202605_resolute`): `make PLATFORM=broadcom configure` if `.platform` is missing, then `make target/debs/resolute/libswsscommon-dev_1.0.0_amd64.deb`. Expected: both libswsscommon debs exist. If the slave image tag differs from `09b917bca7a`, use the tag `make` built.
- [ ] **Step 3:** Baseline: `SLAVE_CARGO "cargo test 2>&1 | tail -20"`. Expected: all existing tests pass. If `apt-get install` fails on dependencies, add the matching `/debs/libnl*` debs to the install list and record that in `SLAVE_CARGO`.

### Task 2: Pebble API client and exit reporting

**Files:**
- Create: `src/sonic-supervisord-utilities-rs/src/pebble_mode.rs`
- Modify: `src/sonic-supervisord-utilities-rs/src/lib.rs` (add `pub mod pebble_mode;`)
- Modify: `src/sonic-supervisord-utilities-rs/Cargo.toml` (move `serde_json = "1.0"` to `[dependencies]`; add `libc = "0.2"`; versions already in Cargo.lock — `cargo build --locked` must still pass)
- Test: `src/sonic-supervisord-utilities-rs/tests/test_pebble_mode.rs`

**Interfaces:**
- Produces (all `pub` in `pebble_mode`):
  - `struct PebbleService { pub name: String, pub current: String }` (derive Debug, Clone, PartialEq)
  - `fn pebble_socket_path() -> PathBuf`
  - `fn parse_services_response(raw: &str) -> Result<Vec<PebbleService>, String>` — `raw` is the full HTTP response (status line, headers, body)
  - `fn query_services(socket: &Path, timeout: Duration) -> Result<Vec<PebbleService>, String>`
  - `fn read_program_list(path: &Path) -> Result<Vec<String>, String>` — `program:` values; `group:` skipped with `warn!`; Err on missing file or a line not `key:value` with key `program`/`group`
  - `fn exited_critical(services: &[PebbleService], critical: &[String]) -> Vec<String>` — names with `current == "error"` that are in `critical`, in `services` order
  - `fn exit_message(process: &str, ctr: &str) -> String`
  - `fn report_exits(ctr: &str, critical_file: &Path, socket: &Path, timeout: Duration, publish: &mut dyn FnMut(&str) -> Result<(), String>) -> Vec<String>` — logs and returns the reported names; never panics; logs `info!(exit_message)` then calls `publish(name)` per name
  - consts `PEBBLE_DEFAULT_DIR = "/var/lib/pebble/default"`, `PEBBLE_API_TIMEOUT: Duration = 2s`

- [ ] **Step 1: Write failing tests** in `tests/test_pebble_mode.rs`. Helper `fn fake_pebble(dir: &Path, response: Option<&'static str>) -> PathBuf` binds a `UnixListener` at `dir/.pebble.socket` in a thread; for `Some(r)` it reads the request and writes `r`, for `None` it accepts and holds the connection open without answering. Tests:
  - `parse_ok`: response `"HTTP/1.0 200 OK\r\nContent-Type: application/json\r\n\r\n{\"type\":\"sync\",\"status-code\":200,\"status\":\"OK\",\"result\":[{\"name\":\"snmpd\",\"startup\":\"disabled\",\"current\":\"inactive\"},{\"name\":\"snmp-subagent\",\"startup\":\"disabled\",\"current\":\"error\"}]}"` → two services, second `current == "error"`.
  - `parse_non_200`: `"HTTP/1.0 500 Internal Server Error\r\n\r\n{\"type\":\"error\",\"result\":{\"message\":\"x\"}}"` → `Err`.
  - `parse_garbage`: `"not http"` → `Err`.
  - `exited_critical_filters`: services `[(a,error),(b,inactive),(c,error),(d,active)]`, critical `[a,b,d]` → `["a"]`.
  - `read_program_list_variants`: file `"program:x\n\n  program: y \ngroup:g\nprogram:z"` → `["x","y","z"]`; missing file → `Err`; file `"bogus\n"` → `Err`; empty file → `Ok(vec![])`.
  - `exit_message_text`: `exit_message("snmpd","snmp") == "Process 'snmpd' exited unexpectedly. Terminating supervisor 'snmp'"`.
  - `report_exits_reports_error_critical`: fake pebble with the `parse_ok` response, critical file `program:snmpd\nprogram:snmp-subagent\n` → returns `["snmp-subagent"]`, publish called exactly once with `"snmp-subagent"`.
  - `report_exits_normal_stop`: all services `inactive` → `[]`, publish never called.
  - `report_exits_missing_critical_file` → `[]`, publish never called.
  - `report_exits_no_socket` (socket path does not exist) → `[]`.
  - `report_exits_hung_socket`: `fake_pebble(dir, None)`, timeout 300ms → `[]` and the call returns in < 2s.
- [ ] **Step 2:** `SLAVE_CARGO "cargo test --test test_pebble_mode"` → FAIL (module missing).
- [ ] **Step 3:** Implement the Interfaces above. `query_services`: `UnixStream::connect`, `set_read_timeout`/`set_write_timeout(timeout)`, write `GET /v1/services HTTP/1.0\r\nHost: localhost\r\n\r\n`, `read_to_string`, then `parse_services_response`. Parse: split at first `\r\n\r\n`, status line must contain ` 200 `, body JSON `result` array, each element's `name` and `current` strings. `report_exits`: `read_program_list` Err → `warn!` + return `[]`; empty list → return `[]` without querying; `query_services` Err → `error!` + `[]`.
- [ ] **Step 4:** `SLAVE_CARGO "cargo test"` → all tests, old and new, PASS.
- [ ] **Step 5:** `git status --short` shows only the files listed above.

### Task 3: Heartbeat watchdog

**Files:**
- Modify: `src/sonic-supervisord-utilities-rs/src/pebble_mode.rs`
- Test: `src/sonic-supervisord-utilities-rs/tests/test_pebble_mode.rs`

**Interfaces:**
- Consumes: `proc_exit_listener::{get_group_and_process_list}` is NOT used (it calls `process::exit`); use Task 2's `read_program_list` for `watchdog_processes`.
- Produces:
  - `fn heartbeat_file(dir: &Path, process: &str) -> PathBuf` → `dir/<process>.heartbeat`
  - `struct Watchdog` with `fn new() -> Self` and
    `fn tick(&mut self, now: Instant, watch_file: &Path, heartbeat_dir: &Path, load_thresholds: &mut dyn FnMut() -> HashMap<String, f64>) -> Vec<(String, u64)>` — returns `(process, elapsed_minutes)` for every stale process; `load_thresholds` is called at most once per `Watchdog` lifetime, on the first tick that finds any heartbeat file; thresholds resolved with `proc_exit_listener::get_heartbeat_alert_interval`
  - const `HEARTBEAT_DIR = "/tmp"`

- [ ] **Step 1: Write failing tests** (temp dir; set mtimes with `File::set_modified`; drive `now` as `t0 + Duration`):
  - `wd_no_file_no_alert`: watch file `program:orchagent`, no heartbeat file → `[]`, loader not called.
  - `wd_first_seen_then_stale`: create file at t0 → tick(t0) `[]` and loader called once (returns empty map); tick(t0+59s) `[]`; tick(t0+60s) `[("orchagent",1)]`; tick(t0+61s) `[("orchagent",1)]`; tick(t0+125s) `[("orchagent",2)]`.
  - `wd_mtime_change_resets`: stale at t0+60s, then change mtime, tick(t0+61s) `[]`, tick(t0+120s) `[]`, tick(t0+121s) `[("orchagent",1)]`.
  - `wd_threshold_zero_disables`: loader returns `{"orchagent": 0.0}` → never alerts at t0+600s.
  - `wd_custom_threshold`: loader returns `{"orchagent": 10.0}` → alert at t0+10s with minutes 0.
  - `wd_recreate_no_reload`: stale, delete file → tick `[]`; recreate → tick `[]` (fresh first-seen), loader call count still 1.
  - `wd_no_watch_file`: watch file missing → `[]`, no panic.
- [ ] **Step 2:** `SLAVE_CARGO "cargo test --test test_pebble_mode wd_"` → FAIL.
- [ ] **Step 3:** Implement. Per process state `{ last_mtime: SystemTime, last_beat: Instant }`; missing file removes the state; first seen or changed mtime sets `last_beat = now`; elapsed = `now - last_beat` in seconds (f64); alert when `threshold > 0.0 && elapsed >= threshold`, minutes `(elapsed / 60.0) as u64`.
- [ ] **Step 4:** `SLAVE_CARGO "cargo test"` → all PASS.
- [ ] **Step 5:** `git status --short`.

### Task 4: Pebble-mode main loop and binary dispatch

**Files:**
- Modify: `src/sonic-supervisord-utilities-rs/src/pebble_mode.rs`
- Modify: `src/sonic-supervisord-utilities-rs/src/bin/supervisor_proc_exit_listener.rs`

**Interfaces:**
- Consumes: Task 2 `report_exits`, `pebble_socket_path`, `PEBBLE_API_TIMEOUT`; Task 3 `Watchdog`, `HEARTBEAT_DIR`; `proc_exit_listener::{generate_alerting_message, publish_events, load_heartbeat_alert_interval, ConfigDBTrait}`; `swss_common::{ConfigDBConnector, EventPublisher}`.
- Produces: `pub fn main_with_args(args: Option<Vec<String>>) -> Result<(), String>` in `pebble_mode`; clap struct `PebbleArgs { #[arg(long)] pebble: bool, #[arg(short = 'c', long = "container-name")] container_name: Option<String> }`.

- [ ] **Step 1:** Implement `main_with_args`: `syslog::init_unix(LOG_USER, Info)` (Err → return Err, pebble restarts us); container name from arg or `CONTAINER_NAME` (both missing → Err); block SIGTERM with `libc::sigprocmask` **before** anything else that may spawn threads; loop: `libc::sigtimedwait` on {SIGTERM} with 1s timeout; on timeout run `Watchdog::tick` with real paths and a loader that builds `ConfigDBConnector::new(false, None)` + `connect(true, false)` and calls `load_heartbeat_alert_interval` (any Err → empty map), and log each alert via `generate_alerting_message(p, "stuck", m, Severity::LOG_WARNING)`; on SIGTERM call `report_exits` with a `publish` closure that lazily creates `EventPublisher::new("sonic-events-host")` and calls `publish_events`, then `deinit()` the publisher if created, then return `Ok(())`.
- [ ] **Step 2:** In the bin: if any argv element equals `--pebble`, call `pebble_mode::main_with_args(None)` (map Err to exit code 1 after printing to stderr); otherwise the existing `main_with_args(None)?` unchanged.
- [ ] **Step 3:** `SLAVE_CARGO "cargo test && cargo build --release --locked && ldd target/release/supervisor-proc-exit-listener-rs"` → tests PASS; ldd lists only libswsscommon, libstdc++, libgcc_s, libc, libm (and libswsscommon's own deps), all of which exist in the database rock (verified on dut2: libc.so.6, libgcc_s.so.1, libstdc++.so.6).
- [ ] **Step 4:** Smoke: `SLAVE_CARGO "target/release/supervisor-proc-exit-listener-rs --help | head -3; target/release/supervisor-proc-exit-listener-rs --container-name x </dev/null; echo rc=\$?"` → old mode still parses `--container-name` (it may fail later on ConfigDB connect; it must not mention `--pebble`).
- [ ] **Step 5:** `git diff --stat -- src/sonic-supervisord-utilities-rs/src/proc_exit_listener.rs` → empty.

### Task 5: orchagent heartbeat filter and swss watchdog list

**Files:**
- Modify: `dockers/docker-orchagent/orchagent.sh` (final `exec` only)
- Modify: `dockers/docker-orchagent/start.sh` (add `-t /usr/share/sonic/templates/watchdog_processes.j2,/etc/supervisor/watchdog_processes \` next to the `critical_processes.j2` line in `CFGGEN_PARAMS`)
- Modify: `dockers/docker-orchagent/rockcraft.yaml` (organize `watchdog_processes.j2: usr/share/sonic/templates/watchdog_processes.j2`; delete the `- -watchdog_processes.j2` stage exclusion)

**Interfaces:**
- Produces: heartbeat file `/tmp/orchagent.heartbeat` (Task 3 reads `HEARTBEAT_DIR/orchagent.heartbeat`).

- [ ] **Step 1:** Replace the final line with the block from spec §6.3, verbatim (comment lines included).
- [ ] **Step 2: Docker-path and pebble-path check** in a throwaway container (no repo files created):
  ```bash
  docker run --rm -v "$PWD/dockers/docker-orchagent/orchagent.sh:/o.sh:ro" ubuntu:26.04 bash -c '
    printf "#!/bin/bash\necho normal-1\necho \"<!--XSUPERVISOR:BEGIN-->heartbeat<!--XSUPERVISOR:END-->\"\n" > /usr/bin/orchagent; chmod +x /usr/bin/orchagent
    sed -n "/^# Mask SIGHUP/,\$p" /o.sh > /tail.sh
    echo "== supervisord path"; bash /tail.sh; ls /tmp/orchagent.heartbeat 2>&1
    cp /bin/sleep /tmp/pebble; /tmp/pebble 30 & sleep 0.2
    echo "== pebble path"; bash /tail.sh; sleep 0.3; ls /tmp/orchagent.heartbeat'
  ```
  Expected: supervisord path prints both lines and no heartbeat file; pebble path prints only `normal-1` and the heartbeat file exists.
- [ ] **Step 3:** `bash -n dockers/docker-orchagent/orchagent.sh dockers/docker-orchagent/start.sh` → no output; `python3 -c 'import yaml;yaml.safe_load(open("dockers/docker-orchagent/rockcraft.yaml"))'` → no error.
- [ ] **Step 4:** `git status --short`.

### Task 6: Package the listener into every in-scope rock

**Files:**
- Modify: `rockcraft.yaml` of the 16 rocks in Global Constraints.

- [ ] **Step 1:** In each file: add `dpkg -x debs/sonic-supervisord-utilities-rs_*.deb ${CRAFT_PART_INSTALL}` on the line after the existing `dpkg -x debs/libswsscommon_*.deb ${CRAFT_PART_INSTALL}`; add to top-level `services:` (after `rsyslogd`, same key order style as neighbours):
  ```yaml
    proc-exit-listener:
      command: /usr/bin/supervisor-proc-exit-listener-rs --pebble
      override: replace
      startup: enabled
      on-success: ignore
      requires: [rsyslogd]
      after: [rsyslogd]
  ```
  This puts the service in rockcraft's own boot layer (`001-rockcraft-*.yaml`), the same way `rsyslogd` is defined, so it starts with rsyslogd before start.sh. This resolves spec §10's open loading question without staging extra layer files.
- [ ] **Step 2: Verify** with one script run from the worktree root:
  ```bash
  python3 - <<'EOF'
  import yaml, glob
  files = [f"dockers/docker-{n}/rockcraft.yaml" for n in "database dhcp-relay eventd fpm-frr lldp macsec nat orchagent platform-monitor router-advertiser sflow snmp sonic-gnmi sysmgr teamd".split()] + ["platform/broadcom/docker-syncd-brcm/rockcraft.yaml"]
  want = {"command": "/usr/bin/supervisor-proc-exit-listener-rs --pebble", "override": "replace", "startup": "enabled", "on-success": "ignore", "requires": ["rsyslogd"], "after": ["rsyslogd"]}
  for f in files:
      d = yaml.safe_load(open(f)); s = d["services"]
      assert s.get("proc-exit-listener") == want, f
      assert "rsyslogd" in s, f
      assert open(f).read().count("dpkg -x debs/sonic-supervisord-utilities-rs_*.deb") == 1, f
  for f in ["dockers/docker-sonic-mgmt-framework/rockcraft.yaml", "dockers/docker-iccpd/rockcraft.yaml", "dockers/docker-dhcp-server/rockcraft.yaml"]:
      assert "supervisor-proc-exit-listener" not in open(f).read(), f
  print("ok", len(files))
  EOF
  ```
  Expected: `ok 16`.
- [ ] **Step 3:** `git status --short` shows exactly 16 rockcraft.yaml changes plus earlier tasks' files.

### Task 7: Hardware verification on dut2

Only dut2 (`ssh dut2`, 10.240.36.51); never `et3-dh3-f-sw1`. Containers may be restarted. Image on dut2 lacks the change, so deploy into containers' writable layers, mirroring what the rock will contain, then remove it all.

**Deploy per container `C`** (snmp, eventd, database, swss): `docker cp` the release binary to `C:/usr/bin/supervisor-proc-exit-listener-rs`; write the service block of Task 6 as `services:` YAML to `C:/var/lib/pebble/default/layers/900-pel-test.yaml` (persists across container restart, loaded at pebble boot); for swss also copy the new `orchagent.sh` (keep `/usr/bin/orchagent.sh.pel-orig`) and write `/etc/supervisor/watchdog_processes` containing `program:orchagent`; then `sudo systemctl restart <svc>` once. Space restarts of one service ≥ 2 min apart (systemd start-limit was hit once before).

- [ ] **Step 1: Startup** — for each C: `docker exec C pebble services proc-exit-listener` shows `active`; `docker logs --since 5m C | grep -c 'supervisor-proc-exit-listener.*exited'` is 0 or a few early restarts that end in `active` (Review Focus 4).
- [ ] **Step 2: Exit report** — snmp: `kill -9` the `sonic_ax_impl` pid; eventd: `kill -9` eventd; database (do it last: a database restart cascades to every dependent service): `kill -9` the redis-server on 6379. For each, host syslog has `C#supervisor-proc-exit-listener-rs: Process '<p>' exited unexpectedly. Terminating supervisor '<C>'` and `EVENT_PUBLISHED` with `process-exited-unexpectedly`; `docker logs` shows listener stopped before `rsyslogd`. For snmp also run `docker exec -d eventd timeout 60 stdbuf -oL events_tool -r -n 1` beforehand and confirm the full event text.
- [ ] **Step 3: Normal stop** — `sudo systemctl restart snmp`: no `exited unexpectedly` line, no event from the listener.
- [ ] **Step 4: Heartbeat** — swss: the timestamp of `sudo grep XSUPERVISOR /var/log/syslog | tail -1` is earlier than the swss restart; `/tmp/orchagent.heartbeat` mtime advances every ~10s; `kill -STOP <orchagent>` for 150s → `swss#supervisor-proc-exit-listener-rs: Process 'orchagent' is stuck in namespace 'host' (1 minutes).` about once per second, then `(2 minutes)`; `kill -CONT` → alerts stop.
- [ ] **Step 5: Cleanup** — remove the binary, `900-pel-test.yaml`, swss `watchdog_processes`, restore `orchagent.sh` from `.pel-orig`; restart each service once; `docker diff C | grep -E 'pel|proc-exit|watchdog_processes|orchagent.sh'` empty; `show system-health detail` OK for all; interface up-count equals the pre-test value.

### Task 8: Spec sync

**Files:**
- Modify: `~/repos/sonic-buildimage-doc/docs/superpowers/specs/2026-11-06-pebble-proc-exit-listener-design-{zh,en}.md`

- [ ] **Step 1:** §6.5: replace the shared-layer-file approach and its "loading" bullet with the per-rock `services:` entry from Task 6 (reason: same as `rsyslogd`, loaded by pebble at boot from rockcraft's own layer; no extra file staging). §6.6: drop "organize entry for the layer file". §10: remove the resolved loading item. Keep zh and en in sync; no line numbers.
- [ ] **Step 2:** Record Task 7 results in §9 (date, image, what, result).
- [ ] **Step 3:** `git -C ~/repos/sonic-buildimage-doc status --short` shows the spec files and this plan only.
