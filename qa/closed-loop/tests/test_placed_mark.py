"""One PlacedMark declaration per Swift module. A second one does not compile on macOS."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
MODIFIER = r"(?:public|internal|fileprivate|private|open|final|nonisolated|override)"
KIND = r"(?:struct|class|enum|actor|typealias)"
DECLARATION = re.compile(rf"^\s*(?:{MODIFIER}\s+)*{KIND}\s+PlacedMark\b")
PLACE = re.compile(r"\bfunc\s+place\s*\(\s*_?\s*marks\s*:\s*\[MarkPin\]\s*\)\s*->\s*\[LaidOutMark\]")
ANNOUNCE = re.compile(r"\bfunc\s+announce\s*\(\s*_?\s*placed\s*:\s*\[LaidOutMark\]\s*\)")


def placed_mark_declarations(root):
    found = []
    for path in sorted((root / "Sources").rglob("*.swift")):
        for number, line in enumerate(path.read_text().splitlines(), 1):
            code = line.split("//", 1)[0]
            if DECLARATION.search(code):
                found.append(f"{path.relative_to(root).as_posix()}:{number}")
    return found


def declarations_by_module(found):
    modules = {}
    for item in found:
        parts = item.split("/")
        module = parts[1] if len(parts) > 2 and parts[0] == "Sources" else "?"
        modules.setdefault(module, []).append(item)
    return modules


class PlacedMarkDeclarationTests(unittest.TestCase):
    def test_each_source_module_declares_placed_mark_at_most_once(self):
        found = placed_mark_declarations(ROOT)
        modules = declarations_by_module(found)
        self.assertEqual(list(modules), ["ZeusCore"])
        self.assertEqual(len(modules["ZeusCore"]), 1)
        self.assertTrue(modules["ZeusCore"][0].startswith("Sources/ZeusCore/Present/DrawingScene.swift:"))

    def test_place_returns_laid_out_mark_and_announce_uses_it(self):
        layout = (ROOT / "Sources/ZeusCore/Pointing/MarkLayout.swift").read_text()
        overlay = (ROOT / "Sources/Zeus/Mac/MarkOverlay.swift").read_text()
        self.assertIsNotNone(PLACE.search(layout))
        self.assertIsNotNone(ANNOUNCE.search(overlay))

    def test_each_declaration_kind_is_counted(self):
        from tempfile import TemporaryDirectory
        samples = {
            "struct": "public struct PlacedMark {}\n",
            "class": "public final class PlacedMark {}\n",
            "enum": "enum PlacedMark {}\n",
            "actor": "public actor PlacedMark {}\n",
            "typealias": "typealias PlacedMark = Int\n",
        }
        for kind, source in samples.items():
            with self.subTest(kind=kind), TemporaryDirectory() as directory:
                root = Path(directory)
                folder = root / "Sources/ZeusCore/Present"
                folder.mkdir(parents=True)
                (folder / "Kind.swift").write_text("// struct PlacedMark stays a comment\n" + source)
                found = placed_mark_declarations(root)
                self.assertEqual(found, [f"Sources/ZeusCore/Present/Kind.swift:2"], kind)

    def test_a_second_module_is_counted_separately(self):
        from tempfile import TemporaryDirectory
        with TemporaryDirectory() as directory:
            root = Path(directory)
            core = root / "Sources/ZeusCore/Present"
            mac = root / "Sources/Zeus/Mac"
            core.mkdir(parents=True)
            mac.mkdir(parents=True)
            (core / "DrawingScene.swift").write_text("public struct PlacedMark {}\n")
            (mac / "MarkOverlay.swift").write_text("private class PlacedMark {}\n")
            modules = declarations_by_module(placed_mark_declarations(root))
            self.assertEqual(sorted(modules), ["Zeus", "ZeusCore"])
            self.assertEqual(len(modules["Zeus"]), 1)
            self.assertEqual(len(modules["ZeusCore"]), 1)
            self.assertTrue(modules["Zeus"][0].startswith("Sources/Zeus/Mac/"))

    def test_wrong_signatures_are_not_the_laid_out_mark_contract(self):
        from tempfile import TemporaryDirectory
        with TemporaryDirectory() as directory:
            root = Path(directory)
            layout = root / "Sources/ZeusCore/Pointing"
            overlay = root / "Sources/Zeus/Mac"
            layout.mkdir(parents=True)
            overlay.mkdir(parents=True)
            (layout / "MarkLayout.swift").write_text(
                "public func place(_ marks: [MarkPin]) -> [PlacedMark] {\n")
            (overlay / "MarkOverlay.swift").write_text(
                "private func announce(_ placed: [PlacedMark]) {\n")
            self.assertIsNone(PLACE.search((layout / "MarkLayout.swift").read_text()))
            self.assertIsNone(ANNOUNCE.search((overlay / "MarkOverlay.swift").read_text()))
