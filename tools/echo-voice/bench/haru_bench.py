#!/usr/bin/env python3
"""Haru-4B (MLX) benchmark: latency, real-time factor, memory, per-stage timers.

Runs INSIDE an isolated venv that has haru_mlx installed from a pinned commit of
https://github.com/higurashi-ai/Haru (written against 7fe6b7665f8bf035998f401f8cb779fbe53f2751).
Nothing here downloads anything by itself: pass --model DIR pointing at a local
checkpoint directory (config.json, model.safetensors, tokenizer.json) that you
fetched and hash-checked beforehand.

Haru is speech-to-speech (full duplex). The benchmark texts are the USER side:
each one is synthesised with a built-in macOS system voice (`say`), followed by
silence so the model can answer, and fed frame by frame. We capture the model's
audio + text stream. We never feed or clone a real person's voice.

Subcommands
  make-audio  texts JSON -> one 24 kHz mono WAV per item (macOS `say` + silence tail)
  run         benchmark the model over those WAVs -> report JSON + reply WAVs
  selftest    check the pure helpers (no MLX needed)

Examples
  python haru_bench.py make-audio --texts bench_texts.json --out audio/ \
      --voice-fr Thomas --voice-en Samantha --tail 6
  python haru_bench.py run --model ~/models/Haru-4B --audio audio/ --out results/ \
      --quantize none --seed 0 --mode both
"""

from __future__ import annotations

import argparse
import json
import math
import os
import platform
import resource
import statistics
import subprocess
import sys
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path

SAMPLE_RATE = 24_000
FRAME_SAMPLES = 3_200
FRAME_SECONDS = FRAME_SAMPLES / SAMPLE_RATE  # 0.1333 s
PINNED_COMMIT = "7fe6b7665f8bf035998f401f8cb779fbe53f2751"

# --------------------------------------------------------------------------- pure helpers


def percentile(values: list[float], q: float) -> float:
    """Linear-interpolated percentile, q in [0, 100]."""
    if not values:
        return float("nan")
    xs = sorted(values)
    if len(xs) == 1:
        return xs[0]
    pos = (len(xs) - 1) * q / 100.0
    lo, hi = math.floor(pos), math.ceil(pos)
    return xs[lo] + (xs[hi] - xs[lo]) * (pos - lo)


def summarize(values: list[float]) -> dict[str, float]:
    if not values:
        return {"n": 0}
    return {
        "n": len(values),
        "mean_ms": 1000 * statistics.fmean(values),
        "p50_ms": 1000 * percentile(values, 50),
        "p95_ms": 1000 * percentile(values, 95),
        "max_ms": 1000 * max(values),
    }


def real_time_factor(compute_seconds: float, frames: int) -> float:
    """Compute time / audio time produced. < 1 means faster than real time."""
    if frames <= 0:
        return float("nan")
    return compute_seconds / (frames * FRAME_SECONDS)


def rms_dbfs(samples) -> float:
    n = len(samples)
    if n == 0:
        return -math.inf
    acc = 0.0
    for s in samples:
        acc += float(s) * float(s)
    rms = math.sqrt(acc / n)
    return -math.inf if rms <= 0 else 20 * math.log10(rms)


def first_voiced_frame(frames_dbfs: list[float], tokens: list[int], silent_ids: set[int],
                       start_index: int, threshold_dbfs: float = -40.0) -> int | None:
    """Index of the first model frame at/after start_index that is audibly speaking
    (audio above threshold) or carries a non-silent text token."""
    for i in range(start_index, len(frames_dbfs)):
        if frames_dbfs[i] > threshold_dbfs or (i < len(tokens) and tokens[i] not in silent_ids):
            return i
    return None


def speech_end_seconds(user_dbfs_per_frame: list[float], threshold_dbfs: float = -45.0) -> float:
    """End time (s) of the last user frame above threshold."""
    last = -1
    for i, d in enumerate(user_dbfs_per_frame):
        if d > threshold_dbfs:
            last = i
    return (last + 1) * FRAME_SECONDS


def peak_rss_bytes() -> int:
    r = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    return int(r) if sys.platform == "darwin" else int(r) * 1024  # macOS: bytes, Linux: KiB


# --------------------------------------------------------------------------- make-audio


def cmd_make_audio(args) -> None:
    if sys.platform != "darwin":
        sys.exit("make-audio uses macOS `say`; run it on the Mac")
    texts = json.loads(Path(args.texts).read_text(encoding="utf-8"))
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    import numpy as np
    import soundfile as sf

    voices = {"fr": args.voice_fr, "en": args.voice_en}
    manifest = []
    for lang in ("fr", "en"):
        for item in texts[lang]:
            raw = out / f"{item['id']}.raw.wav"
            subprocess.run(
                ["say", "-v", voices[lang], "-o", str(raw), "--file-format=WAVE",
                 f"--data-format=LEI16@{SAMPLE_RATE}", item["text"]],
                check=True,
            )
            audio, sr = sf.read(str(raw), dtype="float32", always_2d=True)
            assert sr == SAMPLE_RATE, sr
            mono = audio.mean(axis=1)
            lead = np.zeros(int(args.lead * SAMPLE_RATE), dtype=np.float32)
            tail = np.zeros(int(args.tail * SAMPLE_RATE), dtype=np.float32)
            full = np.concatenate([lead, mono, tail])
            path = out / f"{item['id']}.wav"
            sf.write(str(path), full, SAMPLE_RATE)
            raw.unlink()
            manifest.append({"id": item["id"], "lang": lang, "length": item["length"], "voice": voices[lang],
                             "speech_seconds": len(mono) / SAMPLE_RATE, "file": path.name})
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False))
    print(f"wrote {len(manifest)} files to {out}")


# --------------------------------------------------------------------------- run


@dataclass
class ItemResult:
    id: str
    lang: str
    mode: str
    frames: int = 0
    prefill_seconds: float = 0.0          # session.start(): prompt prefill + frame 0
    time_to_first_audio_ms: float = 0.0   # wall clock from start() call to frame 0 audio in hand
    response_latency_ms: float | None = None  # first voiced model frame after user speech end (audio time)
    step: dict = field(default_factory=dict)
    stages: dict = field(default_factory=dict)  # instrumented mode only
    glue_fraction: float | None = None
    rtf: float = 0.0
    text: str = ""


STAGES = ("encode", "embed", "lm", "logits_sample", "head", "decode", "host")


def _peak_mlx(mx) -> int | None:
    for fn in ("get_peak_memory",):
        if hasattr(mx, fn):
            return int(getattr(mx, fn)())
    metal = getattr(mx, "metal", None)
    if metal is not None and hasattr(metal, "get_peak_memory"):
        return int(metal.get_peak_memory())
    return None


def _reset_peak_mlx(mx) -> None:
    if hasattr(mx, "reset_peak_memory"):
        mx.reset_peak_memory()
    elif getattr(mx, "metal", None) is not None and hasattr(mx.metal, "reset_peak_memory"):
        mx.metal.reset_peak_memory()


def make_instrumented_step(session, mx, np):
    """A copy of DuplexSession.step/_emit at the pinned commit, with an mx.eval
    barrier after every stage so each stage's GPU time is attributable.
    Barriers serialise work MLX could otherwise overlap: compare the total
    against plain mode to see their cost."""
    from haru_mlx.sampling import sample_token

    model, cfg = session.model, session.config
    timers = {k: [] for k in STAGES}

    def step(user_audio):
        t0 = time.perf_counter()
        audio = np.asarray(user_audio, dtype=np.float32).reshape(-1)
        session._codec.feed(mx.array(audio))
        user_latent = model.codec.sample(session._codec.pop(), session._next_key())
        mx.eval(user_latent, session._codec.arrays())
        t1 = time.perf_counter()
        embeddings = model.embed(session._token[None], session._latent[None], user_latent)
        mx.eval(embeddings)
        t2 = time.perf_counter()
        hidden = model(embeddings, session._cache)[:, -1]
        mx.eval(hidden, session._cache_arrays())
        t3 = time.perf_counter()
        logits = model.logits(hidden)
        if session._dry is not None:
            session._dry.apply(logits)
        logits[:, session._stream_ids] = model.logits_fp32(hidden, session._stream_ids)
        if cfg.eop_bias:
            logits[:, session.eop_id] = logits[:, session.eop_id] + cfg.eop_bias
        if session._force_text > 0:
            logits[:, mx.array(session._banned, dtype=mx.int32)] = -mx.inf
            session._force_text -= 1
        token = sample_token(logits, cfg.temperature, cfg.top_k, cfg.top_p, session._next_key())
        mx.eval(token)
        t4 = time.perf_counter()
        noise = mx.random.normal((1, model.config.latent_dim), key=session._next_key()).astype(model.dtype)
        latent = model.unscale_latents(model.head.sample(hidden, noise, cfg.guidance_scale))
        mx.eval(latent)
        t5 = time.perf_counter()
        out = mx.clip(session._codec.decode(latent[None])[0], -1.0, 1.0)
        mx.eval(out, session._codec.arrays())
        t6 = time.perf_counter()
        session._token, session._latent = token, latent
        token_id = int(token.item())
        if session._dry is not None:
            session._dry.update(token_id)
        audio_np = np.array(out, dtype=np.float32)
        text = session._detokenizer.push(token_id)
        session.index += 1
        t7 = time.perf_counter()
        for k, a, b in zip(STAGES, (t0, t1, t2, t3, t4, t5, t6), (t1, t2, t3, t4, t5, t6, t7)):
            timers[k].append(b - a)
        return audio_np, token_id, text, t7 - t0

    return step, timers


def cmd_run(args) -> None:
    import numpy as np
    import soundfile as sf
    import mlx.core as mx
    import haru_mlx
    from haru_mlx.models import load_model
    from haru_mlx.session import DuplexConfig, DuplexSession

    audio_dir, out = Path(args.audio), Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((audio_dir / "manifest.json").read_text())
    if args.limit:
        manifest = manifest[: args.limit]

    system_prompt = Path(args.system_prompt_file).read_text(encoding="utf-8").strip() if args.system_prompt_file else ""
    reference = None
    if args.reference:
        from haru_mlx.audio import load_audio, prepare_reference
        reference = prepare_reference(load_audio(args.reference))

    _reset_peak_mlx(mx)
    t = time.perf_counter()
    model = load_model(args.model, quantize=None if args.quantize == "none" else int(args.quantize))
    load_seconds = time.perf_counter() - t
    silent = {model.config.pad_token_id, model.config.eop_token_id}

    # Warm-up (kernel compilation, buffer pools) on silence; not reported.
    warm = DuplexSession(model, system_prompt, reference, DuplexConfig(seed=0))
    warm.start()
    for _ in range(args.warmup_frames):
        warm.step(np.zeros(FRAME_SAMPLES, dtype=np.float32))
    del warm

    modes = ["plain", "instrumented"] if args.mode == "both" else [args.mode]
    results: list[ItemResult] = []
    for item in manifest:
        user, sr = sf.read(str(audio_dir / item["file"]), dtype="float32")
        assert sr == SAMPLE_RATE, f"{item['file']}: {sr} Hz"
        count = max(1, -(-len(user) // FRAME_SAMPLES))
        user = np.pad(user, (0, count * FRAME_SAMPLES - len(user)))
        user_frames = [user[i * FRAME_SAMPLES:(i + 1) * FRAME_SAMPLES] for i in range(count)]
        end_s = speech_end_seconds([rms_dbfs(f) for f in user_frames])
        for mode in modes:
            cfg = DuplexConfig(seed=args.seed, guidance_scale=args.guidance_scale, max_frames=count + 1)
            session = DuplexSession(model, system_prompt, reference, cfg)
            r = ItemResult(id=item["id"], lang=item["lang"], mode=mode)
            t = time.perf_counter()
            f0 = session.start()
            r.prefill_seconds = time.perf_counter() - t
            r.time_to_first_audio_ms = 1000 * r.prefill_seconds
            audio_out, tokens, texts, step_s = [f0.audio], [f0.token], [f0.text], []
            if mode == "plain":
                for i in range(count - 1):
                    fr = session.step(user_frames[i])
                    audio_out.append(fr.audio); tokens.append(fr.token); texts.append(fr.text)
                    step_s.append(fr.seconds)
            else:
                step, timers = make_instrumented_step(session, mx, np)
                for i in range(count - 1):
                    a, tok, txt, sec = step(user_frames[i])
                    audio_out.append(a); tokens.append(tok); texts.append(txt); step_s.append(sec)
                r.stages = {k: summarize(v) for k, v in timers.items()}
                total = sum(step_s)
                device = sum(sum(timers[k]) for k in STAGES if k != "host")
                # Upper bound on host/Python share: everything not inside a stage barrier.
                r.glue_fraction = (total - device) / total if total else None
            r.frames = len(step_s)
            r.step = summarize(step_s)
            r.rtf = real_time_factor(sum(step_s), len(step_s))
            dbfs = [rms_dbfs(a) for a in audio_out]
            start_idx = int(math.ceil(end_s / FRAME_SECONDS))
            v = first_voiced_frame(dbfs, tokens, silent, start_idx)
            r.response_latency_ms = None if v is None else 1000 * (v * FRAME_SECONDS - end_s)
            r.text = "".join(texts).strip()
            reply = np.concatenate(audio_out)[: len(user)]
            sf.write(str(out / f"{item['id']}.{mode}.wav"), np.stack([user, reply], axis=1), SAMPLE_RATE)
            results.append(r)
            print(f"{r.id:6s} {mode:12s} frames={r.frames:4d} p50={r.step.get('p50_ms', 0):6.1f} ms "
                  f"p95={r.step.get('p95_ms', 0):6.1f} ms rtf={r.rtf:.3f} prefill={r.prefill_seconds:.2f} s "
                  f"resp={r.response_latency_ms}", flush=True)

    report = {
        "pinned_commit": PINNED_COMMIT,
        "haru_mlx_version": getattr(haru_mlx, "__version__", "?"),
        "mlx_version": getattr(mx, "__version__", "?"),
        "python": sys.version.split()[0],
        "machine": platform.platform(),
        "chip": _chip(),
        "quantize": args.quantize,
        "seed": args.seed,
        "load_seconds": load_seconds,
        "peak_mlx_bytes": _peak_mlx(mx),
        "peak_rss_bytes": peak_rss_bytes(),
        "items": [asdict(r) for r in results],
    }
    for mode in modes:
        steps = [r.step["p50_ms"] for r in results if r.mode == mode and r.step.get("n")]
        report[f"{mode}_median_of_p50_ms"] = statistics.median(steps) if steps else None
        report[f"{mode}_median_rtf"] = statistics.median([r.rtf for r in results if r.mode == mode]) if steps else None
    (out / "report.json").write_text(json.dumps(report, indent=2, ensure_ascii=False))
    print(json.dumps({k: v for k, v in report.items() if k != "items"}, indent=2))


def _chip() -> str:
    try:
        return subprocess.run(["sysctl", "-n", "machdep.cpu.brand_string"], capture_output=True, text=True).stdout.strip()
    except Exception:
        return "?"


# --------------------------------------------------------------------------- selftest


def cmd_selftest(_args) -> None:
    assert percentile([1, 2, 3, 4], 50) == 2.5
    assert abs(real_time_factor(0.0434 * 10, 10) - 0.3255) < 1e-3
    assert rms_dbfs([0.0] * 10) == -math.inf
    assert abs(rms_dbfs([1.0] * 10)) < 1e-9
    assert first_voiced_frame([-90, -90, -30], [1, 1, 1], {1}, 0) == 2
    assert first_voiced_frame([-90, -90, -90], [1, 5, 1], {1}, 0) == 1
    assert first_voiced_frame([-90] * 3, [1] * 3, {1}, 0) is None
    assert abs(speech_end_seconds([-20, -20, -90, -90]) - 2 * FRAME_SECONDS) < 1e-9
    print("selftest ok")


def main(argv=None) -> None:
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = p.add_subparsers(dest="cmd", required=True)
    a = sub.add_parser("make-audio")
    a.add_argument("--texts", required=True)
    a.add_argument("--out", required=True)
    a.add_argument("--voice-fr", default="Thomas", help="built-in macOS voice (list: say -v '?')")
    a.add_argument("--voice-en", default="Samantha")
    a.add_argument("--lead", type=float, default=0.5, help="silence before the utterance (s)")
    a.add_argument("--tail", type=float, default=6.0, help="silence after it, for the model's reply (s)")
    r = sub.add_parser("run")
    r.add_argument("--model", required=True, help="LOCAL checkpoint dir (no implicit download)")
    r.add_argument("--audio", required=True)
    r.add_argument("--out", required=True)
    r.add_argument("--quantize", choices=("none", "8"), default="none")
    r.add_argument("--mode", choices=("plain", "instrumented", "both"), default="both")
    r.add_argument("--seed", type=int, default=0)
    r.add_argument("--guidance-scale", type=float, default=1.5)
    r.add_argument("--warmup-frames", type=int, default=16)
    r.add_argument("--limit", type=int, default=0)
    r.add_argument("--system-prompt-file")
    r.add_argument("--reference", help="optional voice clip; only a synthetic/system voice you may use")
    sub.add_parser("selftest")
    args = p.parse_args(argv)
    if args.cmd == "run" and not Path(args.model).expanduser().is_dir():
        sys.exit("--model must be a local directory (this script never downloads)")
    {"make-audio": cmd_make_audio, "run": cmd_run, "selftest": cmd_selftest}[args.cmd](args)


if __name__ == "__main__":
    os.environ.setdefault("HF_HUB_OFFLINE", "1")  # belt and braces: no hub calls during the run
    main()
