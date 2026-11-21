"""PlacedMark is one type. A second struct with that name is an invalid redeclaration
and the Mac app target stops at Sources/ZeusCore/Present/DrawingScene.swift.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
DECLARATION = re.compile(
    r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*"
    r"(?:(?:public|internal|fileprivate|private|open|final|nonisolated|indirect)\s+)*"
    r"(?:struct|class|enum|actor|typealias)\s+PlacedMark\b"
)


def _code(line, in_block):
    """Comment text blanked, so a declaration mentioned in prose is not a declaration."""
    out = []
    index = 0
    in_string = False
    escaped = False
    while index < len(line):
        char = line[index]
        nxt = line[index + 1] if index + 1 < len(line) else ""
        if in_block:
            if char == "*" and nxt == "/":
                in_block = False
                out.append("  ")
                index += 2
                continue
            out.append(" ")
            index += 1
            continue
        if in_string:
            out.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            index += 1
            continue
        if char == '"':
            in_string = True
            out.append(char)
            index += 1
            continue
        if char == "/" and nxt == "/":
            out.append(" " * (len(line) - index))
            break
        if char == "/" and nxt == "*":
            in_block = True
            out.append("  ")
            index += 2
            continue
        out.append(char)
        index += 1
    return "".join(out), in_block


def declaration_sites(text, label="sample"):
    sites = []
    in_block = False
    for number, line in enumerate(text.splitlines(), 1):
        code, in_block = _code(line, in_block)
        if DECLARATION.search(code):
            sites.append(f"{label}:{number}")
    return sites


def repository_declarations(root=ROOT):
    found = []
    for path in sorted((root / "Sources").rglob("*.swift")):
        found.extend(declaration_sites(path.read_text(encoding="utf-8"), str(path.relative_to(root))))
    return found


class PlacedMarkDeclaration(unittest.TestCase):
    def test_placed_mark_is_declared_once(self):
        found = repository_declarations()
        self.assertEqual(len(found), 1, "PlacedMark declarations: " + ", ".join(found))

    def test_a_second_declaration_is_reported(self):
        text = "\n".join([
            "public struct PlacedMark: Equatable {}",
            "// public struct PlacedMark {}",
            "extension PlacedMark {}",
            "/* public struct PlacedMark {} */",
            "public struct PlacedMark {}",
        ])
        self.assertEqual(declaration_sites(text), ["sample:1", "sample:5"])

    def test_comments_that_span_lines_are_not_declarations(self):
        text = "/*\npublic struct PlacedMark {}\n*/\npublic struct PlacedMark {}\n"
        self.assertEqual(declaration_sites(text), ["sample:4"])


if __name__ == "__main__":
    unittest.main()
