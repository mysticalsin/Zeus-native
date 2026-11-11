import Foundation

/// What the desktop explanation card needs to know to be placed. Pure value types: no AppKit,
/// no screen reads, so every rule is testable. All rectangles share one coordinate space,
/// AppKit global points with a bottom-left origin (negative origins and several displays are
/// normal), and "above" means a larger y.
public struct ExplanationCardContent: Equatable, Sendable {
    /// Fitted size of the 2D diagram in canvas units, or nil when there is none.
    public var visual: ExplanationSize2?
    public var hasWorld: Bool
    public var captionCharacters: Int
    public init(visual: ExplanationSize2? = nil, hasWorld: Bool = false, captionCharacters: Int = 0) {
        self.visual = visual; self.hasWorld = hasWorld; self.captionCharacters = captionCharacters
    }
}

public struct ExplanationCardRequest: Equatable, Sendable {
    /// The turn display's visible frame: the menu bar and a docked Dock are already excluded.
    public var usable: ExplanationRect
    /// The subject the short connector points at (the pointed-at control or the marks on it).
    public var anchor: ExplanationRect?
    /// Never covered: target bounds, the pointer trail's bounding box, the active input area.
    public var protected: [ExplanationRect]
    /// Bands the card may not use even though they lie inside `usable` (an auto-hidden Dock edge).
    public var reserved: [ExplanationRect]
    public var content: ExplanationCardContent
    /// The current beat's objects alone. Present only when it differs from `content`; it enables
    /// the "split into beats" rung.
    public var beat: ExplanationCardContent?
    public init(usable: ExplanationRect, anchor: ExplanationRect? = nil, protected: [ExplanationRect] = [],
                reserved: [ExplanationRect] = [], content: ExplanationCardContent, beat: ExplanationCardContent? = nil) {
        self.usable = usable; self.anchor = anchor; self.protected = protected; self.reserved = reserved
        self.content = content; self.beat = beat
    }
}

public struct ExplanationCardConnector: Equatable, Sendable {
    public var from: ExplanationVector3
    public var to: ExplanationVector3
}

/// Which step of the fallback ladder produced the result. Order: preferred spot at full size,
/// moved elsewhere at full size, shrunk (compact tier, nonessential content dropped), split into
/// beats, then speech only.
public enum ExplanationCardRung: Int, Equatable, Sendable, Comparable {
    case preferred, moved, shrunk, split, speechOnly
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

public enum ExplanationCardTier: Int, Equatable, Sendable { case full, compact, minimum }

public struct ExplanationCardLayout: Equatable, Sendable {
    public var rung: ExplanationCardRung
    /// nil only for `.speechOnly`.
    public var frame: ExplanationRect?
    public var tier: ExplanationCardTier
    public var showsWorld: Bool
    /// Only the current beat's objects are shown.
    public var beatOnly: Bool
    /// Canvas units to card points. Never below `ExplanationCardPlacement.minimumVisualScale`.
    public var visualScale: Double
    /// Section sizes in card points, so the view can match the arithmetic exactly.
    public var visualSize: ExplanationSize2?
    public var worldHeight: Double
    public var captionHeight: Double
    public var connector: ExplanationCardConnector?
}

public enum ExplanationCardPlacement {
    public static let edgeInset = 12.0
    public static let protectedMargin = 12.0
    public static let connectorGap = 20.0
    public static let maxConnectorDistance = 320.0
    /// Diagram text is drawn at a fixed point size, so the scale floor is what keeps a diagram readable.
    public static let minimumVisualScale = 0.5
    public static let maximumVisualScale = 1.5
    public static let captionFontSize = 13.0
    public static let tierWidths: [ExplanationCardTier: Double] = [.full: 460, .compact: 380, .minimum: 320]
    public static let sidePadding = 12.0, headerHeight = 32.0, sectionGap = 8.0, bottomPadding = 12.0
    public static let captionLineHeight = 18.0, captionPadding = 12.0
    static let gridStep = 24.0, maxCardHeight = 640.0
    /// A caption is the exact spoken text and is never clipped or shrunk, so one that needs more
    /// lines than this has no card (speech only).
    static let maxCaptionLines = 12

    /// Lines the caption needs, from the caption font size (a glyph averages about 0.6 em).
    static func captionLines(characters: Int, width: Double) -> Int {
        guard characters > 0 else { return 0 }
        let perLine = max(8, Int((width - 2 * sidePadding) / (captionFontSize * 0.6)))
        return max(1, (characters + perLine - 1) / perLine)
    }

    struct Size {
        var width: Double; var height: Double; var scale: Double; var showsWorld: Bool
        var visual: ExplanationSize2?; var worldHeight: Double; var captionHeight: Double
    }

    /// The card's size for one tier, or nil when the diagram would fall below the readable scale.
    static func sizing(for content: ExplanationCardContent, tier: ExplanationCardTier, maxHeight: Double) -> Size? {
        guard let width = tierWidths[tier] else { return nil }
        // The 3D view is nonessential beside a diagram: only the full tier keeps it.
        let showsWorld = content.hasWorld && (content.visual == nil || tier == .full)
        let worldHeight = showsWorld ? (tier == .full ? 220.0 : tier == .compact ? 190.0 : 170.0) : 0
        let lines = captionLines(characters: content.captionCharacters, width: width)
        guard lines <= maxCaptionLines else { return nil }
        let captionHeight = lines == 0 ? 0 : Double(lines) * captionLineHeight + captionPadding
        var fixed = headerHeight + bottomPadding
        if worldHeight > 0 { fixed += sectionGap + worldHeight }
        if captionHeight > 0 { fixed += sectionGap + captionHeight }
        var scale = 1.0, visualHeight = 0.0
        if let visual = content.visual {
            guard visual.width.isFinite, visual.height.isFinite, visual.width > 0, visual.height > 0 else { return nil }
            fixed += sectionGap
            scale = min(maximumVisualScale, (width - 2 * sidePadding) / visual.width, (maxHeight - fixed) / visual.height)
            guard scale >= minimumVisualScale else { return nil }
            visualHeight = visual.height * scale
        }
        let height = fixed + visualHeight
        guard height <= maxHeight else { return nil }
        return Size(width: width, height: height, scale: scale, showsWorld: showsWorld,
                    visual: content.visual.map { ExplanationSize2(width: $0.width * scale, height: $0.height * scale) },
                    worldHeight: worldHeight, captionHeight: captionHeight)
    }

    public static func place(_ request: ExplanationCardRequest) -> ExplanationCardLayout {
        let area = inset(request.usable, by: edgeInset)
        let maxHeight = min(area.height, maxCardHeight)
        var blocked = request.protected.map { inflate($0, by: protectedMargin) } + request.reserved
        if let anchor = request.anchor { blocked.append(inflate(anchor, by: protectedMargin)) }
        let focus = request.anchor ?? request.protected.first

        func attempt(_ content: ExplanationCardContent, tier: ExplanationCardTier)
            -> (frame: ExplanationRect, size: Size, base: Bool)? {
            guard let size = sizing(for: content, tier: tier, maxHeight: maxHeight),
                  size.width <= area.width, size.height <= area.height,
                  let spot = bestSpot(width: size.width, height: size.height, area: area, blocked: blocked,
                                      anchor: request.anchor, focus: focus) else { return nil }
            return (spot.frame, size, spot.base)
        }
        func layout(_ rung: ExplanationCardRung, _ found: (frame: ExplanationRect, size: Size, base: Bool),
                    tier: ExplanationCardTier, beatOnly: Bool) -> ExplanationCardLayout {
            ExplanationCardLayout(rung: rung, frame: found.frame, tier: tier, showsWorld: found.size.showsWorld,
                                  beatOnly: beatOnly, visualScale: found.size.scale, visualSize: found.size.visual,
                                  worldHeight: found.size.worldHeight, captionHeight: found.size.captionHeight,
                                  connector: request.anchor.map { connector(card: found.frame, anchor: $0) })
        }

        if let found = attempt(request.content, tier: .full) {
            return layout(found.base ? .preferred : .moved, found, tier: .full, beatOnly: false)
        }
        for tier in [ExplanationCardTier.compact, .minimum] {
            if let found = attempt(request.content, tier: tier) { return layout(.shrunk, found, tier: tier, beatOnly: false) }
        }
        if let beat = request.beat, beat != request.content {
            for tier in [ExplanationCardTier.full, .compact, .minimum] {
                if let found = attempt(beat, tier: tier) { return layout(.split, found, tier: tier, beatOnly: true) }
            }
        }
        return ExplanationCardLayout(rung: .speechOnly, frame: nil, tier: .minimum, showsWorld: false,
                                     beatOnly: false, visualScale: 0, visualSize: nil, worldHeight: 0,
                                     captionHeight: 0, connector: nil)
    }

    // MARK: Candidate search

    /// Base candidates hug the anchor on each side, in a fixed preference order. If none is free the
    /// whole usable area is scanned on a grid ("moved"), and a candidate farther than the connector
    /// limit from the anchor is refused.
    static func bestSpot(width: Double, height: Double, area: ExplanationRect, blocked: [ExplanationRect],
                         anchor: ExplanationRect?, focus: ExplanationRect?) -> (frame: ExplanationRect, base: Bool)? {
        func fits(_ rect: ExplanationRect) -> Bool {
            guard contains(area, rect) else { return false }
            if blocked.contains(where: { intersects($0, rect) }) { return false }
            if let anchor, distance(rect, anchor) > maxConnectorDistance { return false }
            return true
        }
        func clamped(_ x: Double, _ y: Double) -> ExplanationRect {
            ExplanationRect(x: min(max(x, area.x), area.x + area.width - width),
                            y: min(max(y, area.y), area.y + area.height - height), width: width, height: height)
        }
        var base: [ExplanationRect] = []
        if let a = focus {
            let g = connectorGap
            let midY = a.y + a.height / 2 - height / 2, midX = a.x + a.width / 2 - width / 2
            let right = a.x + a.width + g, left = a.x - g - width
            let above = a.y + a.height + g, below = a.y - g - height
            base = [clamped(right, midY), clamped(left, midY), clamped(midX, above), clamped(midX, below),
                    clamped(right, a.y + a.height - height), clamped(right, a.y),
                    clamped(left, a.y + a.height - height), clamped(left, a.y),
                    clamped(a.x, above), clamped(a.x + a.width - width, above),
                    clamped(a.x, below), clamped(a.x + a.width - width, below)]
        } else {
            let right = area.x + area.width - width, top = area.y + area.height - height
            base = [clamped(right, top), clamped(area.x, top), clamped(right, area.y), clamped(area.x, area.y)]
        }
        if let first = base.first(where: fits) { return (first, true) }
        var best: (frame: ExplanationRect, distance: Double)?
        var x = area.x
        while x <= area.x + area.width - width + 0.001 {
            var y = area.y
            while y <= area.y + area.height - height + 0.001 {
                let candidate = ExplanationRect(x: x, y: y, width: width, height: height)
                if fits(candidate) {
                    let d = focus.map { distance(candidate, $0) } ?? 0
                    if best == nil || d < best!.distance { best = (candidate, d) }
                }
                y += gridStep
            }
            x += gridStep
        }
        return best.map { ($0.frame, false) }
    }

    static func connector(card: ExplanationRect, anchor: ExplanationRect) -> ExplanationCardConnector {
        let target = ExplanationVector3(x: anchor.x + anchor.width / 2, y: anchor.y + anchor.height / 2)
        let from = ExplanationVector3(x: min(max(target.x, card.x), card.x + card.width),
                                      y: min(max(target.y, card.y), card.y + card.height))
        let to = ExplanationVector3(x: min(max(from.x, anchor.x), anchor.x + anchor.width),
                                    y: min(max(from.y, anchor.y), anchor.y + anchor.height))
        return ExplanationCardConnector(from: from, to: to)
    }

    // MARK: Rectangle helpers (exact, no rounding)

    public static func intersects(_ a: ExplanationRect, _ b: ExplanationRect) -> Bool {
        a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height
    }
    static func contains(_ outer: ExplanationRect, _ inner: ExplanationRect) -> Bool {
        inner.x >= outer.x - 0.001 && inner.y >= outer.y - 0.001
            && inner.x + inner.width <= outer.x + outer.width + 0.001
            && inner.y + inner.height <= outer.y + outer.height + 0.001
    }
    static func inflate(_ rect: ExplanationRect, by amount: Double) -> ExplanationRect {
        ExplanationRect(x: rect.x - amount, y: rect.y - amount, width: rect.width + 2 * amount, height: rect.height + 2 * amount)
    }
    static func inset(_ rect: ExplanationRect, by amount: Double) -> ExplanationRect {
        ExplanationRect(x: rect.x + amount, y: rect.y + amount, width: max(0, rect.width - 2 * amount),
                        height: max(0, rect.height - 2 * amount))
    }
    /// Gap between two rectangles, 0 when they touch or overlap.
    public static func distance(_ a: ExplanationRect, _ b: ExplanationRect) -> Double {
        let dx = max(0, max(a.x - (b.x + b.width), b.x - (a.x + a.width)))
        let dy = max(0, max(a.y - (b.y + b.height), b.y - (a.y + a.height)))
        return (dx * dx + dy * dy).squareRoot()
    }
}

/// A card belongs to exactly one pointing turn. A late callback from a cancelled or replaced turn
/// carries an old token and can neither show nor update it, and a card the owner closed stays
/// closed until the next turn begins.
public struct ExplanationCardLifecycle: Equatable, Sendable {
    public private(set) var token: UUID?
    public private(set) var dismissed = false
    public init() {}

    public mutating func begin(token: UUID) { self.token = token; dismissed = false }
    public mutating func end() { token = nil; dismissed = false }
    public mutating func dismissByOwner() { dismissed = true }
    public func admits(_ candidate: UUID) -> Bool { token == candidate && !dismissed }
}
