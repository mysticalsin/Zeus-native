import AppKit
import ApplicationServices
import ZeusCore

/// Keeps only the AX identity and text Zeus wrote. It never reads AXValue, the clipboard, or
/// surrounding field contents. Unsupported/secure fields cannot earn a replacement receipt.
@MainActor
final class DictationInsertionTracker {
    struct Field {
        let element: AXUIElement
        let owner: TextInsertionReceipt.Owner
        let id: UUID
    }

    private var field: Field?
    private var receipt: TextInsertionReceipt?

    func invalidate() { field = nil; receipt = nil }

    /// Called at turn start. A changed/unknown field permanently drops the previous receipt.
    func beginTurn() -> Field? {
        guard let focused = Self.focusedEditableField() else { invalidate(); return nil }
        if let field, field.owner == focused.owner, CFEqual(field.element, focused.element) { return field }
        invalidate()
        return focused
    }

    func matchesFocus(_ expected: Field) -> Bool {
        guard let focused = Self.focusedEditableField() else { return false }
        return focused.owner == expected.owner && CFEqual(focused.element, expected.element)
    }

    /// Begin a new insertion: older text is no longer eligible, including a copied-only turn.
    func prepareInsertion(in target: Field?) -> TextInsertionReceipt.FieldState? {
        invalidate()
        guard let target else { return nil }
        return inspect(target, span: nil)
    }

    func acknowledge(_ text: String, before: TextInsertionReceipt.FieldState?, target: Field?,
                     sendsReturn: Bool, isCurrent: () -> Bool) async {
        guard !sendsReturn, let before, let target, before.selection.length == 0 else { return }
        let span = TextInsertionReceipt.Span(location: before.selection.location, length: text.utf16.count)
        for attempt in 0..<4 {
            guard isCurrent() else { return }
            // Focus drift drops the proof, even if the person later switches back.
            guard matchesFocus(target) else { return }
            if let after = inspect(target, span: span),
               let acknowledged = TextInsertionReceipt.acknowledgeInsertion(
                text: text, before: before, after: after, sendsReturn: sendsReturn), isCurrent() {
                field = target
                receipt = acknowledged
                return
            }
            if attempt < 3 { try? await Task.sleep(for: .milliseconds(40)) }
        }
    }

    func correct(_ replacement: String, target: Field?, isCurrent: @escaping () -> Bool) async
        -> TextInsertionReceipt.ReplacementResult {
        guard let target, let field, let receipt, target.id == field.id else {
            invalidate()
            return .unavailable
        }
        // Remove the receipt before the first suspension; only acknowledged success renews it.
        invalidate()
        let result = await receipt.replace(with: replacement, steps: .init(
            isCurrent: isCurrent,
            inspect: { [self] in inspect(target, span: $0) },
            select: { [self] span in
                guard isCurrent(), matchesFocus(target), let end = span.end, end >= span.location else { return false }
                var range = CFRange(location: span.location, length: span.length)
                guard let value = AXValueCreate(.cfRange, &range) else { return false }
                return AXUIElementSetAttributeValue(target.element, kAXSelectedTextRangeAttribute as CFString, value) == .success
            },
            replaceSelected: { [self] text in
                guard isCurrent(), matchesFocus(target) else { return false }
                return AXUIElementSetAttributeValue(target.element, kAXSelectedTextAttribute as CFString, text as CFString) == .success
            },
            waitForAcknowledgment: { try? await Task.sleep(for: .milliseconds(40)) }))
        if case .replaced(let acknowledged) = result, isCurrent() { self.field = target; self.receipt = acknowledged }
        return result
    }

    private func inspect(_ target: Field, span: TextInsertionReceipt.Span?) -> TextInsertionReceipt.FieldState? {
        guard matchesFocus(target), let selection = Self.selection(target.element),
              let count = Self.attribute(target.element, kAXNumberOfCharactersAttribute) as? NSNumber,
              count.intValue >= 0, let selectedEnd = selection.end, selectedEnd <= count.intValue else { return nil }
        var ownedText: String?
        if let span {
            guard let end = span.end, end <= count.intValue else { return nil }
            var range = CFRange(location: span.location, length: span.length)
            guard let value = AXValueCreate(.cfRange, &range) else { return nil }
            var raw: CFTypeRef?
            guard AXUIElementCopyParameterizedAttributeValue(target.element, kAXStringForRangeParameterizedAttribute as CFString,
                                                             value, &raw) == .success,
                  let text = raw as? String else { return nil }
            ownedText = text
        }
        return .init(owner: target.owner, fieldID: target.id, selection: selection,
                     characterCount: count.intValue, ownedText: ownedText)
    }

    private static func focusedEditableField() -> Field? {
        let system = AXUIElementCreateSystemWide()
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier, !app.isTerminated,
              let raw = attribute(system, kAXFocusedUIElementAttribute),
              CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        // The CF type has been checked before casting.
        // swiftlint:disable:next force_cast
        let element = raw as! AXUIElement
        var pid: pid_t = 0
        // Bound messages to this field, without changing the process-wide AX timeout.
        guard AXUIElementSetMessagingTimeout(element, 0.2) == .success,
              AXUIElementGetPid(element, &pid) == .success, pid == app.processIdentifier else { return nil }
        var rawSubrole: CFTypeRef?
        let subrole: TextInsertionReceipt.FieldSubrole
        switch AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &rawSubrole) {
        case .success:
            subrole = (rawSubrole as? String).map { .named($0) } ?? .unreadable
        case .noValue:
            subrole = .absent
        default:
            // Unsupported, timeout and wrong-type subroles are not proof of a nonsecure field.
            subrole = .unreadable
        }
        func canSet(_ name: String) -> Bool {
            var settable = DarwinBoolean(false)
            return AXUIElementIsAttributeSettable(element, name as CFString, &settable) == .success && settable.boolValue
        }
        // Both setters must be supported; no fallback to replacing an entire AXValue.
        guard TextInsertionReceipt.supportsField(role: attribute(element, kAXRoleAttribute) as? String,
                                                  subrole: subrole,
                                                  canSelectRange: canSet(kAXSelectedTextRangeAttribute),
                                                  canReplaceSelection: canSet(kAXSelectedTextAttribute)) else { return nil }
        return Field(element: element, owner: .init(pid: pid, bundleID: bundleID), id: UUID())
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    private static func selection(_ element: AXUIElement) -> TextInsertionReceipt.Span? {
        guard let raw = attribute(element, kAXSelectedTextRangeAttribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        // swiftlint:disable:next force_cast
        let value = raw as! AXValue
        var range = CFRange()
        guard AXValueGetType(value) == .cfRange, AXValueGetValue(value, .cfRange, &range) else { return nil }
        return .init(location: range.location, length: range.length)
    }
}
