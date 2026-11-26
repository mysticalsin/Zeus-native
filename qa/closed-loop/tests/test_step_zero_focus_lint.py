"""The step-zero focus lint. The store folder name has one home, and the section never reads a tool result's text."""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
HOME = "Sources/Zeus/SystemFocus/SystemFocusStoreReader.swift"
SECTION = "Sources/Zeus/StepZero/FocusSection.swift"
FOLDER = "DoNotDisturb"
TEXT_FIELDS = (".output", ".error", "standardOutput", "standardError")
SOURCE_SUFFIXES = {".swift", ".m", ".h", ".c"}


def folder_hits(files):
    """Paths under Sources or Tests that contain the store folder name."""
    return [path for path, text in files if FOLDER in text]


def section_text_offenders(text, label=SECTION):
    """Lines where the section reads a tool result's text fields."""
    offenders = []
    for number, line in enumerate(text.splitlines(), 1):
        for field in TEXT_FIELDS:
            if field in line:
                offenders.append("%s:%d:%s" % (label, number, field))
    return offenders


def listed_sources():
    found = []
    for folder in ("Sources", "Tests"):
        root = ROOT / folder
        if not root.exists():
            continue
        for path in sorted(root.rglob("*")):
            if path.is_file() and path.suffix in SOURCE_SUFFIXES:
                found.append((path.relative_to(ROOT).as_posix(), path.read_text(encoding="utf-8")))
    return found


class StepZeroFocusLint(unittest.TestCase):
    def test_folder_name_has_one_home(self):
        hits = folder_hits(listed_sources())
        self.assertTrue(hits == [] or hits == [HOME], hits)
        if hits == [HOME]:
            text = (ROOT / HOME).read_text(encoding="utf-8")
            self.assertEqual(text.count(FOLDER), 1)

    def test_folder_name_samples_are_refused(self):
        home = 'public static let storeDirectory = "%s"' % FOLDER
        self.assertEqual(folder_hits([(HOME, home)]), [HOME])
        self.assertEqual(
            folder_hits([("Sources/Zeus/StepZero/FocusSection.swift", FOLDER)]),
            ["Sources/Zeus/StepZero/FocusSection.swift"],
        )
        self.assertEqual(
            folder_hits([("Tests/ZeusAppTests/SystemFocusStoreReaderTests.swift", FOLDER)]),
            ["Tests/ZeusAppTests/SystemFocusStoreReaderTests.swift"],
        )
        self.assertEqual(
            folder_hits([(HOME, home), ("Sources/Zeus/Onboarding/OnboardingServices.swift", FOLDER)]),
            [HOME, "Sources/Zeus/Onboarding/OnboardingServices.swift"],
        )
        self.assertEqual(folder_hits([("Sources/Other.swift", "Library")]), [])

    def test_section_never_reads_the_tool_result_text(self):
        found = []
        for path, text in listed_sources():
            if path == SECTION:
                found += section_text_offenders(text, path)
        self.assertEqual(found, [])

    def test_section_text_samples_are_refused(self):
        self.assertEqual(section_text_offenders("func childRead(exit: Int) -> ChildRead {\n    exit == 0 ? .yes : .no\n}\n"), [])
        self.assertEqual(
            section_text_offenders("let text = result.output\n"),
            ["%s:1:.output" % SECTION],
        )
        self.assertEqual(
            section_text_offenders("let text = result.error\n"),
            ["%s:1:.error" % SECTION],
        )
        self.assertEqual(
            section_text_offenders("process.standardOutput = pipe\n"),
            ["%s:1:standardOutput" % SECTION],
        )
        self.assertEqual(
            section_text_offenders("process.standardError = pipe\n"),
            ["%s:1:standardError" % SECTION],
        )


if __name__ == "__main__":
    unittest.main()
