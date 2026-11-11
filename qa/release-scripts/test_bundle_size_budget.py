"""Install-size budget (docs/LANGUAGE-PACKS.md, Lean install): the app stays light because language packs
install after the app and release binaries are stripped."""
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SCRIPT = REPO / "scripts/check-bundle-size.sh"


def run(app: Path, budget: int):
    return subprocess.run(["bash", str(SCRIPT), str(app)], text=True, capture_output=True,
                          env=dict(os.environ, BUDGET_MB=str(budget)))


class BundleSizeBudget(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="zeus-size-")
        self.addCleanup(self.temp.cleanup)
        self.app = Path(self.temp.name) / "Zeus.app"
        (self.app / "Contents/MacOS").mkdir(parents=True)
        (self.app / "Contents/MacOS/Zeus").write_bytes(b"\0" * (3 * 1024 * 1024))

    def test_app_under_budget_passes(self):
        result = run(self.app, 10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("budget 10 MB", result.stdout)

    def test_app_over_budget_fails(self):
        result = run(self.app, 2)
        self.assertEqual(result.returncode, 1)
        self.assertIn("install size", result.stdout)

    def test_missing_app_is_an_error_not_a_pass(self):
        self.assertEqual(run(Path(self.temp.name) / "missing.app", 10).returncode, 2)

    def test_default_budget_is_the_lean_target(self):
        text = SCRIPT.read_text()
        self.assertIn('BUDGET_MB="${BUDGET_MB:-150}"', text)


if __name__ == "__main__":
    unittest.main()
