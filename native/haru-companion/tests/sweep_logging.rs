//! Error frames must not echo a prompt or audio samples.

use haru_companion::backend::FakeBackend;
use haru_companion::engine::Engine;
use haru_companion::protocol::{self, ClientMessage, RawFrame};
use haru_companion::supervisor::SpyLauncher;

#[test]
fn error_frames_do_not_contain_the_prompt_or_samples() {
    let secret = "SECRET-NAME-9912 secret@example.com";
    let mut engine = Engine::new(
        FakeBackend::quiet(),
        SpyLauncher::default(),
        vec!["fake-haru".into()],
        true,
    );
    let start = ClientMessage::Start {
        language: "fr".into(),
        system_prompt: secret.into(),
        speak_first: false,
    }
    .encode()
    .unwrap();
    let mut buf = protocol::FrameBuf::default();
    let frames = buf.push(&start).unwrap();
    let mut blob = Vec::new();
    for frame in frames {
        for reply in engine.handle_raw(&frame) {
            blob.extend_from_slice(&reply);
        }
    }
    let bad = RawFrame {
        kind: protocol::PUSH,
        payload: vec![0u8; 16],
    };
    for reply in engine.handle_raw(&bad) {
        blob.extend_from_slice(&reply);
    }
    let text = String::from_utf8_lossy(&blob);
    assert!(!text.contains(secret), "prompt leaked into a socket reply");
    assert!(
        !text.contains("secret@example.com"),
        "address leaked into a socket reply"
    );
}
