#!/usr/bin/env python3
"""Fail when one Swift module declares the same top-level type twice.

Each SwiftPM target is one module. Two module-visible top-level types with
the same name are an invalid redeclaration, and so are two top-level types
with the same name in a single file. A private or fileprivate type may reuse
a name that another file already uses.

Usage:
  scripts/check-duplicate-types.py [PACKAGE_ROOT]

PACKAGE_ROOT defaults to the repository that contains this script. Every
Package.swift under that root is read, except dependency checkouts and build
directories. Exit 0 when clean, 1 when a duplicate is found, 2 on a bad
invocation or an unreadable package.
"""

from __future__ import annotations

import re
import sys
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path

TYPE_KINDS = {"struct", "class", "enum", "protocol", "actor", "typealias"}
MODIFIERS = {
    "public",
    "open",
    "internal",
    "package",
    "private",
    "fileprivate",
    "final",
    "indirect",
    "nonisolated",
    "override",
    "infix",
    "prefix",
    "postfix",
}
FILE_SCOPED = {"private", "fileprivate"}
TARGET_KINDS = {"target", "executableTarget", "testTarget"}


@dataclass(frozen=True)
class Decl:
    name: str
    kind: str
    access: str
    path: str
    line: int
    text: str


def strip_comments_and_strings(text: str, keep_strings: bool = False) -> str:
    """Replace comments and string contents with spaces, keeping newlines."""
    out: list[str] = []
    i = 0
    n = len(text)
    while i < n:
        if text.startswith("//", i):
            j = text.find("\n", i)
            if j < 0:
                out.append(" " * (n - i))
                break
            out.append(" " * (j - i))
            out.append("\n")
            i = j + 1
            continue
        if text.startswith("/*", i):
            j = text.find("*/", i + 2)
            if j < 0:
                out.append(re.sub(r"[^\n]", " ", text[i:]))
                break
            chunk = text[i : j + 2]
            out.append(re.sub(r"[^\n]", " ", chunk))
            i = j + 2
            continue
        if text.startswith('"""', i):
            j = text.find('"""', i + 3)
            if j < 0:
                chunk = text[i:]
            else:
                chunk = text[i : j + 3]
            if keep_strings:
                out.append(chunk)
            else:
                out.append(re.sub(r"[^\n]", " ", chunk))
            if j < 0:
                break
            i = j + 3
            continue
        if text[i] in "\"'":
            quote = text[i]
            j = i + 1
            while j < n:
                if text[j] == "\\":
                    j += 2
                    continue
                if text[j] == quote:
                    j += 1
                    break
                j += 1
            if keep_strings:
                out.append(text[i:j])
            else:
                out.append(re.sub(r"[^\n]", " ", text[i:j]))
            i = j
            continue
        out.append(text[i])
        i += 1
    return "".join(out)


def skip_parens(line: str, i: int) -> int:
    depth = 0
    while i < len(line):
        if line[i] == "(":
            depth += 1
        elif line[i] == ")":
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return i


def match_type_decl(line: str) -> tuple[str, str, str] | None:
    """Return (kind, name, access) when line declares a top-level type."""
    i = 0
    n = len(line)
    while True:
        while i < n and line[i].isspace():
            i += 1
        if i >= n or line[i] != "@":
            break
        i += 1
        while i < n and (line[i].isalnum() or line[i] == "_"):
            i += 1
        if i < n and line[i] == "(":
            i = skip_parens(line, i)
    modifiers: list[str] = []
    while i < n:
        match = re.match(r"[A-Za-z_]+", line[i:])
        if not match:
            return None
        word = match.group(0)
        if word in TYPE_KINDS:
            j = i + len(word)
            name = re.match(r"\s+([A-Za-z_][A-Za-z0-9_]*)", line[j:])
            if not name:
                return None
            access = "internal"
            for modifier in modifiers:
                if modifier in FILE_SCOPED or modifier in {"public", "open", "package", "internal"}:
                    access = modifier
            return word, name.group(1), access
        if word not in MODIFIERS:
            return None
        modifiers.append(word)
        i += len(word)
        while i < n and line[i].isspace():
            i += 1
        if i < n and line[i] == "(":
            i = skip_parens(line, i)
    return None


def top_level_types(text: str, rel: str) -> list[Decl]:
    cleaned = strip_comments_and_strings(text)
    decls: list[Decl] = []
    depth = 0
    for lineno, raw in enumerate(cleaned.splitlines(), 1):
        stripped = raw.strip()
        if depth == 0 and stripped and not stripped.startswith("#"):
            found = match_type_decl(stripped)
            if found:
                kind, name, access = found
                decls.append(Decl(name, kind, access, rel, lineno, stripped[:160]))
        if not stripped.startswith("#"):
            depth += raw.count("{") - raw.count("}")
            if depth < 0:
                depth = 0
    return decls


def target_bodies(package_text: str) -> list[tuple[str, str]]:
    """Return (kind, argument-body) for each SwiftPM target declaration."""
    cleaned = strip_comments_and_strings(package_text, keep_strings=True)
    found: list[tuple[str, str]] = []
    for match in re.finditer(r"\.(target|executableTarget|testTarget)\(", cleaned):
        kind = match.group(1)
        i = match.end()
        depth = 1
        start = i
        while i < len(cleaned) and depth:
            if cleaned[i] == "(":
                depth += 1
            elif cleaned[i] == ")":
                depth -= 1
            i += 1
        found.append((kind, cleaned[start : i - 1]))
    return found


def module_roots(package_path: Path) -> list[tuple[str, Path]]:
    text = package_path.read_text(encoding="utf-8")
    package_root = package_path.parent
    modules: list[tuple[str, Path]] = []
    for kind, body in target_bodies(text):
        if kind not in TARGET_KINDS:
            continue
        name_match = re.search(r'name:\s*"([^"]+)"', body)
        if not name_match:
            raise ValueError(f"{package_path}: a {kind} is missing name")
        name = name_match.group(1)
        path_match = re.search(r'path:\s*"([^"]+)"', body)
        if path_match:
            directory = package_root / path_match.group(1)
        elif kind == "testTarget":
            directory = package_root / "Tests" / name
        else:
            directory = package_root / "Sources" / name
        modules.append((name, directory))
    return modules


def discover_packages(root: Path) -> list[Path]:
    packages: list[Path] = []
    for path in root.rglob("Package.swift"):
        if any(part in {".build", ".git", "checkouts", ".swiftpm"} for part in path.parts):
            continue
        packages.append(path)
    return sorted(packages)


def duplicate_groups(decls: list[Decl]) -> list[list[Decl]]:
    by_name: dict[str, list[Decl]] = defaultdict(list)
    for decl in decls:
        by_name[decl.name].append(decl)
    groups: list[list[Decl]] = []
    for name in sorted(by_name):
        group = by_name[name]
        visible = [decl for decl in group if decl.access not in FILE_SCOPED]
        seen: set[tuple[str, int]] = set()
        if len(visible) >= 2:
            groups.append(sorted(visible, key=lambda decl: (decl.path, decl.line)))
            seen.update((decl.path, decl.line) for decl in visible)
        by_file: dict[str, list[Decl]] = defaultdict(list)
        for decl in group:
            by_file[decl.path].append(decl)
        for path in sorted(by_file):
            same_file = by_file[path]
            if len(same_file) >= 2 and not all((decl.path, decl.line) in seen for decl in same_file):
                groups.append(sorted(same_file, key=lambda decl: decl.line))
    return groups


def scan(root: Path) -> tuple[int, list[str]]:
    lines: list[str] = []
    module_count = 0
    for package in discover_packages(root):
        try:
            modules = module_roots(package)
        except (OSError, ValueError) as error:
            return 2, [str(error)]
        for name, directory in modules:
            module_count += 1
            if not directory.is_dir():
                return 2, [f"{package}: target {name} directory does not exist: {directory}"]
            decls: list[Decl] = []
            for source in sorted(directory.rglob("*.swift")):
                if any(part in {".build", "checkouts"} for part in source.parts):
                    continue
                rel = source.relative_to(root).as_posix()
                decls.extend(top_level_types(source.read_text(encoding="utf-8"), rel))
            for group in duplicate_groups(decls):
                lines.append(f"duplicate top-level type {group[0].name} in {name}")
                for decl in group:
                    lines.append(f"  {decl.path}:{decl.line}: {decl.access} {decl.kind} {decl.name}")
    if lines:
        return 1, lines
    noun = "Swift module" if module_count == 1 else "Swift modules"
    return 0, [f"no duplicate top-level types ({module_count} {noun})"]


def main(argv: list[str]) -> int:
    if len(argv) > 2 or (len(argv) == 2 and argv[1] in {"-h", "--help"}):
        print(__doc__.strip(), file=sys.stderr if len(argv) > 2 else sys.stdout)
        return 0 if len(argv) == 2 else 2
    root = Path(argv[1]).resolve() if len(argv) == 2 else Path(__file__).resolve().parent.parent
    if not root.is_dir():
        print(f"not a directory: {root}", file=sys.stderr)
        return 2
    status, lines = scan(root)
    stream = sys.stdout if status == 0 else sys.stderr
    print("\n".join(lines), file=stream)
    return status


if __name__ == "__main__":
    sys.exit(main(sys.argv))
