"""Tests that kill the surviving mutants from Devin's gate on 9e993ca6.

Charged and uncharged refusals are separate. A measured barge-in stays a
number. One gap stays singular. A non-list or a non-numeric gap must not be
treated as a list of seconds, and must not raise.
"""

from __future__ import annotations

import importlib.util
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
PROVIDERS = ROOT / "providers"
KEY = "zq7VOICEQASECRET4f91c0e2"


def load(directory: Path, filename: str):
    path = directory / filename
    if not path.is_file():
        pytest.fail(f"missing {path}")
    spec = importlib.util.spec_from_file_location(f"zeus_mut_{directory.name}_{path.stem}", path)
    if spec is None or spec.loader is None:
        pytest.fail(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def render(module, tmp_path: Path, ledger: Path, voice: str, text: str = "hello"):
    return module.main([
        "--text", text,
        "--voice", voice,
        "--key-env", "VOICE_QA_TEST_KEY",
        "--ledger", str(ledger),
        "--output", str(tmp_path / f"{voice}.wav"),
    ])


def test_measured_barge_in_stays_a_number_and_gap_count_agrees_in_number() -> None:
    report = load(ROOT, "report.py")
    one = report.render_markdown([{
        "provider": "kokoro",
        "script": "04-question",
        "inter_chunk_gaps_s": [0.2],
        "barge_in_stop_latency_s": 0.42,
    }])
    assert "1 gap, longest 0.20s" in one
    assert "1 gaps" not in one
    assert "0.42" in one
    assert "not measured" not in one

    two = report.render_markdown([{
        "provider": "kokoro",
        "script": "02-long-answer",
        "inter_chunk_gaps_s": [0.11, 0.52],
        "barge_in_stop_latency_s": None,
    }])
    assert "2 gaps, longest 0.52s" in two
    assert "not measured" in two


def test_non_list_and_non_numeric_gaps_do_not_raise() -> None:
    report = load(ROOT, "report.py")
    scalar = report.render_markdown([{
        "provider": "kokoro",
        "script": "01-short-ack",
        "inter_chunk_gaps_s": 0.52,
        "barge_in_stop_latency_s": 0.07,
    }])
    assert "0.52" in scalar
    assert "longest" not in scalar

    words = report.render_markdown([{
        "provider": "kokoro",
        "script": "05-error",
        "inter_chunk_gaps_s": ["later", "soon"],
        "barge_in_stop_latency_s": None,
    }])
    assert "2 gaps" in words
    assert "longest" not in words


def test_status_of_a_corrupt_ledger_does_not_say_a_call_was_skipped(tmp_path: Path) -> None:
    meter = load(PROVIDERS, "meter.py")
    corrupt = tmp_path / "corrupt.json"
    corrupt.write_text("{", encoding="utf-8")
    with pytest.raises(meter.MeterError) as status_error:
        meter.status(corrupt)
    assert "ledger corrupt" in str(status_error.value)
    assert "no call made" not in str(status_error.value)
    with pytest.raises(meter.MeterError) as shown:
        meter.format_status(corrupt)
    assert "no call made" not in str(shown.value)
    with pytest.raises(meter.MeterError) as reserved:
        meter.reserve(corrupt, "elevenlabs", 1)
    assert str(reserved.value) == "ledger corrupt: no call made"
    assert corrupt.read_text(encoding="utf-8") == "{"


def test_elevenlabs_uncharged_refusal_does_not_say_the_count_stayed(tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]) -> None:
    meter = load(PROVIDERS, "meter.py")
    eleven = load(PROVIDERS, "render_elevenlabs.py")
    monkeypatch.setenv("VOICE_QA_TEST_KEY", KEY)
    ledger = tmp_path / "ledger.json"
    meter.initialize(ledger)
    code = render(eleven, tmp_path, ledger, "21m00Tcm4TlvDq8ikWAM")
    captured = capsys.readouterr()
    assert code == 1
    assert "characters stayed counted" not in captured.out + captured.err
    assert meter.status(ledger)["elevenlabs"]["used"] == 0


def test_google_charged_failure_and_uncharged_refusal(tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]) -> None:
    meter = load(PROVIDERS, "meter.py")
    google = load(PROVIDERS, "render_google.py")
    monkeypatch.setenv("VOICE_QA_TEST_KEY", KEY)
    refused = tmp_path / "refused.json"
    meter.initialize(refused)
    code = render(google, tmp_path, refused, "en-US-Standard-A")
    captured = capsys.readouterr()
    assert code == 1
    assert "characters stayed counted" not in captured.out + captured.err
    assert meter.status(refused)["google"]["used"] == 0

    charged = tmp_path / "charged.json"
    meter.initialize(charged)

    def fail_http(request, timeout=None):
        import urllib.error
        raise urllib.error.HTTPError(getattr(request, "full_url", request), 503, "unavailable", hdrs=None, fp=_Body(b"busy"))

    import urllib.request

    def opener_open(self, fullurl, data=None, timeout=None):
        return fail_http(fullurl, timeout)

    monkeypatch.setattr(urllib.request, "urlopen", fail_http)
    monkeypatch.setattr(urllib.request.OpenerDirector, "open", opener_open)
    code = render(google, tmp_path, charged, "en-US-Neural2-D")
    captured = capsys.readouterr()
    assert code == 1
    assert "characters stayed counted" in captured.err
    assert meter.status(charged)["google"]["used"] == len("hello")
    assert not (tmp_path / "en-US-Neural2-D.wav").exists()


def test_oserror_after_a_charge_still_says_the_count_stayed(tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]) -> None:
    meter = load(PROVIDERS, "meter.py")
    monkeypatch.setenv("VOICE_QA_TEST_KEY", KEY)
    for filename, voice, provider in (
        ("render_elevenlabs.py", "EXAVITQu4vr4xnSDxMaL", "elevenlabs"),
        ("render_google.py", "en-US-Wavenet-D", "google"),
    ):
        module = load(PROVIDERS, filename)
        ledger = tmp_path / f"{provider}.json"
        meter.initialize(ledger)

        def fail_fetch(*_args, **_kwargs):
            raise OSError("disk full")

        monkeypatch.setattr(module, "_fetch", fail_fetch)
        code = render(module, tmp_path, ledger, voice)
        captured = capsys.readouterr()
        assert code == 1
        assert "request refused" in captured.err
        assert "characters stayed counted" in captured.err
        assert KEY[:4] not in captured.out + captured.err
        assert meter.status(ledger)[provider]["used"] == len("hello")


class _Body:
    def __init__(self, payload: bytes):
        self._payload = payload

    def read(self) -> bytes:
        return self._payload

    def close(self) -> None:
        return None
