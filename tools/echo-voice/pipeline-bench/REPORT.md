# Haru host pipeline: Python vs Rust vs Go, plus native-runtime feasibility, long-session soak plan, and on-device options

Echo, 2026-11-20 (BRT).

- Everything here was **measured on the box** (Linux x86-64 VM) unless it is labelled *simulated* or *estimate*.
- Mac figures come from the measured M5 run (`bench/results/summary.md`).

## 1. Verdict (short)

- **Rust wins on the pipeline.** Measured on the socket path:
  - 6.9× faster per frame (0.018 ms vs 0.125 ms p50);
  - 5.5× less CPU;
  - half the RSS.
  - Go is 3.5× faster than Python, about half Rust's speed.
- **The win is negligible end to end.**
  - A Haru frame is 80.8 ms on the M5 (q8).
  - The Python host glue measured on the Mac is 0.04 ms of that (0.05 %).
  - The best possible saving is about 0.1 ms per frame (≤ 0.13 % of a frame).
  - With a *simulated* 86.55 ms model stage, warm first audio is 86.98 ms (Python) vs 86.59 ms (Rust).
- **Packaged anyway, but as a client library, not a speed fix.** `haru-pipe` is a Rust crate and CLI with tests and a macOS arm64 binary. Python stays the default.
- **Where speed really is:**
  - the LM step (48 ms; memory-bandwidth bound);
  - lower-bit weights;
  - an in-process native runtime (mlx-swift or mlx-rs), for packaging rather than speed;
  - or a faster Mac.
  - Not the glue.
- **Long sessions.** Upstream has a DRY repetition penalty (on by default) but no context truncation, reset or watchdog.
  - The attention KV cache grows 32 KiB per frame position.
  - Estimate: about +0.85 GiB and about +5–6 ms per frame after 60 min.
  - The harness, the mitigations and a ~2.1 h Mac plan are ready. They are **not run** and wait for Tony's OK.

## 2. Numbers (Python vs Rust vs Go)

**Workload:** fixed, synthetic, seeded (`scripts/gen_workload.py`, manifest sha256 `a2664d33…a79e`).

- **File path:** 5 WAVs × 120 s = 600 s (16 kHz, 44.1 kHz, 48 kHz mono, 48 kHz stereo, 24 kHz). It follows the `haru-mlx-inference` route:
  - read and int16→f32;
  - mono and `resample_poly` to 24 kHz;
  - pad to whole frames and run the 3200-sample frame loop;
  - stereo assembly and PCM_16 write.
- **Stream path:** 600 s of 48 kHz f32 in seeded 5–40 ms socket chunks. It follows the `haru-mlx-native` route:
  - leftover sample handling and `downsample_2x`;
  - ring buffer → 3200-sample frames;
  - `upsample_2x` and FRAME message encoding;
  - 10 ms playback jitter buffer.
- **Model stand-in:** frame t+1 = clip(0.5 · user frame t).

7 interleaved runs per language (`scripts/run_bench.py`), medians (`scripts/aggregate.py`):

| metric (median of 7 runs) | Python (upstream code) | Rust | Go |
|---|---|---|---|
| Stream path per-frame p50 (ms) | 0.1246 | **0.0181** | 0.0358 |
| Stream path per-frame p95 (ms) | 0.1607 | **0.0215** | 0.0443 |
| File path per-frame p50 / p95 (ms) | 0.0085 / 0.0126 | **0.0029 / 0.0069** | 0.0050 / 0.0090 |
| File mode wall, 600 s audio (s) | 0.924 | **0.540** | 0.680 |
| Stream mode wall, 600 s audio (s) | 0.595 | **0.086** | 0.172 |
| Pipeline-only RTF, both modes | 0.00127 | **0.00052** | 0.00071 |
| CPU user+sys per run (s), `/usr/bin/time -v` | 3.90 | **0.71** | 0.99 |
| Peak RSS per run (MB), `/usr/bin/time -v` | 431 | **223** | 291 |
| First audio, warm, **SIMULATED** 86.55 ms model, p50 / p95 (ms) | 86.979 / 87.050 | **86.593 / 86.617** | 86.608 / 86.633 |
| Pipeline overhead on top of the simulated model, p50 (ms) | 0.429 | **0.043** | 0.058 |
| Cold first audio: process spawn → first FRAME, **SIMULATED** model (ms) | 202.8 (181–241) | **90.0** (89.3–91.5) | 91.2 (90.4–97.9) |
| Stream per-frame p50 as a share of the Mac's 80.81 ms frame | 0.154 % | 0.022 % | 0.044 % |
| Speed-up vs Python (stream wall / file wall / CPU) | 1 | **6.9× / 1.7× / 5.5×** | 3.5× / 1.4× / 3.9× |

**Projected end-to-end saving on the Mac (estimate):**
- Box-measured saving per frame: Rust 0.106 ms, Go 0.089 ms (0.13 % / 0.11 % of 80.81 ms).
- The upper bound on the Mac is the Mac-measured host stage itself: 0.04 ms, or 0.05 % of the frame.
- **This is negligible.** The q8 stage budget is encode 10.26, embed 0.77, **LM 48.44**, sample 8.68, head 8.23, decode 10.13 and host 0.04 ms.

**Cold start:**
- Python spends about 110 ms more on the interpreter and imports. Its first `scipy.signal` and `soundfile` import alone costs 664 ms.
- In a real Haru process, model load (3.3–3.8 s) and the prompt (0.41–0.44 s TTFA) are measured on the Mac. They dwarf this, and the model needs Python anyway today.

**Equivalence (parity, saved in `results/parity_*.json`):**
- Rust and Go output is **bit-identical** to each other everywhere.
- Against Python on the stream path: **bit-identical** (FRAME bytes sha256 `ed99f366…52ab`).
- Against Python on the file path:
  - ≤ 1 int16 LSB on ≤ 0.174 % of samples (the worst file in `results/parity_python_vs_rust.json` and `parity_python_vs_go.json` is `reply_user_16k_mono.wav` at 0.1737 %; f32 summation order inside `resample_poly`);
  - 24 kHz input: bit-identical.

**Two facts found along the way:**
- **Writing:** libsndfile 1.2.2 (bundled with soundfile 0.14) writes float→PCM_16 as `floor(x·32768)`, clipped. It does not round (probed). Both ports mirror this.
- **Socket path resampling:** `haru-mlx-native` uses pairwise-mean 2× downsampling and linear 2× upsampling (`native.py` L74-85), not a quality resampler. Only file mode uses `resample_poly` (`audio.py` L28-30).

**Environment** (`results/env.json`):
- Machine: Intel Xeon (8 vCPU, KVM), 16 GB.
- Toolchains: Python 3.13.5 with numpy 2.5.5, scipy 1.18.1, soundfile 0.14.0, libsndfile 1.2.2; rustc 1.85.1 (release, lto=fat, codegen-units=1); go 1.27.3.
- Source sha256: python `a0a18065…89ce` (pipe.py + upstream sdist files), rust `86358c4f…3547`, go `1b3067d4…4b14`.
- Binary sha256: rust `84c873c9…6ae8`, go `d120ee79…be`.
- Upstream sdist: `haru_speech_mlx-0.1.0.tar.gz` sha256 `c52ac526…ae71`.
- Caveat: the box is shared. Load average was 5.9 (1 min) at the start and fell during the run, so absolute times are noisy. The ratios held across all 7 runs.

## 3. Packaging status

**Built:**
- `pipeline-bench/rust`: the benchmark crate in this tree, no dependencies, Apache-2.0. It has a library API and a `haru-pipe` CLI (`convert`, `info`, `bench`, `e2e`). The canonical crate Zeus links is `native/haru-pipe` on `zeus-bot/haru-companion`, which is not in this tree.
- 11 tests:
  - 5 red-first invariants (`RED.log` shows them failing on stubs, then passing): frame = 3200 enforced by type, resampler length rule, DC/in-band/stop-band energy, lossless int16 round trip;
  - 6 parity and layout tests: scipy golden fixtures within 2e-6, numpy `upsample_2x`/`downsample_2x` semantics, leftover handling, FRAME byte layout, ring wrap-around, WAV round trip.

**Binaries** (`package/dist/`, `SHA256SUMS`):
- `haru-pipe-aarch64-apple-darwin`, sha256 `399ed3a6…d6f4`.
  - Cross-built on the box with cargo-zigbuild and ad-hoc signed with rcodesign 0.29.
  - **Not executed on a Mac yet.**
- `haru-pipe-x86_64-unknown-linux-gnu`, sha256 `a316dc22…c57b`.

**Fallback:**
- `python_fallback.load_audio_24k()` uses `haru-pipe` when present, else upstream `load_audio`.
- `haru-mlx-inference` itself is unchanged, and Python stays the default. The fallback's float delta is not in this tree, so it is not quoted here.

**Not done (by design):**
- No team repo was touched and there is no PR. Wiring this into Zeus goes through the factory pipeline: plan, branch, gates.
- Go was not packaged: it lost to Rust. It cross-compiles to darwin/arm64 with `CGO_ENABLED=0` in one command, if it is ever wanted.

## 4. Can the model runtime itself go native? (research, nothing run)

Key point: MLX's kernels are already C++/Metal. Python only builds the lazy graph each frame. A port removes graph-building overhead and the Python runtime, not GPU time. mlx-rs reports greedy decode on Qwen3 within 2 % of Python mlx_lm ([release 0.34.0](https://github.com/oxiglade/mlx-rs/releases)).

| path | status (Nov 2026) | fit for Haru-4B | effort (estimate) | expected speed gain |
|---|---|---|---|---|
| **mlx-swift** (official, uses mlx-c) | Mature; powers MLX Swift LM apps | Best for **Zeus**: in-process, no Python, no socket. Needs a port of qwen3_5, gated_delta (custom Metal kernel), MeanFlow head, VibeVoice codec stream, prompt, DRY and tokenizer (~2k lines Python) | 3–5 engineer-weeks + Mac parity tests | Small (≤ a few %). Real gains: packaging, cold start, one process |
| **mlx-rs** 0.34.0 ([crate](https://crates.io/crates/mlx-rs), [repo](https://github.com/oxiglade/mlx-rs)) | Active. Targets MLX 0.32.2 (we pin 0.32.4). Has `fast::MetalKernel` ([docs](https://oxiglade.github.io/mlx-rs/mlx_rs/fast/struct.MetalKernel.html)), so the Gated DeltaNet kernel ports as-is | Good for a Rust companion daemon (Atlas/Athena localhost bridge) | 3–5 weeks + MLX version alignment | Same as above (their Qwen3 decode: within 2 % of Python) |
| **MLX C API** ([mlx-c](https://github.com/ml-explore/mlx-c), MIT) | Official. Swift binds through it | Base for any language | n/a (building block) | n/a |
| **Go**: [ollama/mlx](https://pkg.go.dev/github.com/ollama/ollama/mlx) (wraps mlx-c, has `gated_delta.go`) or [mlx-cgo](https://github.com/WhoseBiasDoYallSeek/mlx-cgo) (0 stars) | Ollama's package is internal to Ollama; mlx-cgo is immature. Thread-locked cgo | Weak | 4–6 weeks + higher risk | Same ceiling |
| **candle** (Metal) | Qwen3.5 incl. Gated DeltaNet in **open, unmerged** PRs ([#3396](https://github.com/huggingface/candle/pull/3396), [#3461](https://github.com/huggingface/candle/pull/3461)), with reported repetition bugs. VibeVoice in WIP PR [#3421](https://github.com/huggingface/candle/pull/3421) / [any-tts](https://github.com/Rheosoph/any-tts). No MeanFlow head | Poor today | 6–10 weeks | Likely **slower** than MLX for batch-1 decode |
| **llama.cpp / ggml** | Qwen3.5 + fused Gated DeltaNet Metal kernel merged ([#20361](https://github.com/ggml-org/llama.cpp/pull/20361), b8299) | Only the backbone. Haru feeds summed text + audio-latent embeddings and reads hidden states into a MeanFlow head and the codec. Possible via the embeddings API, but the codec and head must live elsewhere. Needs GGUF conversion of Haru's stacked weights | 8–12 weeks, high parity risk | Unknown; could enable q4/q6 K-quants |

**Verdict:**
- Feasible, but not a speed lever. The LM step is bandwidth-bound: about 4.5 GB read per step (*estimate*) at ~153 GB/s on the base M5 gives a floor of ~29 ms; we measured 45–48 ms.
- The real levers are fewer bytes per step (q4/q6 weights, which upstream doesn't offer and which carry a quality risk) and a Mac with more bandwidth. That also explains why the M1 Max (400 GB/s) does 34 ms per step.
- If Tony wants Python gone for Zeus, the path is mlx-swift, flagged as a separate planned refactor.

## 5. Long-session stability: approach (harness ready, not run on the Mac)

**Harness:**
- Code: `soak/haru_soak.py`; plan: `soak/MAC_RUN_PLAN.md`.
- `selftest` passes 59 checks with a fake backend that injects faults: loop, latency drift, memory leak, garbage audio.
- It drives the upstream `DuplexSession` frame by frame, exactly like `haru-mlx-inference`.
- The conversation is scripted and synthetic: built-in `say` voices, 10 topics × 3 paraphrases, FR and EN, no voice reference.

**What upstream exposes (cited lines are from the pinned sdist):**

| knob | where | exposed on |
|---|---|---|
| temperature / top_k / top_p | `frames.py` L15-17, used `session.py` L161 | CLI: `--temperature`, `--top-k` only (`run_inference.py` L37-38); top_p is API only; the native server exposes none (`native.py` L168-175) |
| guidance_scale | `frames.py` L14 | CLI and server (clamped 1–2, `native.py` L172) |
| **DRY repetition penalty**, on by default (mult 0.8, base 1.75, lookback 1024) | `sampling.py` L12-25, `frames.py` L18, applied `session.py` L153-154, L170-171 | API only |
| eop_bias | `frames.py` L19, `session.py` L156-157 | API only |
| max_frames 27,000 (60 min hard stop) | `frames.py` L21, `session.py` L180 | API only |
| context truncation / reset / watchdog | **missing** | — |

No classic repetition or frequency penalty exists.

**What is measured per run:**
- **Latency:** per-frame latency with p50/p95 per checkpoint, drift slope in ms/min (least squares), frames over 133 ms.
- **Memory:** RSS and MLX active/peak/cache every 10 s, with growth slopes in MB/min, plus the number of stored KV positions.
- **Repetition:**
  - repeated-3-gram ratio over 100-word windows;
  - a token loop detector: a block of period 2–32 repeated back to back ≥ 3 times;
  - 4-gram overlap between consecutive replies.
- **On-topic (proposed metric):** WER of Haru's text against an "expected reply" isn't defined, because many replies are valid. Two scores are used instead, both against the script:
  - **keyword hit rate**: the share of answered turns that use at least one of the turn's topic keywords (accent-folded, FR/EN);
  - **TF-IDF discriminative margin**: cosine to its own topic's reference minus the mean cosine to other topics. The share of turns with a margin above 0 is reported.
  - Both are split into first and second half to expose drift.
- **WER is used where it is well defined:** a `wer()` helper scores user-side ASR, or Haru's own speech against its own text channel (speech–text consistency). The optional ASR step needs an ASR model, and that install is not approved. It is off by default.
- **Responsiveness:** answered-turn rate (≥ 1 s voiced in the reply window) and talk-over ratio.
- **Audio:** garbage frame ratio (non-finite, clipping, or spectral flatness > 0.5 while voiced) and voiced ratio.

**Mitigation switches (ours). Each uses explicit state machines:**
- `TurnTracker`: IDLE / USER / MODEL / OVERLAP from VAD on both channels.
- `Watchdog`: OK → PENDING → RESTART → COOLDOWN.

| switch | what it does |
|---|---|
| `--kv-window N` | Rolling KV truncation: keeps the prompt plus the last N positions; RoPE positions keep counting. *Experimental:* Haru wasn't trained with evicted context |
| `--reanchor-minutes M` | Starts a fresh session with the system prompt re-run, at the next IDLE |
| `--watchdog` | Soft faults (loop, 3 unanswered turns, 3 s of garbage audio) restart at the next IDLE. Hard faults (p95 > 120 ms over 30 s, MLX memory > 14 GB) restart immediately |
| `--temperature`, `--top-p`, `--dry on/off`, `--dry-multiplier`, `--eop-bias` | Upstream knobs, reached through the API |

**Predictions to check (estimates from config.json):**
- Haru-4B has 8 full-attention layers × 4 KV heads × 256 dims in bf16, so 32 KiB per position.
- After 60 min (27,000 frames): about 0.85 GiB of KV.
- About 0.9 GB more read per step, so about +5–6 ms per frame by minute 60 (≈ 0.1 ms/min drift).
- Buffer regrowth copies every 256 positions (~34 s).
- With `--kv-window 4096`, KV is capped at about 0.13 GiB.

**Mac plan (8 runs, ~2.1 h wall, needs ≥ 17 GiB free):**
- A60 EN baseline (10/30/60 min are checkpoints of that one run);
- A30 FR baseline;
- B60 EN with all mitigations;
- 10-min ablations: DRY off, T 0.5, T 0.9 with top-p 0.9, KV window 1024, DRY multiplier 1.2.
- Exact commands are in `MAC_RUN_PLAN.md`.
- It re-downloads the 10.54 GB model (same revision and sha256) into `~/echo-haru-soak` and deletes only that folder afterwards. **This needs Tony's approval first.** It is a new download and run, not covered by the benchmark OK.

## 6. On-device voice: integration options per app

**Zeus (native macOS Swift):**
1. **Now:** run `haru-mlx-native` as a local companion process on its Unix socket. This is upstream's own protocol; a Swift client already exists in the Haru repo (`haru_mlx/swift/Shared/Connection.swift`).
   - Zeus owns the mic and speakers (48 kHz f32) and maps PREPARE / START / AUDIO / FRAME onto `VoiceSessionState` (PR #30): idle → starting (prompt ~0.43 s) → streaming → closing → closed or failed.
   - It needs ≥ 16 GB unified memory (q8 peak 7.4 GB measured) and a bundled, hash-locked Python and MLX environment.
   - The watchdog and re-anchoring map onto a clean reconnect, i.e. a fresh session.
2. **Later (refactor to flag):** an in-process mlx-swift port, which removes Python. See section 4: 3–5 weeks.
3. **Read-aloud:** Kyutai Pocket TTS (Rust CPU binary, FR+EN). The download is still waiting for Tony's answer. Until then, AVSpeechSynthesizer is a zero-download fallback.
   - `haru-pipe` isn't needed in Zeus. AVAudioConverter already covers resampling.

**Atlas and Athena (Cloudflare Workers):**
- A Worker can't run a local model, so "on-device" means on the user's machine.
1. **Browser read-aloud (all users):** a small WASM/WebGPU TTS, cached after the first load, for example Kokoro-82M via kokoro-js or Piper / sherpa-onnx WASM.
   - French quality and voice licences must be checked per voice. Kokoro's French is weak.
   - Expect a 80–300 MB one-time download per browser (*estimate*). Feature-detect, and keep Workers AI aura-2 as the fallback.
2. **Local companion (Mac users):** the Zeus or Haru companion also listens on `ws://127.0.0.1:<port>` with an origin allow-list and a pairing token. The web app uses it when present, else the server path. Things to verify:
   - browser Private Network Access preflights;
   - Safari's handling of https → ws://localhost.
   This would be the only way to get Haru duplex into Atlas or Athena.
3. **Haru-4B in the browser: not possible.** It needs 10.5 GB of bf16 weights (about 7.4 GB peak at q8), MLX, and the Apple GPU.
- Duplex Haru is free-form chat. It also doesn't fit the scripted interview and scoring flows, which should stay on read-aloud TTS.

## 7. Reproduce

```
cd tools/echo-voice/pipeline-bench
python3 -m venv .venv && .venv/bin/pip install numpy scipy soundfile
.venv/bin/python scripts/gen_workload.py workload          # deterministic, ~170 MB, gitignored
(cd rust && cargo build --release && cargo test)
(cd go && go test ./... && go build -trimpath -o haru-pipe ./cmd/haru-pipe)
.venv/bin/python scripts/run_bench.py --runs 7 --e2e-runs 7 && .venv/bin/python scripts/aggregate.py
python3 ../bench/haru_bench.py selftest
```
