use haru_companion::backend::{FakeBackend, ScriptStep};
use haru_companion::engine::Engine;
use haru_companion::session::{SessionError, SessionState, FRAME_SAMPLES};
use haru_companion::supervisor::SpyLauncher;
use haru_companion::watchdog::{
    Observation, Turn, Watchdog, WatchdogConfig, WatchdogReason, WdState,
};

fn tone(value: f32) -> Vec<f32> {
    vec![value; FRAME_SAMPLES]
}

fn streaming(script: Vec<ScriptStep>) -> Engine<FakeBackend, SpyLauncher> {
    let mut engine = Engine::new(
        FakeBackend::new(script),
        SpyLauncher::default(),
        vec!["fake-haru".into()],
        true,
    );
    engine.begin_model_load().unwrap();
    engine.finish_model_load().unwrap();
    assert_eq!(engine.session(), &SessionState::Streaming);
    engine
}

fn failed_restart(trace: &[SessionState], reason: WatchdogReason) -> bool {
    trace.iter().any(|state| {
        matches!(
            state,
            SessionState::Failed(SessionError::WatchdogRestart { reason: got }) if *got == reason
        )
    })
}

#[test]
fn loop_in_text_restarts_at_next_idle() {
    let mut watchdog = Watchdog::new(WatchdogConfig::default());
    let text = "alpha beta gamma ".repeat(4);
    let pending = watchdog.observe_text(&text, Turn::Model);
    assert_eq!(pending, WdState::Pending);
    assert_eq!(watchdog.reason(), Some(WatchdogReason::TokenLoop));
    let mut idle = Observation::quiet();
    idle.turn = Turn::Idle;
    idle.loop_found = None;
    assert_eq!(watchdog.next(&idle), WdState::Restart);
}

#[test]
fn stall_over_2s_restarts_immediately() {
    let mut watchdog = Watchdog::new(WatchdogConfig::default());
    let mut under = Observation::quiet();
    under.stall_ms = 1_999;
    under.turn = Turn::Model;
    assert_eq!(watchdog.next(&under), WdState::Ok);
    let mut over = Observation::quiet();
    over.stall_ms = 2_000;
    over.turn = Turn::Model;
    assert_eq!(watchdog.next(&over), WdState::Restart);
    assert_eq!(watchdog.reason(), Some(WatchdogReason::Stall));
    let mut quiet = Watchdog::new(WatchdogConfig::default());
    let mut idle_stall = Observation::quiet();
    idle_stall.stall_ms = 5_000;
    idle_stall.streaming = false;
    assert_eq!(quiet.next(&idle_stall), WdState::Ok);
}

#[test]
fn memory_over_limit_restarts_immediately() {
    let mut watchdog = Watchdog::new(WatchdogConfig::default());
    let mut at_limit = Observation::quiet();
    at_limit.mem_gb = Some(14.0);
    assert_eq!(watchdog.next(&at_limit), WdState::Ok);
    let mut over = Observation::quiet();
    over.mem_gb = Some(14.01);
    over.turn = Turn::Model;
    assert_eq!(watchdog.next(&over), WdState::Restart);
    assert_eq!(watchdog.reason(), Some(WatchdogReason::Memory));
}

#[test]
fn latency_p95_over_120ms_for_30s_restarts_immediately() {
    let mut watchdog = Watchdog::new(WatchdogConfig::default());
    for _ in 0..224 {
        let mut sample = Observation::quiet();
        sample.step_ms = 121.0;
        assert_eq!(watchdog.next(&sample), WdState::Ok);
    }
    let mut last = Observation::quiet();
    last.step_ms = 121.0;
    assert_eq!(watchdog.next(&last), WdState::Restart);
    assert_eq!(watchdog.reason(), Some(WatchdogReason::Latency));
}

#[test]
fn cooldown_blocks_restart_storm() {
    let config = WatchdogConfig {
        cooldown_frames: 3,
        ..WatchdogConfig::default()
    };
    let mut watchdog = Watchdog::new(config);
    let mut hot = Observation::quiet();
    hot.mem_gb = Some(20.0);
    assert_eq!(watchdog.next(&hot), WdState::Restart);
    watchdog.restarted();
    assert_eq!(watchdog.state(), WdState::Cooldown);
    assert_eq!(watchdog.next(&hot), WdState::Cooldown);
    assert_eq!(watchdog.next(&Observation::quiet()), WdState::Cooldown);
    assert_eq!(watchdog.next(&Observation::quiet()), WdState::Ok);
    assert_eq!(watchdog.next(&hot), WdState::Restart);
}

#[test]
fn scripted_faults_restart_cleanly_without_orphans() {
    let phrase = "alpha beta gamma ".repeat(4);
    let mut loop_engine = streaming(vec![ScriptStep::Frame {
        fill: 0.2,
        text: phrase,
        delay_ms: 0,
        step_ms: 1.0,
    }]);
    loop_engine.push(&tone(0.1), 0).unwrap();
    assert!(
        failed_restart(loop_engine.trace(), WatchdogReason::TokenLoop)
            || loop_engine.session() == &SessionState::Streaming
    );
    for index in 1..7 {
        loop_engine.push(&tone(0.0), index).unwrap();
    }
    assert!(failed_restart(
        loop_engine.trace(),
        WatchdogReason::TokenLoop
    ));
    assert_eq!(loop_engine.session(), &SessionState::Idle);
    assert_eq!(loop_engine.alive().len(), 1);

    let mut stall = streaming(vec![ScriptStep::Stall { delay_ms: 2_000 }]);
    let old = stall.alive()[0];
    let frames = stall.push(&tone(0.0), 1).unwrap();
    assert_eq!(frames.len(), 1);
    assert!(frames[0].samples.iter().all(|sample| *sample == 0.0));
    assert_eq!(stall.underruns(), 1);
    assert!(failed_restart(stall.trace(), WatchdogReason::Stall));
    assert!(!stall.alive().contains(&old));
    assert_eq!(stall.alive().len(), 1);
    assert_eq!(stall.session(), &SessionState::Idle);

    let mut crash = streaming(vec![ScriptStep::Exit { code: 7 }]);
    let old = crash.alive()[0];
    let error = crash.push(&tone(0.1), 1).unwrap_err();
    assert_eq!(error, SessionError::ProcessExited { code: 7 });
    assert!(crash.trace().iter().any(|state| {
        matches!(
            state,
            SessionState::Failed(SessionError::ProcessExited { code: 7 })
        )
    }));
    assert!(!crash.alive().contains(&old));
    assert_eq!(crash.alive().len(), 1);
    assert_eq!(crash.session(), &SessionState::Idle);

    let mut garbage = streaming(
        (0..23)
            .map(|_| ScriptStep::Noise {
                delay_ms: 0,
                step_ms: 1.0,
            })
            .collect(),
    );
    for index in 0..23 {
        garbage.push(&tone(0.1), index).unwrap();
    }
    for index in 23..29 {
        garbage.push(&tone(0.0), index).unwrap();
    }
    assert!(failed_restart(garbage.trace(), WatchdogReason::Garbage));
    assert_eq!(garbage.session(), &SessionState::Idle);
    assert_eq!(garbage.alive().len(), 1);

    let mut memory = streaming(Vec::new());
    let old = memory.alive()[0];
    memory.report_memory_gb(15.0);
    assert!(failed_restart(memory.trace(), WatchdogReason::Memory));
    assert!(!memory.alive().contains(&old));
    assert_eq!(memory.session(), &SessionState::Idle);
}

#[test]
fn socket_close_and_start_timeout_are_distinct() {
    let mut closed = streaming(vec![ScriptStep::SocketClosed]);
    let old = closed.alive()[0];
    let error = closed.push(&tone(0.2), 1).unwrap_err();
    assert_eq!(error, SessionError::SocketClosed);
    assert!(!closed.alive().contains(&old));
    assert_eq!(closed.session(), &SessionState::Idle);

    let mut slow = Engine::new(
        FakeBackend::quiet(),
        SpyLauncher::default(),
        vec!["fake".into()],
        true,
    );
    slow.set_start_timeout_ms(1_000);
    slow.begin_model_load().unwrap();
    let old = slow.alive()[0];
    assert!(!slow.ever_streaming());
    slow.advance(1_000);
    assert!(slow
        .trace()
        .iter()
        .any(|state| { matches!(state, SessionState::Failed(SessionError::StartTimeout)) }));
    assert!(!slow.alive().contains(&old));
    assert!(!slow.ever_streaming());
    assert_ne!(slow.session(), &SessionState::Streaming);
    assert!(slow.finish_model_load().is_err());
}
