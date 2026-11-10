import Foundation

/// L4: a short visual answer card shown in the notch HUD (steps, list, or chart title).
public struct PresentCard: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case steps
        case list
        case chart
        case note
    }

    public var kind: Kind
    public var title: String
    public var lines: [String]

    public init(kind: Kind, title: String, lines: [String]) {
        self.kind = kind
        self.title = title
        self.lines = Array(lines.prefix(12))
    }

    public static func parse(_ payload: [String: JSONValue]) -> PresentCard? {
        guard let kindRaw = payload["kind"]?.stringValue ?? payload["type"]?.stringValue,
              let kind = Kind(rawValue: kindRaw) else { return nil }
        let title = payload["title"]?.stringValue ?? ""
        let lines = payload["lines"]?.arrayValue?.compactMap(\.stringValue)
            ?? payload["steps"]?.arrayValue?.compactMap(\.stringValue)
            ?? []
        guard !title.isEmpty || !lines.isEmpty else { return nil }
        return PresentCard(kind: kind, title: title, lines: lines)
    }
}
