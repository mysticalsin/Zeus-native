//! Watchdog samples must be real measurements, not stand-ins or silence.

use haru_companion::backend::{FakeBackend, ScriptStep};
use haru_companion::engine::Engine;
use haru_companion::session::{SessionError, SessionState, FRAME_SAMPLES};
use haru_companion::supervisor::SpyLauncher;
use haru_companion::watchdog::{Observation, Watchdog, WatchdogConfig, WdState};

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
    engine
}

#[test]
fn a_memory_report_does_not_fill_the_latency_window() {
    let script = (0..224)
        .map(|_| ScriptStep::Frame {
            fill: 0.1,
            text: String::new(),
            delay_ms: 0,
            step_ms: 121.0,
        })
        .collect();
    let mut engine = streaming(script);
    for index in 0..224u32 {
        engine.push(&tone(0.1), index).unwrap();
    }
    assert_eq!(engine.session(), &SessionState::Streaming);
    engine.report_memory_gb(1.0);
    assert_eq!(
        engine.session(),
        &SessionState::Streaming,
        "a 1 GB report must not complete a latency window"
    );
    assert!(
        !engine.trace().iter().any(|state| {
            matches!(
                state,
                SessionState::Failed(SessionError::WatchdogRestart { .. })
            )
        }),
        "memory report tripped a watchdog restart: {:?}",
        engine.trace()
    );
}

#[test]
fn non_finite_step_time_restarts_immediately() {
    let mut watchdog = Watchdog::new(WatchdogConfig::default());
    let mut sample = Observation::quiet();
    sample.step_ms = f32::NAN;
    assert_eq!(watchdog.next(&sample), WdState::Restart);
    let mut infinity = Watchdog::new(WatchdogConfig::default());
    let mut sample = Observation::quiet();
    sample.step_ms = f32::INFINITY;
    assert_eq!(infinity.next(&sample), WdState::Restart);
}

#[test]
fn a_late_garbage_frame_still_counts() {
    let mut script = Vec::new();
    for _ in 0..22 {
        script.push(ScriptStep::Noise {
            delay_ms: 0,
            step_ms: 1.0,
        });
    }
    script.push(ScriptStep::Noise {
        delay_ms: 134,
        step_ms: 1.0,
    });
    for _ in 0..8 {
        script.push(ScriptStep::Frame {
            fill: 0.0,
            text: String::new(),
            delay_ms: 0,
            step_ms: 1.0,
        });
    }
    let mut engine = streaming(script);
    for index in 0..31u32 {
        let _ = engine.push(&tone(0.0), index);
    }
    assert!(
        engine.trace().iter().any(|state| {
            matches!(
                state,
                SessionState::Failed(SessionError::WatchdogRestart {
                    reason: haru_companion::watchdog::WatchdogReason::Garbage,
                })
            )
        }),
        "late garbage was dropped from the run: {:?}",
        engine.trace()
    );
}
