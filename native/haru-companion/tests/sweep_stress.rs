//! Connect churn and a synthetic half-hour must not grow fds or RSS.

use haru_companion::backend::{FakeBackend, ScriptStep};
use haru_companion::engine::Engine;
use haru_companion::serve::bind_socket;
use haru_companion::session::FRAME_SAMPLES;
use haru_companion::supervisor::SpyLauncher;
use std::io::{Read, Write};
use std::os::unix::net::UnixStream;
use std::time::{SystemTime, UNIX_EPOCH};

fn fd_count() -> usize {
    std::fs::read_dir("/proc/self/fd")
        .map(|dir| dir.count())
        .unwrap_or(0)
}

fn rss_bytes() -> u64 {
    let text = std::fs::read_to_string("/proc/self/statm").unwrap_or_default();
    text.split_whitespace()
        .nth(1)
        .and_then(|field| field.parse::<u64>().ok())
        .unwrap_or(0)
        .saturating_mul(4096)
}

#[test]
fn ten_thousand_connect_cycles_do_not_leak_fds() {
    let path = std::env::temp_dir().join(format!(
        "zeus-haru-stress-{}-{}.sock",
        std::process::id(),
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    let before = fd_count();
    for _ in 0..10_000 {
        let listener = bind_socket(&path).unwrap();
        let path_for_client = path.clone();
        let server = std::thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            let mut buf = [0u8; 64];
            let _ = stream.read(&mut buf);
            let _ = stream.write_all(&[0x31, 0, 0, 0, 0]);
        });
        let mut client = UnixStream::connect(&path_for_client).unwrap();
        client.write_all(&[0x21, 2, 0, 0, 0, b'{', b'}']).unwrap();
        let mut ack = [0u8; 5];
        client.read_exact(&mut ack).unwrap();
        drop(client);
        server.join().unwrap();
    }
    let _ = std::fs::remove_file(&path);
    let after = fd_count();
    assert!(
        after <= before + 2,
        "fd count grew from {before} to {after}"
    );
}

#[test]
fn thirty_minute_synthetic_soak_stays_flat() {
    let frames = 30 * 60 * 1_000 / 133;
    let mut engine = Engine::new(
        FakeBackend::new(vec![ScriptStep::Frame {
            fill: 0.0,
            text: String::new(),
            delay_ms: 0,
            step_ms: 1.0,
        }]),
        SpyLauncher::default(),
        vec!["fake-haru".into()],
        true,
    );
    engine.enter_streaming_without_spawn().unwrap();
    let silence = vec![0.0; FRAME_SAMPLES];
    let fds_before = fd_count();
    let rss_before = rss_bytes();
    for seq in 0..frames {
        engine
            .push(&silence, u32::try_from(seq).unwrap_or(u32::MAX))
            .unwrap();
    }
    let fds_after = fd_count();
    let rss_after = rss_bytes();
    assert_eq!(fds_before, fds_after, "soak leaked a file descriptor");
    assert!(
        rss_after <= rss_before.saturating_add(8 * 1024 * 1024),
        "rss grew from {rss_before} to {rss_after} over {frames} frames"
    );
    assert_eq!(engine.spawn_count(), 0);
}
