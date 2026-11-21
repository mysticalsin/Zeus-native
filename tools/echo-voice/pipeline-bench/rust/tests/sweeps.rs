//! Sweep regressions. These are not the original red-first invariants.
use haru_pipe::native::Ingest;
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
