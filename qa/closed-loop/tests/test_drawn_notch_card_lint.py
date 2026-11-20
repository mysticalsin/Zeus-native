"""The drawn notch's Settings card (docs/NOTCH-DRAWN-NOTCH-PLAN.md, D3): who may send which calibration event.

Each check is a function over source text, so every one has a sample that must fail it.
"""
from pathlib import Path
import json
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
APP = ROOT / "Sources/Zeus"
CARD = APP / "Settings/GSDrawnNotchCard.swift"
PAGES = APP / "Settings/GlanceSettingsPages.swift"
WINDOW = APP / "Settings/SettingsWindow.swift"
MODEL = APP / "Notch/DrawnNotchModel.swift"
CARD_TESTS = ROOT / "Tests/ZeusAppTests/DrawnNotchCardTests.swift"
FEATURE_MAP = ROOT / "qa/feature-map.json"
DASHES = (chr(0x2013), chr(0x2014))

# Calls on the drawn notch's controller only: other state machines (the recording countdown) have a `cancel` too.
CONTROL = r"\b(?:drawnNotch|DrawnNotchModel\.shared|controller)\??\.send\(\s*\.(begin|setWidth|setHeight|setOffset|step|reset|done|cancel)\b"
LOSS_ALLOWED = {CARD.name, WINDOW.name, MODEL.name}


def code_lines(text):
    return [line.split("//")[0] for line in text.splitlines() if not line.strip().startswith("//")]


def code(text):
    return "\n".join(code_lines(text))


def function_body(text, signature):
    start = text.index(signature)
    brace = text.index("{", start)
    depth = 0
    for index in range(brace, len(text)):
        depth += {"{": 1, "}": -1}.get(text[index], 0)
        if depth == 0:
            return text[brace:index]
    raise AssertionError(signature)


def swift_files():
    return sorted(APP.rglob("*.swift"))


def sends_control(text):
    return re.findall(CONTROL, code(text))


def files_sending_control(files):
    return sorted({path.name for path in files if sends_control(path.read_text(encoding="utf-8"))})


def files_sending_loss(files):
    return sorted({path.name for path in files if "surfaceGone(" in code(path.read_text(encoding="utf-8"))})


def card_sends_loss_on_disappear(card_text):
    text = code(card_text)
    if re.search(r"\.onDisappear\s*\{[^}]*\.pageLeft\(\)", text) is None:
        return False
    return ".surfaceGone(.pageLeft)" in function_body(text, "func pageLeft()")


def card_is_placed(pages_text):
    for line in code_lines(pages_text):
        if re.match(r"\s*(?:private |fileprivate )?struct ", line):
            continue
        if re.search(r"\bDrawnNotchCard\s*[({]", line):
            return True
    return False


def has_dash(text):
    return any(dash in text for dash in DASHES)


def window_sends_both_losses(window_text):
    text = code(window_text)
    closed = function_body(text, "func windowWillClose(")
    minimised = function_body(text, "func windowDidMiniaturize(")
    return ".surfaceGone(.settingsClosed)" in closed and ".surfaceGone(.settingsMinimised)" in minimised


class DrawnNotchCardWiring(unittest.TestCase):
    CARD_TEXT = CARD.read_text(encoding="utf-8")

    def test_the_card_sends_page_left_from_on_disappear(self):
        self.assertTrue(card_sends_loss_on_disappear(self.CARD_TEXT))

    def test_calibration_controls_are_sent_from_the_card_file_only(self):
        self.assertEqual(files_sending_control(swift_files()), [CARD.name])

    def test_losses_are_sent_from_three_files_only(self):
        sending = files_sending_loss(swift_files())
        self.assertTrue(set(sending) <= LOSS_ALLOWED, sending)
        self.assertIn(CARD.name, sending)
        self.assertIn(WINDOW.name, sending)

    def test_the_window_controller_sends_both_window_losses(self):
        self.assertTrue(window_sends_both_losses(WINDOW.read_text(encoding="utf-8")))

    def test_the_card_is_placed_on_a_page(self):
        self.assertTrue(card_is_placed(PAGES.read_text(encoding="utf-8")))

    def test_new_card_files_have_no_en_or_em_dash(self):
        for path in (CARD, CARD_TESTS, Path(__file__)):
            self.assertFalse(has_dash(path.read_text(encoding="utf-8")), path.name)

    def test_the_card_suite_is_a_declared_native_fixture(self):
        checks = json.loads(FEATURE_MAP.read_text(encoding="utf-8"))["checks"]
        entry = next((check for check in checks if check["id"] == "native-DrawnNotchCardTests"), None)
        self.assertIsNotNone(entry, "native-DrawnNotchCardTests is not declared")
        self.assertEqual(entry["kind"], "native-fixture")
        self.assertEqual(entry["file"], "Tests/ZeusAppTests/DrawnNotchCardTests.swift")


class DrawnNotchCardLintFailsOnItsFailureShapes(unittest.TestCase):
    """Fail-first samples: each lint must reject the shape it exists to catch."""

    def test_a_card_without_the_disappear_loss_is_caught(self):
        self.assertFalse(card_sends_loss_on_disappear("struct DrawnNotchCard: View { var body: some View { Text(\"x\") } }"))
        self.assertFalse(card_sends_loss_on_disappear(
            "Text(\"x\").onDisappear { model.cancel() }\nfunc pageLeft() { controller.send(.surfaceGone(.pageLeft)) }"))
        self.assertFalse(card_sends_loss_on_disappear(
            "Text(\"x\").onDisappear { model.pageLeft() }\nfunc pageLeft() { controller.send(.cancel) }"))
        self.assertTrue(card_sends_loss_on_disappear(
            "Text(\"x\").onDisappear { model.pageLeft() }\nfunc pageLeft() { controller.send(.surfaceGone(.pageLeft)) }"))

    def test_a_control_sent_from_another_file_is_caught(self):
        self.assertEqual(sends_control("drawnNotch.send(.begin(saved: shape))"), ["begin"])
        self.assertEqual(sends_control("drawnNotch.send(.setWidth(200))"), ["setWidth"])
        self.assertEqual(sends_control("drawnNotch.send(.step(.width, .up))"), ["step"])
        self.assertEqual(sends_control("// drawnNotch.send(.done)"), [])
        self.assertEqual(sends_control("drawnNotch.send(.surfaceGone(.noDisplay))"), [])
        self.assertEqual(sends_control("DrawnNotchModel.shared.send(.reset)"), ["reset"])
        self.assertEqual(sends_control("context.drawnNotch?.send(.cancel)"), ["cancel"])
        self.assertEqual(sends_control("perform(countdown.send(.cancel))"), [])

    def test_a_loss_sent_from_an_unlisted_file_is_caught(self):
        import tempfile
        with tempfile.TemporaryDirectory() as folder:
            stray = Path(folder) / "Stray.swift"
            stray.write_text("model.send(.surfaceGone(.locked))\n", encoding="utf-8")
            self.assertEqual(files_sending_loss([stray]), ["Stray.swift"])
            self.assertFalse(set(files_sending_loss([stray])) <= LOSS_ALLOWED)

    def test_a_window_controller_missing_a_loss_is_caught(self):
        both = ("func windowWillClose(_ n: Notification) { context.drawnNotch?.send(.surfaceGone(.settingsClosed)) }\n"
                "func windowDidMiniaturize(_ n: Notification) { context.drawnNotch?.send(.surfaceGone(.settingsMinimised)) }")
        self.assertTrue(window_sends_both_losses(both))
        self.assertFalse(window_sends_both_losses(both.replace(".settingsMinimised", ".settingsClosed")))
        self.assertFalse(window_sends_both_losses(both.replace(".settingsClosed", ".settingsMinimised")))

    def test_an_unplaced_card_is_caught(self):
        self.assertFalse(card_is_placed("private struct AppearancePage: View { }\n// DrawnNotchCard(model: m)"))
        self.assertFalse(card_is_placed("struct DrawnNotchCard: View {"))
        self.assertTrue(card_is_placed("        DrawnNotchCard(model: model)"))

    def test_a_dash_in_a_card_file_is_caught(self):
        self.assertTrue(has_dash("a " + DASHES[0] + " b"))
        self.assertTrue(has_dash("a " + DASHES[1] + " b"))
        self.assertFalse(has_dash("a - b"))


if __name__ == "__main__":
    unittest.main()
