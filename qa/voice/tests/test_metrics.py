"""Red tests for the voice QA metrics.

The fixtures are synthetic. A 200 Hz sine and a block of digital silence have
known integrated loudness from pyloudnorm 0.1.1 (ITU-R BS.1770). A second
buffer has a 0.20 s silent gap on a 10 ms frame grid, and three samples at
full scale.

Nothing here is a recording of a person.
"""

from __future__ import annotations

import importlib.util
import json
import math
from pathlib import Path

import numpy as np
import pytest
import soundfile as sf

RATE = 48_000
VOICE_ROOT = Path(__file__).resolve().parents[1]
# pyloudnorm 0.1.1, numpy 2.5.5, on the unfaded 200 Hz sine defined below.
SINE_LUFS = -16.048946659687424
# scipy 1.18.1 resample_poly, 4x, of that same finite buffer. The analytic
# amplitude is 0.25; the higher peak is the resampler's edge response.
SINE_TRUE_PEAK = 0.2832999554539534


def load(filename: str):
    path = VOICE_ROOT / filename
    if not path.is_file():
        pytest.fail(f"missing {path}")
    spec = importlib.util.spec_from_file_location(f"zeus_voice_{path.stem}", path)
    if spec is None or spec.loader is None:
        pytest.fail(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def sine(seconds: float, frequency: float, amplitude: float, phase: float = math.pi / 2) -> np.ndarray:
    count = int(round(seconds * RATE))
    time = np.arange(count, dtype=np.float64) / RATE
    return (amplitude * np.sin(2 * math.pi * frequency * time + phase)).astype(np.float64)


def write_case(directory: Path, name: str, samples: np.ndarray, timing: dict) -> tuple[Path, Path]:
    wav_path = directory / f"{name}.wav"
    timing_path = directory / f"{name}.timing.json"
    sf.write(wav_path, samples.astype(np.float32), RATE, subtype="FLOAT")
    timing_path.write_text(json.dumps(timing), encoding="utf-8")
    return wav_path, timing_path


def test_sine_loudness_true_peak_pitch_and_rate(tmp_path: Path) -> None:
    metrics = load("metrics.py")
    samples = sine(1.0, 200.0, 0.25)
    wav_path, timing_path = write_case(
        tmp_path,
        "sine",
        samples,
        {
            "request_start_s": 0.0,
            "wav_origin_s": 0.0,
            "text": "one two three four",
            "barge_in_requested_s": 0.40,
            "playback_stopped_s": 0.47,
        },
    )
    result = metrics.measure(wav_path, timing_path)

    assert result["sample_rate"] == RATE
    assert result["integrated_lufs"] == pytest.approx(SINE_LUFS, abs=0.01)
    assert result["true_peak"] == pytest.approx(SINE_TRUE_PEAK, abs=1e-4)
    assert result["true_peak_dbtp"] == pytest.approx(20 * math.log10(SINE_TRUE_PEAK), abs=0.01)
    assert result["clipping_count"] == 0
    assert result["leading_onset_clip_count"] == 0
    assert result["leading_onset_clipped"] is False
    assert result["ttfa_s"] == pytest.approx(0.0, abs=1e-6)
    assert result["inter_chunk_gaps_s"] == []
    assert result["word_count"] == 4
    assert result["speech_rate_wps"] == pytest.approx(4.0, abs=1e-6)
    assert metrics.count_syllables("one two three four") == 5
    assert metrics.count_syllables("Bonjour") == 2
    assert result["syllable_count"] == 5
    assert result["speech_rate_sps"] == pytest.approx(5.0, abs=1e-6)
    assert result["pitch_median_hz"] == pytest.approx(200.0, abs=2.0)
    assert result["pitch_std_hz"] < 1.0
    assert result["pitch_variance_hz2"] < 1.0
    assert result["barge_in_stop_latency_s"] == pytest.approx(0.07, abs=1e-9)


def test_silence_loudness_has_no_speech(tmp_path: Path) -> None:
    metrics = load("metrics.py")
    wav_path, timing_path = write_case(
        tmp_path,
        "silence",
        np.zeros(RATE, dtype=np.float64),
        {"request_start_s": 0.0, "wav_origin_s": 0.0, "text": "one two"},
    )
    result = metrics.measure(wav_path, timing_path)

    assert math.isinf(result["integrated_lufs"]) and result["integrated_lufs"] < 0
    assert result["true_peak"] == 0.0
    assert math.isinf(result["true_peak_dbtp"]) and result["true_peak_dbtp"] < 0
    assert result["clipping_count"] == 0
    assert result["leading_onset_clipped"] is False
    assert result["ttfa_s"] is None
    assert result["inter_chunk_gaps_s"] == []
    assert result["speech_rate_wps"] is None
    assert result["pitch_median_hz"] is None
    assert result["barge_in_stop_latency_s"] is None


def test_known_gap_and_wav_onset(tmp_path: Path) -> None:
    metrics = load("metrics.py")
    samples = np.concatenate(
        [
            np.zeros(int(0.10 * RATE), dtype=np.float64),
            sine(0.30, 440.0, 0.20),
            np.zeros(int(0.20 * RATE), dtype=np.float64),
            sine(0.30, 440.0, 0.20),
        ]
    )
    wav_path, timing_path = write_case(
        tmp_path,
        "gap",
        samples,
        {"request_start_s": 0.0, "wav_origin_s": 0.0, "text": "alpha beta"},
    )
    result = metrics.measure(wav_path, timing_path)

    assert result["ttfa_s"] == pytest.approx(0.10, abs=1e-6)
    assert result["inter_chunk_gaps_s"] == pytest.approx([0.20], abs=1e-6)
    assert result["clipping_count"] == 0


def test_known_clip_and_leading_onset(tmp_path: Path) -> None:
    metrics = load("metrics.py")
    samples = sine(0.50, 440.0, 0.50, phase=0.0)
    samples[100] = 1.0
    samples[101] = 1.0
    samples[102] = -1.0
    wav_path, timing_path = write_case(
        tmp_path,
        "clip",
        samples,
        {"request_start_s": 0.05, "first_audio_s": 0.47, "text": "clipped"},
    )
    result = metrics.measure(wav_path, timing_path)

    assert result["clipping_count"] == 3
    assert result["leading_onset_clip_count"] == 3
    assert result["leading_onset_clipped"] is True
    assert result["true_peak"] >= 1.0
    assert result["ttfa_s"] == pytest.approx(0.42, abs=1e-9)


def test_script_set_covers_the_required_cases() -> None:
    directory = VOICE_ROOT / "scripts"
    files = sorted(directory.glob("*.txt")) if directory.is_dir() else []
    assert files, f"missing script set in {directory}"
    texts = {path.name: path.read_text(encoding="utf-8") for path in files}
    joined = "\n".join(texts.values())
    lengths = [len(text.strip()) for text in texts.values()]
    assert min(lengths) < 20
    assert max(lengths) > 400
    assert "?" in joined
    assert "$" in joined
    assert "2026" in joined
    assert "http://" in joined or "https://" in joined
    assert "`" in joined
    assert "Bonjour" in joined
    assert "[[BARGE-IN]]" in joined
    assert any(token in joined.lower() for token in ("error", "failed"))
    for name, text in texts.items():
        assert text.strip(), name
        assert "@" not in text


def test_report_table_lists_each_provider(tmp_path: Path) -> None:
    report = load("report.py")
    rows = [
        {
            "provider": "kokoro",
            "script": "01-short-ack",
            "integrated_lufs": -16.05,
            "ttfa_s": 0.2,
            "true_peak_dbtp": -11.0,
            "clipping_count": 0,
            "inter_chunk_gaps_s": [],
            "speech_rate_wps": 4.0,
            "pitch_std_hz": 0.1,
            "barge_in_stop_latency_s": None,
        },
        {
            "provider": "avspeech",
            "script": "01-short-ack",
            "integrated_lufs": -20.0,
            "ttfa_s": 0.05,
            "true_peak_dbtp": -3.0,
            "clipping_count": 1,
            "inter_chunk_gaps_s": [0.2],
            "speech_rate_wps": 3.5,
            "pitch_std_hz": 12.0,
            "barge_in_stop_latency_s": 0.07,
        },
    ]
    text = report.render_markdown(rows)
    assert "kokoro" in text and "avspeech" in text
    assert "-16.05" in text or "-16.050" in text
    assert "-20.00" in text or "-20.0" in text
    report.write_report(rows, tmp_path)
    metrics_path = tmp_path / "metrics.json"
    report_path = tmp_path / "report.md"
    assert metrics_path.is_file() and report_path.is_file()
    saved = json.loads(metrics_path.read_text(encoding="utf-8"))
    assert saved["rows"][0]["provider"] == "kokoro"
    assert saved["rows"][1]["clipping_count"] == 1
    assert "avspeech" in report_path.read_text(encoding="utf-8")
