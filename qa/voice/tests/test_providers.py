"""Red tests for the metered ElevenLabs and Google renderers.

No test has a provider key and none may open a network connection.
Voice ids are the ones published in the Default voices table and the
Google Cloud TTS supported-voices table. They are not guesses.
"""

from __future__ import annotations

import importlib.util
import json
import re
import socket
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
PROVIDERS = ROOT / "providers"
SECRET = "zq7VOICEQASECRET4f91c0e2"
ELEVENLABS_IDS = {
    "EXAVITQu4vr4xnSDxMaL": "Sarah",
    "JBFqnCBsd6RMkjVDRZzb": "George",
    "nPczCjzI2devNBz1zQrb": "Brian",
}
GOOGLE_IDS = {
    "en-US-Neural2-D": "neural2",
    "en-US-Wavenet-D": "wavenet",
    "en-US-Chirp3-HD-Charon": "chirp-hd",
}
KEY_PATTERNS = (
    re.compile(r"xi-api-key\s*[:=]\s*\S+", re.IGNORECASE),
    re.compile(r"x-goog-api-key\s*[:=]\s*\S+", re.IGNORECASE),
    re.compile(r"authorization\s*:\s*bearer\s+\S+", re.IGNORECASE),
    re.compile(r"AIza[0-9A-Za-z\-_]{20,}"),
    re.compile(r"sk_[A-Za-z0-9]{20,}"),
)


def load(filename: str):
    path = PROVIDERS / filename
    if not path.is_file():
        pytest.fail(f"missing {path}")
    spec = importlib.util.spec_from_file_location(f"zeus_voice_{path.stem}", path)
    if spec is None or spec.loader is None:
        pytest.fail(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def forbid_network(monkeypatch: pytest.MonkeyPatch) -> None:
    def blocked(*_args, **_kwargs):
        raise AssertionError("network is forbidden")

    monkeypatch.setattr(socket, "create_connection", blocked)


def needles(secret: str) -> list[str]:
    return [secret, secret[:8], secret[-8:]]


def assert_clean(text: str) -> None:
    for needle in needles(SECRET):
        assert needle not in text
    for pattern in KEY_PATTERNS:
        assert pattern.search(text) is None


def scan_tree(path: Path) -> None:
    for file in path.rglob("*"):
        if not file.is_file():
            continue
        data = file.read_bytes()
        for needle in needles(SECRET):
            assert needle.encode() not in data
        if file.suffix.lower() in {".json", ".md", ".txt", ".py", ".log"}:
            assert_clean(data.decode("utf-8", "replace"))


class Response:
    def __init__(self, status: int, body: bytes):
        self.status = status
        self._body = body

    def read(self) -> bytes:
        return self._body

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False


def test_cap_boundary_allows_49999_and_refuses_50000(tmp_path: Path) -> None:
    meter = load("meter.py")
    assert meter.MAX_CHARACTERS == 49_999
    ledger = tmp_path / "ledger.json"
    meter.initialize(ledger)
    assert meter.reserve(ledger, "elevenlabs", 49_999) == 49_999
    with pytest.raises(meter.MeterError):
        meter.reserve(ledger, "elevenlabs", 1)
    stored = json.loads(ledger.read_text(encoding="utf-8"))
    assert stored["providers"]["elevenlabs"] == 49_999
    assert meter.status(ledger)["elevenlabs"]["remaining"] == 0

    other = tmp_path / "other.json"
    meter.initialize(other)
    with pytest.raises(meter.MeterError):
        meter.reserve(other, "elevenlabs", 50_000)
    assert json.loads(other.read_text(encoding="utf-8"))["providers"]["elevenlabs"] == 0
    assert meter.reserve(other, "google", 49_999) == 49_999


def test_ledger_persists_across_processes(tmp_path: Path) -> None:
    meter_py = PROVIDERS / "meter.py"
    if not meter_py.is_file():
        pytest.fail(f"missing {meter_py}")
    ledger = tmp_path / "ledger.json"
    init = subprocess.run(
        [sys.executable, str(meter_py), "init", "--ledger", str(ledger)],
        check=False, capture_output=True, text=True,
    )
    assert init.returncode == 0, init.stderr
    for count in ("10", "15"):
        result = subprocess.run(
            [sys.executable, str(meter_py), "reserve", "--ledger", str(ledger),
             "--provider", "elevenlabs", "--characters", count],
            check=False, capture_output=True, text=True,
        )
        assert result.returncode == 0, result.stderr
        assert_clean(result.stdout + result.stderr)
    status = subprocess.run(
        [sys.executable, str(meter_py), "status", "--ledger", str(ledger)],
        check=False, capture_output=True, text=True,
    )
    assert status.returncode == 0
    assert "elevenlabs: used 25 remaining 49974" in status.stdout
    assert "google: used 0 remaining 49999" in status.stdout


def test_concurrent_reserves_keep_one_ledger(tmp_path: Path) -> None:
    meter = load("meter.py")
    meter_py = PROVIDERS / "meter.py"
    ledger = tmp_path / "ledger.json"
    meter.initialize(ledger)
    processes = [
        subprocess.Popen(
            [sys.executable, str(meter_py), "reserve", "--ledger", str(ledger),
             "--provider", "google", "--characters", "1000"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        )
        for _ in range(8)
    ]
    codes = []
    for process in processes:
        stdout, stderr = process.communicate()
        assert_clean(stdout + stderr)
        codes.append(process.returncode)
    assert codes == [0] * 8
    assert meter.status(ledger)["google"]["used"] == 8_000

    capped = tmp_path / "capped.json"
    meter.initialize(capped)
    meter.reserve(capped, "elevenlabs", 49_000)
    racers = [
        subprocess.Popen(
            [sys.executable, str(meter_py), "reserve", "--ledger", str(capped),
             "--provider", "elevenlabs", "--characters", "999"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        )
        for _ in range(2)
    ]
    race_codes = []
    for process in racers:
        stdout, stderr = process.communicate()
        assert_clean(stdout + stderr)
        race_codes.append(process.returncode)
    assert sorted(race_codes) == [0, 1]
    assert meter.status(capped)["elevenlabs"]["used"] == 49_999


def test_missing_corrupt_and_unreadable_ledgers_fail_closed(tmp_path: Path) -> None:
    meter = load("meter.py")
    missing = tmp_path / "missing.json"
    with pytest.raises(meter.MeterError):
        meter.reserve(missing, "elevenlabs", 1)
    assert not missing.exists()

    corrupt = tmp_path / "corrupt.json"
    corrupt.write_text("{", encoding="utf-8")
    with pytest.raises(meter.MeterError):
        meter.reserve(corrupt, "elevenlabs", 1)
    assert corrupt.read_text(encoding="utf-8") == "{"

    negative = tmp_path / "negative.json"
    negative.write_text(
        json.dumps({"version": 1, "providers": {"elevenlabs": -1, "google": 0}}),
        encoding="utf-8",
    )
    with pytest.raises(meter.MeterError):
        meter.reserve(negative, "google", 1)
    assert json.loads(negative.read_text(encoding="utf-8"))["providers"]["elevenlabs"] == -1

    hidden = tmp_path / "hidden.json"
    meter.initialize(hidden)
    original = hidden.read_text(encoding="utf-8")
    hidden.chmod(0)
    try:
        with pytest.raises(meter.MeterError):
            meter.reserve(hidden, "elevenlabs", 1)
    finally:
        hidden.chmod(0o600)
    assert hidden.read_text(encoding="utf-8") == original


def test_redaction_removes_the_key_and_its_edges() -> None:
    meter = load("meter.py")
    leaked = f"HTTP 401 body {SECRET} prefix {SECRET[:8]} suffix {SECRET[-8:]}"
    cleaned = meter.redact(leaked, [SECRET])
    assert_clean(cleaned)
    assert "HTTP 401" in cleaned
    try:
        raise meter.MeterError(cleaned) from None
    except meter.MeterError as error:
        assert SECRET not in str(error)
        assert error.__cause__ is None


def test_key_is_only_read_from_the_named_env(monkeypatch: pytest.MonkeyPatch) -> None:
    meter = load("meter.py")
    monkeypatch.setenv("VOICE_QA_TEST_KEY", SECRET)
    assert meter.read_key("VOICE_QA_TEST_KEY") == SECRET
    with pytest.raises(meter.MeterError) as missing:
        meter.read_key("VOICE_QA_ABSENT")
    assert_clean(str(missing.value))
    with pytest.raises(meter.MeterError) as named:
        meter.read_key(SECRET)
    assert_clean(str(named.value))


def test_allow_list_is_the_documented_stock_set(tmp_path: Path) -> None:
    meter = load("meter.py")
    voices_path = PROVIDERS / "VOICES.md"
    if not voices_path.is_file():
        pytest.fail(f"missing {voices_path}")
    text = voices_path.read_text(encoding="utf-8")
    assert "https://elevenlabs.io/docs/help-center/product/voices/my-voices/what-are-default-voices" in text
    assert "https://cloud.google.com/text-to-speech/docs/list-voices-and-types" in text
    voices = meter.load_voices(voices_path)
    assert set(voices["elevenlabs"]) == set(ELEVENLABS_IDS)
    assert set(voices["google"]) == set(GOOGLE_IDS)
    for voice_id, name in ELEVENLABS_IDS.items():
        entry = voices["elevenlabs"][voice_id]
        assert entry["name"] == name
        assert entry["kind"] == "premade-default"
        assert entry["why"].strip()
    for voice_id, kind in GOOGLE_IDS.items():
        entry = voices["google"][voice_id]
        assert entry["kind"] == kind
        assert entry["why"].strip()
    for provider, entries in voices.items():
        for voice_id, entry in entries.items():
            labelled = f"{voice_id} {entry['name']} {entry['kind']}".lower()
            for banned in ("clone", "cloned", "celebrity", "character"):
                assert banned not in labelled
            meter.require_voice(provider, voice_id, voices)

    with pytest.raises(meter.MeterError):
        meter.require_voice("elevenlabs", "21m00Tcm4TlvDq8ikWAM", voices)
    with pytest.raises(meter.MeterError):
        meter.require_voice("elevenlabs", "gOupLcAkjEnguROwi4oS", voices)
    with pytest.raises(meter.MeterError):
        meter.require_voice("google", "en-US-Studio-O", voices)
    with pytest.raises(meter.MeterError):
        meter.require_voice("google", "en-US-Standard-A", voices)
    with pytest.raises(meter.MeterError):
        meter.require_voice("elevenlabs", "cloned-celebrity-character", voices)

    hostile = voices_path.read_text(encoding="utf-8").replace("premade-default", "cloned", 1)
    hostile_path = tmp_path / "VOICES-hostile.md"
    hostile_path.write_text(hostile, encoding="utf-8")
    with pytest.raises(meter.MeterError):
        meter.load_voices(hostile_path)


def test_default_ledger_path_is_outside_the_repo(tmp_path: Path) -> None:
    meter = load("meter.py")
    chosen = meter.resolve_ledger_path("/tmp/explicit-ledger.json", {}, tmp_path)
    assert chosen == Path("/tmp/explicit-ledger.json")
    from_env = meter.resolve_ledger_path(None, {"ZEUS_VOICE_QA_LEDGER": "/tmp/env-ledger.json"}, tmp_path)
    assert from_env == Path("/tmp/env-ledger.json")
    default = meter.resolve_ledger_path(None, {}, tmp_path)
    assert default == tmp_path / ".cache" / "zeus-voice-qa" / "provider-ledger.json"
    assert ROOT not in default.parents


def test_mocked_elevenlabs_success_and_error(tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]) -> None:
    forbid_network(monkeypatch)
    meter = load("meter.py")
    eleven = load("render_elevenlabs.py")
    import urllib.error
    import urllib.request

    ledger = tmp_path / "ledger.json"
    meter.initialize(ledger)
    monkeypatch.setenv("VOICE_QA_TEST_KEY", SECRET)
    seen = []

    def fake_urlopen(request, timeout=None):
        seen.append(request)
        assert timeout == 30
        assert SECRET not in request.full_url
        headers = {key.lower(): value for key, value in request.header_items()}
        assert headers["xi-api-key"] == SECRET
        body = json.loads(request.data.decode("utf-8"))
        assert body["text"] == "hello there"
        assert body["model_id"] == "eleven_flash_v2_5"
        assert meter.status(ledger)["elevenlabs"]["used"] == len("hello there")
        return Response(200, b"RIFFfake")

    monkeypatch.setattr(urllib.request, "urlopen", fake_urlopen)
    output = tmp_path / "out" / "line.wav"
    code = eleven.main([
        "--text", "hello there",
        "--voice", "EXAVITQu4vr4xnSDxMaL",
        "--key-env", "VOICE_QA_TEST_KEY",
        "--ledger", str(ledger),
        "--output", str(output),
    ])
    captured = capsys.readouterr()
    assert code == 0
    assert output.read_bytes() == b"RIFFfake"
    assert "elevenlabs: used 11 remaining 49988" in captured.out
    assert_clean(captured.out + captured.err)
    assert len(seen) == 1

    def fake_error(request, timeout=None):
        raise urllib.error.HTTPError(
            request.full_url, 401, "unauthorized", hdrs=None,
            fp=_Body(f'{{"detail":"bad {SECRET}"}}'.encode()),
        )

    monkeypatch.setattr(urllib.request, "urlopen", fake_error)
    failed = tmp_path / "out" / "failed.wav"
    code = eleven.main([
        "--text", "nope",
        "--voice", "JBFqnCBsd6RMkjVDRZzb",
        "--key-env", "VOICE_QA_TEST_KEY",
        "--ledger", str(ledger),
        "--output", str(failed),
    ])
    captured = capsys.readouterr()
    assert code == 1
    assert not failed.exists()
    assert_clean(captured.out + captured.err)
    assert "HTTP 401" in captured.err
    assert meter.status(ledger)["elevenlabs"]["used"] == len("hello there") + len("nope")
    scan_tree(tmp_path)
    scan_tree(ROOT / "fixtures")


def test_mocked_google_success_and_voice_refusal(tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]) -> None:
    forbid_network(monkeypatch)
    meter = load("meter.py")
    google = load("render_google.py")
    import urllib.request

    ledger = tmp_path / "ledger.json"
    meter.initialize(ledger)
    monkeypatch.setenv("VOICE_QA_TEST_KEY", SECRET)
    calls = []

    def fake_urlopen(request, timeout=None):
        calls.append(request)
        assert SECRET not in request.full_url
        assert request.full_url == "https://texttospeech.googleapis.com/v1/text:synthesize"
        headers = {key.lower(): value for key, value in request.header_items()}
        assert headers["x-goog-api-key"] == SECRET
        body = json.loads(request.data.decode("utf-8"))
        assert body["voice"]["name"] == "en-US-Neural2-D"
        assert body["voice"]["languageCode"] == "en-US"
        assert body["input"]["text"] == "ready"
        import base64
        payload = json.dumps({"audioContent": base64.b64encode(b"GOOG").decode("ascii")}).encode()
        return Response(200, payload)

    monkeypatch.setattr(urllib.request, "urlopen", fake_urlopen)
    output = tmp_path / "google.wav"
    code = google.main([
        "--text", "ready",
        "--voice", "en-US-Neural2-D",
        "--key-env", "VOICE_QA_TEST_KEY",
        "--ledger", str(ledger),
        "--output", str(output),
    ])
    captured = capsys.readouterr()
    assert code == 0
    assert output.read_bytes() == b"GOOG"
    assert_clean(captured.out + captured.err)
    assert meter.status(ledger)["google"]["used"] == 5

    monkeypatch.setattr(urllib.request, "urlopen", lambda *_args, **_kwargs: (_ for _ in ()).throw(AssertionError("network")))
    refused = google.main([
        "--text", "ready",
        "--voice", "en-US-Chirp3-HD-Charon-clone",
        "--key-env", "VOICE_QA_TEST_KEY",
        "--ledger", str(ledger),
        "--output", str(tmp_path / "refused.wav"),
    ])
    captured = capsys.readouterr()
    assert refused == 1
    assert meter.status(ledger)["google"]["used"] == 5
    assert_clean(captured.out + captured.err)
    assert not (tmp_path / "refused.wav").exists()


def test_corrupt_ledger_does_not_call_the_provider(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    forbid_network(monkeypatch)
    meter = load("meter.py")
    eleven = load("render_elevenlabs.py")
    import urllib.request

    ledger = tmp_path / "ledger.json"
    ledger.write_text("{", encoding="utf-8")
    monkeypatch.setenv("VOICE_QA_TEST_KEY", SECRET)

    def fail_if_called(*_args, **_kwargs):
        raise AssertionError("provider was called")

    monkeypatch.setattr(urllib.request, "urlopen", fail_if_called)
    code = eleven.main([
        "--text", "hello",
        "--voice", "nPczCjzI2devNBz1zQrb",
        "--key-env", "VOICE_QA_TEST_KEY",
        "--ledger", str(ledger),
        "--output", str(tmp_path / "nope.wav"),
    ])
    assert code == 1
    assert ledger.read_text(encoding="utf-8") == "{"
    assert not (tmp_path / "nope.wav").exists()


class _Body:
    def __init__(self, payload: bytes):
        self._payload = payload

    def read(self) -> bytes:
        return self._payload

    def close(self) -> None:
        return None
