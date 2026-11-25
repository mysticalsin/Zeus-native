import Foundation

/// A rectangle in points. The origin is the bottom left, which is the corner a display frame already uses.
public struct LockRect: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var maxX: Double { x + width }
    public var maxY: Double { y + height }

    public func intersects(_ other: LockRect) -> Bool {
        width > 0 && height > 0 && other.width > 0 && other.height > 0
            && x < other.maxX && maxX > other.x
            && y < other.maxY && maxY > other.y
    }
}

/// One display. `frame` is in points. `scale` is recorded and does not change the point frame.
public struct LockDisplay: Equatable, Sendable {
    public var id: String
    public var frame: LockRect
    public var scale: Double

    public init(id: String, frame: LockRect, scale: Double) {
        self.id = id
        self.frame = frame
        self.scale = scale
    }
}

/// The rows the layout needs from a lock scene: a clock, a quiet card, or a full card with an optional lyric.
/// An empty value draws nothing, even if a row flag is still set.
public struct LockLayoutScene: Equatable, Sendable {
    public enum Card: Equatable, Sendable {
        case quiet
        case full(lyric: Bool)
    }

    public var isEmpty: Bool
    public var showsClock: Bool
    public var card: Card?

    public init(isEmpty: Bool, showsClock: Bool, card: Card?) {
        self.isEmpty = isEmpty
        self.showsClock = showsClock
        self.card = card
    }

    public static let empty = LockLayoutScene(isEmpty: true, showsClock: false, card: nil)

    public var draws: Bool {
        guard !isEmpty else { return false }
        return showsClock || card != nil
    }
}

/// Where the lock window sits. The frame is the card itself: nothing transparent is added around it.
public enum LockLayout {
    public static let width: Double = 360
    /// Fraction of the screen height kept for the system clock. Step zero question 7 replaces this one number.
    public static let clockBand: Double = 0.125
    /// Fraction of the screen height kept for the sign-in controls. Step zero question 7 replaces this one number.
    public static let signInBand: Double = 0.25
    public static let pad: Double = 16
    public static let clockRow: Double = 28
    public static let quietRow: Double = 44
    public static let fullBody: Double = 96
    public static let lyricRow: Double = 20

    public static func contentHeight(_ scene: LockLayoutScene) -> Double {
        guard scene.draws else { return 0 }
        var height = pad * 2
        if scene.showsClock { height += clockRow }
        switch scene.card {
        case nil:
            break
        case .quiet:
            height += quietRow
        case .full(let lyric):
            height += fullBody
            if lyric { height += lyricRow }
        }
        return height
    }

    /// Centred horizontally, inside the band between the clock and the sign-in controls, clear of `systemBands`.
    /// Nil when the card cannot sit in that band. `systemBands` stays empty until step zero question 11 measures them.
    public static func frame(display: LockDisplay, scene: LockLayoutScene, systemBands: [LockRect] = []) -> LockRect? {
        let cardHeight = contentHeight(scene)
        guard cardHeight > 0 else { return nil }
        let screen = display.frame
        guard screen.width >= width, screen.height > 0 else { return nil }
        let clock = screen.height * clockBand
        let signIn = screen.height * signInBand
        let lower = screen.y + signIn
        let upper = screen.y + screen.height - clock
        guard upper - lower >= cardHeight else { return nil }
        let cardX = screen.x + (screen.width - width) / 2
        let gaps = freeSpans(lower: lower, upper: upper, cuts: verticalCuts(systemBands, cardX: cardX, lower: lower, upper: upper))
        guard let gap = bestGap(gaps, cardHeight: cardHeight, center: (lower + upper) / 2) else { return nil }
        let y = gap.lower + (gap.length - cardHeight) / 2
        return LockRect(x: cardX, y: y, width: width, height: cardHeight)
    }

    private struct Span {
        var lower: Double
        var upper: Double
        var length: Double { upper - lower }
        var center: Double { (lower + upper) / 2 }
    }

    private static func verticalCuts(_ bands: [LockRect], cardX: Double, lower: Double, upper: Double) -> [Span] {
        let cardSpan = LockRect(x: cardX, y: 0, width: width, height: 1)
        var cuts: [Span] = []
        for band in bands {
            let bandSpan = LockRect(x: band.x, y: 0, width: band.width, height: 1)
            guard cardSpan.intersects(bandSpan) else { continue }
            let start = max(band.y, lower)
            let end = min(band.maxY, upper)
            if end > start { cuts.append(Span(lower: start, upper: end)) }
        }
        return cuts
    }

    private static func freeSpans(lower: Double, upper: Double, cuts: [Span]) -> [Span] {
        var cursor = lower
        var free: [Span] = []
        for cut in cuts.sorted(by: { $0.lower < $1.lower }) {
            let start = max(cut.lower, lower)
            let end = min(cut.upper, upper)
            guard end > start else { continue }
            if start > cursor { free.append(Span(lower: cursor, upper: start)) }
            cursor = max(cursor, end)
        }
        if cursor < upper { free.append(Span(lower: cursor, upper: upper)) }
        return free
    }

    private static func bestGap(_ gaps: [Span], cardHeight: Double, center: Double) -> Span? {
        let fits = gaps.filter { $0.length >= cardHeight }
        return fits.max { lhs, rhs in
            if abs(lhs.length - rhs.length) > 0.5 { return lhs.length < rhs.length }
            let leftDistance = abs(lhs.center - center)
            let rightDistance = abs(rhs.center - center)
            if abs(leftDistance - rightDistance) > 0.5 { return leftDistance > rightDistance }
            return lhs.lower > rhs.lower
        }
    }
}
