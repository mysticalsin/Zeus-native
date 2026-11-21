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
        out[2 * i + 1] = if i + 1 < n { (x[i] + x[i + 1]) * 0.5 } else { x[i] };
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
    for v in pcm48 { out.extend_from_slice(&v.to_le_bytes()); }
}

/// Server-side ingest of client AUDIO payloads into 24 kHz model frames.
pub struct Ingest {
    leftover: Option<f32>,
    /// 0–3 bytes that did not complete a little-endian f32. Carried to the next read.
    byte_carry: Vec<u8>,
    scratch: Vec<f32>,
    half: Vec<f32>,
    /// Samples waiting for a free slot in `framer`. Keeps a large read from growing the ring.
    staged: Vec<f32>,
    framer: Framer,
}

impl Default for Ingest { fn default() -> Self { Self::new() } }

impl Ingest {
    pub fn new() -> Self {
        Ingest { leftover: None, byte_carry: Vec::new(), scratch: Vec::new(), half: Vec::new(), staged: Vec::new(), framer: Framer::new() }
    }
    /// Feed raw little-endian f32 bytes. A trailing 1–3 bytes is kept for the next call.
    pub fn feed_bytes(&mut self, payload: &[u8]) {
        let mut bytes = std::mem::take(&mut self.byte_carry);
        bytes.extend_from_slice(payload);
        let n = bytes.len() - bytes.len() % 4;
        self.byte_carry = bytes[n..].to_vec();
        self.scratch.clear();
        if let Some(l) = self.leftover.take() { self.scratch.push(l); }
        self.scratch.extend(bytes[..n].chunks_exact(4).map(|c| f32::from_le_bytes([c[0], c[1], c[2], c[3]])));
        let even = self.scratch.len() / 2 * 2;
        if even < self.scratch.len() { self.leftover = Some(self.scratch[even]); }
        downsample_2x_into(&self.scratch[..even], &mut self.half);
        if !self.half.is_empty() { self.staged.extend_from_slice(&self.half); }
        self.fill();
    }
    fn fill(&mut self) {
        while !self.staged.is_empty() {
            let free = self.framer.free();
            if free == 0 { break; }
            let n = free.min(self.staged.len());
            self.framer.push_fit(&self.staged[..n]);
            self.staged.drain(..n);
        }
    }
    pub fn pop_into(&mut self, f: &mut Frame) -> bool {
        self.fill();
        let ok = self.framer.pop_into(f);
        self.fill();
        ok
    }
    pub fn pending(&self) -> usize { self.framer.pending() + self.staged.len() }
    pub fn capacity(&self) -> usize { self.framer.capacity() }
}

pub const FRAME_SAMPLES_48K: usize = 2 * FRAME_SAMPLES;
