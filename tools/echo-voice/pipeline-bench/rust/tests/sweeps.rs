//! Sweep regressions. These are not the original red-first invariants.
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
