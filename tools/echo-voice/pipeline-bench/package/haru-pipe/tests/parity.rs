//! Golden fixtures produced by scipy 1.18.1 `resample_poly` (tests/fixtures/*.f32, see README).
use haru_pipe::native::{downsample_2x_into, encode_frame_msg, upsample_2x_into, Ingest};
use haru_pipe::frame::{Frame, FRAME_SAMPLES};
use haru_pipe::ring::Ring;
use haru_pipe::resample::to_24k;
use haru_pipe::wav;

fn f32s(path: &str) -> Vec<f32> {
    std::fs::read(path).unwrap().chunks_exact(4).map(|c| f32::from_le_bytes([c[0], c[1], c[2], c[3]])).collect()
}

#[test]
fn resample_matches_scipy_fixtures() {
    for rate in [16_000u32, 44_100, 48_000] {
        let x = f32s(&format!("tests/fixtures/in_{rate}.f32"));
        let want = f32s(&format!("tests/fixtures/scipy_{rate}_to_24k.f32"));
        let got = to_24k(&x, rate);
        assert_eq!(got.len(), want.len(), "rate {rate}");
        let max = got.iter().zip(&want).map(|(a, b)| (a - b).abs()).fold(0f32, f32::max);
        assert!(max < 2e-6, "rate {rate}: max |diff| {max}");
    }
}

#[test]
fn native_resampling_matches_numpy_semantics() {
    let mut half = Vec::new();
    downsample_2x_into(&[1.0, 3.0, -1.0, 0.0], &mut half);
    assert_eq!(half, vec![2.0, -0.5]);
    let mut up = vec![0.0; 6];
    upsample_2x_into(&[0.0, 1.0, 3.0], &mut up);
    assert_eq!(up, vec![0.0, 0.5, 1.0, 2.0, 3.0, 3.0]);
}

#[test]
fn ingest_keeps_odd_leftover_and_frames_at_3200() {
    let mut ing = Ingest::new();
    let one = 1.0f32.to_le_bytes();
    let bytes: Vec<u8> = (0..(2 * FRAME_SAMPLES + 1)).flat_map(|_| one).collect();
    ing.feed_bytes(&bytes); // 6401 samples at 48 kHz: 3200 at 24 kHz + 1 leftover
    let mut f = Frame::silence();
    assert!(ing.pop_into(&mut f));
    assert!(!ing.pop_into(&mut f));
    ing.feed_bytes(&one); // the leftover pairs with this sample
    assert_eq!(ing.pending(), 1);
}

#[test]
fn frame_message_layout_matches_haru_mlx_native() {
    let mut out = Vec::new();
    encode_frame_msg(7, 1.5, &[0.25, -0.5], &mut out);
    let mut want = vec![0x11u8];
    want.extend_from_slice(&16u32.to_le_bytes()); // payload: u32 + f32 + 2 * f32
    want.extend_from_slice(&7u32.to_le_bytes());
    want.extend_from_slice(&1.5f32.to_le_bytes());
    want.extend_from_slice(&0.25f32.to_le_bytes());
    want.extend_from_slice(&(-0.5f32).to_le_bytes());
    assert_eq!(out, want);
}

#[test]
fn ring_wraps_around() {
    let mut r = Ring::new(5);
    r.push(&[1.0, 2.0, 3.0]).unwrap();
    let mut o = [0.0; 2];
    r.pop_into(&mut o).unwrap();
    r.push(&[4.0, 5.0, 6.0, 7.0]).unwrap();
    assert!(r.push(&[8.0]).is_err());
    let mut all = [0.0; 5];
    r.pop_into(&mut all).unwrap();
    assert_eq!(all, [3.0, 4.0, 5.0, 6.0, 7.0]);
}

#[test]
fn wav_pcm16_round_trip() {
    let x: Vec<f32> = (-100..100).map(|i| i as f32 / 128.0).collect();
    let w = wav::decode(&wav::encode_pcm16(24_000, 2, &x)).unwrap();
    assert_eq!((w.rate, w.channels), (24_000, 2));
    assert_eq!(w.samples, x);
}
