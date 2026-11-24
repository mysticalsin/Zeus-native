//! Synthetic half-hour in its own process so the fd count is not shared
//! with the connect-churn test.

use haru_companion::backend::{FakeBackend, ScriptStep};
use haru_companion::engine::Engine;
use haru_companion::session::FRAME_SAMPLES;
use haru_companion::supervisor::SpyLauncher;

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
