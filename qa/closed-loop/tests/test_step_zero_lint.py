"""The step-zero wave lint.

The launch flag has one Swift home. The responsibility lookup has one home.
The listed folders do not name StepZero. The probe paths do not log. Tests do
not name the live facts. The repo plist does not carry the marker.
"""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
FLAG = "--step-zero-probe"
FLAG_HOME = "Sources/ZeusCore/StepZero/StepZeroGate.swift"
RESPONSIBILITY = "responsibility_get_pid_responsible_for_pid"
RESPONSIBILITY_HOME = "Sources/Zeus/StepZero/StepZeroProbe.swift"
MARKER = "ZeusStepZeroProbe"
PLIST = "Resources/Info.plist"
SOURCE_SUFFIXES = {".swift", ".m", ".h", ".c"}
LISTED_FOLDERS = (
    "Sources/Zeus/Intent",
    "Sources/Zeus/Voice",
    "Sources/Zeus/Chrome",
    "Sources/Zeus/Agents",
    "Sources/Zeus/App/DeepLinks.swift",
    "Sources/Zeus/App/DebugCommands.swift",
    "Sources/Zeus/App/CommandCenter.swift",
    "Sources/Zeus/App/AppDelegate.swift",
    "Sources/zeus-cli",
    "Sources/zeus-bridge",
    "Sources/zeus-hook",
)
PROBE_PATHS = (
    "Sources/Zeus/StepZero",
    "Sources/ZeusNowPlayingHelper",
    "Sources/zeus-np-plain",
    "Sources/Zeus/LockScreen/LockSpace.swift",
    "Sources/Zeus/Earbuds",
    "Sources/Zeus/TopBar/SystemSourceCanary.swift",
    "Sources/Zeus/TopBar/SpeakerBrowser.swift",
    "Sources/Zeus/SystemFocus/SystemFocusStoreReader.swift",
)
LOG_TOKENS = ("NSLog", "print(", "os_log", "Logger(", "fprintf", "printf(")
LIVE_FACTS = (RESPONSIBILITY, MARKER, "StepZeroProbe")


def files_under(relative):
    """Swift and Objective-C files at a path, or none when the path is absent."""
    path = ROOT / relative
    if not path.exists():
        return []
    if path.is_file():
        candidates = [path]
    else:
        candidates = [child for child in sorted(path.rglob("*")) if child.is_file()]
    return [child for child in candidates if child.suffix in SOURCE_SUFFIXES]


def read_sources(folders):
    found = []
    for folder in folders:
        root = ROOT / folder
        if not root.exists():
            continue
        paths = [root] if root.is_file() else sorted(root.rglob("*"))
        for path in paths:
            if path.is_file() and path.suffix in SOURCE_SUFFIXES:
                found.append((path.relative_to(ROOT).as_posix(), path.read_text(encoding="utf-8")))
    return found


def token_hits(files, token):
    return [path for path, text in files if token in text]


def one_home(files, token, home):
    """Empty, or the one home with the token once."""
    hits = token_hits(files, token)
    if hits == []:
        return True
    if hits != [home]:
        return False
    return dict(files)[home].count(token) == 1


def code_portion(line):
    stripped = line.strip()
    if stripped.startswith("//") or stripped.startswith("/*") or stripped.startswith("*"):
        return ""
    if "//" in line:
        return line.split("//", 1)[0]
    return line


def token_in_code(code, token):
    """True when the token appears as its own call, not as the tail of a longer name."""
    start = 0
    while True:
        index = code.find(token, start)
        if index < 0:
            return False
        if index > 0 and code[index - 1].isalnum():
            start = index + 1
            continue
        return True


def log_offenders(text, label):
    offenders = []
    for number, line in enumerate(text.splitlines(), 1):
        code = code_portion(line)
        for token in LOG_TOKENS:
            if token_in_code(code, token):
                offenders.append("%s:%d:%s" % (label, number, token))
    return offenders


def log_offenders_in_tree():
    offenders = []
    for relative in PROBE_PATHS:
        for path in files_under(relative):
            label = path.relative_to(ROOT).as_posix()
            offenders += log_offenders(path.read_text(encoding="utf-8"), label)
    return offenders


def step_zero_offenders(files):
    return ["%s" % path for path, text in files if "StepZero" in text]


def whole_token(text, token):
    """True when the token is not the tail of a longer name."""
    start = 0
    while True:
        index = text.find(token, start)
        if index < 0:
            return False
        if index > 0 and text[index - 1].isalnum():
            start = index + 1
            continue
        return True


def live_fact_offenders(files):
    offenders = []
    for path, text in files:
        for token in LIVE_FACTS:
            if whole_token(text, token):
                offenders.append("%s:%s" % (path, token))
    return offenders


def list_flag_hits_in(files):
    """Paths whose text holds the launch flag. Zero or one path is the one list."""
    return [path for path, text in files if FLAG in text]


def list_flag_hits():
    files = []
    for folder in ("scripts", "Resources"):
        root = ROOT / folder
        if not root.exists():
            continue
        for path in sorted(root.rglob("*")):
            if path.is_file() and path.suffix in {".sh", ".py", ".plist", ".txt", ".json", ".md", ".yml", ".yaml"}:
                files.append((path.relative_to(ROOT).as_posix(), path.read_text(encoding="utf-8", errors="replace")))
    return list_flag_hits_in(files)


class StepZeroLint(unittest.TestCase):
    def test_flag_has_one_swift_home(self):
        files = read_sources(("Sources", "Tests"))
        hits = token_hits(files, FLAG)
        self.assertTrue(hits == [] or hits == [FLAG_HOME], hits)
        if hits == [FLAG_HOME]:
            self.assertEqual(dict(files)[FLAG_HOME].count(FLAG), 1)

    def test_flag_samples_are_refused(self):
        home = 'public static let flag = "%s"' % FLAG
        self.assertTrue(one_home([(FLAG_HOME, home)], FLAG, FLAG_HOME))
        self.assertFalse(one_home([
            (FLAG_HOME, home),
            ("Sources/Zeus/App/main.swift", FLAG),
        ], FLAG, FLAG_HOME))
        self.assertFalse(one_home([
            ("Tests/ZeusCoreTests/StepZeroGateTests.swift", FLAG),
        ], FLAG, FLAG_HOME))
        self.assertFalse(one_home([(FLAG_HOME, home + "\n" + home)], FLAG, FLAG_HOME))
        self.assertTrue(one_home([("Sources/Other.swift", "ordinary")], FLAG, FLAG_HOME))

    def test_flag_has_one_list(self):
        hits = list_flag_hits()
        self.assertLessEqual(len(hits), 1, hits)

    def test_list_samples_are_refused(self):
        self.assertEqual(list_flag_hits_in([("scripts/bundle.sh", "ordinary")]), [])
        self.assertEqual(
            list_flag_hits_in([("scripts/bundle.sh", "arg = %s" % FLAG)]),
            ["scripts/bundle.sh"],
        )
        two = list_flag_hits_in([
            ("scripts/bundle.sh", FLAG),
            ("scripts/package.sh", FLAG),
        ])
        self.assertEqual(two, ["scripts/bundle.sh", "scripts/package.sh"])
        self.assertGreater(len(two), 1)

    def test_responsibility_name_has_one_home(self):
        files = read_sources(("Sources", "Tests"))
        hits = token_hits(files, RESPONSIBILITY)
        self.assertTrue(hits == [] or hits == [RESPONSIBILITY_HOME], hits)
        if hits == [RESPONSIBILITY_HOME]:
            self.assertEqual(dict(files)[RESPONSIBILITY_HOME].count(RESPONSIBILITY), 1)

    def test_responsibility_samples_are_refused(self):
        home = 'dlsym(handle, "%s")' % RESPONSIBILITY
        self.assertTrue(one_home([(RESPONSIBILITY_HOME, home)], RESPONSIBILITY, RESPONSIBILITY_HOME))
        self.assertFalse(one_home([
            (RESPONSIBILITY_HOME, home),
            (FLAG_HOME, RESPONSIBILITY),
        ], RESPONSIBILITY, RESPONSIBILITY_HOME))
        self.assertFalse(one_home([
            ("Tests/ZeusCoreTests/StepZeroGateTests.swift", RESPONSIBILITY),
        ], RESPONSIBILITY, RESPONSIBILITY_HOME))
        self.assertFalse(one_home([(RESPONSIBILITY_HOME, home + home)], RESPONSIBILITY, RESPONSIBILITY_HOME))
        self.assertTrue(one_home([(FLAG_HOME, "parent pid")], RESPONSIBILITY, RESPONSIBILITY_HOME))

    def test_step_zero_name_stays_out_of_the_listed_folders(self):
        self.assertEqual(step_zero_offenders(read_sources(LISTED_FOLDERS)), [])

    def test_listed_folder_samples_are_refused(self):
        self.assertEqual(step_zero_offenders([
            ("Sources/Zeus/Intent/FastActions.swift", "ordinary"),
        ]), [])
        self.assertEqual(step_zero_offenders([
            ("Sources/Zeus/App/AppDelegate.swift", "StepZeroProbe.runIfRequested()"),
        ]), ["Sources/Zeus/App/AppDelegate.swift"])
        self.assertEqual(step_zero_offenders([
            ("Sources/Zeus/Voice/WakeWordController.swift", "let name = StepZero"),
        ]), ["Sources/Zeus/Voice/WakeWordController.swift"])
        self.assertEqual(step_zero_offenders([
            ("Sources/zeus-cli/main.swift", "StepZero"),
        ]), ["Sources/zeus-cli/main.swift"])

    def test_probe_paths_do_not_log(self):
        self.assertEqual(log_offenders_in_tree(), [])

    def test_log_samples_are_refused(self):
        self.assertEqual(log_offenders("let count = 1\n", "Sources/Zeus/StepZero/FocusSection.swift"), [])
        self.assertEqual(
            log_offenders("print(count)\n", "Sources/Zeus/Earbuds/BluetoothConsent.swift"),
            ["Sources/Zeus/Earbuds/BluetoothConsent.swift:1:print("],
        )
        self.assertEqual(
            log_offenders("NSLog(message)\n", "Sources/Zeus/TopBar/SpeakerBrowser.swift"),
            ["Sources/Zeus/TopBar/SpeakerBrowser.swift:1:NSLog"],
        )
        self.assertEqual(
            log_offenders("os_log(.error, \"x\")\n", "Sources/Zeus/LockScreen/LockSpace.swift"),
            ["Sources/Zeus/LockScreen/LockSpace.swift:1:os_log"],
        )
        self.assertEqual(
            log_offenders("let log = Logger(subsystem: \"zeus\", category: \"probe\")\n",
                          "Sources/Zeus/SystemFocus/SystemFocusStoreReader.swift"),
            ["Sources/Zeus/SystemFocus/SystemFocusStoreReader.swift:1:Logger("],
        )
        self.assertEqual(
            log_offenders("fprintf(stderr, \"x\")\n", "Sources/zeus-np-plain/main.m"),
            ["Sources/zeus-np-plain/main.m:1:fprintf"],
        )
        self.assertEqual(
            log_offenders("printf(\"x\")\n", "Sources/ZeusNowPlayingHelper/ZNPProbe.m"),
            ["Sources/ZeusNowPlayingHelper/ZNPProbe.m:1:printf("],
        )
        self.assertEqual(log_offenders("// print(secret)\n", "Sources/Zeus/StepZero/FocusSection.swift"), [])

    def test_tests_do_not_name_live_facts(self):
        self.assertEqual(live_fact_offenders(read_sources(("Tests",))), [])

    def test_live_fact_samples_are_refused(self):
        self.assertEqual(live_fact_offenders([
            ("Tests/ZeusCoreTests/StepZeroGateTests.swift", "StepZeroGate.decide(facts)"),
        ]), [])
        self.assertEqual(live_fact_offenders([
            ("Tests/ZeusAppTests/StepZeroWriterTests.swift", RESPONSIBILITY),
        ]), ["Tests/ZeusAppTests/StepZeroWriterTests.swift:%s" % RESPONSIBILITY])
        self.assertEqual(live_fact_offenders([
            ("Tests/ZeusAppTests/StepZeroSessionTests.swift", "StepZeroProbe.runIfRequested()"),
        ]), ["Tests/ZeusAppTests/StepZeroSessionTests.swift:StepZeroProbe"])
        self.assertEqual(live_fact_offenders([
            ("Tests/ZeusCoreTests/StepZeroGateTests.swift", MARKER),
        ]), ["Tests/ZeusCoreTests/StepZeroGateTests.swift:%s" % MARKER])

    def test_repo_plist_has_no_marker(self):
        text = (ROOT / PLIST).read_text(encoding="utf-8")
        self.assertNotIn(MARKER, text)
        self.assertNotIn(MARKER + "Until", text)

    def test_plist_marker_sample_is_refused(self):
        sample = "<key>%s</key><true/>" % MARKER
        self.assertIn(MARKER, sample)
        self.assertNotIn(MARKER, "<key>NSBluetoothAlwaysUsageDescription</key>")


if __name__ == "__main__":
    unittest.main()
