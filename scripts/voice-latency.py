#!/usr/bin/env python3
"""Reads `voice-latency` lines (written by Zeus into voice.log) and prints a per-turn table plus p50 and p90.

Used by scripts/voice-latency.sh. The lines hold stage times in milliseconds since key-up, engine names and
a short reason. They never hold the transcript, the answer or a key.

    voice-latency.py --file PATH            analyse a log file and exit
    some-command | voice-latency.py --live  print each turn as it arrives; summary on Ctrl-C or end of input
"""
import argparse
import re
import sys

STAGES = ["transcript", "request", "first_token", "first_sentence", "tts_request", "first_audio", "turn_end"]
PAIR = re.compile(r'(\w+)=("[^"]*"|\S+)')
LINE = re.compile(r"voice-latency\s+(.*)$")
STAMP = re.compile(r"^(\d{4}-\d{2}-\d{2}T(\d{2}:\d{2}:\d{2}))")
# Targets from docs/VOICE-LATENCY.md: key-up to first audio.
TARGET_API_MS = 1200
TARGET_CLI_MS = 2500


def parse(line):
    """One log line to a dict, or None when it is not a voice-latency line."""
    match = LINE.search(line)
    if not match:
        return None
    row = {}
    for key, value in PAIR.findall(match.group(1)):
        row[key] = value.strip('"')
    if "turn" not in row:
        return None
    stamp = STAMP.match(line)
    row["at"] = stamp.group(2) if stamp else "-"
    return row


def number(row, key):
    value = row.get(key, "-")
    return int(value) if value.lstrip("-").isdigit() and value != "-" else None


def percentile(values, fraction):
    """Linear interpolation between ranks. None for an empty list."""
    if not values:
        return None
    ordered = sorted(values)
    position = (len(ordered) - 1) * fraction
    low = int(position)
    high = min(low + 1, len(ordered) - 1)
    return ordered[low] + (ordered[high] - ordered[low]) * (position - low)


def cell(value, width):
    return ("-" if value is None else str(value)).rjust(width)


HEADER = ["time", "turn", "ttfa", "transc", "request", "1st_tok", "1st_sen", "tts_req", "1st_aud", "end", "brain", "tts"]


def format_row(row):
    brain = row.get("brain", "-")
    model = row.get("model", "-")
    tts = row.get("tts", "-")
    cells = [row.get("at", "-").ljust(8), row.get("turn", "-").ljust(8), cell(number(row, "ttfa"), 5)]
    cells += [cell(number(row, key), 7) for key in STAGES]
    cells += [f"{brain}/{model}".ljust(34), tts]
    return " ".join(cells)


def header_line():
    widths = [8, 8, 5] + [7] * len(STAGES)
    names = HEADER[:3 + len(STAGES)]
    head = " ".join(name.ljust(width) if index < 2 else name.rjust(width) for index, (name, width) in enumerate(zip(names, widths)))
    return head + " " + "brain/model".ljust(34) + " tts"


def summary(rows):
    ttfa = [v for v in (number(r, "ttfa") for r in rows) if v is not None]
    first_token = [v for v in (number(r, "first_token") for r in rows) if v is not None]
    out = [f"turns: {len(rows)}  with audio: {len(ttfa)}"]
    for name, values in (("key-up -> first audio", ttfa), ("key-up -> first token", first_token)):
        if values:
            p50, p90 = percentile(values, 0.5), percentile(values, 0.9)
            out.append(f"{name}: p50 {p50:.0f} ms  p90 {p90:.0f} ms  (n={len(values)})")
        else:
            out.append(f"{name}: no data yet")
    if ttfa:
        p50 = percentile(ttfa, 0.5)
        timed = [r for r in rows if number(r, "ttfa") is not None]
        api = [r for r in timed if r.get("brain", "").startswith(("anthropic", "openai"))]
        target = TARGET_API_MS if timed and len(api) == len(timed) else TARGET_CLI_MS
        out.append(f"target p50 for this route: {target} ms -> {'PASS' if p50 <= target else 'ABOVE TARGET'}")
    return "\n".join(out)


def run(stream, live):
    rows = []
    print(header_line())
    try:
        for line in stream:
            row = parse(line)
            if row is None:
                continue
            rows.append(row)
            print(format_row(row), flush=True)
    except KeyboardInterrupt:
        pass
    print()
    print(summary(rows))
    return rows


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--file", help="analyse this log file and exit")
    parser.add_argument("--last", type=int, default=0, help="only the last N turns")
    parser.add_argument("--live", action="store_true", help="read lines from stdin as they arrive")
    args = parser.parse_args(argv)
    if args.file:
        with open(args.file, encoding="utf-8", errors="replace") as handle:
            lines = handle.readlines()
        parsed = [line for line in lines if parse(line)]
        if args.last > 0:
            parsed = parsed[-args.last:]
        run(parsed, live=False)
        return 0
    run(sys.stdin, live=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
