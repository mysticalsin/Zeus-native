//! Close and start must not leak a child, including when the client vanishes.

use haru_companion::backend::FakeBackend;
use haru_companion::engine::Engine;
use haru_companion::protocol::{self, ServerMessage};
use haru_companion::serve::{bind_socket, serve_one};
use haru_companion::session::{SessionError, SessionHost, SessionState};
use haru_companion::supervisor::SpyLauncher;
use std::io::{Read, Write};
use std::os::unix::fs::PermissionsExt;
use std::os::unix::net::UnixStream;
use std::time::{SystemTime, UNIX_EPOCH};

fn scratch(name: &str) -> std::path::PathBuf {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let root =
        std::env::temp_dir().join(format!("zeus-haru-{name}-{}-{nanos}", std::process::id()));
    std::fs::create_dir_all(&root).unwrap();
    let mut perms = std::fs::metadata(&root).unwrap().permissions();
    perms.set_mode(0o700);
    std::fs::set_permissions(&root, perms).unwrap();
    root.join("zeus.sock")
}

#[test]
fn replacing_a_live_session_kills_the_previous_child() {
    let mut host = SessionHost::new(SpyLauncher::default(), vec!["fake-haru".into()]);
    host.begin_model_load().unwrap();
    let first = host.pid().unwrap();
    host.spawn_fresh_idle().unwrap();
    assert_eq!(host.alive().len(), 1, "fresh idle leaked pid {first}");
    assert!(
        !host.alive().contains(&first),
        "pid {first} still alive after a new session"
    );
    let second = host.pid().unwrap();
    host.begin_model_load().unwrap();
    assert_eq!(host.alive(), vec![second]);
    assert_eq!(host.spawn_count(), 2);
}

#[test]
fn interleaved_close_and_start_never_leaks_a_child() {
    for step in 0..2_000u32 {
        let mut host = SessionHost::new(SpyLauncher::default(), vec!["fake-haru".into()]);
        let mut rng = step.wrapping_add(1);
        for _ in 0..24 {
            rng = rng.wrapping_mul(1664525).wrapping_add(1013904223);
            match rng % 5 {
                0 => {
                    let _ = host.begin_model_load();
                }
                1 => {
                    let _ = host.finish_model_load();
                }
                2 => {
                    let _ = host.close();
                }
                3 => {
                    let _ = host.fail(SessionError::SocketClosed);
                }
                _ => {
                    let _ = host.spawn_fresh_idle();
                }
            }
            assert!(
                host.alive().len() <= 1,
                "step {step} leaked children {:?}",
                host.alive()
            );
        }
    }
}

#[test]
fn close_after_a_restart_kills_the_fresh_child() {
    let mut host = SessionHost::new(SpyLauncher::default(), vec!["fake-haru".into()]);
    host.begin_model_load().unwrap();
    host.finish_model_load().unwrap();
    host.fail(SessionError::SocketClosed).unwrap();
    host.spawn_fresh_idle().unwrap();
    assert_eq!(host.state(), &SessionState::Idle);
    assert_eq!(host.alive().len(), 1);
    host.close().unwrap();
    assert_eq!(host.state(), &SessionState::Closed);
    assert!(
        host.alive().is_empty(),
        "close from the restarted idle session left {:?}",
        host.alive()
    );
}

#[test]
fn client_drop_without_close_kills_the_child() {
    let path = scratch("drop");
    let listener = bind_socket(&path).unwrap();
    let server = std::thread::spawn(move || {
        let mut engine = Engine::new(
            FakeBackend::quiet(),
            SpyLauncher::default(),
            vec!["fake-haru".into()],
            true,
        );
        serve_one(listener, &mut engine).unwrap();
        (engine.alive(), engine.session().clone())
    });
    let mut client = UnixStream::connect(&path).unwrap();
    client
        .set_read_timeout(Some(std::time::Duration::from_secs(3)))
        .unwrap();
    client
        .write_all(&protocol::ClientMessage::Hello { v: 1 }.encode().unwrap())
        .unwrap();
    let mut header = [0u8; 5];
    client.read_exact(&mut header).unwrap();
    let len = u32::from_le_bytes([header[1], header[2], header[3], header[4]]) as usize;
    let mut payload = vec![0u8; len];
    client.read_exact(&mut payload).unwrap();
    client
        .write_all(
            &protocol::ClientMessage::Start {
                language: "en".into(),
                system_prompt: "hi".into(),
                speak_first: false,
            }
            .encode()
            .unwrap(),
        )
        .unwrap();
    // Drain the two state frames so the server has finished START, then vanish.
    for _ in 0..2 {
        client.read_exact(&mut header).unwrap();
        let len = u32::from_le_bytes([header[1], header[2], header[3], header[4]]) as usize;
        let mut payload = vec![0u8; len];
        client.read_exact(&mut payload).unwrap();
        let state = protocol::decode_server_frame(&protocol::RawFrame {
            kind: header[0],
            payload,
        })
        .unwrap();
        if let ServerMessage::State { session, .. } = state {
            let _ = session;
        }
    }
    drop(client);
    let (alive, state) = server.join().unwrap();
    assert!(
        alive.is_empty(),
        "child still alive after the client dropped: {alive:?}"
    );
    assert!(state.is_terminal(), "session stayed {state:?}");
    let _ = std::fs::remove_file(&path);
}
