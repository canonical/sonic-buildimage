//! Pebble mode of supervisor-proc-exit-listener-rs: same reports as the supervisord listener, for rock containers.
//! Run as a pebble service: `supervisor-proc-exit-listener-rs --pebble`.
//! On SIGTERM (pebble shutting down) it reports critical services pebble shows in `error`.

use crate::proc_exit_listener::get_heartbeat_alert_interval;
use log::{error, warn};
use std::collections::HashMap;
use std::fs;
use std::io::{Read, Write};
use std::os::unix::net::UnixStream;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant, SystemTime};

pub const PEBBLE_DEFAULT_DIR: &str = "/var/lib/pebble/default";
pub const PEBBLE_API_TIMEOUT: Duration = Duration::from_secs(2);
/// orchagent.sh's pebble branch refreshes HEARTBEAT_DIR/<process>.heartbeat on every heartbeat line
pub const HEARTBEAT_DIR: &str = "/tmp";

/// One entry of pebble's `GET /v1/services` result
#[derive(Debug, Clone, PartialEq)]
pub struct PebbleService {
    pub name: String,
    pub current: String,
}

/// Pebble API socket: $PEBBLE_SOCKET, else ${PEBBLE:-/var/lib/pebble/default}/.pebble.socket
pub fn pebble_socket_path() -> PathBuf {
    if let Some(socket) = std::env::var_os("PEBBLE_SOCKET").filter(|s| !s.is_empty()) {
        return PathBuf::from(socket);
    }
    let dir = std::env::var_os("PEBBLE")
        .filter(|s| !s.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(PEBBLE_DEFAULT_DIR));
    dir.join(".pebble.socket")
}

/// Parse a full HTTP response (status line, headers, body) of `GET /v1/services`
pub fn parse_services_response(raw: &str) -> Result<Vec<PebbleService>, String> {
    let (head, body) = raw
        .split_once("\r\n\r\n")
        .ok_or_else(|| "malformed HTTP response".to_string())?;
    let status_line = head.lines().next().unwrap_or_default();
    if !status_line.contains(" 200 ") {
        return Err(format!("pebble API returned '{}'", status_line));
    }
    let json: serde_json::Value =
        serde_json::from_str(body).map_err(|e| format!("invalid pebble API JSON: {}", e))?;
    let result = json
        .get("result")
        .and_then(|r| r.as_array())
        .ok_or_else(|| "pebble API response has no result array".to_string())?;
    result
        .iter()
        .map(|s| {
            let name = s.get("name").and_then(|v| v.as_str());
            let current = s.get("current").and_then(|v| v.as_str());
            match (name, current) {
                (Some(n), Some(c)) => Ok(PebbleService { name: n.to_string(), current: c.to_string() }),
                _ => Err(format!("pebble service entry without name/current: {}", s)),
            }
        })
        .collect()
}

/// Query pebble's service list over its Unix socket
pub fn query_services(socket: &Path, timeout: Duration) -> Result<Vec<PebbleService>, String> {
    let mut stream =
        UnixStream::connect(socket).map_err(|e| format!("cannot connect to {}: {}", socket.display(), e))?;
    stream.set_read_timeout(Some(timeout)).map_err(|e| e.to_string())?;
    stream.set_write_timeout(Some(timeout)).map_err(|e| e.to_string())?;
    stream
        .write_all(b"GET /v1/services HTTP/1.0\r\nHost: localhost\r\n\r\n")
        .map_err(|e| format!("cannot send pebble API request: {}", e))?;
    let mut raw = String::new();
    stream
        .read_to_string(&mut raw)
        .map_err(|e| format!("cannot read pebble API response: {}", e))?;
    parse_services_response(&raw)
}

/// `program:` names of a critical_processes/watchdog_processes file; `group:` entries are skipped with a warning
pub fn read_program_list(path: &Path) -> Result<Vec<String>, String> {
    let content = fs::read_to_string(path).map_err(|e| format!("cannot read {}: {}", path.display(), e))?;
    let mut programs = Vec::new();
    for line in content.lines() {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        match line.split_once(':').map(|(k, v)| (k.trim(), v.trim())) {
            Some(("program", v)) if !v.is_empty() && !v.contains(':') => programs.push(v.to_string()),
            Some(("group", v)) if !v.is_empty() && !v.contains(':') => {
                warn!("Ignoring '{}' in {}: pebble has no process groups", line, path.display())
            }
            _ => return Err(format!("syntax of the line {} in {} is incorrect", line, path.display())),
        }
    }
    Ok(programs)
}

/// Critical services that pebble shows in `error`, i.e. exited on their own before shutdown
pub fn exited_critical(services: &[PebbleService], critical: &[String]) -> Vec<String> {
    services
        .iter()
        .filter(|s| s.current == "error" && critical.contains(&s.name))
        .map(|s| s.name.clone())
        .collect()
}

/// Same text as the supervisord listener writes
pub fn exit_message(process: &str, ctr: &str) -> String {
    format!("Process '{}' exited unexpectedly. Terminating supervisor '{}'", process, ctr)
}

/// Log and publish every critical service that exited unexpectedly; returns the reported names. Never panics.
pub fn report_exits(
    ctr: &str,
    critical_file: &Path,
    socket: &Path,
    timeout: Duration,
    publish: &mut dyn FnMut(&str) -> Result<(), String>,
) -> Vec<String> {
    let critical = match read_program_list(critical_file) {
        Ok(c) => c,
        Err(e) => {
            warn!("Not reporting process exits: {}", e);
            return Vec::new();
        }
    };
    if critical.is_empty() {
        return Vec::new();
    }
    let services = match query_services(socket, timeout) {
        Ok(s) => s,
        Err(e) => {
            error!("Not reporting process exits: {}", e);
            return Vec::new();
        }
    };
    let failed = exited_critical(&services, &critical);
    for name in &failed {
        log::info!("{}", exit_message(name, ctr));
        if let Err(e) = publish(name) {
            error!("Failed to publish event for process {}: {}", name, e);
        }
    }
    failed
}

/// Heartbeat file of a watchdog process: <dir>/<process>.heartbeat
pub fn heartbeat_file(dir: &Path, process: &str) -> PathBuf {
    dir.join(format!("{}.heartbeat", process))
}

struct HeartbeatState {
    last_mtime: SystemTime,
    last_beat: Instant,
}

/// Heartbeat watchdog over heartbeat-file mtimes; mirrors the supervisord listener's heartbeat check
pub struct Watchdog {
    states: HashMap<String, HeartbeatState>,
    thresholds: Option<HashMap<String, f64>>,
}

impl Default for Watchdog {
    fn default() -> Self {
        Self::new()
    }
}

impl Watchdog {
    pub fn new() -> Self {
        Watchdog { states: HashMap::new(), thresholds: None }
    }

    /// One check; returns (process, elapsed minutes) for every process whose heartbeat is stale.
    /// `load_thresholds` (HEARTBEAT alert intervals, seconds) is called once, when a heartbeat file is first found.
    pub fn tick(
        &mut self,
        now: Instant,
        watch_file: &Path,
        heartbeat_dir: &Path,
        load_thresholds: &mut dyn FnMut() -> HashMap<String, f64>,
    ) -> Vec<(String, u64)> {
        let processes = read_program_list(watch_file).unwrap_or_default();
        self.states.retain(|p, _| processes.contains(p));
        let mut alerts = Vec::new();
        for process in processes {
            let mtime = match fs::metadata(heartbeat_file(heartbeat_dir, &process)).and_then(|m| m.modified()) {
                Ok(t) => t,
                Err(_) => {
                    self.states.remove(&process);
                    continue;
                }
            };
            let thresholds = self.thresholds.get_or_insert_with(|| load_thresholds());
            let threshold = get_heartbeat_alert_interval(&process, thresholds);
            let state = self
                .states
                .entry(process.clone())
                .or_insert(HeartbeatState { last_mtime: mtime, last_beat: now });
            if state.last_mtime != mtime {
                state.last_mtime = mtime;
                state.last_beat = now;
            }
            let elapsed = now.saturating_duration_since(state.last_beat).as_secs_f64();
            if threshold > 0.0 && elapsed >= threshold {
                alerts.push((process, (elapsed / 60.0) as u64));
            }
        }
        alerts
    }
}

const CRITICAL_PROCESSES_FILE: &str = "/etc/supervisor/critical_processes";
const WATCH_PROCESSES_FILE: &str = "/etc/supervisor/watchdog_processes";
const EVENTS_PUBLISHER_SOURCE: &str = "sonic-events-host";
const TICK: libc::timespec = libc::timespec { tv_sec: 1, tv_nsec: 0 };

#[derive(clap::Parser, Debug)]
#[command(name = "supervisor-proc-exit-listener-rs --pebble")]
#[command(about = "SONiC process exit listener, pebble mode")]
pub struct PebbleArgs {
    #[arg(long)]
    pub pebble: bool,

    /// Defaults to $CONTAINER_NAME
    #[arg(short = 'c', long = "container-name")]
    pub container_name: Option<String>,
}

/// HEARTBEAT alert intervals from CONFIG_DB; empty on any error (callers fall back to the default)
fn load_thresholds_from_db() -> HashMap<String, f64> {
    let db = match swss_common::ConfigDBConnector::new(false, None) {
        Ok(db) => db,
        Err(e) => {
            warn!("Cannot create ConfigDB connector for HEARTBEAT: {}", e);
            return HashMap::new();
        }
    };
    // wait_for_init=false: never block the watchdog loop, and so SIGTERM handling, on DB init
    if let Err(e) = db.connect(false, false) {
        warn!("Cannot connect to ConfigDB for HEARTBEAT: {}", e);
        return HashMap::new();
    }
    crate::proc_exit_listener::load_heartbeat_alert_interval(&db)
}

fn on_sigterm(ctr: &str) {
    let mut publisher: Option<swss_common::EventPublisher> = None;
    report_exits(ctr, Path::new(CRITICAL_PROCESSES_FILE), &pebble_socket_path(), PEBBLE_API_TIMEOUT, &mut |name: &str| {
        if publisher.is_none() {
            publisher = Some(swss_common::EventPublisher::new(EVENTS_PUBLISHER_SOURCE).map_err(|e| e.to_string())?);
        }
        let handle = publisher.as_ref().expect("publisher initialised above");
        crate::proc_exit_listener::publish_events(handle, name, ctr).map_err(|e| e.to_string())
    });
    if let Some(mut p) = publisher {
        if let Err(e) = p.deinit() {
            warn!("Failed to deinit event publisher: {}", e);
        }
    }
}

/// Entry point of `--pebble`: 1s heartbeat checks until SIGTERM, then report exited critical services and return
pub fn main_with_args(args: Option<Vec<String>>) -> Result<(), String> {
    use clap::Parser;
    let args = match args {
        Some(a) => PebbleArgs::try_parse_from(a).map_err(|e| e.to_string())?,
        None => PebbleArgs::parse(),
    };
    let ctr = args
        .container_name
        .or_else(|| std::env::var("CONTAINER_NAME").ok().filter(|s| !s.is_empty()))
        .ok_or_else(|| "no --container-name and no CONTAINER_NAME".to_string())?;

    // Block SIGTERM first, before anything can spawn threads, so it is only taken by sigtimedwait below
    let mut set: libc::sigset_t = unsafe { std::mem::zeroed() };
    unsafe {
        libc::sigemptyset(&mut set);
        libc::sigaddset(&mut set, libc::SIGTERM);
        if libc::pthread_sigmask(libc::SIG_BLOCK, &set, std::ptr::null_mut()) != 0 {
            return Err("cannot block SIGTERM".to_string());
        }
    }

    syslog::init_unix(syslog::Facility::LOG_USER, log::LevelFilter::Info)
        .map_err(|e| format!("Failed to initialize syslog: {}", e))?;

    let mut watchdog = Watchdog::new();
    loop {
        let signo = unsafe { libc::sigtimedwait(&set, std::ptr::null_mut(), &TICK) };
        if signo == libc::SIGTERM {
            on_sigterm(&ctr);
            return Ok(());
        }
        let alerts = watchdog.tick(
            Instant::now(),
            Path::new(WATCH_PROCESSES_FILE),
            Path::new(HEARTBEAT_DIR),
            &mut load_thresholds_from_db,
        );
        for (process, minutes) in alerts {
            crate::proc_exit_listener::generate_alerting_message(&process, "stuck", minutes, syslog::Severity::LOG_WARNING);
        }
    }
}
