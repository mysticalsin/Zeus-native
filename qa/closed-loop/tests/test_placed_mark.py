"""ZeusCore may declare PlacedMark once. A second declaration does not compile on macOS."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
STRUCT = re.compile(r"^\s*(?:public\s+|internal\s+|fileprivate\s+|private\s+|open\s+)?struct\s+PlacedMark\b")


def placed_mark_structs(root):
    found = []
    for path in sorted((root / "Sources/ZeusCore").rglob("*.swift")):
        for number, line in enumerate(path.read_text().splitlines(), 1):
            code = line.split("//", 1)[0]
            if STRUCT.search(code):
                found.append(f"{path.relative_to(root).as_posix()}:{number}")
    return found


class PlacedMarkDeclarationTests(unittest.TestCase):
    def test_zeuscore_declares_placed_mark_once(self):
        found = placed_mark_structs(ROOT)
        self.assertEqual(len(found), 1)
        self.assertTrue(found[0].startswith("Sources/ZeusCore/Present/DrawingScene.swift:"))

    def test_mark_layout_names_its_own_type(self):
        text = (ROOT / "Sources/ZeusCore/Pointing/MarkLayout.swift").read_text()
        self.assertIn("struct LaidOutMark", text)
        self.assertNotRegex(text, r"\bstruct\s+PlacedMark\b")

    def test_a_second_declaration_is_reported(self):
        # The scan is what the guard runs. Two structs in one tree must both be named.
        from tempfile import TemporaryDirectory
        with TemporaryDirectory() as directory:
            root = Path(directory)
            core = root / "Sources/ZeusCore/Present"
            core.mkdir(parents=True)
            (core / "One.swift").write_text("public struct PlacedMark {}\n")
            (core / "Two.swift").write_text("// struct PlacedMark in a comment is not a declaration\npublic struct PlacedMark {}\n")
            found = placed_mark_structs(root)
            self.assertEqual(len(found), 2)
