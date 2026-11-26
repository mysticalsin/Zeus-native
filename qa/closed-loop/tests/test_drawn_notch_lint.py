"""The drawn notch's wiring (docs/NOTCH-DRAWN-NOTCH-PLAN.md, D2): what no pure rule can see.

Each check is a function over source text, so every one has a sample that must fail it.
"""
from pathlib import Path
import json
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
CONTROLLER = ROOT / "Sources/Zeus/Notch/NotchController.swift"
VIEW = ROOT / "Sources/Zeus/Notch/NotchView.swift"
MODEL = ROOT / "Sources/Zeus/Notch/DrawnNotchModel.swift"
MODEL_TESTS = ROOT / "Tests/ZeusAppTests/DrawnNotchModelTests.swift"
FEATURE_MAP = ROOT / "qa/feature-map.json"

HOVER_GATE = "guard NotchOpenRules.opensOnHover(Self.openTrigger) else"
CLICK_GUARD = "topBar != nil || !model.sessions.isEmpty || model.approval != nil"
CLICK_RULE = "NotchOpenRules.opensOnClick(trigger: Self.openTrigger, panelIsOpen: model.presentation == .panel"
CALIBRATION_GUARD = "drawnNotch.isCalibrating"
HELPER = "ignoresMouseWhileClosed()"
# The router for closed and peek: only this exact call, and its closed case must return the helper above.
ROUTER_CALL = re.compile(r"ignoresMouse\(for: \.?[A-Za-z_][A-Za-z0-9_.]*\)")
DASHES = (chr(0x2013), chr(0x2014))


def function_body(text, signature):
    start = text.index(signature)
    brace = text.index("{", start)
    depth = 0
    for index in range(brace, len(text)):
        depth += {"{": 1, "}": -1}.get(text[index], 0)
        if depth == 0:
            return text[brace:index]
    raise AssertionError(signature)


def code_lines(text):
    return [line.split("//")[0] for line in text.splitlines() if not line.strip().startswith("//")]


def comes_before(body, first, second):
    return first in body and second in body and body.index(first) < body.index(second)


# The seven anchors of the plan's table, as source text.
def anchors_hold(text):
    problems = []
    alerts = text[text.index("private func alertsChanged()"):]
    alerts = alerts[:alerts.index("\n    }\n")]
    for needle in ("alertWake?.cancel()", "nextDeadline()"):
        if needle not in alerts:
            problems.append("alertsChanged lost " + needle)
    if len(re.findall(r"Task\.sleep", alerts)) != 1:
        problems.append("alertsChanged must hold exactly one Task.sleep")
    if "Timer" in alerts:
        problems.append("alertsChanged names a Timer")
    if "model.alerts.setSuspended(presentation != .closed" not in function_body(text, "func show(_ presentation"):
        problems.append("show lost setSuspended")
    if "whileOpen: true" not in function_body(text, "func snoozeAlert("):
        problems.append("snoozeAlert lost whileOpen")
    start = function_body(text, "func start()")
    if not comes_before(start, "if self?.openOnClick() == true { return }", "self?.clickedOutside()"):
        problems.append("start lost the early return before clickedOutside")
    if re.search(r"addLocalMonitorForEvents\(matching: \[\.leftMouseDown\]\)[^}]*?openOnClick\(\)", start) is None:
        problems.append("start lost the local mouse-down monitor")
    moved = function_body(text, "private func mouseMoved()")
    gate, dwell = moved.find(HOVER_GATE), moved.find("hoverTask = Task")
    shortcut = moved.find("guard topBar != nil else { show(.panel); return }")
    if not (gate != -1 and gate < dwell and gate < shortcut):
        problems.append("mouseMoved lost the hover gate order")
    click = function_body(text, "private func openOnClick() -> Bool")
    if CLICK_GUARD not in click or not comes_before(click, CLICK_RULE, "show(.panel)"):
        problems.append("openOnClick lost its anchors")
    return problems


def start_holds_no_drawn_observer(text):
    start = function_body(text, "func start()")
    banned = ("DrawnNotch", "drawnNotch", "surfaceGone", "willSleepNotification", "sessionDidResignActive", "didHideNotification")
    found = [name for name in banned if name in start]
    if start.count("addObserver(") != 3:
        found.append("addObserver count")
    return found


def calibration_guard_in_place(text):
    moved = function_body(text, "private func mouseMoved()")
    click = function_body(text, "private func openOnClick() -> Bool")
    hover_ok = (CALIBRATION_GUARD in moved and moved.index(HOVER_GATE) < moved.index(CALIBRATION_GUARD)
                < moved.index("hoverTask = Task") and moved.index(CALIBRATION_GUARD) < moved.index("guard topBar != nil else { show(.panel); return }"))
    click_ok = (CALIBRATION_GUARD in click and click.index(CLICK_GUARD) < click.index(CALIBRATION_GUARD)
                < click.index(CLICK_RULE) < click.index("show(.panel)"))
    return hover_ok and click_ok


def unrouted_ignores_mouse_calls(text):
    """Closed-state calls of setIgnoresMouse that do not go through the helper. The open panel half of
    mouseMoved may still pass its own answer, and `false` is the notch taking the mouse."""
    moved = function_body(text, "private func mouseMoved()")
    panel_half = moved[moved.index("case .panel:"):]
    found = []
    for number, line in enumerate(code_lines(text), 1):
        if "setIgnoresMouse(" not in line or "func setIgnoresMouse" in line:
            continue
        if line.strip() in panel_half_lines(panel_half):
            continue
        argument = line[line.index("setIgnoresMouse(") + len("setIgnoresMouse("):].rsplit(")", 1)[0]
        if argument.strip() == "false" or HELPER in argument or ROUTER_CALL.fullmatch(argument.strip()):
            continue
        found.append(f"{number}: {line.strip()}")
    return found


def router_closed_arm_is_the_helper(text):
    """The router's `.closed` arm returns the helper, so a closed notch never takes the mouse by another rule."""
    body = function_body(text, "private func ignoresMouse(for presentation")
    return re.search(r"case \.closed:\s*return ignoresMouseWhileClosed\(\)", body) is not None


def panel_half_lines(panel_half):
    return {line.strip() for line in panel_half.splitlines() if "setIgnoresMouse(" in line}


def build_reports_displays(text):
    return "displaysChanged(" in function_body(text, "private func build()")


def closed_wings_ignore_hits(text):
    return re.search(r"ClosedWings\(topBar: topBar(?:, [^)]*)?\)[^\n]*\n?[^\n]*\.allowsHitTesting\(false\)", text) is not None


def closed_width_key_free_of_footprint(text):
    body = function_body(text, "var closedWidthKey: ClosedWingsFacts.MotionKey?")
    return "size(for" not in body and "footprint" not in body


def opens_a_window(text):
    return [name for name in ("NSPanel(", "NSWindow(") if name in "\n".join(code_lines(text))]


def screen_mid_x_lines(text):
    """Code lines that centre on the real screen frame. The controller centres every zone on the anchor frame."""
    return [f"{number}: {line.strip()}" for number, line in enumerate(code_lines(text), 1) if "screen.frame.midX" in line]


def anchor_has_one_source(text):
    """The anchor frame is built in exactly one place, and the real frame stays for the display pick and the window."""
    return (len(re.findall(r"NotchAnchor\.frame\(screenFrame: screen\.frame", "\n".join(code_lines(text)))) == 1
            and "GlanceTopBar.windowFrame(screen: target.frame)" in text
            and "$0.screen.frame.contains(NSEvent.mouseLocation)" in text)


def view_offset_comes_last(text):
    """In NotchView.body the one sideways offset is the last modifier, after the alert animation, so the alerts move
    with the body. The animation may wrap the overlay in a closure. `offset` moves drawing and not layout."""
    view = text[text.index("struct NotchView: View"):]
    body = function_body(view, "var body: some View")
    marker = "value: model.alerts.isEmpty)"
    lines = [line.strip() for line in code_lines(body) if line.strip()]
    if body.count(".offset(x:") != 1 or marker not in body or not lines:
        return False
    return lines[-1] == ".offset(x: NotchAnchor.offset(footprint))" and body.index(marker) < body.index(".offset(x:")


def has_dash(text):
    return any(dash in text for dash in DASHES)


def sends_calibration_control(text):
    pattern = r"\.send\(\.(begin|setWidth|setHeight|setOffset|step|reset|done|cancel)\b"
    return re.findall(pattern, text)


class DrawnNotchWiring(unittest.TestCase):
    CONTROLLER_TEXT = CONTROLLER.read_text(encoding="utf-8")
    VIEW_TEXT = VIEW.read_text(encoding="utf-8")

    def test_the_seven_anchors_still_hold(self):
        self.assertEqual(anchors_hold(self.CONTROLLER_TEXT), [])

    def test_start_holds_no_new_observer(self):
        self.assertEqual(start_holds_no_drawn_observer(self.CONTROLLER_TEXT), [])

    def test_the_calibration_guard_sits_after_the_hover_gate_and_before_the_panel_opens(self):
        self.assertTrue(calibration_guard_in_place(self.CONTROLLER_TEXT))

    def test_every_closed_state_ignore_goes_through_the_helper(self):
        self.assertEqual(unrouted_ignores_mouse_calls(self.CONTROLLER_TEXT), [])

    def test_the_router_is_only_accepted_as_an_exact_call(self):
        sample = self.CONTROLLER_TEXT.replace("setIgnoresMouse(ignoresMouse(for: presentation))",
                                              "setIgnoresMouse(ignoresMouse(for: presentation) && true)", 1)
        self.assertNotEqual(unrouted_ignores_mouse_calls(sample), [])

    def test_the_router_closed_arm_returns_the_helper(self):
        self.assertTrue(router_closed_arm_is_the_helper(self.CONTROLLER_TEXT))
        sample = self.CONTROLLER_TEXT.replace("case .closed: return ignoresMouseWhileClosed()", "case .closed: return true", 1)
        self.assertNotEqual(sample, self.CONTROLLER_TEXT)
        self.assertFalse(router_closed_arm_is_the_helper(sample))

    def test_build_reports_the_displays_to_the_model(self):
        self.assertTrue(build_reports_displays(self.CONTROLLER_TEXT))

    def test_the_closed_wings_are_drawn_with_hit_testing_off(self):
        self.assertTrue(closed_wings_ignore_hits(self.VIEW_TEXT))

    def test_the_closed_width_key_does_not_read_the_footprint(self):
        self.assertTrue(closed_width_key_free_of_footprint(self.VIEW_TEXT))

    def test_no_notch_file_opens_a_window_of_its_own_for_the_shape(self):
        self.assertEqual(opens_a_window(MODEL.read_text(encoding="utf-8")), [])
        self.assertEqual(opens_a_window(self.VIEW_TEXT), [])

    def test_the_notch_never_sends_a_calibration_control(self):
        # Only the Settings card starts or changes calibration; the notch and its controller send losses only.
        self.assertEqual(sends_calibration_control(self.CONTROLLER_TEXT), [])
        self.assertEqual(sends_calibration_control(self.VIEW_TEXT), [])

    def test_no_zone_is_centred_on_the_real_screen_frame(self):
        self.assertEqual(screen_mid_x_lines(self.CONTROLLER_TEXT), [])

    def test_the_anchor_frame_has_one_source_and_the_real_frame_stays_for_the_pick_and_the_window(self):
        self.assertTrue(anchor_has_one_source(self.CONTROLLER_TEXT))

    def test_the_view_offset_is_the_last_modifier_of_the_body(self):
        self.assertTrue(view_offset_comes_last(self.VIEW_TEXT))

    def test_new_app_files_have_no_en_or_em_dash(self):
        for path in (MODEL, MODEL_TESTS, Path(__file__)):
            text = path.read_text(encoding="utf-8")
            self.assertFalse(has_dash(text), path.name)

    def test_the_model_suite_is_a_declared_native_fixture(self):
        checks = json.loads(FEATURE_MAP.read_text(encoding="utf-8"))["checks"]
        entry = next((check for check in checks if check["id"] == "native-DrawnNotchModelTests"), None)
        self.assertIsNotNone(entry, "native-DrawnNotchModelTests is not declared")
        self.assertEqual(entry["kind"], "native-fixture")
        self.assertEqual(entry["file"], "Tests/ZeusAppTests/DrawnNotchModelTests.swift")


class DrawnNotchLintFailsOnItsFailureShapes(unittest.TestCase):
    """Fail-first samples: each lint must reject the shape it exists to catch."""
    REAL = CONTROLLER.read_text(encoding="utf-8")

    def test_a_lost_anchor_is_caught(self):
        self.assertTrue(anchors_hold(self.REAL.replace("whileOpen: true", "whileOpen: false")))
        self.assertTrue(anchors_hold(self.REAL.replace("if self?.openOnClick() == true { return }", "_ = self?.openOnClick()")))
        self.assertTrue(anchors_hold(self.REAL.replace(HOVER_GATE, "guard true else")))

    def test_a_timer_in_alerts_changed_is_caught(self):
        broken = self.REAL.replace("alertWake?.cancel()\n        alertWake = nil\n        if model.alerts.isEmpty {",
                                   "alertWake?.cancel()\n        alertWake = nil\n        // a Timer\n        if model.alerts.isEmpty {", 1)
        self.assertTrue(anchors_hold(broken))

    def test_an_observer_added_to_start_is_caught(self):
        broken = self.REAL.replace("func start() {\n", "func start() {\n        NotificationCenter.default.addObserver(forName: NSApplication.didHideNotification, object: nil, queue: .main) { _ in }\n", 1)
        self.assertTrue(start_holds_no_drawn_observer(broken))

    def test_a_guard_above_the_hover_gate_is_caught(self):
        moved = function_body(self.REAL, "private func mouseMoved()")
        broken_moved = moved.replace(HOVER_GATE, "guard !drawnNotch.isCalibrating else { return }\n            " + HOVER_GATE, 1)
        self.assertFalse(calibration_guard_in_place(self.REAL.replace(moved, broken_moved)))
        self.assertFalse(calibration_guard_in_place("private func mouseMoved() { }\nprivate func openOnClick() -> Bool { }"))

    def test_a_closed_ignore_that_skips_the_helper_is_caught(self):
        sample = "    func show(_ presentation: P) {\n        setIgnoresMouse(presentation == .closed)\n    }\n" + self.REAL[self.REAL.index("    private func mouseMoved()"):]
        self.assertTrue(unrouted_ignores_mouse_calls(sample))
        self.assertTrue(unrouted_ignores_mouse_calls(
            "    private func alertsChanged() {\n        if model.alerts.isEmpty { setIgnoresMouse(true) }\n    }\n" + self.REAL[self.REAL.index("    private func mouseMoved()"):]))

    def test_a_build_that_does_not_report_displays_is_caught(self):
        self.assertFalse(build_reports_displays("private func build() { panels = [] }"))

    def test_closed_wings_without_the_modifier_are_caught(self):
        self.assertFalse(closed_wings_ignore_hits("ClosedWings(topBar: topBar).frame(height: barHeight)\n"))
        self.assertTrue(closed_wings_ignore_hits("ClosedWings(topBar: topBar).frame(height: barHeight)\n    .allowsHitTesting(false)"))

    def test_a_width_key_that_reads_the_footprint_is_caught(self):
        sample = "var closedWidthKey: ClosedWingsFacts.MotionKey? {\n model.presentation == .closed ? size(for: .closed) : nil\n }"
        self.assertFalse(closed_width_key_free_of_footprint(sample))

    def test_a_window_in_the_model_is_caught(self):
        self.assertEqual(opens_a_window("let w = NSPanel(contentRect: .zero)"), ["NSPanel("])
        self.assertEqual(opens_a_window("// NSWindow( is not allowed"), [])

    def test_a_zone_centred_on_the_real_frame_is_caught(self):
        self.assertTrue(screen_mid_x_lines(self.REAL.replace("zone.minX", "screen.frame.midX", 1)))
        self.assertTrue(screen_mid_x_lines("let x = screen.frame.midX - width / 2"))
        self.assertEqual(screen_mid_x_lines("// screen.frame.midX is the real centre"), [])
        self.assertEqual(screen_mid_x_lines("let x = anchor.midX - width / 2"), [])

    def test_a_second_anchor_source_or_a_moved_window_frame_is_caught(self):
        two = "let a = NotchAnchor.frame(screenFrame: screen.frame, footprint: footprint)\nlet b = NotchAnchor.frame(screenFrame: screen.frame, footprint: x)\n"
        self.assertFalse(anchor_has_one_source(two + "GlanceTopBar.windowFrame(screen: target.frame)\n$0.screen.frame.contains(NSEvent.mouseLocation)"))
        one = "let a = NotchAnchor.frame(screenFrame: screen.frame, footprint: footprint)\n"
        self.assertFalse(anchor_has_one_source(one + "GlanceTopBar.windowFrame(screen: anchor)\n$0.screen.frame.contains(NSEvent.mouseLocation)"))
        self.assertFalse(anchor_has_one_source(one + "GlanceTopBar.windowFrame(screen: target.frame)\n$0.screen.frame.contains(anchorPoint)"))

    def test_an_offset_before_the_alert_animation_or_a_second_offset_is_caught(self):
        offset = ".offset(x: NotchAnchor.offset(footprint))"
        sample = ("struct NotchView: View {\n    var body: some View {\n        Text(\"a\")\n            " + offset
                  + "\n            .animation(nil, value: model.alerts.isEmpty)\n    }\n}\n")
        self.assertFalse(view_offset_comes_last(sample))
        late = sample.replace("            " + offset + "\n", "").replace("value: model.alerts.isEmpty)", "value: model.alerts.isEmpty)\n            " + offset)
        self.assertTrue(view_offset_comes_last(late))
        twice = late.replace(offset, offset + "\n            " + offset)
        self.assertFalse(view_offset_comes_last(twice))
        self.assertTrue(view_offset_comes_last(late.replace(offset, "// the place\n            " + offset)))
        self.assertFalse(view_offset_comes_last(late.replace(offset, ".offset(x: 0)")))
        self.assertFalse(view_offset_comes_last(late.replace(offset, offset + "\n            .opacity(1)")))

    def test_a_dash_is_caught(self):
        self.assertTrue(has_dash("a " + DASHES[0] + " b"))
        self.assertTrue(has_dash("a " + DASHES[1] + " b"))
        self.assertFalse(has_dash("a - b"))

    def test_a_calibration_control_sent_from_the_notch_is_caught(self):
        self.assertEqual(sends_calibration_control("drawnNotch.send(.begin(saved: x))"), ["begin"])
        self.assertEqual(sends_calibration_control("drawnNotch.send(.surfaceGone(.noDisplay))"), [])


if __name__ == "__main__":
    unittest.main()
