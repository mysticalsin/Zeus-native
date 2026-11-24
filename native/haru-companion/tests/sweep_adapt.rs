//! Inspector ADAPT on the companion: model audio, talk locales, app-support path.

use haru_companion::protocol::{self, decode_client, ClientMessage, ServerMessage};
use haru_companion::session::FRAME_SAMPLES;
use haru_companion::supervisor::{haru_socket_path, model_socket, private_socket};
use haru_companion::upstream;
use std::io::{Read, Write};
use std::os::unix::fs::PermissionsExt;
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::PathBuf;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

fn scratch(name: &str) -> PathBuf {
    let path = std::env::temp_dir().join(format!(
        "zeus-adapt-{name}-{}-{}",
        std::process::id(),
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    std::fs::create_dir_all(&path).unwrap();
    let mut perms = std::fs::metadata(&path).unwrap().permissions();
    perms.set_mode(0o700);
    std::fs::set_permissions(&path, perms).unwrap();
    path
}

fn read_frame(stream: &mut UnixStream) -> (u8, Vec<u8>) {
    let mut header = [0u8; 5];
    stream.read_exact(&mut header).unwrap();
    let len = u32::from_le_bytes(header[1..5].try_into().unwrap()) as usize;
    let mut payload = vec![0u8; len];
    stream.read_exact(&mut payload).unwrap();
    (header[0], payload)
}

#[test]
fn a_talk_locale_is_canonical_english_or_french() {
    let payload = br#"{"language":"en-US","system_prompt":"hi","speak_first":false}"#;
    let framed = protocol::frame(protocol::START, payload);
    let message = decode_client(&framed).unwrap();
    match message {
        ClientMessage::Start { language, .. } => assert_eq!(language, "en"),
        other => panic!("{other:?}"),
    }
    let encoded = ClientMessage::Start {
        language: "fr-CA".into(),
        system_prompt: String::new(),
        speak_first: false,
    }
    .encode()
    .unwrap();
    match decode_client(&encoded).unwrap() {
        ClientMessage::Start { language, .. } => assert_eq!(language, "fr"),
        other => panic!("{other:?}"),
    }
    let rejected = protocol::frame(protocol::START, br#"{"language":"ja"}"#);
    assert!(decode_client(&rejected).is_err());
}

#[test]
fn the_public_socket_returns_model_audio_not_silence() {
    let root = scratch("hear");
    std::fs::create_dir(root.join("model")).unwrap();
    let public = root.join("zeus.sock");
    let model_path = model_socket(&private_socket(&public));
    let listener = UnixListener::bind(&model_path).unwrap();
    std::thread::spawn(move || {
        let (mut stream, _) = listener.accept().unwrap();
        stream
            .set_read_timeout(Some(Duration::from_millis(800)))
            .unwrap();
        let mut buf = [0u8; 65536];
        let deadline = Instant::now() + Duration::from_secs(2);
        while Instant::now() < deadline {
            match stream.read(&mut buf) {
                Ok(0) | Err(_) => break,
                Ok(_) => {}
            }
        }
        let mut payload = Vec::new();
        payload.extend_from_slice(&1u32.to_le_bytes());
        payload.extend_from_slice(&1.0f32.to_le_bytes());
        for _ in 0..6400 {
            payload.extend_from_slice(&0.5f32.to_le_bytes());
        }
        let frame = upstream::frame(upstream::FRAME, &payload);
        let _ = stream.write_all(&frame);
    });
    let public_for_server = public.clone();
    let model_dir = root.join("model");
    let server = std::thread::spawn(move || {
        haru_companion::run([
            "serve".into(),
            "--socket".into(),
            public_for_server.display().to_string(),
            "--python".into(),
            "/bin/sleep".into(),
            "--model".into(),
            model_dir.display().to_string(),
        ])
    });
    let deadline = Instant::now() + Duration::from_secs(2);
    while Instant::now() < deadline && !public.exists() {
        std::thread::sleep(Duration::from_millis(10));
    }
    let mut client = UnixStream::connect(&public).unwrap();
    client
        .set_read_timeout(Some(Duration::from_secs(3)))
        .unwrap();
    client
        .write_all(&ClientMessage::Hello { v: 1 }.encode().unwrap())
        .unwrap();
    let _ = read_frame(&mut client);
    client
        .write_all(
            &ClientMessage::Start {
                language: "en".into(),
                system_prompt: String::new(),
                speak_first: false,
            }
            .encode()
            .unwrap(),
        )
        .unwrap();
    let _ = read_frame(&mut client);
    let _ = read_frame(&mut client);
    let samples = vec![0.0f32; FRAME_SAMPLES];
    client
        .write_all(&ClientMessage::Push { seq: 1, samples }.encode().unwrap())
        .unwrap();
    let mut heard = None;
    for _ in 0..6 {
        let (kind, payload) = read_frame(&mut client);
        if kind != protocol::FRAME {
            continue;
        }
        let message = protocol::decode_server_frame(&protocol::RawFrame { kind, payload }).unwrap();
        if let ServerMessage::Frame { samples, .. } = message {
            heard = Some(samples);
            break;
        }
    }
    let samples = heard.expect("no model frame");
    assert!(
        samples.iter().any(|sample| *sample != 0.0),
        "public socket answered with silence"
    );
    drop(client);
    let _ = server.join();
    let _ = std::fs::remove_dir_all(&root);
}

#[test]
fn the_app_support_socket_sits_in_a_0700_haru_directory() {
    let app = scratch("app").join("Application Support");
    std::fs::create_dir_all(&app).unwrap();
    let socket = haru_socket_path(&app);
    assert_eq!(
        socket,
        app.join("Zeus").join("haru").join("zeus.sock"),
        "zeus.sock must live in Application Support/Zeus/haru"
    );
    let listener = haru_companion::serve::bind_socket(&socket).unwrap();
    let parent = socket.parent().unwrap();
    let mode = std::fs::symlink_metadata(parent)
        .unwrap()
        .permissions()
        .mode()
        & 0o777;
    assert_eq!(mode, 0o700, "haru directory must be 0700");
    assert_eq!(private_socket(&socket).parent(), Some(parent));
    assert_eq!(
        model_socket(&private_socket(&socket)).parent(),
        Some(parent)
    );
    drop(listener);
    let _ = std::fs::remove_dir_all(app.parent().unwrap());
}

#[test]
fn off_linux_identity_keeps_ctime_nanoseconds() {
    let source = include_str!("../src/serve.rs");
    assert!(
        !source.contains("ctime_nsec: 0"),
        "off-Linux identity drops ctime nanoseconds"
    );
}

#[test]
fn parent_death_without_prctl_is_a_known_limit() {
    let source = include_str!("../src/supervisor.rs");
    assert!(
        source.contains("Known limit"),
        "macOS parent death is not recorded as a known limit"
    );
    #[cfg(target_os = "linux")]
    assert!(source.contains("PR_SET_PDEATHSIG") || source.contains("prctl"));
}
