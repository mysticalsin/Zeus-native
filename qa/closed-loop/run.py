#!/usr/bin/env python3
"""Run fresh, source-bound Zeus checks. Full mode fails every unproved obligation."""
import argparse
from datetime import datetime, timezone
import importlib.util
import json
import os
from pathlib import Path
import platform
import re
import signal
import subprocess
import sys
import tempfile
import time
import native_evidence as native

from contracts import (ROOT, Invalid, case_passed, digest, evaluate_features, load,
                       manifest_matches, require, source_snapshot, swift_summary, validate_map, validate_registry,
                       validate_native_build)


def portable_module():
    spec = importlib.util.spec_from_file_location("zeus_portable", ROOT / "qa/portable-core/prepare.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT).decode().strip()


def snapshot(output):
    return source_snapshot(ROOT, output)


def save(path, data):
    path.write_text(json.dumps(data, indent=2) + "\n")


def artifact(path, output):
    # The owned root may be an OS alias (/var -> /private/var on macOS).
    # Resolve only that root; child file/directory redirects still fail closed.
    require(not path.is_symlink() and path.resolve() == output.resolve() / path.relative_to(output),
            "artifact escaped output or redirects a child")
    return {"path": str(path.relative_to(output)), "sha256": digest(path.read_bytes())}


def cleanup_owned_command(process, stream):
    """Stop only an unreaped child in the fresh group created by execute.

    Python 3.11 on macOS has no waitid(WNOWAIT). A nonblocking waitpid probe
    therefore admits signaling only while the exact direct child is still
    running. If it was already reaped (including an interrupted poll), group
    identity is no longer reserved: report incomplete cleanup rather than risk
    signaling a reused PID. Descendants that create another group are outside
    this deliberately narrow ownership boundary.
    """
    def unconfirmed(reason):
        stream.write("\nCHECK CLEANUP UNCONFIRMED: " + reason + "\n")
        return False

    # Defer a second cancellation only for this finite cleanup interval. Restore
    # the caller's exact mask after the last signal and bounded direct-child reap.
    old_mask = signal.pthread_sigmask(signal.SIG_BLOCK, {signal.SIGINT, signal.SIGTERM})
    try:
        if signal.getsignal(signal.SIGCHLD) != signal.SIG_DFL:
            return unconfirmed("child reaping policy is not exclusive; no group signal sent")
        if process.returncode is not None:
            return unconfirmed("direct child already reaped; no group signal sent")
        try:
            child, status = os.waitpid(process.pid, os.WNOHANG)
        except ChildProcessError:
            return unconfirmed("direct child ownership unavailable; no group signal sent")
        except OSError as error:
            return unconfirmed(f"child ownership probe failed (errno {error.errno}); no group signal sent")
        if child == process.pid:
            process.returncode = os.waitstatus_to_exitcode(status)
            return unconfirmed("direct child exited before cleanup; no group signal sent")
        if child != 0 or process.pid <= 0 or process.pid == os.getpgrp():
            return unconfirmed("fresh child group could not be established; no group signal sent")
        try:
            if os.getpgid(process.pid) != process.pid:
                return unconfirmed("child left its owned group; no group signal sent")
        except OSError as error:
            return unconfirmed(f"child group probe failed (errno {error.errno}); no group signal sent")

        signal_failed = False

        def send(signum):
            nonlocal signal_failed
            try:
                os.killpg(process.pid, signum)
            except ProcessLookupError:
                pass
            except OSError as error:
                signal_failed = True
                stream.write(f"\nCHECK CLEANUP SIGNAL FAILED: {signum.name} (errno {error.errno})\n")

        reaped = False
        try:
            send(signal.SIGTERM)
            # No poll/wait/reap here: the unreaped leader reserves the group
            # identity even if TERM exits it while a grandchild ignores TERM.
            time.sleep(0.25)
        finally:
            try:
                send(signal.SIGKILL)
            finally:
                try:
                    process.wait(timeout=1)
                    reaped = True
                except subprocess.TimeoutExpired:
                    unconfirmed("direct child did not exit within the cleanup deadline")
                except OSError as error:
                    unconfirmed(f"direct child reap failed (errno {error.errno})")
        if signal_failed:
            return unconfirmed("one or more owned group signals failed")
        return reaped
    finally:
        signal.pthread_sigmask(signal.SIG_SETMASK, old_mask)


def execute(command, log, timeout, environment=None):
    started = time.monotonic()
    with log.open("w") as stream:
        process = None
        try:
            # Auto-reaping or a custom SIGCHLD handler can lose the actual exit
            # status before Popen polls it. Do not launch under that ambiguity.
            if signal.getsignal(signal.SIGCHLD) != signal.SIG_DFL:
                raise OSError("Default SIGCHLD ownership is required for check execution")
            process = subprocess.Popen(command, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT,
                                       start_new_session=True,
                                       env={**os.environ, "NO_COLOR": "1", "PYTHONDONTWRITEBYTECODE": "1", **(environment or {})})
            # Preserve subprocess.run's timeout contract: process creation itself
            # is outside the deadline. A blocked OS spawn is not a bounded claim.
            deadline = time.monotonic() + timeout
            while True:
                code = process.poll()
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise subprocess.TimeoutExpired(command, timeout)
                if code is not None:
                    break
                time.sleep(min(0.01, remaining))
        except subprocess.TimeoutExpired:
            if process is not None:
                cleanup_owned_command(process, stream)
            stream.write(f"\nCHECK TIMEOUT after {timeout} seconds\n")
            code = 124
        except OSError as error:
            if process is not None:
                cleanup_owned_command(process, stream)
            stream.write(f"\nCHECK COULD NOT START: {error}\n")
            code = 127
        except BaseException:
            if process is not None:
                cleanup_owned_command(process, stream)
            raise
    return code, round(time.monotonic() - started, 3)


def python_summary(log, code):
    require(code == 0, f"command exited {code}")
    summaries = re.findall(r"^Ran (\d+) tests? in ", log, re.MULTILINE)
    require(len(summaries) == 1 and int(summaries[0]) > 0, "missing or empty Python test summary")
    require(re.search(r"^OK\s*$", log, re.MULTILINE), "skipped, failed or expected-failure Python suite cannot pass")
    functions = sorted(set(re.findall(r"^(test_\w+) \([^\n]+\) \.\.\. ok$", log, re.MULTILINE)))
    require(len(functions) == int(summaries[0]), "Python cases missing/duplicated/skipped")
    return int(summaries[0]), 1, functions


def compile_native(args, output, source_hash):
    folder = output / "native-build"
    folder.mkdir()
    log = folder / "build.log"
    row = {"status": "failed", "command": [], "exit_code": None,
           "source_snapshot_sha256": source_hash, "artifacts": [], "duration_seconds": 0}
    try:
        require(snapshot(output)["sha256"] == source_hash, "Source changed before the native compiler barrier")
        row["command"] = ["swift", "build", "--build-tests", "--jobs", str(args.jobs)]
        code, seconds = execute(row["command"], log, args.timeout)
        row.update(exit_code=code, duration_seconds=seconds, artifacts=[artifact(log, output)])
        require(code == 0, f"native compiler command exited {code}")
        require(snapshot(output)["sha256"] == source_hash, "Source changed during the native compiler barrier")
        row["status"] = "passed"
        validate_native_build(row, output, source_hash, args.jobs)
    except (Invalid, OSError, ValueError) as error:
        row.update(status="failed", reason=str(error))
        if not log.exists():
            log.write_text(f"NATIVE BUILD NOT EXECUTED: {error}\n")
        row["artifacts"] = [artifact(log, output)]
    return row


def run_checks(definitions, args, output, portable, result):
    native_definitions = [row for row in definitions if row["kind"] in native.NATIVE_KINDS]
    for definition in definitions:
        if definition["kind"] in native.NATIVE_KINDS and args.mode == "full" and platform.system() == "Darwin" and "native_build" not in result:
            result["native_build"] = compile_native(args, output, result["source_snapshot_sha256"])
            if result["native_build"]["status"] == "passed":
                result["native_discovery"] = discover_native(args, output, result["source_snapshot_sha256"], native_definitions)
        result["checks"].append(run_check(definition, args, output, portable, result.get("native_build"),
                                          result.get("native_discovery"), native_definitions))


def discover_native(args, output, source_hash, definitions):
    folder = output / "native-discovery"
    folder.mkdir()
    log = folder / "test.log"
    row = {"status": "failed", "command": [], "exit_code": None, "source_snapshot_sha256": source_hash,
           "artifacts": [], "duration_seconds": 0}
    try:
        require(snapshot(output)["sha256"] == source_hash, "Source changed before native discovery")
        row["command"] = native.discovery_command(str(output))
        code, seconds = execute(row["command"], log, args.timeout)
        row.update(exit_code=code, duration_seconds=seconds)
        row["artifacts"] = [artifact(path, output) for path in (log, folder / "events.jsonl") if path.is_file()]
        row["status"] = "passed"
        native.validate_discovery_receipt(row, output, source_hash, definitions, str(ROOT), str(output))
        require(snapshot(output)["sha256"] == source_hash, "Source changed during native discovery")
    except (Invalid, OSError, ValueError) as error:
        row.update(status="failed", reason=str(error))
        if not log.is_file():
            log.write_text(f"NATIVE DISCOVERY NOT EXECUTED: {error}\n")
        row["artifacts"] = [artifact(path, output) for path in (log, folder / "events.jsonl") if path.is_file()]
    print(f"native-discovery: {row['status']}", flush=True)
    return row


def run_native_check(definition, args, output, native_build, discovery_receipt, all_definitions, selection=None):
    selection = selection or [definition]
    row = {"id": definition["id"], "kind": definition["kind"], "tier": "native-integration", "scope": definition["scope"],
           "status": "not-run", "command": [], "exit_code": None, "tests": 0, "suites": 0,
           "passed_functions": [], "passed_cases": [], "parameter_cases": 0, "artifacts": []}
    if args.mode != "full":
        row["reason"] = "Native checks are separate from portable development; the CI app job still requires them."
        return row
    if platform.system() != "Darwin":
        row.update(status="blocked", reason="Actual production native targets require macOS and Apple SDKs.")
        return row
    try:
        require(native_build is not None, "Native compiler barrier is missing")
        source_hash = snapshot(output)["sha256"]
        validate_native_build(native_build, output, source_hash, args.jobs)
    except (Invalid, OSError, ValueError) as error:
        row.update(status="blocked", blocker="native-build", reason=str(error))
        return row
    try:
        require(discovery_receipt is not None, "Native compiled discovery is missing")
        compiled = native.validate_discovery_receipt(discovery_receipt, output, source_hash, all_definitions, str(ROOT), str(output))
    except (Invalid, OSError, ValueError) as error:
        row.update(status="blocked", blocker="native-discovery", reason=str(error))
        return row
    folder = output / definition["id"]
    folder.mkdir()
    log, events = folder / "test.log", folder / "events.jsonl"
    try:
        row["command"] = native.run_command(selection, args.jobs, str(output), definition["id"], ROOT)
        environment = {"ZEUS_QA_ARTIFACT_DIR": str(folder / "native-artifacts")}
        if native.native_app_host.selected(selection):
            environment.update(native.native_app_host.prepare(output, definition["id"]))
        code, seconds = execute(row["command"], log, args.timeout, environment)
        row.update(exit_code=code, duration_seconds=seconds)
        count, suites, _ = swift_summary(log.read_text(), code)
        metrics = native.execution(events, compiled, selection)
        require((count, suites) == (metrics["tests"], metrics["suites"]), "native text summary differs from qualified execution")
        row.update(metrics, passed_functions=sorted({case["function"] for case in metrics["passed_cases"]}), status="passed")
    except (Invalid, OSError, ValueError, subprocess.SubprocessError) as error:
        row.update(status="failed", reason=str(error))
    for file in [log, events, *sorted((folder / "native-artifacts").rglob("*"))]:
        if file.is_file():
            row["artifacts"].append(artifact(file, output))
    print(f"{row['id']}: {row['status']} ({row['tests']} fully identified tests)", flush=True)
    return row


def run_check(definition, args, output, portable, native_build=None, discovery_receipt=None, all_definitions=None):
    ident, kind = definition["id"], definition["kind"]
    if kind in native.NATIVE_KINDS:
        return run_native_check(definition, args, output, native_build, discovery_receipt, all_definitions or [definition])
    row = {"id": ident, "kind": kind, "tier": definition.get("tier", "contract"),
           "scope": definition["scope"], "status": "not-run", "command": [], "exit_code": None,
           "tests": 0, "suites": 0, "passed_functions": [], "artifacts": []}
    if kind == "unimplemented":
        row.update(status="unimplemented", reason=definition["reason"])
        return row
    folder = output / ident
    folder.mkdir()
    log = folder / "test.log"
    try:
        if kind == "portable":
            package = portable.prepare(folder, definition["group"])
            row["package"] = str(package.relative_to(output))
            command = ["swift", "test", "--package-path", str(package), "--jobs", str(args.jobs)]
        elif kind == "release-mocks":
            command = [sys.executable, "qa/release-scripts/test_release_scripts.py"]
        elif kind == "selftests":
            command = [sys.executable, "-m", "unittest", "discover", "-s", "qa/closed-loop/tests", "-p", "test_*.py", "-v"]
        else:
            raise Invalid("unknown executable checker")
        row["command"] = command
        code, seconds = execute(command, log, args.timeout,
                                {"ZEUS_QA_ARTIFACT_DIR": str(folder / "native-artifacts")})
        row.update(exit_code=code, duration_seconds=seconds)
        count, suites, functions = (python_summary if kind in {"selftests", "release-mocks"} else swift_summary)(log.read_text(), code)
        row.update(tests=count, suites=suites, passed_functions=functions)
        if kind == "portable":
            # Recreate from current repository after execution; catches omission,
            # stale manifests and any edits to the actual compiled source snapshot.
            with tempfile.TemporaryDirectory(prefix="zeus-receipt-verify-") as tmp:
                expected = portable.prepare(Path(tmp), definition["group"])
                manifest_matches(package, expected)
            row["artifacts"].append(artifact(package / "validation-manifest.json", output))
        row["status"] = "passed"
    except (Invalid, OSError, ValueError) as error:
        row.update(status="failed", reason=str(error))
    if log.is_file():
        row["artifacts"].append(artifact(log, output))
    for file in sorted((folder / "native-artifacts").rglob("*")):
        if file.is_file():
            row["artifacts"].append(artifact(file, output))
    print(f"{ident}: {row['status']} ({row['tests']} tests)", flush=True)
    return row


def evaluate_registry(registry, checks, output):
    rows = []
    for entry in registry:
        check = checks[entry["check"]]
        status, reason = check["status"], check.get("reason", "")
        if status == "passed":
            try:
                case_passed(entry["guard"], check, output)
            except (Invalid, OSError, ValueError) as error:
                status, reason = "failed", str(error)
        rows.append({"id": entry["id"], "check": entry["check"], "status": status, "reason": reason})
    return rows


def finish(args, output, result):
    save(output / "result.json", result)
    candidates = [{"check": r["id"], "status": r["status"], "reason": r.get("reason", ""),
                   "tested_sha": result.get("tested_sha"), "source_snapshot_sha256": result.get("source_snapshot_sha256"),
                   "command": r["command"], "artifacts": r["artifacts"],
                   "required_action": "Reproduce, repair, and add a real type/lint/test guard to qa/regressions.json; do not mark this candidate as resolved evidence."}
                  for r in result.get("checks", []) if r["status"] == "failed"]
    if result.get("native_build", {}).get("status") == "failed":
        build = result["native_build"]
        candidates.append({"check": "native-build", "status": "failed", "reason": build.get("reason", ""),
                           "tested_sha": result.get("tested_sha"), "source_snapshot_sha256": build["source_snapshot_sha256"],
                           "command": build["command"], "artifacts": build["artifacts"],
                           "required_action": "Repair the shared compiler failure before rerunning native fixtures; blocked fixtures are not passing evidence."})
    save(output / "regression-candidates.json", {"schema_version": 1, "failures": candidates})
    lines = [f"Zeus {args.mode}: {result['status']}", "", f"Tested SHA: {result.get('tested_sha', 'unknown')}",
             f"Source snapshot: {result.get('source_snapshot_sha256', 'unavailable')}",
             f"Fully accepted checklist items: {sum(f['status'] == 'passed' for f in result.get('features', []))}/19",
             f"Release ready: {str(result.get('release_ready', False)).lower()}", "",
             "Development success establishes only its executed guards. Native fixtures are not device proof.", ""]
    if "native_build" in result:
        lines.extend([f"Native compiler barrier: {result['native_build']['status']}",
                      f"Compiler log: native-build/build.log — {result['native_build'].get('reason', 'current-source compilation completed')}", ""])
    for feature in result.get("features", []):
        lines.append(f"- {feature['id']} {feature['title']}: {feature['status']}")
        lines.extend(f"  - {o['id']}: {o['status']} — {o.get('reason') or o['check']}" for o in feature["obligations"])
    if result.get("errors"):
        lines.extend(["", *result["errors"]])
    (output / "summary.md").write_text("\n".join(lines) + "\n")
    print(f"CLOSED_LOOP status={result['status']} mode={args.mode} tests={result.get('totals', {}).get('tests', 0)}", flush=True)
    return 0 if result["status"] == "passed" else 1


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", required=True, choices=("development", "full"))
    parser.add_argument("--output", required=True, type=Path, help="New directory; never overwrite old evidence")
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument("--timeout", type=int, default=1800, help="Per-check seconds; timeout is failure")
    args = parser.parse_args(argv)
    if args.jobs < 1 or args.timeout < 1:
        parser.error("jobs and timeout must be positive")
    output = args.output.expanduser().resolve()
    output.mkdir(parents=True, exist_ok=False)
    result = {"schema_version": 1, "mode": args.mode, "status": "failed", "release_ready": False,
              "started_at": datetime.now(timezone.utc).isoformat(), "host": platform.platform(), "platform": sys.platform,
              "repository": str(ROOT), "output_directory": str(output),
              "checks": [], "features": [], "regressions": [], "totals": {"tests": 0, "suites": 0}, "errors": []}
    try:
        tested_sha = git("rev-parse", "HEAD")
        result.update(tested_sha=tested_sha, head_sha=os.environ.get("ZEUS_HEAD_SHA", tested_sha),
                      dirty=bool(git("status", "--porcelain")))
        require(os.environ.get("ZEUS_TESTED_SHA", tested_sha) == tested_sha, "ZEUS_TESTED_SHA does not identify the actual checkout")
        require(re.fullmatch(r"[0-9a-f]{40}", result["head_sha"]), "invalid head SHA")
        before = snapshot(output)
        result["source_snapshot_sha256"] = before["sha256"]
        save(output / "source-manifest.json", before)
        result["source_manifest"] = artifact(output / "source-manifest.json", output)
        portable = portable_module()
        feature_map = load(ROOT / "qa/feature-map.json")
        definitions = validate_map(feature_map, portable)
        registry = validate_registry(load(ROOT / "qa/regressions.json"), definitions)
        result["map_sha256"] = digest((ROOT / "qa/feature-map.json").read_bytes())
        result["registry_sha256"] = digest((ROOT / "qa/regressions.json").read_bytes())
        selftest = {"id": "closed-loop-selftests", "kind": "selftests", "scope": "Runner/schema/receipt/aggregate rejection regressions."}
        run_checks([selftest, *definitions.values()], args, output, portable, result)
        checks = {row["id"]: row for row in result["checks"]}
        result["features"] = evaluate_features(feature_map, checks, output)
        result["regressions"] = evaluate_registry(registry, checks, output)
        result["totals"] = {key: sum(r[key] for r in result["checks"]) for key in ("tests", "suites")}
        required = {"closed-loop-selftests"} | {c["id"] for c in definitions.values() if args.mode == "full" or c["kind"] in {"portable", "release-mocks"}}
        bad = [c["id"] for c in result["checks"] if c["id"] in required and c["status"] != "passed"]
        # A passing group cannot hide a removed/not-executed feature or regression case.
        bad += [o["id"] for f in result["features"] for o in f["obligations"] if o["check"] in required and o["status"] != "passed"]
        bad += [r["id"] for r in result["regressions"] if r["check"] in required and r["status"] != "passed"]
        require(snapshot(output) == before, "Repository input changed while checks ran; rerun on a stable snapshot")
        require(git("rev-parse", "HEAD") == tested_sha, "Checkout changed while checks ran")
        result["release_ready"] = args.mode == "full" and all(f["status"] == "passed" for f in result["features"])
        if bad:
            result["errors"].append("Unmet required checks/cases: " + ", ".join(bad))
        result["status"] = "passed" if not bad else "failed"
    except (Invalid, OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
        result["errors"].append(str(error))
    result["finished_at"] = datetime.now(timezone.utc).isoformat()
    return finish(args, output, result)


if __name__ == "__main__":
    raise SystemExit(main())
