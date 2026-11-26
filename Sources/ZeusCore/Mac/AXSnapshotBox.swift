import Foundation

/// Lookup, nearest-match, ranking, and render rules for one accessibility snapshot.
/// Frames stay on `AXSnapshot`. This type takes the numbers and the flags.
public enum AXSnapshotBox {
    public struct Spot: Equatable, Sendable {
        public var role: String
        public var label: String?
        public var midX: Double
        public var midY: Double

        public init(role: String, label: String?, midX: Double, midY: Double) {
            self.role = role
            self.label = label
            self.midX = midX
            self.midY = midY
        }
    }

    /// What ranking needs from one element. The caller decides interactive from the role and the actions.
    public struct Row: Equatable, Sendable {
        public var interactive: Bool
        public var enabled: Bool
        public var hasLabel: Bool
        public var hasValue: Bool

        public init(interactive: Bool, enabled: Bool, hasLabel: Bool, hasValue: Bool) {
            self.interactive = interactive
            self.enabled = enabled
            self.hasLabel = hasLabel
            self.hasValue = hasValue
        }
    }

    /// `found` is the zero-based element index. The other cases carry the canonical ref, `s<n>:e<m>`.
    public enum Lookup: Equatable, Sendable {
        case found(Int)
        case malformed
        case stale(ref: String, current: Int)
        case unknown(ref: String)
    }

    /// Reads "s12:e4", also written "@s12:e4" or "[s12:e4]". A ref from another snapshot is stale.
    /// An index past `count` is unknown. Anything else is malformed.
    public static func lookup(_ text: String, snapshot: Int, count: Int) -> Lookup {
        guard let parsed = parse(text) else { return .malformed }
        let shown = "s\(parsed.snapshot):e\(parsed.index)"
        guard parsed.snapshot == snapshot else { return .stale(ref: shown, current: snapshot) }
        let offset = parsed.index - 1
        guard offset >= 0, offset < count else { return .unknown(ref: shown) }
        return .found(offset)
    }

    /// Distance between a frame's middle and a point. The same middle is zero.
    public static func distance(midX: Double, midY: Double, x: Double, y: Double) -> Double {
        return hypot(midX - x, midY - y)
    }

    /// The earlier element wins when two matches sit at the same distance. Nil when `old` has no label.
    public static func relocateIndex(old: Spot, among spots: [Spot]) -> Int? {
        guard let label = old.label?.lowercased(), !label.isEmpty else { return nil }
        return spots.enumerated().filter { _, spot in
            spot.role == old.role && spot.label?.lowercased() == label
        }.min { lhs, rhs in
            distance(midX: lhs.element.midX, midY: lhs.element.midY, x: old.midX, y: old.midY)
                < distance(midX: rhs.element.midX, midY: rhs.element.midY, x: old.midX, y: old.midY)
        }?.offset
    }

    /// Enabled controls first, then the other shown rows, each group in walk order.
    /// A row with no control, no label, and no value is left out.
    public static func rankedIndexes(_ rows: [Row]) -> [Int] {
        let shown = rows.enumerated().filter { _, row in
            row.interactive || row.hasLabel || row.hasValue
        }
        let first = shown.filter { $0.element.interactive && $0.element.enabled }
        let rest = shown.filter { !($0.element.interactive && $0.element.enabled) }
        return (first + rest).map(\.offset)
    }

    /// The compact text the brain reads. `body` is already one line per ranked element, without the dash.
    /// A window name loses its line breaks and keeps the first 60 characters.
    public static func render(app: String, window: String?, snapshot: Int, body: [String], limit: Int, truncated: Bool) -> String {
        let shown = body.prefix(max(limit, 0))
        let place = window.map { "\(app), window \"\(clip($0, 60))\"" } ?? app
        var lines = ["Controls in \(place) (snapshot s\(snapshot); use a ref like {\"ref\":\"s\(snapshot):e1\"} to target one):"]
        lines += shown.map { "- \($0)" }
        let hidden = body.count - shown.count
        if hidden > 0 || truncated {
            lines.append("- ... \(hidden) more not listed" + (truncated ? "; the walk stopped early" : ""))
        }
        return lines.joined(separator: "\n")
    }

    private static func parse(_ text: String) -> (snapshot: Int, index: Int)? {
        var body = Substring(text.trimmingCharacters(in: .whitespaces).lowercased())
        if body.hasPrefix("@") { body = body.dropFirst() }
        if body.hasPrefix("["), body.hasSuffix("]") { body = body.dropFirst().dropLast() }
        let parts = body.split(separator: ":")
        guard parts.count == 2, parts[0].hasPrefix("s"), parts[1].hasPrefix("e"),
              let snapshot = Int(parts[0].dropFirst()), let index = Int(parts[1].dropFirst()),
              snapshot > 0, index > 0 else { return nil }
        return (snapshot, index)
    }

    /// Newlines become spaces, then the first `limit` characters. `AXSnapshotElement.clip` does this for a line.
    private static func clip(_ text: String, _ limit: Int) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        return flat.count > limit ? String(flat.prefix(limit)) + "..." : flat
    }
}
