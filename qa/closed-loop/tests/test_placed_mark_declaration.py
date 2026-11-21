"""Top-level type names in ZeusCore are unique.

Two `public struct PlacedMark` declarations made `swift build` fail on the Mac app job
(`invalid redeclaration` and `ambiguous` lookup). Nested types and extensions do not count.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
SOURCES = ROOT / "Sources/ZeusCore"
DECLARATION = re.compile(
    r"^\s*(?:(?:public|open|internal|fileprivate|private|package|final|indirect|nonisolated)\s+"
    r"|@[A-Za-z_][A-Za-z0-9_]*(?:\([^()\n]*\))?\s+)*"
    r"(?:struct|class|enum|actor|protocol|typealias)\s+([A-Za-z_][A-Za-z0-9_]*)"
)


def blank_comments(text):
    """Comments become spaces. Newlines stay, so declaration line numbers do too."""
    out = []
    in_string = False
    escaped = False
    triple = False
    in_block = False
    index = 0
    while index < len(text):
        char = text[index]
        nxt = text[index + 1] if index + 1 < len(text) else ""
        nxt2 = text[index + 2] if index + 2 < len(text) else ""
        if in_block:
            if char == "*" and nxt == "/":
                in_block = False
                out.append("  ")
                index += 2
                continue
            out.append("\n" if char == "\n" else " ")
            index += 1
            continue
        if in_string:
            out.append(char)
            if triple:
                if text.startswith('"""', index):
                    out.append('""')
                    in_string = False
                    triple = False
                    index += 3
                    continue
            elif escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            index += 1
            continue
        if char == '"' and nxt == '"' and nxt2 == '"':
            in_string = True
            triple = True
            out.append('"""')
            index += 3
            continue
        if char == '"':
            in_string = True
            out.append(char)
            index += 1
            continue
        if char == "/" and nxt == "/":
            while index < len(text) and text[index] != "\n":
                out.append(" ")
                index += 1
            continue
        if char == "/" and nxt == "*":
            in_block = True
            out.append("  ")
            index += 2
            continue
        out.append(char)
        index += 1
    return "".join(out)


def declaration_sites(text, label="sample"):
    """Top-level type declarations as `label:line Name`. Types nested in braces are skipped."""
    sites = []
    depth = 0
    for number, line in enumerate(blank_comments(text).splitlines(), 1):
        if depth == 0:
            match = DECLARATION.match(line)
            if match:
                sites.append(f"{label}:{number} {match.group(1)}")
        paren = 0
        for char in line:
            if char == "(":
                paren += 1
            elif char == ")":
                paren = max(0, paren - 1)
            elif paren == 0 and char == "{":
                depth += 1
            elif paren == 0 and char == "}":
                depth = max(0, depth - 1)
    return sites


def duplicate_reports(sites):
    grouped = {}
    for site in sites:
        name = site.rsplit(" ", 1)[1]
        grouped.setdefault(name, []).append(site.rsplit(" ", 1)[0])
    reports = []
    for name in sorted(grouped):
        places = grouped[name]
        if len(places) > 1:
            reports.append(name + " at " + ", ".join(places))
    return reports


def repository_duplicates(root=SOURCES):
    sites = []
    for path in sorted(root.rglob("*.swift")):
        sites.extend(declaration_sites(path.read_text(encoding="utf-8"), str(path.relative_to(ROOT))))
    return duplicate_reports(sites)


class ZeusCoreTypeDeclarations(unittest.TestCase):
    def test_zeuscore_top_level_type_names_are_unique(self):
        found = repository_duplicates()
        self.assertEqual(found, [], "duplicate top-level types: " + "; ".join(found))

    def test_a_second_top_level_declaration_is_reported(self):
        text = "\n".join([
            "public struct PlacedMark: Equatable {}",
            "// public struct PlacedMark {}",
            "extension PlacedMark {}",
            "struct Holder {",
            "    struct PlacedMark {}",
            "}",
            "public struct PlacedMark {}",
            "struct Other {}",
        ])
        self.assertEqual(
            duplicate_reports(declaration_sites(text)),
            ["PlacedMark at sample:1, sample:7"],
        )

    def test_a_comment_that_spans_lines_is_not_a_declaration(self):
        text = "/*\npublic struct PlacedMark {}\n*/\npublic struct OnlyOnce {}\n"
        self.assertEqual(duplicate_reports(declaration_sites(text)), [])
        self.assertEqual(declaration_sites(text), ["sample:4 OnlyOnce"])


if __name__ == "__main__":
    unittest.main()
