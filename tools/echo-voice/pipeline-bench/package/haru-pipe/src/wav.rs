//! Minimal RIFF/WAVE reader (PCM 16/24/32, float32, WAVE_FORMAT_EXTENSIBLE) and PCM_16 writer.
use std::io::{self, Write};
use std::path::Path;

#[derive(Debug, Clone)]
pub struct Wav { pub rate: u32, pub channels: usize, pub samples: Vec<f32> /* interleaved */ }

fn bad(msg: &str) -> io::Error { io::Error::new(io::ErrorKind::InvalidData, msg.to_string()) }
fn u16le(b: &[u8], o: usize) -> u16 { u16::from_le_bytes([b[o], b[o + 1]]) }
fn u32le(b: &[u8], o: usize) -> u32 { u32::from_le_bytes([b[o], b[o + 1], b[o + 2], b[o + 3]]) }

pub fn decode(b: &[u8]) -> io::Result<Wav> {
    if b.len() < 12 || &b[0..4] != b"RIFF" || &b[8..12] != b"WAVE" { return Err(bad("not a RIFF/WAVE file")); }
    let (mut pos, mut fmt, mut data) = (12usize, None, None);
    while pos + 8 <= b.len() {
        let id = &b[pos..pos + 4];
        let size = u32le(b, pos + 4) as usize;
        let body = pos + 8;
        let end = (body + size).min(b.len());
        if id == b"fmt " { fmt = Some(&b[body..end]); }
        if id == b"data" { data = Some(&b[body..end]); }
        pos = body + size + (size & 1);
    }
    let f = fmt.ok_or_else(|| bad("missing fmt chunk"))?;
    let d = data.ok_or_else(|| bad("missing data chunk"))?;
    if f.len() < 16 { return Err(bad("short fmt chunk")); }
    let mut tag = u16le(f, 0);
    let channels = u16le(f, 2) as usize;
    let rate = u32le(f, 4);
    let bits = u16le(f, 14);
    if tag == 0xFFFE && f.len() >= 26 { tag = u16le(f, 24); }
    if channels == 0 { return Err(bad("zero channels")); }
    let samples: Vec<f32> = match (tag, bits) {
        (1, 16) => d.chunks_exact(2).map(|c| i16::from_le_bytes([c[0], c[1]]) as f32 * (1.0 / 32768.0)).collect(),
        (1, 24) => d.chunks_exact(3).map(|c| ((i32::from_le_bytes([0, c[0], c[1], c[2]]) >> 8) as f32) * (1.0 / 8_388_608.0)).collect(),
        (1, 32) => d.chunks_exact(4).map(|c| (i32::from_le_bytes([c[0], c[1], c[2], c[3]]) as f64 / 2_147_483_648.0) as f32).collect(),
        (3, 32) => d.chunks_exact(4).map(|c| f32::from_le_bytes([c[0], c[1], c[2], c[3]])).collect(),
        _ => return Err(bad(&format!("unsupported WAV format tag {tag} / {bits} bits"))),
    };
    Ok(Wav { rate, channels, samples })
}

pub fn read(path: impl AsRef<Path>) -> io::Result<Wav> { decode(&std::fs::read(path)?) }

/// Encode interleaved f32 as a 16-bit PCM WAV (44-byte header, like libsndfile's).
pub fn encode_pcm16(rate: u32, channels: usize, interleaved: &[f32]) -> Vec<u8> {
    let data_len = interleaved.len() * 2;
    let mut out = Vec::with_capacity(44 + data_len);
    let block = (channels * 2) as u16;
    out.extend_from_slice(b"RIFF");
    out.extend_from_slice(&((36 + data_len) as u32).to_le_bytes());
    out.extend_from_slice(b"WAVEfmt ");
    out.extend_from_slice(&16u32.to_le_bytes());
    out.extend_from_slice(&1u16.to_le_bytes());
    out.extend_from_slice(&(channels as u16).to_le_bytes());
    out.extend_from_slice(&rate.to_le_bytes());
    out.extend_from_slice(&(rate * block as u32).to_le_bytes());
    out.extend_from_slice(&block.to_le_bytes());
    out.extend_from_slice(&16u16.to_le_bytes());
    out.extend_from_slice(b"data");
    out.extend_from_slice(&(data_len as u32).to_le_bytes());
    let mut pcm = vec![0i16; interleaved.len()];
    crate::convert::f32_to_i16_into(interleaved, &mut pcm);
    out.reserve(data_len);
    for v in pcm { out.extend_from_slice(&v.to_le_bytes()); }
    out
}

/// Encode interleaved f32 as an IEEE-float WAV (lossless hand-off to Python).
pub fn encode_f32(rate: u32, channels: usize, interleaved: &[f32]) -> Vec<u8> {
    let data_len = interleaved.len() * 4;
    let block = (channels * 4) as u16;
    let mut out = Vec::with_capacity(44 + data_len);
    out.extend_from_slice(b"RIFF");
    out.extend_from_slice(&((36 + data_len) as u32).to_le_bytes());
    out.extend_from_slice(b"WAVEfmt ");
    out.extend_from_slice(&16u32.to_le_bytes());
    out.extend_from_slice(&3u16.to_le_bytes());
    out.extend_from_slice(&(channels as u16).to_le_bytes());
    out.extend_from_slice(&rate.to_le_bytes());
    out.extend_from_slice(&(rate * block as u32).to_le_bytes());
    out.extend_from_slice(&block.to_le_bytes());
    out.extend_from_slice(&32u16.to_le_bytes());
    out.extend_from_slice(b"data");
    out.extend_from_slice(&(data_len as u32).to_le_bytes());
    for v in interleaved { out.extend_from_slice(&v.to_le_bytes()); }
    out
}

pub fn write_pcm16(path: impl AsRef<Path>, rate: u32, channels: usize, interleaved: &[f32]) -> io::Result<()> {
    let mut f = std::fs::File::create(path)?;
    f.write_all(&encode_pcm16(rate, channels, interleaved))
}

/// `haru_mlx.audio.load_audio`: any WAV -> mono f32 at 24 kHz.
pub fn load_audio(path: impl AsRef<Path>) -> io::Result<Vec<f32>> {
    let w = read(path)?;
    let mono = crate::convert::to_mono(&w.samples, w.channels);
    Ok(crate::resample::to_24k(&mono, w.rate))
}
