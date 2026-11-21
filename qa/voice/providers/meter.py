"""Character ledger for provider renders.

The cap is 49,999 characters per provider. A call that would make the total
50,000 or more is refused, and one request may not exceed 5,000 characters.
The count is recorded before the call. A missing, corrupt, unreadable, or
symlinked ledger refuses the call.

This file is a local guard for a test run. It is not tamper-proof.

The ledger path comes from a flag, otherwise ZEUS_VOICE_QA_LEDGER, otherwise
~/.cache/zeus-voice-qa/provider-ledger.json. That default is outside the repo.
"""

from __future__ import annotations

import argparse
import errno
import fcntl
import json
import os
import stat
import sys
import tempfile
import unicodedata
import urllib.error
import urllib.request
from pathlib import Path

MAX_CHARACTERS = 49_999
MAX_REQUEST_CHARACTERS = 5_000
MAX_ERROR_BODY = 200
MAX_KEY_CHARACTERS = 256
LEDGER_ENV = "ZEUS_VOICE_QA_LEDGER"
PROVIDERS = ("elevenlabs", "google")
BANNED_LABELS = ("clone", "cloned", "celebrity", "character")


class MeterError(Exception):
    """A refused call or a ledger that cannot be trusted."""


def resolve_ledger_path(flag: str | None, environ: dict | None = None, home: Path | None = None) -> Path:
    if flag:
        return Path(flag)
    source = os.environ if environ is None else environ
    configured = source.get(LEDGER_ENV)
    if configured:
        return Path(configured)
    root = Path.home() if home is None else Path(home)
    return root / ".cache" / "zeus-voice-qa" / "provider-ledger.json"


def initialize(path: Path) -> None:
    path = Path(path)
    if path.is_symlink():
        raise MeterError("ledger refused")
    if path.exists():
        raise MeterError("ledger already exists")
    payload = {"providers": {name: 0 for name in PROVIDERS}, "version": 1}
    text = json.dumps(payload, indent=2, sort_keys=True) + "\n"
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600)
    except FileExistsError:
        raise MeterError("ledger already exists") from None
    except OSError as error:
        if error.errno == errno.ELOOP:
            raise MeterError("ledger refused") from None
        raise MeterError("ledger failed") from None
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(text)
            handle.flush()
            os.fsync(handle.fileno())
    except Exception:
        try:
            os.unlink(path)
        except OSError:
            pass
        raise MeterError("ledger failed") from None


def reserve(path: Path, provider: str, characters: int) -> int:
    if type(characters) is not int or characters < 1:
        raise MeterError("character count refused")
    if characters > MAX_REQUEST_CHARACTERS:
        raise MeterError("request too large")
    if provider not in PROVIDERS:
        raise MeterError("provider refused")
    path = Path(path)
    with _lock(path):
        data = _read(path)
        updated = data["providers"][provider] + characters
        if updated > MAX_CHARACTERS:
            remaining = MAX_CHARACTERS - data["providers"][provider]
            raise MeterError(f"character cap reached: {characters} requested, {remaining} remaining")
        data["providers"][provider] = updated
        _atomic_write(path, json.dumps(data, indent=2, sort_keys=True) + "\n")
        return updated


def status(path: Path) -> dict:
    data = _read(Path(path))
    return {
        provider: {
            "used": data["providers"][provider],
            "remaining": MAX_CHARACTERS - data["providers"][provider],
        }
        for provider in PROVIDERS
    }


def format_status(path: Path) -> str:
    current = status(path)
    return "\n".join(
        f"{provider}: used {current[provider]['used']} remaining {current[provider]['remaining']}"
        for provider in PROVIDERS
    )


def read_key(env_name: str, environ: dict | None = None) -> str:
    source = os.environ if environ is None else environ
    if not isinstance(env_name, str) or not env_name:
        raise MeterError("API key is missing")
    value = source.get(env_name)
    if not isinstance(value, str):
        raise MeterError("API key is missing")
    cleaned = value.strip()
    if not cleaned:
        raise MeterError("API key is missing")
    if _has_control(cleaned) or len(cleaned) > MAX_KEY_CHARACTERS:
        raise MeterError("API key refused")
    return cleaned


def redact(text: str, secrets) -> str:
    needles = []
    exact = []
    for secret in secrets:
        if not isinstance(secret, str) or not secret:
            continue
        stripped = secret.strip()
        if len(secret) > MAX_KEY_CHARACTERS or len(stripped) > MAX_KEY_CHARACTERS:
            exact.extend(item for item in (secret, stripped) if item)
            continue
        variants = {secret, stripped}
        escaped = set()
        for item in variants:
            if not item:
                continue
            escaped.add(item)
            escaped.add(item.encode("unicode_escape").decode("ascii"))
            escaped.add(repr(item)[1:-1])
        for item in escaped:
            needles.append(item)
            if len(item) < 4:
                continue
            for size in range(4, len(item) + 1):
                for start in range(0, len(item) - size + 1):
                    needles.append(item[start:start + size])
    cleaned = text
    for needle in exact:
        cleaned = cleaned.replace(needle, "[REDACTED]")
    for needle in sorted(set(needles), key=len, reverse=True):
        if needle:
            cleaned = cleaned.replace(needle, "[REDACTED]")
    return cleaned


def load_voices(path: Path) -> dict:
    try:
        lines = Path(path).read_text(encoding="utf-8").splitlines()
    except OSError:
        raise MeterError("voice list unreadable") from None
    sections = {"elevenlabs": {}, "google": {}}
    current = None
    for line in lines:
        stripped = line.strip()
        if stripped == "## ElevenLabs":
            current = "elevenlabs"
            continue
        if stripped == "## Google":
            current = "google"
            continue
        if current is None or not stripped.startswith("|"):
            continue
        cells = [cell.strip() for cell in stripped.strip("|").split("|")]
        if len(cells) != 4 or cells[0] == "id" or all(set(cell) <= set("-: ") for cell in cells):
            continue
        voice_id, name, kind, why = cells
        labelled = f"{voice_id} {name} {kind}".lower()
        if any(banned in labelled for banned in BANNED_LABELS):
            raise MeterError("voice refused")
        if current == "elevenlabs" and kind != "premade-default":
            raise MeterError("voice refused")
        if current == "google" and kind not in {"neural2", "wavenet", "chirp-hd"}:
            raise MeterError("voice refused")
        if not why:
            raise MeterError("voice refused")
        sections[current][voice_id] = {"name": name, "kind": kind, "why": why}
    if not sections["elevenlabs"] or not sections["google"]:
        raise MeterError("voice list unreadable")
    return sections


def require_voice(provider: str, voice_id: str, voices: dict) -> dict:
    if provider not in voices or not isinstance(voice_id, str):
        raise MeterError("voice refused")
    lowered = voice_id.lower()
    if any(banned in lowered for banned in BANNED_LABELS):
        raise MeterError("voice refused")
    entry = voices[provider].get(voice_id)
    if entry is None:
        raise MeterError("voice refused")
    return entry


class _RefuseRedirect(urllib.request.HTTPRedirectHandler):
    def http_error_302(self, req, fp, code, msg, headers):
        raise MeterError("redirect refused") from None

    http_error_301 = http_error_303 = http_error_307 = http_error_308 = http_error_302


def http_post(url: str, payload: bytes, headers: dict, secrets, timeout: int = 30) -> bytes:
    try:
        safe = _safe_headers(headers)
        request = urllib.request.Request(url, data=payload, headers=safe, method="POST")
    except MeterError:
        raise
    except Exception:
        raise MeterError("request refused") from None
    opener = urllib.request.build_opener(_RefuseRedirect())
    try:
        with opener.open(request, timeout=timeout) as response:
            body = response.read()
    except MeterError:
        raise
    except urllib.error.HTTPError as error:
        try:
            detail = error.read().decode("utf-8", "replace")
        except Exception:
            detail = ""
        cleaned = redact(detail, secrets)[:MAX_ERROR_BODY]
        raise MeterError(f"HTTP {error.code}: {cleaned}") from None
    except Exception:
        raise MeterError("request refused") from None
    if not body:
        raise MeterError("provider response refused")
    return body


def _has_control(value: str) -> bool:
    return any(unicodedata.category(char) == "Cc" or ord(char) < 32 or ord(char) == 127 for char in value)


def _safe_headers(headers: dict) -> dict:
    safe = {}
    for name, value in headers.items():
        if not isinstance(name, str) or not isinstance(value, str):
            raise MeterError("request refused")
        if _has_control(name) or _has_control(value) or len(name) > MAX_KEY_CHARACTERS or len(value) > MAX_KEY_CHARACTERS:
            raise MeterError("request refused")
        safe[name] = value
    return safe


def _open_nofollow(path: Path, flags: int) -> int:
    if path.is_symlink():
        raise MeterError("ledger refused")
    try:
        fd = os.open(path, flags | os.O_NOFOLLOW | os.O_CLOEXEC)
    except OSError as error:
        if error.errno == errno.ENOENT:
            raise MeterError("ledger missing") from None
        if error.errno == errno.ELOOP:
            raise MeterError("ledger refused") from None
        raise MeterError("ledger unreadable") from None
    try:
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            raise MeterError("ledger refused")
    except MeterError:
        os.close(fd)
        raise
    return fd


def _read(path: Path) -> dict:
    fd = _open_nofollow(path, os.O_RDONLY)
    try:
        chunks = []
        while True:
            block = os.read(fd, 65536)
            if not block:
                break
            chunks.append(block)
        raw = b"".join(chunks).decode("utf-8")
    except OSError:
        raise MeterError("ledger unreadable") from None
    except UnicodeError:
        raise MeterError("ledger corrupt: no call made") from None
    finally:
        os.close(fd)
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        raise MeterError("ledger corrupt: no call made") from None
    providers = data.get("providers") if isinstance(data, dict) else None
    if not isinstance(data, dict) or data.get("version") != 1 or not isinstance(providers, dict):
        raise MeterError("ledger corrupt: no call made")
    if set(providers) != set(PROVIDERS):
        raise MeterError("ledger corrupt: no call made")
    for value in providers.values():
        if type(value) is not int or value < 0 or value > MAX_CHARACTERS:
            raise MeterError("ledger corrupt: no call made")
    return data


def _atomic_write(path: Path, text: str) -> None:
    if path.is_symlink():
        raise MeterError("ledger refused")
    fd, temporary = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(text)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    except Exception:
        try:
            os.unlink(temporary)
        except OSError:
            pass
        raise MeterError("ledger failed") from None


class _lock:
    def __init__(self, path: Path):
        self.path = path
        self.fd = None

    def __enter__(self):
        lock_path = self.path.with_name(self.path.name + ".lock")
        if lock_path.is_symlink():
            raise MeterError("ledger refused")
        try:
            self.fd = os.open(lock_path, os.O_CREAT | os.O_RDWR | os.O_CLOEXEC | os.O_NOFOLLOW, 0o600)
            fcntl.flock(self.fd, fcntl.LOCK_EX)
        except OSError as error:
            if self.fd is not None:
                os.close(self.fd)
                self.fd = None
            if error.errno == errno.ELOOP:
                raise MeterError("ledger refused") from None
            raise MeterError("ledger failed") from None
        return self

    def __exit__(self, *_args):
        if self.fd is not None:
            try:
                fcntl.flock(self.fd, fcntl.LOCK_UN)
            finally:
                os.close(self.fd)
        return False


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="meter")
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("init", "status"):
        command = commands.add_parser(name)
        command.add_argument("--ledger", required=True)
    reserve_command = commands.add_parser("reserve")
    reserve_command.add_argument("--ledger", required=True)
    reserve_command.add_argument("--provider", required=True)
    reserve_command.add_argument("--characters", required=True, type=int)
    args = parser.parse_args(argv)
    path = Path(args.ledger)
    try:
        if args.command == "init":
            initialize(path)
        elif args.command == "reserve":
            reserve(path, args.provider, args.characters)
        else:
            print(format_status(path))
    except MeterError as error:
        print(redact(str(error), []), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
