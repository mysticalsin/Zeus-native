import AppKit
import ApplicationServices
import ZeusCore

/// Puts dictated text into the app in front: clipboard + ⌘V, then the previous clipboard comes
/// back. Without Accessibility the text stays on the clipboard and the notch says so.
@MainActor
enum TextInserter {
    enum Outcome: Equatable {
        case pasted, copiedOnly
        /// A direct AX replacement was attempted, but its readback was unavailable. It may
        /// already be applied; callers must never label it copied or automatically retry it.
        case unconfirmed
    }

    /// Decides whether dictated text may be pasted into the target app. Only `ready` pastes;
    /// every unknown or negative state fails closed. Pure apart from the injected probe.
    enum DeliveryGate {
        enum Action: Equatable { case paste, clipboardOnly, abort }

        /// Who is frontmost and who owns the focused element, by PID and bundle ID.
        struct Probe {
            var frontmost: () -> DictationFileInject.TargetIdentity?
            var focused: () -> DictationFileInject.TargetIdentity?
        }

        static func state(target: DictationFileInject.TargetIdentity?, terminated: Bool,
                          probe: Probe) -> DictationFileInject.TargetState {
            guard let target, !terminated else { return .unavailable }
            return DictationFileInject.identityState(target: target, frontmost: probe.frontmost(),
                                                     focus: probe.focused())
        }

        static func action(for state: DictationFileInject.TargetState, allowClipboardFallback: Bool) -> Action {
            if state == .ready { return .paste }
            return allowClipboardFallback ? .clipboardOnly : .abort
        }

        static func identity(of app: NSRunningApplication) -> DictationFileInject.TargetIdentity {
            .init(pid: app.processIdentifier, bundleID: app.bundleIdentifier)
        }

        /// The real lookups: the frontmost app and the owner of the focused accessibility element.
        @MainActor static var live: Probe {
            Probe(
                frontmost: { NSWorkspace.shared.frontmostApplication.map { identity(of: $0) } },
                focused: {
                    guard AXIsProcessTrusted() else { return nil }
                    var focused: CFTypeRef?
                    guard AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString, &focused) == .success,
                          let element = focused else { return nil }
                    var pid: pid_t = 0
                    // swiftlint:disable:next force_cast
                    guard AXUIElementGetPid(element as! AXUIElement, &pid) == .success else { return nil }
                    return .init(pid: pid, bundleID: NSRunningApplication(processIdentifier: pid)?.bundleIdentifier)
                })
        }
    }

    /// Asked at every real sink moment (after each delay, before each key): may this still act?
    /// Returns `.abort` when the turn was cancelled or replaced. nil means ungated (legacy callers).
    typealias DeliveryCheck = @MainActor () -> DeliveryGate.Action

    /// The effects a delayed delivery performs. Production fills these with the pasteboard,
    /// CGEvents and `Task.sleep`; tests fill them with recorders and an instant sleep.
    @MainActor
    struct SinkSteps {
        var sleep: (Int) async -> Void
        var pasteKey: () -> Void = {}
        var returnKey: () -> Void = {}
        var typeChunk: ([UInt16]) -> Void = { _ in }
        var newline: () -> Void = {}
        var copyText: () -> Void = {}
        var restoreIfUnchanged: () -> Void = {}
    }

    enum PasteResult: Equatable { case pasted, clipboardOnly, aborted }
    enum TypeResult: Equatable { case typed, clipboardOnly, aborted(piecesTyped: Int) }

    /// The delayed ⌘V sequence; `insert` runs exactly this. The text is already on the clipboard.
    static func runPaste(pressReturn: Bool, restoreClipboard: Bool, steps: SinkSteps,
                         check: DeliveryCheck?, settleMs: Int = 60) async -> PasteResult {
        // Let the modifier the person was holding come up before we press ⌘V. With no modifier
        // down there is nothing to wait for, which saves 60 ms on every dictation.
        if settleMs > 0 { await steps.sleep(settleMs) }
        switch check?() ?? .paste {
        case .paste: break
        case .clipboardOnly: return .clipboardOnly
        case .abort:
            if restoreClipboard { steps.restoreIfUnchanged() }
            return .aborted
        }
        steps.pasteKey()
        if pressReturn {
            await steps.sleep(120)
            if (check?() ?? .paste) == .paste { steps.returnKey() }
        }
        if restoreClipboard {
            await steps.sleep(450)
            // Only our own transient write is put back, and only if nothing else changed the
            // clipboard meanwhile. No owner gate: skipping it would leave a cancelled turn's text there.
            steps.restoreIfUnchanged()
        }
        return .pasted
    }

    /// The delayed key-by-key sequence; `type` runs exactly this. The gate is rechecked before
    /// every piece, so a drift or cancel stops typing at once.
    static func runType(pieces: [KeystrokeTyping.Piece], pressReturn: Bool, steps: SinkSteps,
                        check: DeliveryCheck?) async -> TypeResult {
        await steps.sleep(60)
        var typed = 0
        func verdict() -> DeliveryGate.Action { check?() ?? .paste }
        func stop(_ action: DeliveryGate.Action) -> TypeResult {
            if action == .clipboardOnly { steps.copyText(); return .clipboardOnly }
            return .aborted(piecesTyped: typed)
        }
        for piece in pieces {
            let action = verdict()
            guard action == .paste else { return stop(action) }
            switch piece {
            case .newline:
                steps.newline()
            case .text(let chunk):
                steps.typeChunk(Array(chunk.utf16))
            }
            typed += 1
            // Slow enough for remote desktops to keep up.
            await steps.sleep(8)
        }
        if pressReturn {
            await steps.sleep(120)
            let action = verdict()
            guard action == .paste else { return stop(action) }
            steps.newline()
        }
        return .typed
    }

    /// Marks our own clipboard writes so the clipboard history skips them.
    static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    typealias Snapshot = [[NSPasteboard.PasteboardType: Data]]

    /// The user's clipboard as it was before our latest dictated write, and the change count of
    /// that write. While the board still carries it, the board holds our text, not the user's.
    struct PendingOriginal {
        var changeCount: Int
        var saved: Snapshot?
    }

    static var pendingOriginal: PendingOriginal?

    /// What to save as "the user's clipboard". When the board still holds an earlier (cancelled or
    /// replaced) dictated write of ours, the true original is that write's saved snapshot, not
    /// the dictated text. Pure apart from the injected `read`.
    static func resolveSnapshot(boardChangeCount: Int, pending: PendingOriginal?,
                                read: () -> Snapshot?) -> Snapshot? {
        if let pending, pending.changeCount == boardChangeCount { return pending.saved }
        return read()
    }

    /// How long to wait before ⌘V: nothing when no modifier key is down, else the usual 60 ms.
    static func pasteSettleMs(modifiersDown: Bool) -> Int { modifiersDown ? 60 : 0 }

    /// `onPasteKey` runs the moment ⌘V is posted: the text is on its way into the app.
    static func insert(_ text: String, pressReturn: Bool = false, restoreClipboard: Bool = true,
                       deliveryCheck: DeliveryCheck? = nil, onPasteKey: (@MainActor () -> Void)? = nil) async -> Outcome {
        let board = NSPasteboard.general
        let saved = resolveSnapshot(boardChangeCount: board.changeCount, pending: pendingOriginal,
                                    read: { snapshot(board) })
        board.clearContents()
        board.setString(text, forType: .string)
        board.setData(Data(), forType: transientType)
        let ours = board.changeCount
        pendingOriginal = PendingOriginal(changeCount: ours, saved: saved)

        guard AXIsProcessTrusted() else { return .copiedOnly }
        let steps = SinkSteps(
            sleep: { try? await Task.sleep(for: .milliseconds($0)) },
            pasteKey: { press(key: 9, flags: .maskCommand); onPasteKey?() }, // V
            returnKey: { press(key: 36, flags: []) }, // Return
            restoreIfUnchanged: {
                if let saved, board.changeCount == ours { restore(saved, to: board) }
            })
        let result = await runPaste(pressReturn: pressReturn, restoreClipboard: restoreClipboard && saved != nil,
                                    steps: steps, check: deliveryCheck,
                                    settleMs: pasteSettleMs(modifiersDown: !NSEvent.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty))
        return result == .pasted ? .pasted : .copiedOnly
    }

    /// Value of the focused accessibility element (dictation E2E paste verification).
    static func focusedFieldText() -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused else { return nil }
        // swiftlint:disable:next force_cast
        let ax = element as! AXUIElement
        if let value = axString(ax, attribute: kAXValueAttribute), !value.isEmpty { return value }
        if let value = axString(ax, attribute: kAXSelectedTextAttribute), !value.isEmpty { return value }
        return nil
    }

    private static func axString(_ element: AXUIElement, attribute: String) -> String? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success else { return nil }
        return raw as? String
    }

    /// The selected text in the focused field, when the app exposes it (for "Selected text" context).
    static func selectedText() -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused else { return nil }
        var selected: CFTypeRef?
        // swiftlint:disable:next force_cast
        guard AXUIElementCopyAttributeValue(element as! AXUIElement, kAXSelectedTextAttribute as CFString, &selected) == .success else { return nil }
        let text = selected as? String
        return text?.isEmpty == false ? text : nil
    }

    private static func press(key: CGKeyCode, flags: CGEventFlags) {
        // Posting keys untrusted makes macOS prompt mid-use; dictation falls back to the clipboard.
        guard AXIsProcessTrusted() else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private static func snapshot(_ board: NSPasteboard) -> Snapshot? {
        guard let items = board.pasteboardItems, !items.isEmpty else { return nil }
        return items.map { item in
            var copy: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types { if let data = item.data(forType: type) { copy[type] = data } }
            return copy
        }
    }

    private static func restore(_ saved: [[NSPasteboard.PasteboardType: Data]], to board: NSPasteboard) {
        board.clearContents()
        let items = saved.map { entry -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in entry { item.setData(data, forType: type) }
            item.setData(Data(), forType: transientType)
            return item
        }
        board.writeObjects(items)
    }
}
