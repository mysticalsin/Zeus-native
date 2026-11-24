//! Public helpers must not hang on a zero period.

use haru_companion::watchdog::find_loop;
use std::time::Duration;

#[test]
fn a_zero_loop_period_returns() {
    let (tx, rx) = std::sync::mpsc::channel();
    std::thread::spawn(move || {
        let found = find_loop(&["a", "a", "a", "a"], 0, 2, 2);
        let _ = tx.send(found);
    });
    assert!(
        rx.recv_timeout(Duration::from_secs(1)).is_ok(),
        "find_loop hung on period 0"
    );
}
