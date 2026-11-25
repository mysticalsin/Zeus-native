#!/usr/bin/env python3
"""Action-speed harness.

Drives the six reference prompts through `Zeus --ask` (a Debug build) and
prints p50 and p95 per stage per prompt type against the recorded reference
frame baseline. The reference app is not launched. A missing sample is
unmeasured. It is not faster, and it fails the budget score.

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


def seconds_to_ms(seconds):
    """Reference frame times are stored in seconds. Comparison uses whole milliseconds."""
    return int(round(seconds * 1000))


def versus_reference(p50_ms, baseline_s):
    """How a measured p50 sits against the recorded reference frame time.

    The reference app is not launched. `baseline_s` is the owner's frame table.
    A missing Zeus sample is unmeasured, never faster.
    """
    if baseline_s is None:
        return "no_baseline", None, None
    reference_ms = seconds_to_ms(baseline_s)
    if p50_ms is None:
        return "unmeasured", reference_ms, None
    delta = p50_ms - reference_ms
    if delta < 0:
        standing = "faster"
    elif delta > 0:
        standing = "slower"
    else:
        standing = "same"
    return standing, reference_ms, delta


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
    keys = [event["monoNs"] for event in events if event["stage"] == "keyRelease"]
    if not keys:
        raise ValueError("key release")
    key = keys[0]
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
            p50 = percentile(values, 50)
            p95 = percentile(values, 95)
            baseline_s = BASELINE_S[kind].get(stage)
            standing, reference_ms, delta = versus_reference(p50, baseline_s)
            rows.append({
                "kind": kind,
                "stage": stage,
                "n": len(values),
                "p50_ms": p50,
                "p95_ms": p95,
                "baseline_s": baseline_s,
                "reference_ms": reference_ms,
                "delta_p50_ms": delta,
                "versus_reference": standing,
            })
    return rows


def reference_only(baseline=None):
    """Frame marks that are not Zeus stages. Printed so they are not dropped from the comparison."""
    source = BASELINE_S if baseline is None else baseline
    notes = []
    for kind, _prompt in PROMPTS:
        for mark, seconds in source[kind].items():
            if mark in STAGES:
                continue
            notes.append({
                "kind": kind,
                "mark": mark,
                "reference_s": seconds,
                "reference_ms": seconds_to_ms(seconds),
            })
    return notes


def _ceiling_status(p50_ms, p95_ms, ceiling_ms, both):
    if p50_ms is None or (both and p95_ms is None):
        return "unmeasured"
    if both:
        return "inside" if p50_ms <= ceiling_ms and p95_ms <= ceiling_ms else "over"
    return "inside" if p50_ms <= ceiling_ms else "over"


def stage_applies(kind, stage):
    """First audio is a budget on every prompt.

    Pointer and first visual are budgets only where the reference baseline
    records that stage. A capital question does not fail for a missing pointer.
    """
    if stage == "firstTtsAudio":
        return True
    return stage in BASELINE_S.get(kind, {})


def target_verdicts(rows):
    """Score measured percentiles against the action-speed ceilings.

    An empty stage is unmeasured. It is not inside the ceiling.
    """
    by_key = {(row["kind"], row["stage"]): row for row in rows}
    verdicts = []
    for kind, _prompt in PROMPTS:
        audio = by_key[(kind, "firstTtsAudio")]
        for stat, target_key in (("p50_ms", "firstTtsAudio_p50"), ("p95_ms", "firstTtsAudio_p95")):
            ceiling_ms = seconds_to_ms(TARGETS_S[target_key])
            value = audio[stat]
            if value is None:
                status = "unmeasured"
            elif value <= ceiling_ms:
                status = "inside"
            else:
                status = "over"
            verdicts.append({
                "kind": kind,
                "stage": "firstTtsAudio",
                "stat": stat,
                "ms": value,
                "ceiling_ms": ceiling_ms,
                "status": status,
                "applicable": stage_applies(kind, "firstTtsAudio"),
            })
        for stage, target_key in (("pointerArrival", "pointerArrival"), ("firstOverlayPaint", "firstOverlayPaint")):
            row = by_key[(kind, stage)]
            ceiling_ms = seconds_to_ms(TARGETS_S[target_key])
            verdicts.append({
                "kind": kind,
                "stage": stage,
                "stat": "p50_and_p95",
                "p50_ms": row["p50_ms"],
                "p95_ms": row["p95_ms"],
                "ceiling_ms": ceiling_ms,
                "status": _ceiling_status(row["p50_ms"], row["p95_ms"], ceiling_ms, True),
                "applicable": stage_applies(kind, stage),
            })
    return verdicts


def score_budgets(verdicts):
    """The run passes only when every applicable row is inside its ceiling.

    Unmeasured fails the score. Over fails the score. Zero applicable rows
    fail the score. A missing live sample is not a pass.
    """
    checks = [verdict for verdict in verdicts if verdict.get("applicable")]
    inside = sum(verdict["status"] == "inside" for verdict in checks)
    over = sum(verdict["status"] == "over" for verdict in checks)
    unmeasured = sum(verdict["status"] == "unmeasured" for verdict in checks)
    return {
        "passed": bool(checks) and inside == len(checks),
        "checks": len(checks),
        "inside": inside,
        "over": over,
        "unmeasured": unmeasured,
    }


def _cell(value, width, signed=False):
    if value is None:
        text = "-"
    elif signed:
        text = f"{value:+d}"
    else:
        text = str(value)
    return f"{text:>{width}}"


def format_table(rows):
    header = (
        f"{'prompt':<12} {'stage':<20} {'n':>4} {'p50_ms':>10} {'p95_ms':>10} "
        f"{'reference_ms':>13} {'delta_p50_ms':>13} {'versus_reference':<17}"
    )
    lines = [header]
    for row in rows:
        lines.append(
            f"{row['kind']:<12} {row['stage']:<20} {row['n']:>4} "
            f"{_cell(row['p50_ms'], 10)} {_cell(row['p95_ms'], 10)} "
            f"{_cell(row['reference_ms'], 13)} {_cell(row['delta_p50_ms'], 13, signed=True)} "
            f"{row['versus_reference']:<17}"
        )
    return "\n".join(lines)


def format_report(rows, notes, verdicts, score):
    lines = [format_table(rows), "", "reference-only marks (not Zeus stages)"]
    for note in notes:
        lines.append(f"{note['kind']:<12} {note['mark']:<20} {note['reference_ms']:>8} ms")
    lines.extend(["", "targets"])
    for verdict in verdicts:
        shown = verdict.get("ms", verdict.get("p50_ms"))
        mark = "budget" if verdict.get("applicable") else "not-applicable"
        lines.append(
            f"{verdict['kind']:<12} {verdict['stage']:<20} {verdict['stat']:<12} "
            f"{_cell(shown, 8)}  ceiling {verdict['ceiling_ms']:>6}  {verdict['status']:<10} {mark}"
        )
    standing = "pass" if score["passed"] else "fail"
    lines.extend([
        "",
        (
            f"score: {standing}  inside {score['inside']}  "
            f"over {score['over']}  unmeasured {score['unmeasured']}"
        ),
        "reference app: not launched; comparison uses the recorded frame baseline",
    ])
    return "\n".join(lines)


def report(samples):
    rows = summarize(samples)
    notes = reference_only()
    verdicts = target_verdicts(rows)
    score = score_budgets(verdicts)
    payload = {
        "rows": rows,
        "baseline_s": BASELINE_S,
        "targets_s": TARGETS_S,
        "reference_only": notes,
        "target_verdicts": verdicts,
        "score": score,
        "measurement": {
            "reference_app_launched": False,
            "zeus_launched": False,
            "reference_source": "owner frame baseline, seconds from key release",
        },
        "prompts": [{"kind": kind, "text": text} for kind, text in PROMPTS],
    }
    return format_report(rows, notes, verdicts, score), payload


def measurement_exit(missed, passed=True):
    """A lost prompt is an incomplete measurement.

    A finished run whose applicable budgets are unmeasured or over fails the score.
    """
    if missed:
        return 3
    if not passed:
        return 4
    return 0


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


def _launch(command, env, timeout):
    subprocess.run(command, env=env, check=False, timeout=timeout,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def drive(zeus, repeats, trace_path, runner=None, timeout=70):
    """One `--ask` per prompt. A prompt that does not write exactly one turn is missed.

    `runner` replaces the process launch in tests. It must not be a Zeus binary.
    The prompt text is not stored on a miss.
    """
    launch = runner or _launch
    collected = []
    missed = []
    env = os.environ.copy()
    env["ZEUS_ACTION_SPEED_TRACE"] = "1"
    env["ZEUS_ACTION_SPEED_TRACE_FILE"] = str(trace_path)
    for _ in range(repeats):
        for kind, prompt in PROMPTS:
            before = _line_count(trace_path)
            try:
                launch([zeus, "--ask", prompt], env, timeout)
            except subprocess.TimeoutExpired:
                missed.append({"kind": kind, "reason": "timeout"})
                continue
            except OSError:
                missed.append({"kind": kind, "reason": "launch"})
                continue
            try:
                added = _new_lines(trace_path, before)
                turns = group_turns(added)
            except ValueError:
                missed.append({"kind": kind, "reason": "trace"})
                continue
            if len(turns) != 1:
                missed.append({"kind": kind, "reason": "turn_count", "turns": len(turns)})
                continue
            collected.append((kind, added))
    if not collected:
        return [], missed
    lines = [line for _kind, added in collected for line in added]
    kinds = [kind for kind, _added in collected]
    return attach_kinds(group_turns(lines), kinds), missed


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
    missed = []
    launched = False
    if args.fixture:
        samples = load_fixture(open_path(args.fixture))
    elif args.zeus:
        if not pathlib.Path(args.zeus).is_file():
            print(f"Zeus binary not found: {args.zeus}", file=sys.stderr)
            print("ZEUS_ACTION_SPEED_TRACE=1 python3 qa/speed/action_speed.py --n 20 --zeus .build/debug/Zeus", file=sys.stderr)
            return 2
        launched = True
        with tempfile.TemporaryDirectory(prefix="zeus-action-speed-") as directory:
            trace = os.path.join(directory, "action-speed.jsonl")
            try:
                samples, missed = drive(args.zeus, args.n, pathlib.Path(trace))
            except ValueError as error:
                print(f"action-speed trace: {error}", file=sys.stderr)
                return 3
    else:
        print("ZEUS_ACTION_SPEED_TRACE=1 python3 qa/speed/action_speed.py --n 20 --zeus .build/debug/Zeus", file=sys.stderr)
        return 2
    table, payload = report(samples)
    payload["measurement"]["zeus_launched"] = launched
    if launched:
        payload["missed"] = missed
    print(table)
    print(json.dumps(payload, indent=2, sort_keys=True))
    if not launched:
        return 0
    return measurement_exit(missed, payload["score"]["passed"])


def open_path(text):
    return pathlib.Path(text)


if __name__ == "__main__":
    sys.exit(main())
