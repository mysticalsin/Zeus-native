"""The step-zero lock lint. Space names have one home, and the removal name stays in its table."""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
HOME = "Sources/Zeus/LockScreen/LockSpace.swift"
SPACE_TOKENS = (
    "SLSSpace",
    "SLSMainConnectionID",
    "SLSShowSpaces",
    "SLSHideSpaces",
    "CGSSpace",
    "SkyLight.framework",
)
REMOVAL = "SLSRemoveWindowsFromSpaces"
SOURCE_SUFFIXES = {".swift", ".m", ".h", ".c"}


def removal_table_line(line):
    return line.strip() == 'public static let removalCandidate = "%s"' % REMOVAL


def space_token_offenders(files):
    """Paths other than the lock-space file that contain a space token."""
    offenders = []
    for path, text in files:
        if path == HOME:
            continue
        for token in SPACE_TOKENS:
            if token in text:
                offenders.append("%s:%s" % (path, token))
    return offenders


def removal_offenders(files):
    """Lines where the removal name appears outside the one table entry."""
    offenders = []
    for path, text in files:
        for number, line in enumerate(text.splitlines(), 1):
            if REMOVAL not in line:
                continue
            if path != HOME or not removal_table_line(line):
                offenders.append("%s:%d" % (path, number))
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


class StepZeroLockLint(unittest.TestCase):
    def test_space_functions_are_named_in_one_file(self):
        files = listed_sources()
        self.assertEqual(space_token_offenders(files), [])
        home = (ROOT / HOME).read_text(encoding="utf-8")
        for token in ("SLSSpace", "SLSMainConnectionID", "SLSShowSpaces", "SLSHideSpaces", "SkyLight.framework"):
            self.assertIn(token, home)
        self.assertEqual(home.count(REMOVAL), 1)

    def test_space_token_samples_are_refused(self):
        home = "SLSSpace SLSMainConnectionID SLSShowSpaces SLSHideSpaces SkyLight.framework"
        self.assertEqual(space_token_offenders([(HOME, home)]), [])
        self.assertEqual(
            space_token_offenders([("Sources/Other.swift", "let name = SLSSpace")]),
            ["Sources/Other.swift:SLSSpace"],
        )
        self.assertEqual(
            space_token_offenders([("Sources/Other.swift", "CGSSpace")]),
            ["Sources/Other.swift:CGSSpace"],
        )
        self.assertEqual(
            space_token_offenders([("Sources/Other.swift", "SkyLight.framework")]),
            ["Sources/Other.swift:SkyLight.framework"],
        )
        self.assertEqual(space_token_offenders([("Sources/Other.swift", "ordinary")]), [])

    def test_removal_name_is_only_in_the_name_table(self):
        files = listed_sources()
        self.assertEqual(removal_offenders(files), [])
        home = (ROOT / HOME).read_text(encoding="utf-8")
        table_lines = [line for line in home.splitlines() if removal_table_line(line)]
        self.assertEqual(len(table_lines), 1)

    def test_removal_call_samples_are_refused(self):
        table = 'public static let removalCandidate = "%s"' % REMOVAL
        self.assertEqual(removal_offenders([(HOME, table)]), [])
        call = 'dlsym(handle, "%s")' % REMOVAL
        self.assertEqual(removal_offenders([(HOME, call)]), ["%s:1" % HOME])
        self.assertEqual(
            removal_offenders([("Tests/ZeusAppTests/LockSpaceTests.swift", REMOVAL)]),
            ["Tests/ZeusAppTests/LockSpaceTests.swift:1"],
        )
        self.assertEqual(removal_offenders([("Sources/Zeus/LockScreen/LockSpace.swift", "ordinary")]), [])
