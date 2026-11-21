#!/usr/bin/env python3
"""Deterministic, seeded, synthetic speech-like workload (no real voices, no TTS).

Each "utterance" is a sequence of syllables: a glottal pulse train with a
slowly varying F0 (90-240 Hz) shaped by three formant resonators picked from a
small vowel table, with occasional noise fricatives, Hann syllable envelopes
(~4 Hz syllable rate) and 0.2-0.8 s pauses between phrases. Written as int16
WAV (what a mic recording usually is) plus one raw float32 48 kHz stream file
(what Zeus's client sends haru-mlx-native over the socket).

    python gen_workload.py OUTDIR
"""
import hashlib, json, sys
from pathlib import Path
import numpy as np
from scipy.signal import lfilter
import soundfile as sf

VOWELS = [(730, 1090, 2440), (270, 2290, 3010), (300, 870, 2240), (530, 1840, 2480),
          (660, 1720, 2410), (490, 1350, 1690), (570, 840, 2410), (440, 1020, 2240)]


def resonator(x, f, bw, sr):
    r = np.exp(-np.pi * bw / sr)
    a = [1.0, -2 * r * np.cos(2 * np.pi * f / sr), r * r]
    return lfilter([1.0 - r], a, x)


def speechlike(seconds, sr, seed, channels=1):
    rng = np.random.default_rng(seed)
    n = int(round(seconds * sr))
    out = np.zeros(n)
    pos = int(0.3 * sr)
    while pos < n:
        phrase_syll = rng.integers(3, 12)
        f0_base = rng.uniform(90, 240)
        for s in range(phrase_syll):
            dur = int(rng.uniform(0.12, 0.30) * sr)
            if pos + dur >= n:
                break
            t = np.arange(dur) / sr
            f0 = f0_base * (1 + 0.08 * np.sin(2 * np.pi * rng.uniform(0.5, 2) * t)) * (1 - 0.15 * s / phrase_syll)
            phase = np.cumsum(f0 / sr)
            pulses = np.diff(np.floor(phase), prepend=0.0)  # one impulse per glottal period
            src = lfilter([1.0], [1.0, -0.97], pulses)      # glottal roll-off
            v = VOWELS[rng.integers(len(VOWELS))]
            y = sum(resonator(src, f, 60 + 0.06 * f, sr) * g for f, g in zip(v, (1.0, 0.5, 0.25)) if f < sr / 2 - 200)
            if rng.random() < 0.3:  # fricative onset
                k = dur // 4
                noise = rng.standard_normal(k) * 0.3
                y[:k] += lfilter([1, -1], [1], noise)
            out[pos:pos + dur] += y * np.hanning(dur)
            pos += dur
        pos += int(rng.uniform(0.2, 0.8) * sr)
    out *= 10 ** (-20 / 20) / (np.sqrt(np.mean(out ** 2)) + 1e-12)  # -20 dBFS RMS
    out = np.clip(out, -0.99, 0.99)
    if channels == 2:  # right channel: same talker, slightly delayed and quieter (room mic)
        d = int(0.0007 * sr)
        right = np.concatenate([np.zeros(d), out[:-d]]) * 0.8
        out = np.stack([out, right], axis=1)
    return out


FILES = [  # name, rate, channels, seconds, seed
    ("user_16k_mono.wav", 16000, 1, 120, 1),
    ("user_44k1_mono.wav", 44100, 1, 120, 2),
    ("user_48k_mono.wav", 48000, 1, 120, 3),
    ("user_48k_stereo.wav", 48000, 2, 120, 4),
    ("user_24k_mono.wav", 24000, 1, 120, 5),
]
STREAM = ("stream_48k.f32", 48000, 600, 6)


def main(out):
    out = Path(out); out.mkdir(parents=True, exist_ok=True)
    manifest = {"files": [], "stream": None, "generator": "gen_workload.py", "frame_samples": 3200, "sample_rate": 24000}
    for name, sr, ch, sec, seed in FILES:
        x = speechlike(sec, sr, seed, ch)
        sf.write(out / name, x.astype(np.float32), sr, subtype="PCM_16")
        manifest["files"].append({"file": name, "rate": sr, "channels": ch, "seconds": sec, "seed": seed,
                                  "sha256": hashlib.sha256((out / name).read_bytes()).hexdigest()})
    name, sr, sec, seed = STREAM
    x = speechlike(sec, sr, seed).astype("<f4")
    (out / name).write_bytes(x.tobytes())
    manifest["stream"] = {"file": name, "rate": sr, "channels": 1, "seconds": sec, "seed": seed, "format": "f32le",
                          "sha256": hashlib.sha256((out / name).read_bytes()).hexdigest()}
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2))
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main(sys.argv[1])
