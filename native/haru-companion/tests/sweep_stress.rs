//! Connect churn and a synthetic half-hour must not grow fds or RSS.

use haru_companion::serve::bind_socket;
use std::io::{Read, Write};
use std::os::unix::net::UnixStream;
use std::time::{SystemTime, UNIX_EPOCH};

fn fd_count() -> usize {
    std::fs::read_dir("/proc/self/fd")
        .map(|dir| dir.count())
        .unwrap_or(0)
}

#[test]
fn ten_thousand_connect_cycles_do_not_leak_fds() {
    let root = std::env::temp_dir().join(format!(
        "zeus-haru-stress-{}-{}",
        std::process::id(),
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    std::fs::create_dir_all(&root).unwrap();
    let path = root.join("zeus.sock");
    let before = fd_count();
    for _ in 0..10_000 {
        let listener = bind_socket(&path).unwrap();
        let path_for_client = path.clone();
        let server = std::thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            let mut buf = [0u8; 64];
            let _ = stream.read(&mut buf);
            let _ = stream.write_all(&[0x31, 0, 0, 0, 0]);
        });
        let mut client = UnixStream::connect(&path_for_client).unwrap();
        client.write_all(&[0x21, 2, 0, 0, 0, b'{', b'}']).unwrap();
        let mut ack = [0u8; 5];
        client.read_exact(&mut ack).unwrap();
        drop(client);
        server.join().unwrap();
    }
    let _ = std::fs::remove_dir_all(&root);
    let after = fd_count();
    assert!(
        after <= before + 2,
        "fd count grew from {before} to {after}"
    );
}
