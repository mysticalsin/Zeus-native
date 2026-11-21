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
