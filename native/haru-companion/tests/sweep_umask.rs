//! bind_socket must not change the process umask seen by other threads.

use haru_companion::serve::bind_socket;
use std::os::unix::fs::PermissionsExt;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

#[test]
fn binding_a_socket_does_not_strip_execute_from_other_directories() {
    let root = std::env::temp_dir().join(format!("zeus-umask-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    std::fs::create_dir_all(&root).unwrap();
    let mut perms = std::fs::metadata(&root).unwrap().permissions();
    perms.set_mode(0o700);
    std::fs::set_permissions(&root, perms).unwrap();
    let stop = Arc::new(AtomicBool::new(false));
    let stop_bind = Arc::clone(&stop);
    let bind_root = root.clone();
    let binder = std::thread::spawn(move || {
        let mut n = 0u32;
        while !stop_bind.load(Ordering::Relaxed) {
            let path = bind_root.join(format!("sock-{n}"));
            if let Ok(listener) = bind_socket(&path) {
                drop(listener);
                let _ = std::fs::remove_file(&path);
            }
            n = n.wrapping_add(1);
        }
    });
    let mut created = 0u32;
    for i in 0..400 {
        let dir = root.join(format!("dir-{i}"));
        std::fs::create_dir(&dir).unwrap();
        std::fs::write(dir.join("note"), b"ok").unwrap();
        let mode = std::fs::metadata(&dir).unwrap().permissions().mode() & 0o111;
        assert!(
            mode != 0,
            "directory {dir:?} was created without the execute bit while a socket was binding"
        );
        created += 1;
    }
    stop.store(true, Ordering::Relaxed);
    binder.join().unwrap();
    assert!(created == 400);
    let _ = std::fs::remove_dir_all(&root);
}
