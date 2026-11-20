"""One PlacedMark declaration in ZeusCore, and the screen mark's place signature is exact."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
MODIFIERS = {
    "public", "internal", "fileprivate", "private", "open", "package",
    "final", "indirect", "nonisolated", "override", "consuming", "borrowing",
}
KINDS = {"struct", "class", "enum", "actor", "protocol", "typealias"}
PLACE = "public func place(_ marks: [MarkPin]) -> [LaidOutMark]"
DRAWING = "Sources/ZeusCore/Present/DrawingScene.swift"


class InfrastructureError(Exception):
    pass


def strip_swift(text):
    out = []
    i = 0
    limit = len(text)
    while i < limit:
        if text.startswith("//", i):
            newline = text.find("\n", i)
            if newline < 0:
                break
            out.append("\n")
            i = newline + 1
            continue
        if text.startswith("/*", i):
            i = _skip_block_comment(text, i + 2)
            out.append(" ")
            continue
        if text.startswith('"""', i):
            i = _skip_literal(text, i + 3, '"""')
            out.append(" ")
            continue
        if text[i] == '"':
            i = _skip_quoted(text, i + 1)
            out.append(" ")
            continue
        out.append(text[i])
        i += 1
    return "".join(out)


def _skip_block_comment(text, i):
    depth = 1
    limit = len(text)
    while i < limit and depth:
        if text.startswith("/*", i):
            depth += 1
            i += 2
        elif text.startswith("*/", i):
            depth -= 1
            i += 2
        else:
            i += 1
    return i


def _skip_literal(text, i, closer):
    end = text.find(closer, i)
    if end < 0:
        return len(text)
    return end + len(closer)


def _skip_quoted(text, i):
    limit = len(text)
    while i < limit:
        if text[i] == "\\":
            i += 2
            continue
        if text[i] == '"':
            return i + 1
        i += 1
    return limit


def collapse(text):
    return " ".join(text.split())


def declaration_count(text):
    collapsed = collapse(strip_swift(text))
    while True:
        updated = re.sub(r"@[A-Za-z_][A-Za-z0-9_]*(\([^()]*\))?", " ", collapsed)
        if updated == collapsed:
            break
        collapsed = updated
    words = re.sub(r"[^@A-Za-z0-9_]+", " ", collapsed).split()
    count = 0
    for index, word in enumerate(words):
        if word != "PlacedMark" or index == 0:
            continue
        cursor = index - 1
        if words[cursor] not in KINDS:
            continue
        cursor -= 1
        while cursor >= 0 and (words[cursor] in MODIFIERS or words[cursor].startswith("@")):
            cursor -= 1
        count += 1
    return count


def placed_mark_declarations(root):
    found = []
    sources = root / "Sources"
    if not sources.is_dir():
        return found
    for path in sorted(sources.rglob("*.swift")):
        count = declaration_count(path.read_text())
        found.extend([path.relative_to(root).as_posix()] * count)
    return found


def place_signature_is_exact(text):
    collapsed = collapse(strip_swift(text))
    start = collapsed.find(PLACE)
    if start < 0:
        return False
    rest = collapsed[start + len(PLACE):].lstrip(" ")
    return rest[:1] in ("{", "")


def tree_passes(root):
    layout = root / "Sources/ZeusCore/Pointing/MarkLayout.swift"
    return (placed_mark_declarations(root) == [DRAWING]
            and layout.is_file() and place_signature_is_exact(layout.read_text()))


def finish_or_infrastructure(work):
    for attempt in (1, 2):
        try:
            return work()
        except InfrastructureError:
            if attempt == 2:
                raise
    raise InfrastructureError("timeout")


def _tree(directory, files):
    root = Path(directory)
    for name, text in files.items():
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
    return root


class PlacedMarkDeclarationTests(unittest.TestCase):
    def test_zeuscore_declares_placed_mark_once(self):
        self.assertTrue(finish_or_infrastructure(lambda: tree_passes(ROOT)))

    def test_each_survivor_mutant_fails_the_guard(self):
        from tempfile import TemporaryDirectory
        drawing = "public struct PlacedMark {}\n"
        place = "    public func place(_ marks: [MarkPin]) -> [LaidOutMark] {\n        return []\n    }\n"
        base = {
            DRAWING: drawing,
            "Sources/ZeusCore/Pointing/MarkLayout.swift": place,
        }
        mutants = {
            "optional return": ("Sources/ZeusCore/Pointing/MarkLayout.swift",
                                "public func place(_ marks: [MarkPin]) -> [LaidOutMark]? {\n"),
            "missing underscore": ("Sources/ZeusCore/Pointing/MarkLayout.swift",
                                   "public func place(marks: [MarkPin]) -> [LaidOutMark] {\n"),
            "split struct": ("Sources/Zeus/Mac/Extra.swift", "public struct\nPlacedMark {}\n"),
            "comment between name": ("Sources/Zeus/Mac/Extra.swift", "public struct /* name */ PlacedMark {}\n"),
            "package struct": ("Sources/Zeus/Mac/Extra.swift", "package struct PlacedMark {}\n"),
            "indirect enum": ("Sources/Zeus/Mac/Extra.swift", "indirect enum PlacedMark {}\n"),
            "attribute prefix": ("Sources/Zeus/Mac/Extra.swift", "@MainActor public struct PlacedMark {}\n"),
            "protocol": ("Sources/Zeus/Mac/Extra.swift", "public protocol PlacedMark {}\n"),
            "typealias": ("Sources/Zeus/Mac/Extra.swift", "typealias PlacedMark = Int\n"),
            "actor": ("Sources/Zeus/Mac/Extra.swift", "public actor PlacedMark {}\n"),
        }
        for name, (path, text) in mutants.items():
            with self.subTest(mutant=name), TemporaryDirectory() as directory:
                files = dict(base)
                files[path] = text
                self.assertFalse(tree_passes(_tree(directory, files)), name)

    def test_comments_and_strings_are_not_declarations(self):
        samples = [
            "/* public struct PlacedMark {} */\n",
            "// public struct PlacedMark {}\n",
            "let note = \"public struct PlacedMark {}\"\n",
            "let note = \"\"\"\npublic struct PlacedMark {}\n\"\"\"\n",
            "public struct Real {\n /* struct PlacedMark {} */ }\n",
        ]
        for sample in samples:
            self.assertEqual(declaration_count(sample), 0, sample)
        self.assertEqual(declaration_count("public struct PlacedMark {} /* struct PlacedMark {} */\n"), 1)
        self.assertEqual(declaration_count("let s = \"\"\"\nstruct PlacedMark {}\n\"\"\"\npublic struct PlacedMark {}\n"), 1)

    def test_declaration_forms_are_found(self):
        forms = [
            "public struct\nPlacedMark {}",
            "public struct /* name */ PlacedMark {}",
            "package struct PlacedMark {}",
            "indirect enum PlacedMark {}",
            "@MainActor public struct PlacedMark {}",
            "@available(macOS 14, *) public final class PlacedMark {}",
            "public actor PlacedMark {}",
            "protocol PlacedMark {}",
            "typealias PlacedMark = Int",
        ]
        for form in forms:
            self.assertEqual(declaration_count(form), 1, form)

    def test_this_module_adds_no_skip_or_xfail(self):
        text = Path(__file__).read_text()
        banned = [
            "@" + "unittest.skip",
            "unittest.skip" + "(",
            "pytest.mark." + "skip",
            "pytest.mark." + "xfail",
            "expected" + "Failure",
        ]
        for item in banned:
            self.assertNotIn(item, text)

    def test_a_timeout_is_an_infrastructure_error_after_one_retry(self):
        calls = {"n": 0}

        def timed_out():
            calls["n"] += 1
            raise InfrastructureError("timeout")

        with self.assertRaises(InfrastructureError):
            finish_or_infrastructure(timed_out)
        self.assertEqual(calls["n"], 2)
