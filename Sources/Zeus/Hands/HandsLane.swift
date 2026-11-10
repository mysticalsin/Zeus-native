import AppKit
import ApplicationServices
import ZeusCore

/// Scratch-window proof for the integrator. Acts only on a window this process creates.
@MainActor
enum HandsLive {
    static func run(onCue: (HandsCue) -> Void, onPreview: (WorkBehindPreview?) -> Void) -> String {
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let cursor = NSEvent.mouseLocation
        let box = HandsScratchBox()
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 320, height: 180),
                              styleMask: [.titled, .closable], backing: .buffered, defer: true)
        window.title = "Zeus Scratch"
        window.isReleasedWhenClosed = false
        let field = NSTextField(string: "hello there friend")
        field.frame = NSRect(x: 20, y: 100, width: 220, height: 24)
        field.placeholderString = "Search"
        let save = NSButton(title: "Save", target: box, action: #selector(HandsScratchBox.save(_:)))
        save.frame = NSRect(x: 20, y: 50, width: 80, height: 28)
        save.bezelStyle = .rounded
        let send = NSButton(title: "Send", target: box, action: #selector(HandsScratchBox.send(_:)))
        send.frame = NSRect(x: 110, y: 50, width: 80, height: 28)
        send.bezelStyle = .rounded
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))
        content.addSubview(field)
        content.addSubview(save)
        content.addSubview(send)
        window.contentView = content
        window.orderBack(nil)
        defer { window.close() }

        let board = NSPasteboard.general
        let savedClip = board.string(forType: .string)
        defer {
            board.clearContents()
            if let savedClip { board.setString(savedClip, forType: .string) }
        }

        onPreview(WorkBehindPreview(streaming: true, title: "Zeus Scratch",
                                    frames: [HandsFrame(x: 20, y: 50, w: 80, h: 28)], windowID: "scratch"))
        defer { onPreview(nil) }

        var lines: [String] = []
        var problems: [String] = []
        guard AXIsProcessTrusted() else {
            return "FAIL accessibility"
        }
        guard let root = axWindow(titled: "Zeus Scratch") else {
            return "FAIL scratch window"
        }
        if let search = axDescendant(root, role: kAXTextFieldRole as String, label: nil) ?? axDescendant(root, role: kAXTextAreaRole as String, label: nil) {
            let code = AXUIElementSetAttributeValue(search, kAXValueAttribute as CFString, "hello" as CFTypeRef)
            lines.append("type ax=\(code.rawValue)")
            if code != .success || field.stringValue != "hello" { problems.append("type") }
        } else {
            problems.append("field")
        }
        if let button = axDescendant(root, role: kAXButtonRole as String, label: "Save") {
            let code = AXUIElementPerformAction(button, kAXPressAction as CFString)
            lines.append("click ax=\(code.rawValue) saves=\(box.saves)")
            if code != .success || box.saves != 1 { problems.append("click") }
            if let frame = saveFrame(button) {
                onCue(HandsCue(x: frame.x, y: frame.y, label: "Save"))
            }
        } else {
            problems.append("save")
        }
        let scroll = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 1, wheel2: 0, wheel3: 0)
        scroll?.postToPid(getpid())
        lines.append("scroll delivery=postToPid")
        if box.sends != 0 { problems.append("send") }
        let afterFront = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let afterCursor = NSEvent.mouseLocation
        if afterFront != front { problems.append("front") }
        if afterCursor != cursor { problems.append("cursor") }
        if board.string(forType: .string) != savedClip { problems.append("clipboard") }
        lines.append("front=\(front.map(String.init) ?? "none") cursor=\(Int(cursor.x)),\(Int(cursor.y)) sends=\(box.sends)")
        lines.append(problems.isEmpty ? "PASS" : "FAIL \(problems.joined(separator: ", "))")
        return lines.joined(separator: "\n")
    }

    private static func axWindow(titled title: String) -> AXUIElement? {
        let app = AXUIElementCreateApplication(getpid())
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return nil }
        return windows.first { axString($0, kAXTitleAttribute as String) == title }
    }

    private static func axDescendant(_ element: AXUIElement, role: String, label: String?) -> AXUIElement? {
        if axString(element, kAXRoleAttribute as String) == role {
            if let label {
                if axString(element, kAXTitleAttribute as String) == label { return element }
            } else {
                return element
            }
        }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let children = value as? [AXUIElement] else { return nil }
        for child in children {
            if let found = axDescendant(child, role: role, label: label) { return found }
        }
        return nil
    }

    private static func axString(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func saveFrame(_ element: AXUIElement) -> HandsPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &value) == .success, let value else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(value as! AXValue, .cgPoint, &point) else { return nil }
        return HandsPoint(x: Int(point.x), y: Int(point.y))
    }
}

private final class HandsScratchBox: NSObject {
    var saves = 0
    var sends = 0
    @objc func save(_ sender: Any?) { saves += 1 }
    @objc func send(_ sender: Any?) { sends += 1 }
}

/// Shows the selection diff in the notch. Return accepts it. Esc clears it. A draft is never sent.
@MainActor
final class HandsHUD {
    static let shared = HandsHUD()

    weak var notch: NotchController?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var edit: SelectionEdit?
    private var covered: NSWindow?

    func present(_ edit: SelectionEdit, notch: NotchController?) {
        self.notch = notch
        self.edit = edit
        notch?.model.selectionEdit = edit
        notch?.show(.peek)
        armKeys()
    }

    func show(preview: WorkBehindPreview?, window: NSWindow? = nil) {
        notch?.model.workBehind = preview
        covered = window
        if preview?.streaming == true { notch?.show(.peek) }
    }

    func openCoveredWindow() {
        covered?.makeKeyAndOrderFront(nil)
        notch?.model.workBehind = nil
        covered = nil
    }

    func accept() {
        guard var edit else { return }
        edit.accepted = true
        let session = SelectionEditSession(edit: edit, clipboard: NSPasteboard.general.string(forType: .string))
        var applying = session
        applying.accept()
        if applying.sendPressed { disarm(); return }
        if let text = applying.appliedText {
            replaceSelection(text)
        }
        self.edit = applying.edit
        notch?.model.selectionEdit = nil
        disarm()
    }

    func dismiss() {
        edit = nil
        notch?.model.selectionEdit = nil
        notch?.model.workBehind = nil
        disarm()
    }

    /// Replaces only the selection. A field that refuses the write is never given the whole value
    /// (`text` is just the replacement, so that would wipe the rest); the text is copied for
    /// pasting instead, and the clipboard is left alone when the write worked.
    private func replaceSelection(_ text: String) {
        if applyToSelection(text) { return }
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text, forType: .string)
        NSSound.beep()
    }

    private func applyToSelection(_ text: String) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused else { return false }
        let ax = element as! AXUIElement
        return AXUIElementSetAttributeValue(ax, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success
    }

    private func armKeys() {
        disarm()
        guard AXIsProcessTrusted() else { return }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: HandsHUD.callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func disarm() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    private static let callback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let hud = Unmanaged<HandsHUD>.fromOpaque(refcon).takeUnretainedValue()
            if let tap = hud.tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        guard code == 36 || code == 53 else { return Unmanaged.passUnretained(event) }
        let key = code
        DispatchQueue.main.async {
            if key == 36 { HandsHUD.shared.accept() } else { HandsHUD.shared.dismiss() }
        }
        return nil
    }
}

/// "When I say X, do Y" and a later replay. Unknown steps are not saved.
@MainActor
enum LearnedSteps {
    static func run(_ step: String) async -> Bool {
        let trimmed = step.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower.hasPrefix("open ") {
            let name = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            return await open(name)
        }
        if lower.hasPrefix("close ") || lower.hasPrefix("quit ") {
            let name = String(trimmed.dropFirst(lower.hasPrefix("close ") ? 6 : 5)).trimmingCharacters(in: .whitespaces)
            return close(name)
        }
        return false
    }

    private static func open(_ name: String) async -> Bool {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: name) ?? appURL(named: name)
        guard let url else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        return (try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)) != nil
    }

    private static func appURL(named name: String) -> URL? {
        let urls = (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: "/Applications"), includingPropertiesForKeys: nil)) ?? []
        let local = (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: "/System/Applications"), includingPropertiesForKeys: nil)) ?? []
        return (urls + local).first { $0.deletingPathExtension().lastPathComponent.lowercased() == name.lowercased() }
    }

    private static func close(_ name: String) -> Bool {
        let matches = NSWorkspace.shared.runningApplications.filter { $0.localizedName?.lowercased() == name.lowercased() }
        if matches.isEmpty { return true }
        return matches.allSatisfy { $0.terminate() }
    }

    static func handle(_ transcript: String) async -> String? {
        if let parsed = NamedShortcutPhrase.parse(transcript) {
            var ok = true
            for step in parsed.steps where ok {
                ok = await run(step)
            }
            guard ok else { return "That didn't finish, so I didn't save it." }
            _ = LearnedShortcutDisk.shared.save(phrase: parsed.phrase, steps: parsed.steps, verified: true)
            return "Saved \(parsed.phrase)."
        }
        guard let shortcut = LearnedShortcutDisk.shared.match(transcript) else { return nil }
        for step in shortcut.steps {
            if await run(step) { continue }
            _ = LearnedShortcutDisk.shared.remove(shortcut.id)
            return nil
        }
        return "Done."
    }
}
