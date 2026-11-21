//! Sweep regressions. These are not the original red-first invariants.
use haru_pipe::bench::stream_run;
use haru_pipe::native::Ingest;
use std::time::Duration;
use haru_pipe::resample::{resample_poly, BadRatio};
use haru_pipe::stats::summary_json;

#[test]
fn empty_summary_is_finite_json() {
    let s = summary_json(&[]);
    assert!(s.contains("\"n\": 0"), "{s}");
    let lower = s.to_ascii_lowercase();
    assert!(!lower.contains("nan"), "{s}");
    assert!(!lower.contains("inf"), "{s}");
}

/// EV-STAT-2: an empty summary is JSON, percentiles are null, mean is null or 0.
#[test]
fn empty_summary_percentiles_are_null() {
    let s = summary_json(&[]);
    for key in ["p50_ms", "p95_ms", "p99_ms"] {
        assert!(s.contains(&format!("\"{key}\": null")), "{s}");
    }
    assert!(s.contains("\"mean_ms\": null") || s.contains("\"mean_ms\": 0"), "{s}");
    assert!(!s.contains("-0"), "{s}");
}

/// EV-STREAM-1: a read split after 5 bytes must carry the trailing 1-3 bytes.
#[test]
fn five_byte_split_matches_single_read() {
    let raw: Vec<u8> = (0..64).map(|i| i as u8).collect();
    let mut whole = Ingest::new();
    whole.feed_bytes(&raw);
    let mut split = Ingest::new();
    split.feed_bytes(&raw[..5]);
    split.feed_bytes(&raw[5..]);
    assert_eq!(whole.pending(), split.pending(), "pending samples diverged");
}

/// EV-RS-1: up < 1 or down < 1 is an error, not an empty vec and not a panic.
#[test]
fn bad_resample_ratio_is_an_error() {
    for (up, down) in [(0u64, 2u64), (2, 0), (0, 0)] {
        match resample_poly(&[0.25, -0.5], up, down) {
            Err(BadRatio { up: u, down: d }) => assert_eq!((u, d), (up, down)),
            Ok(y) => panic!("up={up} down={down} returned {} samples", y.len()),
        }
    }
}

/// EV-MEM-1: a multi-minute stream must not retain every FRAME payload.
#[test]
fn stream_messages_stay_bounded() {
    // 16 frames at 48 kHz: 16 * 6400 samples. Unbounded storage is ~400 KB.
    let raw = vec![0u8; 16 * 6_400 * 4];
    let (st, _) = stream_run(&raw, 0, Duration::ZERO, || {});
    assert!(st.index > 10, "produced only {} frames", st.index);
    assert!(st.msgs.len() <= 32 * 1024, "msgs grew to {} bytes", st.msgs.len());
}
