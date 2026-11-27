import Foundation

/// A short answer card. The voice says the sentences. The bolt shows one short line.
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

    /// The sentence to speak and the line the bolt may show. Nil when the card has no words.
    public struct Shown: Equatable, Sendable {
        public var spoken: String
        public var bolt: String

        public init(spoken: String, bolt: String) {
            self.spoken = spoken
            self.bolt = bolt
        }
    }

    public func shown() -> Shown? {
        let parts = ([title] + lines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard let first = parts.first else { return nil }
        let spoken = parts.map { part -> String in
            guard let end = part.last, end == "." || end == "?" || end == "!" else { return part + "." }
            return part
        }.joined(separator: " ")
        let bolt = PointerGuideCaptionSplit.boltText(title)
            ?? PointerGuideCaptionSplit.oneLine(title.isEmpty ? first : title)
            ?? PointerGuideCaptionSplit.oneLine(first)
            ?? "Here"
        guard PointerGuideCaptionSplit.boltText(bolt) == bolt else { return nil }
        return Shown(spoken: spoken, bolt: bolt)
    }
}
