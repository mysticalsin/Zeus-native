use haru_companion::backend::FakeBackend;
use haru_companion::engine::Engine;
use haru_companion::protocol::{self, ServerMessage};
use haru_companion::serve::{bind_socket, serve_one};
use haru_companion::session::FRAME_SAMPLES;
use haru_companion::supervisor::SpyLauncher;
use std::io::{Read, Write};
use std::os::unix::fs::PermissionsExt;
use std::os::unix::net::UnixStream;
use std::time::{SystemTime, UNIX_EPOCH};

fn read_frame(stream: &mut UnixStream) -> (u8, Vec<u8>) {
    let mut header = [0u8; 5];
    stream.read_exact(&mut header).unwrap();
    let kind = header[0];
    let len = u32::from_le_bytes([header[1], header[2], header[3], header[4]]) as usize;
    let mut payload = vec![0u8; len];
    stream.read_exact(&mut payload).unwrap();
    (kind, payload)
}

#[test]
fn requested_session_round_trips_on_a_private_socket() {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let root = std::env::temp_dir().join(format!("zeus-haru-test-{}-{nanos}", std::process::id()));
    std::fs::create_dir_all(&root).unwrap();
    let mut perms = std::fs::metadata(&root).unwrap().permissions();
    perms.set_mode(0o700);
    std::fs::set_permissions(&root, perms).unwrap();
    let path = root.join("zeus.sock");
    let listener = bind_socket(&path).unwrap();
    let mode = std::fs::metadata(&path).unwrap().permissions().mode() & 0o777;
    assert_eq!(mode, 0o600);
    let path_for_client = path.clone();
    let server = std::thread::spawn(move || {
        let mut engine = Engine::new(
            FakeBackend::quiet(),
            SpyLauncher::default(),
            vec!["fake-haru".into()],
            true,
        );
        serve_one(listener, &mut engine).unwrap();
        engine.spawn_count()
    });
    let mut client = UnixStream::connect(&path_for_client).unwrap();
    client
        .set_read_timeout(Some(std::time::Duration::from_secs(3)))
        .unwrap();
    client
        .write_all(&protocol::ClientMessage::Hello { v: 1 }.encode().unwrap())
        .unwrap();
    let (kind, payload) = read_frame(&mut client);
    assert_eq!(kind, protocol::HELLO_ACK);
    let ack = protocol::decode_server_frame(&protocol::RawFrame { kind, payload }).unwrap();
    match ack {
        ServerMessage::HelloAck {
            sample_rate,
            frame_samples,
            ..
        } => assert_eq!((sample_rate, frame_samples), (24_000, 3200)),
        other => panic!("{other:?}"),
    }
    let start = protocol::ClientMessage::Start {
        language: "en".into(),
        system_prompt: "hello".into(),
        speak_first: false,
    }
    .encode()
    .unwrap();
    client.write_all(&start).unwrap();
    let _starting = read_frame(&mut client);
    let (kind, payload) = read_frame(&mut client);
    assert_eq!(kind, protocol::STATE);
    let state = protocol::decode_server_frame(&protocol::RawFrame { kind, payload }).unwrap();
    match state {
        ServerMessage::State { session, .. } => assert_eq!(session, "streaming"),
        other => panic!("{other:?}"),
    }
    let push = protocol::ClientMessage::Push {
        seq: 4,
        samples: vec![0.25; FRAME_SAMPLES],
    }
    .encode()
    .unwrap();
    client.write_all(&push).unwrap();
    let (kind, payload) = read_frame(&mut client);
    assert_eq!(kind, protocol::FRAME);
    let frame = protocol::decode_server_frame(&protocol::RawFrame { kind, payload }).unwrap();
    match frame {
        ServerMessage::Frame { seq, samples, .. } => {
            assert_eq!(seq, 4);
            assert_eq!(samples.len(), FRAME_SAMPLES);
        }
        other => panic!("{other:?}"),
    }
    client
        .write_all(&protocol::ClientMessage::Close.encode().unwrap())
        .unwrap();
    let _closing = read_frame(&mut client);
    let (kind, payload) = read_frame(&mut client);
    let closed = protocol::decode_server_frame(&protocol::RawFrame { kind, payload }).unwrap();
    match closed {
        ServerMessage::State { session, .. } => assert_eq!(session, "closed"),
        other => panic!("{other:?}"),
    }
    drop(client);
    let spawns = server.join().unwrap();
    assert_eq!(spawns, 1);
    let _ = std::fs::remove_dir_all(&root);
}
