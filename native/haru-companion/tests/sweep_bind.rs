//! Bind window, parent mode, and a child that replaces the socket.

use haru_companion::backend::FakeBackend;
use haru_companion::engine::Engine;
use haru_companion::protocol::{decode_server, ServerMessage};
use haru_companion::serve::{
    bind_socket, current_uid, listener_matches, peer_uid, serve_one_with, unlink_if_ours, FixedPeer,
    OsPeer, PeerCheck,
};
use haru_companion::supervisor::{decide, serve_child_argv, LaunchDecision, LaunchRequest};
use std::io::Read;
use std::os::unix::fs::PermissionsExt;
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

extern "C" {
    fn umask(mask: u32) -> u32;
}

fn scratch(name: &str) -> PathBuf {
    let path = std::env::temp_dir().join(format!(
        "zeus-bind-{name}-{}-{}",
        std::process::id(),
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    std::fs::create_dir_all(&path).unwrap();
    path
}

fn mode(path: &std::path::Path) -> u32 {
    std::fs::symlink_metadata(path).unwrap().permissions().mode() & 0o777
}

fn set_mode(path: &std::path::Path, bits: u32) {
    let mut perms = std::fs::metadata(path).unwrap().permissions();
    perms.set_mode(bits);
    std::fs::set_permissions(path, perms).unwrap();
}

#[test]
fn a_world_writable_parent_is_refused() {
    let root = scratch("ww");
    let parent = root.join("open");
    std::fs::create_dir(&parent).unwrap();
    set_mode(&parent, 0o777);
    let error = bind_socket(&parent.join("zeus.sock")).unwrap_err();
    assert_eq!(error.kind(), std::io::ErrorKind::PermissionDenied);
    assert!(
        !parent.join("zeus.sock").exists(),
        "refused bind still created a socket"
    );
    let _ = std::fs::remove_dir_all(&root);
}

#[test]
fn a_sticky_directory_we_own_is_tightened_before_bind() {
    let root = scratch("sticky");
    let parent = root.join("tmpish");
    std::fs::create_dir(&parent).unwrap();
    set_mode(&parent, 0o1777);
    let socket = parent.join("zeus.sock");
    let listener = bind_socket(&socket).unwrap();
    assert_eq!(mode(&parent) & 0o022, 0, "parent stayed group or world writable");
    assert_eq!(mode(&parent), 0o700);
    assert_eq!(mode(&socket), 0o600);
    drop(listener);
    let _ = std::fs::remove_dir_all(&root);
}

#[test]
fn umask_000_still_leaves_a_0600_socket_in_a_0700_directory() {
    let root = scratch("umask");
    let socket = root.join("priv").join("zeus.sock");
    let old = unsafe { umask(0) };
    let bound = bind_socket(&socket);
    unsafe { umask(old) };
    let listener = bound.unwrap();
    assert_eq!(mode(&socket), 0o600);
    assert_eq!(mode(socket.parent().unwrap()), 0o700);
    drop(listener);
    let _ = std::fs::remove_dir_all(&root);
}

#[test]
fn python_is_not_given_the_parent_gate_path() {
    let root = scratch("argv");
    let model = root.join("model");
    std::fs::create_dir(&model).unwrap();
    let decision = decide(&LaunchRequest {
        conversation_mode: true,
        python: Some(PathBuf::from("/bin/sleep")),
        model: Some(model),
        socket: Some(root.join("zeus.sock")),
        quantize: 8,
    });
    let LaunchDecision::Launch {
        python,
        model,
        private_socket,
        quantize,
        ..
    } = decision
    else {
        panic!("expected a launch");
    };
    let argv = serve_child_argv(&python, &model, &private_socket, quantize);
    let handed = argv
        .windows(2)
        .find(|pair| pair[0] == "--socket")
        .map(|pair| pair[1].clone())
        .unwrap();
    assert_ne!(
        handed,
        private_socket.display().to_string(),
        "python can unlink the parent gate and bind its own socket"
    );
    assert!(
        handed.ends_with(".model"),
        "python listen path {handed} is not a distinct .model socket"
    );
    let _ = std::fs::remove_dir_all(&root);
}

#[test]
fn a_child_unlink_and_rebind_is_not_our_socket() {
    let root = scratch("rebind");
    let parent = root.join("priv");
    std::fs::create_dir(&parent).unwrap();
    set_mode(&parent, 0o700);
    let path = parent.join("zeus.sock.child");
    let listener = bind_socket(&path).unwrap();
    std::fs::remove_file(&path).unwrap();
    let _impostor = UnixListener::bind(&path).unwrap();
    let check = listener_matches(&listener, &path);
    assert!(
        check.is_err(),
        "parent accepted a socket it did not create: {check:?}"
    );
    drop(listener);
    let _ = std::fs::remove_dir_all(&root);
}

#[test]
fn unlink_if_ours_keeps_a_different_inode() {
    let root = scratch("inode");
    let path = root.join("notes");
    std::fs::write(&path, b"keep").unwrap();
    unlink_if_ours(&path, 0, 0).unwrap();
    assert_eq!(std::fs::read(&path).unwrap(), b"keep");
    let _ = std::fs::remove_dir_all(&root);
}

#[test]
fn open_flags_are_not_hardcoded_x86_values() {
    let source = include_str!("../src/serve.rs");
    assert!(
        !source.contains("0x10000"),
        "O_DIRECTORY is still the x86 literal"
    );
    assert!(
        !source.contains("0x20000"),
        "O_NOFOLLOW is still the x86 literal"
    );
}

#[test]
fn peer_uid_refusal_ends_with_eof() {
    let root = scratch("eof");
    let path = root.join("priv").join("zeus.sock");
    let listener = bind_socket(&path).unwrap();
    let (tx, rx) = std::sync::mpsc::channel();
    std::thread::spawn(move || {
        let mut engine = Engine::new(
            FakeBackend::quiet(),
            haru_companion::supervisor::SpyLauncher::default(),
            vec!["fake-haru".into()],
            false,
        );
        let result = serve_one_with(
            listener,
            &mut engine,
            &FixedPeer {
                peer: 42,
                owner: 1000,
            },
        );
        let _ = tx.send(result.map_err(|error| error.kind()));
    });
    let mut client = UnixStream::connect(&path).unwrap();
    client
        .set_read_timeout(Some(std::time::Duration::from_secs(2)))
        .unwrap();
    let mut header = [0u8; 5];
    client.read_exact(&mut header).unwrap();
    let len = u32::from_le_bytes(header[1..5].try_into().unwrap()) as usize;
    let mut payload = vec![0u8; len];
    client.read_exact(&mut payload).unwrap();
    let mut frame = header.to_vec();
    frame.extend(payload);
    let message = decode_server(&frame).unwrap();
    assert!(matches!(
        message,
        ServerMessage::Error { ref code, .. } if code == "peer_uid"
    ));
    let mut tail = [0u8; 8];
    let n = client.read(&mut tail).unwrap();
    assert_eq!(n, 0, "the socket stayed open after peer_uid");
    let outcome = rx
        .recv_timeout(std::time::Duration::from_secs(2))
        .unwrap();
    assert_eq!(outcome, Err(std::io::ErrorKind::PermissionDenied));
    let _ = std::fs::remove_dir_all(&root);
}

#[test]
fn os_peer_uid_matches_geteuid() {
    let root = scratch("ospeer");
    let path = root.join("priv").join("zeus.sock");
    let listener = bind_socket(&path).unwrap();
    let server = std::thread::spawn(move || {
        let (stream, _) = listener.accept().unwrap();
        let uid = peer_uid(&stream).unwrap();
        assert!(OsPeer.allow(&stream).is_ok());
        uid
    });
    let _client = UnixStream::connect(&path).unwrap();
    let uid = server.join().unwrap();
    assert_eq!(uid, current_uid());
    let _ = std::fs::remove_dir_all(&root);
}
