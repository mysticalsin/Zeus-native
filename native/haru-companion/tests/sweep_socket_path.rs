//! The socket path must not follow a symlink or destroy a regular file.

use haru_companion::serve::bind_socket;
use std::os::unix::fs::{FileTypeExt, PermissionsExt};

fn dir(name: &str) -> std::path::PathBuf {
    let path = std::env::temp_dir().join(format!(
        "zeus-haru-{name}-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    std::fs::create_dir_all(&path).unwrap();
    path
}

#[test]
fn dangling_symlink_is_not_followed() {
    let root = dir("link");
    let target = root.join("not-created");
    let link = root.join("sock");
    std::os::unix::fs::symlink(&target, &link).unwrap();
    let listener = bind_socket(&link).unwrap();
    assert!(
        !target.exists(),
        "bind followed the symlink and created {}",
        target.display()
    );
    let meta = std::fs::symlink_metadata(&link).unwrap();
    assert!(meta.file_type().is_socket());
    assert_eq!(meta.permissions().mode() & 0o777, 0o600);
    drop(listener);
    let _ = std::fs::remove_dir_all(&root);
}

#[test]
fn a_regular_file_is_not_replaced() {
    let root = dir("file");
    let path = root.join("notes");
    std::fs::write(&path, b"keep-me").unwrap();
    let error = bind_socket(&path).unwrap_err();
    assert_eq!(error.kind(), std::io::ErrorKind::AlreadyExists);
    assert_eq!(std::fs::read(&path).unwrap(), b"keep-me");
    let _ = std::fs::remove_dir_all(&root);
}

#[test]
fn serve_accepts_one_client_then_removes_the_socket() {
    let root = dir("stay");
    std::fs::create_dir(root.join("model")).unwrap();
    let socket = root.join("z.sock");
    let socket_for_server = socket.clone();
    let model = root.join("model");
    let server = std::thread::spawn(move || {
        haru_companion::run([
            "serve".into(),
            "--socket".into(),
            socket_for_server.display().to_string(),
            "--python".into(),
            "/bin/sleep".into(),
            "--model".into(),
            model.display().to_string(),
            "--watchdog".into(),
        ])
    });
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(2);
    while std::time::Instant::now() < deadline && !socket.exists() {
        std::thread::sleep(std::time::Duration::from_millis(10));
    }
    let connected = std::os::unix::net::UnixStream::connect(&socket);
    let code = server.join().unwrap();
    assert!(
        connected.is_ok(),
        "serve returned before a client could connect"
    );
    drop(connected);
    assert_eq!(code, 0);
    assert!(!socket.exists(), "socket left behind after serve returned");
    let _ = std::fs::remove_dir_all(&root);
}

#[test]
fn failed_spawn_removes_the_socket_it_created() {
    let root = dir("spawn");
    std::fs::create_dir(root.join("model")).unwrap();
    let socket = root.join("z.sock");
    let code = haru_companion::run([
        "serve".into(),
        "--socket".into(),
        socket.display().to_string(),
        "--python".into(),
        "/no/such/haru-python".into(),
        "--model".into(),
        root.join("model").display().to_string(),
    ]);
    assert_ne!(code, 0);
    assert!(
        !socket.exists(),
        "failed serve left {}",
        socket.display()
    );
    let _ = std::fs::remove_dir_all(&root);
}
