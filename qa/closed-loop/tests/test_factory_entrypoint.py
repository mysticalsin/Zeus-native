import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]


class FactoryEntrypointTests(unittest.TestCase):
    """Exercise the real shell adapter with a disposable runner, never the full CI suite."""

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="zeus-factory-entrypoint-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.checkout = self.base / "checkout with spaces"
        self.wrapper = self.checkout / "tools/check.sh"
        self.wrapper.parent.mkdir(parents=True)
        shutil.copy2(ROOT / "tools/check.sh", self.wrapper)
        self.caller = self.base / "unrelated working directory"
        self.caller.mkdir()
        runner = self.checkout / "qa/closed-loop/run.py"
        runner.parent.mkdir(parents=True)
        runner.write_text('''import argparse, json, os, pathlib, sys
parser = argparse.ArgumentParser()
parser.add_argument("--mode", required=True, choices=("development", "full"))
parser.add_argument("--output", required=True, type=pathlib.Path)
parser.add_argument("--jobs", type=int, default=4)
parser.add_argument("--timeout", type=int, default=1800)
args = parser.parse_args()
if args.jobs < 1 or args.timeout < 1:
    parser.error("jobs and timeout must be positive")
args.output.mkdir(parents=True, exist_ok=False)
(args.output / "invocation.json").write_text(json.dumps({"argv": sys.argv[1:], "cwd": os.getcwd()}))
print("synthetic runner executed")
raise SystemExit(int(os.environ.get("ZEUS_TEST_RUNNER_EXIT", "0")))
''')

    def run_wrapper(self, *arguments, code=0, invocation="sh"):
        environment = dict(os.environ, ZEUS_TEST_RUNNER_EXIT=str(code))
        command = [str(self.wrapper)] if invocation == "direct" else ["/bin/" + invocation, str(self.wrapper)]
        return subprocess.run([*command, *map(str, arguments)], cwd=self.caller,
                              env=environment, capture_output=True, text=True, timeout=5)

    def automatic_receipt(self, result, mode):
        prefix = "Zeus " + mode + " evidence: "
        lines = [line for line in result.stdout.splitlines() if line.startswith(prefix)]
        self.assertEqual(len(lines), 1, result.stdout + result.stderr)
        output = Path(lines[0][len(prefix):])
        self.addCleanup(shutil.rmtree, output.parent, True)
        self.assertTrue(output.is_absolute())
        self.assertFalse(output.resolve().is_relative_to(self.checkout.resolve()))
        self.assertFalse(output.resolve().is_relative_to(self.caller.resolve()))
        self.assertEqual(output.name, "result")
        return output, json.loads((output / "invocation.json").read_text())

    def test_no_argument_direct_and_bash_calls_run_development_with_fresh_external_evidence(self):
        outputs = []
        for invocation in ("direct", "bash"):
            result = self.run_wrapper(invocation=invocation)
            self.assertEqual(result.returncode, 0, result.stderr)
            output, observed = self.automatic_receipt(result, "development")
            outputs.append(output)
            self.assertEqual(observed["argv"], ["--mode", "development", "--output", str(output)])
        self.assertNotEqual(outputs[0], outputs[1])

    def test_explicit_mode_full_keeps_automatic_failure_evidence_and_exit(self):
        result = self.run_wrapper("--mode", "full", code=29)
        self.assertEqual(result.returncode, 29)
        output, observed = self.automatic_receipt(result, "full")
        self.assertEqual(observed["argv"], ["--mode", "full", "--output", str(output)])
        self.assertTrue(output.is_dir())

    def test_outside_checkout_arguments_and_caller_relative_output_are_preserved(self):
        output = Path("fresh relative evidence")
        result = self.run_wrapper("development", "--output", output, "--jobs", "2", "--timeout", "17")
        self.assertEqual(result.returncode, 0, result.stderr)
        observed = json.loads((self.caller / output / "invocation.json").read_text())
        self.assertEqual(observed["argv"], ["--mode", "development", "--output", str(output), "--jobs", "2", "--timeout", "17"])
        self.assertEqual(Path(observed["cwd"]).resolve(), self.caller.resolve())
        self.assertFalse((self.checkout / output).exists())

    def test_full_mode_failure_exit_is_not_hidden_or_downgraded(self):
        output = self.base / "failed-full-evidence"
        result = self.run_wrapper("full", "--output", output, code=73)
        self.assertEqual(result.returncode, 73)
        observed = json.loads((output / "invocation.json").read_text())
        self.assertEqual(observed["argv"][:2], ["--mode", "full"])
        self.assertNotIn("PASS", result.stdout)

    def test_existing_external_evidence_is_not_overwritten(self):
        output = self.base / "external-evidence"
        first = self.run_wrapper("development", "--output", output)
        self.assertEqual(first.returncode, 0, first.stderr)
        receipt = (output / "invocation.json").read_bytes()
        second = self.run_wrapper("development", "--output", output)
        self.assertNotEqual(second.returncode, 0)
        self.assertEqual((output / "invocation.json").read_bytes(), receipt)

    def test_unsupported_missing_duplicate_or_mode_override_arguments_never_run(self):
        output = self.base / "must-not-exist"
        cases = [("unknown", "--output", output), ("--mode",), ("--mode", "unknown"),
                 ("development", "--output"), ("development", "--output", ""),
                 ("full", "--output", output, "--mode", "development"),
                 ("--mode", "full", "--output", output, "--mode", "development"),
                 ("development", "--output", output, "--allow-missing", "true"),
                 ("development", "--output", output, "--output", output),
                 ("development", "--output", output, "--jobs", "1", "--jobs", "2"),
                 ("development", "--output", output, "--timeout", "1", "--timeout", "2")]
        for arguments in cases:
            with self.subTest(arguments=arguments):
                result = self.run_wrapper(*arguments)
                self.assertEqual(result.returncode, 2)
                self.assertFalse(output.exists())
                self.assertNotIn("synthetic runner executed", result.stdout)

    def test_invalid_counts_and_timeouts_are_rejected_before_runner_dispatch(self):
        output = self.base / "must-not-exist"
        for option in ("--jobs", "--timeout"):
            for value in ("0", "000", "-1", "1.5", "many", ""):
                with self.subTest(option=option, value=value):
                    result = self.run_wrapper("development", "--output", output, option, value)
                    self.assertEqual(result.returncode, 2)
                    self.assertFalse(output.exists())

    def test_shell_metacharacters_in_a_path_remain_literal(self):
        output = self.base / "evidence; $(touch injected-marker)"
        result = self.run_wrapper("development", "--output", output)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((output / "invocation.json").is_file())
        self.assertFalse((self.caller / "injected-marker").exists())

    def test_help_is_read_only_and_never_dispatches(self):
        result = self.run_wrapper("--help")
        self.assertEqual(result.returncode, 0)
        self.assertIn("development|full", result.stdout)
        self.assertNotIn("synthetic runner executed", result.stdout)
        self.assertEqual(list(self.caller.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
