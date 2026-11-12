#!/usr/bin/env python3
"""First explicit target launch on a fresh CI runner; diagnostic evidence only.

The Homebrew driver never executes/resolves an Apple target before measurement.
Popen itself cannot be interrupted safely by this driver; the workflow caps the
measurement step and whole job. Request expiry is never replaced by cleanup success.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import selectors
import subprocess
import sys
import time

XCODE = "/Applications/Xcode_26.3.app/Contents/Developer"
TARGETS = {"system-launcher": "/usr/bin/python3", "xcode-direct": XCODE + "/usr/bin/python3"}
MARKER = b"ZEUS_PYTHON_ENTRY_V1\n"
CODE = "import os; os.write(1, b'ZEUS_PYTHON_ENTRY_V1\\n')"
REQUEST_NS = 3_000_000_000
STREAM_LIMIT = 4096


def write_json(path: Path, value: dict) -> None:
    temporary = path.with_suffix(path.suffix + ".partial")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    temporary.replace(path)


class Capture:
    def __init__(self, limit: int):
        self.limit = limit
        self.data = {"stdout": bytearray(), "stderr": bytearray()}
        self.count = {"stdout": 0, "stderr": 0}
        self.marker_ns = None
        self.exceeded = False

    def accept(self, stream: str, data: bytes, observed_ns: int) -> None:
        self.count[stream] += len(data)
        remaining = max(0, self.limit - len(self.data[stream]))
        self.data[stream].extend(data[:remaining])
        self.exceeded |= self.count[stream] > self.limit
        if self.marker_ns is None and self.data["stdout"].startswith(MARKER):
            self.marker_ns = observed_ns

    def metadata(self) -> dict:
        return {name: {"bytes_observed": self.count[name], "bytes_retained": len(data),
                       "retained_sha256": hashlib.sha256(data).hexdigest(),
                       "truncated": self.count[name] > len(data)} for name, data in self.data.items()}


class PipeReader:
    def __init__(self, process):
        self.selector = selectors.DefaultSelector()
        try:
            for name in ("stdout", "stderr"):
                handle = getattr(process, name)
                os.set_blocking(handle.fileno(), False)
                self.selector.register(handle, selectors.EVENT_READ, name)
        except BaseException:
            self.selector.close()
            raise

    @property
    def finished(self):
        return not self.selector.get_map()

    def read(self, timeout):
        result = []
        for key, _ in self.selector.select(timeout):
            try:
                data = os.read(key.fd, 4096)
            except BlockingIOError:
                continue
            if not data:
                self.selector.unregister(key.fileobj)
            else:
                result.append((key.data, data))
        return result

    def close(self):
        self.selector.close()


def cleanup(process, clock) -> dict:
    result = {"term_sent": False, "kill_sent": False, "reaped": False}
    if process.poll() is None:
        try:
            process.terminate()
            result["term_sent"] = True
        except ProcessLookupError:
            pass
        try:
            process.wait(timeout=0.5)
        except subprocess.TimeoutExpired:
            try:
                process.kill()
                result["kill_sent"] = True
            except ProcessLookupError:
                pass
    try:
        result["exit_code"] = process.wait(timeout=1)
        result["reaped"] = True
        result["reaped_observed_ns"] = clock()
    except subprocess.TimeoutExpired:
        result["exit_code"] = None
        result["reaped_observed_ns"] = None
    finally:
        # Never drain descendant-owned pipes after failure; close only our ends.
        for name in ("stdout", "stderr"):
            handle = getattr(process, name, None)
            if handle is not None:
                handle.close()
    return result


def observe(command, *, environment, timeout_ns=REQUEST_NS, require_marker=True,
            limit=STREAM_LIMIT, spawn=subprocess.Popen, clock=time.monotonic_ns,
            reader_factory=PipeReader):
    capture = Capture(limit)
    result = {"command": command, "request_deadline_seconds": timeout_ns / 1e9,
              "status": "incomplete", "failure": None, "spawn_return_ns": None,
              "entry_observed_ns": None, "exit_observed_ns": None}
    process = reader = None
    begin = clock()
    result["spawn_begin_ns"] = begin
    deadline = begin + timeout_ns
    try:
        process = spawn(command, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE, env=environment, close_fds=True)
        result["spawn_return_ns"] = clock()
        # Spawn time belongs to the same original deadline, including late success.
        if result["spawn_return_ns"] >= deadline:
            result["failure"] = "spawn-returned-after-deadline"
        else:
            reader = reader_factory(process)
            while True:
                now = clock()
                if now >= deadline:
                    result["failure"] = "request-deadline"
                    break
                code = process.poll()
                observed = clock()
                if code is not None and result["exit_observed_ns"] is None:
                    result["exit_observed_ns"] = observed
                # Even a normally nonblocking poll can cross the absolute deadline
                # if this driver is descheduled. Timestamp after the observation.
                if observed >= deadline:
                    result["failure"] = "request-deadline"
                    break
                if code is not None and reader.finished:
                    break
                chunks = reader.read(min(0.02, (deadline - observed) / 1e9))
                observed = clock()
                if observed >= deadline:
                    result["failure"] = "request-deadline"
                    break
                for stream, data in chunks:
                    capture.accept(stream, data, observed)
                if capture.exceeded:
                    result["failure"] = "output-limit"
                    break
    except OSError as error:
        result["failure"] = "spawn-or-io-error"
        result["error_type"] = type(error).__name__
        result["error_errno"] = error.errno
    finally:
        if reader is not None:
            reader.close()
        if process is not None:
            result["cleanup"] = cleanup(process, clock)
        else:
            result["cleanup"] = {"term_sent": False, "kill_sent": False, "reaped": False,
                                 "exit_code": None, "reaped_observed_ns": None}
    result["entry_observed_ns"] = capture.marker_ns if require_marker else None
    if result["exit_observed_ns"] is None:
        result["exit_observed_ns"] = result["cleanup"]["reaped_observed_ns"]
    result["streams"] = capture.metadata()
    for name, absolute in (("spawn", result["spawn_return_ns"]), ("entry", result["entry_observed_ns"]),
                           ("exit", result["exit_observed_ns"])):
        result[name + "_observed_seconds"] = None if absolute is None else (absolute - begin) / 1e9
    result["entry_by_two_seconds"] = capture.marker_ns is not None and capture.marker_ns - begin <= 2_000_000_000
    if result["failure"] is None:
        if not result["cleanup"]["reaped"]:
            result["failure"] = "child-not-reaped"
        elif result["cleanup"]["exit_code"] != 0:
            result["failure"] = "nonzero-exit"
        elif require_marker and bytes(capture.data["stdout"]) != MARKER:
            result["failure"] = "missing-or-unexpected-marker"
    result["status"] = "passed" if result["failure"] is None else "failed"
    return result, capture


def actual_driver_path() -> str:
    if sys.platform != "darwin":
        raise RuntimeError("macOS-required")
    # Public own-PID API verifies the actual executable, not a spoofable argv[0].
    import ctypes
    library = ctypes.CDLL("/usr/lib/libproc.dylib", use_errno=True)
    library.proc_pidpath.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_uint32]
    library.proc_pidpath.restype = ctypes.c_int
    buffer = ctypes.create_string_buffer(4096)
    if library.proc_pidpath(os.getpid(), buffer, len(buffer)) <= 0:
        raise RuntimeError("driver-path-unavailable")
    actual = os.path.realpath(os.fsdecode(buffer.value))
    if not actual.startswith("/opt/homebrew/") or actual in TARGETS.values():
        raise RuntimeError("driver-is-not-independent-homebrew-python")
    return actual


def child_environment():
    # No credential variables, Python customization, models or network commands.
    environment = {key: os.environ[key] for key in ("HOME", "TMPDIR", "USER", "LOGNAME") if key in os.environ}
    environment.update(PATH="/usr/bin:/bin:/usr/sbin:/sbin", LANG="C", LC_ALL="C", DEVELOPER_DIR=XCODE)
    return environment


def path_metadata(path: str) -> dict:
    result = {"path": path}
    try:
        result["resolved_path"] = os.path.realpath(path)
        result["is_symlink"] = os.path.islink(path)
        result["size_bytes"] = os.stat(path).st_size
        if result["size_bytes"] > 64 * 1024 * 1024:
            result["hash_status"] = "size-limit"
        else:
            digest = hashlib.sha256()
            remaining = 64 * 1024 * 1024
            with open(path, "rb") as source:
                while remaining:
                    block = source.read(min(1024 * 1024, remaining))
                    if not block:
                        break
                    digest.update(block); remaining -= len(block)
                grew_past_limit = bool(source.read(1)) if remaining == 0 else False
            result.update(hash_status="size-limit" if grew_past_limit else "complete")
            if not grew_past_limit:
                result["sha256"] = digest.hexdigest()
    except OSError as error:
        result.update(error_type=type(error).__name__, error_errno=error.errno)
    return result


def post_measurement_metadata(driver: str, environment: dict, expected_revision: str | None) -> dict:
    # Nothing here runs before the one measured target attempt.
    script = Path(__file__).resolve()
    repository = script.parent.parent
    commands = [["/usr/bin/xcrun", "--find", "python3"], ["/usr/bin/xcode-select", "--print-path"],
                ["/usr/bin/otool", "-L", TARGETS["system-launcher"]],
                ["/usr/bin/otool", "-L", TARGETS["xcode-direct"]],
                ["/usr/bin/nm", "-u", TARGETS["system-launcher"]],
                ["/usr/bin/git", "-C", str(repository), "rev-parse", "HEAD"]]
    results = []
    for command in commands:
        result, capture = observe(command, environment=environment, require_marker=False, limit=8192)
        # These fixed commands report executable paths/linkage only. No raw target
        # stdout/stderr is ever included in artifacts or logs.
        text = bytes(capture.data["stdout"]).decode("utf-8", errors="replace")
        if command[0] == "/usr/bin/nm":
            text = "\n".join(line for line in text.splitlines() if "xcselect" in line.lower())
        result["metadata_lines"] = ["".join(c if c.isprintable() else " " for c in line)[:512]
                                    for line in text.splitlines()[:64]]
        results.append(result)
    expected_selection = [TARGETS["xcode-direct"], XCODE]
    selection_verified = all(result["status"] == "passed" and result["metadata_lines"] == [expected]
                             for result, expected in zip(results[:2], expected_selection))
    revision_verified = (expected_revision is not None and results[-1]["status"] == "passed"
                         and results[-1]["metadata_lines"] == [expected_revision])
    workflow = repository / ".github/workflows/python-launch-diagnostic.yml"
    return {"collected_after_measurement": True, "selection_verified": selection_verified,
            "revision_verified": revision_verified,
            "revision_status": "verified" if revision_verified else "unavailable-or-mismatched",
            "selection_status": "verified" if selection_verified else "unavailable-or-mismatched",
            "commands": results,
            "files": [path_metadata(path) for path in [*TARGETS.values(), driver, str(script), str(workflow)]]}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--variant", choices=TARGETS)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args(argv)
    if args.self_test:
        return self_test()
    if args.variant is None or args.output is None:
        parser.error("--variant and --output are required")
    args.output.mkdir(parents=True, exist_ok=True)
    def revision(variable):
        value = os.environ.get(variable, "")
        return value.lower() if len(value) == 40 and all(c in "0123456789abcdef" for c in value.lower()) else None
    def identifier(variable):
        value = os.environ.get(variable, "")
        return value if 0 < len(value) <= 20 and value.isascii() and value.isdecimal() else None
    result = {"schema_version": 1, "diagnostic_only": True, "tested_revision": revision("GITHUB_SHA"),
              "head_revision": revision("ZEUS_DIAGNOSTIC_HEAD_SHA"),
              "run_id": identifier("GITHUB_RUN_ID"), "run_attempt": identifier("GITHUB_RUN_ATTEMPT"),
              "variant": args.variant,
              "target_literal": TARGETS[args.variant], "status": "incomplete", "attempts": 0,
              "claim": "Parent-observed fixed marker and exit only; does not replace Kokoro tests or prove product performance.",
              "cold_scope": "First explicit target launch by this workflow on a fresh hosted runner; runner-image bootstrap history is unknown.",
              "outer_limit": "OS spawn is noninterruptible here; the workflow separately caps this step and job.",
              "cleanup_scope": "Own direct Popen child only; parent pipe ends close without draining. Descendant termination is not proved."}
    write_json(args.output / "measurement.json", result)
    with (args.output / "events.jsonl").open("w", encoding="utf-8") as events:
        def event(phase):
            row = {"phase": phase, "parent_monotonic_ns": time.monotonic_ns()}
            events.write(json.dumps(row) + "\n"); events.flush()
            print(json.dumps(row), flush=True)
        try:
            result["driver_actual_executable"] = actual_driver_path()
        except (RuntimeError, OSError) as error:
            codes = {"macOS-required", "driver-path-unavailable", "driver-is-not-independent-homebrew-python"}
            reason = str(error) if str(error) in codes else "driver-inspection-error"
            result.update(status="failed", failure="driver-precondition", error_type=type(error).__name__, error_code=reason)
            write_json(args.output / "measurement.json", result)
            event("driver-precondition-failed")
            return 1
        environment = child_environment()
        event("before-first-target-spawn")
        result["attempts"] = 1
        write_json(args.output / "measurement.json", result)
        measurement, _ = observe([TARGETS[args.variant], "-I", "-S", "-c", CODE], environment=environment)
        result.update(measurement)
        write_json(args.output / "measurement.json", result)
        event("measurement-finished")
        metadata = post_measurement_metadata(result["driver_actual_executable"], environment, result["tested_revision"])
        write_json(args.output / "metadata.json", metadata)
        metadata_ok = metadata["selection_verified"] and metadata["revision_verified"]
        metadata_ok &= all(item["status"] == "passed" for item in metadata["commands"])
        metadata_ok &= all(item.get("hash_status") == "complete" for item in metadata["files"])
        result["metadata_status"] = "passed" if metadata_ok else "failed"
        result["driver_status"] = "passed" if result["status"] == "passed" and metadata_ok else "failed"
        write_json(args.output / "measurement.json", result)
        event("post-measurement-metadata-finished")
    return 0 if result["driver_status"] == "passed" else 1


def self_test():
    import unittest

    class Clock:
        now = 0
        def __call__(self): return self.now

    class Handle:
        closed = False
        def close(self): self.closed = True

    class Process:
        def __init__(self, ignore_term=False):
            self.stdout, self.stderr = Handle(), Handle()
            self.code = None; self.ignore_term = ignore_term; self.term = self.kills = 0
        def poll(self): return self.code
        def terminate(self):
            self.term += 1
            if not self.ignore_term: self.code = -15
        def kill(self): self.kills += 1; self.code = -9
        def wait(self, timeout):
            if self.code is None: raise subprocess.TimeoutExpired("owned-fixture", timeout)
            return self.code

    class Reader:
        def __init__(self, process, clock, frames):
            self.process, self.clock, self.frames, self.finished = process, clock, list(frames), False
        def read(self, timeout):
            seconds, chunks, code, finished = self.frames.pop(0)
            self.clock.now = int(seconds * 1e9); self.process.code = code; self.finished = finished
            return chunks
        def close(self): pass

    class Guards(unittest.TestCase):
        def run_fixture(self, frames, *, spawn_seconds=0, ignore_term=False):
            clock, process, calls = Clock(), Process(ignore_term), []
            def spawn(command, **kwargs):
                calls.append(command); clock.now = int(spawn_seconds * 1e9); return process
            result, capture = observe([TARGETS["system-launcher"], "-I", "-S", "-c", CODE],
                environment={}, spawn=spawn, clock=clock,
                reader_factory=lambda p: Reader(p, clock, frames))
            return result, capture, process, calls

        def test_spawn_time_consumes_original_deadline_without_fallback(self):
            result, _, process, calls = self.run_fixture([], spawn_seconds=3.1)
            self.assertEqual(result["failure"], "spawn-returned-after-deadline")
            self.assertEqual(len(calls), 1); self.assertEqual(process.term, 1)
            self.assertTrue(result["cleanup"]["reaped"])

        def test_spawn_failure_keeps_one_attempt_without_a_replacement(self):
            calls = []
            def missing(command, **kwargs):
                calls.append(command)
                raise FileNotFoundError(2, "synthetic missing executable")
            result, _ = observe(["/fixed-missing-fixture"], environment={}, spawn=missing, clock=Clock())
            self.assertEqual(len(calls), 1)
            self.assertEqual(result["failure"], "spawn-or-io-error")
            self.assertEqual(result["error_errno"], 2)
            self.assertFalse(result["cleanup"]["reaped"])
            self.assertNotIn("synthetic missing executable", json.dumps(result))

        def test_marker_fragments_and_exit_share_parent_monotonic_origin(self):
            result, _, _, _ = self.run_fixture([(1.8, [("stdout", MARKER[:8])], None, False),
                (1.9, [("stdout", MARKER[8:])], None, False), (2.9, [], 0, True)])
            self.assertEqual(result["status"], "passed")
            self.assertTrue(result["entry_by_two_seconds"])
            self.assertEqual(result["entry_observed_seconds"], 1.9)
            self.assertEqual(result["exit_observed_seconds"], 2.9)

        def test_entry_after_two_seconds_is_recorded_without_changing_three_second_deadline(self):
            result, _, _, _ = self.run_fixture([(2.1, [("stdout", MARKER)], 0, True)])
            self.assertEqual(result["status"], "passed"); self.assertFalse(result["entry_by_two_seconds"])

        def test_late_exit_zero_cannot_replace_timeout_with_success(self):
            result, _, _, _ = self.run_fixture([(3.1, [("stdout", MARKER)], 0, True)])
            self.assertEqual(result["failure"], "request-deadline")
            self.assertEqual(result["cleanup"]["exit_code"], 0)
            self.assertFalse(result["entry_by_two_seconds"])

        def test_delayed_poll_cannot_backdate_exit_or_pass_after_deadline(self):
            clock, process = Clock(), Process()
            def delayed_poll():
                if process.code == 0:
                    clock.now = 3_100_000_000
                return process.code
            process.poll = delayed_poll
            result, _ = observe(["/fixed-fixture"], environment={}, clock=clock,
                                spawn=lambda *args, **kwargs: process,
                                reader_factory=lambda p: Reader(p, clock, [(2.9, [("stdout", MARKER)], 0, True)]))
            self.assertEqual(result["failure"], "request-deadline")
            self.assertEqual(result["exit_observed_seconds"], 3.1)
            self.assertEqual(result["cleanup"]["exit_code"], 0)

        def test_no_marker_and_unexpected_payload_cannot_pass_or_enter_artifacts(self):
            result, _, _, _ = self.run_fixture([(0.1, [("stdout", b"private-fixture-value")], 0, True)])
            self.assertEqual(result["failure"], "missing-or-unexpected-marker")
            self.assertNotIn("private-fixture-value", json.dumps(result))

        def test_output_budget_and_owned_term_kill_join(self):
            result, capture, process, _ = self.run_fixture([(0.1, [("stderr", b"x" * (STREAM_LIMIT + 1))], None, False)], ignore_term=True)
            self.assertEqual(result["failure"], "output-limit")
            self.assertEqual(len(capture.data["stderr"]), STREAM_LIMIT)
            self.assertEqual((process.term, process.kills), (1, 1))
            self.assertTrue(process.stdout.closed and process.stderr.closed)
            self.assertTrue(result["cleanup"]["reaped"])

        def test_main_preserves_measurement_failure_and_requires_complete_selection_metadata(self):
            import contextlib
            import io
            import tempfile
            from unittest.mock import patch
            for measurement_ok, selection_ok, revision_ok in [(False, True, True), (True, False, True),
                                                               (True, True, False), (True, True, True)]:
                with tempfile.TemporaryDirectory(prefix="zeus-launcher-guard-") as directory:
                    measured = {"status": "passed" if measurement_ok else "failed",
                                "failure": None if measurement_ok else "request-deadline"}
                    metadata = {"selection_verified": selection_ok, "revision_verified": revision_ok,
                                "commands": [{"status": "passed"}],
                                "files": [{"hash_status": "complete"}]}
                    module = sys.modules[__name__]
                    with patch.object(module, "actual_driver_path", return_value="/opt/homebrew/fixture"), \
                         patch.object(module, "observe", return_value=(measured, None)) as attempt, \
                         patch.object(module, "post_measurement_metadata", return_value=metadata), \
                         contextlib.redirect_stdout(io.StringIO()):
                        code = main(["--variant", "xcode-direct", "--output", directory])
                    saved = json.loads((Path(directory) / "measurement.json").read_text())
                    self.assertEqual(code, 0 if measurement_ok and selection_ok and revision_ok else 1)
                    self.assertEqual(saved["status"], measured["status"])
                    self.assertEqual(saved["attempts"], 1)
                    attempt.assert_called_once_with([TARGETS["xcode-direct"], "-I", "-S", "-c", CODE],
                                                    environment=child_environment())

    outcome = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(Guards))
    return 0 if outcome.wasSuccessful() else 1


if __name__ == "__main__":
    raise SystemExit(main())
