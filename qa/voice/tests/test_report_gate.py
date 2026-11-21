"""The offline comparison must fail closed when a clip is not listenable.

Silence, clipping, a wrong transcript, and a late time to first audio used to
exit 0 with no FAIL line. A refused voice exited 1 with no FAIL line. The
Kokoro long answer at 5.31 s was printed as an ordinary row.
"""

from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import wave
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]


def load():
    path = ROOT / "report.py"
    spec = importlib.util.spec_from_file_location("zeus_report_gate", path)
    if spec is None or spec.loader is None:
        pytest.fail(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def healthy(**overrides) -> dict:
    row = {
        "provider": "kokoro",
        "script": "01-short-ack",
        "ttfa_s": 0.23,
        "integrated_lufs": -21.0,
        "rms": 0.05,
        "true_peak_dbtp": -6.23,
        "clipping_count": 0,
        "text": "Understood.",
        "transcript": "Understood.",
        "inter_chunk_gaps_s": [],
        "barge_in_stop_latency_s": None,
    }
    row.update(overrides)
    return row


def test_silence_prints_fail_and_exits_nonzero(tmp_path: Path) -> None:
    report = load()
    quiet, lines = report.evaluate([healthy(script="01-silent", integrated_lufs=-80.0)])
    assert quiet == 1
    assert "FAIL 01-silent integrated_lufs -80.00 -70.00" in lines
    hushed, rms_lines = report.evaluate([healthy(script="01-hushed", rms=0.0)])
    assert hushed == 1
    assert "FAIL 01-hushed rms 0.00 0.01" in rms_lines

    clip = tmp_path / "silence"
    clip.mkdir()
    wav_path = clip / "silence.wav"
    with wave.open(str(wav_path), "w") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(24000)
        handle.writeframes(b"\x00\x00" * 24000)
    (clip / "silence.timing.json").write_text(json.dumps({
        "provider": "kokoro",
        "script": "silence",
        "text": "Hello.",
        "request_start_s": 0.0,
        "first_audio_s": 0.2,
    }), encoding="utf-8")
    result = subprocess.run(
        [sys.executable, str(ROOT / "report.py"), str(clip), "--output", str(tmp_path / "out")],
        check=False, capture_output=True, text=True,
    )
    assert result.returncode != 0
    assert result.stdout.splitlines()[0].startswith("FAIL silence ")


def test_clipping_prints_fail() -> None:
    report = load()
    peak, peak_lines = report.evaluate([healthy(script="01-hot", true_peak_dbtp=-0.4)])
    assert peak == 1
    assert "FAIL 01-hot true_peak_dbtp -0.40 -1.00" in peak_lines
    full, full_lines = report.evaluate([healthy(script="01-full", clipping_count=3)])
    assert full == 1
    assert "FAIL 01-full clipping_count 3 0" in full_lines


def test_wrong_transcript_prints_fail() -> None:
    report = load()
    code, lines = report.evaluate([healthy(
        script="04-question",
        text="what time is it",
        transcript="completely different words",
    )])
    assert code == 1
    assert lines == ["FAIL 04-question word_error_rate 1.00 0.10"]


def test_late_ttfa_prints_fail() -> None:
    report = load()
    code, lines = report.evaluate([healthy(script="04-question", ttfa_s=9.5)])
    assert code == 1
    assert lines == ["FAIL 04-question ttfa_s 9.50 2.50"]


def test_refused_voice_prints_fail() -> None:
    report = load()
    code, lines = report.evaluate([{
        "script": "ready",
        "voice_refused": "en-US-Standard-A",
    }])
    assert code == 1
    assert lines == ["FAIL ready voice refused: en-US-Standard-A"]
    text = report.render_markdown([{"script": "ready", "voice_refused": "en-US-Standard-A"}])
    assert "| FAIL |" in text


def test_long_answer_under_its_budget_is_a_warning() -> None:
    report = load()
    code, lines = report.evaluate([healthy(script="02-long-answer", ttfa_s=5.31)])
    assert code == 0
    assert lines == ["WARN 02-long-answer ttfa_s 5.31 8.00"]
    text = report.render_markdown([healthy(script="02-long-answer", ttfa_s=5.31)])
    assert "| WARN |" in text
    assert "| PASS |" not in text


def test_a_clip_inside_every_threshold_passes() -> None:
    report = load()
    row = healthy()
    code, lines = report.evaluate([row])
    assert code == 0
    assert lines == []
    text = report.render_markdown([row])
    assert "OFFLINE ENGINE COMPARISON" in text
    assert "Kokoro" in text
    assert "ElevenLabs non-streaming" in text
    assert "Google Cloud TTS" in text
    assert "ElevenLabs > OpenAI > Gemini" in text
    assert "Murmure" in text and "Scribe" in text
    assert "| PASS |" in text
    readme = (ROOT / "README.md").read_text(encoding="utf-8")
    assert "OFFLINE ENGINE COMPARISON" in readme
    assert "ElevenLabs > OpenAI > Gemini" in readme
    assert "does not drive Murmure or Scribe" in readme
