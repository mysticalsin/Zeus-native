"""Verifier-owned copy of the companion turn table.

This is not CompanionTurnMachine. S1 owns that file. The end-to-end run fails if the
Swift oracle and this table disagree, and it fails every pair that is not listed.
"""

PHASES = ["idle", "listening", "transcribing", "thinking", "speaking", "interrupted", "error"]

EDGES = [
    ("idle", "key_confirmed", "listening", ["show buddy", "lamp mic on", "arm capture", "start mic"]),
    ("idle", "key_tap_inside_confirm", "idle", []),
    ("idle", "mouse_down_while_arming", "idle", []),
    ("listening", "key_up", "transcribing", ["lamp mic off when the device closes", "commit partial"]),
    ("listening", "double_tap_latch", "listening", ["stay", "arm the silence timer"]),
    ("listening", "silence_timer_on_latch", "transcribing", ["lamp mic off when the device closes", "commit partial"]),
    ("listening", "escape", "idle", ["stop mic", "lamp off", "hide after linger"]),
    ("listening", "capture_denied_at_start", "error", ["speak the short line"]),
    ("transcribing", "partial_committed_instant", "speaking", ["no brain", "no capture wait"]),
    ("transcribing", "partial_committed_needs_brain", "thinking", ["send transcript", "attach capture if it succeeded"]),
    ("transcribing", "empty_partial", "idle", ["no request"]),
    ("transcribing", "recognizer_failure", "error", ["speak the short line"]),
    ("thinking", "first_sentence_ready", "speaking", ["schedule that sentence", "fly if a point tag is already parsed"]),
    ("thinking", "brain_failure", "error", ["speak the short line", "do not invent a screen"]),
    ("thinking", "key_down", "interrupted", ["cancel brain", "cancel speech"]),
    ("speaking", "playback_ended", "idle", ["lamps off", "linger"]),
    ("speaking", "key_down", "interrupted", ["stop speech", "stop flight", "stop capture"]),
    ("speaking", "escape", "interrupted", ["stop speech", "stop flight", "stop capture"]),
    ("interrupted", "cleanup_key_held", "listening", ["start a new mic"]),
    ("interrupted", "cleanup_key_up", "idle", ["linger"]),
    ("error", "line_spoken", "idle", ["lamps off", "pointer cleared"]),
    ("error", "key_down", "listening", ["the line may be cut"]),
    ("any", "sleep_or_display_change", "interrupted", ["discard capture"]),
]


def legal_applications():
    applied = [edge for edge in EDGES if edge[0] != "any"]
    for phase in PHASES:
        for edge in EDGES:
            if edge[0] == "any":
                applied.append((phase, edge[1], edge[2], edge[3]))
    return applied


def events():
    return sorted({edge[1] for edge in EDGES})


def step(phase, event):
    for edge in legal_applications():
        if edge[0] == phase and edge[1] == event:
            return edge
    return None


def illegal_pairs():
    legal = {(edge[0], edge[1]) for edge in legal_applications()}
    return [(phase, event) for phase in PHASES for event in events() if (phase, event) not in legal]


def percentile_30(samples):
    """p50 is the 15th of 30 sorted samples. p95 is the 29th. Both are 1-based."""
    if len(samples) != 30:
        raise ValueError(f"expected 30 samples, got {len(samples)}")
    ordered = sorted(samples)
    return ordered[14], ordered[28]


def dropped(samples, hertz):
    period_ms = 1000.0 / hertz
    limit = 1.5 * period_ms
    return sum(1 for sample in samples if sample > limit), limit
