"""UX polish for the voice QA report and the messages around a stressed ledger.

The comparison table is what a person reads. A long list of gap times and a
blank barge-in cell do not say what happened. The same is true when a render
stops near the character cap, loses a race, or finds a corrupt ledger.
"""

from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
PROVIDERS = ROOT / "providers"


def load(directory: Path, filename: str):
    path = directory / filename
    if not path.is_file():
        pytest.fail(f"missing {path}")
    spec = importlib.util.spec_from_file_location(f"zeus_ux_{path.stem}", path)
    if spec is None or spec.loader is None:
        pytest.fail(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_report_summarizes_gaps_and_names_an_unmeasured_barge_in(tmp_path: Path) -> None:
    report = load(ROOT, "report.py")
    gaps = [0.11, 0.52, 0.20]
    rows = [{
        "provider": "kokoro",
        "script": "02-long-answer",
        "integrated_lufs": -21.78,
        "ttfa_s": 5.31,
        "true_peak_dbtp": -4.86,
        "clipping_count": 0,
        "inter_chunk_gaps_s": gaps,
        "speech_rate_wps": 3.61,
        "pitch_std_hz": 34.19,
        "barge_in_stop_latency_s": None,
    }]
    text = report.render_markdown(rows)
    assert "3 gaps, longest 0.52s" in text
    assert "0.11" not in text
    assert "not measured" in text
    report.write_report(rows, tmp_path)
    saved = json.loads((tmp_path / "metrics.json").read_text(encoding="utf-8"))
    assert saved["rows"][0]["inter_chunk_gaps_s"] == gaps


def test_near_cap_and_corrupt_ledger_say_what_stopped(tmp_path: Path) -> None:
    meter = load(PROVIDERS, "meter.py")
    ledger = tmp_path / "ledger.json"
    meter.initialize(ledger)
    for _ in range(9):
        meter.reserve(ledger, "elevenlabs", 5_000)
    meter.reserve(ledger, "elevenlabs", 4_990)
    assert meter.status(ledger)["elevenlabs"]["used"] == 49_990
    with pytest.raises(meter.MeterError) as caught:
        meter.reserve(ledger, "elevenlabs", 20)
    assert str(caught.value) == "character cap reached: 20 requested, 9 remaining"
    assert meter.status(ledger)["elevenlabs"]["used"] == 49_990

    corrupt = tmp_path / "corrupt.json"
    corrupt.write_text("{", encoding="utf-8")
    with pytest.raises(meter.MeterError) as broken:
        meter.reserve(corrupt, "elevenlabs", 1)
    assert str(broken.value) == "ledger corrupt: no call made"
    assert corrupt.read_text(encoding="utf-8") == "{"


def test_a_failed_render_says_the_characters_stayed_counted(tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]) -> None:
    meter = load(PROVIDERS, "meter.py")
    eleven = load(PROVIDERS, "render_elevenlabs.py")
    monkeypatch.setenv("VOICE_QA_TEST_KEY", "zq7VOICEQASECRET4f91c0e2")
    ledger = tmp_path / "charged.json"
    meter.initialize(ledger)

    def fail_http(request, timeout=None):
        import urllib.error
        raise urllib.error.HTTPError(request.full_url, 503, "unavailable", hdrs=None, fp=_Body(b"busy"))

    import urllib.request

    def opener_open(self, fullurl, data=None, timeout=None):
        return fail_http(fullurl, timeout)

    monkeypatch.setattr(urllib.request, "urlopen", fail_http)
    monkeypatch.setattr(urllib.request.OpenerDirector, "open", opener_open)
    code = eleven.main([
        "--text", "hello",
        "--voice", "EXAVITQu4vr4xnSDxMaL",
        "--key-env", "VOICE_QA_TEST_KEY",
        "--ledger", str(ledger),
        "--output", str(tmp_path / "stopped.wav"),
    ])
    captured = capsys.readouterr()
    assert code == 1
    assert "characters stayed counted" in captured.err
    assert "zq7V" not in captured.out + captured.err
    assert meter.status(ledger)["elevenlabs"]["used"] == len("hello")
    assert not (tmp_path / "stopped.wav").exists()
    assert not (tmp_path / "stopped.wav.partial").exists()


def test_two_renders_near_the_cap_leave_one_clear_refusal(tmp_path: Path) -> None:
    meter = load(PROVIDERS, "meter.py")
    meter_py = PROVIDERS / "meter.py"
    ledger = tmp_path / "race.json"
    meter.initialize(ledger)
    for _ in range(9):
        meter.reserve(ledger, "elevenlabs", 5_000)
    meter.reserve(ledger, "elevenlabs", 4_499)
    assert meter.status(ledger)["elevenlabs"]["used"] == 49_499
    processes = [
        subprocess.Popen(
            [sys.executable, str(meter_py), "reserve", "--ledger", str(ledger),
             "--provider", "elevenlabs", "--characters", "500"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        )
        for _ in range(2)
    ]
    results = []
    for process in processes:
        stdout, stderr = process.communicate()
        results.append((process.returncode, stdout, stderr))
    codes = sorted(item[0] for item in results)
    assert codes == [0, 1]
    loser = next(item for item in results if item[0] == 1)
    assert "character cap reached: 500 requested, 0 remaining" in loser[2]
    assert meter.status(ledger)["elevenlabs"]["used"] == 49_999


class _Body:
    def __init__(self, payload: bytes):
        self._payload = payload

    def read(self) -> bytes:
        return self._payload

    def close(self) -> None:
        return None
