//! Sweep regressions. These are not the original red-first invariants.
use haru_pipe::bench::{stream_run, Stream};
use haru_pipe::native::Ingest;
use std::time::Duration;
use haru_pipe::resample::{resample_poly, BadRatio};
use haru_pipe::rng::XorShift32;
use haru_pipe::stats::{percentile, summary_json};

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

fn wav_pcm(rate: u32, ch: u16, bits: u16, payload: &[u8]) -> Vec<u8> {
    let mut fmt = vec![0u8; 16];
    fmt[0..2].copy_from_slice(&1u16.to_le_bytes());
    fmt[2..4].copy_from_slice(&ch.to_le_bytes());
    fmt[4..8].copy_from_slice(&rate.to_le_bytes());
    let block = ch.saturating_mul(bits / 8);
    fmt[8..12].copy_from_slice(&(rate.saturating_mul(block as u32)).to_le_bytes());
    fmt[12..14].copy_from_slice(&block.to_le_bytes());
    fmt[14..16].copy_from_slice(&bits.to_le_bytes());
    let chunk = |id: &[u8; 4], body: &[u8]| {
        let mut c = id.to_vec();
        c.extend_from_slice(&(body.len() as u32).to_le_bytes());
        c.extend_from_slice(body);
        if body.len() % 2 == 1 { c.push(0); }
        c
    };
    let mut body = chunk(b"fmt ", &fmt);
    body.extend(chunk(b"data", payload));
    let mut out = b"RIFF".to_vec();
    out.extend_from_slice(&((4 + body.len()) as u32).to_le_bytes());
    out.extend_from_slice(b"WAVE");
    out.extend(body);
    out
}

#[test]
fn seeded_chunkings_match_one_read() {
    let mut raw = vec![0u8; 6_400 * 4];
    for (i, b) in raw.iter_mut().enumerate() { *b = (i * 3) as u8; }
    let mut one = Stream::new(Duration::ZERO, 0);
    one.feed(&raw, || {});
    let mut split = Stream::new(Duration::ZERO, 0);
    let mut state = 0x1234_5678u32;
    let mut i = 0;
    while i < raw.len() {
        state = state.wrapping_mul(1_664_525).wrapping_add(1_013_904_223);
        let n = 1 + (state as usize % 17);
        let end = (i + n).min(raw.len());
        split.feed(&raw[i..end], || {});
        i = end;
    }
    assert_eq!(one.index, split.index);
    assert_eq!(one.msgs, split.msgs);
}

#[test]
fn eof_mid_frame_emits_no_frame() {
    let raw = vec![1u8; 100];
    let mut st = Stream::new(Duration::ZERO, 0);
    let mut n = 0;
    st.feed(&raw, || n += 1);
    assert_eq!(n, 0);
    assert_eq!(st.index, 1);
}

#[test]
fn xorshift_chunks_match_the_shared_sequence() {
    let mut r = XorShift32::new();
    for expect in [1575usize, 1505, 999, 908, 752, 1875, 851, 404] {
        assert_eq!(r.chunk_samples(), expect);
    }
}

#[test]
fn percentile_matches_numpy_linear() {
    // numpy.percentile(..., method="linear") on these arrays.
    let a = [1.0, 2.0, 3.0, 4.0, 10.0];
    assert!((percentile(&a, 50.0) - 3.0).abs() < 1e-9);
    assert!((percentile(&a, 95.0) - 8.8).abs() < 1e-9);
    assert!((percentile(&[1.0, 1.0, 1.0], 95.0) - 1.0).abs() < 1e-9);
    assert!((percentile(&[1.0, 4.0], 95.0) - 3.85).abs() < 1e-9);
    assert!((percentile(&[1.0], 50.0) - 1.0).abs() < 1e-9);
}

#[test]
fn large_read_keeps_a_bounded_input_ring() {
    let raw = vec![0u8; 9 * 6_400 * 4];
    let mut st = Stream::new(Duration::ZERO, 0);
    st.feed(&raw, || {});
    assert_eq!(st.index, 10, "nine frames from a cold index of 1");
    assert!(st.input_capacity() <= 8 * 3_200, "ring grew to {}", st.input_capacity());
}

#[test]
fn wav_rejects_zero_rate() {
    let err = haru_pipe::wav::decode(&wav_pcm(0, 1, 16, &[0, 0]));
    assert!(err.is_err(), "rate 0 decoded: {err:?}");
}
