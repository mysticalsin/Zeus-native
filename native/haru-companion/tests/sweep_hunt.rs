//! Reproduction tests for the external hunt against 583c3dcc.
//! Each test is named for the finding it locks.

use haru_companion::backend::{BackendEvent, UpstreamBackend};
use haru_companion::engine::Engine;
use haru_companion::protocol::{self, decode_client, ClientMessage, FrameBuf};
use haru_companion::serve::{bind_socket, serve_one};
use haru_companion::session::{
    ChildControl, SessionError, SessionHost, SessionState, FRAME_SAMPLES,
};
use haru_companion::supervisor::{
    apply, decide, ChildState, LaunchDecision, LaunchRequest, NoLaunchReason, SpyBinder,
    SpyLauncher, SpyNet, StdLauncher, Supervisor,
};
use haru_companion::upstream::{self, StartRequest, UpstreamMessage};
use haru_companion::watchdog::WatchdogReason;
use std::io::{Read, Write};
use std::os::unix::fs::PermissionsExt;
use std::os::unix::net::UnixStream;
use std::path::Path;
use std::time::{Duration, Instant};

extern "C" {
    fn kill(pid: i32, sig: i32) -> i32;
}

fn temp_dir(name: &str) -> std::path::PathBuf {
    let path = std::env::temp_dir().join(format!(
        "zeus-hunt-{name}-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    std::fs::create_dir_all(&path).unwrap();
    path
}

fn read_frame(stream: &mut UnixStream) -> (u8, Vec<u8>) {
    let mut header = [0u8; 5];
    stream.read_exact(&mut header).unwrap();
    let len = u32::from_le_bytes([header[1], header[2], header[3], header[4]]) as usize;
    let mut payload = vec![0u8; len];
    stream.read_exact(&mut payload).unwrap();
    (header[0], payload)
}

fn proc_alive(pid: u32) -> bool {
    Path::new(&format!("/proc/{pid}")).exists()
}

#[test]
fn hc02_a_model_must_be_a_directory() {
    let root = temp_dir("model");
    let file = root.join("weights.bin");
    std::fs::write(&file, b"not a directory").unwrap();
    let missing = root.join("missing-model");
    for model in [file, missing] {
        let decision = decide(&LaunchRequest {
            conversation_mode: true,
            python: Some(std::path::PathBuf::from("/bin/sleep")),
            model: Some(model),
            socket: Some(root.join("z.sock")),
            quantize: 8,
        });
        assert_eq!(
            decision,
            LaunchDecision::NoLaunch {
                reason: NoLaunchReason::MissingModel
            }
        );
        let mut processes = SpyLauncher::default();
        let mut sockets = SpyBinder::default();
        let mut net = SpyNet::default();
        assert!(apply(&decision, &mut processes, &mut sockets, &mut net).is_err());
        assert_eq!(processes.spawn_count(), 0);
    }
    let _ = std::fs::remove_dir_all(&root);
}

#[test]
fn hc03_a_quiet_client_stays_connected_and_disconnect_kills_the_child() {
    let path = temp_dir("quiet").join("z.sock");
    let listener = bind_socket(&path).unwrap();
    let (done_tx, done_rx) = std::sync::mpsc::channel();
    let server = std::thread::spawn(move || {
        let mut engine = Engine::new(
            haru_companion::backend::FakeBackend::quiet(),
            SpyLauncher::default(),
            vec!["fake-haru".into()],
            true,
        );
        let _ = serve_one(listener, &mut engine);
        let _ = done_tx.send((engine.session().clone(), engine.alive()));
    });
    let mut client = UnixStream::connect(&path).unwrap();
    client
        .set_read_timeout(Some(Duration::from_secs(2)))
        .unwrap();
    client
        .write_all(&ClientMessage::Hello { v: 1 }.encode().unwrap())
        .unwrap();
    let _ = read_frame(&mut client);
    client
        .write_all(
            &ClientMessage::Start {
                language: "en".into(),
                system_prompt: "hi".into(),
                speak_first: false,
            }
            .encode()
            .unwrap(),
        )
        .unwrap();
    let _ = read_frame(&mut client);
    let _ = read_frame(&mut client);
    std::thread::sleep(Duration::from_secs(4));
    assert!(
        done_rx.try_recv().is_err(),
        "a quiet client was disconnected by the read timeout"
    );
    drop(client);
    let (state, alive) = done_rx.recv_timeout(Duration::from_secs(2)).unwrap();
    assert!(state.is_terminal(), "disconnect left {state:?}");
    assert!(
        alive.is_empty(),
        "child still alive after disconnect: {alive:?}"
    );
    server.join().unwrap();
    let _ = std::fs::remove_file(&path);
}

#[test]
fn hc04_sigkill_is_reaped_and_finish_does_not_stream() {
    let mut host = SessionHost::new(StdLauncher::new(), vec!["/bin/sleep".into(), "30".into()]);
    host.begin_model_load().unwrap();
    let pid = host.pid().unwrap();
    unsafe { kill(pid as i32, 9) };
    std::thread::sleep(Duration::from_millis(20));
    let error = host.finish_model_load().unwrap_err();
    assert_eq!(error, SessionError::ProcessExited { code: -1 });
    assert_ne!(host.state(), &SessionState::Streaming);
    assert!(
        !host.ever_streaming(),
        "a killed child was allowed to stream"
    );
    assert!(
        host.alive().is_empty(),
        "zombie stayed in alive(): {:?}",
        host.alive()
    );
    assert!(
        !proc_alive(pid) || {
            let stat = std::fs::read_to_string(format!("/proc/{pid}/stat")).unwrap_or_default();
            !stat.contains(" Z ")
        }
    );
}

#[test]
fn hc05_kill_reaps_the_process_group() {
    let root = temp_dir("group");
    let script = root.join("parent.sh");
    let child_pid = root.join("child.pid");
    std::fs::write(
        &script,
        format!(
            "#!/bin/sh\n/bin/sleep 60 &\necho $! > {}\nwait\n",
            child_pid.display()
        ),
    )
    .unwrap();
    let mut mode = std::fs::metadata(&script).unwrap().permissions();
    mode.set_mode(0o755);
    std::fs::set_permissions(&script, mode).unwrap();
    let mut launcher = StdLauncher::new();
    let pid = launcher.spawn(&[script.display().to_string()]).unwrap();
    let deadline = Instant::now() + Duration::from_secs(2);
    while Instant::now() < deadline && !child_pid.exists() {
        std::thread::sleep(Duration::from_millis(10));
    }
    let grand = std::fs::read_to_string(&child_pid)
        .unwrap_or_default()
        .trim()
        .parse::<u32>()
        .unwrap_or(0);
    assert!(grand > 1, "grandchild did not start");
    launcher.kill(pid);
    let gone = Instant::now() + Duration::from_secs(2);
    while Instant::now() < gone && proc_alive(grand) {
        std::thread::sleep(Duration::from_millis(20));
    }
    assert!(
        !proc_alive(grand),
        "descendant {grand} survived kill of {pid}"
    );
    unsafe { kill(grand as i32, 9) };
    let _ = std::fs::remove_dir_all(&root);
}

#[test]
fn hc07_start_after_a_stall_restart_keeps_one_child() {
    let mut engine = Engine::new(
        haru_companion::backend::FakeBackend::new(vec![
            haru_companion::backend::ScriptStep::Stall { delay_ms: 2_000 },
        ]),
        SpyLauncher::default(),
        vec!["fake-haru".into()],
        true,
    );
    engine.begin_model_load().unwrap();
    engine.finish_model_load().unwrap();
    let _ = engine.push(&vec![0.0; FRAME_SAMPLES], 1);
    assert!(engine.trace().iter().any(|state| {
        matches!(
            state,
            SessionState::Failed(SessionError::WatchdogRestart {
                reason: WatchdogReason::Stall,
            })
        )
    }));
    let start = protocol::RawFrame {
        kind: protocol::START,
        payload: br#"{"language":"en","system_prompt":"hi","speak_first":false}"#.to_vec(),
    };
    let _ = engine.handle_raw(&start);
    assert_eq!(engine.alive().len(), 1, "restart START leaked a child");
}

#[test]
fn hc08_upstream_silence_stalls_within_two_seconds() {
    let (mut peer, stream) = UnixStream::pair().unwrap();
    peer.set_nonblocking(true).unwrap();
    let mut engine = Engine::new(
        UpstreamBackend::new(
            stream,
            StartRequest {
                language: "en".into(),
                system_prompt: String::new(),
                speak_first: false,
            },
        ),
        SpyLauncher::default(),
        Vec::new(),
        true,
    );
    engine.enter_streaming_without_spawn().unwrap();
    let started = Instant::now();
    std::thread::spawn(move || {
        std::thread::sleep(Duration::from_millis(2_500));
        let _ = peer.write_all(&[0x11, 0, 0, 0, 0]);
    });
    let _ = engine.push(&vec![0.0; FRAME_SAMPLES], 1);
    assert!(
        started.elapsed() < Duration::from_millis(2_300),
        "push blocked for {:?}",
        started.elapsed()
    );
    assert!(engine.underruns() >= 1, "stall did not count an underrun");
    assert!(
        engine.trace().iter().any(|state| {
            matches!(
                state,
                SessionState::Failed(SessionError::WatchdogRestart {
                    reason: WatchdogReason::Stall,
                })
            )
        }),
        "trace {:?}",
        engine.trace()
    );
}

#[test]
fn hc09_upstream_text_feeds_the_token_watchdog() {
    let (mut peer, stream) = UnixStream::pair().unwrap();
    let phrase = b"alpha beta gamma ";
    for _ in 0..8 {
        let framed = upstream::frame(0x12, phrase);
        peer.write_all(&framed).unwrap();
    }
    let mut engine = Engine::new(
        UpstreamBackend::new(
            stream,
            StartRequest {
                language: "en".into(),
                system_prompt: String::new(),
                speak_first: false,
            },
        ),
        SpyLauncher::default(),
        Vec::new(),
        true,
    );
    engine.enter_streaming_without_spawn().unwrap();
    for seq in 0..8u32 {
        let _ = engine.push(&vec![0.0; FRAME_SAMPLES], seq);
    }
    assert!(
        engine.trace().iter().any(|state| {
            matches!(
                state,
                SessionState::Failed(SessionError::WatchdogRestart {
                    reason: WatchdogReason::TokenLoop,
                })
            )
        }),
        "upstream TEXT did not restart: {:?}",
        engine.trace()
    );
}

struct FixedRead {
    data: Vec<u8>,
    at: usize,
}

impl Read for FixedRead {
    fn read(&mut self, buf: &mut [u8]) -> std::io::Result<usize> {
        if self.at >= self.data.len() {
            return Ok(0);
        }
        let n = buf.len().min(self.data.len() - self.at);
        buf[..n].copy_from_slice(&self.data[self.at..self.at + n]);
        self.at += n;
        Ok(n)
    }
}

impl Write for FixedRead {
    fn write(&mut self, data: &[u8]) -> std::io::Result<usize> {
        Ok(data.len())
    }
    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}

impl haru_companion::backend::ReadDeadline for FixedRead {
    fn arm_read_timeout(&self, _timeout: Duration) -> std::io::Result<()> {
        Ok(())
    }
}

#[test]
fn hc10_upstream_frame_is_capped_at_3200_samples() {
    let samples = 10_000usize;
    let payload_len = 8 + samples * 4;
    let mut data = Vec::new();
    data.push(0x11);
    data.extend_from_slice(&(payload_len as u32).to_le_bytes());
    data.extend_from_slice(&1u32.to_le_bytes());
    data.extend_from_slice(&1.0f32.to_le_bytes());
    data.extend(std::iter::repeat(0u8).take(samples * 4));
    let mut engine = Engine::new(
        UpstreamBackend::new(
            FixedRead { data, at: 0 },
            StartRequest {
                language: "en".into(),
                system_prompt: String::new(),
                speak_first: false,
            },
        ),
        SpyLauncher::default(),
        Vec::new(),
        false,
    );
    engine.enter_streaming_without_spawn().unwrap();
    match engine.push(&vec![0.0; FRAME_SAMPLES], 1) {
        Err(_) => {}
        Ok(frames) => assert_eq!(frames[0].samples.len(), FRAME_SAMPLES),
    }
    let _ = UpstreamMessage::Text(String::new());
    let _ = BackendEvent::SocketClosed;
}

#[test]
fn hc11_only_a_canonical_integer_version_is_one() {
    let msg = ClientMessage::Start {
        language: "fr".into(),
        system_prompt: "¡".into(),
        speak_first: true,
    };
    assert_eq!(decode_client(&msg.encode().unwrap()).unwrap(), msg);
    for body in [br#"{"v":1.0}"#.as_slice(), br#"{"v":1.9}"#, br#"{"v":01}"#] {
        let framed = protocol::frame(protocol::HELLO, body);
        assert!(
            decode_client(&framed).is_err(),
            "accepted {}",
            String::from_utf8_lossy(body)
        );
    }
    assert!(matches!(
        decode_client(&protocol::frame(protocol::HELLO, br#"{"v":1}"#)).unwrap(),
        ClientMessage::Hello { v: 1 }
    ));
    let _ = FrameBuf::default();
}

#[test]
fn hc12_deep_json_is_bad_json_not_an_abort() {
    let mut payload = String::from("1");
    for _ in 0..20_000 {
        payload = format!("{{\"a\":{payload}}}");
    }
    let framed = protocol::frame(protocol::START, payload.as_bytes());
    assert_eq!(
        decode_client(&framed).unwrap_err(),
        protocol::ProtocolError::BadJson
    );
}

#[test]
fn hc13_a_live_listener_is_not_unlinked() {
    let path = temp_dir("live").join("z.sock");
    let listener = bind_socket(&path).unwrap();
    let second = bind_socket(&path);
    assert!(second.is_err(), "second bind stole a live listener");
    assert_eq!(second.unwrap_err().kind(), std::io::ErrorKind::AddrInUse);
    let client = UnixStream::connect(&path).unwrap();
    let accepted = listener.accept();
    assert!(accepted.is_ok(), "original listener could not accept");
    drop(client);
    drop(listener);
    let _ = std::fs::remove_file(&path);
}

#[test]
fn hc15_binding_does_not_chmod_a_different_file() {
    let root = temp_dir("chmod");
    let victim = root.join("victim");
    std::fs::write(&victim, b"VICTIM").unwrap();
    let mut mode = std::fs::metadata(&victim).unwrap().permissions();
    mode.set_mode(0o644);
    std::fs::set_permissions(&victim, mode).unwrap();
    let socket = root.join("z.sock");
    let stop = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false));
    let stop_racer = std::sync::Arc::clone(&stop);
    let socket_racer = socket.clone();
    let victim_racer = victim.clone();
    let racer = std::thread::spawn(move || {
        while !stop_racer.load(std::sync::atomic::Ordering::Relaxed) {
            let _ = std::fs::remove_file(&socket_racer);
            let _ = std::os::unix::fs::symlink(&victim_racer, &socket_racer);
        }
    });
    let deadline = Instant::now() + Duration::from_millis(250);
    while Instant::now() < deadline {
        if let Ok(listener) = bind_socket(&socket) {
            drop(listener);
        }
    }
    stop.store(true, std::sync::atomic::Ordering::Relaxed);
    racer.join().unwrap();
    let mode = std::fs::symlink_metadata(&victim)
        .unwrap()
        .permissions()
        .mode()
        & 0o777;
    assert_eq!(std::fs::read(&victim).unwrap(), b"VICTIM");
    assert_eq!(mode, 0o644, "bind_socket changed the victim mode");
    let _ = std::fs::remove_dir_all(&root);
}

#[test]
fn hc18_a_model_directory_may_contain_the_word_reference() {
    let root = temp_dir("ref");
    let model = root.join("my-reference-model");
    std::fs::create_dir(&model).unwrap();
    let code = haru_companion::run([
        "serve".into(),
        "--socket".into(),
        root.join("z.sock").display().to_string(),
        "--python".into(),
        "/no/such/haru-python".into(),
        "--model".into(),
        model.display().to_string(),
    ]);
    assert_ne!(
        code, 2,
        "a directory named my-reference-model was refused as reference_path"
    );
    let _ = std::fs::remove_dir_all(&root);
}

#[test]
fn hc19_restart_budget_follows_wall_time_not_advance() {
    let mut supervisor = Supervisor::new(SpyLauncher::default(), vec!["python3".into()]);
    supervisor.start().unwrap();
    for _ in 0..3 {
        supervisor.on_exit(1);
    }
    assert_eq!(supervisor.state(), &ChildState::Ready);
    let spawns = supervisor.spawn_count();
    std::thread::sleep(Duration::from_secs(2));
    supervisor.advance(10 * 60 * 1000);
    supervisor.on_exit(1);
    assert_eq!(
        supervisor.state(),
        &ChildState::Stopped { failed: true },
        "advance() reopened the restart budget"
    );
    assert_eq!(supervisor.spawn_count(), spawns);
    assert!(supervisor.alive().is_empty());
}
