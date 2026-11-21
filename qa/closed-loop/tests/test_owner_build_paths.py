"""Owner build paths stay the same relative directories when HOME is /Users/example.

Docs name that directory with a placeholder. Scripts and the call probe still append the same
relative suffix to $HOME, so an owner Mac resolves the paths it resolved before.
"""
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[3]


def expand(expression):
    """Expand a bash path expression with HOME set to /Users/example and globbing off."""
    completed = subprocess.run(
        ["bash", "-c", "set -f\nexport HOME=/Users/example\nprintf %s " + expression + "\n"],
        check=True, text=True, capture_output=True)
    return completed.stdout


class OwnerBuildPaths(unittest.TestCase):
    def test_shell_assignments_match_the_historical_absolute_paths(self):
        cases = [
            ("scripts/trusted-ax-journey.sh", 'BUILD_DIR="$HOME/AI-Brain-build/zeus-native-build"',
             "/Users/example/AI-Brain-build/zeus-native-build"),
            ("scripts/trusted-ax-journey.sh", 'RECEIPTS_DIR="$HOME/AI-Brain-build/zeus-trusted-ax"',
             "/Users/example/AI-Brain-build/zeus-trusted-ax"),
            ("scripts/voice-selftest.sh", 'DIR="$HOME/AI-Brain-build/voice-selftest"',
             "/Users/example/AI-Brain-build/voice-selftest"),
            ("scripts/human-qa.sh", 'BASE="$HOME/AI-Brain-build/zeus-human-qa"',
             "/Users/example/AI-Brain-build/zeus-human-qa"),
            ("scripts/human-qa.sh", 'CACHE="$HOME/AI-Brain-build/zeus-human-qa/.cache"',
             "/Users/example/AI-Brain-build/zeus-human-qa/.cache"),
            ("scripts/pointing-selftest.sh", '"$HOME"/AI-Brain-build/zeus-qa-*/app*/Zeus.app',
             "/Users/example/AI-Brain-build/zeus-qa-*/app*/Zeus.app"),
            ("scripts/voice-selftest.sh", '"$HOME"/AI-Brain-build/zeus-qa-*/app*/Zeus.app',
             "/Users/example/AI-Brain-build/zeus-qa-*/app*/Zeus.app"),
        ]
        for relative, expression, historical in cases:
            text = (ROOT / relative).read_text()
            self.assertIn(expression, text, relative)
            self.assertEqual(expand(expression if expression.startswith('"') else expression.split("=", 1)[1]), historical)

    def test_trusted_journey_passes_those_directories_to_the_runner(self):
        text = (ROOT / "scripts/trusted-ax-journey.sh").read_text()
        self.assertIn('exec python3 qa/closed-loop/trusted_ax.py --build-dir "$BUILD_DIR" --receipts "$RECEIPTS_DIR"', text)

    def test_trusted_ax_defaults_equal_the_swift_build_paths(self):
        """The Python defaults are $HOME-relative and equal the directories the Swift build script uses."""
        runner = (ROOT / "qa/closed-loop/trusted_ax.py").read_text()
        self.assertIn("os.path.expanduser('~/AI-Brain-build/zeus-native-build')", runner)
        self.assertIn("os.path.expanduser('~/AI-Brain-build/zeus-trusted-ax')", runner)
        env = dict(**{k: v for k, v in __import__("os").environ.items()}, HOME="/Users/example")
        completed = subprocess.run(
            [__import__("sys").executable, "-c",
             "import trusted_ax\n"
             "args = trusted_ax.build_parser().parse_args([])\n"
             "print(args.build_dir)\n"
             "print(args.receipts)\n"],
            cwd=ROOT / "qa/closed-loop", env=env, text=True, capture_output=True, check=True)
        build, receipts = completed.stdout.splitlines()
        self.assertEqual(build, "/Users/example/AI-Brain-build/zeus-native-build")
        self.assertEqual(receipts, "/Users/example/AI-Brain-build/zeus-trusted-ax")
        self.assertEqual(build, expand('"$HOME/AI-Brain-build/zeus-native-build"'))
        self.assertEqual(receipts, expand('"$HOME/AI-Brain-build/zeus-trusted-ax"'))

    def test_swift_suffixes_join_to_the_historical_absolute_paths(self):
        home = (ROOT / "Sources/Zeus/Voice/LocalHome.swift").read_text()
        self.assertIn('getenv("HOME")', home)
        self.assertIn("NSHomeDirectory()", home)
        probe = (ROOT / "scripts/call-ax-probe.swift").read_text()
        self.assertIn("func localHomePath()", probe)
        self.assertIn('getenv("HOME")', probe)
        self.assertIn("NSHomeDirectory()", probe)
        expected = {
            "Sources/Zeus/Voice/KokoroWorker.swift": [
                ("AI-Brain-build/jarvis-laya-backend/models",
                 "/Users/example/AI-Brain-build/jarvis-laya-backend/models"),
                ("AI-Brain-build/jarvis-laya-backend/.venv/bin/python",
                 "/Users/example/AI-Brain-build/jarvis-laya-backend/.venv/bin/python"),
            ],
            "Sources/Zeus/Voice/VoiceSelfTest.swift": [
                ("AI-Brain-build/voice-selftest/receipt-",
                 "/Users/example/AI-Brain-build/voice-selftest/receipt-"),
            ],
            "scripts/call-ax-probe.swift": [
                ("AI-Brain-build/call-ax-probe/",
                 "/Users/example/AI-Brain-build/call-ax-probe/"),
            ],
        }
        for relative, rows in expected.items():
            text = (ROOT / relative).read_text()
            needle = "localHomePath()" if relative.startswith("scripts/") else "LocalHome.appending"
            self.assertIn(needle, text, relative)
            for suffix, historical in rows:
                self.assertIn(suffix, text, relative)
                self.assertEqual(expand(f'"$HOME/{suffix}"'), historical)


if __name__ == "__main__":
    unittest.main()
