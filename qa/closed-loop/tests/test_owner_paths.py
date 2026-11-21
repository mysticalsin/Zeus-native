"""S11-09: runnable defaults must not point at one developer's build tree."""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]

# file -> substring that must not remain as a default location
CHECKS = {
    "scripts/pointing-selftest.sh": "AI-Brain-build",
    "scripts/voice-selftest.sh": "AI-Brain-build",
    "scripts/trusted-ax-journey.sh": "AI-Brain-build",
    "scripts/human-qa.sh": "AI-Brain-build",
    "scripts/silent-eval.sh": "zeus-wt/glance-clone-proof",
    "scripts/check-perf-budget.sh": "zeus-wt/topbar",
    "scripts/call-ax-probe.swift": "AI-Brain-build",
    "qa/closed-loop/trusted_ax.py": "AI-Brain-build",
    "qa/closed-loop/README.md": "AI-Brain-build",
    "Sources/Zeus/Voice/KokoroWorker.swift": "AI-Brain-build",
    "Sources/Zeus/Voice/VoiceSelfTest.swift": "AI-Brain-build",
    "docs/HUMAN-QA.md": "AI-Brain-build",
    "docs/VOICE-PIPELINE.md": "AI-Brain-build",
}


class OwnerPathDefaults(unittest.TestCase):
    def test_defaults_do_not_use_one_home_layout(self):
        hits = []
        for relative, needle in CHECKS.items():
            text = (ROOT / relative).read_text(encoding="utf-8")
            if needle in text:
                hits.append(f"{relative} still contains {needle}")
        self.assertEqual(hits, [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
