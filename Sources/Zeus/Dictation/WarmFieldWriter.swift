import ApplicationServices
import AppKit

/// Writes dictated words into a focused field, including one that already holds text.
/// Does not touch the clipboard. A secure field is left alone.
@MainActor
enum WarmFieldWriter {
    /// `captured` is the field this turn started in. The live focus is tried first.
    /// When that element cannot take another insert, the captured field is tried.
    static func write(_ text: String, captured: AXUIElement?) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        if let focused = AXFinder.focusedElement(), write(text, into: focused) { return true }
        if let captured { return write(text, into: captured) }
        return false
    }

    private static func write(_ text: String, into element: AXUIElement) -> Bool {
        let current = AXFinder.string(element, kAXValueAttribute) ?? ""
        let steps = WarmFieldInsert.steps(
            text: text,
            current: current,
            valueSettable: AXFinder.isSettable(element, kAXValueAttribute),
            selectedTextSettable: AXFinder.isSettable(element, kAXSelectedTextAttribute),
            secure: AXFinder.isSecure(element))
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for step in steps {
            let wrote: Bool
            switch step {
            case .setValue(let next):
                wrote = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, next as CFString) == .success
            case .setSelectedText(let insert):
                wrote = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, insert as CFString) == .success
            }
            guard wrote else { continue }
            if WarmFieldInsert.landed(fieldValue: AXFinder.string(element, kAXValueAttribute),
                                     selectedText: AXFinder.string(element, kAXSelectedTextAttribute),
                                     expected: trimmed) {
                return true
            }
        }
        return false
    }
}
