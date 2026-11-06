//! Tests for the pebble mode of supervisor-proc-exit-listener-rs

use sonic_supervisord_utilities_rs::pebble_mode::*;
use std::cell::RefCell;
use std::io::{Read, Write};
use std::os::unix::net::UnixListener;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};
use tempfile::TempDir;

const SERVICES_OK: &str = "HTTP/1.0 200 OK\r\nContent-Type: application/json\r\n\r\n{\"type\":\"sync\",\"status-code\":200,\"status\":\"OK\",\"result\":[{\"name\":\"snmpd\",\"startup\":\"disabled\",\"current\":\"inactive\"},{\"name\":\"snmp-subagent\",\"startup\":\"disabled\",\"current\":\"error\"}]}";
const SERVICES_ALL_INACTIVE: &str = "HTTP/1.0 200 OK\r\nContent-Type: application/json\r\n\r\n{\"type\":\"sync\",\"status-code\":200,\"status\":\"OK\",\"result\":[{\"name\":\"snmpd\",\"startup\":\"disabled\",\"current\":\"inactive\"},{\"name\":\"snmp-subagent\",\"startup\":\"disabled\",\"current\":\"inactive\"}]}";

/// Serve one pebble API connection on dir/.pebble.socket.
/// Some(r): read the request, answer r. None: accept and never answer.
fn fake_pebble(dir: &Path, response: Option<&'static str>) -> PathBuf {
    let path = dir.join(".pebble.socket");
    let listener = UnixListener::bind(&path).unwrap();
    std::thread::spawn(move || {
        if let Ok((mut conn, _)) = listener.accept() {
            match response {
                Some(r) => {
                    let mut buf = [0u8; 1024];
                    let _ = conn.read(&mut buf);
                    let _ = conn.write_all(r.as_bytes());
                }
                None => std::thread::sleep(Duration::from_secs(10)),
            }
        }
    });
    path
}

fn write_file(dir: &Path, name: &str, content: &str) -> PathBuf {
    let path = dir.join(name);
    std::fs::write(&path, content).unwrap();
    path
}

fn svc(name: &str, current: &str) -> PebbleService {
    PebbleService { name: name.to_string(), current: current.to_string() }
}

#[test]
fn parse_ok() {
    let services = parse_services_response(SERVICES_OK).unwrap();
    assert_eq!(services, vec![svc("snmpd", "inactive"), svc("snmp-subagent", "error")]);
}

#[test]
fn parse_non_200() {
    let raw = "HTTP/1.0 500 Internal Server Error\r\n\r\n{\"type\":\"error\",\"result\":{\"message\":\"x\"}}";
    assert!(parse_services_response(raw).is_err());
}

#[test]
fn parse_garbage() {
    assert!(parse_services_response("not http").is_err());
}

#[test]
fn exited_critical_filters() {
    let services = vec![svc("a", "error"), svc("b", "inactive"), svc("c", "error"), svc("d", "active")];
    let critical = vec!["a".to_string(), "b".to_string(), "d".to_string()];
    assert_eq!(exited_critical(&services, &critical), vec!["a".to_string()]);
}

#[test]
fn read_program_list_variants() {
    let dir = TempDir::new().unwrap();
    let ok = write_file(dir.path(), "ok", "program:x\n\n  program: y \ngroup:g\nprogram:z");
    assert_eq!(read_program_list(&ok).unwrap(), vec!["x", "y", "z"]);
    assert!(read_program_list(&dir.path().join("missing")).is_err());
    let bogus = write_file(dir.path(), "bogus", "bogus\n");
    assert!(read_program_list(&bogus).is_err());
    let empty = write_file(dir.path(), "empty", "");
    assert_eq!(read_program_list(&empty).unwrap(), Vec::<String>::new());
}

#[test]
fn exit_message_text() {
    assert_eq!(
        exit_message("snmpd", "snmp"),
        "Process 'snmpd' exited unexpectedly. Terminating supervisor 'snmp'"
    );
}

#[test]
fn report_exits_reports_error_critical() {
    let dir = TempDir::new().unwrap();
    let socket = fake_pebble(dir.path(), Some(SERVICES_OK));
    let critical = write_file(dir.path(), "critical", "program:snmpd\nprogram:snmp-subagent\n");
    let published = RefCell::new(Vec::new());
    let reported = report_exits("snmp", &critical, &socket, PEBBLE_API_TIMEOUT, &mut |p: &str| {
        published.borrow_mut().push(p.to_string());
        Ok(())
    });
    assert_eq!(reported, vec!["snmp-subagent".to_string()]);
    assert_eq!(*published.borrow(), vec!["snmp-subagent".to_string()]);
}

#[test]
fn report_exits_normal_stop() {
    let dir = TempDir::new().unwrap();
    let socket = fake_pebble(dir.path(), Some(SERVICES_ALL_INACTIVE));
    let critical = write_file(dir.path(), "critical", "program:snmpd\nprogram:snmp-subagent\n");
    let mut calls = 0;
    let reported = report_exits("snmp", &critical, &socket, PEBBLE_API_TIMEOUT, &mut |_p: &str| {
        calls += 1;
        Ok(())
    });
    assert!(reported.is_empty());
    assert_eq!(calls, 0);
}

#[test]
fn report_exits_missing_critical_file() {
    let dir = TempDir::new().unwrap();
    let socket = fake_pebble(dir.path(), Some(SERVICES_OK));
    let mut calls = 0;
    let reported = report_exits("snmp", &dir.path().join("missing"), &socket, PEBBLE_API_TIMEOUT, &mut |_p: &str| {
        calls += 1;
        Ok(())
    });
    assert!(reported.is_empty());
    assert_eq!(calls, 0);
}

#[test]
fn report_exits_no_socket() {
    let dir = TempDir::new().unwrap();
    let critical = write_file(dir.path(), "critical", "program:snmp-subagent\n");
    let reported = report_exits("snmp", &critical, &dir.path().join("nosock"), PEBBLE_API_TIMEOUT, &mut |_p: &str| Ok(()));
    assert!(reported.is_empty());
}

#[test]
fn report_exits_hung_socket() {
    let dir = TempDir::new().unwrap();
    let socket = fake_pebble(dir.path(), None);
    let critical = write_file(dir.path(), "critical", "program:snmp-subagent\n");
    let start = Instant::now();
    let reported = report_exits("snmp", &critical, &socket, Duration::from_millis(300), &mut |_p: &str| Ok(()));
    assert!(reported.is_empty());
    assert!(start.elapsed() < Duration::from_secs(2), "took {:?}", start.elapsed());
}

// ---- heartbeat watchdog ----

use std::collections::HashMap;
use std::time::SystemTime;

fn set_mtime(path: &Path, t: SystemTime) {
    std::fs::OpenOptions::new().write(true).open(path).unwrap().set_modified(t).unwrap();
}

struct Wd {
    dir: TempDir,
    watch: PathBuf,
    hb: PathBuf,
    t0: Instant,
}

impl Wd {
    fn new() -> Self {
        let dir = TempDir::new().unwrap();
        let watch = write_file(dir.path(), "watchdog_processes", "program:orchagent\n");
        let hb = heartbeat_file(dir.path(), "orchagent");
        Wd { dir, watch, hb, t0: Instant::now() }
    }
    fn touch(&self, secs_ago_base: u64) {
        std::fs::write(&self.hb, "").unwrap();
        set_mtime(&self.hb, SystemTime::UNIX_EPOCH + Duration::from_secs(1_000_000 + secs_ago_base));
    }
    fn tick(&self, w: &mut Watchdog, at: u64, loads: &RefCell<u32>, thresholds: &HashMap<String, f64>) -> Vec<(String, u64)> {
        w.tick(self.t0 + Duration::from_secs(at), &self.watch, self.dir.path(), &mut || {
            *loads.borrow_mut() += 1;
            thresholds.clone()
        })
    }
}

fn alert(m: u64) -> Vec<(String, u64)> {
    vec![("orchagent".to_string(), m)]
}

#[test]
fn wd_heartbeat_file_name() {
    assert_eq!(heartbeat_file(Path::new("/tmp"), "orchagent"), PathBuf::from("/tmp/orchagent.heartbeat"));
    assert_eq!(HEARTBEAT_DIR, "/tmp");
}

#[test]
fn wd_no_file_no_alert() {
    let wd = Wd::new();
    let mut w = Watchdog::new();
    let loads = RefCell::new(0);
    assert!(wd.tick(&mut w, 0, &loads, &HashMap::new()).is_empty());
    assert!(wd.tick(&mut w, 600, &loads, &HashMap::new()).is_empty());
    assert_eq!(*loads.borrow(), 0);
}

#[test]
fn wd_first_seen_then_stale() {
    let wd = Wd::new();
    let mut w = Watchdog::new();
    let loads = RefCell::new(0);
    let none = HashMap::new();
    wd.touch(0);
    assert!(wd.tick(&mut w, 0, &loads, &none).is_empty());
    assert_eq!(*loads.borrow(), 1);
    assert!(wd.tick(&mut w, 59, &loads, &none).is_empty());
    assert_eq!(wd.tick(&mut w, 60, &loads, &none), alert(1));
    assert_eq!(wd.tick(&mut w, 61, &loads, &none), alert(1));
    assert_eq!(wd.tick(&mut w, 125, &loads, &none), alert(2));
    assert_eq!(*loads.borrow(), 1);
}

#[test]
fn wd_mtime_change_resets() {
    let wd = Wd::new();
    let mut w = Watchdog::new();
    let loads = RefCell::new(0);
    let none = HashMap::new();
    wd.touch(0);
    wd.tick(&mut w, 0, &loads, &none);
    assert_eq!(wd.tick(&mut w, 60, &loads, &none), alert(1));
    set_mtime(&wd.hb, SystemTime::UNIX_EPOCH + Duration::from_secs(1_000_061));
    assert!(wd.tick(&mut w, 61, &loads, &none).is_empty());
    assert!(wd.tick(&mut w, 120, &loads, &none).is_empty());
    assert_eq!(wd.tick(&mut w, 121, &loads, &none), alert(1));
}

#[test]
fn wd_threshold_zero_disables() {
    let wd = Wd::new();
    let mut w = Watchdog::new();
    let loads = RefCell::new(0);
    let zero: HashMap<String, f64> = [("orchagent".to_string(), 0.0)].into();
    wd.touch(0);
    wd.tick(&mut w, 0, &loads, &zero);
    assert!(wd.tick(&mut w, 600, &loads, &zero).is_empty());
}

#[test]
fn wd_custom_threshold() {
    let wd = Wd::new();
    let mut w = Watchdog::new();
    let loads = RefCell::new(0);
    let ten: HashMap<String, f64> = [("orchagent".to_string(), 10.0)].into();
    wd.touch(0);
    wd.tick(&mut w, 0, &loads, &ten);
    assert!(wd.tick(&mut w, 9, &loads, &ten).is_empty());
    assert_eq!(wd.tick(&mut w, 10, &loads, &ten), alert(0));
}

#[test]
fn wd_recreate_no_reload() {
    let wd = Wd::new();
    let mut w = Watchdog::new();
    let loads = RefCell::new(0);
    let none = HashMap::new();
    wd.touch(0);
    wd.tick(&mut w, 0, &loads, &none);
    assert_eq!(wd.tick(&mut w, 60, &loads, &none), alert(1));
    std::fs::remove_file(&wd.hb).unwrap();
    assert!(wd.tick(&mut w, 61, &loads, &none).is_empty());
    wd.touch(0);
    assert!(wd.tick(&mut w, 62, &loads, &none).is_empty());
    assert!(wd.tick(&mut w, 121, &loads, &none).is_empty());
    assert_eq!(wd.tick(&mut w, 122, &loads, &none), alert(1));
    assert_eq!(*loads.borrow(), 1);
}

#[test]
fn wd_no_watch_file() {
    let wd = Wd::new();
    let mut w = Watchdog::new();
    let loads = RefCell::new(0);
    wd.touch(0);
    let r = w.tick(wd.t0, &wd.dir.path().join("missing"), wd.dir.path(), &mut || {
        *loads.borrow_mut() += 1;
        HashMap::new()
    });
    assert!(r.is_empty());
    assert_eq!(*loads.borrow(), 0);
}
