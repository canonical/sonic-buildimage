use std::io::{BufRead, BufReader, Write};
use std::net::TcpListener;
use std::process::Command;
 
use serde::Serialize;
 
#[derive(Serialize)]
struct HealthStatus {
    check_bmp_db: String,
    check_bmp_port: String,
}
 
// Rock containers run pebble instead of supervisord
const DB_STATUS_CMD: &str = "if command -v supervisorctl >/dev/null; then supervisorctl status; \
    else pebble services --format json redis_bmp; fi";

// Reads `supervisorctl status` (RUNNING) or `pebble services --format json` (active)
fn redis_bmp_running(status: &str) -> bool {
    if let Ok(json) = serde_json::from_str::<serde_json::Value>(status) {
        return json["services"]["redis_bmp"]["current"] == "active";
    }
    status.lines().any(|line| {
        let fields: Vec<&str> = line.split_whitespace().collect();
        fields.first() == Some(&"redis_bmp") && fields.get(1) == Some(&"RUNNING")
    })
}

fn check_bmp_db() -> String {
    let output = Command::new("docker")
        .args(["exec", "-i", "database", "bash", "-c", DB_STATUS_CMD])
        .output();

    match output {
        Ok(output) => {
            if !output.status.success() {
                return format!("ERROR: Command failed with status {}", output.status);
            }

            let stdout = String::from_utf8_lossy(&output.stdout);

            if redis_bmp_running(&stdout) {
                "OK".to_string()
            } else {
                "ERROR: redis_bmp not running".to_string()
            }
        }
        Err(e) => format!("ERROR: Failed to run command - {}", e),
    }
}
 
fn check_bmp_port() -> String {
    match std::net::TcpStream::connect("127.0.0.1:5000") {
        Ok(_) => "OK".to_string(),
        Err(e) => format!("ERROR: {}", e),
    }
}
 
fn main() {
    // Start a HTTP server listening on port 50060
    let listener = TcpListener::bind("127.0.0.1:50060")
    .expect("Failed to bind to 127.0.0.1:50060");

    println!("Watchdog HTTP server running on http://127.0.0.1:50060");

    for stream_result in listener.incoming() {
        match stream_result {
            Ok(mut stream) => {
                let mut reader = BufReader::new(&stream);
                let mut request_line = String::new();
 
                if let Ok(_) = reader.read_line(&mut request_line) {
                    println!("Received request: {}", request_line.trim_end());
 
                    if !request_line.starts_with("GET /") {
                        let response = "HTTP/1.1 405 Method Not Allowed\r\n\r\n";
                        stream.write_all(response.as_bytes()).ok();
                        continue;
                    }
 
                    let db_result = check_bmp_db();
                    let port_result = check_bmp_port();
 
                    let status = HealthStatus {
                        check_bmp_db: db_result.clone(),
                        check_bmp_port: port_result.clone(),
                    };
 
                    let json_body = serde_json::to_string(&status).unwrap();
                    let all_passed = [db_result, port_result]
                        .iter()
                        .all(|s| s.starts_with("OK"));
 
                    let status_line = if all_passed {
                        "HTTP/1.1 200 OK"
                    } else {
                        "HTTP/1.1 500 Internal Server Error"
                    };
 
                    let response = format!(
                        "{status_line}\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{}",
                        json_body.len(),
                        json_body
                    );
 
                    if let Err(e) = stream.write_all(response.as_bytes()) {
                        eprintln!("Failed to write response: {}", e);
                    }
                }
            }
            Err(e) => {
                eprintln!("Error accepting connection: {}", e);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn supervisorctl_status() {
        assert!(redis_bmp_running("redis       RUNNING   pid 32, uptime 0:00:09\nredis_bmp   RUNNING   pid 33, uptime 0:00:09\n"));
        assert!(!redis_bmp_running("redis_bmp   EXITED    Oct 05 02:01 AM\n"));
    }

    #[test]
    fn pebble_services() {
        let service = |current: &str| format!(
            r#"{{"services":{{"redis_bmp":{{"name":"redis_bmp","startup":"disabled","current":"{current}"}}}}}}"#);
        assert!(redis_bmp_running(&service("active")));
        assert!(!redis_bmp_running(&service("error")));
        assert!(!redis_bmp_running(r#"{"services":{}}"#));
    }
}
