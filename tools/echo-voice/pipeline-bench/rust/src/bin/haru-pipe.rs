//! haru-pipe CLI.
//!   haru-pipe bench   --workload DIR --out DIR [--mode all|file|stream]
//!   haru-pipe e2e     --workload DIR [--model-ms 86.55] [--frames 40]   (SIMULATED model stage)
//!   haru-pipe convert IN.wav OUT.wav        any WAV -> 24 kHz mono PCM_16, zero-padded to whole frames
//!   haru-pipe info    IN.wav                rate, channels, seconds, Haru frame count
use haru_pipe::{bench, frame, stats, wav};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

fn arg(args: &[String], name: &str, default: Option<&str>) -> String {
    args.windows(2).find(|w| w[0] == name).map(|w| w[1].clone())
        .or(default.map(String::from)).unwrap_or_else(|| die(&format!("missing {name}")))
}
fn die(msg: &str) -> ! { eprintln!("haru-pipe: {msg}"); std::process::exit(2) }

/// Tiny manifest reader: the workload manifest's "file" entries, in order.
fn manifest(dir: &Path) -> (Vec<String>, String) {
    let text = std::fs::read_to_string(dir.join("manifest.json")).unwrap_or_else(|e| die(&format!("manifest: {e}")));
    let mut files = Vec::new();
    for part in text.split("\"file\": \"").skip(1) { files.push(part.split('"').next().unwrap().to_string()); }
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
            std::fs::create_dir_all(&out).unwrap();
            let (files, stream) = manifest(&wl);
            let mut parts = vec!["\"impl\": \"rust\"".to_string()];
            if mode == "all" || mode == "file" {
                let t0 = Instant::now();
                let (mut jsons, mut per, mut audio) = (Vec::new(), Vec::new(), 0.0);
                for f in &files {
                    let r = bench::file_one(&wl.join(f), &out.join(format!("reply_{f}"))).unwrap_or_else(|e| die(&format!("{f}: {e}")));
                    jsons.push(r.json); per.extend(r.per_frame_ns); audio += r.audio_s;
                }
                let wall = t0.elapsed().as_secs_f64();
                parts.push(format!("\"file\": {{\"files\": [{}], \"wall_s\": {wall}, \"audio_s\": {audio}, \"rtf\": {}, \"per_frame\": {}}}",
                    jsons.join(", "), wall / audio, stats::summary_json(&per)));
            }
            if mode == "all" || mode == "stream" {
                let raw = std::fs::read(wl.join(&stream)).unwrap();
                let t0 = Instant::now();
                let (st, per) = bench::stream_run(&raw, 0, Duration::ZERO, || {});
                let wall = t0.elapsed().as_secs_f64();
                let audio = raw.len() as f64 / 4.0 / 48_000.0;
                std::fs::write(out.join("stream_frames.bin"), &st.msgs).unwrap();
                parts.push(format!("\"stream\": {{\"frames\": {}, \"wall_s\": {wall}, \"audio_s\": {audio}, \"rtf\": {}, \"per_frame\": {}, \"drained_samples\": {}}}",
                    per.len(), wall / audio, stats::summary_json(&per), st.drained));
            }
            println!("{{{}}}", parts.join(", "));
        }
        Some("e2e") => {
            let wl = PathBuf::from(arg(&args, "--workload", None));
            let model_ms: f64 = arg(&args, "--model-ms", Some("86.55")).parse().unwrap();
            let frames: usize = arg(&args, "--frames", Some("40")).parse().unwrap();
            let (_, stream) = manifest(&wl);
            use std::io::Read;
            let mut raw = vec![0u8; frames * 2 * frame::FRAME_SAMPLES * 4 + 1_000_000];
            let mut f = std::fs::File::open(wl.join(stream)).unwrap();
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
