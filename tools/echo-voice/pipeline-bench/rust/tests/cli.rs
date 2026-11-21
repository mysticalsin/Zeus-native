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

fn wav_pcm() -> Vec<u8> {
    let mut fmt = vec![0u8; 16];
    fmt[0..2].copy_from_slice(&1u16.to_le_bytes());
    fmt[2..4].copy_from_slice(&1u16.to_le_bytes());
    fmt[4..8].copy_from_slice(&24_000u32.to_le_bytes());
    fmt[8..12].copy_from_slice(&48_000u32.to_le_bytes());
    fmt[12..14].copy_from_slice(&2u16.to_le_bytes());
    fmt[14..16].copy_from_slice(&16u16.to_le_bytes());
    let data = [0u8, 0, 0, 0x40];
    let chunk = |id: &[u8; 4], body: &[u8]| {
        let mut c = id.to_vec();
        c.extend_from_slice(&(body.len() as u32).to_le_bytes());
        c.extend_from_slice(body);
        c
    };
    let mut body = chunk(b"fmt ", &fmt);
    body.extend(chunk(b"data", &data));
    let mut out = b"RIFF".to_vec();
    out.extend_from_slice(&((4 + body.len()) as u32).to_le_bytes());
    out.extend_from_slice(b"WAVE");
    out.extend(body);
    out
}

#[test]
fn manifest_escape_is_refused() {
    let root = std::env::temp_dir().join(format!("haru-escape-{}", std::process::id()));
    let _ = fs::remove_dir_all(&root);
    let wl = root.join("a/b/c/wl");
    let out = root.join("a/b/out");
    fs::create_dir_all(wl.join("subdir")).unwrap();
    fs::create_dir_all(out.join("reply_subdir")).unwrap();
    fs::create_dir_all(root.join("a/keep")).unwrap();
    fs::create_dir_all(root.join("keep")).unwrap();
    let wav = wav_pcm();
    fs::write(root.join("a/keep/SENTINEL"), &wav).unwrap();
    let sentinel = root.join("keep/SENTINEL");
    fs::write(&sentinel, b"stay").unwrap();
    let abs_wav = root.join("abs.wav");
    fs::write(&abs_wav, &wav).unwrap();
    let run_case = |file: &str| {
        let man = format!("{{\"files\":[{{\"file\":{file:?}}}],\"stream\":{{\"file\":\"unused.f32\"}}}}\n");
        fs::write(wl.join("manifest.json"), man).unwrap();
        let got = run(&["bench", "--workload", wl.to_str().unwrap(), "--out", out.to_str().unwrap(), "--mode", "file"]);
        let text = String::from_utf8_lossy(&got.stderr);
        assert_eq!(got.status.code(), Some(2), "file {file} stderr {text} stdout {}", String::from_utf8_lossy(&got.stdout));
        assert!(text.contains("refusing manifest path"), "{text}");
        assert_eq!(fs::read(&sentinel).unwrap(), b"stay");
    };
    run_case("subdir/../../../../keep/SENTINEL");
    run_case(abs_wav.to_str().unwrap());
    run_case("");
    let link = wl.join("subdir/escape.wav");
    std::os::unix::fs::symlink(&sentinel, &link).unwrap();
    run_case("subdir/escape.wav");
    let _ = fs::remove_dir_all(&root);
}
