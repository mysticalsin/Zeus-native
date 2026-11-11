#!/usr/bin/env python3
"""Run all audited Core tests plus only the mapped app suites, with qualified proof."""
import argparse
import os
from pathlib import Path
import platform
import subprocess
import sys

import native_evidence as native
import run as runner
from contracts import ROOT, Invalid, digest, load, require, validate_map, validate_registry


def run_partitions(args, output, result, selection):
    """Keep process-global app state isolated, and collect later failures too."""
    result["native_runs"] = []
    for definition in native.partitions(selection):
        try:
            row = runner.run_native_check(definition, args, output, result["native_build"],
                                          result.get("native_discovery"), selection)
        except (Invalid, OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
            row = {"id": definition["id"], "kind": definition["kind"], "tier": "native-integration",
                   "scope": definition["scope"], "status": "failed", "command": [], "exit_code": None,
                   "tests": 0, "suites": 0, "parameter_cases": 0, "passed_functions": [],
                   "passed_cases": [], "artifacts": [], "reason": str(error)}
        result["native_runs"].append(row)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--jobs", default=4, type=int)
    parser.add_argument("--timeout", default=1800, type=int)
    args = parser.parse_args(argv)
    if args.jobs < 1 or args.timeout < 1:
        parser.error("jobs and timeout must be positive")
    args.mode = "full"
    output = args.output.expanduser().resolve()
    output.mkdir(parents=True, exist_ok=False)
    result = {"schema_version": 2, "status": "failed", "repository": str(ROOT), "output_directory": str(output),
              "platform": sys.platform, "errors": []}
    try:
        require(platform.system() == "Darwin", "Native module execution requires macOS and Apple SDKs")
        result["tested_sha"] = runner.git("rev-parse", "HEAD")
        result["head_sha"] = os.environ.get("ZEUS_HEAD_SHA", result["tested_sha"])
        require(os.environ.get("ZEUS_TESTED_SHA", result["tested_sha"]) == result["tested_sha"], "native expected SHA differs from checkout")
        before = runner.snapshot(output)
        result["source_snapshot_sha256"] = before["sha256"]
        runner.save(output / "source-manifest.json", before)
        result["source_manifest"] = runner.artifact(output / "source-manifest.json", output)
        feature_map = load(ROOT / "qa/feature-map.json")
        definitions = validate_map(feature_map, runner.portable_module())
        registry = validate_registry(load(ROOT / "qa/regressions.json"), definitions)
        result["map_sha256"] = digest((ROOT / "qa/feature-map.json").read_bytes())
        result["registry_sha256"] = digest((ROOT / "qa/regressions.json").read_bytes())
        selection = [row for row in definitions.values() if row["kind"] in native.NATIVE_KINDS]
        result["native_build"] = runner.compile_native(args, output, before["sha256"])
        if result["native_build"]["status"] == "passed":
            result["native_discovery"] = runner.discover_native(args, output, before["sha256"], selection)
        run_partitions(args, output, result, selection)
        failures = [row["id"] + ": " + row.get("reason", row["status"])
                    for row in result["native_runs"] if row["status"] != "passed"]
        require(not failures, "; ".join(failures))
        compiled = native.validate_discovery_receipt(result["native_discovery"], output, before["sha256"],
                                                     selection, str(ROOT), str(output))
        result["native_summary"] = native.validate_partition_receipts(
            result["native_runs"], output, compiled, selection, args.jobs, str(ROOT), str(output))
        for row in registry:
            if row["check"] in definitions and definitions[row["check"]]["kind"] in native.NATIVE_KINDS:
                native.case_passed(row["guard"], result["native_summary"]["passed_cases"])
        for feature in feature_map["features"]:
            for obligation in feature["obligations"]:
                if definitions[obligation["check"]]["kind"] in native.NATIVE_KINDS:
                    for case in obligation["cases"]:
                        native.case_passed(case, result["native_summary"]["passed_cases"])
        require(runner.snapshot(output) == before, "native source changed during execution")
        require(runner.git("rev-parse", "HEAD") == result["tested_sha"], "native checkout changed during execution")
        result["status"] = "passed"
    except (Invalid, OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
        result["errors"].append(str(error))
    runner.save(output / "result.json", result)
    verified = sum(row.get("tests", 0) for row in result.get("native_runs", []) if row["status"] == "passed")
    print(f"NATIVE status={result['status']} verified_tests={verified} partitions={len(result.get('native_runs', []))}")
    for error in result["errors"]:
        print(error)
    return 0 if result["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
