"""Render one line with a stock Google Cloud TTS voice.

The key is read from the environment variable named by --key-env. It is sent
only in the X-Goog-Api-Key header, never in the URL. Nothing in this process
prints or stores it. No call is made until the character ledger accepts the text.
"""

from __future__ import annotations

import argparse
import base64
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import meter

VOICES = Path(__file__).resolve().with_name("VOICES.md")
ENDPOINT = "https://texttospeech.googleapis.com/v1/text:synthesize"
MARKERS = ("-Neural2-", "-Wavenet-", "-Chirp3-HD-")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="render_google")
    parser.add_argument("--text", required=True)
    parser.add_argument("--voice", required=True)
    parser.add_argument("--key-env", required=True)
    parser.add_argument("--ledger", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args(argv)
    return _render(args.text, args.voice, args.key_env, Path(args.ledger), Path(args.output))


def _render(text: str, voice: str, key_env: str, ledger: Path, output: Path) -> int:
    secrets: list[str] = []
    try:
        voices = meter.load_voices(VOICES)
        meter.require_voice("google", voice, voices)
        key = meter.read_key(key_env)
        secrets.append(key)
        meter.reserve(ledger, "google", len(text))
        audio = _fetch(text, voice, key, secrets)
        _write(output, audio)
        return 0
    except meter.MeterError as error:
        print(meter.redact(str(error), secrets), file=sys.stderr)
        return 1
    except Exception as error:
        print(meter.redact(str(error), secrets), file=sys.stderr)
        return 1
    finally:
        _report(ledger)


def language_code(voice: str) -> str:
    for marker in MARKERS:
        if marker in voice:
            return voice.split(marker, 1)[0]
    raise meter.MeterError("voice refused")


def _fetch(text: str, voice: str, key: str, secrets: list[str]) -> bytes:
    payload = json.dumps({
        "audioConfig": {"audioEncoding": "LINEAR16", "sampleRateHertz": 24000},
        "input": {"text": text},
        "voice": {"languageCode": language_code(voice), "name": voice},
    }).encode("utf-8")
    headers = {"Content-Type": "application/json", "X-Goog-Api-Key": key}
    body = meter.http_post(ENDPOINT, payload, headers, secrets)
    try:
        encoded = json.loads(body.decode("utf-8"))["audioContent"]
        audio = base64.b64decode(encoded, validate=True)
    except Exception:
        raise meter.MeterError("provider response refused") from None
    if not audio:
        raise meter.MeterError("provider response refused")
    return audio


def _write(output: Path, audio: bytes) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_name(output.name + ".partial")
    temporary.write_bytes(audio)
    temporary.replace(output)


def _report(ledger: Path) -> None:
    try:
        print(meter.format_status(ledger))
    except meter.MeterError:
        print("ledger: unreadable", file=sys.stderr)


if __name__ == "__main__":
    sys.exit(main())
