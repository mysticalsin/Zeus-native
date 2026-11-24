//! Spawn failure must not leave the session stuck in `Starting`.

use haru_companion::backend::FakeBackend;
use haru_companion::engine::Engine;
use haru_companion::protocol::{self, RawFrame};
use haru_companion::session::{ChildControl, SessionError, SessionHost, SessionState};
use std::io;

struct FailSpawn;

impl ChildControl for FailSpawn {
    fn spawn(&mut self, _argv: &[String]) -> io::Result<u32> {
        Err(io::Error::other("python is not executable"))
    }

    fn kill(&mut self, _pid: u32) {}

    fn alive(&self) -> Vec<u32> {
        Vec::new()
    }

    fn spawn_count(&self) -> u32 {
        0
    }
}

#[test]
fn spawn_failure_fails_the_session_instead_of_staying_in_starting() {
    let mut host = SessionHost::new(FailSpawn, vec!["missing-python".into()]);
    let error = host.begin_model_load().unwrap_err();
    assert_eq!(error, SessionError::ProcessExited { code: -1 });
    assert_eq!(
        host.state(),
        &SessionState::Failed(SessionError::ProcessExited { code: -1 })
    );
    assert!(host.alive().is_empty());
    assert!(host.finish_model_load().is_err());
    assert_ne!(host.state(), &SessionState::Streaming);
}

#[test]
fn socket_start_reports_process_exited_when_spawn_fails() {
    let mut engine = Engine::new(
        FakeBackend::quiet(),
        FailSpawn,
        vec!["missing-python".into()],
        true,
    );
    let frame = RawFrame {
        kind: protocol::START,
        payload: br#"{"language":"en","system_prompt":"hi","speak_first":false}"#.to_vec(),
    };
    let replies = engine.handle_raw(&frame);
    let blob = replies.concat();
    let text = String::from_utf8_lossy(&blob);
    assert!(
        text.contains("process_exited"),
        "client should see process_exited, got {text}"
    );
    assert!(
        !text.contains("illegal_transition"),
        "a spawn failure is not an illegal transition, got {text}"
    );
    assert!(matches!(
        engine.session(),
        SessionState::Failed(SessionError::ProcessExited { code: -1 })
    ));
}
