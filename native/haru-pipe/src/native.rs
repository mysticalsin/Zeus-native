//! The `haru-mlx-native` socket audio path: the client sends 48 kHz f32 of any length,
//! the server downsamples by pairwise means, frames at 3200, and answers each user frame
//! with a FRAME message of 48 kHz f32 (linear-interpolated 2x upsample).
use crate::frame::{Frame, Framer, FRAME_SAMPLES};

pub const CLIENT_SAMPLE_RATE: u32 = 48_000;
pub const MSG_AUDIO: u8 = 0x01;
pub const MSG_FRAME: u8 = 0x11;
pub const MSG_TEXT: u8 = 0x12;

/// `downsample_2x`: pcm.reshape(-1, 2).mean(axis=1). Odd tail is the caller's leftover.
pub fn downsample_2x_into(x: &[f32], out: &mut Vec<f32>) {
    out.clear();
    out.extend(x.chunks_exact(2).map(|c| (c[0] + c[1]) / 2.0));
}

/// `upsample_2x`: even = x, odd = (x[i] + x[i+1]) * 0.5, last odd = x[-1].
pub fn upsample_2x_into(x: &[f32], out: &mut [f32]) {
    let n = x.len();
    assert_eq!(out.len(), 2 * n);
    for i in 0..n {
        out[2 * i] = x[i];
        out[2 * i + 1] = if i + 1 < n {
            (x[i] + x[i + 1]) * 0.5
        } else {
            x[i]
        };
    }
}

/// One FRAME message: `<BI` header, `<If` (index, step ms), then f32 LE PCM.
pub fn encode_frame_msg(index: u32, step_ms: f32, pcm48: &[f32], out: &mut Vec<u8>) {
    let payload = 8 + 4 * pcm48.len();
    out.reserve(5 + payload);
    out.push(MSG_FRAME);
    out.extend_from_slice(&(payload as u32).to_le_bytes());
    out.extend_from_slice(&index.to_le_bytes());
    out.extend_from_slice(&step_ms.to_le_bytes());
    for v in pcm48 {
        out.extend_from_slice(&v.to_le_bytes());
    }
}

/// Server-side ingest of client AUDIO payloads into 24 kHz model frames.
pub struct Ingest {
    leftover: Option<f32>,
    scratch: Vec<f32>,
    half: Vec<f32>,
    framer: Framer,
}

impl Default for Ingest {
    fn default() -> Self {
        Self::new()
    }
}

impl Ingest {
    pub fn new() -> Self {
        Ingest {
            leftover: None,
            scratch: Vec::new(),
            half: Vec::new(),
            framer: Framer::new(),
        }
    }
    /// Feed raw little-endian f32 bytes (any length that is a multiple of 4).
    pub fn feed_bytes(&mut self, payload: &[u8]) {
        self.scratch.clear();
        if let Some(l) = self.leftover.take() {
            self.scratch.push(l);
        }
        self.scratch.extend(
            payload
                .chunks_exact(4)
                .map(|c| f32::from_le_bytes([c[0], c[1], c[2], c[3]])),
        );
        let even = self.scratch.len() / 2 * 2;
        if even < self.scratch.len() {
            self.leftover = Some(self.scratch[even]);
        }
        downsample_2x_into(&self.scratch[..even], &mut self.half);
        if !self.half.is_empty() {
            self.framer.push(&self.half);
        }
    }
    pub fn pop_into(&mut self, f: &mut Frame) -> bool {
        self.framer.pop_into(f)
    }
    pub fn pending(&self) -> usize {
        self.framer.pending()
    }
}

pub const FRAME_SAMPLES_48K: usize = 2 * FRAME_SAMPLES;
