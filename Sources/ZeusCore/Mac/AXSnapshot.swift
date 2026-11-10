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
/// order and belong to this snapshot only.
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
        guard let parsed = AXRef(ref) else { throw AXSnapshotError.malformedRef(ref) }
        guard parsed.snapshot == id else { throw AXSnapshotError.staleRef(ref: parsed.description, current: id) }
        guard elements.indices.contains(parsed.index - 1) else { throw AXSnapshotError.unknownRef(parsed.description) }
        return elements[parsed.index - 1]
    }

    /// The element in this snapshot that is most likely `old` from an earlier one: same role and
    /// label, nearest on screen. Nil when `old` had no label to go by.
    public func relocate(_ old: AXSnapshotElement) -> AXSnapshotElement? {
        guard let label = old.label?.lowercased(), !label.isEmpty else { return nil }
        let center = CGPoint(x: old.frame.midX, y: old.frame.midY)
        return elements.filter { $0.role == old.role && $0.label?.lowercased() == label }
            .min { Self.distance($0.frame, center) < Self.distance($1.frame, center) }
    }

    static func distance(_ frame: CGRect, _ point: CGPoint) -> Double {
        hypot(frame.midX - point.x, frame.midY - point.y)
    }

    /// The elements worth showing, in order: enabled controls first, then labelled text and the
    /// rest, each group in walk order. Unlabelled containers are left out.
    public var ranked: [AXSnapshotElement] {
        let shown = elements.filter { $0.isInteractive || !($0.label ?? "").isEmpty || !($0.value ?? "").isEmpty }
        let first = shown.filter { $0.isInteractive && $0.enabled }
        let rest = shown.filter { !($0.isInteractive && $0.enabled) }
        return first + rest
    }

    /// The compact text the brain reads: one line per element, at most `limit` lines.
    public func render(limit: Int = 40) -> String {
        let ranked = ranked
        let shown = ranked.prefix(max(limit, 0))
        let place = window.map { "\(app), window \"\(AXSnapshotElement.clip($0, 60))\"" } ?? app
        var lines = ["Controls in \(place) (snapshot s\(id); use a ref like {\"ref\":\"s\(id):e1\"} to target one):"]
        lines += shown.map { "- " + $0.line() }
        let hidden = ranked.count - shown.count
        if hidden > 0 || truncated {
            lines.append("- ... \(hidden) more not listed" + (truncated ? "; the walk stopped early" : ""))
        }
        return lines.joined(separator: "\n")
    }
}
