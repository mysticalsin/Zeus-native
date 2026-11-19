#!/usr/bin/env python3
"""Local trusted-Mac runner for the SwiftUI accessibility journey (never CI, never gate full mode).

Packages the already built bundled test host the same way CI does, runs only the trusted suite, then
validates the Swift Testing event stream. An exit status alone is never a pass. Only this process's own
windows are touched by the test; this runner requests no permission and captures no screen or audio.
"""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import plistlib
import platform
import shutil
import signal
import subprocess
import sys

import native_app_host as host
import native_evidence as native
from contracts import ROOT, Invalid, require

SUITE = "ScribeTrustedAccessibilityJourneyTests"
FILTER = "^ZeusAppTests\\." + SUITE + "/"
IDENT = "trusted-" + SUITE
REQUIRED_FUNCTION = "realButtonsDriveStartKeepStopFailedSaveRetryAndClose"
TIMEOUT_SECONDS = 600
ISSUE_SYMBOLS = {"fail", "skip", "knownIssue", "issue"}


def require_local_mac():
    require(platform.system() == "Darwin", "the trusted AX journey requires macOS")
    require("GITHUB_ACTIONS" not in os.environ, "the trusted AX journey never runs in CI")


def build_products(build_dir):
    """The compiled host and test bundle inside the caller's scratch path, never anywhere else."""
    build_dir = Path(build_dir).resolve()
    debug = build_dir / "debug"
    built = debug / "zeus-native-test-host"
    # Swift 6.2 (CI) links one combined package test bundle; newer Swift Build backends emit one
    # bundle per test target. Accept exactly one of the two layouts.
    candidates = [debug / "ZeusPackageTests.xctest/Contents/MacOS/ZeusPackageTests",
                  debug / "ZeusAppTests.xctest/Contents/MacOS/ZeusAppTests"]
    present = [path for path in candidates if path.is_file()]
    require(len(present) == 1, "expected exactly one compiled app test bundle; run scripts/trusted-ax-journey.sh")
    tests = present[0]
    for binary in (built, tests):
        require(binary.is_file() and os.access(binary, os.X_OK) and binary.resolve().is_relative_to(build_dir),
                "compiled test host or test bundle is missing or redirected; run scripts/trusted-ax-journey.sh")
    return built, tests


def package(output, built):
    """Same layout and Info.plist as the CI host package (native_app_host.prepare)."""
    target = host.executable(output, IDENT)
    target.parent.mkdir(parents=True, exist_ok=False)
    shutil.copy2(built, target)
    (target.parent.parent / "Info.plist").write_bytes(plistlib.dumps(host.INFO))
    return target, host.runtime_configuration()["environment"]


def command(target, tests, events):
    return [str(target), "--test-bundle-path", str(tests), "--filter", FILTER,
            "--event-stream-output-path", str(events), "--event-stream-version", "0"]


def validate_events(path):
    """Return (problems, passed_test_ids). Pass only when everything started also ended cleanly."""
    problems, declared, started, ended = [], set(), set(), set()
    runs_started = runs_ended = issues = 0
    try:
        rows = native.stream(Path(path))
    except (Invalid, OSError, ValueError) as error:
        return [str(error)], []
    for row in rows:
        payload = row["payload"]
        if row["kind"] == "test":
            if payload.get("kind") == "function" and type(payload.get("id")) is str:
                declared.add(payload["id"])
            continue
        kind, ident = payload.get("kind"), payload.get("testID")
        messages = payload.get("messages", [])
        symbols = {m.get("symbol") for m in messages if type(m) is dict} if type(messages) is list else set()
        if kind in {"issueRecorded", "testSkipped"} or symbols & ISSUE_SYMBOLS:
            issues += 1
        if kind == "runStarted":
            runs_started += 1
        elif kind == "runEnded":
            runs_ended += 1
            if "pass" not in symbols:
                problems.append("run ended without a pass event")
        elif kind == "testStarted" and type(ident) is str and "/" in ident:
            started.add(ident)
        elif kind == "testEnded" and type(ident) is str and "/" in ident:
            ended.add(ident)
            if "pass" not in symbols:
                problems.append(f"test ended without a pass event: {ident}")
    if issues:
        problems.append(f"{issues} issue or skip events recorded")
    if (runs_started, runs_ended) != (1, 1):
        problems.append(f"run lifecycle incomplete: started={runs_started} ended={runs_ended}")
    if not started:
        problems.append("no test started")
    if started != ended:
        problems.append("started tests without a terminal event: " + ", ".join(sorted(started - ended)))
    if not started <= declared:
        problems.append("started tests were never declared")
    if not any(ident.startswith("ZeusAppTests." + SUITE + "/" + REQUIRED_FUNCTION + "(") for ident in ended):
        problems.append("the AX journey test did not run to completion: " + REQUIRED_FUNCTION)
    if any(not ident.startswith("ZeusAppTests." + SUITE + "/") for ident in started | ended):
        problems.append("a test outside the trusted suite ran")
    return problems, sorted(ended)


def validate_receipt(receipt_path, tested_sha):
    """Strictly re-validate a trusted-Mac receipt for the tested source sha; return it or raise Invalid.

    Used by run.py when it consumes a receipt and again by gate.py, so neither trusts the other's word.
    The receipt and its events file must be regular files (never links). The events file is the
    `events.jsonl` next to the receipt, so a receipt copied into a run output stays verifiable.
    """
    path = Path(receipt_path)
    require(path.is_file() and not path.is_symlink() and path.stat().st_size <= 1024 * 1024,
            "trusted receipt is missing, redirected or oversized")
    try:
        value = json.loads(path.read_text())
    except ValueError as error:
        raise Invalid(f"trusted receipt is not valid JSON: {error}")
    require(type(value) is dict, "trusted receipt must be an object")
    require(type(value.get("schema_version")) is int and value["schema_version"] == 1,
            "trusted receipt schema_version is not 1")
    require(value.get("result") == "passed", "trusted receipt result is not passed")
    require(type(tested_sha) is str and bool(tested_sha) and value.get("sha") == tested_sha,
            "trusted receipt belongs to another source sha")
    require(value.get("dirty") is False, "trusted receipt was taken on a dirty tree")
    require(type(value.get("exit_code")) is int and value["exit_code"] == 0, "trusted receipt exit_code is not 0")
    require(value.get("problems") == [], "trusted receipt records problems")
    ids = value.get("test_ids")
    require(type(ids) is list and all(type(ident) is str for ident in ids), "trusted receipt test_ids are malformed")
    prefix = "ZeusAppTests." + SUITE + "/"
    require(all(ident.startswith(prefix) for ident in ids), "trusted receipt lists a test outside the trusted suite")
    require(any(ident.startswith(prefix + REQUIRED_FUNCTION + "(") for ident in ids),
            "trusted receipt lacks the required test " + REQUIRED_FUNCTION)
    require(type(value.get("events")) is str and Path(value["events"]).name == "events.jsonl",
            "trusted receipt does not reference an events.jsonl file")
    events = path.parent / "events.jsonl"
    require(events.is_file() and not events.is_symlink(), "trusted receipt events file is missing or redirected")
    problems, ended = validate_events(events)
    require(not problems, "trusted receipt events do not validate: " + "; ".join(problems))
    require(sorted(ids) == ended, "trusted receipt test_ids differ from its events")
    return value


def git(*args):
    return subprocess.check_output(["git", "-c", "core.fileMode=false", *args], cwd=ROOT, text=True, timeout=30).strip()


def run_host(argv, log, environment):
    with log.open("w") as stream:
        process = subprocess.Popen(argv, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT, start_new_session=True,
                                   env={**os.environ, "NO_COLOR": "1", **environment})
        try:
            return process.wait(timeout=TIMEOUT_SECONDS)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
            stream.write(f"\nTRUSTED AX JOURNEY TIMEOUT after {TIMEOUT_SECONDS} seconds\n")
            return 124


def main(argv=None):
    home = Path.home()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-dir", type=Path, default=home / "AI-Brain-build/zeus-native-build")
    parser.add_argument("--receipts", type=Path, default=home / "AI-Brain-build/zeus-trusted-ax")
    args = parser.parse_args(argv)
    require_local_mac()
    built, tests = build_products(args.build_dir)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    sha = git("rev-parse", "HEAD")
    output = args.receipts.expanduser().resolve() / f"run-{stamp}-{sha[:7]}"
    output.mkdir(parents=True, exist_ok=False)
    target, environment = package(output, built)
    events, log = output / "events.jsonl", output / "test.log"
    code = run_host(command(target, tests, events), log, environment)
    problems, passed = validate_events(events)
    ok = code == 0 and not problems
    if code != 0:
        problems.insert(0, f"host exit status {code}")
    receipt = {"schema_version": 1, "result": "passed" if ok else "failed", "sha": sha,
               "dirty": bool(git("status", "--porcelain")), "timestamp": stamp, "exit_code": code,
               "filter": FILTER, "test_ids": passed, "problems": problems, "events": str(events), "log": str(log)}
    (output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(f"TRUSTED AX JOURNEY {receipt['result'].upper()} tests={len(passed)} receipt={output / 'receipt.json'}")
    for problem in problems:
        print("  " + problem)
    return 0 if ok else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Invalid as error:
        print(f"TRUSTED AX JOURNEY REFUSED: {error}", file=sys.stderr)
        raise SystemExit(2)
