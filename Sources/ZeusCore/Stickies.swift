import CoreGraphics
import Foundation

/// A sticky note: Markdown text, a colour, and where it lives on screen.
public struct StickyNote: Codable, Equatable, Identifiable, Sendable {
    public enum Tint: String, Codable, CaseIterable, Identifiable, Sendable {
        case bolt, sky, leaf, ember, violet, cloud
        public var id: String { rawValue }
        public var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
    }

    public enum Edge: String, Codable, CaseIterable, Sendable { case left, right }

    /// Floating somewhere on screen, or tucked against a screen edge as a slim tab.
    public enum Placement: Codable, Equatable, Sendable {
        case floating(CGRect)
        case edge(Edge, top: Double)
    }

    public var id: UUID
    public var text: String
    public var tint: Tint
    public var placement: Placement
    public var created: Date
    public var updated: Date

    public init(id: UUID = UUID(), text: String = "", tint: Tint = .bolt, placement: Placement = .floating(CGRect(x: 120, y: 120, width: 260, height: 220)),
                created: Date = Date()) {
        self.id = id
        self.text = text
        self.tint = tint
        self.placement = placement
        self.created = created
        updated = created
    }

    /// The first non-empty line, without Markdown markers, for titles and VoiceOver.
    public var title: String {
        let line = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? ""
        let stripped = line.drop { "#>-*+ ".contains($0) }.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
        guard !stripped.isEmpty else { return "Empty note" }
        return stripped.count > 40 ? String(stripped.prefix(39)) + "…" : stripped
    }

    public var isOnEdge: Bool {
        if case .edge = placement { return true }
        return false
    }
}

/// Stickies as one JSON file in Application Support, written atomically.
public struct StickyStore: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    public static var standard: StickyStore {
        StickyStore(url: ZeusPaths.supportDirectory.appendingPathComponent("stickies.json"))
    }

    public func load() -> [StickyNote] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([StickyNote].self, from: data)) ?? []
    }

    public func save(_ notes: [StickyNote]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(notes).write(to: url, options: .atomic)
    }
}

/// Where an edge-shelf sticky sits: a slim tab when tucked away, the full card when it slides
/// out on hover. Pure geometry so it can be tested.
public enum EdgeShelf {
    public static let tabWidth: Double = EdgeShelfBox.tabWidth
    public static let cardSize = CGSize(width: EdgeShelfBox.cardWidth, height: EdgeShelfBox.cardHeight)

    /// `visible` is the screen's visible frame (AppKit coordinates, origin bottom-left).
    /// `top` is the distance from the top of the visible frame to the card's top.
    public static func frame(edge: StickyNote.Edge, top: Double, expanded: Bool, visible: CGRect,
                             size: CGSize = cardSize) -> CGRect {
        let rect = EdgeShelfBox.frame(
            edge: edge == .left ? .left : .right,
            top: top,
            expanded: expanded,
            visibleMinX: Double(visible.minX),
            visibleMaxX: Double(visible.maxX),
            visibleMaxY: Double(visible.maxY),
            visibleHeight: Double(visible.height),
            width: Double(size.width),
            height: Double(size.height))
        return CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
    }

    /// The edge a floating card was dropped nearest to, if it is within `snap` points of it.
    public static func snapEdge(for frame: CGRect, visible: CGRect,
                                snap: Double = EdgeShelfBox.snapDistance) -> StickyNote.Edge? {
        switch EdgeShelfBox.snapEdge(
            frameMinX: Double(frame.minX),
            frameMaxX: Double(frame.maxX),
            visibleMinX: Double(visible.minX),
            visibleMaxX: Double(visible.maxX),
            snap: snap) {
        case .left: .left
        case .right: .right
        case nil: nil
        }
    }

    /// The `top` value that keeps a card where it was dropped.
    public static func top(for frame: CGRect, visible: CGRect) -> Double {
        EdgeShelfBox.top(frameMaxY: Double(frame.maxY), visibleMaxY: Double(visible.maxY))
    }
}
