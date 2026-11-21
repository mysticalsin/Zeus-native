"""Render one line with a premade ElevenLabs default voice.

The key is read from the environment variable named by --key-env. It is sent
only in the xi-api-key header. Nothing in this process prints or stores it.
No call is made until the character ledger accepts the text.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import meter

VOICES = Path(__file__).resolve().with_name("VOICES.md")
ENDPOINT = "https://api.elevenlabs.io/v1/text-to-speech/{voice}?output_format=pcm_24000"
MODEL = "eleven_flash_v2_5"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="render_elevenlabs")
    parser.add_argument("--text", required=True)
    parser.add_argument("--voice", required=True)
    parser.add_argument("--key-env", required=True)
    parser.add_argument("--ledger", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args(argv)
    return _render(args.text, args.voice, args.key_env, Path(args.ledger), Path(args.output))


def _render(text: str, voice: str, key_env: str, ledger: Path, output: Path) -> int:
    secrets: list[str] = []
    charged = False
    try:
        try:
            voices = meter.load_voices(VOICES)
            meter.require_voice("elevenlabs", voice, voices)
            key = meter.read_key(key_env)
            secrets.append(key)
            meter.reserve(ledger, "elevenlabs", len(text))
            charged = True
            audio = _fetch(text, voice, key, secrets)
            _write(output, audio)
        except meter.MeterError as error:
            print(meter.redact(str(error), secrets), file=sys.stderr)
        except Exception:
            print("request refused", file=sys.stderr)
        else:
            return 0
        if charged:
            print("characters stayed counted", file=sys.stderr)
        return 1
    finally:
        _report(ledger)


def _fetch(text: str, voice: str, key: str, secrets: list[str]) -> bytes:
    payload = json.dumps({"model_id": MODEL, "text": text}).encode("utf-8")
    headers = {
        "Accept": "application/octet-stream",
        "Content-Type": "application/json",
        "xi-api-key": key,
    }
    return meter.http_post(ENDPOINT.format(voice=voice), payload, headers, secrets)


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
