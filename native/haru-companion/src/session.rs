//! Session lifecycle. This is the amended `VoiceSessionState` table:
//! exhaustive matches, no wildcard arm, `(starting, close) -> closing`,
//! `(idle, close) -> closed` so a later start is refused, and `closed` /
//! `failed` accept nothing. `badFrameSize` is not a transition.

use crate::watchdog::WatchdogReason;
use std::fmt;

pub const FRAME_SAMPLES: usize = haru_pipe::frame::FRAME_SAMPLES;
pub const SAMPLE_RATE: u32 = haru_pipe::SAMPLE_RATE;
pub const LOCKSTEP_MS: u64 = 133;

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum SessionState {
    Idle,
    Starting,
    Streaming,
    Closing,
    Closed,
    Failed(SessionError),
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum SessionEvent {
    Start,
    Started,
    Push,
    Close,
    Closed,
    Fail(SessionError),
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum SessionError {
    IllegalTransition {
        from: Box<SessionState>,
        event: Box<SessionEvent>,
    },
    BadFrameSize {
        expected: usize,
        got: usize,
    },
    ProcessExited {
        code: i32,
    },
    SocketClosed,
    StartTimeout,
    WatchdogRestart {
        reason: WatchdogReason,
    },
}

impl SessionError {
    pub fn code(&self) -> &'static str {
        match self {
            SessionError::IllegalTransition { .. } => "illegal_transition",
            SessionError::BadFrameSize { .. } => "bad_frame_size",
            SessionError::ProcessExited { .. } => "process_exited",
            SessionError::SocketClosed => "socket_closed",
            SessionError::StartTimeout => "start_timeout",
            SessionError::WatchdogRestart { .. } => "watchdog_restart",
        }
    }

    pub fn message(&self) -> String {
        match self {
            SessionError::IllegalTransition { from, event } => {
                format!("illegal transition from {from} on {event}")
            }
            SessionError::BadFrameSize { expected, got } => {
                format!("a frame is {expected} samples, got {got}")
            }
            SessionError::ProcessExited { code } => format!("haru child exited ({code})"),
            SessionError::SocketClosed => "haru socket closed".to_string(),
            SessionError::StartTimeout => "model load timed out".to_string(),
            SessionError::WatchdogRestart { reason } => format!("watchdog restart ({reason})"),
        }
    }

    /// One value of every error variant. The match is the generator: a new
    /// variant does not compile until it grows an arm here.
    pub fn representatives() -> Vec<Self>  {
        todo!("red");
    }
}

fn push_errors(probe: &SessionError, out: &mut Vec<SessionError>) {
    match probe {
        SessionError::BadFrameSize { expected, got } => {
            out.push(SessionError::BadFrameSize {
                expected: *expected,
                got: got.saturating_add(1),
            });
            push_errors(&SessionError::ProcessExited { code: 1 }, out);
        }
        SessionError::ProcessExited { code } => {
            out.push(SessionError::ProcessExited { code: *code });
            push_errors(&SessionError::SocketClosed, out);
        }
        SessionError::SocketClosed => {
            out.push(SessionError::SocketClosed);
            push_errors(&SessionError::StartTimeout, out);
        }
        SessionError::StartTimeout => {
            out.push(SessionError::StartTimeout);
            push_errors(
                &SessionError::WatchdogRestart {
                    reason: WatchdogReason::TokenLoop,
                },
                out,
            );
        }
        SessionError::WatchdogRestart { reason } => {
            match reason {
                WatchdogReason::TokenLoop
                | WatchdogReason::Latency
                | WatchdogReason::Memory
                | WatchdogReason::Stall
                | WatchdogReason::Garbage
                | WatchdogReason::Unanswered => {
                    out.push(SessionError::WatchdogRestart {
                        reason: WatchdogReason::TokenLoop,
                    });
                }
            }
            push_errors(&sample_illegal(), out);
        }
        SessionError::IllegalTransition { from, event } => {
            out.push(SessionError::IllegalTransition {
                from: from.clone(),
                event: event.clone(),
            });
        }
    }
}

fn sample_illegal() -> SessionError {
    SessionError::IllegalTransition {
        from: Box::new(SessionState::Closed),
        event: Box::new(SessionEvent::Start),
    }
}

impl SessionState {
    pub fn next(&self, event: &SessionEvent) -> Result<SessionState, SessionError>  {
        todo!("red");
    }

    pub fn wire_name(&self) -> &'static str {
        match self {
            SessionState::Idle => "idle",
            SessionState::Starting => "starting",
            SessionState::Streaming => "streaming",
            SessionState::Closing => "closing",
            SessionState::Closed => "closed",
            SessionState::Failed(error) => {
                let _ = error.code();
                "failed"
            }
        }
    }

    pub fn is_terminal(&self) -> bool {
        match self {
            SessionState::Closed => true,
            SessionState::Failed(error) => {
                let _kept = error.code();
                true
            }
            SessionState::Idle
            | SessionState::Starting
            | SessionState::Streaming
            | SessionState::Closing => false,
        }
    }

    /// Every state the table test walks, including one `failed` per error variant.
    pub fn representatives() -> Vec<Self>  {
        todo!("red");
    }
}

fn push_states(probe: &SessionState, out: &mut Vec<SessionState>) {
    match probe {
        SessionState::Idle => {
            out.push(SessionState::Idle);
            push_states(&SessionState::Starting, out);
        }
        SessionState::Starting => {
            out.push(SessionState::Starting);
            push_states(&SessionState::Streaming, out);
        }
        SessionState::Streaming => {
            out.push(SessionState::Streaming);
            push_states(&SessionState::Closing, out);
        }
        SessionState::Closing => {
            out.push(SessionState::Closing);
            push_states(&SessionState::Closed, out);
        }
        SessionState::Closed => {
            out.push(SessionState::Closed);
            for error in SessionError::representatives() {
                out.push(SessionState::Failed(error));
            }
        }
        SessionState::Failed(error) => {
            out.push(SessionState::Failed(error.clone()));
        }
    }
}

impl SessionEvent {
    pub fn representatives() -> Vec<Self>  {
        todo!("red");
    }
}

fn push_events(probe: &SessionEvent, out: &mut Vec<SessionEvent>) {
    match probe {
        SessionEvent::Start => {
            out.push(SessionEvent::Start);
            push_events(&SessionEvent::Started, out);
        }
        SessionEvent::Started => {
            out.push(SessionEvent::Started);
            push_events(&SessionEvent::Push, out);
        }
        SessionEvent::Push => {
            out.push(SessionEvent::Push);
            push_events(&SessionEvent::Close, out);
        }
        SessionEvent::Close => {
            out.push(SessionEvent::Close);
            push_events(&SessionEvent::Closed, out);
        }
        SessionEvent::Closed => {
            out.push(SessionEvent::Closed);
            for error in SessionError::representatives() {
                out.push(SessionEvent::Fail(error));
            }
        }
        SessionEvent::Fail(error) => {
            out.push(SessionEvent::Fail(error.clone()));
        }
    }
}

fn illegal(state: &SessionState, event: &SessionEvent) -> SessionError {
    SessionError::IllegalTransition {
        from: Box::new(state.clone()),
        event: Box::new(event.clone()),
    }
}

/// A push is refused with `illegalTransition` when the session cannot accept
/// one. A wrong size on a legal push is `badFrameSize` and is not applied.
pub fn apply_push(state: &SessionState, samples: &[f32]) -> Result<SessionState, SessionError>  {
    todo!("red");
}

impl fmt::Display for SessionState {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(self.wire_name())
    }
}

impl fmt::Display for SessionEvent {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            SessionEvent::Start => formatter.write_str("start"),
            SessionEvent::Started => formatter.write_str("started"),
            SessionEvent::Push => formatter.write_str("push"),
            SessionEvent::Close => formatter.write_str("close"),
            SessionEvent::Closed => formatter.write_str("closed"),
            SessionEvent::Fail(error) => write!(formatter, "fail({})", error.code()),
        }
    }
}

impl fmt::Display for SessionError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.message())
    }
}

impl fmt::Display for WatchdogReason {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        let name = match self {
            WatchdogReason::TokenLoop => "token_loop",
            WatchdogReason::Latency => "latency",
            WatchdogReason::Memory => "memory",
            WatchdogReason::Stall => "stall",
            WatchdogReason::Garbage => "garbage",
            WatchdogReason::Unanswered => "unanswered",
        };
        formatter.write_str(name)
    }
}

impl std::error::Error for SessionError {}

/// Spawn and kill the model child. Tests use a spy; `serve` uses a process.
pub trait ChildControl {
    fn spawn(&mut self, argv: &[String]) -> std::io::Result<u32>;
    fn kill(&mut self, pid: u32);
    fn alive(&self) -> Vec<u32>;
    fn spawn_count(&self) -> u32;
}

/// Applies the session table and owns the child pid for one load.
pub struct SessionHost<C: ChildControl> {
    state: SessionState,
    trace: Vec<SessionState>,
    child: C,
    argv: Vec<String>,
    pid: Option<u32>,
    ever_streaming: bool,
}

impl<C: ChildControl> SessionHost<C> {
    pub fn new(child: C, argv: Vec<String>) -> Self {
        Self {
            state: SessionState::Idle,
            trace: Vec::new(),
            child,
            argv,
            pid: None,
            ever_streaming: false,
        }
    }

    pub fn state(&self) -> &SessionState {
        &self.state
    }

    pub fn trace(&self) -> &[SessionState] {
        &self.trace
    }

    pub fn ever_streaming(&self) -> bool {
        self.ever_streaming
    }

    pub fn alive(&self) -> Vec<u32> {
        self.child.alive()
    }

    pub fn spawn_count(&self) -> u32 {
        self.child.spawn_count()
    }

    pub fn pid(&self) -> Option<u32> {
        self.pid
    }

    pub fn transition(&mut self, event: SessionEvent) -> Result<(), SessionError> {
        let next = self.state.next(&event)?;
        self.apply(next);
        Ok(())
    }

    /// Idle -> Starting, then spawn. Returns while the load is still in progress.
    pub fn begin_model_load(&mut self) -> Result<(), SessionError>  {
        todo!("red");
    }

    /// Started is legal only from Starting. Closing or Closed refuses it.
    pub fn finish_model_load(&mut self) -> Result<(), SessionError>  {
        todo!("red");
    }

    /// Close. Starting becomes Closing, the child is killed, then Closed.
    /// Idle becomes Closed and does not spawn, so a later start is refused.
    pub fn close(&mut self) -> Result<(), SessionError>  {
        todo!("red");
    }

    pub fn fail(&mut self, error: SessionError) -> Result<(), SessionError> {
        let next = self.state.next(&SessionEvent::Fail(error))?;
        self.apply(next);
        self.kill_pid();
        Ok(())
    }

    /// Recovery is a new session, not a transition out of `failed`.
    pub fn spawn_fresh_idle(&mut self) -> Result<(), SessionError> {
        self.ever_streaming = false;
        self.pid = None;
        self.apply(SessionState::Idle);
        self.spawn_child()?;
        Ok(())
    }

    fn spawn_child(&mut self) -> Result<(), SessionError> {
        match self.child.spawn(&self.argv) {
            Ok(pid) => {
                self.pid = Some(pid);
                Ok(())
            }
            Err(_) => Err(SessionError::ProcessExited { code: -1 }),
        }
    }

    fn kill_pid(&mut self) {
        if let Some(pid) = self.pid.take() {
            self.child.kill(pid);
        }
    }

    fn apply(&mut self, next: SessionState)  {
        todo!("red");
    }
}
