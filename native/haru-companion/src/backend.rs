//! Model backends. Tests and `selftest` use [`FakeBackend`]. The real child
//! speaks the upstream socket; nothing here downloads a model.

use crate::session::FRAME_SAMPLES;
use crate::upstream::{self, StartRequest, UpstreamMessage};
use std::collections::VecDeque;
use std::io::{Read, Write};

#[derive(Clone, Debug, PartialEq)]
pub enum BackendEvent {
    Frame {
        samples: Vec<f32>,
        text: String,
        delay_ms: u64,
        step_ms: f32,
    },
    Stall {
        delay_ms: u64,
    },
    Exited {
        code: i32,
    },
    SocketClosed,
}

pub trait ModelBackend {
    fn exchange(&mut self, samples: &[f32]) -> BackendEvent;
    fn exchanges(&self) -> u32;
}

#[derive(Clone, Debug)]
pub enum ScriptStep {
    Frame {
        fill: f32,
        text: String,
        delay_ms: u64,
        step_ms: f32,
    },
    Noise {
        delay_ms: u64,
        step_ms: f32,
    },
    Stall {
        delay_ms: u64,
    },
    Exit {
        code: i32,
    },
    SocketClosed,
}

#[derive(Debug)]
pub struct FakeBackend {
    script: VecDeque<ScriptStep>,
    exchanges: u32,
}

impl FakeBackend {
    pub fn new(script: Vec<ScriptStep>) -> Self {
        Self {
            script: script.into(),
            exchanges: 0,
        }
    }

    pub fn quiet() -> Self {
        Self::new(Vec::new())
    }
}

impl ModelBackend for FakeBackend {
    fn exchange(&mut self, _samples: &[f32]) -> BackendEvent {
        self.exchanges = self.exchanges.saturating_add(1);
        match self.script.pop_front() {
            Some(ScriptStep::Frame {
                fill,
                text,
                delay_ms,
                step_ms,
            }) => BackendEvent::Frame {
                samples: vec![fill; FRAME_SAMPLES],
                text,
                delay_ms,
                step_ms,
            },
            Some(ScriptStep::Noise { delay_ms, step_ms }) => BackendEvent::Frame {
                samples: noise_frame(),
                text: String::new(),
                delay_ms,
                step_ms,
            },
            Some(ScriptStep::Stall { delay_ms }) => BackendEvent::Stall { delay_ms },
            Some(ScriptStep::Exit { code }) => BackendEvent::Exited { code },
            Some(ScriptStep::SocketClosed) => BackendEvent::SocketClosed,
            None => BackendEvent::Frame {
                samples: vec![0.0; FRAME_SAMPLES],
                text: String::new(),
                delay_ms: 0,
                step_ms: 0.0,
            },
        }
    }

    fn exchanges(&self) -> u32 {
        self.exchanges
    }
}

fn noise_frame() -> Vec<f32> {
    (0..FRAME_SAMPLES)
        .map(|index| if index % 2 == 0 { 0.8 } else { -0.8 })
        .collect()
}

/// Speaks `haru_mlx.native` on an already-connected stream. Tests do not construct it.
pub struct UpstreamBackend<S> {
    stream: S,
    pending: VecDeque<u8>,
    exchanges: u32,
    request: StartRequest,
    started: bool,
}

impl<S> UpstreamBackend<S> {
    pub fn new(stream: S, request: StartRequest) -> Self {
        Self {
            stream,
            pending: VecDeque::new(),
            exchanges: 0,
            request,
            started: false,
        }
    }
}

impl<S: Read + Write> ModelBackend for UpstreamBackend<S> {
    fn exchange(&mut self, samples: &[f32]) -> BackendEvent {
        self.exchanges = self.exchanges.saturating_add(1);
        if !self.started {
            let bytes = upstream::encode_start(&self.request);
            if self.stream.write_all(&bytes).is_err() {
                return BackendEvent::SocketClosed;
            }
            self.started = true;
        }
        let audio = upstream::encode_upstream_push(samples);
        if self.stream.write_all(&audio).is_err() {
            return BackendEvent::SocketClosed;
        }
        match read_upstream(&mut self.stream, &mut self.pending) {
            Ok(UpstreamMessage::Frame { pcm48, step_ms, .. }) => BackendEvent::Frame {
                samples: upstream::downsample_48k(&pcm48),
                text: String::new(),
                delay_ms: 0,
                step_ms,
            },
            Ok(UpstreamMessage::Error(_)) => BackendEvent::Exited { code: -1 },
            Ok(_) => BackendEvent::Stall { delay_ms: 0 },
            Err(ReadFault::Closed) => BackendEvent::SocketClosed,
            Err(ReadFault::Exited) => BackendEvent::Exited { code: -1 },
        }
    }

    fn exchanges(&self) -> u32 {
        self.exchanges
    }
}

enum ReadFault {
    Closed,
    Exited,
}

fn read_upstream<S: Read>(
    stream: &mut S,
    pending: &mut VecDeque<u8>,
) -> Result<UpstreamMessage, ReadFault> {
    loop {
        if pending.len() >= 5 {
            let kind = pending[0];
            let len = u32::from_le_bytes([pending[1], pending[2], pending[3], pending[4]]) as usize;
            if len > crate::protocol::MAX_FRAME_BYTES {
                pending.clear();
                return Err(ReadFault::Exited);
            }
            if pending.len() >= 5 + len {
                for _ in 0..5 {
                    pending.pop_front();
                }
                let payload: Vec<u8> = pending.drain(..len).collect();
                return Ok(upstream::decode_upstream(kind, &payload));
            }
        }
        let mut buf = [0u8; 4096];
        match stream.read(&mut buf) {
            Ok(0) => return Err(ReadFault::Closed),
            Ok(n) => pending.extend(&buf[..n]),
            Err(_) => return Err(ReadFault::Exited),
        }
    }
}
