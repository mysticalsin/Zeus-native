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
    "verdict",
)

# Speech in these fixtures sits near -21 LUFS. Below -70 LUFS there is nothing to hear.
SILENCE_LUFS = -70.0
# The metrics module already calls a frame silent at RMS 0.01. A whole clip under that is silence.
SILENCE_RMS = 0.01
# EBU R128 treats a true peak above -1.0 dBTP as clipping, before any sample reaches full scale.
CLIP_TRUE_PEAK_DBTP = -1.0
# One wrong word in ten is still the same sentence. Above that, the transcript is the wrong line.
WER_MAX = 0.10
# Zeus demotes a non-ElevenLabs engine once time to first audio passes 2.5 s.
TTFA_BUDGET_S = 2.5
# Kokoro returns a long answer as one file. 5.31 s is late but listenable. 9.5 s is not.
TTFA_LONG_ANSWER_BUDGET_S = 8.0

COMPARISON_LABEL = (
    "OFFLINE ENGINE COMPARISON of Kokoro, ElevenLabs non-streaming, and Google Cloud TTS. "
    "This is not the live Zeus provider order (ElevenLabs > OpenAI > Gemini). "
    "It does not drive Murmure or Scribe."
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
        if isinstance(timing.get("text"), str):
            row["text"] = timing["text"]
        if isinstance(timing.get("transcript"), str):
            row["transcript"] = timing["transcript"]
        rows.append(row)
    return rows


def render_markdown(rows: list[dict]) -> str:
    header = "| " + " | ".join(COLUMNS) + " |"
    rule = "| " + " | ".join("---" for _ in COLUMNS) + " |"
    body = [header, rule]
    for row in rows:
        cells = []
        for column in COLUMNS:
            if column == "verdict":
                cells.append(_verdict(row))
            else:
                cells.append(_cell(column, row.get(column)))
        body.append("| " + " | ".join(cells) + " |")
    if len(body) == 2:
        body.append("| " + " | ".join("" for _ in COLUMNS) + " |")
    lines = [
        "# OFFLINE ENGINE COMPARISON",
        "",
        COMPARISON_LABEL,
        "",
        "Each row is one rendered script. Time to first audio uses the timing JSON when it records `first_audio_s`; otherwise it is the first non-silent sample in the WAV. Barge-in stop latency is present only when the timing JSON records both the request and the stop. FAIL and WARN are not ordinary rows.",
        "",
        *body,
        "",
    ]
    return "\n".join(lines)


def evaluate(rows: list[dict]) -> tuple[int, list[str]]:
    """Return the process code and the FAIL or WARN lines for these rows."""
    lines: list[str] = []
    failed = False
    for row in rows:
        clip = _clip(row)
        refused = row.get("voice_refused")
        if isinstance(refused, str) and refused.strip():
            lines.append(f"FAIL {clip} voice refused: {refused.strip()}")
            failed = True
        for level, metric, value, limit in _breaches(row):
            lines.append(f"{level} {clip} {metric} {_num(value)} {_num(limit)}")
            if level == "FAIL":
                failed = True
    return (1 if failed else 0), lines


def _breaches(row: dict):
    found = []
    if _below(row.get("integrated_lufs"), SILENCE_LUFS):
        found.append(("FAIL", "integrated_lufs", row["integrated_lufs"], SILENCE_LUFS))
    if _below(row.get("rms"), SILENCE_RMS):
        found.append(("FAIL", "rms", row["rms"], SILENCE_RMS))
    peak = row.get("true_peak_dbtp")
    if _finite(peak) and peak > CLIP_TRUE_PEAK_DBTP:
        found.append(("FAIL", "true_peak_dbtp", peak, CLIP_TRUE_PEAK_DBTP))
    count = row.get("clipping_count")
    if isinstance(count, int) and not isinstance(count, bool) and count > 0:
        found.append(("FAIL", "clipping_count", count, 0))
    rate = _transcript_rate(row)
    if rate is not None and rate > WER_MAX:
        found.append(("FAIL", "word_error_rate", rate, WER_MAX))
    ttfa = row.get("ttfa_s")
    if _finite(ttfa):
        if _long_answer(row):
            if ttfa > TTFA_LONG_ANSWER_BUDGET_S:
                found.append(("FAIL", "ttfa_s", ttfa, TTFA_LONG_ANSWER_BUDGET_S))
            elif ttfa > TTFA_BUDGET_S:
                found.append(("WARN", "ttfa_s", ttfa, TTFA_LONG_ANSWER_BUDGET_S))
        elif ttfa > TTFA_BUDGET_S:
            found.append(("FAIL", "ttfa_s", ttfa, TTFA_BUDGET_S))
    return found


def _verdict(row: dict) -> str:
    _code, lines = evaluate([row])
    if any(line.startswith("FAIL ") for line in lines):
        return "FAIL"
    if any(line.startswith("WARN ") for line in lines):
        return "WARN"
    return "PASS"


def _clip(row: dict) -> str:
    for key in ("script", "wav"):
        value = row.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
    return "clip"


def _long_answer(row: dict) -> bool:
    script = row.get("script")
    return isinstance(script, str) and "long-answer" in script


def _transcript_rate(row: dict) -> float | None:
    if "transcript" not in row:
        return None
    transcript = row.get("transcript")
    expected = row.get("expected_text")
    if not isinstance(expected, str):
        expected = row.get("text")
    if not isinstance(transcript, str) or not isinstance(expected, str):
        return None
    return word_error_rate(transcript, expected)


def word_error_rate(hypothesis: str, reference: str) -> float:
    """Word Levenshtein distance divided by the number of expected words."""
    hyp = _words(hypothesis)
    ref = _words(reference)
    if not ref and not hyp:
        return 0.0
    if not ref:
        return 1.0
    previous = list(range(len(hyp) + 1))
    for i, expected in enumerate(ref, start=1):
        current = [i]
        for j, heard in enumerate(hyp, start=1):
            cost = 0 if heard == expected else 1
            current.append(min(current[j - 1] + 1, previous[j] + 1, previous[j - 1] + cost))
        previous = current
    return previous[-1] / len(ref)


def _words(text: str) -> list[str]:
    words = []
    for token in text.split():
        cleaned = "".join(ch for ch in token.lower() if ch.isalnum())
        if cleaned:
            words.append(cleaned)
    return words


def _below(value, floor: float) -> bool:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return False
    if isinstance(value, float) and math.isnan(value):
        return False
    return value < floor


def _finite(value) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def _num(value) -> str:
    if isinstance(value, bool):
        return str(value)
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        if math.isinf(value):
            return "-inf" if value < 0 else "inf"
        return f"{value:.2f}"
    return str(value)


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
        numbers = [
            item for item in value
            if isinstance(item, (int, float)) and not isinstance(item, bool) and math.isfinite(item)
        ]
        noun = "gap" if len(value) == 1 else "gaps"
        if not numbers:
            return f"{len(value)} {noun}"
        return f"{len(value)} {noun}, longest {max(numbers):.2f}s"
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


def main(argv: list[str] | None = None) -> int:
    import argparse

    parser = argparse.ArgumentParser(description="Compare rendered voice providers.")
    parser.add_argument("root", type=Path, help="Directory of provider folders containing WAV and timing JSON files.")
    parser.add_argument("--output", type=Path, help="Where to write metrics.json and report.md. Defaults to root.")
    args = parser.parse_args(argv)
    output = args.output or args.root
    rows = collect(args.root)
    metrics_path, report_path = write_report(rows, output)
    code, messages = evaluate(rows)
    for message in messages:
        print(message)
    print(f"rows: {len(rows)}")
    print(metrics_path)
    print(report_path)
    return code


if __name__ == "__main__":
    sys.exit(main())
