import Foundation

public enum SelectionKind: String, Equatable, Sendable {
    case replace, draft, insert
}

public struct TextDiffLine: Equatable, Sendable, Identifiable {
    public enum Kind: String, Equatable, Sendable { case same, removed, added }
    public var id: Int
    public var kind: Kind
    public var text: String

    public init(id: Int, kind: Kind, text: String) {
        self.id = id
        self.kind = kind
        self.text = text
    }
}

/// A selection edit. A draft never sends. The clipboard value handed back is the one we borrowed.
public struct SelectionEdit: Equatable, Sendable {
    public var kind: SelectionKind
    public var before: String
    public var after: String
    public var diff: [TextDiffLine]
    public var sends: Bool
    public var accepted: Bool

    public init(kind: SelectionKind, before: String, after: String, sends: Bool = false, accepted: Bool = false) {
        self.kind = kind
        self.before = before
        self.after = after
        self.diff = Self.lines(before: before, after: after)
        self.sends = sends
        self.accepted = accepted
    }

    public static func lines(before: String, after: String) -> [TextDiffLine] {
        if before == after { return [TextDiffLine(id: 0, kind: .same, text: before)] }
        return [
            TextDiffLine(id: 0, kind: .removed, text: before),
            TextDiffLine(id: 1, kind: .added, text: after),
        ]
    }
}

public struct ClipboardGuard: Equatable, Sendable {
    public var saved: String?

    public init(current: String?) { saved = current }

    /// Whatever a paste-only field borrowed, the clipboard goes back to this.
    public func restored() -> String? { saved }
}

public struct SelectionEditSession: Equatable, Sendable {
    public var edit: SelectionEdit
    public var clipboard: ClipboardGuard
    public var sendPressed: Bool

    public init(edit: SelectionEdit, clipboard: String?) {
        self.edit = edit
        self.clipboard = ClipboardGuard(current: clipboard)
        self.sendPressed = false
    }

    public mutating func accept() {
        edit.accepted = true
        sendPressed = false
    }

    /// The field after Return. A draft inserts the new text and still does not send.
    public var appliedText: String? {
        guard edit.accepted else { return nil }
        switch edit.kind {
        case .replace: return edit.after
        case .draft, .insert: return edit.after
        }
    }
}

public enum SelectionRewrite {
    public static func plan(utterance: String, selection: String) -> SelectionEdit? {
        let trimmed = utterance.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower.hasPrefix("reply to this") {
            let rest = trimmed.dropFirst("reply to this".count)
            var body = rest.trimmingCharacters(in: .whitespacesAndNewlines)
            if body.hasPrefix(".") { body = body.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines) }
            if body.isEmpty { body = selection }
            return SelectionEdit(kind: .draft, before: selection, after: String(body), sends: false)
        }
        if lower.hasPrefix("insert ") {
            let body = trimmed.dropFirst("insert ".count).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { return nil }
            return SelectionEdit(kind: .insert, before: selection, after: body, sends: false)
        }
        if lower.contains("shorter") {
            return SelectionEdit(kind: .replace, before: selection, after: shorter(selection), sends: false)
        }
        return nil
    }

    /// Keeps the first half of the words. No model call.
    public static func shorter(_ text: String) -> String {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count > 1 else { return text }
        return words.prefix(max(words.count / 2, 1)).joined(separator: " ")
    }
}

public enum SelectionAcceptance {
    public static func report() -> (text: String, passed: Bool) {
        var problems: [String] = []
        let clip = "copied-note"
        guard let shorter = SelectionRewrite.plan(utterance: "make this shorter", selection: "hello there friend") else {
            return ("FAIL shorter", false)
        }
        var replace = SelectionEditSession(edit: shorter, clipboard: clip)
        if shorter.kind != .replace || shorter.after != "hello" || shorter.sends { problems.append("shorter") }
        if shorter.diff.contains(where: { $0.kind == .removed && $0.text == "hello there friend" }) == false { problems.append("diff") }
        replace.accept()
        if replace.appliedText != "hello" || replace.clipboard.restored() != clip || replace.sendPressed { problems.append("restore") }

        guard let reply = SelectionRewrite.plan(utterance: "Reply to this. Thursday works", selection: "Can you do Thursday?") else {
            return ("FAIL draft", false)
        }
        var draft = SelectionEditSession(edit: reply, clipboard: clip)
        let sendBefore = draft.sendPressed
        draft.accept()
        if reply.kind != .draft || reply.sends || reply.after != "Thursday works" || draft.sendPressed != sendBefore || draft.sendPressed {
            problems.append("draft")
        }
        let text = problems.isEmpty ? "PASS replace=hello draft=Thursday works clipboard=\(clip) sends=false" : "FAIL \(problems.joined(separator: ", "))"
        return (text, problems.isEmpty)
    }
}
