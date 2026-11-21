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
    pub fn representatives() -> Vec<Self> {
        let mut out = Vec::new();
        push_errors(
            &SessionError::BadFrameSize {
                expected: FRAME_SAMPLES,
                got: 0,
            },
            &mut out,
        );
        out
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
    pub fn next(&self, event: &SessionEvent) -> Result<SessionState, SessionError> {
        match self {
            SessionState::Idle => match event {
                SessionEvent::Start => Ok(SessionState::Starting),
                SessionEvent::Close => Ok(SessionState::Closed),
                SessionEvent::Fail(error) => Ok(SessionState::Failed(error.clone())),
                SessionEvent::Started | SessionEvent::Push | SessionEvent::Closed => {
                    Err(illegal(self, event))
                }
            },
            SessionState::Starting => match event {
                SessionEvent::Started => Ok(SessionState::Streaming),
                SessionEvent::Close => Ok(SessionState::Closing),
                SessionEvent::Fail(error) => Ok(SessionState::Failed(error.clone())),
                SessionEvent::Start | SessionEvent::Push | SessionEvent::Closed => {
                    Err(illegal(self, event))
                }
            },
            SessionState::Streaming => match event {
                SessionEvent::Push => Ok(SessionState::Streaming),
                SessionEvent::Close => Ok(SessionState::Closing),
                SessionEvent::Fail(error) => Ok(SessionState::Failed(error.clone())),
                SessionEvent::Start | SessionEvent::Started | SessionEvent::Closed => {
                    Err(illegal(self, event))
                }
            },
            SessionState::Closing => match event {
                SessionEvent::Closed => Ok(SessionState::Closed),
                SessionEvent::Fail(error) => Ok(SessionState::Failed(error.clone())),
                SessionEvent::Start
                | SessionEvent::Started
                | SessionEvent::Push
                | SessionEvent::Close => Err(illegal(self, event)),
            },
            SessionState::Closed => match event {
                SessionEvent::Start
                | SessionEvent::Started
                | SessionEvent::Push
                | SessionEvent::Close
                | SessionEvent::Closed => Err(illegal(self, event)),
                SessionEvent::Fail(error) => {
                    let _kept = error.code();
                    Err(illegal(self, event))
                }
            },
            SessionState::Failed(existing) => match event {
                SessionEvent::Start
                | SessionEvent::Started
                | SessionEvent::Push
                | SessionEvent::Close
                | SessionEvent::Closed => {
                    let _kept = existing.code();
                    Err(illegal(self, event))
                }
                SessionEvent::Fail(error) => {
                    let _kept = (existing.code(), error.code());
                    Err(illegal(self, event))
                }
            },
        }
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
    pub fn representatives() -> Vec<Self> {
        let mut out = Vec::new();
        push_states(&SessionState::Idle, &mut out);
        out
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
    pub fn representatives() -> Vec<Self> {
        let mut out = Vec::new();
        push_events(&SessionEvent::Start, &mut out);
        out
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
pub fn apply_push(state: &SessionState, samples: &[f32]) -> Result<SessionState, SessionError> {
    let next = state.next(&SessionEvent::Push)?;
    if samples.len() != FRAME_SAMPLES {
        return Err(SessionError::BadFrameSize {
            expected: FRAME_SAMPLES,
            got: samples.len(),
        });
    }
    Ok(next)
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

/// SVG of the legal transitions. Node positions are fixed; every edge is an
/// `Ok` result from [`SessionState::next`], and the moving dot walks
/// idle → starting → streaming → closing → closed by calling `next`.
pub fn state_machine_svg() -> String {
    let nodes = [
        (SessionState::Idle, 90.0, 70.0),
        (SessionState::Starting, 280.0, 70.0),
        (SessionState::Streaming, 490.0, 70.0),
        (SessionState::Closing, 490.0, 230.0),
        (SessionState::Closed, 280.0, 230.0),
        (
            SessionState::Failed(SessionError::SocketClosed),
            90.0,
            230.0,
        ),
    ];
    let events = [
        SessionEvent::Start,
        SessionEvent::Started,
        SessionEvent::Push,
        SessionEvent::Close,
        SessionEvent::Closed,
        SessionEvent::Fail(SessionError::SocketClosed),
    ];
    let mut edges: Vec<(String, String, String, bool)> = Vec::new();
    for (state, _, _) in &nodes {
        for event in &events {
            if let Ok(next) = state.next(event) {
                let fail = matches!(event, SessionEvent::Fail(_));
                edges.push((
                    state.wire_name().to_string(),
                    event.to_string(),
                    next.wire_name().to_string(),
                    fail,
                ));
            }
        }
    }
    edges.sort();
    let pos = |name: &str| -> (f64, f64) {
        nodes
            .iter()
            .find(|(state, _, _)| state.wire_name() == name)
            .map(|(_, x, y)| (*x, *y))
            .unwrap_or((0.0, 0.0))
    };
    let mut walk = SessionState::Idle;
    let mut walk_points = vec![pos(walk.wire_name())];
    for event in [
        SessionEvent::Start,
        SessionEvent::Started,
        SessionEvent::Close,
        SessionEvent::Closed,
    ] {
        if let Ok(next) = walk.next(&event) {
            walk = next;
            walk_points.push(pos(walk.wire_name()));
        }
    }
    let mut path = format!("M {} {}", walk_points[0].0, walk_points[0].1 + 28.0);
    for (x, y) in walk_points.iter().skip(1) {
        path.push_str(&format!(" L {x} {}", y + 28.0));
    }
    let mut lines = String::new();
    for (from, event, to, fail) in &edges {
        let (x1, y1) = pos(from);
        let (x2, y2) = pos(to);
        let color = if *fail { "#9a3412" } else { "#44403c" };
        if from == to {
            lines.push_str(&format!(
                "<path d=\"M {x1} {y1} m 28 -18 a 18 18 0 1 1 -1 0\" fill=\"none\" stroke=\"{color}\" stroke-width=\"1.4\"/>"
            ));
            lines.push_str(&format!(
                "<text x=\"{x1}\" y=\"{}\" text-anchor=\"middle\" font-size=\"11\" fill=\"{color}\">{event}</text>",
                y1 - 46.0
            ));
            continue;
        }
        let mx = (x1 + x2) / 2.0;
        let my = (y1 + y2) / 2.0 - 8.0;
        lines.push_str(&format!(
            "<line x1=\"{x1}\" y1=\"{y1}\" x2=\"{x2}\" y2=\"{y2}\" stroke=\"{color}\" stroke-width=\"1.4\" marker-end=\"url(#arrow)\"/>"
        ));
        lines.push_str(&format!(
            "<text x=\"{mx}\" y=\"{my}\" text-anchor=\"middle\" font-size=\"11\" fill=\"{color}\">{event}</text>"
        ));
    }
    let mut circles = String::new();
    for (state, x, y) in &nodes {
        let name = state.wire_name();
        let fill = if state.is_terminal() {
            "#e7e5e4"
        } else {
            "#fff7ed"
        };
        circles.push_str(&format!(
            "<g><rect x=\"{}\" y=\"{}\" width=\"120\" height=\"36\" rx=\"8\" fill=\"{fill}\" stroke=\"#292524\"/><text x=\"{x}\" y=\"{}\" text-anchor=\"middle\" font-size=\"14\" font-family=\"ui-sans-serif, system-ui, sans-serif\" fill=\"#1c1917\">{name}</text></g>",
            x - 60.0,
            y - 18.0,
            y + 5.0
        ));
    }
    format!(
        r##"<svg xmlns="http://www.w3.org/2000/svg" width="640" height="340" viewBox="0 0 640 340" role="img" aria-label="Haru session state machine">
<title>Haru session state machine</title>
<desc>Legal edges come from SessionState::next. The dot walks idle, starting, streaming, closing, closed.</desc>
<style>text {{ font-family: ui-sans-serif, system-ui, sans-serif; }}</style>
<defs><marker id="arrow" markerWidth="8" markerHeight="8" refX="7" refY="3" orient="auto"><path d="M0,0 L8,3 L0,6 Z" fill="#44403c"/></marker></defs>
<rect width="640" height="340" fill="#fafaf9"/>
{lines}
{circles}
<circle r="5" fill="#c2410c"><animateMotion dur="8s" repeatCount="indefinite" path="{path}"/></circle>
</svg>
"##
    )
}

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
    /// A spawn error is `process_exited` and moves the session to `failed`.
    /// A child already adopted for this session is kept; a second process is not spawned.
    pub fn begin_model_load(&mut self) -> Result<(), SessionError> {
        let next = self.state.next(&SessionEvent::Start)?;
        self.apply(next);
        if self.pid.is_some() {
            return Ok(());
        }
        if let Err(error) = self.spawn_child() {
            self.fail(error.clone())?;
            return Err(error);
        }
        Ok(())
    }

    /// Started is legal only from Starting. Closing or Closed refuses it.
    /// A child that has already exited becomes `process_exited` and is reaped.
    pub fn finish_model_load(&mut self) -> Result<(), SessionError> {
        if self.child_exited() {
            let error = SessionError::ProcessExited { code: -1 };
            self.fail(error.clone())?;
            return Err(error);
        }
        let next = self.state.next(&SessionEvent::Started)?;
        self.apply(next);
        Ok(())
    }

    /// True when the recorded pid has exited. The pid is reaped and forgotten.
    pub fn child_exited(&mut self) -> bool {
        let Some(pid) = self.pid else {
            return false;
        };
        if self.child.alive().contains(&pid) {
            return false;
        }
        self.pid = None;
        true
    }

    /// Close. Starting becomes Closing, the child is killed, then Closed.
    /// Idle becomes Closed and does not spawn, so a later start is refused.
    /// A child left alive by a restart is killed on this close too.
    pub fn close(&mut self) -> Result<(), SessionError> {
        let next = self.state.next(&SessionEvent::Close)?;
        self.apply(next);
        self.kill_pid();
        if self.state == SessionState::Closing {
            let closed = self.state.next(&SessionEvent::Closed)?;
            self.apply(closed);
        }
        Ok(())
    }

    pub fn fail(&mut self, error: SessionError) -> Result<(), SessionError> {
        let next = self.state.next(&SessionEvent::Fail(error))?;
        self.apply(next);
        self.kill_pid();
        Ok(())
    }

    /// Recovery is a new session, not a transition out of `failed`.
    /// Any child still recorded for the old session is killed first.
    pub fn spawn_fresh_idle(&mut self) -> Result<(), SessionError> {
        self.kill_pid();
        self.ever_streaming = false;
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

    fn apply(&mut self, next: SessionState) {
        if matches!(next, SessionState::Streaming) {
            self.ever_streaming = true;
        }
        self.trace.push(next.clone());
        self.state = next;
    }
}
