import Foundation

/// A short, private confirmation after Zeus finishes a note, a file placement, a clipboard
/// change, or a dictation. The notch can show the title and Undo. The note body, the path,
/// the clipboard text, and the dictated words stay out of this value.
public enum PrivateActionKind: String, Sendable, Equatable, CaseIterable {
    case note, file, clipboard, dictation

    public var title: String {
        switch self {
        case .note: "Note saved"
        case .file: "File placed"
        case .clipboard: "Copied"
        case .dictation: "Dictated"
        }
    }

    public var symbol: String {
        switch self {
        case .note: "note.text"
        case .file: "doc"
        case .clipboard: "doc.on.doc.fill"
        case .dictation: "waveform"
        }
    }
}

/// Stable names for the notch receipt and its Undo control.
public enum PrivateActionReceiptID {
    public static let row = "notch.actionReceipt"
    public static let undo = "notch.actionReceipt.undo"
}

/// What the notch may show. `private` is the default: nothing here is safe to share or notify.
public struct PrivateActionReceipt: Equatable, Sendable, Identifiable {
    public enum Visibility: String, Sendable, Equatable {
        case `private`
        case shared
    }

    public var id: UUID
    public var kind: PrivateActionKind
    public var visibility: Visibility
    public var undoLabel: String

    public init(id: UUID, kind: PrivateActionKind, visibility: Visibility = .private, undoLabel: String = "Undo") {
        self.id = id
        self.kind = kind
        self.visibility = visibility
        self.undoLabel = undoLabel
    }

    public var title: String { kind.title }
    public var symbol: String { kind.symbol }
    /// The only line the notch draws. It is the fixed title, never the action's contents.
    public var notchLine: String { title }
    /// Nil while the receipt is private, which is the default. A shared receipt still carries the title only.
    public var sharedBody: String? { visibility == .shared ? title : nil }
    public var isPrivate: Bool { visibility == .private }

    /// True when `secret` shows up in a line the notch or a share may read.
    /// The fixed title is allowed to contain short ordinary words. A line that is not that title
    /// and still contains the secret is a leak.
    public func publishes(_ secret: String) -> Bool {
        let needle = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard needle.count >= 8 else { return false }
        let visible = [title, notchLine, undoLabel, sharedBody ?? ""]
        return visible.contains { field in
            field.caseInsensitiveCompare(kind.title) != .orderedSame && field.localizedCaseInsensitiveContains(needle)
        }
    }
}

/// The undo handle handed back to the performer. `token` is an id, not the hidden text.
public struct PrivateUndoEffect: Equatable, Sendable {
    public var receiptID: UUID
    public var kind: PrivateActionKind
    public var token: String

    public init(receiptID: UUID, kind: PrivateActionKind, token: String) {
        self.receiptID = receiptID
        self.kind = kind
        self.token = token
    }
}

/// Returned once, to the code that undoes the action. `restore` is not part of the receipt.
public struct PrivateUndoOutcome: Equatable, Sendable {
    public var effect: PrivateUndoEffect
    public var restore: String

    public init(effect: PrivateUndoEffect, restore: String) {
        self.effect = effect
        self.restore = restore
    }
}

/// One current receipt. A newer Zeus action replaces it. Undo works once, then the slot is dropped.
public struct PrivateActionLedger: Equatable, Sendable {
    /// How long the notch keeps the receipt so Undo can be reached.
    public static let hold: TimeInterval = 8

    public private(set) var current: PrivateActionReceipt?
    private var slot: Slot?

    public init() {}

    private struct Slot: Equatable, Sendable {
        var id: UUID
        var restore: String
        var token: String
        var kind: PrivateActionKind
    }

    /// Records a finished action. `withheld` is the private text that must not be copied onto the receipt.
    /// Empty withheld text records nothing. `share` defaults to false.
    @discardableResult
    public mutating func record(kind: PrivateActionKind, withheld: [String], restore: String, token: String,
                                 share: Bool = false, id: UUID = UUID()) -> PrivateActionReceipt? {
        let secrets = withheld.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !secrets.isEmpty else { return nil }
        let receipt = PrivateActionReceipt(id: id, kind: kind, visibility: share ? .shared : .private)
        guard secrets.allSatisfy({ !receipt.publishes($0) }) else { return nil }
        current = receipt
        slot = Slot(id: id, restore: restore, token: token, kind: kind)
        return receipt
    }

    /// Drops the receipt and its undo material. Used when the hold ends.
    public mutating func dismiss() {
        current = nil
        slot = nil
    }

    /// Undoes the current receipt once. A second call, or a call after dismiss, does nothing.
    public mutating func undo() -> PrivateUndoOutcome? {
        guard let current, let slot, slot.id == current.id else { return nil }
        let outcome = PrivateUndoOutcome(
            effect: PrivateUndoEffect(receiptID: current.id, kind: current.kind, token: slot.token),
            restore: slot.restore)
        self.current = nil
        self.slot = nil
        return outcome
    }

    /// Bare U undoes the receipt on the closed notch. The hub decision row keeps U while it is showing.
    /// Command, Shift, Option, and Control do not take this shortcut, and an open panel does not either.
    public static func claimsUndo(characters: String, command: Bool, shift: Bool, option: Bool, control: Bool,
                                   decisionRowVisible: Bool, receiptVisible: Bool, panelOpen: Bool) -> Bool {
        guard receiptVisible, !decisionRowVisible, !panelOpen else { return false }
        guard !command, !shift, !option, !control else { return false }
        return characters == "u" || characters == "U"
    }
}
