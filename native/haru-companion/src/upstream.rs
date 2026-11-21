//! Client codec for `haru_mlx.native` (48 kHz). Zeus stays at 24 kHz.
//! Rate conversion is `haru_pipe::downsample_2x` / `upsample_2x`.

use haru_pipe::native::{downsample_2x_into, upsample_2x_into};

pub const AUDIO: u8 = 0x01;
pub const START: u8 = 0x02;
pub const PREPARE: u8 = 0x03;
pub const HELLO: u8 = 0x10;
pub const FRAME: u8 = 0x11;
pub const TEXT: u8 = 0x12;
pub const ASSETS: u8 = 0x13;
pub const ERROR: u8 = 0x14;
pub const READY: u8 = 0x15;

#[derive(Clone, Debug, PartialEq)]
pub struct StartRequest {
    pub language: String,
    pub system_prompt: String,
    pub speak_first: bool,
}

pub fn downsample_48k(pcm48: &[f32]) -> Vec<f32>  {
    todo!("red");
}

pub fn upsample_24k(pcm24: &[f32]) -> Vec<f32>  {
    todo!("red");
}

pub fn frame(kind: u8, payload: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(5 + payload.len());
    out.push(kind);
    let len = u32::try_from(payload.len()).unwrap_or(u32::MAX);
    out.extend_from_slice(&len.to_le_bytes());
    out.extend_from_slice(payload);
    out
}

/// START for the Python child. v1 never sends `reference_path`.
pub fn encode_start(request: &StartRequest) -> Vec<u8>  {
    todo!("red");
}

pub fn encode_audio(pcm48: &[f32]) -> Vec<u8> {
    let mut payload = Vec::with_capacity(pcm48.len() * 4);
    for sample in pcm48 {
        payload.extend_from_slice(&sample.to_le_bytes());
    }
    frame(AUDIO, &payload)
}

pub fn encode_upstream_push(pcm24: &[f32]) -> Vec<u8> {
    encode_audio(&upsample_24k(pcm24))
}

#[derive(Clone, Debug, PartialEq)]
pub enum UpstreamMessage {
    Assets(String),
    Hello(String),
    Frame {
        index: u32,
        step_ms: f32,
        pcm48: Vec<f32>,
    },
    Text(String),
    Error(String),
    Ready(String),
    Other {
        kind: u8,
        payload: Vec<u8>,
    },
}

pub fn decode_upstream(kind: u8, payload: &[u8]) -> UpstreamMessage {
    match kind {
        ASSETS => UpstreamMessage::Assets(lossy(payload)),
        HELLO => UpstreamMessage::Hello(lossy(payload)),
        FRAME => decode_frame(payload),
        TEXT => UpstreamMessage::Text(lossy(payload)),
        ERROR => UpstreamMessage::Error(lossy(payload)),
        READY => UpstreamMessage::Ready(lossy(payload)),
        AUDIO | START | PREPARE => UpstreamMessage::Other {
            kind,
            payload: payload.to_vec(),
        },
        other => UpstreamMessage::Other {
            kind: other,
            payload: payload.to_vec(),
        },
    }
}

fn decode_frame(payload: &[u8]) -> UpstreamMessage {
    if payload.len() < 8 || (payload.len() - 8) % 4 != 0 {
        return UpstreamMessage::Error("short frame".to_string());
    }
    let index = u32::from_le_bytes([payload[0], payload[1], payload[2], payload[3]]);
    let step_ms = f32::from_le_bytes([payload[4], payload[5], payload[6], payload[7]]);
    let pcm48 = payload[8..]
        .chunks_exact(4)
        .map(|chunk| f32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]))
        .collect();
    UpstreamMessage::Frame {
        index,
        step_ms,
        pcm48,
    }
}

fn lossy(payload: &[u8]) -> String {
    String::from_utf8_lossy(payload).into_owned()
}

/// 24 kHz model frame recovered from an upstream 48 kHz FRAME.
pub fn model_frame_from_upstream(message: &UpstreamMessage) -> Option<Vec<f32>>  {
    todo!("red");
}
