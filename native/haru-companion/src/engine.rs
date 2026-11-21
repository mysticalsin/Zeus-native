//! Ties the session, the child, the fake-or-real backend, and the watchdog together.
//! A restart builds a new idle session. It does not transition out of `failed`.

use crate::backend::{BackendEvent, ModelBackend};
use crate::protocol::{self, ClientMessage, ProtocolError, RawFrame, ServerMessage};
use crate::session::{
    ChildControl, SessionError, SessionEvent, SessionHost, SessionState, FRAME_SAMPLES, LOCKSTEP_MS,
};
use crate::supervisor::{ChildEvent, ChildState, RestartBudget};
use crate::watchdog::{
    find_loop, is_garbage_frame, Observation, TurnTracker, Watchdog, WatchdogConfig,
    WatchdogReason, WdState,
};
use std::time::Instant;

#[derive(Clone, Debug, PartialEq)]
pub struct OutFrame {
    pub seq: u32,
    pub step_ms: f32,
    pub samples: Vec<f32>,
    pub text: String,
}

pub struct Engine<B: ModelBackend, C: ChildControl> {
    host: SessionHost<C>,
    backend: B,
    watchdog: Watchdog,
    budget: RestartBudget,
    clock_ms: u64,
    load_started_ms: u64,
    loading: bool,
    start_timeout_ms: u64,
    underruns: u64,
    turn: TurnTracker,
    garbage_run: u32,
    text_tokens: Vec<String>,
    watchdog_on: bool,
    child_phase: ChildState,
    mem_gb: Option<f32>,
}

impl<B: ModelBackend, C: ChildControl> Engine<B, C> {
    pub fn new(backend: B, child: C, argv: Vec<String>, watchdog_on: bool) -> Self {
        Self {
            host: SessionHost::new(child, argv),
            backend,
            watchdog: Watchdog::new(WatchdogConfig::default()),
            budget: RestartBudget::standard(),
            clock_ms: 0,
            load_started_ms: 0,
            loading: false,
            start_timeout_ms: 30_000,
            underruns: 0,
            turn: TurnTracker::new(),
            garbage_run: 0,
            text_tokens: Vec::new(),
            watchdog_on,
            child_phase: ChildState::NotStarted,
            mem_gb: None,
        }
    }

    pub fn session(&self) -> &SessionState {
        self.host.state()
    }

    pub fn trace(&self) -> &[SessionState] {
        self.host.trace()
    }

    pub fn ever_streaming(&self) -> bool {
        self.host.ever_streaming()
    }

    pub fn alive(&self) -> Vec<u32> {
        self.host.alive()
    }

    pub fn spawn_count(&self) -> u32 {
        self.host.spawn_count()
    }

    pub fn underruns(&self) -> u64 {
        self.underruns
    }

    pub fn exchanges(&self) -> u32 {
        self.backend.exchanges()
    }

    pub fn child_state(&self) -> &ChildState {
        &self.child_phase
    }

    pub fn set_start_timeout_ms(&mut self, timeout_ms: u64) {
        self.start_timeout_ms = timeout_ms;
    }

    pub fn begin_model_load(&mut self) -> Result<(), SessionError>  {
        todo!("red");
    }

    pub fn finish_model_load(&mut self) -> Result<(), SessionError>  {
        todo!("red");
    }

    pub fn close(&mut self) -> Result<(), SessionError>  {
        todo!("red");
    }

    /// In-process fake session: the state moves, and no child is spawned.
    pub fn enter_streaming_without_spawn(&mut self) -> Result<(), SessionError>  {
        todo!("red");
    }

    pub fn advance(&mut self, ms: u64)  {
        todo!("red");
    }

    pub fn report_memory_gb(&mut self, gb: f32)  {
        todo!("red");
    }

    pub fn push(&mut self, samples: &[f32], seq: u32) -> Result<Vec<OutFrame>, SessionError>  {
        todo!("red");
    }

    pub fn handle_raw(&mut self, raw: &RawFrame) -> Vec<Vec<u8>>  {
        todo!("red");
    }

    fn handle_message(&mut self, message: ClientMessage) -> Vec<Vec<u8>> {
        match message {
            ClientMessage::Hello { v: 1 } => vec![ServerMessage::hello_ack().encode()],
            ClientMessage::Hello { .. } => {
                vec![protocol::protocol_error_frame(&ProtocolError::BadJson)]
            }
            ClientMessage::Start { .. } => self.handle_start(),
            ClientMessage::Push { seq, samples } => self.handle_push(seq, &samples),
            ClientMessage::Close => self.handle_close(),
        }
    }

    fn handle_start(&mut self) -> Vec<Vec<u8>> {
        if self.begin_model_load().is_err() {
            return vec![protocol::error_frame(&SessionError::IllegalTransition {
                from: Box::new(self.host.state().clone()),
                event: Box::new(SessionEvent::Start),
            })];
        }
        let starting = self.state_message();
        if self.finish_model_load().is_err() {
            return vec![
                starting,
                protocol::error_frame(&SessionError::IllegalTransition {
                    from: Box::new(self.host.state().clone()),
                    event: Box::new(SessionEvent::Started),
                }),
            ];
        }
        vec![starting, self.state_message()]
    }

    fn handle_push(&mut self, seq: u32, samples: &[f32]) -> Vec<Vec<u8>> {
        let before = self.host.trace().len();
        match self.push(samples, seq) {
            Ok(frames) => {
                let mut out: Vec<Vec<u8>> = frames
                    .iter()
                    .map(|frame| {
                        ServerMessage::Frame {
                            seq: frame.seq,
                            step_ms: frame.step_ms,
                            samples: frame.samples.clone(),
                        }
                        .encode()
                    })
                    .collect();
                for frame in &frames {
                    if !frame.text.is_empty() {
                        out.push(protocol::frame(protocol::TEXT, frame.text.as_bytes()));
                    }
                }
                out.extend(self.trace_states_since(before));
                out
            }
            Err(error) => {
                let mut out = vec![protocol::error_frame(&error)];
                out.extend(self.trace_states_since(before));
                out
            }
        }
    }

    fn handle_close(&mut self) -> Vec<Vec<u8>> {
        let was_open = matches!(
            self.host.state(),
            SessionState::Starting | SessionState::Streaming
        );
        if self.close().is_err() {
            return vec![protocol::error_frame(&SessionError::IllegalTransition {
                from: Box::new(self.host.state().clone()),
                event: Box::new(SessionEvent::Close),
            })];
        }
        if was_open {
            let closing = ServerMessage::State {
                session: "closing".to_string(),
                child: self.child_phase.wire_name().to_string(),
                watchdog: self.watchdog.wire_name().to_string(),
            }
            .encode();
            return vec![closing, self.state_message()];
        }
        vec![self.state_message()]
    }

    fn emit(
        &mut self,
        seq: u32,
        model: Vec<f32>,
        text: String,
        delay_ms: u64,
        step_ms: f32,
    ) -> Result<Vec<OutFrame>, SessionError> {
        self.clock_ms = self.clock_ms.saturating_add(delay_ms);
        let late = delay_ms > LOCKSTEP_MS;
        let played = if late {
            vec![0.0; FRAME_SAMPLES]
        } else {
            model
        };
        if late {
            self.underruns = self.underruns.saturating_add(1);
        }
        self.observe(&played, &text, step_ms, delay_ms);
        Ok(vec![OutFrame {
            seq,
            step_ms,
            samples: played,
            text,
        }])
    }

    fn observe(&mut self, played: &[f32], text: &str, step_ms: f32, stall_ms: u64) {
        if !self.watchdog_on {
            return;
        }
        if !text.is_empty() {
            self.text_tokens
                .extend(text.split_whitespace().map(str::to_string));
        }
        let loop_found = find_loop(&self.text_tokens, 3, 32, 3);
        if is_garbage_frame(played) {
            self.garbage_run = self.garbage_run.saturating_add(1);
        } else {
            self.garbage_run = 0;
        }
        let turn = self.turn.push(played);
        let streaming = matches!(self.host.state(), SessionState::Streaming);
        let observation = Observation {
            turn,
            step_ms,
            loop_found,
            mem_gb: self.mem_gb.or(Some(1.0)),
            silent_turns: 0,
            garbage_run: self.garbage_run,
            stall_ms,
            streaming,
        };
        self.apply_watchdog(&observation);
    }

    fn apply_watchdog(&mut self, observation: &Observation) {
        let state = self.watchdog.next(observation);
        if state == WdState::Restart {
            let reason = self.watchdog.reason().unwrap_or(WatchdogReason::Stall);
            let _ = self.fail_and_restart(SessionError::WatchdogRestart { reason });
        }
    }

    fn fail_and_restart(&mut self, error: SessionError) -> Result<(), SessionError> {
        self.loading = false;
        self.host.fail(error)?;
        self.text_tokens.clear();
        self.garbage_run = 0;
        self.turn = TurnTracker::new();
        if self.budget.allow(self.clock_ms) {
            self.watchdog.restarted();
            self.host.spawn_fresh_idle()?;
            self.child_phase = ChildState::Ready;
        } else {
            self.child_phase = ChildState::Stopped { failed: true };
        }
        Ok(())
    }

    fn state_message(&self) -> Vec<u8> {
        ServerMessage::State {
            session: self.host.state().wire_name().to_string(),
            child: self.child_phase.wire_name().to_string(),
            watchdog: self.watchdog.wire_name().to_string(),
        }
        .encode()
    }

    fn trace_states_since(&self, before: usize) -> Vec<Vec<u8>> {
        self.host.trace()[before..]
            .iter()
            .map(|state| {
                ServerMessage::State {
                    session: state.wire_name().to_string(),
                    child: self.child_phase.wire_name().to_string(),
                    watchdog: self.watchdog.wire_name().to_string(),
                }
                .encode()
            })
            .collect()
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct SelftestReport {
    pub frames: u64,
    pub overhead_p50_ms: f64,
    pub overhead_p95_ms: f64,
    pub rss_bytes: u64,
    pub underruns: u64,
    pub spawned: u32,
    pub binds: u32,
    pub network_attempts: u32,
}

impl SelftestReport {
    pub fn to_json(&self) -> String {
        format!(
            "{{\"frames\":{},\"overhead_p50_ms\":{:.6},\"overhead_p95_ms\":{:.6},\"rss_bytes\":{},\"underruns\":{},\"spawned\":{},\"binds\":{},\"network_attempts\":{}}}",
            self.frames,
            self.overhead_p50_ms,
            self.overhead_p95_ms,
            self.rss_bytes,
            self.underruns,
            self.spawned,
            self.binds,
            self.network_attempts
        )
    }
}

pub fn selftest_report(frames: usize) -> SelftestReport  {
    todo!("red");
}

fn percentile(values: &[f64], q: f64) -> f64 {
    if values.is_empty() {
        return 0.0;
    }
    let mut sorted = values.to_vec();
    sorted.sort_by(|left, right| left.total_cmp(right));
    let rank = q * (sorted.len() - 1) as f64;
    let lo = rank.floor() as usize;
    let hi = rank.ceil() as usize;
    let frac = rank - lo as f64;
    sorted[lo] * (1.0 - frac) + sorted[hi] * frac
}

pub fn rss_bytes() -> u64 {
    #[cfg(target_os = "linux")]
    {
        if let Ok(text) = std::fs::read_to_string("/proc/self/statm") {
            if let Some(pages) = text
                .split_whitespace()
                .nth(1)
                .and_then(|field| field.parse::<u64>().ok())
            {
                return pages.saturating_mul(4096);
            }
        }
    }
    0
}
