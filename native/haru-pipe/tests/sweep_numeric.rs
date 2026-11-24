//! Edge inputs must return an error instead of panicking or hanging.

use haru_pipe::native::Ingest;
use haru_pipe::resample::{firwin_kaiser, to_24k};
use haru_pipe::stats;
use haru_pipe::wav;
use std::time::Duration;

#[test]
fn a_huge_wav_chunk_does_not_panic() {
    let mut bytes = Vec::new();
    bytes.extend_from_slice(b"RIFF");
    bytes.extend_from_slice(&100u32.to_le_bytes());
    bytes.extend_from_slice(b"WAVE");
    bytes.extend_from_slice(b"fmt ");
    bytes.extend_from_slice(&u32::MAX.to_le_bytes());
    bytes.extend_from_slice(&[0u8; 8]);
    let decoded = std::panic::catch_unwind(|| wav::decode(&bytes));
    assert!(decoded.is_ok(), "malformed chunk size panicked");
    assert!(decoded.unwrap().is_err());
}

#[test]
fn a_zero_sample_rate_does_not_panic() {
    let decoded = std::panic::catch_unwind(|| to_24k(&[0.25, -0.25, 0.5, -0.5], 0));
    assert!(decoded.is_ok(), "rate 0 panicked");
    assert!(decoded.unwrap().is_empty());
}

#[test]
fn ingest_keeps_a_partial_sample_across_reads() {
    let mut raw = Vec::new();
    raw.extend_from_slice(&1.0f32.to_le_bytes());
    raw.extend_from_slice(&3.0f32.to_le_bytes());
    let mut ingest = Ingest::new();
    ingest.feed_bytes(&raw[..2]);
    ingest.feed_bytes(&raw[2..]);
    assert_eq!(ingest.pending(), 1);
}

#[test]
fn a_huge_kaiser_beta_returns_finite_taps() {
    let (tx, rx) = std::sync::mpsc::channel();
    std::thread::spawn(move || {
        let taps = firwin_kaiser(5, 0.4, 800.0);
        let finite = taps.iter().all(|tap| tap.is_finite());
        let sum: f64 = taps.iter().sum();
        let _ = tx.send(finite && sum.is_finite() && sum > 0.0);
    });
    let got = rx.recv_timeout(Duration::from_secs(2));
    assert!(got.is_ok(), "kaiser design did not return");
    assert!(got.unwrap());
}

#[test]
fn percentile_outside_0_to_100_does_not_panic() {
    let value = std::panic::catch_unwind(|| stats::percentile(&[1.0, 2.0, 3.0, 4.0], 10_000.0));
    assert!(value.is_ok(), "percentile panicked");
    assert!(value.unwrap().is_finite());
}
