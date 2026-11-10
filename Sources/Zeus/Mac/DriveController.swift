import AppKit
import ApplicationServices
import ZeusCore

/// Drive mode: carries out a `mac.drive` plan in Mac apps. Steps aim at a ref from the latest
/// `AXSnapshot` (preferred), an element title, or a screenshot point. Wherever the element has an
/// Accessibility action (AXPress, an AXValue write, AXShowMenu then a menu item) the step runs
/// headless, without moving the pointer; the visible glide and a synthetic CGEvent click are kept
/// for steps with no AX action. The plan is shown in the notch first; it waits for a yes unless the
/// autonomy setting lets safe, undoable plans run. Esc stops it at once. A bolt trail follows the
/// cursor. A step that failed before doing anything (stale ref, element gone) is tried once more
/// after a fresh snapshot; a step that may have acted is never repeated.
@MainActor
final class DriveController {
    static let shared = DriveController()

    private(set) var isDriving = false
    private var cancelled = false
    private var escMonitors: [Any] = []
    private var shouldStop: Bool { cancelled || Task.isCancelled }
    /// What a readClipboard step read, for {clipboard} in later steps of the same plan.
    private var clipboardText: String?
    weak var notch: NotchController?

    static var autonomy: DriveAutonomy {
        DriveAutonomy(rawValue: UserDefaults.standard.string(forKey: DriveAutonomy.settingsKey) ?? "") ?? .default
    }

    /// Runs the plan; returns what to say when it did not finish.
    func perform(_ plan: DrivePlan, screenshots: [ScreenShot]) async -> String? {
        guard !Task.isCancelled else { return "Stopped." }
        guard !isDriving else { return "I'm already driving. Press Esc to stop that first." }
        guard AXIsProcessTrusted() else { return "I need Accessibility access to drive your Mac. It's in System Settings, Privacy." }
        // Refs take their label from the snapshot that issued them, so the card and the risk
        // describe what is really on screen.
        let plan = plan.labelled { AXSnapshotter.shared.model(for: $0) }
        if let refusal = plan.refusal { log("refused: \(refusal.kind.rawValue)"); return refusal.message }
        // Reserve the controller before the approval await; two approved plans must never share a run.
        isDriving = true
        cancelled = false
        clipboardText = nil
        defer {
            isDriving = false
            clipboardText = nil
            stopEscWatch()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                if !self.isDriving { MarkModel.shared.trail = []; MarkOverlay.shared.hide() }
            }
        }
        let autonomy = Self.autonomy
        log("plan risk=\(plan.risk) autonomy=\(autonomy.rawValue) steps=\(plan.steps.count) approval=\(plan.needsApproval(autonomy))")
        if plan.needsApproval(autonomy) {
            let risk: HookEvent.Risk = plan.risk == .destructive ? .high : .medium
            let verdict = await notch?.requestApproval(agent: "ZEUS", project: "Drive mode", tool: "Mac",
                                                       command: Self.approvalCard(plan), risk: risk) ?? .deny
            guard verdict == .allow else { log("declined"); return "Okay, I won't touch anything." }
        }
        guard !shouldStop else { return "Stopped." }
        MarkModel.shared.trail = []
        MarkOverlay.shared.show(capturingMouse: false)
        startEscWatch()
        // Once this drive has taken its own snapshot, older refs are found again by role and label.
        var resnapshotted = false
        for (index, planned) in plan.steps.enumerated() {
            if shouldStop { log("cancelled at step \(index + 1)"); return "Stopped." }
            let step = clipboardText.map { planned.filling(clipboard: $0) } ?? planned
            // The approval card contains the content; the system log must not copy typed text or labels.
            log("step \(index + 1)/\(plan.steps.count)")
            var failure = await run(step, screenshots: screenshots, relocate: resnapshotted)
            if let error = failure, error.retrySafe, !shouldStop {
                log("step \(index + 1): \(error.kind.rawValue), nothing done; once more after a new snapshot")
                AXSnapshotter.shared.capture()
                resnapshotted = true
                failure = await run(step, screenshots: screenshots, relocate: true)
            }
            if let error = failure {
                log("step \(index + 1) failed: \(error.kind.rawValue) retrySafe=\(error.retrySafe)")
                return error.message
            }
            try? await Task.sleep(for: .milliseconds(180))
        }
        log("done")
        return shouldStop ? "Stopped." : nil
    }

    func cancel() {
        guard isDriving else { return }
        cancelled = true
    }

    /// Send, delete and buy show exactly what changes. Every other plan keeps its step list.
    private static func approvalCard(_ plan: DrivePlan) -> String {
        var extras: [String] = []
        for step in plan.steps {
            let label: String?
            switch step {
            case .click(let target, _): label = target.label
            default: label = nil
            }
            if let label, let intent = HandsGate.intent(clicking: label),
               case .approve(let preview) = HandsGate.judge(intent) {
                extras.append(preview.card)
            }
        }
        return extras.isEmpty ? plan.card : extras.joined(separator: "\n")
    }

    // MARK: Steps

    private func run(_ step: DriveStep, screenshots: [ScreenShot], relocate: Bool) async -> DriveError? {
        guard !shouldStop else { return nil }
        switch step {
        case .openApp(let name):
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: name)
                ?? Self.appURL(named: name) else { return DriveError(.notFound, "I couldn't find \(name).", retrySafe: false) }
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: config)
            try? await Task.sleep(for: .milliseconds(700))
        case .move(let target):
            guard PhysicalPointerSettings.enabled else { return Self.pointerDisabled }
            switch locate(target, screenshots: screenshots, relocate: relocate) {
            case .failure(let error): return error
            case .success(let found): await glide(to: found.point)
            }
        case .click(let target, let double):
            let found: Found
            switch locate(target, screenshots: screenshots, relocate: relocate) {
            case .failure(let error): return error
            case .success(let f): found = f
            }
            if !double, let element = found.element, AXFinder.actions(element).contains(kAXPressAction) {
                // Headless: the press needs no pointer.
                let code = AXUIElementPerformAction(element, kAXPressAction as CFString)
                if code == .success { log("AX press"); return nil }
                let error = DriveError.ax(code.rawValue, doing: "press", on: Self.name(target))
                // Gone or half-done: never follow up with a click.
                guard error.kind == .unsupported else { return error }
            }
            guard PhysicalPointerSettings.enabled else { return Self.pointerDisabled }
            await glide(to: found.point)
            if shouldStop { return nil }
            guard PhysicalPointerSettings.enabled else { return Self.pointerDisabled }
            Self.click(at: found.point, count: double ? 2 : 1)
            log("CGEvent click")
        case .type(let text, let into):
            let intended: AXUIElement
            if let into {
                switch locate(into, screenshots: screenshots, relocate: relocate) {
                case .failure(let error):
                    return error
                case .success(let found):
                    guard let element = found.element else { return .notFound(Self.name(into)) }
                    guard found.model?.isSecure != true, !AXFinder.isSecure(element) else {
                        return .secureField(Self.name(into))
                    }
                    intended = element
                    if AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success {
                        log("AX focus")
                    } else {
                        guard PhysicalPointerSettings.enabled else { return Self.pointerDisabled }
                        await glide(to: found.point)
                        if shouldStop { return nil }
                        guard PhysicalPointerSettings.enabled else { return Self.pointerDisabled }
                        Self.click(at: found.point, count: 1)
                    }
                }
            } else {
                guard let focused = AXFinder.focusedElement() else {
                    return .unsupported("I couldn't verify the focused field, so I stopped before typing.")
                }
                intended = focused
            }
            // Typed as keystrokes (not AXValue) so the app's own Undo takes it back.
            return await type(text, replacing: false, into: intended)
        case .key(let combo):
            guard let (mods, key) = KeyCombo.split(combo), let code = KeyCodes.code(for: key) else {
                return .unsupported("I don't know the key \(combo).")
            }
            Self.press(code: code, modifiers: mods)
        case .scroll(let lines):
            guard let amount = Int32(exactly: lines) else { return .unsupported("That scroll amount is out of range.") }
            Self.post(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: amount, wheel2: 0, wheel3: 0))
        case .wait(let seconds):
            try? await Task.sleep(for: .seconds(seconds))
        case .setValue(let target, let text):
            return await setValue(text, target: target, screenshots: screenshots, relocate: relocate)
        case .select(let target, let option):
            switch locate(target, screenshots: screenshots, relocate: relocate) {
            case .failure(let error): return error
            case .success(let found):
                guard let element = found.element else { return .unsupported("I can't choose from \(Self.name(target)).") }
                return await choose(option, in: element, role: found.model?.role, name: Self.name(target))
            }
        case .toggle(let target, let on):
            switch locate(target, screenshots: screenshots, relocate: relocate) {
            case .failure(let error): return error
            case .success(let found):
                guard let element = found.element else { return .unsupported("I can't switch \(Self.name(target)).") }
                return await toggle(element, on: on, point: found.point, name: Self.name(target))
            }
        case .expand(let target):
            switch locate(target, screenshots: screenshots, relocate: relocate) {
            case .failure(let error): return error
            case .success(let found):
                guard let element = found.element else { return .unsupported("I can't expand \(Self.name(target)).") }
                return expand(element, role: found.model?.role, name: Self.name(target))
            }
        case .focusWindow(let app, let title):
            return await focusWindow(app: app, title: title)
        case .readClipboard:
            clipboardText = NSPasteboard.general.string(forType: .string) ?? ""
            log("clipboard read (\(clipboardText?.count ?? 0) characters)")
        case .writeClipboard(let text):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            log("clipboard written (\(text.count) characters)")
        }
        return nil
    }

    /// AXValue straight into the field. A password field is refused. When the value cannot be
    /// set through Accessibility, the field is clicked and its text replaced by typing.
    private func setValue(_ text: String, target: DriveTarget, screenshots: [ScreenShot], relocate: Bool) async -> DriveError? {
        guard !shouldStop else { return nil }
        let found: Found
        switch locate(target, screenshots: screenshots, relocate: relocate) {
        case .failure(let error): return error
        case .success(let f): found = f
        }
        guard let element = found.element else { return .unsupported("I can't fill \(Self.name(target)).") }
        if found.model?.isSecure == true || AXFinder.isSecure(element) { return .secureField(Self.name(target)) }
        if AXFinder.isSettable(element, kAXValueAttribute) {
            let code = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFString)
            if code == .success { log("AX value set"); return nil }
            let error = DriveError.ax(code.rawValue, doing: "fill", on: Self.name(target))
            guard error.kind == .unsupported else { return error }
        }
        // No AX way in: focus it the visible way, select all, then type over it.
        guard PhysicalPointerSettings.enabled else { return Self.pointerDisabled }
        await glide(to: found.point)
        if shouldStop { return nil }
        guard PhysicalPointerSettings.enabled else { return Self.pointerDisabled }
        Self.click(at: found.point, count: 1)
        return await type(text, replacing: true, into: element)
    }

    private static let pointerDisabled = DriveError.unsupported("Physical pointer control is off, so I can't move to or click that target.")

    private func type(_ text: String, replacing: Bool, into intended: AXUIElement) async -> DriveError? {
        guard !AXFinder.isSecure(intended) else { return .secureField("The focused field") }
        let result = await DriveTypingFlow.run(
            chunks: Self.chunks(text), replacing: replacing,
            mayEmit: { !self.shouldStop && AXFinder.isFocused(intended) && !AXFinder.isSecure(intended) },
            sleep: { try? await Task.sleep(for: .milliseconds($0)) },
            selectAll: { if let code = KeyCodes.code(for: "a") { Self.press(code: code, modifiers: ["cmd"]) } },
            delete: { if let code = KeyCodes.code(for: "delete") { Self.press(code: code, modifiers: []) } },
            type: { Self.typeUnicode($0) }
        )
        guard case .interrupted = result else { return nil }
        if shouldStop { return nil }
        if AXFinder.isSecure(intended) { return .secureField("The focused field") }
        return DriveError(.mayHaveActed, "The focused field changed or couldn't be verified, so I stopped typing. Check the field before trying again.", retrySafe: false)
    }

    /// Pop-up buttons, menu buttons and combo boxes: open the menu, press the item. Tab groups,
    /// radio groups and lists: press or select the child with that title.
    private func choose(_ option: String, in element: AXUIElement, role knownRole: String?, name: String) async -> DriveError? {
        guard !shouldStop else { return nil }
        let role = knownRole ?? AXFinder.string(element, kAXRoleAttribute) ?? ""
        let actions = AXFinder.actions(element)
        let quoted = "\u{201C}\(option)\u{201D}"
        if ["AXPopUpButton", "AXComboBox"].contains(role),
           AXFinder.string(element, kAXValueAttribute)?.caseInsensitiveCompare(option) == .orderedSame {
            log("option already selected")
            return nil
        }
        if ["AXPopUpButton", "AXMenuButton", "AXMenuBarItem", "AXComboBox"].contains(role) || actions.contains("AXShowMenu") {
            let open = actions.contains("AXShowMenu") ? "AXShowMenu" : kAXPressAction
            let code = AXUIElementPerformAction(element, open as CFString)
            guard code == .success else { return .ax(code.rawValue, doing: "open", on: name) }
            try? await Task.sleep(for: .milliseconds(250))
            guard !shouldStop else { return nil }
            if let item = AXFinder.element(titled: option, in: element, roles: ["AXMenuItem"], cap: 600) {
                let press = AXUIElementPerformAction(item, kAXPressAction as CFString)
                if press == .success { log("AX menu item"); return nil }
                return .ax(press.rawValue, doing: "choose", on: quoted)
            }
            // Close the menu again; nothing was chosen. (No synthetic Esc: that stops the drive.)
            if let menu = AXFinder.element(titled: nil, in: element, roles: ["AXMenu"], cap: 50) {
                _ = AXUIElementPerformAction(menu, kAXCancelAction as CFString)
            }
            if role == "AXComboBox", AXFinder.isSettable(element, kAXValueAttribute) {
                let set = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, option as CFString)
                return set == .success ? nil : .ax(set.rawValue, doing: "fill", on: name)
            }
            return .notFound("\(quoted) in \(name)")
        }
        guard let item = AXFinder.element(titled: option, in: element, roles: nil, cap: 600) else {
            return .notFound("\(quoted) in \(name)")
        }
        if AXFinder.actions(item).contains(kAXPressAction) {
            let press = AXUIElementPerformAction(item, kAXPressAction as CFString)
            return press == .success ? nil : .ax(press.rawValue, doing: "choose", on: quoted)
        }
        if AXFinder.isSettable(item, kAXSelectedAttribute) {
            let set = AXUIElementSetAttributeValue(item, kAXSelectedAttribute as CFString, kCFBooleanTrue)
            return set == .success ? nil : .ax(set.rawValue, doing: "choose", on: quoted)
        }
        return .unsupported("I can't choose \(quoted) in \(name) directly.")
    }

    /// Checkboxes and switches: nothing to do when already in that state.
    private func toggle(_ element: AXUIElement, on: Bool, point: CGPoint, name: String) async -> DriveError? {
        guard !shouldStop else { return nil }
        guard let current = AXFinder.number(element, kAXValueAttribute) else {
            return .unsupported("I can't tell whether \(name) is on or off.")
        }
        guard DriveStep.needsPress(current: current, on: on) else { log("already \(on ? "on" : "off")"); return nil }
        if AXFinder.actions(element).contains(kAXPressAction) {
            let code = AXUIElementPerformAction(element, kAXPressAction as CFString)
            guard code == .success else { return .ax(code.rawValue, doing: "switch", on: name) }
            log("AX press")
        } else {
            guard PhysicalPointerSettings.enabled else { return Self.pointerDisabled }
            await glide(to: point)
            if shouldStop { return nil }
            guard PhysicalPointerSettings.enabled else { return Self.pointerDisabled }
            Self.click(at: point, count: 1)
            log("CGEvent click")
        }
        try? await Task.sleep(for: .milliseconds(150))
        if let after = AXFinder.number(element, kAXValueAttribute), DriveStep.needsPress(current: after, on: on) {
            return DriveError(.mayHaveActed, "\(name) didn't end up \(on ? "on" : "off"), so I stopped.", retrySafe: false)
        }
        return nil
    }

    /// Disclosure triangles, outline rows (AXDisclosing), AXExpanded elements and menus.
    private func expand(_ element: AXUIElement, role knownRole: String?, name: String) -> DriveError? {
        guard !shouldStop else { return nil }
        let role = knownRole ?? AXFinder.string(element, kAXRoleAttribute) ?? ""
        let actions = AXFinder.actions(element)
        func done(_ code: AXError, _ how: String) -> DriveError? {
            if code == .success { log(how); return nil }
            return .ax(code.rawValue, doing: "expand", on: name)
        }
        if role == "AXDisclosureTriangle" {
            if AXFinder.number(element, kAXValueAttribute) == 1 { log("already open"); return nil }
            return done(AXUIElementPerformAction(element, kAXPressAction as CFString), "AX press")
        }
        for attribute in ["AXDisclosing", kAXExpandedAttribute] where AXFinder.isSettable(element, attribute) {
            if AXFinder.number(element, attribute) == 1 { log("already open"); return nil }
            return done(AXUIElementSetAttributeValue(element, attribute as CFString, kCFBooleanTrue), "AX \(attribute)")
        }
        if actions.contains("AXShowMenu") { return done(AXUIElementPerformAction(element, "AXShowMenu" as CFString), "AX show menu") }
        if ["AXPopUpButton", "AXMenuButton", "AXMenuBarItem"].contains(role), actions.contains(kAXPressAction) {
            return done(AXUIElementPerformAction(element, kAXPressAction as CFString), "AX press")
        }
        return .unsupported("I can't expand \(name).")
    }

    /// Brings a running app forward, then raises the window whose title matches.
    private func focusWindow(app name: String, title: String?) async -> DriveError? {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        guard let app = apps.first(where: { $0.localizedName?.caseInsensitiveCompare(name) == .orderedSame
                                             || $0.bundleIdentifier?.caseInsensitiveCompare(name) == .orderedSame })
            ?? apps.first(where: { $0.localizedName?.localizedCaseInsensitiveContains(name) == true }) else {
            return DriveError(.notFound, "\(name) isn't open.", retrySafe: false)
        }
        app.activate()
        try? await Task.sleep(for: .milliseconds(300))
        guard !shouldStop else { return nil }
        guard let title, !title.isEmpty else { return nil }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        let windows = AXUIElementCopyAttributeValue(root, kAXWindowsAttribute as CFString, &value) == .success
            ? (value as? [AXUIElement]) ?? [] : []
        let wanted = title.lowercased()
        let titled = windows.map { ($0, AXFinder.string($0, kAXTitleAttribute)?.lowercased() ?? "") }
        guard let window = (titled.first { $0.1 == wanted } ?? titled.first { $0.1.contains(wanted) })?.0 else {
            return DriveError(.notFound, "I couldn't find a \(app.localizedName ?? name) window called \u{201C}\(title)\u{201D}.", retrySafe: false)
        }
        let code = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        _ = AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        return code == .success ? nil : .ax(code.rawValue, doing: "raise", on: "that window")
    }

    // MARK: Finding things

    /// A point in global AppKit coordinates, the AX element there when there is one, and the
    /// snapshot model when the target was a ref.
    private struct Found {
        var point: CGPoint
        var element: AXUIElement?
        var model: AXSnapshotElement?
    }

    /// A ref first (a stale ref is an error on the first try, then found again by role and label),
    /// then the element title, then the screenshot point.
    private func locate(_ target: DriveTarget, screenshots: [ScreenShot], relocate: Bool) -> Result<Found, DriveError> {
        if let ref = target.ref {
            do {
                let (model, element) = try AXSnapshotter.shared.resolve(ref, relocate: relocate)
                // A live element answers with its frame; a dead one went away since the snapshot.
                guard let frame = AXFinder.frame(of: element) else {
                    if !relocate { return .failure(.notFound(Self.name(target))) }
                    throw AXSnapshotError.unknownRef(ref)
                }
                return .success(Found(point: CGPoint(x: frame.midX, y: frame.midY), element: element, model: model))
            } catch {
                log("\(ref): \(error)")
                if !relocate {
                    if case AXSnapshotError.staleRef = error { return .failure(.staleRef(ref)) }
                    return .failure(.notFound(Self.name(target)))
                }
                // Found again neither by ref nor by role and label: fall back to the title or point.
            }
        }
        if let label = target.label, !label.isEmpty, let element = AXFinder.element(titled: label),
           let frame = AXFinder.frame(of: element) {
            return .success(Found(point: CGPoint(x: frame.midX, y: frame.midY), element: element))
        }
        guard let x = target.x, let y = target.y else { return .failure(.notFound(Self.name(target))) }
        let point: CGPoint
        if !screenshots.isEmpty {
            let index = (target.screen ?? 1) - 1
            point = ScreenCapture.globalPoint(x: x, y: y, on: screenshots.indices.contains(index) ? screenshots[index] : screenshots[0])
        } else {
            // No screenshot this turn: x, y are points from the top-left of the main screen.
            let height = NSScreen.screens.first?.frame.height ?? 0
            point = CGPoint(x: Double(x), y: height - Double(y))
        }
        return .success(Found(point: point, element: AXFinder.element(at: point)))
    }

    // MARK: Cursor

    /// Moves the real cursor along a short eased path, drawing the trail.
    private func glide(to end: CGPoint) async {
        guard PhysicalPointerSettings.enabled else { return }
        let start = NSEvent.mouseLocation
        let steps = 18
        for i in 1...steps {
            if shouldStop || !PhysicalPointerSettings.enabled { return }
            let t = Double(i) / Double(steps)
            let e = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
            let p = CGPoint(x: start.x + (end.x - start.x) * e, y: start.y + (end.y - start.y) * e)
            MarkModel.shared.trail.append(p)
            if MarkModel.shared.trail.count > 40 { MarkModel.shared.trail.removeFirst() }
            let q = Self.quartz(p)
            CGWarpMouseCursorPosition(q)
            let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: q, mouseButton: .left)
            Self.post(event)
            try? await Task.sleep(for: .milliseconds(16))
        }
    }

    /// AppKit (bottom-left) to Quartz (top-left of the main screen).
    static func quartz(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x, y: (NSScreen.screens.first?.frame.height ?? 0) - p.y)
    }

    static func click(at p: CGPoint, count: Int) {
        guard PhysicalPointerSettings.enabled else { return }
        let q = quartz(p)
        for n in 1...count {
            for type in [CGEventType.leftMouseDown, .leftMouseUp] {
                let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: q, mouseButton: .left)
                event?.setIntegerValueField(.mouseEventClickState, value: Int64(n))
                post(event)
            }
        }
    }

    static func chunks(_ text: String) -> [String] {
        var out: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if current.utf16.count >= 16 { out.append(current); current = "" }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    static func typeUnicode(_ text: String) {
        let units = Array(text.utf16)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down) else { continue }
            units.withUnsafeBufferPointer { event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: $0.baseAddress) }
            post(event)
        }
    }

    static func press(code: CGKeyCode, modifiers: Set<String>) {
        var flags: CGEventFlags = []
        if modifiers.contains("cmd") { flags.insert(.maskCommand) }
        if modifiers.contains("shift") { flags.insert(.maskShift) }
        if modifiers.contains("option") { flags.insert(.maskAlternate) }
        if modifiers.contains("ctrl") { flags.insert(.maskControl) }
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)
            event?.flags = flags
            post(event)
        }
    }

    private static func post(_ event: CGEvent?) {
        event?.setIntegerValueField(.eventSourceUserData, value: DriveInputAttribution.eventTag)
        event?.post(tap: .cghidEventTap)
    }

    static func appURL(named name: String) -> URL? {
        for dir in ["/Applications", "/System/Applications", "/System/Applications/Utilities", NSHomeDirectory() + "/Applications"] {
            let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).app")
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    static func name(_ t: DriveTarget) -> String {
        if let label = t.label, !label.isEmpty { return "\u{201C}\(label)\u{201D}" }
        return t.ref == nil ? "that spot" : "that control"
    }

    // MARK: Esc

    private func startEscWatch() {
        let handler: (NSEvent) -> Void = { event in
            guard !DriveInputAttribution.isOwnEvent(userData: event.cgEvent?.getIntegerValueField(.eventSourceUserData)) else { return }
            MainActor.assumeIsolated { DriveController.shared.cancel(); WalkthroughController.shared.cancel() }
        }
        let mask: NSEvent.EventTypeMask = [.keyDown, .mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown,
                                         .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel]
        if AccessibilityGate.trusted, let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler) { escMonitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { handler($0); return $0 }) { escMonitors.append(local) }
    }

    private func stopEscWatch() {
        escMonitors.forEach(NSEvent.removeMonitor)
        escMonitors = []
    }

    private func log(_ message: String) { NSLog("[ZEUS] drive: %@", message) }
}

/// Accessibility lookups. AX uses Quartz coordinates (top-left of the main screen).
@MainActor
enum AXFinder {
    static func focusedElement() -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func isFocused(_ expected: AXUIElement) -> Bool {
        guard let focused = focusedElement(), CFEqual(focused, expected) else { return false }
        var pid: pid_t = 0
        guard AXUIElementGetPid(focused, &pid) == .success else { return false }
        return NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
    }

    static func element(at p: CGPoint) -> AXUIElement? {
        var element: AXUIElement?
        let q = DriveController.quartz(p)
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(q.x), Float(q.y), &element) == .success else { return nil }
        return element
    }

    /// The first element in the frontmost app (or under `root`) whose title, description or value
    /// matches `label` (exact, case-insensitive, then contains), optionally of one of `roles`.
    /// A nil label matches the first element of those roles. Breadth-first, capped.
    static func element(titled label: String?, in root: AXUIElement? = nil, roles: Set<String>? = nil,
                        cap: Int = AXSnapshotter.maxElements) -> AXUIElement? {
        guard let root = root ?? NSWorkspace.shared.frontmostApplication.map({ AXUIElementCreateApplication($0.processIdentifier) })
        else { return nil }
        let wanted = label?.lowercased()
        var queue: [AXUIElement] = [root]
        var head = 0
        var partial: AXUIElement?
        while head < queue.count, head < cap {
            let element = queue[head]
            head += 1
            if roles.map({ $0.contains(string(element, kAXRoleAttribute) ?? "") }) ?? true {
                guard let wanted else { return element }
                for attribute in [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute] {
                    guard let text = string(element, attribute)?.lowercased(), !text.isEmpty else { continue }
                    if text == wanted { return element }
                    if partial == nil, text.count < 80, text.contains(wanted) { partial = element }
                }
            }
            var children: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
               let list = children as? [AXUIElement] { queue += list }
        }
        return partial
    }

    static func actions(_ element: AXUIElement) -> [String] { AXSnapshotter.actions(element) }

    static func number(_ element: AXUIElement, _ attribute: String) -> Int? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return (value as? NSNumber)?.intValue
    }

    static func isSettable(_ element: AXUIElement, _ attribute: String) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success && settable.boolValue
    }

    static func isSecure(_ element: AXUIElement) -> Bool {
        string(element, kAXRoleAttribute) == kAXSecureTextFieldSubrole || string(element, kAXSubroleAttribute) == kAXSecureTextFieldSubrole
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    /// Frame in AppKit coordinates.
    static func frame(of element: AXUIElement) -> CGRect? {
        var position: CFTypeRef?
        var size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success else { return nil }
        var p = CGPoint.zero
        var s = CGSize.zero
        // swiftlint:disable force_cast
        guard AXValueGetValue(position as! AXValue, .cgPoint, &p), AXValueGetValue(size as! AXValue, .cgSize, &s) else { return nil }
        let height = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: p.x, y: height - p.y - s.height, width: s.width, height: s.height)
    }
}

/// Virtual key codes for the US layout keys a plan may press.
enum KeyCodes {
    static let named: [String: CGKeyCode] = [
        "return": 36, "enter": 76, "tab": 48, "space": 49, "delete": 51, "backspace": 51, "escape": 53, "esc": 53,
        "left": 123, "right": 124, "down": 125, "up": 126, "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
        "forwarddelete": 117,
    ]
    static let letters: [Character: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13,
        "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25,
        "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38,
        "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "`": 50,
    ]

    static func code(for key: String) -> CGKeyCode? {
        if let code = named[key] { return code }
        if key.count == 1, let c = key.first { return letters[c] }
        return nil
    }
}
