"""Build a provider comparison from measured rows.

``write_report`` writes ``metrics.json`` and ``report.md`` into the directory
it is given. It does not create files anywhere else.
"""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from metrics import measure

COLUMNS = (
    "provider",
    "script",
    "ttfa_s",
    "wav_onset_s",
    "integrated_lufs",
    "true_peak_dbtp",
    "clipping_count",
    "inter_chunk_gaps_s",
    "speech_rate_wps",
    "pitch_std_hz",
    "barge_in_stop_latency_s",
)


def collect(root: str | Path) -> list[dict]:
    """Measure every WAV that has a sibling ``<name>.timing.json``."""
    rows: list[dict] = []
    base = Path(root)
    for wav_path in sorted(base.rglob("*.wav")):
        timing_path = wav_path.with_name(wav_path.stem + ".timing.json")
        if not timing_path.is_file():
            continue
        row = measure(wav_path, timing_path)
        timing = json.loads(timing_path.read_text(encoding="utf-8"))
        row["provider"] = str(timing.get("provider") or wav_path.parent.name)
        row["script"] = str(timing.get("script") or wav_path.stem)
        row["wav"] = wav_path.name
        rows.append(row)
    return rows


def render_markdown(rows: list[dict]) -> str:
    header = "| " + " | ".join(COLUMNS) + " |"
    rule = "| " + " | ".join("---" for _ in COLUMNS) + " |"
    body = [header, rule]
    for row in rows:
        body.append("| " + " | ".join(_cell(column, row.get(column)) for column in COLUMNS) + " |")
    if len(body) == 2:
        body.append("| " + " | ".join("" for _ in COLUMNS) + " |")
    lines = [
        "# Voice QA comparison",
        "",
        "Each row is one rendered script. Time to first audio uses the timing JSON when it records `first_audio_s`; otherwise it is the first non-silent sample in the WAV. Barge-in stop latency is present only when the timing JSON records both the request and the stop.",
        "",
        *body,
        "",
    ]
    return "\n".join(lines)


def write_report(rows: list[dict], output_dir: str | Path) -> tuple[Path, Path]:
    destination = Path(output_dir)
    destination.mkdir(parents=True, exist_ok=True)
    metrics_path = destination / "metrics.json"
    report_path = destination / "report.md"
    payload = {"rows": [_jsonable(row) for row in rows]}
    metrics_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    report_path.write_text(render_markdown(rows), encoding="utf-8")
    return metrics_path, report_path


def _cell(column: str, value) -> str:
    if column == "barge_in_stop_latency_s" and value is None:
        return "not measured"
    if column == "inter_chunk_gaps_s" and isinstance(value, list):
        if not value:
            return ""
        longest = max(value)
        noun = "gap" if len(value) == 1 else "gaps"
        return f"{len(value)} {noun}, longest {longest:.2f}s"
    if value is None:
        return ""
    if isinstance(value, bool):
        return "yes" if value else "no"
    if isinstance(value, float):
        if not math.isfinite(value):
            return "-inf" if value < 0 else "inf"
        return f"{value:.2f}"
    if isinstance(value, list):
        return ", ".join(_cell("", item) for item in value)
    return str(value).replace("|", "\\|")


def _jsonable(value):
    if isinstance(value, dict):
        return {str(key): _jsonable(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [_jsonable(item) for item in value]
    if isinstance(value, float) and not math.isfinite(value):
        return None
    if isinstance(value, (np_floating(),)):
        number = float(value)
        return None if not math.isfinite(number) else number
    if hasattr(value, "item") and callable(value.item):
        try:
            return _jsonable(value.item())
        except (ValueError, TypeError):
            return value
    return value


def np_floating():
    import numpy as np

    return np.floating


def main() -> None:
    import argparse

    parser = argparse.ArgumentParser(description="Compare rendered voice providers.")
    parser.add_argument("root", type=Path, help="Directory of provider folders containing WAV and timing JSON files.")
    parser.add_argument("--output", type=Path, help="Where to write metrics.json and report.md. Defaults to root.")
    args = parser.parse_args()
    output = args.output or args.root
    rows = collect(args.root)
    metrics_path, report_path = write_report(rows, output)
    print(f"rows: {len(rows)}")
    print(metrics_path)
    print(report_path)


if __name__ == "__main__":
    main()
