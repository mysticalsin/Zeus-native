//! Explicit watchdog. Soft faults wait for idle. Hard faults restart at once.
//!
//! The thresholds follow the box soak (`haru_soak.py`): a repeated token block,
//! three unanswered turns, ~3 s of garbage audio, p95 step over 120 ms for 30 s,
//! child RSS over 14 GB, and 2 s without a frame while streaming.

use std::collections::VecDeque;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum WatchdogReason {
    TokenLoop,
    Latency,
    Memory,
    Stall,
    Garbage,
    Unanswered,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum WdState {
    Ok,
    Pending,
    Restart,
    Cooldown,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Turn {
    Idle,
    User,
    Model,
    Overlap,
}

#[derive(Clone, Debug, PartialEq)]
pub struct WatchdogConfig {
    pub loop_repeats: usize,
    pub loop_min_period: usize,
    pub loop_max_period: usize,
    pub latency_ms: f32,
    pub latency_window: usize,
    pub mem_gb: f32,
    pub silent_turns: u32,
    pub cooldown_frames: u32,
    pub garbage_frames: u32,
    pub stall_ms: u64,
}

impl Default for WatchdogConfig {
    fn default() -> Self {
        Self {
            loop_repeats: 3,
            loop_min_period: 3,
            loop_max_period: 32,
            latency_ms: 120.0,
            latency_window: 225,
            mem_gb: 14.0,
            silent_turns: 3,
            cooldown_frames: 450,
            garbage_frames: 23,
            stall_ms: 2_000,
        }
    }
}

#[derive(Clone, Debug)]
pub struct Observation {
    pub turn: Turn,
    pub step_ms: f32,
    pub loop_found: Option<(usize, usize)>,
    pub mem_gb: Option<f32>,
    pub silent_turns: u32,
    pub garbage_run: u32,
    pub stall_ms: u64,
    pub streaming: bool,
}

impl Observation {
    pub fn quiet() -> Self {
        Self {
            turn: Turn::Idle,
            step_ms: 1.0,
            loop_found: None,
            mem_gb: Some(1.0),
            silent_turns: 0,
            garbage_run: 0,
            stall_ms: 0,
            streaming: true,
        }
    }
}

#[derive(Debug)]
pub struct Watchdog {
    cfg: WatchdogConfig,
    state: WdState,
    reason: Option<WatchdogReason>,
    lat: VecDeque<f32>,
    cool: u32,
}

impl Watchdog {
    pub fn new(cfg: WatchdogConfig) -> Self {
        let window = cfg.latency_window;
        Self {
            cfg,
            state: WdState::Ok,
            reason: None,
            lat: VecDeque::with_capacity(window),
            cool: 0,
        }
    }

    pub fn state(&self) -> WdState {
        self.state
    }

    pub fn reason(&self) -> Option<WatchdogReason> {
        self.reason
    }

    pub fn wire_name(&self) -> &'static str {
        match self.state {
            WdState::Ok => "ok",
            WdState::Pending => "pending",
            WdState::Restart => "restart",
            WdState::Cooldown => "cooldown",
        }
    }

    pub fn next(&mut self, obs: &Observation) -> WdState {
        self.lat.push_back(obs.step_ms);
        while self.lat.len() > self.cfg.latency_window {
            self.lat.pop_front();
        }
        if self.state == WdState::Cooldown {
            self.cool = self.cool.saturating_sub(1);
            if self.cool == 0 {
                self.state = WdState::Ok;
                self.reason = None;
            }
            return self.state;
        }
        if let Some(reason) = self.hard(obs) {
            self.state = WdState::Restart;
            self.reason = Some(reason);
            return self.state;
        }
        if let Some(reason) = self.soft(obs) {
            if self.state == WdState::Ok {
                self.state = WdState::Pending;
                self.reason = Some(reason);
            }
        }
        if self.state == WdState::Pending && obs.turn == Turn::Idle {
            self.state = WdState::Restart;
        }
        self.state
    }

    pub fn restarted(&mut self) {
        self.state = WdState::Cooldown;
        self.cool = self.cfg.cooldown_frames;
        self.lat.clear();
        self.reason = None;
    }

    /// Feed model text and a turn. A repeated block becomes a soft fault.
    pub fn observe_text(&mut self, text: &str, turn: Turn) -> WdState {
        let words: Vec<&str> = text.split_whitespace().collect();
        let found = find_loop(
            &words,
            self.cfg.loop_min_period,
            self.cfg.loop_max_period,
            self.cfg.loop_repeats,
        );
        let mut obs = Observation::quiet();
        obs.turn = turn;
        obs.loop_found = found;
        self.next(&obs)
    }

    fn hard(&self, obs: &Observation) -> Option<WatchdogReason> {
        let mut reason = None;
        if self.lat.len() == self.cfg.latency_window && self.p95() > self.cfg.latency_ms {
            reason = Some(WatchdogReason::Latency);
        }
        if obs.mem_gb.is_some_and(|mem| mem > self.cfg.mem_gb) {
            reason = Some(WatchdogReason::Memory);
        }
        if obs.streaming && obs.stall_ms >= self.cfg.stall_ms {
            reason = Some(WatchdogReason::Stall);
        }
        reason
    }

    fn soft(&self, obs: &Observation) -> Option<WatchdogReason> {
        if let Some((period, reps)) = obs.loop_found {
            if reps >= self.cfg.loop_repeats && period >= self.cfg.loop_min_period {
                return Some(WatchdogReason::TokenLoop);
            }
        }
        if obs.silent_turns >= self.cfg.silent_turns {
            return Some(WatchdogReason::Unanswered);
        }
        if obs.garbage_run >= self.cfg.garbage_frames {
            return Some(WatchdogReason::Garbage);
        }
        None
    }

    fn p95(&self) -> f32 {
        percentile_linear(self.lat.iter().copied(), 0.95)
    }
}

pub fn percentile_linear(values: impl IntoIterator<Item = f32>, q: f32) -> f32 {
    let mut samples: Vec<f32> = values.into_iter().collect();
    if samples.is_empty() {
        return 0.0;
    }
    samples.sort_by(|a, b| a.total_cmp(b));
    let rank = q * (samples.len() - 1) as f32;
    let lo = rank.floor() as usize;
    let hi = rank.ceil() as usize;
    let frac = rank - lo as f32;
    samples[lo] * (1.0 - frac) + samples[hi] * frac
}

/// `(period, repeats)` when `tokens` ends with a block repeated back to back.
pub fn find_loop<T: PartialEq>(
    tokens: &[T],
    min_period: usize,
    max_period: usize,
    min_repeats: usize,
) -> Option<(usize, usize)> {
    let n = tokens.len();
    let mut best: Option<(usize, usize)> = None;
    for period in min_period..=max_period {
        if n < period.saturating_mul(min_repeats) {
            break;
        }
        let mut reps = 1usize;
        while reps.saturating_add(1).saturating_mul(period) <= n
            && tokens[n - (reps + 1) * period..n - reps * period] == tokens[n - period..n]
        {
            reps += 1;
        }
        if reps >= min_repeats {
            let score = reps * period;
            let replace = match best {
                None => true,
                Some((period_best, reps_best)) => score > period_best * reps_best,
            };
            if replace {
                best = Some((period, reps));
            }
        }
    }
    best
}

/// Noise-like, clipped, or non-finite model audio. A steady tone is not garbage.
pub fn is_garbage_frame(samples: &[f32]) -> bool {
    if samples.is_empty() {
        return false;
    }
    if samples.iter().any(|sample| !sample.is_finite()) {
        return true;
    }
    let mut sum_sq = 0.0f64;
    let mut clips = 0usize;
    let mut crossings = 0usize;
    let mut previous = samples[0];
    for sample in samples {
        let value = f64::from(*sample);
        sum_sq += value * value;
        if sample.abs() >= 0.99 {
            clips += 1;
        }
        if previous * *sample < 0.0 {
            crossings += 1;
        }
        previous = *sample;
    }
    if clips * 100 > samples.len() {
        return true;
    }
    let rms = (sum_sq / samples.len() as f64).sqrt();
    if rms <= 1e-6 {
        return false;
    }
    let dbfs = 20.0 * rms.log10();
    let zero_crossing_rate = crossings as f32 / samples.len() as f32;
    dbfs > -45.0 && zero_crossing_rate > 0.15
}

pub fn frame_dbfs(samples: &[f32]) -> f64 {
    if samples.is_empty() {
        return -120.0;
    }
    let sum_sq: f64 = samples
        .iter()
        .map(|sample| f64::from(*sample).powi(2))
        .sum();
    let rms = (sum_sq / samples.len() as f64).sqrt();
    if rms <= 1e-6 {
        -120.0
    } else {
        20.0 * rms.log10()
    }
}

#[derive(Debug)]
pub struct TurnTracker {
    hang: u32,
    quiet: u32,
    state: Turn,
}

impl TurnTracker {
    pub fn new() -> Self {
        Self {
            hang: 6,
            quiet: 6,
            state: Turn::Idle,
        }
    }

    pub fn push(&mut self, samples: &[f32]) -> Turn {
        let voiced = frame_dbfs(samples) > -45.0;
        self.quiet = if voiced {
            0
        } else {
            self.quiet.saturating_add(1)
        };
        self.state = if self.quiet < self.hang {
            Turn::Model
        } else {
            Turn::Idle
        };
        self.state
    }

    pub fn state(&self) -> Turn {
        self.state
    }
}

impl Default for TurnTracker {
    fn default() -> Self {
        Self::new()
    }
}
