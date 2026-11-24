//! Security sweep: peer uid on the secured socket, and a private child socket.

use haru_companion::backend::FakeBackend;
use haru_companion::engine::Engine;
use haru_companion::serve::{bind_socket, serve_one_with, FixedPeer};
use haru_companion::supervisor::{private_socket, SpyLauncher};
use std::os::unix::fs::PermissionsExt;
use std::os::unix::net::UnixStream;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

fn scratch(name: &str) -> std::path::PathBuf {
    let path = std::env::temp_dir().join(format!(
        "zeus-sec-{name}-{}-{}",
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

fn mode(path: &std::path::Path) -> u32 {
    std::fs::symlink_metadata(path)
        .unwrap()
        .permissions()
        .mode()
        & 0o777
}

#[test]
fn e02_child_socket_is_0600_inside_a_0700_dir() {
    let root = scratch("child");
    let public = root.join("priv").join("zeus.sock");
    let child = private_socket(&public);
    let _public_listener = bind_socket(&public).unwrap();
    let _child_listener = bind_socket(&child).unwrap();
    assert_eq!(mode(&public), 0o600, "public socket mode");
    assert_eq!(mode(public.parent().unwrap()), 0o700, "public parent");
    assert_eq!(mode(&child), 0o600, "child socket mode");
    assert_eq!(mode(child.parent().unwrap()), 0o700, "child parent");
    drop(_public_listener);
    drop(_child_listener);
    let _ = std::fs::remove_dir_all(&root);
}

#[test]
fn e02_serve_creates_the_child_socket_and_unlinks_it() {
    let root = scratch("serve");
    std::fs::create_dir(root.join("model")).unwrap();
    let public = root.join("priv").join("zeus.sock");
    let child = private_socket(&public);
    let public_for_server = public.clone();
    let model = root.join("model");
    let server = std::thread::spawn(move || {
        haru_companion::run([
            "serve".into(),
            "--socket".into(),
            public_for_server.display().to_string(),
            "--python".into(),
            "/bin/sleep".into(),
            "--model".into(),
            model.display().to_string(),
        ])
    });
    let deadline = Instant::now() + Duration::from_secs(2);
    while Instant::now() < deadline && !child.exists() {
        std::thread::sleep(Duration::from_millis(10));
    }
    assert!(
        child.exists(),
        "serve did not create the secured child socket"
    );
    assert_eq!(mode(&child), 0o600);
    assert_eq!(mode(child.parent().unwrap()), 0o700);
    let client = UnixStream::connect(&public);
    drop(client);
    let code = server.join().unwrap();
    assert_eq!(code, 0);
    assert!(!child.exists(), "child socket was left behind");
    assert!(!public.exists(), "public socket was left behind");
    let _ = std::fs::remove_dir_all(&root);
}

#[test]
fn e02_injected_foreign_uid_is_refused() {
    let root = scratch("peer");
    let path = root.join("zeus.sock");
    let listener = bind_socket(&path).unwrap();
    let (tx, rx) = std::sync::mpsc::channel();
    std::thread::spawn(move || {
        let mut engine = Engine::new(
            FakeBackend::quiet(),
            SpyLauncher::default(),
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
    let _client = UnixStream::connect(&path).unwrap();
    let outcome = rx.recv_timeout(Duration::from_secs(2));
    assert!(
        matches!(outcome, Ok(Err(std::io::ErrorKind::PermissionDenied))),
        "a foreign uid was not refused: {outcome:?}"
    );
    let _ = std::fs::remove_dir_all(&root);
}
