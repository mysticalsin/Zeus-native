"""Rate, pitch, and the empty-text check for the Mac AVSpeech render.

UltronSystemVoicePick uses 0.92 of AVSpeechUtteranceDefaultSpeechRate and a pitch
multiplier of 0.82. An empty script is not a render, so the process exits 2.
Linux can run this file. It does not call AVFoundation.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

RATE_SCALE = 0.92
PITCH = 0.82


def exit_code(argument_count: int, text: str) -> int:
    if argument_count != 3:
        return 2
    if not text.strip():
        return 2
    return 0


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv if argv is None else argv)
    if len(args) != 3:
        print("usage: avspeech_plan.py OUTPUT.wav TEXTFILE", file=sys.stderr)
        return 2
    try:
        text = Path(args[2]).read_text(encoding="utf-8")
    except OSError:
        text = ""
    code = exit_code(len(args), text)
    if not text.strip():
        print("empty text", file=sys.stderr)
    print(json.dumps({"exit": code, "rate_scale": RATE_SCALE, "pitch": PITCH}))
    return code


if __name__ == "__main__":
    sys.exit(main())
