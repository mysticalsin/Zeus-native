"""Provider-agnostic measurements for one rendered utterance.

`measure` reads a WAV and a timing JSON. Integrated loudness is pyloudnorm's
ITU-R BS.1770 implementation. Silence, gaps, clipping, onset, true peak, speech
rate, pitch variance and barge-in latency are defined with the constants below
so a synthetic fixture has one expected result.

The timing object may contain:

- ``request_start_s``: timeline zero for the request. Default 0.
- ``wav_origin_s``: timeline time of sample 0. Default 0.
- ``first_audio_s``: when the engine first had audio. When this is present,
  time to first audio is ``first_audio_s - request_start_s``. Otherwise it is
  the first non-silent sample mapped through ``wav_origin_s``.
- ``text`` or ``word_count``: used for the speech rate.
- ``barge_in_requested_s`` and ``playback_stopped_s``: both are required before
  a stop latency is reported. A missing pair stays null.
"""

from __future__ import annotations

import json
import math
from pathlib import Path

import numpy as np
import pyloudnorm as pyln
import soundfile as sf
from scipy.signal import resample_poly

FRAME_S = 0.01
SILENCE_RMS = 0.01
# A silence shorter than this is inside a chunk. Kokoro's clause pause is 0.10 s.
MIN_GAP_S = 0.10
CLIP_AMPLITUDE = 0.999
ONSET_WINDOW_S = 0.020
TRUE_PEAK_FACTOR = 4
F0_MIN_HZ = 70.0
F0_MAX_HZ = 400.0
PITCH_FRAME_S = 0.040
PITCH_HOP_S = 0.010
VOWELS = set("aeiouyàâäéèêëîïôùûüœæ")


def count_syllables(text: str) -> int:
    """Count vowel groups. A word with letters but no vowel still counts as one."""
    total = 0
    for raw in text.split():
        word = "".join(ch for ch in raw.lower() if ch.isalpha())
        if not word:
            continue
        groups = 0
        in_vowel = False
        for ch in word:
            vowel = ch in VOWELS
            if vowel and not in_vowel:
                groups += 1
            in_vowel = vowel
        total += max(groups, 1)
    return total


def measure(wav_path: str | Path, timing_path: str | Path) -> dict:
    samples, sample_rate = _read_mono(wav_path)
    timing = json.loads(Path(timing_path).read_text(encoding="utf-8"))
    return measure_samples(samples, sample_rate, timing)


def measure_samples(samples: np.ndarray, sample_rate: int, timing: dict | None = None) -> dict:
    timing = timing or {}
    samples = np.asarray(samples, dtype=np.float64).reshape(-1)
    rate = int(sample_rate)
    duration_s = float(len(samples) / rate) if rate else 0.0
    onset = _onset_index(samples)
    silent, frame = _silence_mask(samples, rate)
    gaps = _gaps(silent)
    clipping_count = int(np.count_nonzero(np.abs(samples) >= CLIP_AMPLITUDE)) if len(samples) else 0
    leading_count = _leading_clips(samples, onset, rate)
    true_peak = _true_peak(samples)
    loudness = _integrated_lufs(samples, rate)
    words, syllables = _counts(timing)
    active_s = float(np.count_nonzero(~silent) * FRAME_S) if len(silent) else 0.0
    pitch_median, pitch_std, pitch_var = _pitch(samples, rate)
    return {
        "sample_rate": rate,
        "duration_s": duration_s,
        "ttfa_s": _ttfa(timing, onset, rate),
        "wav_onset_s": None if onset is None else float(onset / rate),
        "inter_chunk_gaps_s": gaps,
        "integrated_lufs": loudness,
        "true_peak": true_peak,
        "true_peak_dbtp": _db(true_peak),
        "clipping_count": clipping_count,
        "leading_onset_clip_count": leading_count,
        "leading_onset_clipped": leading_count > 0,
        "word_count": words,
        "syllable_count": syllables,
        "speech_rate_wps": None if words is None or active_s <= 0 else float(words / active_s),
        "speech_rate_sps": None if syllables is None or active_s <= 0 else float(syllables / active_s),
        "active_speech_s": active_s,
        "pitch_median_hz": pitch_median,
        "pitch_std_hz": pitch_std,
        "pitch_variance_hz2": pitch_var,
        "barge_in_stop_latency_s": _barge_in(timing),
        "frame_s": FRAME_S,
        "frame_samples": frame,
    }


def _read_mono(wav_path: str | Path) -> tuple[np.ndarray, int]:
    data, sample_rate = sf.read(wav_path, always_2d=True, dtype="float64")
    if data.shape[1] == 1:
        mono = data[:, 0]
    else:
        mono = data.mean(axis=1)
    return mono, int(sample_rate)


def _onset_index(samples: np.ndarray) -> int | None:
    if len(samples) == 0:
        return None
    hits = np.flatnonzero(np.abs(samples) >= SILENCE_RMS)
    if len(hits) == 0:
        return None
    return int(hits[0])


def _silence_mask(samples: np.ndarray, rate: int) -> tuple[np.ndarray, int]:
    frame = max(1, int(round(FRAME_S * rate)))
    count = len(samples) // frame
    if count == 0:
        return np.zeros(0, dtype=bool), frame
    trimmed = samples[: count * frame].reshape(count, frame)
    rms = np.sqrt(np.mean(trimmed * trimmed, axis=1))
    return rms < SILENCE_RMS, frame


def _gaps(silent: np.ndarray) -> list[float]:
    gaps: list[float] = []
    seen_speech = False
    run = 0
    for is_silent in silent:
        if bool(is_silent):
            run += 1
            continue
        if seen_speech and run * FRAME_S >= MIN_GAP_S:
            gaps.append(float(run * FRAME_S))
        seen_speech = True
        run = 0
    return gaps


def _leading_clips(samples: np.ndarray, onset: int | None, rate: int) -> int:
    if onset is None:
        return 0
    window = max(1, int(round(ONSET_WINDOW_S * rate)))
    segment = samples[onset : onset + window]
    return int(np.count_nonzero(np.abs(segment) >= CLIP_AMPLITUDE))


def _true_peak(samples: np.ndarray) -> float:
    if len(samples) == 0:
        return 0.0
    oversampled = resample_poly(samples, TRUE_PEAK_FACTOR, 1)
    if len(oversampled) == 0:
        return 0.0
    return float(np.max(np.abs(oversampled)))


def _integrated_lufs(samples: np.ndarray, rate: int) -> float:
    if len(samples) == 0 or rate <= 0:
        return float("-inf")
    meter = pyln.Meter(rate)
    loudness = meter.integrated_loudness(samples)
    return float(loudness)


def _counts(timing: dict) -> tuple[int | None, int | None]:
    text = timing.get("text")
    if isinstance(text, str) and text.strip():
        words = int(timing["word_count"]) if timing.get("word_count") is not None else len(text.split())
        return words, count_syllables(text)
    if timing.get("word_count") is not None:
        return int(timing["word_count"]), None
    return None, None


def _ttfa(timing: dict, onset: int | None, rate: int) -> float | None:
    request_start = float(timing.get("request_start_s", 0.0))
    if timing.get("first_audio_s") is not None:
        return float(timing["first_audio_s"]) - request_start
    if onset is None:
        return None
    origin = float(timing.get("wav_origin_s", 0.0))
    return origin + (onset / rate) - request_start


def _barge_in(timing: dict) -> float | None:
    requested = timing.get("barge_in_requested_s")
    stopped = timing.get("playback_stopped_s")
    if requested is None or stopped is None:
        return None
    return float(stopped) - float(requested)


def _pitch(samples: np.ndarray, rate: int) -> tuple[float | None, float | None, float | None]:
    frame_len = max(1, int(round(PITCH_FRAME_S * rate)))
    hop = max(1, int(round(PITCH_HOP_S * rate)))
    if len(samples) < frame_len:
        return None, None, None
    min_lag = max(1, int(rate / F0_MAX_HZ))
    max_lag = max(min_lag + 1, int(rate / F0_MIN_HZ))
    found: list[float] = []
    start = 0
    while start + frame_len <= len(samples):
        frame = samples[start : start + frame_len]
        frame = frame - np.mean(frame)
        energy = float(np.dot(frame, frame))
        if energy >= 1e-8:
            corr = np.correlate(frame, frame, mode="full")[frame_len - 1 :]
            if max_lag < len(corr):
                lag = int(np.argmax(corr[min_lag : max_lag + 1])) + min_lag
                if corr[0] > 0 and corr[lag] / corr[0] > 0.3:
                    shift = 0.0
                    if 0 < lag < len(corr) - 1:
                        left, center, right = float(corr[lag - 1]), float(corr[lag]), float(corr[lag + 1])
                        denom = left - 2 * center + right
                        if denom != 0:
                            shift = 0.5 * (left - right) / denom
                    f0 = rate / (lag + shift)
                    if F0_MIN_HZ <= f0 <= F0_MAX_HZ:
                        found.append(float(f0))
        start += hop
    if not found:
        return None, None, None
    values = np.asarray(found, dtype=np.float64)
    return float(np.median(values)), float(np.std(values)), float(np.var(values))


def _db(amplitude: float) -> float:
    if amplitude <= 0:
        return float("-inf")
    return float(20 * math.log10(amplitude))
