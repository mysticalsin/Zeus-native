"""Strict, dependency-free validation for Zeus's finite acceptance matrix.

This validates our versioned schema and semantic cross-references, not arbitrary
JSON Schema. The adjacent *.schema.json files document the wire format.
"""
import hashlib
import json
import os
import re
import subprocess
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[2]
FEATURE_IDS = {f"F{i:02}" for i in range(1, 14)} | {f"S{i:02}" for i in range(1, 7)}
TIERS = {"contract", "native-integration", "device-proof"}
STATUSES = {"passed", "failed", "blocked", "not-run", "unimplemented"}


class Invalid(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise Invalid(message)


def fields(obj, required, optional=()):
    require(type(obj) is dict, "expected object")
    require(set(required) <= obj.keys(), f"missing fields: {set(required) - obj.keys()}")
    require(obj.keys() <= set(required) | set(optional), f"unknown fields: {obj.keys() - set(required) - set(optional)}")


def nonempty(value):
    require(type(value) is str and bool(value.strip()), "expected nonempty string")


def relative_file(path, root=ROOT):
    nonempty(path)
    value = PurePosixPath(path)
    require(not value.is_absolute() and ".." not in value.parts and "\\" not in path, "unsafe path")
    target = (root / path).resolve()
    require(target.is_relative_to(root.resolve()) and target.is_file(), f"missing or escaping file: {path}")
    return target


def unique(items, key):
    require(type(items) is list and bool(items), "expected nonempty array")
    ids = [item.get(key) if type(item) is dict else None for item in items]
    require(all(type(i) is str and i for i in ids), f"invalid {key}")
    require(len(set(ids)) == len(ids), f"duplicate {key}")


def digest(data):
    return hashlib.sha256(data).hexdigest()


def source_snapshot(root, output):
    # macOS temporary paths may enter through /var and resolve under /private/var.
    # Normalize the owned output root, not arbitrary child symlinks in inputs.
    output = output.resolve()
    paths = subprocess.check_output(["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"], cwd=root).decode().split("\0")
    files = []
    for name in sorted(set(paths) - {""}):
        path = root / name
        if path.resolve().is_relative_to(output) or "__pycache__" in path.parts or path.suffix == ".pyc":
            continue
        relative = PurePosixPath(name)
        # Build/check inputs, not handoff prose or prior evidence. Excluding
        # receipts avoids a self-referential hash when a result is archived.
        # All Sources/resources and Tests remain included regardless of suffix.
        if relative.parts[0] == "docs" or name.startswith("qa/receipts/"):
            continue
        if (len(relative.parts) == 1 and path.suffix == ".md") or (name.startswith("qa/") and path.suffix == ".md"):
            continue
        # Hash symlink identity rather than dereferencing unrelated data.
        value = digest(os.readlink(path).encode()) if path.is_symlink() else digest(path.read_bytes()) if path.is_file() else "missing"
        files.append({"path": name, "sha256": value})
    return {"sha256": digest(json.dumps(files, sort_keys=True, separators=(",", ":")).encode()), "files": files}


def load(path):
    # Duplicate JSON keys are otherwise silently replaced, including a failed status.
    def pairs(items):
        obj = {}
        for key, value in items:
            require(key not in obj, f"duplicate JSON key: {key}")
            obj[key] = value
        return obj
    return json.loads(Path(path).read_text(), object_pairs_hook=pairs)


def validate_compiler_log(text):
    """Require compiler completion and reject diagnostic headers, not source excerpts."""
    require(re.search(r"(?m)^Build complete!(?: \([^\n]*\))?\s*$", text),
            "native compiler log has no completion")
    for raw in text.splitlines():
        line = re.sub(r"\x1b\[[0-9;]*m", "", raw).strip()
        # Swift prints source/caret gutters below warnings. An argument such as
        # converter.convert(to: output, error: &error) is not a diagnostic.
        if re.match(r"(?:\d+)?\s*\|", line):
            continue
        failure = re.match(
            r"(?:(?:.*?:\d+(?::\d+)?:|(?:swift(?:c|-frontend)?|clang(?:\+\+)?|ld|ld64|<unknown>):)\s*)?"
            r"(?:error|fatal error|internal error):", line, re.IGNORECASE)
        require(not failure and not re.match(r"CHECK (?:TIMEOUT|COULD NOT START)\b", line),
                "native compiler log contains failure")


def validate_native_build(build, output, source_hash, jobs=None):
    """Only fresh, intact compiler success may authorize native --skip-build."""
    fields(build, {"status", "command", "exit_code", "source_snapshot_sha256", "artifacts", "duration_seconds"}, {"reason"})
    require(build["status"] == "passed" and type(build["exit_code"]) is int and build["exit_code"] == 0,
            "native compiler barrier did not pass")
    command = build["command"]
    require(type(command) is list and len(command) == 5 and command[:4] == ["swift", "build", "--build-tests", "--jobs"]
            and type(command[4]) is str and command[4].isdigit() and int(command[4]) > 0,
            "native compiler barrier command is not allowlisted")
    require(jobs is None or command[4] == str(jobs), "native compiler barrier job count changed")
    require(build["source_snapshot_sha256"] == source_hash, "native compiler barrier belongs to other source")
    require(type(build["duration_seconds"]) in {int, float} and build["duration_seconds"] >= 0,
            "native compiler barrier duration is invalid")
    require(type(build["artifacts"]) is list and len(build["artifacts"]) == 1, "native compiler barrier needs its compiler log")
    evidence = build["artifacts"][0]
    fields(evidence, {"path", "sha256"})
    require(evidence["path"] == "native-build/build.log", "native compiler barrier has an unexpected log")
    root = output.resolve()
    log = root / evidence["path"]
    require(not log.is_symlink() and not log.parent.is_symlink() and log.resolve().is_relative_to(root),
            "native compiler log is redirected")
    require(log.is_file() and digest(log.read_bytes()) == evidence["sha256"], "native compiler log is missing or changed")
    validate_compiler_log(log.read_text())


def runnable_functions(text, python=False):
    if python:
        return re.findall(r"(?m)^\s*def\s+(test_[A-Za-z_0-9]+)\s*\(", text)
    # This is intentionally conservative, not a Swift parser. Require the actual
    # @Test declaration, not a same-named ordinary helper. Ambiguity fails closed.
    return re.findall(r"(?m)^[ \t]*(?:@MainActor[ \t]+)?@Test\b(?:(?!\bfunc\b)[\s\S])*?\bfunc\s+([A-Za-z_][A-Za-z_0-9]*)\s*\(", text)


def validate_case(case, root=ROOT):
    fields(case, {"file", "function"})
    file = relative_file(case["file"], root)
    require(case["file"].startswith(("Tests/ZeusCoreTests/", "Tests/ZeusAppTests/")) or case["file"] in {
        "qa/release-scripts/test_release_scripts.py", "qa/closed-loop/tests/test_gate.py", "qa/closed-loop/tests/test_contracts.py",
        "qa/closed-loop/tests/test_native_evidence.py", "qa/closed-loop/tests/test_native_processes.py"}, "case must be a repository test")
    require(type(case["function"]) is str and re.fullmatch(r"[A-Za-z_][A-Za-z_0-9]*", case["function"]), "invalid test function")
    require(runnable_functions(file.read_text(), file.suffix == ".py").count(case["function"]) == 1, f"runnable test removed or ambiguous: {case}")


def validate_map(data, portable, root=ROOT):
    fields(data, {"schema_version", "scope", "checks", "features"})
    require(type(data["schema_version"]) is int and data["schema_version"] == 1, "unsupported map version")
    nonempty(data["scope"])
    unique(data["checks"], "id")
    checks = {c["id"]: c for c in data["checks"]}
    for check in checks.values():
        fields(check, {"id", "kind", "tier", "scope"}, {"group", "suite", "file", "reason", "module"})
        nonempty(check["scope"])
        nonempty(check["kind"])
        nonempty(check["tier"])
        require(check["tier"] in TIERS, "invalid evidence tier")
        if check["kind"] == "portable":
            require(set(check) == {"id", "kind", "tier", "scope", "group"}, "invalid portable fields")
            nonempty(check["group"])
            require(check["tier"] == "contract" and check["group"] in portable.GROUPS and check["group"] != "wiki", "unknown or unsuitable default portable group")
        elif check["kind"] == "native-fixture":
            require(set(check) == {"id", "kind", "tier", "scope", "suite", "file"}, "invalid native fields")
            require(check["tier"] == "native-integration", "native fixtures cannot establish device proof")
            file = relative_file(check["file"], root)
            require(check["file"].startswith(("Tests/ZeusAppTests/", "Tests/ZeusCoreTests/")), "native fixture must be a test")
            nonempty(check["suite"])
            require(re.fullmatch(r"[A-Za-z][A-Za-z0-9]*Tests", check["suite"]), "invalid suite selector")
            require(re.search(r"\b(?:struct|class)\s+" + check["suite"] + r"\b", file.read_text()), "missing native suite")
        elif check["kind"] == "native-module":
            require(set(check) == {"id", "kind", "tier", "scope", "module"}, "invalid native module fields")
            require(check["tier"] == "native-integration" and check["module"] == "ZeusCoreTests",
                    "only audited ZeusCoreTests may run as a complete native module")
        elif check["kind"] == "release-mocks":
            require(set(check) == {"id", "kind", "tier", "scope"} and check["tier"] == "contract", "release mocks are contract evidence only")
        elif check["kind"] == "unimplemented":
            require(set(check) == {"id", "kind", "tier", "scope", "reason"}, "invalid unimplemented fields")
            nonempty(check["reason"])
        else:
            raise Invalid("unknown checker kind; no arbitrary commands or imported pass receipts")
    groups = [c["group"] for c in checks.values() if c["kind"] == "portable"]
    require(len(groups) == len(set(groups)), "duplicate portable group")
    require(set(groups) == set(portable.GROUPS) - {"wiki"}, "every default portable group must execute")
    unique(data["features"], "id")
    require({f["id"] for f in data["features"]} == FEATURE_IDS, "all 13 Friday and 6 Sunday items are mandatory")
    used_checks, obligation_ids = set(), set()
    for feature in data["features"]:
        fields(feature, {"id", "title", "obligations"})
        nonempty(feature["title"])
        unique(feature["obligations"], "id")
        tiers = set()
        for obligation in feature["obligations"]:
            fields(obligation, {"id", "check", "acceptance", "cases"})
            require(obligation["id"].startswith(feature["id"] + "."), "obligation belongs to wrong feature")
            require(obligation["id"] not in obligation_ids, "duplicate obligation")
            obligation_ids.add(obligation["id"])
            nonempty(obligation["acceptance"])
            require(obligation["check"] in checks, "unknown obligation checker")
            check = checks[obligation["check"]]
            tiers.add(check["tier"])
            used_checks.add(check["id"])
            require(type(obligation["cases"]) is list, "cases must be array")
            require(bool(obligation["cases"]) == (check["kind"] != "unimplemented"), "implemented obligations need actual cases; unimplemented cannot claim them")
            for case in obligation["cases"]:
                validate_case(case, root)
                if check["kind"] == "native-fixture":
                    require(case["file"] == check["file"], "case not in native fixture")
                elif check["kind"] == "native-module":
                    require(case["file"].startswith("Tests/ZeusCoreTests/"), "case not in the complete Core module")
                elif check["kind"] == "portable":
                    # Exact excerpt membership is checked against the prepared manifest.
                    require(case["file"].startswith(("Tests/ZeusCoreTests/", "Tests/ZeusAppTests/")), "portable case must be selected real repository test")
                else:
                    require(case["file"] == "qa/release-scripts/test_release_scripts.py", "release case not in mock suite")
        require(TIERS <= tiers, f"{feature['id']} needs contract, native integration, and device proof obligations")
    require(used_checks == checks.keys(), "orphan checker not used by feature map")
    modules = [check for check in checks.values() if check["kind"] == "native-module"]
    require(len(modules) == 1, "exactly one complete audited Core module checker is required")
    require(not any(c["kind"] == "native-fixture" and c["file"].startswith("Tests/ZeusCoreTests/") for c in checks.values()),
            "named Core obligations must bind to complete Core execution, not duplicate narrow runs")
    return checks


def validate_registry(data, checks, root=ROOT):
    fields(data, {"schema_version", "policy", "regressions"})
    require(type(data["schema_version"]) is int and data["schema_version"] == 1, "unsupported registry version")
    nonempty(data["policy"])
    unique(data["regressions"], "id")
    for row in data["regressions"]:
        fields(row, {"id", "failure", "features", "check", "guard"})
        nonempty(row["failure"])
        require(type(row["features"]) is list and bool(row["features"]) and set(row["features"]) <= FEATURE_IDS, "invalid regression feature reference")
        require(row["check"] == "closed-loop-selftests" or (row["check"] in checks and checks[row["check"]]["kind"] != "unimplemented"), "regression needs an executable guard")
        validate_case(row["guard"], root)
        if row["check"] == "closed-loop-selftests":
            require(row["guard"]["file"].startswith("qa/closed-loop/tests/"), "selftest guard not in runner test suite")
        elif checks[row["check"]]["kind"] == "native-fixture":
            require(row["guard"]["file"] == checks[row["check"]]["file"], "guard not in selected native suite")
        elif checks[row["check"]]["kind"] == "native-module":
            require(row["guard"]["file"].startswith("Tests/ZeusCoreTests/"), "guard not in complete Core module")
    return data["regressions"]


def swift_summary(log, returncode):
    summaries = re.findall(r"Test run with (\d+) tests? in (\d+) suites? (passed|failed)", log)
    require(returncode == 0, f"command exited {returncode}")
    require(len(summaries) == 1, "missing or ambiguous Swift Testing summary")
    count, suites, status = summaries[0]
    require(status == "passed" and int(count) > 0 and int(suites) > 0, "zero, failed, or skipped-only tests cannot pass")
    require(not re.search(r"(?:✘|Test run .* failed|[1-9]\d* failures?)", log), "failure diagnostic in otherwise passing log")
    functions = sorted(set(re.findall(r"✔ Test ([A-Za-z_][A-Za-z_0-9]*)\([^\n]*\) passed after", log)))
    require(functions, "no passed test cases")
    return int(count), int(suites), functions


def manifest_matches(actual_root, expected_root):
    """Compare a fresh deterministic re-generation, including every compiled byte.

    Comparing only listed hashes lets a forged/omitted manifest or edited generated
    excerpt pass. Ignore only SwiftPM's generated build/cache files and test.log.
    """
    def files(root):
        result = {}
        for p in root.rglob("*"):
            name = str(p.relative_to(root))
            if not p.is_file() or p.relative_to(root).parts[0] in {".build", ".swiftpm"} or name == "test.log":
                continue
            data = p.read_bytes()
            if name == "validation-manifest.json":
                manifest = load(p)
                require(type(manifest.get("repository")) is str, "invalid manifest repository metadata")
                # The checkout location differs across CI OS/jobs. Normalize only
                # this non-input metadata; hashes, platform and every byte of all
                # compiled/package files still compare exactly.
                manifest["repository"] = "<checkout>"
                data = json.dumps(manifest, sort_keys=True, separators=(",", ":")).encode()
            result[name] = digest(data)
        return result
    require(files(actual_root) == files(expected_root), "portable manifest or compiled source differs from current exact-source recipe")


def case_passed(case, check, output, root=ROOT):
    require(check["status"] == "passed", "checker did not pass")
    if check.get("kind") in {"native-fixture", "native-module"}:
        from native_evidence import case_passed as qualified_case_passed
        qualified_case_passed(case, check.get("passed_cases", []))
        return
    require(case["function"] in check.get("passed_functions", []), f"required case did not run: {case['function']}")
    if "package" in check:
        # Test definitions must be among the exact copied/selected excerpt bytes.
        package = output / check["package"]
        manifest = load(package / "validation-manifest.json")
        full = {f["source"] for f in manifest["files"]}
        excerpts = [e for e in manifest["excerpts"] if e["source"] == case["file"]]
        present = case["file"] in full
        for excerpt in excerpts:
            source = (root / case["file"]).read_text()
            start = source.index(excerpt["start"])
            end = len(source) if excerpt["end_exclusive"] == "EOF" else source.index(excerpt["end_exclusive"], start)
            present |= bool(re.search(r"\bfunc\s+" + re.escape(case["function"]) + r"\s*\(", source[start:end]))
        require(present, f"test not included in compiled snapshot: {case['file']}")
        selected = list((package / "Tests").rglob("*.swift"))
    elif check.get("kind") == "selftests":
        selected = list((root / "qa/closed-loop/tests").glob("test_*.py"))
    else:
        selected = [root / case["file"]]
    count = sum(runnable_functions(p.read_text(), p.suffix == ".py").count(case["function"]) for p in selected)
    require(count == 1, f"passed log identity is ambiguous or not runnable in selected sources: {case['function']}")


def evaluate_features(feature_map, checks, output):
    rows = []
    for feature in feature_map["features"]:
        obligations = []
        for obligation in feature["obligations"]:
            check = checks.get(obligation["check"], {"status": "not-run", "reason": "Missing checker result"})
            status, reason = check["status"], check.get("reason", "")
            if status == "passed":
                try:
                    for case in obligation["cases"]:
                        case_passed(case, check, output)
                except (Invalid, OSError, ValueError) as error:
                    status, reason = "failed", str(error)
            obligations.append({"id": obligation["id"], "check": obligation["check"], "status": status, "reason": reason})
        rows.append({"id": feature["id"], "title": feature["title"],
                     "status": "passed" if all(o["status"] == "passed" for o in obligations) else "incomplete",
                     "obligations": obligations})
    return rows
