import CoreGraphics
import Foundation

/// A short handle for one element of one accessibility snapshot: "s<snapshot>:e<n>". A ref only
/// means something inside the snapshot that issued it; once a newer snapshot is taken it is stale.
/// (The ref idea comes from agent-desktop, Apache-2.0, Vercel; this is a Swift re-telling.)
public struct AXRef: Hashable, Sendable, CustomStringConvertible {
    public let snapshot: Int
    public let index: Int

    public init(snapshot: Int, index: Int) {
        self.snapshot = snapshot
        self.index = index
    }

    /// Reads "s12:e4", also written "@s12:e4" or "[s12:e4]".
    public init?(_ text: String) {
        var body = Substring(text.trimmingCharacters(in: .whitespaces).lowercased())
        if body.hasPrefix("@") { body = body.dropFirst() }
        if body.hasPrefix("["), body.hasSuffix("]") { body = body.dropFirst().dropLast() }
        let parts = body.split(separator: ":")
        guard parts.count == 2, parts[0].hasPrefix("s"), parts[1].hasPrefix("e"),
              let snapshot = Int(parts[0].dropFirst()), let index = Int(parts[1].dropFirst()),
              snapshot > 0, index > 0 else { return nil }
        self.init(snapshot: snapshot, index: index)
    }

    public var description: String { "s\(snapshot):e\(index)" }
}

public enum AXSnapshotError: Error, Equatable, Sendable {
    /// Not a ref at all.
    case malformedRef(String)
    /// The ref came from an older (or other) snapshot. Take a new snapshot and look again.
    case staleRef(ref: String, current: Int)
    /// The right snapshot, but no element with that number.
    case unknownRef(String)
}

/// One element as the snapshot saw it. Frames are Quartz points (top-left of the main screen).
public struct AXSnapshotElement: Equatable, Sendable {
    public internal(set) var ref: AXRef
    public var role: String
    public var subrole: String?
    /// The best human label: title, else description, else placeholder.
    public var label: String?
    /// Never filled for secure text fields.
    public var value: String?
    public var enabled: Bool
    public var focused: Bool
    public var frame: CGRect
    public var actions: [String]

    public init(role: String, subrole: String? = nil, label: String? = nil, value: String? = nil, enabled: Bool = true,
                focused: Bool = false, frame: CGRect = .zero, actions: [String] = []) {
        self.ref = AXRef(snapshot: 0, index: 0)
        self.role = role
        self.subrole = subrole
        self.label = label
        self.value = value
        self.enabled = enabled
        self.focused = focused
        self.frame = frame
        self.actions = actions
    }

    public var isSecure: Bool { role == "AXSecureTextField" || subrole == "AXSecureTextField" }

    static let interactiveRoles: Set<String> = [
        "AXButton", "AXCheckBox", "AXRadioButton", "AXTextField", "AXSecureTextField", "AXTextArea", "AXPopUpButton",
        "AXComboBox", "AXMenuButton", "AXMenuItem", "AXMenuBarItem", "AXLink", "AXSlider", "AXIncrementor",
        "AXDisclosureTriangle", "AXColorWell", "AXSearchField", "AXStepper", "AXSegmentedControl",
    ]
    static let interactiveActions: Set<String> = ["AXPress", "AXShowMenu", "AXIncrement", "AXPick", "AXConfirm"]

    public var isInteractive: Bool {
        Self.interactiveRoles.contains(role) || actions.contains { Self.interactiveActions.contains($0) }
    }

    /// "button", "checkbox", "switch", "securefield"...
    public var shortRole: String {
        if isSecure { return "securefield" }
        switch subrole {
        case "AXSwitch": return "switch"
        case "AXSearchField": return "searchfield"
        case "AXTabButton": return "tab"
        default: break
        }
        switch role {
        case "AXPopUpButton": return "popup"
        case "AXRadioButton": return "radio"
        case "AXStaticText": return "text"
        case "AXDisclosureTriangle": return "disclosure"
        default: return role.hasPrefix("AX") ? String(role.dropFirst(2)).lowercased() : role.lowercased()
        }
    }

    /// Checkboxes, switches and radios report 0, 1 or 2 (mixed).
    public var isOnOff: Bool { ["AXCheckBox", "AXRadioButton", "AXSwitch"].contains(role) || subrole == "AXSwitch" }

    /// One line of the brain's view: `button "New Note" [s3:e7]`, plus state when it matters.
    func line() -> String {
        var text = shortRole
        if let label, !label.isEmpty { text += " \"\(Self.clip(label, 60))\"" }
        if isOnOff, let value { text += value == "1" ? " on" : value == "0" ? " off" : " mixed" }
        else if !isSecure, let value, !value.isEmpty, value != label { text += " = \"\(Self.clip(value, 40))\"" }
        if !enabled { text += " disabled" }
        if focused { text += " focused" }
        return text + " [\(ref)]"
    }

    static func clip(_ text: String, _ limit: Int) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        return flat.count > limit ? String(flat.prefix(limit)) + "..." : flat
    }
}

/// What the frontmost window looked like to Accessibility at one moment. Refs are numbered in walk
/// order and belong to this snapshot only. Lookup, the nearest match, the order, and the text are
/// read from `AXSnapshotBox`.
public struct AXSnapshot: Equatable, Sendable {
    public let id: Int
    public let app: String
    public let window: String?
    public let elements: [AXSnapshotElement]
    /// True when the walk stopped at the element cap or the time budget.
    public let truncated: Bool

    public init(id: Int, app: String, window: String? = nil, elements: [AXSnapshotElement], truncated: Bool = false) {
        self.id = id
        self.app = app
        self.window = window
        self.elements = elements.enumerated().map { offset, element in
            var numbered = element
            numbered.ref = AXRef(snapshot: id, index: offset + 1)
            return numbered
        }
        self.truncated = truncated
    }

    /// The element for `ref`, or `.staleRef` when the ref belongs to another snapshot.
    public func element(_ ref: String) throws -> AXSnapshotElement {
        switch AXSnapshotBox.lookup(ref, snapshot: id, count: elements.count) {
        case .found(let index):
            return elements[index]
        case .malformed:
            throw AXSnapshotError.malformedRef(ref)
        case .stale(let shown, let current):
            throw AXSnapshotError.staleRef(ref: shown, current: current)
        case .unknown(let shown):
            throw AXSnapshotError.unknownRef(shown)
        }
    }

    /// The element in this snapshot that is most likely `old` from an earlier one: same role and
    /// label, nearest on screen. Nil when `old` had no label to go by.
    public func relocate(_ old: AXSnapshotElement) -> AXSnapshotElement? {
        let oldSpot = AXSnapshotBox.Spot(
            role: old.role, label: old.label, midX: Double(old.frame.midX), midY: Double(old.frame.midY))
        let spots = elements.map {
            AXSnapshotBox.Spot(role: $0.role, label: $0.label, midX: Double($0.frame.midX), midY: Double($0.frame.midY))
        }
        guard let index = AXSnapshotBox.relocateIndex(old: oldSpot, among: spots) else { return nil }
        return elements[index]
    }

    /// The elements worth showing, in order: enabled controls first, then labelled text and the
    /// rest, each group in walk order. Unlabelled containers are left out.
    public var ranked: [AXSnapshotElement] {
        let rows = elements.map {
            AXSnapshotBox.Row(
                interactive: $0.isInteractive, enabled: $0.enabled,
                hasLabel: !($0.label ?? "").isEmpty, hasValue: !($0.value ?? "").isEmpty)
        }
        return AXSnapshotBox.rankedIndexes(rows).map { elements[$0] }
    }

    /// The compact text the brain reads: one line per element, at most `limit` lines.
    public func render(limit: Int = 40) -> String {
        let ranked = ranked
        return AXSnapshotBox.render(
            app: app, window: window, snapshot: id, body: ranked.map { $0.line() }, limit: limit, truncated: truncated)
    }
}
