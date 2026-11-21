"""Linux A/B for clause-chunked Kokoro time to first audio.

Not an app dependency. Install the harness tools by hand, then point this at
the Kokoro v1.0 weights:

    python3 -m pip install 'kokoro-onnx==0.4.9' 'pyloudnorm==0.1.1' soundfile
    # weights in --cache, the same URLs qa/voice/render_kokoro.py uses

The before row is Kokoro.create of the whole long answer. The after row is
Kokoro.create of the first clause only, which is what the clause scheduler
would have to wait for. Loudness after polish is a gain to -16 LUFS and then
a 4x true-peak limit at -1 dBTP, the same targets as VoiceStreamPolish.
"""

from __future__ import annotations

import argparse
import json
import time
from pathlib import Path

import numpy as np
import pyloudnorm
import soundfile as sf
from scipy.signal import resample_poly

LONG_ANSWER = (
    "The reply is spoken one sentence at a time. Each sentence is rendered by the engine that is ready, "
    "then handed to the player while the next sentence is still being prepared. A short pause sits between "
    "sentences so the line does not run together. If the preferred engine has no key, no model, or a recent "
    "failure, the next engine in the chain takes that sentence. The last engine is the system voice: it renders "
    "buffers, lowers the pitch, and slows the rate before the same player speaks them. This paragraph is synthetic "
    "fixture text for a voice harness. It names no person, no account, and no private recording. The numbers here "
    "are only a shape, such as section 4 and step 2, and they are not a measurement."
)


def metrics(samples: np.ndarray, rate: int) -> dict:
    mono = np.asarray(samples, dtype=np.float64).reshape(-1)
    loudness = float(pyloudnorm.Meter(rate).integrated_loudness(mono))
    peak = float(np.max(np.abs(resample_poly(mono, 4, 1))))
    dbtp = float(20 * np.log10(peak)) if peak > 0 else float("-inf")
    return {"integrated_lufs": loudness, "true_peak": peak, "true_peak_dbtp": dbtp}


def polish(samples: np.ndarray, rate: int) -> np.ndarray:
    raw = metrics(samples, rate)
    gain = 10 ** ((-16.0 - raw["integrated_lufs"]) / 20.0)
    scaled = np.asarray(samples, dtype=np.float64).reshape(-1) * gain
    peak = float(np.max(np.abs(resample_poly(scaled, 4, 1))))
    ceiling = 10 ** (-1.0 / 20.0)
    if peak > ceiling:
        scaled *= ceiling * (1 - 1e-6) / peak
    return scaled


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cache", type=Path, default=Path.home() / ".cache" / "zeus-voice-qa")
    parser.add_argument("--fixture-wav", type=Path, required=True)
    parser.add_argument("--fixture-timing", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    from kokoro_onnx import Kokoro

    timing = json.loads(args.fixture_timing.read_text(encoding="utf-8"))
    fixture, fixture_rate = sf.read(args.fixture_wav, always_2d=True)
    fixture_mono = fixture.mean(axis=1)
    first = LONG_ANSWER.split(". ", 1)[0] + "."

    started = time.perf_counter()
    engine = Kokoro(str(args.cache / "kokoro-v1.0.onnx"), str(args.cache / "voices-v1.0.bin"))
    load_s = time.perf_counter() - started

    def synthesize(text: str):
        mark = time.perf_counter()
        audio, rate = engine.create(text, voice="bm_george", speed=0.88, lang="en-gb")
        return np.asarray(audio, dtype=np.float64), int(rate), time.perf_counter() - mark

    full_audio, rate, full_s = synthesize(LONG_ANSWER)
    clause_audio, clause_rate, clause_s = synthesize(first)
    polished_full = polish(full_audio, rate)
    polished_clause = polish(clause_audio, clause_rate)
    report = {
        "label": "Linux-harness numbers. Not an M-series Mac measurement.",
        "voice": "bm_george",
        "speed": 0.88,
        "lang": "en-gb",
        "model_load_s": load_s,
        "full_chars": len(LONG_ANSWER),
        "first_clause": first,
        "first_clause_chars": len(first),
        "proposed_ttfa_budget_s": 1.0,
        "proposed_ttfa_budget_note": "Warm Kokoro on an M-series Mac, first clause of 40-90 characters. Proposed, not measured on a Mac.",
        "fixture_ttfa_s": timing["first_audio_s"],
        "fixture": metrics(fixture_mono, int(fixture_rate)),
        "host_full_render_s": full_s,
        "host_full": metrics(full_audio, rate),
        "host_first_clause_s": clause_s,
        "host_first_clause": metrics(clause_audio, clause_rate),
        "polished_full": metrics(polished_full, rate),
        "polished_first_clause": metrics(polished_clause, clause_rate),
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
