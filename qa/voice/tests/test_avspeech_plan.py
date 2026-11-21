"""Rate, pitch, and the empty-text check for the Mac AVSpeech script.

AVFoundation is not on Linux, so the synthesizer itself is not run here.
The numbers and the empty-text exit live in avspeech_plan.py, which this file runs.
"""

from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
PLAN = ROOT / "mac" / "avspeech_plan.py"
SWIFT = ROOT / "mac" / "render_avspeech.swift"


def load():
    if not PLAN.is_file():
        pytest.fail(f"missing {PLAN}")
    spec = importlib.util.spec_from_file_location("avspeech_plan", PLAN)
    if spec is None or spec.loader is None:
        pytest.fail(f"cannot load {PLAN}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_rate_pitch_and_empty_text_come_from_the_plan(tmp_path: Path) -> None:
    plan = load()
    assert plan.RATE_SCALE == 0.92
    assert plan.PITCH == 0.82
    assert plan.exit_code(3, "") == 2
    assert plan.exit_code(3, " \n\t") == 2
    assert plan.exit_code(2, "Hello.") == 2
    assert plan.exit_code(3, "Hello.") == 0

    empty = tmp_path / "empty.txt"
    empty.write_text("  \n", encoding="utf-8")
    refused = subprocess.run(
        [sys.executable, str(PLAN), str(tmp_path / "out.wav"), str(empty)],
        check=False, capture_output=True, text=True,
    )
    assert refused.returncode == 2
    assert "empty text" in refused.stderr

    spoken = tmp_path / "line.txt"
    spoken.write_text("Hello.\n", encoding="utf-8")
    accepted = subprocess.run(
        [sys.executable, str(PLAN), str(tmp_path / "out.wav"), str(spoken)],
        check=False, capture_output=True, text=True,
    )
    assert accepted.returncode == 0
    payload = json.loads(accepted.stdout)
    assert payload["rate_scale"] == 0.92
    assert payload["pitch"] == 0.82
    assert payload["exit"] == 0

    source = SWIFT.read_text(encoding="utf-8")
    assert "avspeech_plan.py" in source
    assert "rate_scale" in source
    assert "AVSpeechUtteranceDefaultSpeechRate * 0.92" not in source
    assert "pitchMultiplier = 0.82" not in source
    assert "exit(0)" not in source
