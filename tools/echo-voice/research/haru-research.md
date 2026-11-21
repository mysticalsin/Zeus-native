# Haru voice layer: research notes (Echo, 2026-11-20)

Read-only research. Nothing was cloned, installed or run on the box or on Tony's Mac, and no weights were downloaded.
Sources were read through the GitHub API, raw.githubusercontent.com, the HF API and PyPI metadata. I also fetched the 65 KB `haru-speech-mlx` wheel from PyPI onto the box to diff it against the repo; it contains code only.
**Read this together with** `/workspace/research-substrate/FINDINGS.md` (Jarvis). That file already covers what Haru is, its licence, "Dessa", Substrate and per-app fit. This file does not repeat it. It adds verified corrections, a supply-chain review, the exact MLX run path, hot spots, a GPU price and the benchmark design.

Pinned source used throughout: commit `7fe6b7665f8bf035998f401f8cb779fbe53f2751` (HEAD of `main`, 2026-11-13 05:31 UTC = 02:31 BRT).
HF model revision: `8d6e83bcd3701a76fc27a764965665da1df7da78`.

## 0. Key framing (agrees with Jarvis)
Haru-4B is a **full-duplex speech-to-speech dialogue model**. It is **not TTS**: it has no text-in mode, and it writes its own words ([model card](https://huggingface.co/higurashi-ai/Haru-4B)). So "a voice layer from Haru" either (a) replaces the whole voice agent loop, or (b) needs a TTS-style fine-tune that does not exist today. A fixed-text naturalness A/B is therefore not directly possible. The benchmark below feeds synthetic **user** speech and measures Haru's replies.

## 1. Verified additions and corrections to FINDINGS.md
| Item | Verified value | Source |
|---|---|---|
| Checkpoint size | `model.safetensors` 10,540,113,510 B + `tokenizer.json` 19,989,325 B; repo total 10,560,111,749 B. The MLX loader downloads only `config.json`, `model.safetensors` and `tokenizer.json` | [HF tree API](https://huggingface.co/api/models/higurashi-ai/Haru-4B/tree/main), [hub.py L8](https://github.com/higurashi-ai/Haru/blob/7fe6b7665f8bf035998f401f8cb779fbe53f2751/haru_mlx/haru_mlx/hub.py#L8) |
| Params | ≈5.27 B, from 10.54 GB ÷ 2 B (bf16). HF shows "5B" | derived |
| LM | Qwen3.5-4B text: 32 layers (8 full attention, 24 Gated DeltaNet linear attention), hidden 2560, vocab 248,320, 16 heads / 4 KV heads, head_dim 256 | [config.json](https://huggingface.co/higurashi-ai/Haru-4B/blob/main/config.json) |
| "65 ms on a MacBook" | Measured on an **M1 Max** with the **int8** native Swift app. It **excludes up to 133 ms of audio framing**. One model step = 34.2 ± 0.5 ms; total p50 = 65.2 ± 1.5 ms | [blog §3.2](https://blog.higurashi.ai/melte/haru4b/) |
| Offline MLX speed | M1 Max 64 GB, MLX 0.32.4, 31 s recording: **43 ms/frame bf16, 31 ms/frame `--quantize 8`**; **peak memory 13.5 GB / 11.2 GB**. RTF ≈ 0.32 / 0.23 (derived: ms ÷ 133.3) | [haru_mlx/tests/README.md](https://github.com/higurashi-ai/Haru/blob/7fe6b7665f8bf035998f401f8cb779fbe53f2751/haru_mlx/tests/README.md) |
| GPU | B300: codec encode + decode + one LM step ≈ 15 ms (vLLM-Omni). Triton codec: 0.7 ms vs 6 ms per frame | [blog](https://blog.higurashi.ai/melte/haru4b/), [haru/README](https://github.com/higurashi-ai/Haru/blob/7fe6b7665f8bf035998f401f8cb779fbe53f2751/haru/README.md) |
| CPU | The loader says "pass `torch.float32` to run on CPU". The MLX code has CPU array fallbacks, and the authors made their PyTorch parity dumps on CPU. So CPU **works**, but its speed is **unknown** (not published) | [loaders.py L41-42](https://github.com/higurashi-ai/Haru/blob/7fe6b7665f8bf035998f401f8cb779fbe53f2751/haru/haru/models/loaders.py#L41-L42), tests README |
| Sampling defaults | temp 0.7, top-k 25, top-p 1.0, DRY repetition penalty, MeanFlow guidance 1.5 (range 1–2), 1 step | [session.py L32-45](https://github.com/higurashi-ai/Haru/blob/7fe6b7665f8bf035998f401f8cb779fbe53f2751/haru/haru/session.py#L32-L45) |
| Licence detail | Code and weights: Apache-2.0. The VibeVoice codec architecture and weights inside are MIT (Microsoft). The web client is derived from Moshi (MIT). The MLX Qwen3.5 code is derived from mlx-lm (MIT). The Qwen3.5 upstream weight licence is **not stated in the repo**, so it is unverified | [THIRD_PARTY_NOTICES.md](https://github.com/higurashi-ai/Haru/blob/7fe6b7665f8bf035998f401f8cb779fbe53f2751/THIRD_PARTY_NOTICES.md) |
| Training | 40 M h of real speech, 160+ languages, 9 primary languages (FR is one); 13 M h separated duplex dialogue; 256×B200 for ~8 days | blog |

## 2. Hardware (scope item a)
- **Apple Silicon (MLX):** bf16 needs ~13.5 GB peak and int8 ~11.2 GB peak (published, M1 Max). In practice that means a Mac with **≥16 GB unified memory for int8, and preferably 24 GB+ for bf16**. That is my inference from the published peaks; 16 GB with bf16 is untested.
- **NVIDIA (PyTorch):** "a CUDA GPU with about 12 GB". The Triton codec is CUDA-only and opt-in; the default `codec_backend="torch"` runs anywhere. The vLLM-Omni path is GPU-only.
- **Cloud-agent CPU VM:** weights alone are ~21 GB in fp32 (5.27 B × 4 B, derived). Real-time needs ≤133 ms per frame. No CPU timing is published, so it is **impractical / unknown**. Don't plan a CPU baseline.
- **Smallest common GPU that fits:** NVIDIA L4 24 GB, AWS `g6.xlarge`: **$0.8048/h on demand** in us-east-1/us-east-2/us-west-2 ([Vantage](https://instances.vantage.sh/aws/ec2/g6.xlarge?currency=USD&region=us-east-1)) and **$1.37/h in São Paulo** ([GPU Ledger](https://gpuledger.dev/instances/aws/g6-xlarge/), read 20 Nov). Caveat: g6.xlarge has only 16 GiB host RAM. The loader puts safetensors straight onto the device ([loaders.py L49](https://github.com/higurashi-ai/Haru/blob/7fe6b7665f8bf035998f401f8cb779fbe53f2751/haru/haru/models/loaders.py#L49)), so this probably fits, but I haven't verified it. **Renting this is spend and needs Tony's OK.** The free option is Tony's Mac.

## 3. Supply-chain review (before anything runs on the Mac)
- **Install from PyPI, not a clone:** `haru-speech-mlx==0.1.0`. It is published by GitHub Actions **Trusted Publishing**, manually dispatched with an explicit commit SHA ([release.yml](https://github.com/higurashi-ai/Haru/blob/7fe6b7665f8bf035998f401f8cb779fbe53f2751/.github/workflows/release.yml)).
  - Wheel `haru_speech_mlx-0.1.0-py3-none-any.whl`, sha256 `5e57120ff2649ebce3b498aad346502c1b517c78e700952cb2e5289b3c866561`, 65,393 B, uploaded 2026-11-13 01:45 UTC.
  - **I diffed every .py/.json in the wheel against the repo at the pinned commit: 0 differences.** The `haru_mlx/` package code is also unchanged between the first commit `d3612b0` and HEAD; only a test changed ([compare](https://github.com/higurashi-ai/Haru/compare/d3612b02037d0f1083490b8afe153aa8553092af...7fe6b7665f8bf035998f401f8cb779fbe53f2751)).
  - The wheel is pure Python (`py3-none-any`). It has no `setup.py`, no build hooks, no `.pth` files and no native code. Entry points are only `haru-mlx-inference` and `haru-mlx-native`.
- **Runtime network:** only `huggingface_hub.snapshot_download` when `--model` is not a local directory ([hub.py L11-18](https://github.com/higurashi-ai/Haru/blob/7fe6b7665f8bf035998f401f8cb779fbe53f2751/haru_mlx/haru_mlx/hub.py#L11-L18)). `native.py` listens on a **local Unix socket** in `$TMPDIR` (no TCP). There is no telemetry.
  - The PyTorch `haru` package, which we don't need, has extra network surface: `--share` opens a Gradio public tunnel ([server.py L611-669](https://github.com/higurashi-ai/Haru/blob/7fe6b7665f8bf035998f401f8cb779fbe53f2751/haru/haru/server.py#L611-L669)), and the WebRTC module references a Cloudflare TURN endpoint ([webrtc.py L47](https://github.com/higurashi-ai/Haru/blob/7fe6b7665f8bf035998f401f8cb779fbe53f2751/haru/haru/webrtc.py#L47)). **Do not install `haru`, `[share]` or `[webrtc]`.**
- **Subprocess:** `ffmpeg` runs only for non-WAV/FLAC/Ogg input ([audio.py L34-48](https://github.com/higurashi-ai/Haru/blob/7fe6b7665f8bf035998f401f8cb779fbe53f2751/haru_mlx/haru_mlx/audio.py#L34-L48)). The bench uses WAV, so it is never called.
- **Deserialisation:** weights load via `mx.load` on safetensors ([loaders.py L51](https://github.com/higurashi-ai/Haru/blob/7fe6b7665f8bf035998f401f8cb779fbe53f2751/haru_mlx/haru_mlx/models/loaders.py#L51)). There is no pickle, `torch.load` or `trust_remote_code`. The tokenizer uses the HF `tokenizers` JSON format.
- **Risks to flag:**
  - (1) Dependencies are lower bounds only (`mlx>=0.32`, `tokenizers>=0.21`, `huggingface-hub>=0.26`, `numpy>=1.26`, `scipy>=1.13`, `soundfile>=0.13`), so an install pulls whatever is latest. Mitigation: hash-locked requirements (below), with MLX pinned to the version the authors tested (0.32.4).
  - (2) The project is 8 days old, with 699 stars and one org.
  - (3) The Swift app (`build_app.sh`) compiles and launches a Python child process. It is **not needed** for the benchmark; skip it.
  - (4) The weights are a 10.5 GB opaque blob. Verify the LFS sha256 `ad2c3534ef6bd88525e22e5da3ac4fb739368406bf3b1c852cbafbade647c0fa` after download.

## 4. Exact MLX run path (for Tony's Mac, needs his explicit OK; nothing here has been run)
```bash
# Isolated dir + venv; Python 3.10+ (3.12 recommended), Apple silicon, macOS 13+
mkdir -p ~/haru-bench && cd ~/haru-bench
python3.12 -m venv .venv && source .venv/bin/activate
python -m pip install --upgrade pip pip-tools
cat > requirements.in <<'R'
haru-speech-mlx==0.1.0
mlx==0.32.4
R
pip-compile --generate-hashes --output-file requirements.txt requirements.in   # review the resolved list
pip install --require-hashes --no-deps -r requirements.txt
python -c "import hashlib,sys,haru_mlx;print(haru_mlx.__version__)"
# Checkpoint: explicit, revision-pinned, only the 3 files the loader needs (~10.56 GB)
huggingface-cli download higurashi-ai/Haru-4B config.json model.safetensors tokenizer.json \
  --revision 8d6e83bcd3701a76fc27a764965665da1df7da78 --local-dir ~/haru-bench/Haru-4B
shasum -a 256 ~/haru-bench/Haru-4B/model.safetensors   # expect ad2c3534…0fa
# Offline smoke run (file in, file out; local dir => no hub calls)
HF_HUB_OFFLINE=1 haru-mlx-inference user.wav reply.wav --model ~/haru-bench/Haru-4B \
  --system-prompt-file card.txt --seed 0 --stereo --transcript reply.jsonl [--quantize 8]
```
- **File input mode:** yes. `haru-mlx-inference INPUT.wav OUTPUT.wav` takes any sample rate (mixed to mono, resampled to 24 kHz). It feeds the audio frame by frame, as in a live call, and writes the model's side; `--stereo` puts the user on the left channel and the model on the right. It also prints the median ms per frame ([run_inference.py](https://github.com/higurashi-ai/Haru/blob/7fe6b7665f8bf035998f401f8cb779fbe53f2751/haru_mlx/haru_mlx/run_inference.py)).
- **Persona:** a text card via `--system-prompt(-file)`, built with `haru_mlx.prompt.render_card` and the bundled `card_templates.json` (fr and en included).
- **Voice:** `--reference` is optional (3–180 s, one speaker). Haru ships with no voices. For the benchmark, run **without** a reference (model default), or use a built-in macOS system voice clip. Apple's licence for reusing `say` output as a cloning reference is **not verified**, so default to no reference.
- **Synthetic user audio:** macOS `say -v Thomas` (fr_FR) / `say -v Samantha` (en_US) with `--data-format=LEI16@24000`, plus 0.5 s of leading silence and 6 s of trailing silence so Haru can answer. Check which voices are installed with `say -v '?'`.

## 5. Hot spots (per frame; 7.5 frames/s, budget 133 ms)
PyTorch path ([session.py@pinned](https://github.com/higurashi-ai/Haru/blob/7fe6b7665f8bf035998f401f8cb779fbe53f2751/haru/haru/session.py)):
1. **LM step via HF transformers** `Qwen3_5TextModel` + `DynamicCache`, run eagerly one position at a time. There is no CUDA graph for the LM, so Python and kernel-launch overhead is paid on every frame ([models/haru.py L109-111](https://github.com/higurashi-ai/Haru/blob/7fe6b7665f8bf035998f401f8cb779fbe53f2751/haru/haru/models/haru.py#L109-L111); [session.py L141-143](https://github.com/higurashi-ai/Haru/blob/7fe6b7665f8bf035998f401f8cb779fbe53f2751/haru/haru/session.py#L141-L143)). This is the most likely dominant cost and the main thing vLLM-Omni fixes.
2. **Full-vocab logits every frame:** 2560 × 248,320 matmul, plus an fp32 cast ([haru.py L113-115](https://github.com/higurashi-ai/Haru/blob/7fe6b7665f8bf035998f401f8cb779fbe53f2751/haru/haru/models/haru.py#L113-L115)). This happens even on the many PAD frames.
3. **Codec:** the default backend is `torch` at about 6 ms per encode or decode; Triton is opt-in at 0.7 ms ([session.py L44](https://github.com/higurashi-ai/Haru/blob/7fe6b7665f8bf035998f401f8cb779fbe53f2751/haru/haru/session.py#L44), README figures).
4. **Host syncs:** `int(token)` and `audio.cpu().numpy()` force a GPU→CPU sync on every frame ([session.py L166-171](https://github.com/higurashi-ai/Haru/blob/7fe6b7665f8bf035998f401f8cb779fbe53f2751/haru/haru/session.py#L166-L171)).
5. **DRY penalty in pure Python:** an O(lookback 1024 × match ≤32) scan per spoken token, plus new tensors built every frame ([sampling.py L26-77](https://github.com/higurashi-ai/Haru/blob/7fe6b7665f8bf035998f401f8cb779fbe53f2751/haru/haru/sampling.py#L26-L77)).
6. **Serving:** one model worker thread ([backends.py L124](https://github.com/higurashi-ai/Haru/blob/7fe6b7665f8bf035998f401f8cb779fbe53f2751/haru/haru/backends.py#L124)) and `--max-sessions 1` by default ([server.py L583](https://github.com/higurashi-ai/Haru/blob/7fe6b7665f8bf035998f401f8cb779fbe53f2751/haru/haru/server.py#L583)).

MLX path: it builds the whole frame lazily and runs a **single `mx.eval`** per frame ([haru_mlx session.py L166](https://github.com/higurashi-ai/Haru/blob/7fe6b7665f8bf035998f401f8cb779fbe53f2751/haru_mlx/haru_mlx/session.py#L166)). The Gated DeltaNet recurrence and the codec depthwise convs are custom Metal kernels. Python glue is therefore expected to be small, but that is **unmeasured**. The bench quantifies it.

## 6. Rust options (adds to Jarvis §4)
| Component | Best Rust mapping | Existing port? | Risk |
|---|---|---|---|
| Qwen3.5 backbone (24 Gated DeltaNet + 8 attention layers) | candle (Metal/CUDA) or mistral.rs; burn possible | No Rust Gated DeltaNet found; I did not do an exhaustive search | Needs a custom Metal + CUDA recurrence kernel; parity is hard (bf16 drift of 6e-2 to 1.4e-1 is already normal between backends, per the tests README) |
| VibeVoice causal codec (conv/convtranspose, depthwise mixer, streaming state) | candle conv1d, or ONNX export → `ort` | Not found | Streaming state handling; ONNX export of a stateful causal codec |
| MeanFlow 4-layer MLP head | trivial in candle/burn/ort | n/a | low |
| Tokenizer | `tokenizers` crate (already Rust) | yes | low |
| Sampling/DRY, framing, I/O | plain Rust | n/a | low; this is where Rust removes Python overhead |

llama.cpp/GGML: it has Qwen-family support, but whether it supports Qwen3.5 Gated DeltaNet as an *embeddings-in, hidden-out* backbone is **unknown**, and that would need verifying. **Recommendation:** first measure the glue share with the bench. Port only if the glue share or tail jitter is material. Even then, start with a Rust *orchestrator* around the existing kernels (or around vLLM-Omni), not a full model port.

## 7. Profiling plan (scope item c)
- **Plain vs instrumented runs** (`haru_bench.py --mode both`). Plain mode = the unmodified `session.step`, so its wall time is the true cost.
  - Instrumented mode = the same code with `mx.eval` barriers after each stage: encode, embed, LM, logits+sample, head, decode, host.
  - `glue_fraction = (total − Σ device stages) / total` is an upper bound on the Python/host share. The instrumented-minus-plain gap is the cost of the barriers themselves, i.e. the overlap MLX normally gets.
- **Python level:** `python -m cProfile -o prof.out haru_bench.py run … --mode plain --limit 4`, then `snakeviz`/`pstats`. Optionally `py-spy record -o flame.svg -- python haru_bench.py …`; py-spy needs `sudo` on macOS, so ask first.
- **GPU level (optional):** `mx.metal.start_capture("haru.gputrace")` around 10 frames, opened in Xcode Instruments, to see per-kernel time.
- **Decision rule:** if glue is ≥15–20 % of p50 step time **or** p95/p50 is >1.5, a Rust orchestrator is worth a spike. Otherwise Rust buys packaging, not speed. These thresholds are my proposal, not from any source.

## 8. Benchmark protocol
- **Inputs:** `/workspace/echo/research/bench_texts.json`. It has 10 FR + 10 EN invented sentences, 3 short (~5 words), 4 medium (~20–27) and 3 long (~53–67) per language. They are rendered as user speech with macOS system voices.
- **Configs:** {bf16, int8} × {no reference}, seed 0, 16 warm-up frames, persona card from the bundled fr/en templates.
- **Metrics per item:**
  - load time;
  - `start()` = prefill + frame 0 = **time to first audio**;
  - per-frame compute p50/p95/max;
  - **RTF** = Σ compute ÷ (frames × 133.3 ms);
  - **response latency** = first voiced model frame after the user's speech ends (audio time);
  - **peak memory** (`mx.get_peak_memory`, plus ru_maxrss);
  - per-stage timers and glue fraction.
- **Listening:** blind A/B (e.g. bf16 vs int8, guidance 1.2 vs 1.5 vs 1.8, temperature 0.6 vs 0.8). Raters hear randomised stereo files, use synthetic user speech only, and score naturalness and turn-taking on a 1–5 scale. Never use a real person's voice as the reference.
- **Script:** `/workspace/echo/bench/haru_bench.py` (`make-audio`, `run`, `selftest`). It never downloads anything (it requires a local `--model` dir and sets `HF_HUB_OFFLINE=1`). `selftest` passes on the box.

**Candidate first failing test for the plan stage**
- `test_bench_report_contract`: running `haru_bench.py run` with a **stub session** (fake model, canned frames) writes a `report.json` with `rtf`, `time_to_first_audio_ms`, `peak_mlx_bytes`, a `stages` key for all 7 stages, and `glue_fraction` in [0,1]. It fails today because there is no stub/backend injection point.
- TEST COMMAND: `cd /workspace/echo/bench && python -m pytest -q test_haru_bench.py::test_bench_report_contract`
- Later, for a Rust slice: `cargo test -p haru-codec --test parity` (Rust decode vs MLX reference latents within the published 2e-5 decoder tolerance).

## 9. Per-app notes (scope item d)
This section is based on the brief and FINDINGS.md only. **I did not read the Atlas, Athena, Métis or Zeus repos, so everything here is unverified.**
- **Atlas / Athena (Cloudflare Workers, FR+EN, Workers AI aura-2 TTS today):** Workers cannot host a 4B model. Haru also isn't TTS, so it cannot drop in behind the aura-2 call. The only path is an external WebSocket duplex endpoint (GPU or Mac) that replaces the voice loop, which conflicts with the scripted interview/scoring logic. Recommendation: keep aura-2.
- **Métis (Windows):** Haru has no Windows/DirectML path. Options are PyTorch CUDA on an NVIDIA GPU with ~12 GB, or a remote endpoint. Haru isn't relevant to recording/transcription.
- **Zeus (macOS Swift):** this is the natural fit. `haru_mlx/swift` already shows a Swift client talking to `haru_mlx.native` over a Unix socket ([Connection.swift](https://github.com/higurashi-ai/Haru/blob/7fe6b7665f8bf035998f401f8cb779fbe53f2751/haru_mlx/swift/Shared/Connection.swift)). It needs ≥16 GB unified memory (int8).

## 10. Substrate (scope item e)
FINDINGS.md already covers it, and I agree with it: Apache-2.0, Go, 7,992 stars, created 2026-05-13, pushed 2026-11-20, CNCF topic, homepage ate.dev, 983 open issues (GitHub API at 15:09 BRT). It is a Kubernetes agent-sandbox runtime with no voice/TTS role, so it does not fit Atlas, Athena, Métis or Zeus. Nothing to add.

## 11. Open questions for Tony (via Jarvis)
1. Which "Dessa": the Block full-duplex model (likely) or the 2019 Dessa RealTalk demo?
2. Is the goal a **TTS** for fixed text (then Haru is the wrong base) or a **duplex voice agent** (then Haru fits, but it replaces the loop)?
3. Mac model and unified memory size (≥16 GB for int8, 24 GB+ preferred for bf16)? OK to create `~/haru-bench`, install the hash-locked venv and download 10.56 GB?
4. Any GPU hosting budget (L4 ≈ $0.80/h us-east-1, $1.37/h São Paulo), or Mac-only?
5. Voices: is no reference acceptable, or will Tony provide an owned/consented voice? Which persona card for FR and EN?
6. Which app first: Zeus (on-device), as suggested here?
