//! Model backends. Tests and `selftest` use [`FakeBackend`]. The real child
//! speaks the upstream socket; nothing here downloads a model.

use crate::session::FRAME_SAMPLES;
use crate::upstream::{self, StartRequest, UpstreamMessage};
use std::collections::VecDeque;
use std::io::{Read, Write};
use std::os::unix::io::AsRawFd;
use std::os::unix::net::UnixStream;
use std::time::Duration;

const UPSTREAM_STALL_MS: u64 = 2_000;

/// Arms a read deadline. Sockets use `SO_RCVTIMEO`. Other readers no-op.
pub trait ReadDeadline {
    fn arm_read_timeout(&self, timeout: Duration) -> std::io::Result<()>;
}

impl ReadDeadline for UnixStream {
    fn arm_read_timeout(&self, timeout: Duration) -> std::io::Result<()> {
        arm_fd_timeout(self.as_raw_fd(), timeout)
    }
}

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
    fn note_start(&mut self, _language: &str, _system_prompt: &str, _speak_first: bool) {}
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

/// Connects to the model listen socket on the first exchange and then
/// speaks `haru_mlx.native`. Until that exchange, the client has not
/// been given a frame.
pub struct ModelLink {
    path: std::path::PathBuf,
    request: crate::upstream::StartRequest,
    inner: Option<UpstreamBackend<UnixStream>>,
}

impl ModelLink {
    pub fn new(path: std::path::PathBuf) -> Self {
        Self {
            path,
            request: crate::upstream::StartRequest {
                language: "en".to_string(),
                system_prompt: String::new(),
                speak_first: false,
            },
            inner: None,
        }
    }
}

impl ModelBackend for ModelLink {
    fn note_start(&mut self, language: &str, system_prompt: &str, speak_first: bool) {
        self.request.language = language.to_string();
        self.request.system_prompt = system_prompt.to_string();
        self.request.speak_first = speak_first;
    }

    fn exchange(&mut self, samples: &[f32]) -> BackendEvent {
        if self.inner.is_none() {
            let stream = match connect_model(&self.path) {
                Ok(stream) => stream,
                Err(_) => return BackendEvent::SocketClosed,
            };
            self.inner = Some(UpstreamBackend::new(stream, self.request.clone()));
        }
        self.inner
            .as_mut()
            .map(|backend| backend.exchange(samples))
            .unwrap_or(BackendEvent::SocketClosed)
    }

    fn exchanges(&self) -> u32 {
        self.inner
            .as_ref()
            .map(UpstreamBackend::exchanges)
            .unwrap_or(0)
    }
}

fn connect_model(path: &std::path::Path) -> std::io::Result<UnixStream> {
    let deadline = std::time::Instant::now() + Duration::from_secs(2);
    let mut last = std::io::Error::new(std::io::ErrorKind::NotFound, "model socket");
    while std::time::Instant::now() < deadline {
        match UnixStream::connect(path) {
            Ok(stream) => return Ok(stream),
            Err(error) => {
                last = error;
                std::thread::sleep(Duration::from_millis(20));
            }
        }
    }
    Err(last)
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

impl<S: Read + Write + ReadDeadline> ModelBackend for UpstreamBackend<S> {
    fn exchange(&mut self, samples: &[f32]) -> BackendEvent {
        self.exchanges = self.exchanges.saturating_add(1);
        let _ = self
            .stream
            .arm_read_timeout(Duration::from_millis(UPSTREAM_STALL_MS));
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
            Ok(UpstreamMessage::Frame { pcm48, step_ms, .. }) => {
                let samples = upstream::downsample_48k(&pcm48);
                if samples.len() != FRAME_SAMPLES {
                    return BackendEvent::Exited { code: -1 };
                }
                BackendEvent::Frame {
                    samples,
                    text: String::new(),
                    delay_ms: 0,
                    step_ms,
                }
            }
            Ok(UpstreamMessage::Text(text)) => BackendEvent::Frame {
                samples: vec![0.0; FRAME_SAMPLES],
                text,
                delay_ms: 0,
                step_ms: 0.0,
            },
            Ok(UpstreamMessage::Error(_)) => BackendEvent::Exited { code: -1 },
            Ok(_) => BackendEvent::Stall { delay_ms: 0 },
            Err(ReadFault::Timeout) => BackendEvent::Stall {
                delay_ms: UPSTREAM_STALL_MS,
            },
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
    Timeout,
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
            Err(error)
                if error.kind() == std::io::ErrorKind::TimedOut
                    || error.kind() == std::io::ErrorKind::WouldBlock =>
            {
                return Err(ReadFault::Timeout);
            }
            Err(_) => return Err(ReadFault::Exited),
        }
    }
}

fn arm_fd_timeout(fd: i32, timeout: Duration) -> std::io::Result<()> {
    #[repr(C)]
    struct Timeval {
        tv_sec: i64,
        tv_usec: i64,
    }
    let tv = Timeval {
        tv_sec: timeout.as_secs() as i64,
        tv_usec: timeout.subsec_micros() as i64,
    };
    let rc = unsafe {
        setsockopt(
            fd,
            1,
            20,
            (&tv as *const Timeval).cast(),
            std::mem::size_of::<Timeval>() as u32,
        )
    };
    if rc != 0 {
        Err(std::io::Error::last_os_error())
    } else {
        Ok(())
    }
}

extern "C" {
    fn setsockopt(
        sockfd: i32,
        level: i32,
        optname: i32,
        optval: *const core::ffi::c_void,
        optlen: u32,
    ) -> i32;
}
