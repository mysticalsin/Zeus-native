# haru-pipe

The part of Haru-4B's pipeline that is **not the model**, in Rust, with no dependencies:
WAV I/O, int16↔float32, resampling to 24 kHz, 3200-sample (133 ms) framing,
ring and jitter buffers, and the `haru-mlx-native` socket frame format.

It reproduces what `haru-speech-mlx==0.1.0` does on the host:

| Upstream (Python) | haru-pipe (Rust) | Parity on the bench workload |
|---|---|---|
| `soundfile.read(..., dtype="float32")` → `mean(axis=1)` | `wav::read` → `convert::to_mono` | exact |
| `scipy.signal.resample_poly` (Kaiser β 5) | `resample::Polyphase` (same taps and alignment) | ≤ 1 LSB at int16 on ≤ 0.17 % of samples; < 2e-6 on the golden fixtures |
| `soundfile.write` PCM_16 (libsndfile 1.2.2: `floor(x·32768)`, clipped) | `wav::write_pcm16` | exact |
| `native.downsample_2x` / `upsample_2x` / FRAME `<BI><If>` | `native::*` | bit-identical stream (sha256 `ed99f366…52ab`) |
| `DuplexSession.step` rejecting ≠ 3200 samples | `frame::Frame` (only 3200 is representable) | `FrameError::BadFrameSize { expected: 3200, got }` |

## Measured speed (Linux x86-64 box, 7 runs, median)

| | Python (upstream) | haru-pipe |
|---|---|---|
| Socket path, per frame p50 / p95 | 0.125 / 0.161 ms | **0.018 / 0.022 ms** |
| File path, 600 s of audio | 0.924 s | **0.540 s** |
| CPU per run | 3.90 s | **0.71 s** |
| Peak RSS | 431 MB | **223 MB** |

**Read this honestly:** one Haru frame takes **80.8 ms** on the M5 (q8). The Python host glue
measured on the Mac is **0.04 ms** of that. haru-pipe can save at most that: **≤ 0.05 % of the frame**.
It is not a latency fix. It is a small, tested, dependency-free library for **clients**
(Zeus, a local companion app) that need Haru's audio contract without Python.

## CLI

```
haru-pipe convert IN.wav OUT.wav [--float]   # any WAV -> 24 kHz mono PCM_16 (or float32), padded to whole 3200-sample frames
haru-pipe info IN.wav                # {"rate", "channels", "seconds", "haru_frames"}
haru-pipe bench --workload DIR --out DIR [--mode all|file|stream]
haru-pipe e2e   --workload DIR [--model-ms 86.55] [--frames 40]   # SIMULATED model stage
```

## Library

```rust
use haru_pipe::{wav, frame::{Framer, FRAME_SAMPLES}, native::{Ingest, upsample_2x_into, encode_frame_msg}};

let pcm24 = wav::load_audio("user.wav")?;          // = haru_mlx.audio.load_audio
let mut framer = Framer::new();
framer.push(&pcm24);
while let Some(frame) = framer.pop() { /* frame.as_slice().len() == FRAME_SAMPLES */ }
```

## Build and test

```
cargo test                       # 11 tests: 5 red-first invariants (RED.log) + 6 parity/layout tests
cargo build --release            # target/release/haru-pipe
```

macOS arm64 from Linux (done on the box, **not yet run on a Mac**):

```
rustup target add aarch64-apple-darwin
pip install cargo-zigbuild ziglang
cargo zigbuild --release --target aarch64-apple-darwin
rcodesign sign target/aarch64-apple-darwin/release/haru-pipe   # ad-hoc signature, needed on Apple silicon
```

Prebuilt: `../dist/haru-pipe-aarch64-apple-darwin` (Mach-O arm64, ad-hoc signed) and
`../dist/haru-pipe-x86_64-unknown-linux-gnu`. On a Mac, `cargo build --release` works natively too.

## Fallback

Python stays the default. `python_fallback.load_audio_24k()` uses `haru-pipe` when it is on
`PATH` (or `HARU_PIPE_BIN`) and otherwise calls upstream `haru_mlx.audio.load_audio`.

Licence: Apache-2.0, like Haru. Fixtures in `tests/fixtures` are synthetic sine/chirp signals.
