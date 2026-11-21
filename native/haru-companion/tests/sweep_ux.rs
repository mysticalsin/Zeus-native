//! UX polish and motion: readable diagram labels, and a refusal the client can see.

use haru_companion::backend::FakeBackend;
use haru_companion::engine::Engine;
use haru_companion::protocol::{decode_server, ServerMessage};
use haru_companion::serve::{bind_socket, serve_one_with, FixedPeer};
use haru_companion::session::state_machine_svg;
use haru_companion::supervisor::SpyLauncher;
use std::io::Read;
use std::os::unix::net::UnixStream;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

fn attr(tag: &str, name: &str) -> f64 {
    let key = format!("{name}=\"");
    let start = tag.find(&key).unwrap() + key.len();
    let end = tag[start..].find('"').unwrap() + start;
    tag[start..end].parse().unwrap()
}

fn texts(svg: &str) -> Vec<(f64, f64, String)> {
    let mut out = Vec::new();
    let mut rest = svg;
    while let Some(start) = rest.find("<text ") {
        rest = &rest[start..];
        let tag_end = rest.find('>').unwrap();
        let close = rest.find("</text>").unwrap();
        let body = rest[tag_end + 1..close].to_string();
        out.push((attr(&rest[..tag_end], "x"), attr(&rest[..tag_end], "y"), body));
        rest = &rest[close..];
    }
    out
}

fn motion_points(svg: &str) -> Vec<(f64, f64)> {
    let key = "path=\"";
    let start = svg.find(key).unwrap() + key.len();
    let end = svg[start..].find('"').unwrap() + start;
    let numbers: Vec<f64> = svg[start..end]
        .split_whitespace()
        .filter(|token| *token != "M" && *token != "L")
        .map(|token| token.parse().unwrap())
        .collect();
    numbers.chunks(2).map(|pair| (pair[0], pair[1])).collect()
}

fn distance_to_path(point: (f64, f64), path: &[(f64, f64)]) -> f64 {
    path.windows(2)
        .map(|segment| distance_to_segment(point, segment[0], segment[1]))
        .fold(f64::MAX, f64::min)
}

fn distance_to_segment(point: (f64, f64), a: (f64, f64), b: (f64, f64)) -> f64 {
    let dx = b.0 - a.0;
    let dy = b.1 - a.1;
    let len2 = dx * dx + dy * dy;
    if len2 == 0.0 {
        return ((point.0 - a.0).powi(2) + (point.1 - a.1).powi(2)).sqrt();
    }
    let t = ((point.0 - a.0) * dx + (point.1 - a.1) * dy) / len2;
    let t = t.clamp(0.0, 1.0);
    let x = a.0 + t * dx;
    let y = a.1 + t * dy;
    ((point.0 - x).powi(2) + (point.1 - y).powi(2)).sqrt()
}

#[test]
fn diagram_labels_stay_readable_while_the_dot_moves() {
    let svg = state_machine_svg();
    let labels = texts(&svg);
    let mut seen = std::collections::BTreeSet::new();
    for (x, y, text) in &labels {
        let key = (x.round() as i64, y.round() as i64);
        assert!(
            seen.insert(key),
            "two labels share ({x}, {y}); one of them is {text}"
        );
    }
    let path = motion_points(&svg);
    let states = ["idle", "starting", "streaming", "closing", "closed", "failed"];
    for (x, y, text) in &labels {
        if states.contains(&text.as_str()) {
            continue;
        }
        let gap = distance_to_path((*x, *y), &path);
        assert!(
            gap >= 14.0,
            "the moving dot covers {text} at ({x}, {y}); gap {gap}"
        );
    }
}

fn read_one_frame(stream: &mut UnixStream) -> Vec<u8> {
    let mut header = [0u8; 5];
    stream.read_exact(&mut header).unwrap();
    let len = u32::from_le_bytes(header[1..5].try_into().unwrap()) as usize;
    let mut payload = vec![0u8; len];
    stream.read_exact(&mut payload).unwrap();
    let mut frame = header.to_vec();
    frame.extend(payload);
    frame
}

#[test]
fn a_refused_peer_reads_an_error_frame_before_the_socket_closes() {
    let root = std::env::temp_dir().join(format!(
        "zeus-ux-{}-{}",
        std::process::id(),
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    std::fs::create_dir_all(&root).unwrap();
    for round in 0..20 {
        let path = root.join(format!("zeus-{round}.sock"));
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
        let mut client = UnixStream::connect(&path).unwrap();
        client
            .set_read_timeout(Some(Duration::from_secs(2)))
            .unwrap();
        let frame = read_one_frame(&mut client);
        let message = decode_server(&frame).unwrap();
        assert!(
            matches!(
                message,
                ServerMessage::Error { ref code, .. } if code == "peer_uid"
            ),
            "round {round} refused a peer without an error frame: {message:?}"
        );
        let outcome = rx.recv_timeout(Duration::from_secs(2));
        assert!(
            matches!(outcome, Ok(Err(std::io::ErrorKind::PermissionDenied))),
            "round {round} outcome {outcome:?}"
        );
    }
    let _ = std::fs::remove_dir_all(&root);
}
