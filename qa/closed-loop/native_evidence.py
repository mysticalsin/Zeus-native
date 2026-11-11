"""Qualified Swift Testing wire-v0 evidence; compilation or totals never imply execution."""
from collections import Counter
import json
from pathlib import Path
import re
import native_app_host

from contracts import (ROOT, Invalid, digest, fields, require, runnable_functions, swift_summary,
                       load, source_snapshot, validate_native_build)

NATIVE_KINDS = {"native-fixture", "native-module"}


def partitions(definitions):
    """One Core process, then each explicitly selected app suite in map order."""
    require(type(definitions) is list and definitions, "native partitions missing")
    require(all(row.get("kind") in NATIVE_KINDS for row in definitions), "unknown native partition")
    ids = [row.get("id") for row in definitions]
    require(all(type(ident) is str and ident for ident in ids) and len(set(ids)) == len(ids),
            "native partition IDs are missing or duplicated")
    core = [row for row in definitions if row["kind"] == "native-module"]
    app = [row for row in definitions if row["kind"] == "native-fixture"]
    require(len(core) == 1 and core[0].get("module") == "ZeusCoreTests", "exactly one complete Core partition is required")
    require(all(row.get("file", "").startswith("Tests/ZeusAppTests/") for row in app),
            "only app suites may follow the complete Core partition")
    # selector also rejects duplicate suite selectors, even under distinct IDs.
    selector(definitions)
    return core + app


def module_for(definition):
    return definition["module"] if definition["kind"] == "native-module" else definition["file"].split("/")[1]


def selector(definitions):
    parts = []
    for definition in definitions:
        if definition["kind"] == "native-module":
            require(definition["module"] == "ZeusCoreTests", "only the audited Core module may run in full")
            parts.append(r"^ZeusCoreTests(?:\.|/)")
        elif definition["kind"] == "native-fixture":
            parts.append("^" + module_for(definition) + r"\." + definition["suite"] + "/")
    require(parts and len(parts) == len(set(parts)), "native selection is empty or duplicated")
    return "|".join(parts)


def selected(test_id, definitions):
    return any(re.match(selector([definition]), test_id) for definition in definitions)


def stream(path):
    require(path.is_file() and not path.is_symlink() and path.stat().st_size <= 128 * 1024 * 1024,
            "native event stream missing, redirected or oversized")
    def pairs(items):
        result = {}
        for key, value in items:
            require(key not in result, "duplicate event JSON key")
            result[key] = value
        return result
    rows = []
    for line in path.read_text().splitlines():
        require(bool(line.strip()), "empty native event record")
        row = json.loads(line, object_pairs_hook=pairs,
                         parse_constant=lambda value: (_ for _ in ()).throw(Invalid("nonfinite event JSON")))
        fields(row, {"kind", "payload", "version"})
        require(type(row["version"]) is int and row["version"] == 0, "unsupported Swift Testing event protocol (only wire v0 is reviewed)")
        require(row["kind"] in {"test", "event"} and type(row["payload"]) is dict, "unknown event record shape")
        rows.append(row)
    require(rows, "empty native event stream")
    return rows


def descriptor(payload, repo, recorded_root, *, require_cases=True):
    require(payload.get("kind") == "function", "expected compiled function")
    ident, name, location = payload.get("id"), payload.get("name"), payload.get("sourceLocation")
    require(type(ident) is str and type(name) is str and type(location) is dict, "compiled test identity missing")
    file_id = location.get("fileID")
    require(type(file_id) is str and re.fullmatch(r"Zeus(?:Core|App)Tests/[A-Za-z_0-9.-]+\.swift", file_id), "unexpected compiled test fileID")
    file = "Tests/" + file_id
    path = repo / file
    require(path.is_file() and not path.is_symlink(), "compiled test source is absent or redirected")
    line, column = location.get("line"), location.get("column")
    require(type(line) is int and line > 0 and type(column) is int and column > 0, "compiled test source location invalid")
    require(type(location.get("_filePath")) is str and Path(location["_filePath"]) == Path(recorded_root) / file,
            "compiled file path does not match the recorded checkout and fileID")
    function = name.split("(", 1)[0]
    require(re.fullmatch(r"[A-Za-z_][A-Za-z_0-9]*", function) and "(" in name, "compiled test function name invalid")
    source = path.read_text()
    require(function in runnable_functions(source), "compiled function is not an actual current @Test declaration")
    require(line <= len(source.splitlines()), "compiled source location is outside the current file")
    declarations = re.finditer(r"(?m)^[ \t]*(?:@MainActor[ \t]+)?@Test\b(?:(?!\bfunc\b)[\s\S])*?\bfunc\s+([A-Za-z_][A-Za-z_0-9]*)\s*\(", source)
    matches = []
    for declaration in declarations:
        offset = declaration.start() + declaration.group().index("@Test") + 1
        matches.append((declaration.group(1), source.count("\n", 0, offset) + 1,
                        offset - source.rfind("\n", 0, offset)))
    require(matches.count((function, line, column)) == 1, "compiled test location does not identify its exact current @Test attribute")
    module = file_id.split("/")[0]
    require((ident.startswith(module + ".") or ident.startswith(module + "/"))
            and ident.endswith("/" + path.name + f":{line}:{column}")
            and "/" + name + "/" in ident, "compiled qualified ID conflicts with its source metadata")
    parameterized = payload.get("isParameterized")
    require(type(parameterized) is bool, "compiled parameterized flag missing")
    cases = payload.get("_testCases", [])
    require(type(cases) is list, "compiled parameter cases missing")
    ids = [case.get("id") if type(case) is dict else None for case in cases]
    require(all(type(value) is str and value for value in ids) and len(ids) == len(set(ids)), "compiled parameter cases invalid or duplicated")
    # Swift Testing's `list` discovers functions without evaluating parameter
    # collections. Its execution stream expands them in declarations before
    # runStarted. Only discovery may omit that expansion; execution must supply
    # a nonempty plan, and every planned argument must subsequently finish.
    if require_cases or "_testCases" in payload:
        require(bool(ids) == parameterized, "parameterized tests need a nonempty declared case plan")
    return {"id": ident, "file": file, "function": function, "line": line, "column": column,
            "parameterized": parameterized, "parameter_cases": sorted(ids)}


def discovery(path, definitions, repo=ROOT, recorded_root=None):
    recorded_root = str(repo) if recorded_root is None else recorded_root
    require(Path(recorded_root).is_absolute(), "discovery checkout must be absolute")
    functions, suites = {}, set()
    for row in stream(path):
        require(row["kind"] == "test", "discovery must contain declarations only")
        payload = row["payload"]
        ident = payload.get("id")
        require(type(ident) is str and ident, "discovery ID missing")
        if payload.get("kind") == "suite":
            require(ident not in suites, "duplicate discovery suite")
            suites.add(ident)
        else:
            require(payload.get("kind") == "function", "unknown discovery declaration")
            if selected(ident, definitions):
                require(ident not in functions, "duplicate compiled test ID")
                functions[ident] = descriptor(payload, repo, recorded_root, require_cases=False)
    require(functions, "selection has no compiled tests")
    for definition in definitions:
        require(any(selected(ident, [definition]) for ident in functions), "mapped native selection has no compiled tests")
    # `list` omits implicit structs without @Suite, even though execution emits
    # their suite lifecycle. Authorize only containers already named by selected
    # compiler-discovered functions, including enclosing nested containers.
    for ident in functions:
        container = ident.split("/", 1)[0].split(".")
        suites.update(".".join(container[:length]) for length in range(2, len(container) + 1))
    if any(row["kind"] == "native-module" for row in definitions):
        # The current source inventory is a completeness check, never an executed
        # count. Conditional/unsupported declarations fail closed for review.
        expected = Counter((str(path.relative_to(repo)), name)
                           for path in (repo / "Tests/ZeusCoreTests").glob("*.swift")
                           for name in runnable_functions(path.read_text()))
        actual = Counter((row["file"], row["function"]) for row in functions.values()
                         if row["file"].startswith("Tests/ZeusCoreTests/"))
        require(expected and actual == expected, "compiled Core discovery omitted or invented current @Test declarations")
    return {"functions": functions, "suites": suites}


def execution(path, compiled, definitions, repo=ROOT, recorded_root=None):
    recorded_root = str(repo) if recorded_root is None else recorded_root
    expected = {ident: row for ident, row in compiled["functions"].items() if selected(ident, definitions)}
    require(expected, "native execution has no selected discovery identities")
    allowed_suites = {suite for suite in compiled["suites"]
                      if any(ident.startswith(suite + "/") or ident.startswith(suite + ".") for ident in expected)}
    declared, started, ended = {}, set(), set()
    case_started, case_ended = set(), set()
    suite_started, suite_ended = set(), set()
    runs_started = runs_ended = 0
    for row in stream(path):
        payload = row["payload"]
        if row["kind"] == "test":
            require(runs_started == 0, "runtime declarations must precede runStarted")
            if payload.get("kind") == "suite":
                require(payload.get("id") in compiled["suites"], "execution invented a suite")
            else:
                item = descriptor(payload, repo, recorded_root)
                require(item["id"] in expected, "execution declaration is not a selected compiled identity")
                discovered = expected[item["id"]]
                require({k: v for k, v in item.items() if k != "parameter_cases"}
                        == {k: v for k, v in discovered.items() if k != "parameter_cases"},
                        "execution declaration differs from selected compiled identity")
                if discovered["parameter_cases"]:
                    require(item["parameter_cases"] == discovered["parameter_cases"],
                            "runtime argument plan differs from expanded discovery")
                require(item["id"] not in declared, "duplicate runtime test declaration")
                declared[item["id"]] = item
            continue
        kind = payload.get("kind")
        messages = payload.get("messages", [])
        require(type(messages) is list and all(type(m) is dict for m in messages), "event messages invalid")
        symbols = {m.get("symbol") for m in messages}
        require(not symbols.intersection({"fail", "skip", "knownIssue", "issue"})
                and kind not in {"issueRecorded", "testSkipped"}, "native event contains an issue or skipped test")
        if kind == "runStarted":
            runs_started += 1
            require(runs_started == 1 and runs_ended == 0, "duplicate or unordered run start")
            continue
        require(runs_started == 1 and runs_ended == 0, "event outside its active run")
        if kind == "runEnded":
            require("pass" in symbols, "native run has no successful terminal event")
            runs_ended += 1
            continue
        ident = payload.get("testID")
        require(ident in expected or ident in allowed_suites, "event has an unknown or unselected identity")
        if ident in compiled["suites"]:
            require(kind in {"testStarted", "testEnded"}, "unexpected suite event")
            if kind == "testStarted":
                require(ident not in suite_started, "duplicate suite start")
                suite_started.add(ident)
            else:
                require(ident in suite_started and ident not in suite_ended and "pass" in symbols, "suite did not finish successfully")
                suite_ended.add(ident)
            continue
        require(ident in declared, "test ran without its qualified declaration")
        if kind == "testStarted":
            require(ident not in started, "duplicate test start")
            started.add(ident)
        elif kind in {"testCaseStarted", "testCaseEnded"}:
            case = payload.get("_testCase")
            require(type(case) is dict and case.get("id") in declared[ident]["parameter_cases"], "unknown parameter case")
            key = (ident, case["id"])
            require(ident in started and ident not in ended, "parameter event outside its test")
            if kind == "testCaseStarted":
                require(key not in case_started, "duplicate parameter start")
                case_started.add(key)
            else:
                require(key in case_started and key not in case_ended, "missing or duplicate parameter completion")
                case_ended.add(key)
        elif kind == "testEnded":
            require(ident in started and ident not in ended and "pass" in symbols, "test did not finish successfully")
            ended.add(ident)
        else:
            raise Invalid("unsupported native execution event")
    require(runs_started == runs_ended == 1, "native run is incomplete")
    require(set(declared) == started == ended == set(expected), "compiled selected tests were omitted or did not complete")
    require(suite_started == suite_ended == allowed_suites, "selected native suite was omitted or did not complete")
    cases = {(ident, case) for ident, row in declared.items() for case in row["parameter_cases"]}
    require(case_started == case_ended == cases, "parameterized execution omitted a declared argument case")
    return {"tests": len(expected), "suites": len(suite_ended), "parameter_cases": len(cases),
            "passed_cases": [declared[ident] for ident in sorted(expected)]}


def case_passed(case, passed_cases):
    matches = [row for row in passed_cases if row["file"] == case["file"] and row["function"] == case["function"]]
    require(len(matches) == 1, "required native file/function has no unique qualified executed identity")


def artifact(root, evidence):
    fields(evidence, {"path", "sha256"})
    value = evidence["path"]
    require(type(value) is str and value and not Path(value).is_absolute()
            and not any(x in {".", ".."} for x in Path(value).parts), "native artifact path escapes output")
    root = root.resolve()
    path = root / value
    require(path.resolve() == path and path.is_file(), "native artifact missing or redirected")
    require(digest(path.read_bytes()) == evidence["sha256"], "native artifact hash changed")
    return path


def discovery_command(output_directory):
    return ["swift", "test", "--skip-build", "--event-stream-output-path",
            str(Path(output_directory) / "native-discovery/events.jsonl"), "--event-stream-version", "0", "list"]


def run_command(definitions, jobs, output_directory, ident, recorded_repo=ROOT):
    if native_app_host.selected(definitions):
        return [str(native_app_host.executable(output_directory, ident)),
                "--test-bundle-path", str(native_app_host.bundle_binary(recorded_repo)),
                "--filter", selector(definitions),
                "--event-stream-output-path", str(Path(output_directory) / ident / "events.jsonl"),
                "--event-stream-version", "0"]
    return ["swift", "test", "--skip-build", "--jobs", str(jobs), "--filter", selector(definitions),
            "--event-stream-output-path", str(Path(output_directory) / ident / "events.jsonl"),
            "--event-stream-version", "0"]


def validate_discovery_receipt(receipt, root, source_hash, definitions, recorded_repo, recorded_output, repo=ROOT):
    fields(receipt, {"status", "command", "exit_code", "source_snapshot_sha256", "artifacts", "duration_seconds"}, {"reason"})
    require(receipt["status"] == "passed" and type(receipt["exit_code"]) is int and receipt["exit_code"] == 0,
            "native discovery did not succeed")
    require(receipt["source_snapshot_sha256"] == source_hash, "discovery belongs to other source")
    require(Path(recorded_repo).is_absolute() and Path(recorded_output).is_absolute(), "native recorded directories must be absolute")
    require(receipt["command"] == discovery_command(recorded_output), "native discovery command changed")
    require(type(receipt["artifacts"]) is list, "discovery artifacts missing")
    files = {item.get("path"): artifact(root, item) for item in receipt["artifacts"]}
    require(len(files) == len(receipt["artifacts"]) == 2
            and set(files) == {"native-discovery/test.log", "native-discovery/events.jsonl"}, "discovery artifact set differs")
    return discovery(files["native-discovery/events.jsonl"], definitions, repo, recorded_repo)


def validate_run_receipt(row, root, compiled, definitions, jobs, recorded_repo, recorded_output, repo=ROOT):
    require(row.get("status") == "passed" and type(row.get("exit_code")) is int and row["exit_code"] == 0,
            "native execution did not succeed")
    ident = row["id"]
    require(row.get("command") == run_command(definitions, jobs, recorded_output, ident, recorded_repo), "native execution selector, build jobs or event command changed")
    require(type(row.get("artifacts")) is list, "native run artifacts missing")
    files = {item.get("path"): artifact(root, item) for item in row["artifacts"]}
    require(len(files) == len(row["artifacts"]), "duplicate native artifact")
    require(ident + "/test.log" in files and ident + "/events.jsonl" in files, "native run needs its log and qualified events")
    require(all(name in {ident + "/test.log", ident + "/events.jsonl"} or name.startswith(ident + "/native-artifacts/") for name in files),
            "native artifact is outside its checker")
    if native_app_host.selected(definitions):
        native_app_host.validate_artifacts(files, ident)
    metrics = execution(files[ident + "/events.jsonl"], compiled, definitions, repo, recorded_repo)
    count, suites, _ = swift_summary(files[ident + "/test.log"].read_text(), 0)
    require((count, suites) == (metrics["tests"], metrics["suites"]), "native summary differs from qualified execution")
    for key in ("tests", "suites", "parameter_cases", "passed_cases"):
        if key != "passed_cases":
            require(type(row.get(key)) is int, "native receipt count must be an integer")
        require(row.get(key) == metrics[key], "native receipt differs from qualified execution: " + key)
    require(row.get("passed_functions") == sorted({case["function"] for case in metrics["passed_cases"]}), "native function summary differs from qualified execution")
    return metrics


def validate_partition_receipts(rows, root, compiled, definitions, jobs, recorded_repo, recorded_output, repo=ROOT):
    ordered = partitions(definitions)
    require(type(rows) is list and len(rows) == len(ordered), "native partition receipts are missing or duplicated")
    require([row.get("id") if type(row) is dict else None for row in rows] == [row["id"] for row in ordered],
            "native partition order or selection changed")
    passed = {}
    totals = {"tests": 0, "suites": 0, "parameter_cases": 0}
    for row, definition in zip(rows, ordered):
        require(row.get("kind") == definition["kind"], "native partition kind changed")
        metrics = validate_run_receipt(row, root, compiled, [definition], jobs, recorded_repo, recorded_output, repo)
        for case in metrics["passed_cases"]:
            require(case["id"] not in passed, "native partitions executed a test more than once")
            passed[case["id"]] = case
        for key in totals:
            totals[key] += metrics[key]
    require(set(passed) == set(compiled["functions"]), "native partition union omitted or invented a compiled function")
    require(totals["tests"] == len(passed), "native partition counts disagree with their exact union")
    return {**totals, "passed_cases": [passed[ident] for ident in sorted(passed)]}


def validate_receipt(root, expected_sha, head_sha, definitions, repo=ROOT):
    """Recompute the CI app's complete Core + explicit app selection from raw events."""
    require(not root.is_symlink(), "native evidence root is redirected")
    root = root.resolve()
    result_path = root / "result.json"
    require(result_path.is_file() and not result_path.is_symlink() and result_path.stat().st_size <= 16 * 1024 * 1024,
            "native result missing, redirected or oversized")
    result = load(result_path)
    fields(result, {"schema_version", "status", "tested_sha", "head_sha", "repository", "output_directory", "platform",
                    "source_snapshot_sha256", "source_manifest", "map_sha256", "registry_sha256", "native_build",
                    "native_discovery", "native_runs", "native_summary", "errors"})
    require(type(result["schema_version"]) is int and result["schema_version"] == 2, "unsupported native receipt")
    require(result["status"] == "passed" and result["errors"] == [] and result["platform"] == "darwin", "native run did not pass on macOS")
    require(result["tested_sha"] == expected_sha and result["head_sha"] == head_sha, "native receipt belongs to other source revision")
    require(result["map_sha256"] == digest((repo / "qa/feature-map.json").read_bytes())
            and result["registry_sha256"] == digest((repo / "qa/regressions.json").read_bytes()), "native policy changed after execution")
    manifest = load(artifact(root, result["source_manifest"]))
    require(manifest == source_snapshot(repo, root) and result["source_snapshot_sha256"] == manifest.get("sha256"),
            "native source snapshot differs from current checkout")
    validate_native_build(result["native_build"], root, result["source_snapshot_sha256"])
    compiled = validate_discovery_receipt(result["native_discovery"], root, result["source_snapshot_sha256"],
                                           definitions, result["repository"], result["output_directory"], repo)
    metrics = validate_partition_receipts(result["native_runs"], root, compiled, definitions,
                                          result["native_build"]["command"][4], result["repository"], result["output_directory"], repo)
    fields(result["native_summary"], {"tests", "suites", "parameter_cases", "passed_cases"})
    require(all(type(result["native_summary"][key]) is int for key in ("tests", "suites", "parameter_cases"))
            and result["native_summary"] == metrics, "native summary differs from the verified partition union")
    native_ids = {definition["id"] for definition in definitions}
    for feature in load(repo / "qa/feature-map.json")["features"]:
        for obligation in feature["obligations"]:
            if obligation["check"] in native_ids:
                for case in obligation["cases"]:
                    case_passed(case, metrics["passed_cases"])
    for regression in load(repo / "qa/regressions.json")["regressions"]:
        if regression["check"] in native_ids:
            case_passed(regression["guard"], metrics["passed_cases"])
    return metrics
