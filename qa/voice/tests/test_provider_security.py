"""Security-lens tests for the provider meter.

Sentinel's review of 8c74617a was not agreed. These tests cover a key that
contains whitespace or a control character, a redirect, a symlinked ledger,
the per-request cap, and a long upstream error. No provider host is contacted.
"""

from __future__ import annotations

import importlib.util
import json
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
PROVIDERS = ROOT / "providers"
KEY = "zq7VOICEQASECRET4f91c0e2"


def load(filename: str):
    path = PROVIDERS / filename
    if not path.is_file():
        pytest.fail(f"missing {path}")
    spec = importlib.util.spec_from_file_location(f"zeus_voice_sec_{path.stem}", path)
    if spec is None or spec.loader is None:
        pytest.fail(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def key_parts(secret: str) -> list[str]:
    parts = []
    for size in range(4, len(secret) + 1):
        for start in range(0, len(secret) - size + 1):
            piece = secret[start:start + size]
            if any(ord(ch) < 32 or ord(ch) == 127 for ch in piece):
                continue
            parts.append(piece)
    return parts


def assert_no_key(text: str, secret: str) -> None:
    for part in key_parts(secret):
        assert part not in text


def patch_transport(monkeypatch: pytest.MonkeyPatch, fake) -> None:
    import urllib.request

    def opener_open(self, fullurl, data=None, timeout=None):
        return fake(fullurl, timeout)

    monkeypatch.setattr(urllib.request, "urlopen", fake)
    monkeypatch.setattr(urllib.request.OpenerDirector, "open", opener_open)


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


def test_whitespace_around_a_key_is_stripped_and_not_echoed(tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]) -> None:
    meter = load("meter.py")
    eleven = load("render_elevenlabs.py")
    for suffix in ("\n", "\r\n", "\t"):
        monkeypatch.setenv("VOICE_QA_TEST_KEY", f"  {KEY}{suffix}")
        assert meter.read_key("VOICE_QA_TEST_KEY") == KEY
        ledger = tmp_path / f"ledger-{suffix.encode().hex()}.json"
        meter.initialize(ledger)
        seen = []

        def fake(request, timeout=None):
            seen.append(request)
            headers = {name.lower(): value for name, value in request.header_items()}
            assert headers["xi-api-key"] == KEY
            return Response(200, b"RIFFfake")

        patch_transport(monkeypatch, fake)
        code = eleven.main([
            "--text", "hello",
            "--voice", "EXAVITQu4vr4xnSDxMaL",
            "--key-env", "VOICE_QA_TEST_KEY",
            "--ledger", str(ledger),
            "--output", str(tmp_path / f"out-{suffix.encode().hex()}.wav"),
        ])
        captured = capsys.readouterr()
        assert code == 0
        assert seen
        assert_no_key(captured.out + captured.err, KEY)
        assert meter.status(ledger)["elevenlabs"]["used"] == len("hello")


def test_control_characters_are_refused_before_the_ledger_is_charged(tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]) -> None:
    meter = load("meter.py")
    eleven = load("render_elevenlabs.py")
    tabbed = f"{KEY[:4]}\t{KEY[4:]}"
    nulled = f"{KEY[:6]}\x00{KEY[6:]}"
    for dirty in (tabbed, nulled):
        with pytest.raises(meter.MeterError) as caught:
            meter.read_key("VOICE_QA_TEST_KEY", {"VOICE_QA_TEST_KEY": dirty})
        assert str(caught.value) == "API key refused"
        assert caught.value.__cause__ is None
        assert_no_key(str(caught.value), KEY)
        with pytest.raises(meter.MeterError) as posted:
            meter.http_post("https://example.invalid/tts", b"{}", {"xi-api-key": dirty}, [dirty], timeout=1)
        assert str(posted.value) in {"API key refused", "request refused"}
        assert_no_key(str(posted.value), KEY)

    monkeypatch.setenv("VOICE_QA_TEST_KEY", tabbed)
    ledger = tmp_path / "tab.json"
    meter.initialize(ledger)

    def fail_if_called(*_args, **_kwargs):
        raise AssertionError("provider was called")

    patch_transport(monkeypatch, fail_if_called)
    code = eleven.main([
        "--text", "hello",
        "--voice", "EXAVITQu4vr4xnSDxMaL",
        "--key-env", "VOICE_QA_TEST_KEY",
        "--ledger", str(ledger),
        "--output", str(tmp_path / "tab.wav"),
    ])
    captured = capsys.readouterr()
    assert code == 1
    assert "API key refused" in captured.err
    assert_no_key(captured.out + captured.err, KEY)
    assert meter.status(ledger)["elevenlabs"]["used"] == 0
    assert not (tmp_path / "tab.wav").exists()


def test_a_key_longer_than_256_characters_is_refused(tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]) -> None:
    meter = load("meter.py")
    eleven = load("render_elevenlabs.py")
    assert meter.MAX_KEY_CHARACTERS == 256
    accepted = "A" * 256
    assert meter.read_key("VOICE_QA_TEST_KEY", {"VOICE_QA_TEST_KEY": f"  {accepted}\n"}) == accepted
    refused = "K" * 257
    with pytest.raises(meter.MeterError) as caught:
        meter.read_key("VOICE_QA_TEST_KEY", {"VOICE_QA_TEST_KEY": f"  {refused}\n"})
    assert str(caught.value) == "API key refused"
    assert caught.value.__cause__ is None
    assert "K" * 4 not in str(caught.value)

    calls = []

    def fail_if_called(*_args, **_kwargs):
        calls.append(True)
        raise AssertionError("provider was called")

    patch_transport(monkeypatch, fail_if_called)
    with pytest.raises(meter.MeterError) as posted:
        meter.http_post("https://example.invalid/tts", b"{}", {"xi-api-key": refused}, [refused], timeout=1)
    assert str(posted.value) in {"API key refused", "request refused"}
    assert "K" * 4 not in str(posted.value)
    assert calls == []

    monkeypatch.setenv("VOICE_QA_TEST_KEY", refused)
    ledger = tmp_path / "long.json"
    meter.initialize(ledger)
    code = eleven.main([
        "--text", "hello",
        "--voice", "EXAVITQu4vr4xnSDxMaL",
        "--key-env", "VOICE_QA_TEST_KEY",
        "--ledger", str(ledger),
        "--output", str(tmp_path / "long.wav"),
    ])
    captured = capsys.readouterr()
    assert code == 1
    assert "API key refused" in captured.err
    assert "K" * 4 not in captured.out + captured.err
    assert meter.status(ledger)["elevenlabs"]["used"] == 0
    assert not (tmp_path / "long.wav").exists()


def test_header_errors_do_not_echo_the_exception_text() -> None:
    meter = load("meter.py")
    dirty = KEY + "\n"
    with pytest.raises(meter.MeterError) as caught:
        meter.http_post(
            "https://example.invalid/must-not-connect",
            b"{}",
            {"xi-api-key": dirty},
            [dirty],
            timeout=1,
        )
    assert str(caught.value) in {"API key refused", "request refused"}
    assert caught.value.__cause__ is None
    assert_no_key(str(caught.value), KEY)
    assert "Invalid header" not in str(caught.value)


def test_redirects_are_refused_by_a_local_stub() -> None:
    meter = load("meter.py")
    hits = []

    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            hits.append(self.path)
            if self.path == "/tts":
                host, port = self.server.server_address
                self.send_response(302)
                self.send_header("Location", f"http://{host}:{port}/landed")
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            body = b"followed"
            self.send_response(200)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            hits.append(self.path)
            body = b"followed"
            self.send_response(200)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, _format, *_args):
            return

    server = HTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        host, port = server.server_address
        with pytest.raises(meter.MeterError) as caught:
            meter.http_post(
                f"http://{host}:{port}/tts",
                b"{}",
                {"xi-api-key": KEY},
                [KEY],
                timeout=2,
            )
        assert str(caught.value) == "redirect refused"
        assert_no_key(str(caught.value), KEY)
        assert "/landed" not in hits
    finally:
        server.shutdown()
        server.server_close()


def test_a_symlinked_ledger_or_lock_is_refused(tmp_path: Path) -> None:
    meter = load("meter.py")
    real = tmp_path / "real.json"
    meter.initialize(real)
    link = tmp_path / "link.json"
    link.symlink_to(real)
    with pytest.raises(meter.MeterError):
        meter.reserve(link, "elevenlabs", 4)
    assert meter.status(real)["elevenlabs"]["used"] == 0

    locked = tmp_path / "locked.json"
    meter.initialize(locked)
    target = tmp_path / "lock-target"
    target.write_text("untouched", encoding="utf-8")
    lock = locked.with_name(locked.name + ".lock")
    lock.symlink_to(target)
    with pytest.raises(meter.MeterError):
        meter.reserve(locked, "google", 3)
    assert target.read_text(encoding="utf-8") == "untouched"
    assert meter.status(locked)["google"]["used"] == 0


def test_a_request_over_5000_characters_is_refused_before_charging(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    meter = load("meter.py")
    eleven = load("render_elevenlabs.py")
    assert meter.MAX_REQUEST_CHARACTERS == 5_000
    monkeypatch.setenv("VOICE_QA_TEST_KEY", KEY)
    ledger = tmp_path / "ledger.json"
    meter.initialize(ledger)
    calls = []

    def fake(request, timeout=None):
        calls.append(request)
        return Response(200, b"RIFFfake")

    patch_transport(monkeypatch, fake)
    too_big = "a" * 5_001
    code = eleven.main([
        "--text", too_big,
        "--voice", "nPczCjzI2devNBz1zQrb",
        "--key-env", "VOICE_QA_TEST_KEY",
        "--ledger", str(ledger),
        "--output", str(tmp_path / "big.wav"),
    ])
    assert code == 1
    assert calls == []
    assert meter.status(ledger)["elevenlabs"]["used"] == 0
    allowed = "b" * 5_000
    code = eleven.main([
        "--text", allowed,
        "--voice", "nPczCjzI2devNBz1zQrb",
        "--key-env", "VOICE_QA_TEST_KEY",
        "--ledger", str(ledger),
        "--output", str(tmp_path / "ok.wav"),
    ])
    assert code == 0
    assert len(calls) == 1
    assert meter.status(ledger)["elevenlabs"]["used"] == 5_000


def test_long_upstream_body_does_not_keep_the_key(monkeypatch: pytest.MonkeyPatch) -> None:
    meter = load("meter.py")
    import urllib.error

    assert meter.MAX_ERROR_BODY == 200
    body = (b"Y" * 80) + KEY.encode() + (b"Z" * 400)

    def fake(request, timeout=None):
        raise urllib.error.HTTPError(getattr(request, "full_url", request), 401, "unauthorized", hdrs=None, fp=_Body(body))

    patch_transport(monkeypatch, fake)
    with pytest.raises(meter.MeterError) as caught:
        meter.http_post("https://example.invalid/tts", b"{}", {"xi-api-key": KEY}, [KEY], timeout=1)
    message = str(caught.value)
    assert message.startswith("HTTP 401")
    assert_no_key(message, KEY)
    detail = message.split(": ", 1)[1] if ": " in message else ""
    assert len(detail) <= 200
    assert "Y" * 201 not in message
    assert "Z" * 201 not in message


def test_ledger_is_documented_as_a_local_guard() -> None:
    readme = (ROOT / "README.md").read_text(encoding="utf-8").lower()
    assert "local guard" in readme
    assert "not tamper-proof" in readme
    log = (ROOT / "SECURITY-LENS.md").read_text(encoding="utf-8").lower()
    assert "security-lens" in log
    for item in ("z-1", "z-2", "z-3", "z-4", "z-5", "z-6"):
        assert item in log


class _Body:
    def __init__(self, payload: bytes):
        self._payload = payload

    def read(self) -> bytes:
        return self._payload

    def close(self) -> None:
        return None
