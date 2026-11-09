//! Supervisor process exit listener binary

use sonic_supervisord_utilities_rs::pebble_mode;
use sonic_supervisord_utilities_rs::proc_exit_listener::main_with_args;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    // --pebble: rock containers, run as a pebble service; otherwise the supervisord eventlistener, unchanged
    if std::env::args().any(|a| a == "--pebble") {
        if let Err(e) = pebble_mode::main_with_args(None) {
            eprintln!("supervisor-proc-exit-listener-rs --pebble: {}", e);
            std::process::exit(1);
        }
        return Ok(());
    }
    main_with_args(None)?;
    Ok(())
}
