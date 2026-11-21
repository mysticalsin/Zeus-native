//! CLI exit codes. Cargo sets CARGO_BIN_EXE_haru_pipe for this integration test.
use std::fs;
use std::path::Path;
use std::process::Command;

fn bin() -> String {
    std::env::var("CARGO_BIN_EXE_haru_pipe").unwrap_or_else(|_| {
        Path::new(env!("CARGO_MANIFEST_DIR")).join("target/debug/haru-pipe").to_string_lossy().into_owned()
    })
}

fn workload(dir: &Path) {
    fs::create_dir_all(dir).unwrap();
    fs::write(dir.join("manifest.json"), r#"{"files": [], "stream": {"file": "s.f32"}}"#).unwrap();
    fs::write(dir.join("s.f32"), []).unwrap();
}

fn run(args: &[&str]) -> std::process::Output {
    Command::new(bin()).args(args).output().unwrap()
}

#[test]
fn bad_mode_and_bad_numbers_exit_2() {
    let root = std::env::temp_dir().join(format!("haru-cli-{}", std::process::id()));
    let _ = fs::remove_dir_all(&root);
    let wl = root.join("wl");
    let out = root.join("out");
    workload(&wl);
    let wl_s = wl.to_str().unwrap();
    let out_s = out.to_str().unwrap();
    let nope = run(&["bench", "--workload", wl_s, "--out", out_s, "--mode", "nope"]);
    assert_eq!(nope.status.code(), Some(2), "{}", String::from_utf8_lossy(&nope.stderr));
    let frames = run(&["e2e", "--workload", wl_s, "--frames", "nope"]);
    assert_eq!(frames.status.code(), Some(2), "{}", String::from_utf8_lossy(&frames.stderr));
    let ms = run(&["e2e", "--workload", wl_s, "--model-ms", "nope"]);
    assert_eq!(ms.status.code(), Some(2), "{}", String::from_utf8_lossy(&ms.stderr));
    let empty = run(&["bench", "--workload", wl_s, "--out", out_s, "--mode", "stream"]);
    assert_eq!(empty.status.code(), Some(2), "stdout {} stderr {}", String::from_utf8_lossy(&empty.stdout), String::from_utf8_lossy(&empty.stderr));
    let compact = root.join("compact");
    fs::create_dir_all(&compact).unwrap();
    fs::write(compact.join("manifest.json"), r#"{"files":[],"stream":{"file":"s.f32"}}"#).unwrap();
    fs::write(compact.join("s.f32"), [0u8; 8]).unwrap();
    let parsed = run(&["bench", "--workload", compact.to_str().unwrap(), "--out", root.join("cout").to_str().unwrap(), "--mode", "stream"]);
    assert_eq!(parsed.status.code(), Some(0), "compact JSON rejected: {}", String::from_utf8_lossy(&parsed.stderr));
    let _ = fs::remove_dir_all(&root);
}
