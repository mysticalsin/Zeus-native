//! Bind window, parent mode, and a child that replaces the socket.

use haru_companion::backend::FakeBackend;
use haru_companion::engine::Engine;
use haru_companion::protocol::{decode_server, ServerMessage};
use haru_companion::serve::{
    bind_socket, current_uid, listener_matches, peer_uid, serve_one_with, unlink_if_ours,
    FixedPeer, OsPeer, PeerCheck,
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
    std::fs::symlink_metadata(path)
        .unwrap()
        .permissions()
        .mode()
        & 0o777
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

fn perm_bits(path: &std::path::Path) -> u32 {
    std::fs::metadata(path).unwrap().permissions().mode() & 0o7777
}

#[test]
fn an_owned_0755_parent_is_refused_and_not_chmodded() {
    let root = scratch("own755");
    let parent = root.join("home");
    std::fs::create_dir(&parent).unwrap();
    set_mode(&parent, 0o755);
    let before = perm_bits(&parent);
    let error = bind_socket(&parent.join("x.sock")).unwrap_err();
    assert_eq!(error.kind(), std::io::ErrorKind::PermissionDenied);
    assert!(
        error.to_string().contains("0700"),
        "refusal did not say the parent must already be 0700: {error}"
    );
    assert_eq!(perm_bits(&parent), before, "existing parent mode changed");
    assert!(!parent.join("x.sock").exists());
    let _ = std::fs::remove_dir_all(&root);
}

#[test]
fn a_sticky_tmp_like_parent_is_not_chmodded_for_its_owner() {
    let root = scratch("root-tmp");
    let parent = root.join("tmp");
    std::fs::create_dir(&parent).unwrap();
    set_mode(&parent, 0o1777);
    let before = perm_bits(&parent);
    let error = haru_companion::serve::bind_socket_as(&parent.join("zeus.sock"), current_uid())
        .unwrap_err();
    assert_eq!(error.kind(), std::io::ErrorKind::PermissionDenied);
    assert_eq!(
        perm_bits(&parent),
        before,
        "euid-owned sticky parent was chmodded"
    );
    let _ = std::fs::remove_dir_all(&root);
}

#[test]
fn a_foreign_euid_is_refused_without_chmod() {
    let root = scratch("foreign");
    let parent = root.join("priv");
    std::fs::create_dir(&parent).unwrap();
    set_mode(&parent, 0o700);
    let before = perm_bits(&parent);
    let foreign = current_uid().wrapping_add(1);
    let error =
        haru_companion::serve::bind_socket_as(&parent.join("zeus.sock"), foreign).unwrap_err();
    assert_eq!(error.kind(), std::io::ErrorKind::PermissionDenied);
    assert!(
        error.to_string().contains("euid"),
        "refusal did not name the owner check: {error}"
    );
    assert_eq!(perm_bits(&parent), before);
    assert!(!parent.join("zeus.sock").exists());
    let _ = std::fs::remove_dir_all(&root);
}

#[test]
fn bound_watch_matches_until_the_entry_is_replaced() {
    let root = scratch("watch");
    let parent = root.join("priv");
    std::fs::create_dir(&parent).unwrap();
    set_mode(&parent, 0o700);
    let path = parent.join("zeus.sock");
    let listener = bind_socket(&path).unwrap();
    let watch = haru_companion::serve::BoundWatch::watch(&listener, &path).unwrap();
    assert!(watch.still_ours(&path), "fresh bind was not ours");
    std::fs::remove_file(&path).unwrap();
    let _other = UnixListener::bind(&path).unwrap();
    assert!(
        !watch.still_ours(&path),
        "replaced entry still matched dev/ino/ctime"
    );
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
    unlink_if_ours(
        &path,
        haru_companion::serve::SocketId {
            dev: 0,
            ino: 0,
            ctime_sec: 0,
            ctime_nsec: 0,
        },
    )
    .unwrap();
    assert_eq!(std::fs::read(&path).unwrap(), b"keep");
    let _ = std::fs::remove_dir_all(&root);
}

#[test]
fn fchmodat_nofollow_documents_the_proc_dependency() {
    let source = include_str!("../src/serve.rs");
    assert!(
        source.contains("/proc/self/fd"),
        "the /proc dependency of fchmodat AT_SYMLINK_NOFOLLOW is not documented"
    );
    assert!(
        source.contains("fails closed"),
        "bind must document that a missing /proc fails closed"
    );
    if std::path::Path::new("/proc/self/fd").is_dir() {
        println!(
            "haru-companion skip: fchmodat AT_SYMLINK_NOFOLLOW uses /proc/self/fd; bind fails closed when it is absent (1 skipped)"
        );
        return;
    }
    let root = scratch("noproc");
    let error = bind_socket(&root.join("priv").join("zeus.sock")).unwrap_err();
    assert!(
        error.kind() != std::io::ErrorKind::NotFound,
        "missing /proc must fail closed, got {error}"
    );
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
    let outcome = rx.recv_timeout(std::time::Duration::from_secs(2)).unwrap();
    assert_eq!(outcome, Err(std::io::ErrorKind::PermissionDenied));
    let _ = std::fs::remove_dir_all(&root);
}

#[test]
fn run_serve_unlinks_by_identity_not_by_path() {
    let source = include_str!("../src/cli.rs");
    assert!(
        !source.contains("remove_file"),
        "run_serve still deletes whatever path is there"
    );
}

#[test]
fn a_model_listen_file_is_kept() {
    let root = scratch("model-file");
    let path = root.join("zeus.sock.child.model");
    std::fs::write(&path, b"keep").unwrap();
    haru_companion::supervisor::release_model_socket(&path).unwrap();
    assert_eq!(std::fs::read(&path).unwrap(), b"keep");
    let _ = std::fs::remove_dir_all(&root);
}

#[test]
fn replaced_child_entry_does_not_hang_serve() {
    let root = scratch("hang");
    set_mode(&root, 0o700);
    let model = root.join("model");
    std::fs::create_dir(&model).unwrap();
    let public = root.join("zeus.sock");
    let child = haru_companion::supervisor::private_socket(&public);
    let public_for_server = public.clone();
    let model_for_server = model.clone();
    let (tx, rx) = std::sync::mpsc::channel();
    std::thread::spawn(move || {
        let code = haru_companion::run([
            "serve".into(),
            "--socket".into(),
            public_for_server.display().to_string(),
            "--python".into(),
            "/bin/sleep".into(),
            "--model".into(),
            model_for_server.display().to_string(),
        ]);
        let _ = tx.send(code);
    });
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(2);
    while std::time::Instant::now() < deadline && !child.exists() {
        std::thread::sleep(std::time::Duration::from_millis(10));
    }
    assert!(child.exists(), "child gate was not created");
    std::fs::remove_file(&child).unwrap();
    let _impostor = UnixListener::bind(&child).unwrap();
    let client = UnixStream::connect(&public);
    drop(client);
    let done = rx.recv_timeout(std::time::Duration::from_secs(2));
    assert!(
        done.is_ok(),
        "serve did not exit after the child socket was replaced: {done:?}"
    );
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
    let source = include_str!("../src/serve.rs");
    assert!(
        source.contains("FixedPeer is the foreign-uid seam"),
        "same-uid SO_PEERCRED does not explain why a foreign uid is FixedPeer"
    );
    let _ = std::fs::remove_dir_all(&root);
}
