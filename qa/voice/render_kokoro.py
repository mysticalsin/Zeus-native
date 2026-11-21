"""Render the fixed script set with local Kokoro on Linux.

The weights are the v1.0 ONNX export Zeus already documents in
``Sources/Zeus/Voice/KokoroWorker.swift``. Kokoro-82M itself is Apache-2.0
(hexgrad/kokoro). The ``kokoro-onnx`` package that runs the export is MIT.
This harness speaks a ``bm_*`` voice. The shipping app default is ``am_michael``
at speed 0.88 with ``lang="en-us"``; see ``qa/voice/README.md``.

Nothing is written outside ``--output``. Weight files stay in ``--cache``.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import time
import urllib.request
from pathlib import Path

import importlib.metadata

import numpy as np
import soundfile as sf

MARKER = "[[BARGE-IN]]"
MODEL_FILES = (
    {
        "name": "kokoro-v1.0.onnx",
        "url": "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/kokoro-v1.0.onnx",
        "min_bytes": 100_000_000,
    },
    {
        "name": "voices-v1.0.bin",
        "url": "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/voices-v1.0.bin",
        "min_bytes": 5_000_000,
    },
)
WEIGHTS_LICENSE = {
    "spdx": "Apache-2.0",
    "name": "Kokoro-82M",
    "url": "https://raw.githubusercontent.com/hexgrad/kokoro/main/LICENSE",
    "model_card": "https://huggingface.co/hexgrad/Kokoro-82M",
}
PACKAGE_LICENSE_NAME = "MIT"


def main() -> int:
    parser = argparse.ArgumentParser(description="Render qa/voice/scripts with Kokoro.")
    parser.add_argument("--scripts", type=Path, default=Path(__file__).resolve().parent / "scripts")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--cache", type=Path, default=Path.home() / ".cache" / "zeus-voice-qa")
    parser.add_argument("--voice", default="bm_george")
    parser.add_argument("--speed", type=float, default=0.88)
    args = parser.parse_args()
    if not args.voice.startswith("bm_"):
        print(f"voice must be a bm_* id, got {args.voice}", file=sys.stderr)
        return 2
    if not 0.5 <= args.speed <= 2.0:
        print(f"speed must be between 0.5 and 2.0, got {args.speed}", file=sys.stderr)
        return 2

    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    scripts = sorted(args.scripts.glob("*.txt"))
    if not scripts:
        print(f"no scripts in {args.scripts}", file=sys.stderr)
        return 2

    cache = args.cache.resolve()
    cache.mkdir(parents=True, exist_ok=True)
    files = []
    for source in MODEL_FILES:
        path = cache / source["name"]
        _download(source["url"], path, source["min_bytes"])
        digest, size = _sha256(path)
        files.append({**source, "sha256": digest, "bytes": size, "path": str(path)})

    license_record = _weights_license(cache)
    package_license = _package_license()

    from kokoro_onnx import Kokoro

    started = time.perf_counter()
    engine = Kokoro(files[0]["path"], files[1]["path"])
    load_s = time.perf_counter() - started
    available = [name for name in engine.voices.files if name.startswith("bm_")]
    if args.voice not in engine.voices.files:
        print(f"{args.voice} is not in the voice pack. bm_* voices: {', '.join(available)}", file=sys.stderr)
        return 2

    failures = []
    rendered = []
    for script in scripts:
        raw = script.read_text(encoding="utf-8")
        spoken, marker_at = _spoken(raw)
        lang = "fr-fr" if script.stem.endswith("french") or "Bonjour" in raw else "en-gb"
        try:
            audio, sample_rate, wall_s = _synthesize(engine, spoken, args.voice, args.speed, lang)
        except Exception as error:  # noqa: BLE001 — one script must not hide the others
            failures.append({"script": script.stem, "lang": lang, "error": f"{type(error).__name__}: {error}"})
            _write_json(output, f"{script.stem}.error.json", failures[-1])
            continue
        wav_path = _confine(output, f"{script.stem}.wav")
        sf.write(wav_path, np.asarray(audio, dtype=np.float32), sample_rate, subtype="PCM_16")
        timing = {
            "provider": "kokoro",
            "script": script.stem,
            "voice": args.voice,
            "speed": args.speed,
            "lang": lang,
            "text": spoken,
            "request_start_s": 0.0,
            "wav_origin_s": 0.0,
            "first_audio_s": wall_s,
            "ttfa_note": "Wall clock of Kokoro.create. The call returns the whole utterance; this engine does not stream.",
            "sample_rate": sample_rate,
            "barge_in_marker_char": marker_at,
        }
        _write_json(output, f"{script.stem}.timing.json", timing)
        rendered.append({"script": script.stem, "bytes": wav_path.stat().st_size, "first_audio_s": wall_s, "lang": lang})

    provenance = {
        "provider": "kokoro",
        "voice": args.voice,
        "speed": args.speed,
        "kokoro_onnx_version": importlib.metadata.version("kokoro-onnx"),
        "kokoro_onnx_license": package_license,
        "weights": [{key: value for key, value in item.items() if key != "path"} for item in files],
        "weights_license": license_record,
        "model_load_s": load_s,
        "rendered": rendered,
        "failures": failures,
        "bm_voices": available,
    }
    _write_json(output, "provenance.json", provenance)
    print(json.dumps({"rendered": len(rendered), "failures": len(failures), "output": str(output)}, indent=2))
    return 1 if failures else 0


def _synthesize(engine, text: str, voice: str, speed: float, lang: str):
    started = time.perf_counter()
    audio, sample_rate = engine.create(text, voice=voice, speed=speed, lang=lang)
    return audio, sample_rate, time.perf_counter() - started


def _spoken(text: str) -> tuple[str, int | None]:
    index = text.find(MARKER)
    if index < 0:
        return " ".join(text.split()), None
    spoken = text[:index] + " " + text[index + len(MARKER) :]
    return " ".join(spoken.split()), index


def _download(url: str, path: Path, min_bytes: int) -> None:
    if path.is_file() and path.stat().st_size >= min_bytes:
        return
    temporary = path.with_name(path.name + ".partial")
    urllib.request.urlretrieve(url, temporary)  # noqa: S310 — the URL is the pinned model release
    if temporary.stat().st_size < min_bytes:
        temporary.unlink(missing_ok=True)
        raise SystemExit(f"{path.name} download is smaller than {min_bytes} bytes")
    temporary.replace(path)


def _sha256(path: Path) -> tuple[str, int]:
    digest = hashlib.sha256()
    size = 0
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
            size += len(chunk)
    return digest.hexdigest(), size


def _weights_license(cache: Path) -> dict:
    destination = cache / "Kokoro-82M-LICENSE"
    record = dict(WEIGHTS_LICENSE)
    try:
        if not destination.is_file():
            urllib.request.urlretrieve(WEIGHTS_LICENSE["url"], destination)  # noqa: S310
        text = destination.read_text(encoding="utf-8", errors="replace")
        digest, size = _sha256(destination)
        record.update({
            "fetched": True,
            "sha256": digest,
            "bytes": size,
            "opens_with_apache_heading": text.lstrip().startswith("Apache License"),
        })
    except Exception as error:  # noqa: BLE001 — a missing license page is reported, not invented
        record.update({"fetched": False, "error": f"{type(error).__name__}: {error}"})
    return record


def _package_license() -> dict:
    try:
        dist = importlib.metadata.distribution("kokoro-onnx")
    except importlib.metadata.PackageNotFoundError as error:
        return {"spdx": None, "error": str(error)}
    license_text = ""
    for name in ("licenses/LICENSE", "LICENSE"):
        try:
            license_text = dist.read_text(name) or ""
        except FileNotFoundError:
            continue
        if license_text:
            break
    spdx = PACKAGE_LICENSE_NAME if license_text.startswith("MIT License") else None
    return {
        "spdx": spdx,
        "sha256": hashlib.sha256(license_text.encode("utf-8")).hexdigest() if license_text else None,
        "opens_with_mit_heading": license_text.startswith("MIT License"),
        "version": dist.version,
    }


def _confine(root: Path, name: str) -> Path:
    target = (root / name).resolve()
    if target != root and root not in target.parents:
        raise SystemExit(f"refusing to write outside {root}: {target}")
    return target


def _write_json(root: Path, name: str, payload: dict) -> None:
    path = _confine(root, name)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    sys.exit(main())
