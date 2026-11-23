//! haru-pipe CLI.
//!   haru-pipe bench   --workload DIR --out DIR [--mode all|file|stream]
//!   haru-pipe e2e     --workload DIR [--model-ms 86.55] [--frames 40]   (SIMULATED model stage)
//!   haru-pipe convert IN.wav OUT.wav        any WAV -> 24 kHz mono PCM_16, zero-padded to whole frames
//!   haru-pipe info    IN.wav                rate, channels, seconds, Haru frame count
use haru_pipe::{bench, frame, stats, wav};
use std::collections::HashSet;
use std::io::Write;
use std::path::{Component, Path, PathBuf};
use std::time::{Duration, Instant};

fn arg(args: &[String], name: &str, default: Option<&str>) -> String {
    args.windows(2).find(|w| w[0] == name).map(|w| w[1].clone())
        .or(default.map(String::from)).unwrap_or_else(|| die(&format!("missing {name}")))
}
fn die(msg: &str) -> ! { eprintln!("haru-pipe: {msg}"); std::process::exit(2) }
fn parse_f64(s: &str, name: &str) -> f64 { s.parse().unwrap_or_else(|_| die(&format!("bad {name}"))) }
fn parse_usize(s: &str, name: &str) -> usize {
    let n: usize = s.parse().unwrap_or_else(|_| die(&format!("bad {name}")));
    if n == 0 { die(&format!("{name} must be at least 1")); }
    n
}
fn rtf(wall: f64, audio: f64) -> f64 {
    if audio == 0.0 { die("no audio in workload"); }
    wall / audio
}

/// File names for every `"file"` string, with or without whitespace around the colon.
fn file_names(text: &str) -> Vec<String> {
    let b = text.as_bytes();
    let key = b"\"file\"";
    let mut out = Vec::new();
    let mut i = 0;
    while i + key.len() <= b.len() {
        if &b[i..i + key.len()] == key {
            let mut j = i + key.len();
            while j < b.len() && b[j].is_ascii_whitespace() { j += 1; }
            if j < b.len() && b[j] == b':' {
                j += 1;
                while j < b.len() && b[j].is_ascii_whitespace() { j += 1; }
                if j < b.len() && b[j] == b'"' {
                    j += 1;
                    let start = j;
                    while j < b.len() && b[j] != b'"' { j += 1; }
                    if let Ok(s) = std::str::from_utf8(&b[start..j]) { out.push(s.to_string()); }
                    i = j;
                    continue;
                }
            }
        }
        i += 1;
    }
    out
}

fn inside(base: &Path, path: &Path) -> bool {
    path == base || path.starts_with(base)
}

fn normalize(path: &Path) -> PathBuf {
    let mut out = PathBuf::new();
    for c in path.components() {
        match c {
            Component::ParentDir => { out.pop(); }
            Component::CurDir => {}
            other => out.push(other.as_os_str()),
        }
    }
    out
}

/// Follow `path` from the canonical `base`. A symlink is resolved even when its
/// target does not exist yet, and any target outside `base` is refused. The
/// returned path has no symlink left in it.
fn place(base: &Path, path: &Path, seen: &mut HashSet<PathBuf>) -> Result<PathBuf, ()> {
    let cleaned = normalize(path);
    if !inside(base, &cleaned) { return Err(()); }
    if cleaned == base { return Ok(base.to_path_buf()); }
    match std::fs::symlink_metadata(&cleaned) {
        Ok(meta) if meta.file_type().is_symlink() => {
            if !seen.insert(cleaned.clone()) { return Err(()); }
            let target = std::fs::read_link(&cleaned).unwrap_or_else(|e| die(&e.to_string()));
            let parent = match cleaned.parent() { Some(parent) => parent, None => return Err(()) };
            let dest = if target.is_absolute() { target } else { parent.join(target) };
            place(base, &dest, seen)
        }
        Ok(_) => {
            let real = std::fs::canonicalize(&cleaned).unwrap_or_else(|e| die(&e.to_string()));
            if !inside(base, &real) { return Err(()); }
            Ok(real)
        }
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
            let (Some(parent), Some(name)) = (cleaned.parent(), cleaned.file_name()) else { return Err(()) };
            let parent = place(base, parent, seen)?;
            let full = parent.join(name);
            if !inside(base, &full) { return Err(()); }
            Ok(full)
        }
        Err(e) => die(&e.to_string()),
    }
}

/// Reject absolute names, empty names, and `..` / root / prefix components, then
/// keep the resolved path inside `base`.
fn confined(base: &Path, name: &str) -> PathBuf {
    if name.is_empty() || Path::new(name).is_absolute() {
        die(&format!("refusing manifest path {name:?}"));
    }
    for c in Path::new(name).components() {
        match c {
            Component::ParentDir | Component::RootDir | Component::Prefix(_) => {
                die(&format!("refusing manifest path {name:?}"));
            }
            Component::CurDir | Component::Normal(_) => {}
        }
    }
    let base = std::fs::canonicalize(base).unwrap_or_else(|e| die(&e.to_string()));
    let mut full = PathBuf::new();
    for c in base.join(name).components() {
        match c {
            Component::ParentDir => { full.pop(); }
            Component::CurDir => {}
            other => full.push(other.as_os_str()),
        }
    }
    if !inside(&base, &full) {
        die(&format!("refusing manifest path {name:?}"));
    }
    // A symlink under the base can still leave it. `exists` is false for a
    // broken link, and creating through that link would write the target.
    place(&base, &full, &mut HashSet::new()).unwrap_or_else(|_| die(&format!("refusing manifest path {name:?}")))
}

/// Tiny manifest reader: the workload manifest's "file" entries, in order.
fn manifest(dir: &Path) -> (Vec<String>, String) {
    let text = std::fs::read_to_string(dir.join("manifest.json")).unwrap_or_else(|e| die(&format!("manifest: {e}")));
    let mut files = file_names(&text);
    let stream = files.pop().unwrap_or_else(|| die("manifest has no stream"));
    (files, stream)
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    match args.get(1).map(String::as_str) {
        Some("bench") => {
            let wl = PathBuf::from(arg(&args, "--workload", None));
            let out = PathBuf::from(arg(&args, "--out", None));
            let mode = arg(&args, "--mode", Some("all"));
            if !matches!(mode.as_str(), "all" | "file" | "stream") { die("bad --mode"); }
            std::fs::create_dir_all(&out).unwrap_or_else(|e| die(&e.to_string()));
            let (files, stream) = manifest(&wl);
            let mut parts = vec!["\"impl\": \"rust\"".to_string()];
            if mode == "all" || mode == "file" {
                let t0 = Instant::now();
                let (mut jsons, mut per, mut audio) = (Vec::new(), Vec::new(), 0.0);
                for f in &files {
                    let src = confined(&wl, f);
                    let dst = confined(&out, &format!("reply_{f}"));
                    let r = bench::file_one(&src, &dst).unwrap_or_else(|e| die(&format!("{f}: {e}")));
                    jsons.push(r.json); per.extend(r.per_frame_ns); audio += r.audio_s;
                }
                let wall = t0.elapsed().as_secs_f64();
                parts.push(format!("\"file\": {{\"files\": [{}], \"wall_s\": {wall}, \"audio_s\": {audio}, \"rtf\": {}, \"per_frame\": {}}}",
                    jsons.join(", "), rtf(wall, audio), stats::summary_json(&per)));
            }
            if mode == "all" || mode == "stream" {
                let raw = std::fs::read(confined(&wl, &stream)).unwrap();
                let t0 = Instant::now();
                let mut frames_out = std::fs::File::create(out.join("stream_frames.bin")).unwrap();
                let (st, per) = bench::stream_run_to(&raw, 0, Duration::ZERO, move |msg| {
                    std::io::Write::write_all(&mut frames_out, msg).unwrap();
                }, || {});
                let wall = t0.elapsed().as_secs_f64();
                let audio = raw.len() as f64 / 4.0 / 48_000.0;
                parts.push(format!("\"stream\": {{\"frames\": {}, \"wall_s\": {wall}, \"audio_s\": {audio}, \"rtf\": {}, \"per_frame\": {}, \"drained_samples\": {}}}",
                    per.len(), rtf(wall, audio), stats::summary_json(&per), st.drained));
            }
            println!("{{{}}}", parts.join(", "));
        }
        Some("e2e") => {
            let wl = PathBuf::from(arg(&args, "--workload", None));
            let model_ms = parse_f64(&arg(&args, "--model-ms", Some("86.55")), "--model-ms");
            let frames = parse_usize(&arg(&args, "--frames", Some("40")), "--frames");
            let (_, stream) = manifest(&wl);
            use std::io::Read;
            let mut raw = vec![0u8; frames * 2 * frame::FRAME_SAMPLES * 4 + 1_000_000];
            let mut f = std::fs::File::open(confined(&wl, &stream)).unwrap();
            let n = f.read(&mut raw).unwrap(); raw.truncate(n);
            let (_, per) = bench::stream_run(&raw, frames, Duration::from_nanos((model_ms * 1e6) as u64), || {
                let mut o = std::io::stdout().lock(); o.write_all(b"FIRST_AUDIO\n").unwrap(); o.flush().unwrap();
            });
            let mut ms: Vec<f64> = per.iter().map(|&v| v as f64 / 1e6).collect();
            ms.sort_by(|a, b| a.partial_cmp(b).unwrap());
            let s = stats::summary_json(&per);
            println!("{{\"impl\": \"rust\", \"simulated_model_ms\": {model_ms}, \"first_audio\": {}, \"overhead_p50_ms\": {}}}}}",
                &s[..s.len() - 1], stats::percentile(&ms, 50.0) - model_ms);
        }
        Some("convert") => {
            let (src, dst) = (args.get(2).unwrap_or_else(|| die("convert IN OUT")), args.get(3).unwrap_or_else(|| die("convert IN OUT")));
            let mut x = wav::load_audio(src).unwrap_or_else(|e| die(&e.to_string()));
            let n = frame::frame_count(x.len());
            x.resize(n * frame::FRAME_SAMPLES, 0.0);
            wav::write_pcm16(dst, haru_pipe::SAMPLE_RATE, 1, &x).unwrap_or_else(|e| die(&e.to_string()));
            println!("{n} frames ({:.3} s) -> {dst}", x.len() as f64 / 24_000.0);
        }
        Some("info") => {
            let w = wav::read(args.get(2).unwrap_or_else(|| die("info IN"))).unwrap_or_else(|e| die(&e.to_string()));
            let secs = w.samples.len() as f64 / w.channels as f64 / w.rate as f64;
            let n24 = (secs * 24_000.0).ceil() as usize;
            println!("{{\"rate\": {}, \"channels\": {}, \"seconds\": {secs}, \"haru_frames\": {}}}", w.rate, w.channels, frame::frame_count(n24));
        }
        _ => die("usage: haru-pipe bench|e2e|convert|info (see source header)"),
    }
}
