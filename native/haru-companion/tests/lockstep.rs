use haru_companion::backend::{FakeBackend, ScriptStep};
use haru_companion::engine::Engine;
use haru_companion::session::{SessionError, SessionState, FRAME_SAMPLES};
use haru_companion::supervisor::SpyLauncher;

fn tone(value: f32) -> Vec<f32> {
    vec![value; FRAME_SAMPLES]
}

#[test]
fn each_push_gets_exactly_one_frame() {
    let script = (0..5)
        .map(|index| ScriptStep::Frame {
            fill: 0.1 * index as f32,
            text: String::new(),
            delay_ms: 0,
            step_ms: 4.0,
        })
        .collect();
    let mut engine = Engine::new(
        FakeBackend::new(script),
        SpyLauncher::default(),
        vec!["fake".into()],
        true,
    );
    engine.begin_model_load().unwrap();
    engine.finish_model_load().unwrap();
    for seq in 0..5u32 {
        let frames = engine.push(&tone(0.01), seq).unwrap();
        assert_eq!(frames.len(), 1);
        assert_eq!(frames[0].seq, seq);
        assert_eq!(frames[0].samples.len(), FRAME_SAMPLES);
        assert_eq!(engine.session(), &SessionState::Streaming);
    }
}

#[test]
fn late_model_frame_yields_silence_and_counts_underrun() {
    let mut engine = Engine::new(
        FakeBackend::new(vec![ScriptStep::Frame {
            fill: 0.5,
            text: String::new(),
            delay_ms: 134,
            step_ms: 134.0,
        }]),
        SpyLauncher::default(),
        vec!["fake".into()],
        true,
    );
    engine.begin_model_load().unwrap();
    engine.finish_model_load().unwrap();
    let frames = engine.push(&tone(0.2), 3).unwrap();
    assert_eq!(frames.len(), 1);
    assert!(frames[0].samples.iter().all(|sample| *sample == 0.0));
    assert_eq!(engine.underruns(), 1);
    assert_eq!(engine.session(), &SessionState::Streaming);
    let error = engine.push(&vec![0.0; 3199], 4).unwrap_err();
    assert_eq!(
        error,
        SessionError::BadFrameSize {
            expected: FRAME_SAMPLES,
            got: 3199
        }
    );
    assert_eq!(engine.session(), &SessionState::Streaming);
    assert_eq!(engine.exchanges(), 1);
}

#[test]
fn selftest_fake_session_spawns_nothing() {
    let report = haru_companion::selftest_report(10_000);
    assert_eq!(report.frames, 10_000);
    assert_eq!(report.spawned, 0);
    assert_eq!(report.binds, 0);
    assert_eq!(report.network_attempts, 0);
    assert_eq!(report.underruns, 0);
    assert!(report.rss_bytes > 0);
    assert!(report.overhead_p50_ms >= 0.0);
    assert!(report.overhead_p95_ms >= report.overhead_p50_ms);
}
