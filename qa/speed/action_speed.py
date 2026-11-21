#!/usr/bin/env python3
"""Action-speed harness.

Drives the six reference prompts through `Zeus --ask` (a Debug build) and
prints p50 and p95 per stage per prompt type, plus the reference-app baseline.

The app writes the trace only when ZEUS_ACTION_SPEED_TRACE=1. This script sets
that flag for the child process. The trace file holds a turn id, a stage name,
and a monotonic nanosecond stamp. It does not hold the prompt.

    ZEUS_ACTION_SPEED_TRACE=1 python3 qa/speed/action_speed.py --n 20 --zeus .build/debug/Zeus

Tests pass --fixture and never launch Zeus. --ask exists only in a Debug build.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import pathlib
import subprocess
import sys
import tempfile
from collections import defaultdict

STAGES = (
    "keyRelease",
    "sttFinal",
    "requestSent",
    "firstModelToken",
    "firstToolDecision",
    "firstTtsAudio",
    "firstOverlayPaint",
    "pointerArrival",
)

# Seconds from key release, frame by frame on the reference app.
BASELINE_S = {
    "capital": {"firstTtsAudio": 2.4, "firstOverlayPaint": 9.4, "answerDone": 14.8, "filler": 2.0},
    "window": {"firstTtsAudio": 2.8},
    "percent": {"firstTtsAudio": 3.9},
    "shorter": {"firstTtsAudio": 4.9},
    "router": {"firstTtsAudio": 5.9, "firstOverlayPaint": 29.8, "drawingEnd": 68.9},
    "wallpaper": {"firstTtsAudio": 4.1, "pointerBox": 4.3, "pointerArrival": 5.1},
}

TARGETS_S = {
    "firstTtsAudio_p50": 2.0,
    "firstTtsAudio_p95": 3.0,
    "pointerArrival": 3.0,
    "firstOverlayPaint": 4.0,
}

DEFAULT_REPEATS = 20

PROMPTS = (
    ("capital", "What's the capital of Australia and its population?"),
    ("window", "What is this window?"),
    ("percent", "18% of 240"),
    ("router", "Draw how my router talks to my Mac"),
    ("wallpaper", "Where do I click to change my wallpaper?"),
    ("shorter", "Make it shorter"),
)

ALLOWED_KEYS = {"turn", "stage", "monoNs"}


def percentile(values, p):
    if not values:
        return None
    ordered = sorted(values)
    rank = math.ceil(p / 100 * len(ordered))
    index = min(len(ordered) - 1, max(0, rank - 1))
    return ordered[index]


def parse_trace_line(line):
    """One production trace line. Extra keys, or any transcript text, are refused."""
    text = line.strip()
    if not text:
        return None
    lowered = text.lower()
    if "transcript" in lowered or "prompt" in lowered:
        raise ValueError("trace line carries text")
    object = json.loads(text)
    if not isinstance(object, dict) or set(object) != ALLOWED_KEYS:
        raise ValueError("trace line keys")
    if object["stage"] not in STAGES:
        raise ValueError("trace stage")
    if not isinstance(object["monoNs"], int) or isinstance(object["monoNs"], bool):
        raise ValueError("trace stamp")
    if not isinstance(object["turn"], str) or not object["turn"]:
        raise ValueError("trace turn")
    return object


def offsets_ms(events):
    key = next(event["monoNs"] for event in events if event["stage"] == "keyRelease")
    offsets = {}
    for event in events:
        offsets[event["stage"]] = max(0, event["monoNs"] - key) // 1_000_000
    return offsets


def group_turns(lines):
    grouped = defaultdict(list)
    order = []
    for line in lines:
        event = parse_trace_line(line)
        if event is None:
            continue
        if event["turn"] not in grouped:
            order.append(event["turn"])
        grouped[event["turn"]].append(event)
    return [{"turn": turn, "offsets": offsets_ms(grouped[turn])} for turn in order]


def attach_kinds(turns, kinds):
    if len(turns) != len(kinds):
        raise ValueError("kind count")
    samples = []
    for turn, kind in zip(turns, kinds):
        if kind not in BASELINE_S:
            raise ValueError("prompt kind")
        samples.append({"kind": kind, "offsets": turn["offsets"]})
    return samples


def summarize(samples):
    by_kind = defaultdict(lambda: defaultdict(list))
    for sample in samples:
        for stage, ms in sample["offsets"].items():
            if stage in STAGES:
                by_kind[sample["kind"]][stage].append(ms)
    rows = []
    for kind, _prompt in PROMPTS:
        for stage in STAGES:
            values = by_kind[kind][stage]
            rows.append({
                "kind": kind,
                "stage": stage,
                "n": len(values),
                "p50_ms": percentile(values, 50),
                "p95_ms": percentile(values, 95),
                "baseline_s": BASELINE_S[kind].get(stage),
            })
    return rows


def format_table(rows):
    header = f"{'prompt':<12} {'stage':<20} {'n':>4} {'p50_ms':>10} {'p95_ms':>10} {'baseline_s':>12}"
    lines = [header]
    for row in rows:
        p50 = "-" if row["p50_ms"] is None else str(row["p50_ms"])
        p95 = "-" if row["p95_ms"] is None else str(row["p95_ms"])
        base = "-" if row["baseline_s"] is None else f"{row['baseline_s']:.1f}"
        lines.append(f"{row['kind']:<12} {row['stage']:<20} {row['n']:>4} {p50:>10} {p95:>10} {base:>12}")
    return "\n".join(lines)


def report(samples):
    rows = summarize(samples)
    payload = {
        "rows": rows,
        "baseline_s": BASELINE_S,
        "targets_s": TARGETS_S,
        "prompts": [{"kind": kind, "text": text} for kind, text in PROMPTS],
    }
    return format_table(rows), payload


def load_fixture(path):
    """Fixture JSON: {\"runs\": [{\"kind\": \"capital\", \"events\": [{\"turn\", \"stage\", \"monoNs\"}]}]}.

    `kind` lives in the fixture, not in the trace lines.
    """
    document = json.loads(path.read_text(encoding="utf-8"))
    samples = []
    for run in document["runs"]:
        lines = []
        for event in run["events"]:
            lines.append(json.dumps({
                "turn": event["turn"],
                "stage": event["stage"],
                "monoNs": event["monoNs"],
            }, separators=(",", ":")))
        turns = group_turns(lines)
        if len(turns) != 1:
            raise ValueError("fixture run")
        samples.extend(attach_kinds(turns, [run["kind"]]))
    return samples


def drive(zeus, repeats, trace_path):
    kinds = []
    lines = []
    env = os.environ.copy()
    env["ZEUS_ACTION_SPEED_TRACE"] = "1"
    env["ZEUS_ACTION_SPEED_TRACE_FILE"] = str(trace_path)
    for _ in range(repeats):
        for kind, prompt in PROMPTS:
            before = _line_count(trace_path)
            subprocess.run([zeus, "--ask", prompt], env=env, check=False, timeout=70,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            added = _new_lines(trace_path, before)
            turns = group_turns(added)
            if not turns:
                continue
            lines.extend(added)
            kinds.extend([kind] * len(turns))
    if not lines:
        return []
    return attach_kinds(group_turns(lines), kinds)


def _line_count(path):
    if not path.exists():
        return 0
    with path.open(encoding="utf-8") as handle:
        return sum(1 for _ in handle)


def _new_lines(path, before):
    if not path.exists():
        return []
    with path.open(encoding="utf-8") as handle:
        return [line for index, line in enumerate(handle) if index >= before]


def main(argv=None):
    parser = argparse.ArgumentParser(description="Measure Zeus action speed against the reference app.")
    parser.add_argument("--n", type=int, default=DEFAULT_REPEATS, help="repeats of each prompt (default 20)")
    parser.add_argument("--zeus", help="path to a Debug Zeus binary with --ask")
    parser.add_argument("--fixture", help="synthetic trace fixture; does not launch Zeus")
    args = parser.parse_args(argv)
    if args.n < 1:
        parser.error("--n must be at least 1")
    if args.fixture:
        samples = load_fixture(open_path(args.fixture))
    elif args.zeus:
        with tempfile.TemporaryDirectory(prefix="zeus-action-speed-") as directory:
            trace = os.path.join(directory, "action-speed.jsonl")
            samples = drive(args.zeus, args.n, pathlib.Path(trace))
    else:
        print("ZEUS_ACTION_SPEED_TRACE=1 python3 qa/speed/action_speed.py --n 20 --zeus .build/debug/Zeus", file=sys.stderr)
        return 2
    table, payload = report(samples)
    print(table)
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0


def open_path(text):
    return pathlib.Path(text)


if __name__ == "__main__":
    sys.exit(main())
