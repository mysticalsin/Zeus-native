#!/usr/bin/env python3
"""Validator for the pointing self-test receipt (schema_version 1).

The app's exit code alone is not a pass. This reads the receipt itself and requires, for every
required check, either `passed` with the metrics that prove it, or `blocked` with the reason and the
System Settings privacy pane the owner opens. Anything else (failed, missing, a pass with no
evidence, a block with no reason, a stray secret or image) is rejected.

    python3 qa/closed-loop/pointing_receipt.py <receipt.json> [--rc <app exit code>]

Exit: 0 every required check passed; 3 valid, but some required checks are blocked by a permission;
1 invalid or failed.
"""
import json
import re
import sys

REQUIRED = ["lifecycle", "capture", "coordinates", "targeting", "protocol", "rendering", "sync", "interruption", "repeat"]
OPTIONAL = ["resources"]
STATUSES = {"passed", "failed", "blocked", "not-measured"}
PANES = {"Privacy_ScreenCapture", "Privacy_Accessibility", "Privacy_ListenEvent", "Privacy_Microphone"}
SECRET = re.compile(r"sk-[A-Za-z0-9_-]{16,}|xi-api|api[_-]?key|authorization|bearer\s+[A-Za-z0-9]", re.I)
FORBIDDEN_KEYS = {"screenshot", "image", "jpeg", "jpegdata", "pixels", "base64", "transcript", "audio", "prompt", "response"}


def _number(metrics, key):
    value = metrics.get(key)
    return value if isinstance(value, (int, float)) and not isinstance(value, bool) else None


def _scan(value, problems, path="receipt"):
    if isinstance(value, dict):
        for key, inner in value.items():
            if str(key).lower() in FORBIDDEN_KEYS:
                problems.append(f"{path}.{key}: a field that could carry captured content")
            _scan(inner, problems, f"{path}.{key}")
    elif isinstance(value, list):
        for index, inner in enumerate(value):
            _scan(inner, problems, f"{path}[{index}]")
    elif isinstance(value, str):
        if len(value) > 2000:
            problems.append(f"{path}: a string over 2000 characters (blob?)")
        if SECRET.search(value):
            problems.append(f"{path}: looks like a credential")


def _evidence(check_id, metrics):
    """Metrics a passing check must show. Returns problems."""
    out = []
    def need(condition, text):
        if not condition:
            out.append(f"{check_id}: {text}")
    if check_id == "lifecycle":
        states = metrics.get("states")
        need(isinstance(states, str) and all(s in states for s in ("listening", "processing", "speaking")), "no state sequence recorded")
        need(metrics.get("requests_after_spoil") == 0, "spoil must send 0 requests")
        need(metrics.get("input_begins_after_double_hold") == 1, "double hold must start exactly 1 session")
    elif check_id == "capture":
        need(metrics.get("capture_attempts_in_turn") == 1, "exactly 1 capture per turn")
        need(_number(metrics, "image_width") and _number(metrics, "image_height"), "capture dimensions missing")
    elif check_id == "coordinates":
        error = _number(metrics, "max_error_pt")
        need(error is not None and error <= 1, "round-trip error must be measured and <= 1 pt")
        need(isinstance(metrics.get("per_display"), list) and metrics["per_display"], "per-display rows missing")
    elif check_id == "targeting":
        probes = metrics.get("probes")
        need(isinstance(probes, list) and len(probes) >= 2, "two probes expected")
        for probe in probes or []:
            need(probe.get("expected") == probe.get("found"), f"identifier mismatch {probe.get('expected')} vs {probe.get('found')}")
    elif check_id == "protocol":
        need(metrics.get("partial_events_rendered") == 0 and (_number(metrics, "split_cuts") or 0) > 0, "split-chunk probe missing")
        need(metrics.get("malformed_op_rejected") is True, "malformed op rejection missing")
        need(metrics.get("off_image_marks_dropped") == 1, "off-image drop missing")
        need(metrics.get("outside_point_returns_nil") is True, "no-clamp proof missing")
    elif check_id == "rendering":
        error = _number(metrics, "ring_center_error_pt")
        need(error is not None and error <= 4, "ring placement must be measured and <= 4 pt")
        need(metrics.get("clicks_pass_through") is True, "click-through proof missing")
        need(metrics.get("strokes_while_held") == 1, "ink stroke proof missing")
        need(metrics.get("fixture_clicks_while_held") == 0, "a click reached the fixture")
        level = _number(metrics, "overlay_level")
        need(level is not None and level > 101, "overlay level must be above menus")
    elif check_id == "sync":
        lag = _number(metrics, "flight_start_minus_first_audio_ms")
        need(lag is not None and lag >= 0, "flight must start at or after first audio")
    elif check_id == "interruption":
        for key in ("esc_to_stopped_ms", "second_hold_to_stopped_ms"):
            value = _number(metrics, key)
            need(value is not None and value <= 150, f"{key} must be measured and <= 150 ms")
        need(metrics.get("next_turn_completed") is True, "next turn after interruption missing")
        need(metrics.get("microphone_idle") is True, "microphone release proof missing")
    elif check_id == "repeat":
        need(metrics.get("turns") == 3 and metrics.get("completed") == 3, "3 completed turns expected")
        need(metrics.get("windows_before") == metrics.get("windows_after"), "window count changed")
    elif check_id == "resources":
        need(_number(metrics, "max_main_thread_gap_ms") is not None, "main-thread gap missing")
    return out


def validate(receipt, rc=None):
    """Returns (problems, blocked_ids). Empty problems means the receipt is acceptable."""
    problems, blocked = [], []
    if not isinstance(receipt, dict):
        return ["receipt is not a JSON object"], blocked
    if receipt.get("schema_version") != 1:
        problems.append("schema_version must be 1")
    if receipt.get("timed_out"):
        problems.append("the self-test hit its 120 s timeout")
    app = receipt.get("app")
    if not isinstance(app, dict) or not app.get("build_stamp"):
        problems.append("app.build_stamp missing")
    for key in ("macos", "provider_path", "started_at", "finished_at", "mode"):
        if not receipt.get(key):
            problems.append(f"{key} missing")
    displays = receipt.get("displays")
    if not isinstance(displays, list) or not displays or not all(isinstance(d, dict) and "scale" in d and "origin" in d for d in displays):
        problems.append("displays must list each display with scale and origin")
    if not isinstance(receipt.get("inputs"), dict):
        problems.append("inputs (injected vs real) missing")
    _scan(receipt, problems)

    rows = receipt.get("checks")
    if not isinstance(rows, list):
        return problems + ["checks missing"], blocked
    by_id = {}
    for row in rows:
        if not isinstance(row, dict) or "id" not in row:
            problems.append("a check has no id"); continue
        if row["id"] in by_id:
            problems.append(f"{row['id']}: listed twice")
        by_id[row["id"]] = row
    for unknown in sorted(set(by_id) - set(REQUIRED) - set(OPTIONAL)):
        problems.append(f"{unknown}: unknown check")
    for check_id in REQUIRED + OPTIONAL:
        required = check_id in REQUIRED
        row = by_id.get(check_id)
        if row is None:
            problems.append(f"{check_id}: missing from the receipt")
            continue
        status, reason, metrics = row.get("status"), row.get("reason", ""), row.get("metrics")
        if status not in STATUSES:
            problems.append(f"{check_id}: unknown status {status!r}"); continue
        if not isinstance(metrics, dict):
            problems.append(f"{check_id}: metrics must be an object"); continue
        if status == "passed":
            if not metrics:
                problems.append(f"{check_id}: passed with no metrics (a pass needs evidence)")
            else:
                problems += _evidence(check_id, metrics)
        elif status == "blocked":
            if not str(reason).strip():
                problems.append(f"{check_id}: blocked without a reason")
            if row.get("permission_pane") not in PANES:
                problems.append(f"{check_id}: blocked without a System Settings pane (one of {sorted(PANES)})")
            if required:
                blocked.append(check_id)
        elif status == "not-measured":
            if required:
                problems.append(f"{check_id}: a required check cannot be not-measured")
            elif not str(reason).strip():
                problems.append(f"{check_id}: not-measured without a reason")
        else:
            problems.append(f"{check_id}: failed" + (f" ({reason})" if reason else ""))
    if rc is not None and rc == 0 and blocked:
        problems.append("the app exited 0 although checks are blocked")
    return problems, blocked


def table(receipt):
    rows = {r.get("id"): r for r in receipt.get("checks", []) if isinstance(r, dict)}
    lines = [f"{'check':<14}{'status':<14}detail"]
    for check_id in REQUIRED + OPTIONAL:
        row = rows.get(check_id, {})
        detail = str(row.get("reason") or "")
        if not detail:
            metrics = row.get("metrics") or {}
            detail = ", ".join(f"{k}={v}" for k, v in list(metrics.items())[:3] if isinstance(v, (int, float, str, bool)))
        if row.get("permission_pane"):
            detail = f"[{row['permission_pane']}] {detail}"
        lines.append(f"{check_id:<14}{str(row.get('status', 'missing')):<14}{detail[:110]}")
    return "\n".join(lines)


def main(argv):
    if len(argv) < 2:
        print(__doc__); return 64
    rc = int(argv[argv.index("--rc") + 1]) if "--rc" in argv else None
    try:
        with open(argv[1]) as handle:
            receipt = json.load(handle)
    except (OSError, ValueError) as error:
        print(f"cannot read receipt: {error}"); return 1
    problems, blocked = validate(receipt, rc)
    print(table(receipt))
    print(f"provider path: {receipt.get('provider_path')}   mode: {receipt.get('mode')}   app rc: {rc}")
    if problems:
        print("\nREJECTED:")
        for problem in problems:
            print(f"  - {problem}")
        return 1
    if blocked:
        print(f"\nVALID, with permission blocks: {', '.join(blocked)}. Grant the pane(s) above in System Settings and run again for a full pass.")
        return 3
    print("\nPASSED: every required check passed with evidence.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
