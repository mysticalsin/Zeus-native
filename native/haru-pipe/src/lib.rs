//! `haru-pipe`: the host-side (non-model) audio pipeline of Haru-4B, in Rust.
//!
//! Mirrors haru-speech-mlx 0.1.0 exactly where it matters for parity:
//! * [`wav`] + [`convert`]: libsndfile semantics (int16 -> f32 divides by 32768,
//!   f32 -> int16 is `floor(x * 32768)` clipped, as measured on libsndfile 1.2.2).
//! * [`resample`]: `scipy.signal.resample_poly` (Kaiser beta 5, half_len 10 * max(up, down)),
//!   what `haru_mlx.audio.decode_audio` uses for any non-24 kHz input.
//! * [`frame`]: 3200-sample (133 ms) frames, size enforced by type.
//! * [`native`]: `haru_mlx.native` socket path (48 kHz client <-> 24 kHz model, FRAME messages).
//! * [`ring`]: fixed-capacity ring buffers for the input framer and the playback jitter buffer.
pub mod bench;
pub mod convert;
pub mod frame;
pub mod native;
pub mod resample;
pub mod ring;
pub mod rng;
pub mod stats;
pub mod wav;

pub const SAMPLE_RATE: u32 = 24_000;
