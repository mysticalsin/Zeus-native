"""The meeting card (docs/MEETING-START-PLAN.md, MS5) is a view of one value and owns no clock.

The countdown ring is one linear animation keyed on the deadline, so the per-second redraw of the digit never
restarts it. A Timer, TimelineView or repeating animation would run with nothing to show. The panel is the only
thing that puts the card on screen, and it takes the card down only inside `render`.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
VIEW = ROOT / "Sources/Zeus/Scribe/ScribeMeetingCardView.swift"
PANEL = ROOT / "Sources/Zeus/Scribe/ScribeMeetingCardPanel.swift"
FORBIDDEN = re.compile(r"\bTimer\b|\bTimelineView\b|\.repeatForever\b|\bCVDisplayLink\b|\bCADisplayLink\b")
DASH = re.compile("[" + chr(0x2013) + chr(0x2014) + "]")


def code_lines(text):
    for number, line in enumerate(text.splitlines(), 1):
        if not line.strip().startswith("//"):
            yield number, line


def clocks(text, label="sample"):
    return [f"{label}:{n}" for n, line in code_lines(text) if FORBIDDEN.search(line)]


def state_declarations(text):
    return [line.strip() for _, line in code_lines(text) if re.search(r"@State\b", line)]


def function_body(text, signature):
    """The braces of the function whose declaration ends in `{`; a protocol requirement has no body."""
    start = text.index(signature)
    open_brace = start + len(signature) - 1
    assert text[open_brace] == "{", signature
    depth = 0
    for index in range(open_brace, len(text)):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0:
                return start, text[open_brace:index + 1]
    raise AssertionError(f"unbalanced braces after {signature}")


class MeetingCardLint(unittest.TestCase):
    def read(self, path):
        self.assertTrue(path.exists(), f"{path.relative_to(ROOT)} is missing")
        return path.read_text()

    def test_the_card_owns_no_timer_timeline_or_repeating_animation(self):
        found = []
        for path in (VIEW, PANEL):
            found += clocks(self.read(path), path.relative_to(ROOT).as_posix())
        self.assertEqual(found, [])

    def test_the_view_keeps_no_meeting_or_card_in_state(self):
        declared = state_declarations(self.read(VIEW))
        self.assertTrue(declared, "the ring and the entrance each keep one plain value")
        for line in declared:
            self.assertNotRegex(line, r"Meeting|[Cc]ard|String", line)

    def test_the_view_has_no_words_of_its_own(self):
        text = self.read(VIEW)
        self.assertNotIn('Text("', text)
        self.assertNotIn("LocalizedStringKey", text)

    def test_the_ring_is_keyed_on_the_deadline(self):
        text = self.read(VIEW)
        self.assertRegex(text, r"\.id\(\s*deadline\s*\)")

    def test_the_view_names_its_three_controls(self):
        text = self.read(VIEW)
        for control in ("primary", "cancel", "dismiss"):
            self.assertIn(f'.ownedJourneyControl("scribe.meetingCard.{control}")', text)
        self.assertIn(".keyboardShortcut(.defaultAction)", text)
        self.assertIn(".keyboardShortcut(.cancelAction)", text)

    def test_the_panel_orders_out_only_inside_render(self):
        text = self.read(PANEL)
        self.assertIn("protocol ScribeMeetingCardRendering", text)
        start, body = function_body(text, "func render(_ card: ScribeMeetingCard) {")
        outside = text[:start] + text[start + len(body):]
        self.assertIn("orderOut(", body)
        self.assertEqual(re.findall(r"\borderOut\(|\bclose\(\)|\.isVisible\s*=", outside), [])

    def test_the_panel_hosts_with_the_first_click_view_and_never_takes_the_keyboard(self):
        text = self.read(PANEL)
        self.assertIn("ScribeCardHostingView(rootView:", text)
        self.assertNotIn("NSHostingView(rootView:", text)
        self.assertIn(".nonactivatingPanel", text)
        self.assertIn("orderFrontRegardless()", text)
        self.assertNotIn("makeKeyAndOrderFront", text)
        self.assertNotIn("NSApp.activate", text)

    def test_motion_comes_from_alert_motion_alone(self):
        for path in (VIEW, PANEL):
            text = self.read(path)
            self.assertEqual(re.findall(r"static let \w*[Dd]uration\w*\s*(?::\s*\w+)?\s*=\s*[0-9.]+", text), [],
                             f"{path.name} keeps a duration of its own")
        self.assertIn("AlertMotion.", self.read(PANEL))

    def test_the_entrance_never_animates_the_ring(self):
        text = self.read(VIEW)
        # An implicit animation on the whole card would replace the ring's own linear sweep in the pass where it
        # starts, so the entrance is scoped to the two modifiers it moves.
        self.assertNotRegex(text, r"\.animation\(entrance\.animation,\s*value:")
        self.assertRegex(text, r"\.animation\(entrance\.animation\)\s*\{[^}]*\.opacity\([^}]*\.offset\(")

    def test_the_panel_picks_its_screen_when_it_appears_not_on_every_render(self):
        text = self.read(PANEL)
        _, body = function_body(text, "private func layout(_ panel: NSPanel, _ host: NSView) {")
        self.assertNotIn("visibleFrame()", body)

    def test_the_panel_places_the_card_with_the_core_rule(self):
        self.assertIn("ScribeMeetingCardPlacement.origin(", self.read(PANEL))

    def test_the_card_sources_have_no_dash_and_use_the_shared_material(self):
        for path in (VIEW, PANEL):
            text = self.read(path)
            self.assertIsNone(DASH.search("\n".join(line for _, line in code_lines(text))), path.name)
        self.assertIn(".alertGlass(", self.read(VIEW))

    def test_a_tap_carries_the_card_the_person_saw(self):
        view = self.read(VIEW)
        for action in ("onPrimary", "onCancel", "onDismiss"):
            self.assertIn(f"var {action}: (ScribeMeetingCard) -> Void", view)
            self.assertRegex(view, rf"\b{action}\(card\)")
            self.assertNotRegex(view, rf"Button\(action: {action}\)")
        panel = self.read(PANEL)
        for action in ("primary", "cancel", "dismiss"):
            self.assertIn(f"var {action}: (ScribeMeetingCard) -> Void", panel)

    def test_the_panel_takes_the_card_down_by_render_generation_not_by_alpha(self):
        text = self.read(PANEL)
        self.assertNotRegex(text, r"alphaValue\s*==")
        self.assertIn("ignoresMouseEvents", text)
        _, body = function_body(text, "func render(_ card: ScribeMeetingCard) {")
        self.assertRegex(body, r"generation")

    def test_the_card_is_one_voiceover_element_for_title_and_status_plus_its_buttons(self):
        text = self.read(VIEW)
        self.assertNotIn(".accessibilityElement(children: .contain)", text)
        self.assertEqual(len(re.findall(r"\.accessibilityLabel\(ScribeMeetingCardText\.label\(", text)), 1)
        self.assertIn(".accessibilityElement(children: .ignore)", text)

    def test_the_panel_owns_the_first_click_hosting_view(self):
        panel = self.read(PANEL)
        self.assertIn("final class ScribeCardHostingView<Content: View>: NSHostingView<Content>", panel)
        self.assertIn("override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }", panel)
        driver = ROOT / "Sources/Zeus/Scribe/ScribePopupDriver.swift"
        self.assertNotIn("class ScribeCardHostingView", self.read(driver))

    def test_the_lint_detects_its_failure_shapes(self):
        self.assertTrue(clocks("TimelineView(.animation) { _ in }"))
        self.assertTrue(clocks("let t = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in }"))
        self.assertTrue(clocks(".animation(.linear.repeatForever(autoreverses: false), value: x)"))
        self.assertFalse(clocks("// a Timer would keep running"))
        self.assertFalse(clocks("withAnimation(.linear(duration: 5)) { share = 0 }"))
        self.assertEqual(state_declarations("@State private var meeting: ScribeMeeting?"),
                         ["@State private var meeting: ScribeMeeting?"])
        _, body = function_body("func render(_ card: X) {\n if a { b() }\n}\nfunc other() {}", "func render(_ card: X) {")
        self.assertEqual(body, "{\n if a { b() }\n}")


if __name__ == "__main__":
    unittest.main()
