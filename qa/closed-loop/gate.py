#!/usr/bin/env python3
"""Record CI evidence and require every fixed prerequisite to pass for the exact run/revision.

This does not configure GitHub branch protection. A missing/cancelled gate is never an approval.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

REQUIRED = {
    "app": ("build", "test", "bundle", "archive"),
    "extension": ("install", "typecheck", "test", "build"),
    "release-scripts": ("test",),
    "feature-map": ("map",),
}
HEX_SHA = re.compile(r"[0-9a-f]{40}\Z")
HEX_HASH = re.compile(r"[0-9a-f]{64}\Z")


def load_json(text: str):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f"duplicate JSON key: {key}")
            result[key] = value
        return result

    def invalid(value):
        raise ValueError(f"non-finite JSON value: {value}")

    return json.loads(text, object_pairs_hook=unique, parse_constant=invalid)


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(65536), b""):
            value.update(block)
    return value.hexdigest()


def artifact(root: Path, relative: str) -> Path:
    if not isinstance(relative, str) or not relative:
        raise ValueError("artifact path is missing")
    path = Path(relative)
    if path.is_absolute() or any(part in (".", "..") for part in path.parts):
        raise ValueError("artifact path escapes its receipt")
    if root.is_symlink():
        raise ValueError("artifact root is redirected")
    root = root.resolve()
    target = root / path
    if target.resolve() != target or not target.is_file():
        raise ValueError(f"missing or redirected artifact: {relative}")
    return target


def load_object(path: Path) -> dict:
    # Receipts contain metadata, never logs or captured media. Oversized metadata fails closed.
    if not path.is_file() or path.is_symlink() or path.stat().st_size > 4 * 1024 * 1024:
        raise ValueError(f"missing, redirected or oversized receipt: {path.name}")
    value = load_json(path.read_text())
    if not isinstance(value, dict):
        raise ValueError(f"receipt must be an object: {path.name}")
    return value


def positive_test_count(job: str, path: Path) -> int:
    patterns = {
        "app": (r"Test run with (\d+) tests?(?: in \d+ suites?)? passed", r"Executed (\d+) tests?, with 0 failures"),
        "extension": (r"^[#ℹ] tests (\d+)\s*$",),
        "release-scripts": (r"^Ran (\d+) tests? in ",),
    }
    maximum = 0
    node_summary = {}
    unittest_ok = False
    with path.open(errors="replace") as stream:
        for line in stream:
            if job == "app" and (re.search(r"Test run with \d+ tests?.* failed", line) or re.search(r"Executed \d+ tests?, with [1-9]\d* failures", line)):
                raise ValueError("native test summary contains failures")
            if job == "extension":
                value = re.match(r"^[#ℹ] (tests|pass|fail|cancelled|skipped|todo) (\d+)\s*$", line)
                if value:
                    node_summary[value[1]] = int(value[2])
            if job == "release-scripts":
                if re.match(r"^FAILED\b|^OK \(skipped=", line):
                    raise ValueError("release-script tests failed or were skipped")
                unittest_ok = unittest_ok or line.strip() == "OK"
            for pattern in patterns[job]:
                match = re.search(pattern, line)
                if match:
                    maximum = max(maximum, int(match[1]))
    if job == "extension":
        if set(node_summary) != {"tests", "pass", "fail", "cancelled", "skipped", "todo"} or node_summary["pass"] != node_summary["tests"] or any(node_summary[key] != 0 for key in ("fail", "cancelled", "skipped", "todo")):
            raise ValueError("extension test summary is missing, failed, cancelled or skipped")
    if job == "release-scripts" and not unittest_ok:
        raise ValueError("release-script tests have no successful terminal summary")
    return maximum


def job_artifacts(job: str) -> set[str]:
    if job == "feature-map":
        return {"result.json"}
    files = {f"{check}.log" for check in REQUIRED[job]}
    if job == "app":
        files.add("native-evidence/result.json")
    return files


def record(job: str, output: Path) -> None:
    output.mkdir(parents=True, exist_ok=True)
    actual_sha = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
    checks = load_json(os.environ.get("ZEUS_STEP_RESULTS", "null"))
    files = {}
    for relative in sorted(job_artifacts(job)):
        path = output / relative
        if path.is_file() and not path.is_symlink():
            files[relative] = {"sha256": digest(path), "bytes": path.stat().st_size}
    result = {
        "schema_version": 1,
        "job": job,
        "tested_sha": actual_sha,
        "expected_sha": os.environ.get("ZEUS_TESTED_SHA", ""),
        "head_sha": os.environ.get("ZEUS_HEAD_SHA", ""),
        "run_id": os.environ.get("GITHUB_RUN_ID", ""),
        "run_attempt": os.environ.get("GITHUB_RUN_ATTEMPT", ""),
        "event": os.environ.get("GITHUB_EVENT_NAME", ""),
        "checks": checks,
        "files": files,
    }
    (output / "job.json").write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")


def policy_modules():
    repo = Path(__file__).resolve().parents[2]
    modules = []
    for name, path in (("zeus_gate_contracts", repo / "qa/closed-loop/contracts.py"),
                       ("zeus_gate_portable", repo / "qa/portable-core/prepare.py")):
        spec = importlib.util.spec_from_file_location(name, path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        modules.append(module)
    return repo, modules[0], modules[1]


def load_policy():
    repo, contracts, portable = policy_modules()
    feature_map = load_object(repo / "qa/feature-map.json")
    definitions = contracts.validate_map(feature_map, portable)
    registry = contracts.validate_registry(load_object(repo / "qa/regressions.json"), definitions)
    return repo, contracts, portable, feature_map, definitions, registry


def native_evidence_module():
    sibling = Path(__file__).resolve().parent
    if str(sibling) not in sys.path:
        sys.path.insert(0, str(sibling))
    module = importlib.import_module("native_evidence")
    if Path(module.__file__).resolve() != sibling / "native_evidence.py" or module.ROOT.resolve() != sibling.parents[1]:
        raise ValueError("native evidence validator is not from the current checkout")
    return module


def native_filter() -> str:
    _, _, _, _, definitions, _ = load_policy()
    native = native_evidence_module()
    return native.selector([row for row in definitions.values() if row["kind"] in native.NATIVE_KINDS])


def validate_native(root: Path, expected_sha: str, head_sha: str) -> int:
    """Require every mapped process receipt before using the verified case union."""
    repo, _, _, feature_map, definitions, registry = load_policy()
    native = native_evidence_module()
    selected = [row for row in definitions.values() if row["kind"] in native.NATIVE_KINDS]
    # Canonicalize the trusted parent, then validate the nested receipt boundary.
    evidence = artifact(root, "native-evidence/result.json").parent
    metrics = native.validate_receipt(evidence, expected_sha, head_sha, selected, repo=repo)
    if type(metrics.get("tests")) is not int or metrics["tests"] <= 0:
        raise ValueError("native execution has no verified positive case count")
    cases = [case for feature in feature_map["features"] for obligation in feature["obligations"]
             if definitions[obligation["check"]]["kind"] in native.NATIVE_KINDS for case in obligation["cases"]]
    cases += [row["guard"] for row in registry if row["check"] in definitions and definitions[row["check"]]["kind"] in native.NATIVE_KINDS]
    if not cases:
        raise ValueError("native acceptance cases are missing")
    for case in cases:
        native.case_passed(case, metrics["passed_cases"])
    return metrics["tests"]


def validate_native_compilation(result: dict, root: Path, mode: str, contracts) -> str | None:
    """Authorize native reuse only with a current-source, verified macOS test build."""
    if mode != "full" or result.get("platform") != "darwin":
        if "native_build" in result:
            raise ValueError("native compiler barrier is only valid for full macOS checks")
        return None
    if "native_build" not in result:
        raise ValueError("full macOS checks have no native compiler barrier")
    contracts.validate_native_build(result["native_build"], root, result["source_snapshot_sha256"])
    return result["native_build"]["command"][4]


def validate_native_command(command, definition: dict, native_jobs: str | None, recorded_output: str, ident: str) -> None:
    if native_jobs is None:
        raise ValueError("native fixture execution has no verified macOS compiler barrier")
    expected = native_evidence_module().run_command([definition], native_jobs, recorded_output, ident)
    if command != expected:
        raise ValueError("native fixture command differs from its verified build, events and exact reviewed selection")


def validate_feature_map(root: Path, expected_sha: str, head_sha: str, mode: str) -> int:
    result_path = artifact(root, "result.json")
    # artifact() validates the boundary and rejects links below it. Normalize the
    # trusted ancestry once (macOS /var aliases /private/var) before package checks.
    root = result_path.parent
    result = load_object(result_path)
    repo, contracts, portable, feature_map, definitions, registry = load_policy()
    if type(result.get("schema_version")) is not int or result["schema_version"] != 1:
        raise ValueError("feature map schema is unsupported")
    if result.get("status") != "passed" or result.get("mode") != mode:
        raise ValueError(f"feature map did not pass {mode} mode")
    if result.get("tested_sha") != expected_sha or result.get("head_sha") != head_sha:
        raise ValueError("feature map belongs to another source/head SHA")
    if result.get("map_sha256") != digest(repo / "qa/feature-map.json") or result.get("registry_sha256") != digest(repo / "qa/regressions.json"):
        raise ValueError("feature map or regression policy is stale")
    if not isinstance(result.get("source_snapshot_sha256"), str) or not HEX_HASH.fullmatch(result["source_snapshot_sha256"]):
        raise ValueError("feature map has no source snapshot hash")
    if result.get("platform") not in {"linux", "darwin"}:
        raise ValueError("feature map platform is missing or unsupported")
    source = result.get("source_manifest")
    if not isinstance(source, dict) or source.get("path") != "source-manifest.json":
        raise ValueError("feature map source manifest is missing")
    source_path = artifact(root, source["path"])
    if digest(source_path) != source.get("sha256"):
        raise ValueError("source manifest artifact hash differs")
    manifest = load_object(source_path)
    expected_manifest = contracts.source_snapshot(repo, root)
    if manifest != expected_manifest or result["source_snapshot_sha256"] != manifest.get("sha256"):
        raise ValueError("feature result source differs from current checkout bytes")
    native_jobs = validate_native_compilation(result, root, mode, contracts)
    native = native_evidence_module()
    native_definitions = [row for row in definitions.values() if row["kind"] in native.NATIVE_KINDS]
    compiled = None
    if native_jobs is not None:
        compiled = native.validate_discovery_receipt(result.get("native_discovery"), root, result["source_snapshot_sha256"],
                                                     native_definitions, result.get("repository"), result.get("output_directory"), repo=repo)
    elif "native_discovery" in result:
        raise ValueError("native discovery is only valid with a verified full macOS build")
    if type(result.get("release_ready")) is not bool:
        raise ValueError("feature map release_ready must be a boolean")
    checks = result.get("checks")
    if not isinstance(checks, list) or not checks:
        raise ValueError("feature map has no executed checks")
    by_id = {}
    count = 0
    required = {"closed-loop-selftests"} | {ident for ident, definition in definitions.items()
                                                if mode == "full" or definition["kind"] in {"portable", "release-mocks"}}
    for check in checks:
        if not isinstance(check, dict) or not isinstance(check.get("id"), str) or not check["id"] or check["id"] in by_id:
            raise ValueError("feature map has missing or duplicate check IDs")
        ident = check["id"]
        by_id[ident] = check
        definition = definitions.get(ident, {"kind": "selftests"} if ident == "closed-loop-selftests" else None)
        if definition is None or check.get("kind") != definition["kind"]:
            raise ValueError(f"unknown or changed feature checker: {ident}")
        tests = check.get("tests")
        if type(tests) is not int or tests < 0:
            raise ValueError(f"feature check has invalid test count: {ident}")
        if ident not in required:
            expected = "unimplemented" if definition["kind"] == "unimplemented" else "not-run"
            if check.get("status") != expected or check.get("exit_code") is not None or tests != 0 or check.get("artifacts") != [] or check.get("command") != []:
                raise ValueError(f"unexecuted feature check claims evidence: {ident}")
            continue
        if definition["kind"] == "unimplemented":
            raise ValueError(f"full mode still has an unimplemented obligation: {ident}")
        if check.get("status") != "passed" or type(check.get("exit_code")) is not int or check["exit_code"] != 0 or tests <= 0:
            raise ValueError(f"required feature check did not execute and succeed: {ident}")
        if not isinstance(check.get("command"), list) or not check["command"] or not all(isinstance(x, str) and x for x in check["command"]):
            raise ValueError(f"feature check has no command: {ident}")
        if definition["kind"] in native.NATIVE_KINDS:
            validate_native_command(check["command"], definition, native_jobs, result["output_directory"], ident)
            metrics = native.validate_run_receipt(check, root, compiled, [definition], native_jobs,
                                                  result["repository"], result["output_directory"], repo=repo)
            count += metrics["tests"]
            continue
        count += tests
        evidence = check.get("artifacts")
        if not isinstance(evidence, list) or not evidence:
            raise ValueError(f"feature check has no evidence: {ident}")
        logs = []
        for entry in evidence:
            if not isinstance(entry, dict):
                raise ValueError(f"feature check has invalid evidence: {ident}")
            path = artifact(root, entry.get("path"))
            if digest(path) != entry.get("sha256"):
                raise ValueError(f"feature check evidence hash mismatch: {ident}")
            if path.name == "test.log":
                logs.append(path)
        if len(logs) != 1:
            raise ValueError(f"feature check must have exactly one test log: {ident}")
        log = logs[0].read_text()
        if definition["kind"] in {"portable", "native-fixture"}:
            actual_tests, _, functions = contracts.swift_summary(log, 0)
        else:
            actual_tests = positive_test_count("release-scripts", logs[0])
            functions = sorted(set(re.findall(r"^(test_\w+) \([^\n]+\) \.\.\. ok$", log, re.MULTILINE)))
        if actual_tests != tests or functions != check.get("passed_functions") or len(functions) == 0:
            raise ValueError(f"feature check test receipt does not match its log: {ident}")
        if definition["kind"] == "portable":
            package_name = check.get("package")
            if not isinstance(package_name, str) or not package_name or Path(package_name).is_absolute() or ".." in Path(package_name).parts:
                raise ValueError(f"feature check has no contained source package: {ident}")
            package = root / package_name
            if package.resolve() != package.absolute() or any(p.is_symlink() for p in package.rglob("*")):
                raise ValueError(f"feature source package is redirected: {ident}")
            with tempfile.TemporaryDirectory(prefix="zeus-gate-source-") as temporary:
                expected = portable.prepare(Path(temporary), definition["group"], platform_name=result["platform"])
                contracts.manifest_matches(package, expected)
    if set(by_id) != set(definitions) | {"closed-loop-selftests"}:
        raise ValueError("feature checker set is missing or unexpected")
    totals = result.get("totals")
    if not isinstance(totals, dict) or type(totals.get("tests")) is not int or totals["tests"] != count or count <= 0:
        raise ValueError("feature map has no verified positive test total")
    features = contracts.evaluate_features(feature_map, by_id, root)
    if result.get("features") != features:
        raise ValueError("feature IDs, obligation bindings or statuses differ from current evidence")
    for feature in features:
        for obligation in feature["obligations"]:
            if obligation["check"] in required and obligation["status"] != "passed":
                raise ValueError(f"required feature obligation did not pass: {obligation['id']}")
    for entry in registry:
        if entry["check"] in required:
            contracts.case_passed(entry["guard"], by_id[entry["check"]], root)
    release_ready = mode == "full" and all(feature["status"] == "passed" for feature in features)
    if result["release_ready"] != release_ready:
        raise ValueError("release_ready contradicts the mandatory feature obligations")
    return count


def evaluate(needs, inputs: Path, expected_sha: str, head_sha: str, run_id: str, attempt: str, mode: str) -> dict:
    errors = []
    jobs = {}
    if not HEX_SHA.fullmatch(expected_sha) or not HEX_SHA.fullmatch(head_sha):
        errors.append("Expected tested/head SHAs must be full commit hashes.")
    if not run_id.isdigit() or not attempt.isdigit() or int(attempt or "0") < 1:
        errors.append("Run identity is missing or invalid.")
    if not isinstance(needs, dict):
        errors.append("Job results are missing or not an object.")
        needs = {}
    if set(needs) != set(REQUIRED):
        errors.append(f"Prerequisite set differs: missing={sorted(set(REQUIRED) - set(needs))}, unexpected={sorted(set(needs) - set(REQUIRED))}.")
    for job, required_checks in REQUIRED.items():
        state = needs.get(job)
        status = state.get("result") if isinstance(state, dict) else None
        jobs[job] = {"result": status, "tests": 0}
        if status != "success":
            errors.append(f"{job}: job result is {status!r}; only success is accepted.")
        root = inputs / f"zeus-check-{job}"
        try:
            receipt = load_object(artifact(root, "job.json"))
            if type(receipt.get("schema_version")) is not int or receipt["schema_version"] != 1:
                raise ValueError("unsupported receipt schema")
            identity = {"job": job, "tested_sha": expected_sha, "expected_sha": expected_sha,
                        "head_sha": head_sha, "run_id": run_id, "run_attempt": attempt}
            if any(receipt.get(key) != value for key, value in identity.items()):
                raise ValueError("receipt belongs to another job, revision, head or run attempt")
            checks = receipt.get("checks")
            if not isinstance(checks, dict) or set(checks) != set(required_checks):
                raise ValueError("receipt check set is missing or unexpected")
            if any(value != "success" for value in checks.values()):
                raise ValueError(f"one or more required checks did not pass: {checks}")
            files = receipt.get("files")
            expected_files = job_artifacts(job)
            if not isinstance(files, dict) or set(files) != expected_files:
                raise ValueError("check logs/results are missing or unexpected")
            for relative, info in files.items():
                path = artifact(root, relative)
                if not isinstance(info, dict) or info.get("sha256") != digest(path) or type(info.get("bytes")) is not int or info["bytes"] != path.stat().st_size:
                    raise ValueError(f"artifact changed after its receipt: {relative}")
            if job == "feature-map":
                jobs[job]["tests"] = validate_feature_map(root, expected_sha, head_sha, mode)
            else:
                count = validate_native(root, expected_sha, head_sha) if job == "app" else positive_test_count(job, artifact(root, "test.log"))
                if count <= 0:
                    raise ValueError("test command produced no positive passing test count")
                jobs[job]["tests"] = count
        except (OSError, ValueError, TypeError, KeyError) as error:
            errors.append(f"{job}: {error}")
    return {"schema_version": 1, "status": "failed" if errors else "passed", "tested_sha": expected_sha,
            "head_sha": head_sha, "run_id": run_id, "run_attempt": attempt, "mode": mode, "jobs": jobs, "errors": errors}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="operation", required=True)
    subparsers.add_parser("native-filter")
    capture = subparsers.add_parser("record")
    capture.add_argument("--job", choices=REQUIRED, required=True)
    capture.add_argument("--output", type=Path, required=True)
    gate = subparsers.add_parser("evaluate")
    gate.add_argument("--inputs", type=Path, required=True)
    gate.add_argument("--output", type=Path, required=True)
    gate.add_argument("--mode", choices=("development", "full"), required=True)
    args = parser.parse_args()
    if args.operation == "native-filter":
        print(native_filter())
        return 0
    if args.operation == "record":
        record(args.job, args.output)
        return 0
    try:
        needs = load_json(os.environ.get("ZEUS_NEEDS_JSON", "null"))
    except ValueError:
        needs = None
    result = evaluate(needs, args.inputs, os.environ.get("ZEUS_TESTED_SHA", ""), os.environ.get("ZEUS_HEAD_SHA", ""),
                      os.environ.get("GITHUB_RUN_ID", ""), os.environ.get("GITHUB_RUN_ATTEMPT", ""), args.mode)
    actual_sha = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
    if actual_sha != result["tested_sha"]:
        result["errors"].append("Gate checkout does not match the tested SHA.")
        result["status"] = "failed"
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "result.json").write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    summary = f"Zeus required checks: **{result['status']}**\n\nTested: `{result['tested_sha']}`\n\nHead: `{result['head_sha']}`\n"
    if result["errors"]:
        summary += "\n" + "\n".join(f"- {error}" for error in result["errors"]) + "\n"
    print(summary)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as output:
            output.write(summary)
    return 0 if result["status"] == "passed" else 1


if __name__ == "__main__":
    sys.exit(main())
