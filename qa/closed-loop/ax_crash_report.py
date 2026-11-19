#!/usr/bin/env python3
"""Read only the original synthetic Scribe host's uniquely identified crash report.

This never repairs, replaces, or awards acceptance credit to a native receipt.
"""
import argparse
from datetime import datetime
import json
import math
import os
from pathlib import Path
import platform
import re
import signal
import stat
import subprocess
import time

import native_app_host as host
import native_evidence as native
from contracts import (ROOT, Invalid, digest, load, require, source_snapshot,
                       validate_native_build)

IDENT = "native-ScribeAccessibilityJourneyTests"
DEFINITION = {"id": IDENT, "kind": "native-fixture", "suite": "ScribeAccessibilityJourneyTests",
              "file": "Tests/ZeusAppTests/ScribeComponentJourneyTests.swift"}
MAX_REPORT = 2 * 1024 * 1024
MAX_READ_BYTES = 8 * 1024 * 1024
MAX_CANDIDATES = 4
POLL_SECONDS = 10
IDENTITY_PREFIX = "Owned-window test host identity: "
MARKER = "ZEUS_CI_REQUIRE_NORMAL_MOTION"


def require_hosted_mac():
    require(platform.system() == "Darwin" and os.environ.get("GITHUB_ACTIONS") == "true"
            and os.environ.get("RUNNER_ENVIRONMENT") == "github-hosted",
            "AX crash diagnosis requires a GitHub-hosted Mac")
    require(MARKER not in os.environ, "normal-motion wrapper has not restored its environment")


def bounded_json(path, limit):
    require(path.is_file() and not path.is_symlink() and path.resolve() == path
            and path.stat().st_size <= limit, "diagnostic input missing, redirected or oversized")
    return load(path)


def validate_original(output, repo=ROOT):
    """Validate failure provenance; never interpret failed execution as passing."""
    output, repo = Path(output).resolve(), Path(repo).resolve()
    result_path = output / "result.json"
    result = bounded_json(result_path, 8 * 1024 * 1024)
    require(type(result) is dict and type(result.get("schema_version")) is int
            and result["schema_version"] == 2 and result.get("status") == "failed"
            and result.get("platform") == "darwin", "original macOS failure receipt is required")
    require(result.get("repository") == str(repo) and result.get("output_directory") == str(output),
            "original evidence is not from this checkout and output directory")
    sha = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, timeout=5).decode().strip()
    require(result.get("tested_sha") == sha == os.environ.get("ZEUS_TESTED_SHA", sha)
            and result.get("head_sha") == os.environ.get("ZEUS_HEAD_SHA", sha),
            "original receipt belongs to another revision")
    for name, key in (("feature-map.json", "map_sha256"), ("regressions.json", "registry_sha256")):
        require(result.get(key) == digest((repo / "qa" / name).read_bytes()), "native policy changed")
    manifest = load(native.artifact(output, result["source_manifest"]))
    require(manifest == source_snapshot(repo, output)
            and result.get("source_snapshot_sha256") == manifest.get("sha256"), "native source changed")
    build = result["native_build"]
    validate_native_build(build, output, manifest["sha256"])
    definitions = [row for row in load(repo / "qa/feature-map.json")["checks"]
                   if row.get("kind") in native.NATIVE_KINDS]
    selected = [row for row in definitions if row.get("id") == IDENT]
    require(len(selected) == 1 and all(selected[0].get(key) == value for key, value in DEFINITION.items()),
            "synthetic AX selector changed")
    native.validate_discovery_receipt(result["native_discovery"], output, manifest["sha256"],
                                      definitions, str(repo), str(output), repo)
    rows = result.get("native_runs")
    require(type(rows) is list, "original native partitions missing")
    selected = [row for row in rows if type(row) is dict and row.get("id") == IDENT]
    require(len(selected) == 1, "original AX failure is missing or duplicated")
    row = selected[0]
    require(row.get("status") == "failed" and type(row.get("exit_code")) is int
            and row["exit_code"] == -signal.SIGTRAP and row.get("kind") == "native-fixture",
            "original AX process did not fail with SIGTRAP")
    command = native.run_command([DEFINITION], build["command"][4], output, IDENT, repo)
    require(row.get("command") == command, "original AX command is not the exact allowlisted command")
    artifacts = row.get("artifacts")
    require(type(artifacts) is list and 5 <= len(artifacts) <= 20, "original AX artifacts missing or excessive")
    files = {item.get("path"): native.artifact(output, item) for item in artifacts}
    require(len(files) == len(artifacts) and all(
        name in {IDENT + "/test.log", IDENT + "/events.jsonl"}
        or name.startswith(IDENT + "/native-artifacts/") for name in files), "original AX artifacts changed scope")
    require(IDENT + "/test.log" in files and IDENT + "/events.jsonl" in files,
            "original AX log and events are required")
    host.validate_artifacts(files, IDENT)
    require(os.access(command[0], os.X_OK), "original host is not executable")
    inputs = host.inputs_path(output, IDENT)
    require(str(inputs.relative_to(output)) in files, "pre-original-run input provenance is missing")
    recorded = bounded_json(inputs, 16 * 1024)
    require(type(recorded) is dict and type(recorded.get("schema_version")) is int
            and type(recorded.get("selected_platform")) is str
            and len(recorded["selected_platform"]) <= 4096
            and Path(recorded["selected_platform"]).is_absolute(), "selected runtime provenance missing")
    require(recorded == host.input_provenance(repo, {"platform": recorded["selected_platform"]}),
            "compiled bundle input changed")
    require(not (repo / ".build").is_symlink(), "build root is redirected")
    tracked = [result_path, output / result["source_manifest"]["path"], *files.values(),
               *[output / item["path"] for item in build["artifacts"]],
               *[output / item["path"] for item in result["native_discovery"]["artifacts"]],
               host.bundle_binary(repo)]
    log = files[IDENT + "/test.log"]
    require(log.stat().st_size <= 2 * 1024 * 1024, "original AX log is oversized")
    identities = [line[len(IDENTITY_PREFIX):] for line in log.read_text().splitlines()
                  if line.startswith(IDENTITY_PREFIX)]
    require(len(identities) == 1, "original host identity is missing or ambiguous")
    identity = strict_decoder().decode(identities[0])
    require(type(identity) is dict and set(identity) == {"pid", "started", "executable"}
            and type(identity["pid"]) is int and identity["pid"] > 0
            and identity["executable"] == command[0], "original host identity changed")
    started = timestamp(identity["started"])
    duration = row.get("duration_seconds")
    require(type(duration) in {int, float} and 0 < duration <= 1800, "original host duration is unavailable")
    return {"source_sha256": manifest["sha256"], "host_identity": identity,
            "started": started, "ended_by": started + duration + 15,
            "tested_sha": sha, "input_provenance": recorded,
            "original_hashes": {str(path): digest(path.read_bytes()) for path in tracked},
            "original_resolved_paths": {str(path): str(path.resolve()) for path in tracked}}


def strict_decoder():
    def pairs(items):
        result = {}
        for key, value in items:
            require(key not in result, "duplicate crash-report JSON key")
            result[key] = value
        return result

    def nonfinite(_value):
        raise Invalid("nonfinite crash-report JSON number")

    def floating(value):
        number = float(value)
        require(math.isfinite(number), "nonfinite crash-report JSON number")
        return number

    return json.JSONDecoder(object_pairs_hook=pairs, parse_constant=nonfinite, parse_float=floating)


def timestamp(value):
    require(type(value) is str and len(value) <= 64, "timestamp is unavailable")
    if re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})", value):
        parsed = datetime.fromisoformat(value)
    elif re.fullmatch(r"\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}(?:\.\d{1,6})? [+-]\d{4}", value):
        parsed = datetime.strptime(value, "%Y-%m-%d %H:%M:%S.%f %z" if "." in value else "%Y-%m-%d %H:%M:%S %z")
    else:
        raise Invalid("unsupported timestamp format")
    require(parsed.tzinfo is not None, "timestamp has no timezone")
    return parsed.timestamp()


def parse_report(raw, context):
    """Support only Apple's two-object crash309 IPS, never general report text."""
    context["phase"] = "report-format"
    text = raw.decode("utf-8").lstrip()
    decoder = strict_decoder()
    header, end = decoder.raw_decode(text)
    text = text[end:].lstrip()
    body, end = decoder.raw_decode(text)
    require(not text[end:].strip(), "trailing crash-report content")
    require(type(header) is dict and type(body) is dict and header.get("bug_type") == "309",
            "unsupported crash-report format")
    identity = context["host_identity"]
    context["phase"] = "report-identity"
    require(type(body.get("pid")) is int, "crash PID is unavailable")
    # A different synthetic suite's report is not this process's evidence.
    if body["pid"] != identity["pid"] or body.get("procPath") != identity["executable"]:
        return None
    require(body.get("procName") == "zeus-native-test-host", "crash process name changed")
    context["phase"] = "report-time"
    launched, captured = timestamp(body.get("procLaunch")), timestamp(body.get("captureTime"))
    # Pre-main startup may precede telemetry by up to five seconds. Capture gets
    # a 15-second reporter allowance beyond the original finite run duration.
    require(context["started"] - 5 <= launched <= context["started"] + 1
            and context["started"] <= captured <= context["ended_by"], "crash time does not identify this run")
    if "timestamp" in header:
        require(abs(timestamp(header["timestamp"]) - captured) <= 2, "crash timestamps disagree")
    context["phase"] = "report-identity"
    if "bundleID" in header:
        require(header["bundleID"] == host.INFO["CFBundleIdentifier"], "crash bundle differs")
    if "bundleInfo" in body:
        require(type(body["bundleInfo"]) is dict, "crash bundle is malformed")
        if "CFBundleIdentifier" in body["bundleInfo"]:
            require(body["bundleInfo"]["CFBundleIdentifier"] == host.INFO["CFBundleIdentifier"],
                    "crash bundle differs")
    exception = body.get("exception")
    require(type(exception) is dict and exception.get("signal") == "SIGTRAP"
            and type(exception.get("type")) is str
            and re.fullmatch(r"[A-Z_0-9]{1,80}", exception["type"]), "crash exception is unsupported")
    context["phase"] = "report-frames"
    threads, images = body.get("threads"), body.get("usedImages")
    require(type(threads) is list and 1 <= len(threads) <= 128
            and type(images) is list and 1 <= len(images) <= 512, "crash thread/image bounds exceeded")
    triggered = [index for index, thread in enumerate(threads)
                 if type(thread) is dict and thread.get("triggered") is True]
    require(len(triggered) == 1, "crashed thread is ambiguous")
    if "faultingThread" in body:
        require(type(body["faultingThread"]) is int and body["faultingThread"] == triggered[0],
                "faulting thread differs")
    frames = threads[triggered[0]].get("frames")
    require(type(frames) is list and 1 <= len(frames) <= 512, "crashed frames are unavailable")
    result = []
    for frame in frames[:24]:
        require(type(frame) is dict and type(frame.get("imageIndex")) is int
                and 0 <= frame["imageIndex"] < len(images), "crash frame image is invalid")
        image = images[frame["imageIndex"]]
        require(type(image) is dict, "crash image is invalid")
        path = image.get("path", image.get("name"))
        require(type(path) is str and path and len(path) <= 4096, "crash image name unavailable")
        basename = Path(path).name
        symbol = frame.get("symbol", "<unresolved>")
        require(type(symbol) is str and symbol and basename
                and all(32 <= ord(char) <= 126 for char in basename), "crash symbol/image is malformed")
        # Do not serialize source paths, control/bidi text, or arbitrary reporter
        # strings disguised as symbols. Unknown spellings stay explicitly absent.
        if len(symbol) > 4096 or not re.fullmatch(r"[A-Za-z0-9_$@?.:<>()\[\]{}, &*+\-=~!#%|^'\"]+", symbol):
            symbol = "<unavailable-symbol>"
        result.append({"image": basename[:120], "symbol": symbol[:240]})
    return {"exception_type": exception["type"], "signal": exception["signal"],
            "frames": result, "frames_truncated": len(frames) > 24, "report_sha256": digest(raw)}


def read_report(name, expected, directory):
    descriptor = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=directory)
    with os.fdopen(descriptor, "rb") as stream:
        before = os.fstat(stream.fileno())
        require(stat.S_ISREG(before.st_mode) and 0 < before.st_size <= MAX_REPORT
                and (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns) == expected,
                "crash candidate changed before reading")
        raw = stream.read(MAX_REPORT + 1)
        after = os.fstat(stream.fileno())
        require(len(raw) == before.st_size and (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns) == expected,
                "crash candidate changed during reading")
        return raw


def collect_reports(context, reports):
    """Fixed own-host filename scope; global read/entry budgets across polling."""
    context["phase"] = "scan"
    expected = reports.stat()
    require(stat.S_ISDIR(expected.st_mode) and reports.resolve() == reports,
            "crash-report directory unavailable or redirected")
    directory = os.open(reports, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        actual = os.fstat(directory)
        require((actual.st_dev, actual.st_ino) == (expected.st_dev, expected.st_ino),
                "crash-report directory changed")
        return scan_reports(context, directory)
    finally:
        os.close(directory)


def scan_reports(context, directory):
    deadline = time.monotonic() + POLL_SECONDS
    cached, entries, read_bytes = {}, 0, 0
    for _ in range(21):
        context["phase"] = "scan"
        candidates = []
        # A fresh open-file description resets directory enumeration each poll;
        # all file opens remain relative to the original, verified directory FD.
        scan = os.open(".", os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=directory)
        try:
            with os.scandir(scan) as listing:
                for entry in listing:
                    entries += 1
                    require(entries <= 1024, "crash directory enumeration limit reached")
                    if not (entry.name.startswith("zeus-native-test-host") and entry.name.endswith(".ips")):
                        continue
                    info = entry.stat(follow_symlinks=False)
                    if not context["started"] - 1 <= info.st_mtime <= context["ended_by"] + 120:
                        continue
                    require(stat.S_ISREG(info.st_mode), "fresh crash candidate is not a regular file")
                    require(len(candidates) < MAX_CANDIDATES, "fresh crash candidate limit reached")
                    signature = (info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns)
                    candidates.append((entry.name, signature))
        finally:
            os.close(scan)
        matches = []
        for name, signature in candidates:
            key = (name, signature)
            if key not in cached:
                require(len(cached) < MAX_CANDIDATES and read_bytes + signature[2] <= MAX_READ_BYTES,
                        "cumulative crash-report read limit reached")
                context["phase"] = "report-read"
                raw = read_report(name, signature, directory)
                read_bytes += len(raw)
                cached[key] = parse_report(raw, context)
            if cached[key] is not None:
                matches.append(cached[key])
        context["phase"] = "report-identity"
        require(len(matches) <= 1, "matching crash reports are ambiguous")
        if matches:
            return matches[0]
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            break
        time.sleep(min(0.5, remaining))
    return None


def verify_unchanged(context, evidence, repo=ROOT):
    require(all(Path(path).is_file() and str(Path(path).resolve()) == context["original_resolved_paths"][path]
                and digest(Path(path).read_bytes()) == expected
                for path, expected in context["original_hashes"].items()), "original evidence or input changed")
    require(source_snapshot(repo, evidence)["sha256"] == context["source_sha256"], "source changed during diagnosis")


def main(arguments=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(arguments)
    context, output = None, None
    phase = "environment"
    result = {"schema_version": 1, "diagnostic_only": True, "acceptance_credit": False,
              "original_exit_code": -signal.SIGTRAP, "status": "unavailable"}
    try:
        require_hosted_mac()
        evidence = args.evidence.resolve()
        phase = "output"
        require(args.output.is_absolute() and args.output.parent.resolve() == evidence.parent
                and args.output.name == "ax-crash-report" and not args.output.is_symlink(),
                "diagnostic output must be the fresh sibling ax-crash-report directory")
        phase = "provenance"
        context = validate_original(evidence)
        context["phase"] = "output"
        destination = evidence.parent / "ax-crash-report"
        destination.mkdir(exist_ok=False)
        output = destination
        result.update(tested_sha=context["tested_sha"], source_sha256=context["source_sha256"],
                      original_result_sha256=context["original_hashes"][str(evidence / "result.json")],
                      input_provenance_sha256=digest(json.dumps(context["input_provenance"], sort_keys=True).encode()))
        # This is the disposable runner's user report directory, never a global
        # crash-report scan or a user-selected path supplied by receipt contents.
        reports = Path.home() / "Library/Logs/DiagnosticReports"
        crash = collect_reports(context, reports)
        context["phase"] = "final-verification"
        verify_unchanged(context, evidence)
        if crash is not None:
            result.update(status="collected", crash=crash, phase="complete")
        else:
            result["reason"] = "matching_report_unavailable"
            result["phase"] = "scan"
    except (Invalid, OSError, ValueError, KeyError, TypeError, RecursionError, subprocess.SubprocessError) as error:
        # No parser text, payload, environment, image path, or raw report escapes.
        result["reason"] = "validation_or_report_unavailable"
        result["error_type"] = type(error).__name__
        result["phase"] = context.get("phase", phase) if context is not None else phase
    except KeyboardInterrupt:
        result["reason"] = "interrupted"
        result["phase"] = context.get("phase", phase) if context is not None else phase
    finally:
        if context is not None:
            try:
                verify_unchanged(context, evidence)
                result["original_evidence_unchanged"] = True
            except (Invalid, OSError, ValueError):
                result.pop("crash", None)
                result.update(status="unavailable", reason="original_evidence_changed", original_evidence_unchanged=False,
                              phase="final-verification")
        if output is not None and output.is_dir():
            with (output / "result.json").open("x") as stream:
                stream.write(json.dumps(result, indent=2) + "\n")
    print("AX crash report: " + result["status"] + "; phase=" + result["phase"]
          + "; diagnostic only; original native failure retained")
    return 0 if result["status"] == "collected" else 1


if __name__ == "__main__":
    raise SystemExit(main())
