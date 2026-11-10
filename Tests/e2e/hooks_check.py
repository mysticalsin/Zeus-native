"""Compares a settings.json after ZEUS's install with the original: other hooks and settings
must be untouched and ZEUS must appear exactly once per event."""
import json, sys

MARK = "Zeus/bin/zeus-hook"
original, installed = (json.load(open(path)) for path in sys.argv[1:3])

def without_zeus(hooks):
    result = {}
    for event, entries in hooks.items():
        kept = []
        for entry in entries:
            handlers = [h for h in entry.get("hooks", []) if MARK not in h.get("command", "")]
            if handlers:
                kept.append({**entry, "hooks": handlers})
        if kept:
            result[event] = kept
    return result

counts = {event: sum(MARK in h.get("command", "") for e in entries for h in e.get("hooks", []))
          for event, entries in installed.get("hooks", {}).items()}
ok = (without_zeus(installed.get("hooks", {})) == original.get("hooks", {})
      and {k: v for k, v in installed.items() if k != "hooks"} == {k: v for k, v in original.items() if k != "hooks"}
      and sorted(e for e, c in counts.items() if c) == sorted(["SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest", "Stop", "SessionEnd"])
      and all(c <= 1 for c in counts.values()))
print("MERGE_OK" if ok else f"MERGE_BAD {counts}")
