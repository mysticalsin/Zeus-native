import Foundation

/// A receipt for text Zeus itself inserted, never a snapshot of the surrounding field.
/// All offsets use AX's UTF-16 units, rather than Swift Character counts.
public struct TextInsertionReceipt: Equatable, Sendable {
    public enum FieldSubrole: Equatable, Sendable {
        /// AX explicitly returned no value, rather than failing to read the attribute.
        case absent
        case named(String)
        case unreadable
    }

    /// Conservative AX capability policy shared with the native adapter. Unknown subroles
    /// cannot silently become ordinary fields when a secure-subrole query fails or times out.
    public static func supportsField(role: String?, subrole: FieldSubrole,
                                     canSelectRange: Bool, canReplaceSelection: Bool) -> Bool {
        guard role == "AXTextField" || role == "AXTextArea", canSelectRange, canReplaceSelection else { return false }
        switch subrole {
        case .absent: return true
        case .named("AXSearchField"): return role == "AXTextField"
        case .named, .unreadable: return false
        }
    }

    public struct Owner: Equatable, Sendable {
        public var pid: Int32
        public var bundleID: String
        public init(pid: Int32, bundleID: String) { self.pid = pid; self.bundleID = bundleID }
    }

    public struct Span: Equatable, Sendable {
        public var location: Int
        public var length: Int
        public init(location: Int, length: Int) { self.location = location; self.length = length }
        public var end: Int? {
            guard location >= 0, length >= 0 else { return nil }
            let (end, overflow) = location.addingReportingOverflow(length)
            return overflow ? nil : end
        }
    }

    /// The adapter must verify the retained native element identity, editable/nonsecure role,
    /// owning app and frontmost focus before returning a state. `ownedText` reads only `span`.
    public struct FieldState: Equatable, Sendable {
        public var owner: Owner
        public var fieldID: UUID
        public var selection: Span
        public var characterCount: Int
        public var ownedText: String?
        public init(owner: Owner, fieldID: UUID, selection: Span, characterCount: Int, ownedText: String? = nil) {
            self.owner = owner; self.fieldID = fieldID; self.selection = selection
            self.characterCount = characterCount; self.ownedText = ownedText
        }
    }

    public let owner: Owner
    public let fieldID: UUID
    public let span: Span
    public let text: String
    public let characterCount: Int

    /// A posted paste key alone never earns a receipt. Require exact native readback, a
    /// collapsed caret, and the expected count change from an originally collapsed selection.
    public static func acknowledgeInsertion(text: String, before: FieldState, after: FieldState,
                                             sendsReturn: Bool) -> Self? {
        guard !sendsReturn, !text.isEmpty, before.selection.length == 0,
              let start = before.selection.end, start <= before.characterCount else { return nil }
        let span = Span(location: start, length: text.utf16.count)
        let (count, overflow) = before.characterCount.addingReportingOverflow(span.length)
        guard !overflow, let end = span.end,
              after.owner == before.owner, after.fieldID == before.fieldID,
              after.characterCount == count, after.selection == Span(location: end, length: 0),
              after.ownedText == text else { return nil }
        return Self(owner: before.owner, fieldID: before.fieldID, span: span, text: text, characterCount: count)
    }

    public func authorizes(_ state: FieldState, selected: Bool = false) -> Bool {
        guard let end = span.end, end <= characterCount, span.length == text.utf16.count else { return false }
        return state.owner == owner && state.fieldID == fieldID && state.characterCount == characterCount
            && state.ownedText == text
            && state.selection == (selected ? span : Span(location: end, length: 0))
    }

    private func replacing(with replacement: String, state: FieldState) -> Self? {
        guard !replacement.isEmpty, characterCount >= span.length else { return nil }
        let replacementSpan = Span(location: span.location, length: replacement.utf16.count)
        let (count, overflow) = (characterCount - span.length).addingReportingOverflow(replacementSpan.length)
        guard !overflow, let end = replacementSpan.end, end <= count,
              state.owner == owner, state.fieldID == fieldID, state.characterCount == count,
              state.selection == Span(location: end, length: 0), state.ownedText == replacement else { return nil }
        return Self(owner: owner, fieldID: fieldID, span: replacementSpan, text: replacement, characterCount: count)
    }

    /// This explicit command replaces the complete preceding dictation. It deliberately does
    /// not infer an earlier word, and ignores quoted/reporting speech and within-turn corrections.
    public static func correctionPayload(_ raw: String) -> String? {
        let pattern = #"^\s*no\s*[,.:;!?—–-]?\s+i\s+meant\b\s*[,.:;!?—–-]?\s*(\S[\s\S]*)$"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = expression.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
              let range = Range(match.range(at: 1), in: raw) else { return nil }
        let payload = raw[range].trimmingCharacters(in: .whitespacesAndNewlines)
        return payload.rangeOfCharacter(from: .alphanumerics) == nil ? nil : payload
    }

    @MainActor
    public struct ReplacementSteps {
        public var isCurrent: () -> Bool
        public var inspect: (Span) -> FieldState?
        public var select: (Span) -> Bool
        public var replaceSelected: (String) -> Bool
        public var waitForAcknowledgment: () async -> Void
        public init(isCurrent: @escaping () -> Bool, inspect: @escaping (Span) -> FieldState?,
                    select: @escaping (Span) -> Bool, replaceSelected: @escaping (String) -> Bool,
                    waitForAcknowledgment: @escaping () async -> Void) {
            self.isCurrent = isCurrent; self.inspect = inspect; self.select = select
            self.replaceSelected = replaceSelected; self.waitForAcknowledgment = waitForAcknowledgment
        }
    }

    public enum ReplacementResult: Equatable, Sendable {
        case replaced(TextInsertionReceipt)
        /// No replacement was attempted. Caller may offer an explicit select-and-paste action.
        case unavailable
        case superseded
        /// A setter was invoked but the expected result could not be proved. Never retry or
        /// automatically paste: the app may have applied it despite an AX failure/timeout.
        case unconfirmed
    }

    /// Production and synthetic tests run this same executor. Selection and replacement use
    /// retained-element AX setters, never focus-dependent backspaces or key sequences.
    @MainActor
    public func replace(with replacement: String, steps: ReplacementSteps) async -> ReplacementResult {
        guard steps.isCurrent() else { return .superseded }
        guard !replacement.isEmpty, let before = steps.inspect(span), authorizes(before),
              steps.isCurrent(), steps.select(span) else { return .unavailable }
        guard steps.isCurrent(), let selected = steps.inspect(span), authorizes(selected, selected: true),
              steps.isCurrent() else { return .unavailable }
        // An error from this setter can mean a timeout after mutation: it is still unconfirmed.
        guard steps.replaceSelected(replacement) else { return .unconfirmed }
        let replacementSpan = Span(location: span.location, length: replacement.utf16.count)
        for attempt in 0..<4 {
            guard steps.isCurrent() else { return .unconfirmed }
            if let state = steps.inspect(replacementSpan), let receipt = replacing(with: replacement, state: state),
               steps.isCurrent() { return .replaced(receipt) }
            if attempt < 3 { await steps.waitForAcknowledgment() }
        }
        return .unconfirmed
    }
}
