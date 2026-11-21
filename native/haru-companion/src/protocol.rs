//! Zeus-facing wire format, version 1.
//!
//! Each message is `u8 type | u32 LE length | payload`. Audio frames are
//! 24 kHz mono, 3200 samples. There is no `reference_path` in v1.

use crate::session::{SessionError, FRAME_SAMPLES, SAMPLE_RATE};

pub const HELLO: u8 = 0x21;
pub const START: u8 = 0x22;
pub const PUSH: u8 = 0x23;
pub const CLOSE: u8 = 0x24;
pub const HELLO_ACK: u8 = 0x31;
pub const STATE: u8 = 0x32;
pub const FRAME: u8 = 0x33;
pub const TEXT: u8 = 0x34;
pub const ERROR: u8 = 0x35;

#[derive(Clone, Debug, PartialEq)]
pub enum ClientMessage {
    Hello {
        v: u32,
    },
    Start {
        language: String,
        system_prompt: String,
        speak_first: bool,
    },
    Push {
        seq: u32,
        samples: Vec<f32>,
    },
    Close,
}

#[derive(Clone, Debug, PartialEq)]
pub enum ServerMessage {
    HelloAck {
        v: u32,
        sample_rate: u32,
        frame_samples: u32,
    },
    State {
        session: String,
        child: String,
        watchdog: String,
    },
    Frame {
        seq: u32,
        step_ms: f32,
        samples: Vec<f32>,
    },
    Text {
        text: String,
    },
    Error {
        code: String,
        message: String,
        expected: Option<u32>,
        got: Option<u32>,
    },
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ProtocolError {
    BadFrameSize { expected: usize, got: usize },
    ReferenceNotAllowed,
    Truncated,
    UnknownType(u8),
    BadJson,
    BadLanguage,
    Oversized,
}

impl ProtocolError {
    pub fn code(&self) -> &'static str {
        match self {
            ProtocolError::BadFrameSize { .. } => "bad_frame_size",
            ProtocolError::ReferenceNotAllowed => "reference_not_allowed",
            ProtocolError::Truncated => "truncated",
            ProtocolError::UnknownType(_) => "unknown_type",
            ProtocolError::BadJson => "bad_json",
            ProtocolError::BadLanguage => "bad_language",
            ProtocolError::Oversized => "oversized",
        }
    }
}

pub fn frame(kind: u8, payload: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(5 + payload.len());
    out.push(kind);
    let len = u32::try_from(payload.len()).unwrap_or(u32::MAX);
    out.extend_from_slice(&len.to_le_bytes());
    out.extend_from_slice(payload);
    out
}

impl ClientMessage {
    pub fn encode(&self) -> Result<Vec<u8>, ProtocolError> {
        match self {
            ClientMessage::Hello { v } => Ok(frame(HELLO, format!("{{\"v\":{v}}}").as_bytes())),
            ClientMessage::Start {
                language,
                system_prompt,
                speak_first,
            } => {
                if language != "en" && language != "fr" {
                    return Err(ProtocolError::BadLanguage);
                }
                let payload = format!(
                    "{{\"language\":{},\"system_prompt\":{},\"speak_first\":{}}}",
                    json_string(language),
                    json_string(system_prompt),
                    if *speak_first { "true" } else { "false" }
                );
                Ok(frame(START, payload.as_bytes()))
            }
            ClientMessage::Push { seq, samples } => encode_push(*seq, samples),
            ClientMessage::Close => Ok(frame(CLOSE, b"")),
        }
    }
}

pub fn encode_push(seq: u32, samples: &[f32]) -> Result<Vec<u8>, ProtocolError> {
    if samples.len() != FRAME_SAMPLES {
        return Err(ProtocolError::BadFrameSize {
            expected: FRAME_SAMPLES,
            got: samples.len(),
        });
    }
    let mut payload = Vec::with_capacity(4 + samples.len() * 4);
    payload.extend_from_slice(&seq.to_le_bytes());
    for sample in samples {
        payload.extend_from_slice(&sample.to_le_bytes());
    }
    Ok(frame(PUSH, &payload))
}

impl ServerMessage {
    pub fn encode(&self) -> Vec<u8> {
        match self {
            ServerMessage::HelloAck {
                v,
                sample_rate,
                frame_samples,
            } => frame(
                HELLO_ACK,
                format!(
                    "{{\"v\":{v},\"sample_rate\":{sample_rate},\"frame_samples\":{frame_samples}}}"
                )
                .as_bytes(),
            ),
            ServerMessage::State {
                session,
                child,
                watchdog,
            } => frame(
                STATE,
                format!(
                    "{{\"session\":{},\"child\":{},\"watchdog\":{}}}",
                    json_string(session),
                    json_string(child),
                    json_string(watchdog)
                )
                .as_bytes(),
            ),
            ServerMessage::Frame {
                seq,
                step_ms,
                samples,
            } => {
                let mut payload = Vec::with_capacity(8 + samples.len() * 4);
                payload.extend_from_slice(&seq.to_le_bytes());
                payload.extend_from_slice(&step_ms.to_le_bytes());
                for sample in samples {
                    payload.extend_from_slice(&sample.to_le_bytes());
                }
                frame(FRAME, &payload)
            }
            ServerMessage::Text { text } => frame(TEXT, text.as_bytes()),
            ServerMessage::Error {
                code,
                message,
                expected,
                got,
            } => {
                let mut payload = format!(
                    "{{\"code\":{},\"message\":{}",
                    json_string(code),
                    json_string(message)
                );
                if let Some(expected) = expected {
                    payload.push_str(&format!(",\"expected\":{expected}"));
                }
                if let Some(got) = got {
                    payload.push_str(&format!(",\"got\":{got}"));
                }
                payload.push('}');
                frame(ERROR, payload.as_bytes())
            }
        }
    }

    pub fn hello_ack() -> Self {
        ServerMessage::HelloAck {
            v: 1,
            sample_rate: SAMPLE_RATE,
            frame_samples: u32::try_from(FRAME_SAMPLES).unwrap_or(3200),
        }
    }
}

pub fn error_frame(error: &SessionError) -> Vec<u8> {
    let (expected, got) = match error {
        SessionError::BadFrameSize { expected, got } => (
            Some(u32::try_from(*expected).unwrap_or(0)),
            Some(u32::try_from(*got).unwrap_or(0)),
        ),
        SessionError::IllegalTransition { .. }
        | SessionError::ProcessExited { .. }
        | SessionError::SocketClosed
        | SessionError::StartTimeout
        | SessionError::WatchdogRestart { .. } => (None, None),
    };
    ServerMessage::Error {
        code: error.code().to_string(),
        message: error.message(),
        expected,
        got,
    }
    .encode()
}

pub fn protocol_error_frame(error: &ProtocolError) -> Vec<u8> {
    let (expected, got) = match error {
        ProtocolError::BadFrameSize { expected, got } => (
            Some(u32::try_from(*expected).unwrap_or(0)),
            Some(u32::try_from(*got).unwrap_or(0)),
        ),
        ProtocolError::UnknownType(kind) => (None, Some(u32::from(*kind))),
        ProtocolError::ReferenceNotAllowed
        | ProtocolError::Truncated
        | ProtocolError::BadJson
        | ProtocolError::BadLanguage
        | ProtocolError::Oversized => (None, None),
    };
    ServerMessage::Error {
        code: error.code().to_string(),
        message: error.code().to_string(),
        expected,
        got,
    }
    .encode()
}

#[derive(Clone, Debug, PartialEq)]
pub struct RawFrame {
    pub kind: u8,
    pub payload: Vec<u8>,
}

pub const MAX_FRAME_BYTES: usize = 8 * 1024 * 1024;

#[derive(Debug, Default)]
pub struct FrameBuf {
    buf: Vec<u8>,
    error: Option<ProtocolError>,
}

impl FrameBuf {
    /// Bytes already accepted. An oversized length is rejected without
    /// waiting for its payload, and the buffer is cleared so a later frame
    /// can be parsed. A valid frame that shared the buffer with that length
    /// is still returned.
    pub fn push(&mut self, bytes: &[u8]) -> Result<Vec<RawFrame>, ProtocolError> {
        if self.buf.len().saturating_add(bytes.len()) > MAX_FRAME_BYTES.saturating_add(5) {
            self.buf.clear();
            return Err(ProtocolError::Oversized);
        }
        self.buf.extend_from_slice(bytes);
        let mut out = Vec::new();
        loop {
            if self.buf.len() < 5 {
                break;
            }
            let kind = self.buf[0];
            let len =
                u32::from_le_bytes([self.buf[1], self.buf[2], self.buf[3], self.buf[4]]) as usize;
            if len > MAX_FRAME_BYTES {
                self.buf.clear();
                if out.is_empty() {
                    return Err(ProtocolError::Oversized);
                }
                self.error = Some(ProtocolError::Oversized);
                return Ok(out);
            }
            if self.buf.len() < 5 + len {
                break;
            }
            let payload = self.buf[5..5 + len].to_vec();
            self.buf.drain(..5 + len);
            out.push(RawFrame { kind, payload });
        }
        Ok(out)
    }

    pub fn take_error(&mut self) -> Option<ProtocolError> {
        self.error.take()
    }
}

pub fn decode_client(bytes: &[u8]) -> Result<ClientMessage, ProtocolError> {
    let mut buf = FrameBuf::default();
    let mut frames = buf.push(bytes)?;
    let Some(frame) = frames.pop() else {
        return Err(ProtocolError::Truncated);
    };
    if !frames.is_empty() || !buf.buf.is_empty() {
        return Err(ProtocolError::BadJson);
    }
    decode_client_frame(&frame)
}

pub fn decode_client_frame(frame: &RawFrame) -> Result<ClientMessage, ProtocolError> {
    match frame.kind {
        HELLO => decode_hello(&frame.payload),
        START => decode_start(&frame.payload),
        PUSH => decode_push(&frame.payload),
        CLOSE => Ok(ClientMessage::Close),
        other => Err(ProtocolError::UnknownType(other)),
    }
}

pub fn decode_server(bytes: &[u8]) -> Result<ServerMessage, ProtocolError> {
    let mut buf = FrameBuf::default();
    let mut frames = buf.push(bytes)?;
    let Some(frame) = frames.pop() else {
        return Err(ProtocolError::Truncated);
    };
    decode_server_frame(&frame)
}

pub fn decode_server_frame(frame: &RawFrame) -> Result<ServerMessage, ProtocolError> {
    match frame.kind {
        HELLO_ACK => decode_hello_ack(&frame.payload),
        STATE => decode_state(&frame.payload),
        FRAME => decode_model_frame(&frame.payload),
        TEXT => Ok(ServerMessage::Text {
            text: String::from_utf8_lossy(&frame.payload).into_owned(),
        }),
        ERROR => decode_error(&frame.payload),
        other => Err(ProtocolError::UnknownType(other)),
    }
}

fn decode_hello(payload: &[u8]) -> Result<ClientMessage, ProtocolError> {
    let json = parse_json(payload)?;
    let v = json
        .get("v")
        .and_then(Json::as_u32)
        .ok_or(ProtocolError::BadJson)?;
    Ok(ClientMessage::Hello { v })
}

fn decode_start(payload: &[u8]) -> Result<ClientMessage, ProtocolError> {
    let json = parse_json(payload)?;
    if json.get("reference_path").is_some() {
        return Err(ProtocolError::ReferenceNotAllowed);
    }
    let language = json
        .get("language")
        .and_then(Json::as_str)
        .unwrap_or("en")
        .to_string();
    if language != "en" && language != "fr" {
        return Err(ProtocolError::BadLanguage);
    }
    let system_prompt = json
        .get("system_prompt")
        .and_then(Json::as_str)
        .unwrap_or("")
        .to_string();
    let speak_first = json
        .get("speak_first")
        .and_then(Json::as_bool)
        .unwrap_or(false);
    Ok(ClientMessage::Start {
        language,
        system_prompt,
        speak_first,
    })
}

fn decode_push(payload: &[u8]) -> Result<ClientMessage, ProtocolError> {
    if payload.len() < 4 || (payload.len() - 4) % 4 != 0 {
        let got = payload.len().saturating_sub(4) / 4;
        return Err(ProtocolError::BadFrameSize {
            expected: FRAME_SAMPLES,
            got,
        });
    }
    let seq = u32::from_le_bytes([payload[0], payload[1], payload[2], payload[3]]);
    let samples: Vec<f32> = payload[4..]
        .chunks_exact(4)
        .map(|chunk| f32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]))
        .collect();
    if samples.len() != FRAME_SAMPLES {
        return Err(ProtocolError::BadFrameSize {
            expected: FRAME_SAMPLES,
            got: samples.len(),
        });
    }
    Ok(ClientMessage::Push { seq, samples })
}

fn decode_hello_ack(payload: &[u8]) -> Result<ServerMessage, ProtocolError> {
    let json = parse_json(payload)?;
    let v = json
        .get("v")
        .and_then(Json::as_u32)
        .ok_or(ProtocolError::BadJson)?;
    let sample_rate = json
        .get("sample_rate")
        .and_then(Json::as_u32)
        .ok_or(ProtocolError::BadJson)?;
    let frame_samples = json
        .get("frame_samples")
        .and_then(Json::as_u32)
        .ok_or(ProtocolError::BadJson)?;
    Ok(ServerMessage::HelloAck {
        v,
        sample_rate,
        frame_samples,
    })
}

fn decode_state(payload: &[u8]) -> Result<ServerMessage, ProtocolError> {
    let json = parse_json(payload)?;
    Ok(ServerMessage::State {
        session: json
            .get("session")
            .and_then(Json::as_str)
            .unwrap_or("")
            .to_string(),
        child: json
            .get("child")
            .and_then(Json::as_str)
            .unwrap_or("")
            .to_string(),
        watchdog: json
            .get("watchdog")
            .and_then(Json::as_str)
            .unwrap_or("")
            .to_string(),
    })
}

fn decode_model_frame(payload: &[u8]) -> Result<ServerMessage, ProtocolError> {
    if payload.len() < 8 || (payload.len() - 8) % 4 != 0 {
        return Err(ProtocolError::BadFrameSize {
            expected: FRAME_SAMPLES,
            got: payload.len().saturating_sub(8) / 4,
        });
    }
    let seq = u32::from_le_bytes([payload[0], payload[1], payload[2], payload[3]]);
    let step_ms = f32::from_le_bytes([payload[4], payload[5], payload[6], payload[7]]);
    let samples: Vec<f32> = payload[8..]
        .chunks_exact(4)
        .map(|chunk| f32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]))
        .collect();
    Ok(ServerMessage::Frame {
        seq,
        step_ms,
        samples,
    })
}

fn decode_error(payload: &[u8]) -> Result<ServerMessage, ProtocolError> {
    let json = parse_json(payload)?;
    Ok(ServerMessage::Error {
        code: json
            .get("code")
            .and_then(Json::as_str)
            .unwrap_or("")
            .to_string(),
        message: json
            .get("message")
            .and_then(Json::as_str)
            .unwrap_or("")
            .to_string(),
        expected: json.get("expected").and_then(Json::as_u32),
        got: json.get("got").and_then(Json::as_u32),
    })
}

pub fn json_string(value: &str) -> String {
    let mut out = String::from("\"");
    for ch in value.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            other if other.is_control() => out.push_str(&format!("\\u{:04x}", other as u32)),
            other => out.push(other),
        }
    }
    out.push('"');
    out
}

#[derive(Clone, Debug, PartialEq)]
enum Json {
    Null,
    Bool(bool),
    Number(f64),
    String(String),
    Object(Vec<(String, Json)>),
}

impl Json {
    fn get(&self, key: &str) -> Option<&Json> {
        match self {
            Json::Object(pairs) => pairs
                .iter()
                .find(|(name, _)| name == key)
                .map(|(_, value)| value),
            Json::Null | Json::Bool(_) | Json::Number(_) | Json::String(_) => None,
        }
    }

    fn as_str(&self) -> Option<&str> {
        match self {
            Json::String(value) => Some(value),
            Json::Null | Json::Bool(_) | Json::Number(_) | Json::Object(_) => None,
        }
    }

    fn as_bool(&self) -> Option<bool> {
        match self {
            Json::Bool(value) => Some(*value),
            Json::Null | Json::Number(_) | Json::String(_) | Json::Object(_) => None,
        }
    }

    fn as_u32(&self) -> Option<u32> {
        match self {
            Json::Number(value)
                if value.is_finite() && *value >= 0.0 && *value <= f64::from(u32::MAX) =>
            {
                Some(*value as u32)
            }
            Json::Number(_) | Json::Null | Json::Bool(_) | Json::String(_) | Json::Object(_) => {
                None
            }
        }
    }
}

fn parse_json(bytes: &[u8]) -> Result<Json, ProtocolError> {
    let text = std::str::from_utf8(bytes).map_err(|_| ProtocolError::BadJson)?;
    let mut parser = Parser { s: text, i: 0 };
    let value = parser.parse().map_err(|_| ProtocolError::BadJson)?;
    parser.skip();
    if parser.i != parser.s.len() {
        return Err(ProtocolError::BadJson);
    }
    Ok(value)
}

struct Parser<'a> {
    s: &'a str,
    i: usize,
}

impl<'a> Parser<'a> {
    fn parse(&mut self) -> Result<Json, ()> {
        self.skip();
        let bytes = self.s.as_bytes();
        if self.i >= bytes.len() {
            return Err(());
        }
        match bytes[self.i] {
            b'{' => self.object(),
            b'"' => Ok(Json::String(self.string()?)),
            b't' => self.eat("true").map(|()| Json::Bool(true)),
            b'f' => self.eat("false").map(|()| Json::Bool(false)),
            b'n' => self.eat("null").map(|()| Json::Null),
            b'-' | b'0'..=b'9' => self.number(),
            _ => Err(()),
        }
    }

    fn object(&mut self) -> Result<Json, ()> {
        self.bump(b'{')?;
        let mut pairs = Vec::new();
        self.skip();
        if self.peek() == Some(b'}') {
            self.i += 1;
            return Ok(Json::Object(pairs));
        }
        loop {
            self.skip();
            let key = self.string()?;
            self.skip();
            self.bump(b':')?;
            let value = self.parse()?;
            pairs.push((key, value));
            self.skip();
            match self.peek() {
                Some(b',') => self.i += 1,
                Some(b'}') => {
                    self.i += 1;
                    break;
                }
                Some(_) | None => return Err(()),
            }
        }
        Ok(Json::Object(pairs))
    }

    fn string(&mut self) -> Result<String, ()> {
        self.bump(b'"')?;
        let bytes = self.s.as_bytes();
        let mut out = String::new();
        while self.i < bytes.len() {
            let ch = bytes[self.i];
            self.i += 1;
            match ch {
                b'"' => return Ok(out),
                b'\\' => {
                    let esc = *bytes.get(self.i).ok_or(())?;
                    self.i += 1;
                    match esc {
                        b'"' => out.push('"'),
                        b'\\' => out.push('\\'),
                        b'/' => out.push('/'),
                        b'n' => out.push('\n'),
                        b'r' => out.push('\r'),
                        b't' => out.push('\t'),
                        b'u' => {
                            let hex = self.s.get(self.i..self.i + 4).ok_or(())?;
                            let code = u32::from_str_radix(hex, 16).map_err(|_| ())?;
                            out.push(char::from_u32(code).ok_or(())?);
                            self.i += 4;
                        }
                        _ => return Err(()),
                    }
                }
                other => out.push(other as char),
            }
        }
        Err(())
    }

    fn number(&mut self) -> Result<Json, ()> {
        let start = self.i;
        let bytes = self.s.as_bytes();
        if bytes.get(self.i) == Some(&b'-') {
            self.i += 1;
        }
        while matches!(
            bytes.get(self.i),
            Some(b'0'..=b'9' | b'.' | b'e' | b'E' | b'+' | b'-')
        ) {
            self.i += 1;
        }
        let text = &self.s[start..self.i];
        let value: f64 = text.parse().map_err(|_| ())?;
        Ok(Json::Number(value))
    }

    fn eat(&mut self, word: &str) -> Result<(), ()> {
        if self.s[self.i..].starts_with(word) {
            self.i += word.len();
            Ok(())
        } else {
            Err(())
        }
    }

    fn bump(&mut self, expected: u8) -> Result<(), ()> {
        if self.peek() == Some(expected) {
            self.i += 1;
            Ok(())
        } else {
            Err(())
        }
    }

    fn peek(&self) -> Option<u8> {
        self.s.as_bytes().get(self.i).copied()
    }

    fn skip(&mut self) {
        while matches!(self.peek(), Some(b' ' | b'\n' | b'\r' | b'\t')) {
            self.i += 1;
        }
    }
}
