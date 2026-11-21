//! Red-first invariants (written before the implementation; see RED.log).
use haru_pipe::convert::{f32_to_i16, i16_to_f32};
use haru_pipe::frame::{Frame, FrameError, Framer, FRAME_SAMPLES};
use haru_pipe::resample::{resample_poly, to_24k};

#[test]
fn frame_size_is_3200_and_enforced() {
    assert_eq!(FRAME_SAMPLES, 3200);
    assert!(Frame::try_from_slice(&vec![0.0; 3200]).is_ok());
    assert_eq!(Frame::try_from_slice(&vec![0.0; 3199]).unwrap_err(), FrameError::BadFrameSize { expected: 3200, got: 3199 });
    assert_eq!(Frame::try_from_slice(&vec![0.0; 3201]).unwrap_err(), FrameError::BadFrameSize { expected: 3200, got: 3201 });
}

#[test]
fn framer_emits_only_whole_frames_in_order() {
    let mut f = Framer::new();
    let x: Vec<f32> = (0..10_000).map(|i| i as f32).collect();
    let mut out = Vec::new();
    for chunk in x.chunks(777) { f.push(chunk); while let Some(fr) = f.pop() { out.push(fr); } }
    assert_eq!(out.len(), 3);
    assert_eq!(f.pending(), 10_000 - 3 * 3200);
    assert_eq!(out[1].as_slice()[0], 3200.0);
    assert!(out.iter().all(|fr| fr.as_slice().len() == 3200));
}

#[test]
fn resampler_output_length_matches_scipy_rule() {
    // scipy.signal.resample_poly: n_out = ceil(n_in * up / down)
    for &(rate, n) in &[(16_000u32, 16_001usize), (44_100, 44_101), (48_000, 48_001), (24_000, 1234)] {
        let x = vec![0.1f32; n];
        let y = to_24k(&x, rate).unwrap();
        let (up, down) = { let g = gcd(24_000, rate as u64); (24_000 / g, rate as u64 / g) };
        assert_eq!(y.len() as u64, (n as u64 * up + down - 1) / down, "rate {rate}");
    }
}

#[test]
fn resampler_preserves_dc_and_inband_energy() {
    let dc = vec![0.25f32; 48_000];
    let y = resample_poly(&dc, 1, 2).unwrap();
    let mid = &y[1000..y.len() - 1000];
    assert!(mid.iter().all(|v| (v - 0.25).abs() < 1e-3), "DC gain must be 1");
    // 1 kHz tone at 16 kHz -> 24 kHz keeps its RMS within 0.1 dB
    let tone: Vec<f32> = (0..32_000).map(|i| (2.0 * std::f32::consts::PI * 1000.0 * i as f32 / 16_000.0).sin() * 0.5).collect();
    let y = to_24k(&tone, 16_000).unwrap();
    let rms = |v: &[f32]| (v.iter().map(|x| (*x as f64).powi(2)).sum::<f64>() / v.len() as f64).sqrt();
    let db = 20.0 * (rms(&y[2000..y.len() - 2000]) / rms(&tone[2000..tone.len() - 2000])).log10();
    assert!(db.abs() < 0.1, "in-band gain {db} dB");
    // an 11 kHz tone at 48 kHz is above the 12 kHz Nyquist? no: 11k < 12k passes; 20 kHz must be removed
    let hf: Vec<f32> = (0..48_000).map(|i| (2.0 * std::f32::consts::PI * 20_000.0 * i as f32 / 48_000.0).sin() * 0.5).collect();
    let y = to_24k(&hf, 48_000).unwrap();
    let att = 20.0 * (rms(&y[2000..y.len() - 2000]) / 0.3535).log10();
    assert!(att < -40.0, "20 kHz must be attenuated by >40 dB, got {att}");
}

#[test]
fn int16_round_trip_is_lossless_and_clips() {
    let all: Vec<i16> = (i16::MIN..=i16::MAX).collect();
    let back = f32_to_i16(&i16_to_f32(&all));
    assert_eq!(all, back);
    assert_eq!(f32_to_i16(&[1.0, 1.5, -1.0, -2.0, 0.5, -0.3 / 32768.0]), vec![32767, 32767, -32768, -32768, 16384, -1]);
}

fn gcd(a: u64, b: u64) -> u64 { if b == 0 { a } else { gcd(b, a % b) } }
