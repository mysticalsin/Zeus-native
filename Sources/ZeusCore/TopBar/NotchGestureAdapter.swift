import Foundation

/// The samples a notch pointer gesture is made of.
///
/// `TopBarGestureRouter` on the weather branch accepts `TopBarPointerSample`. That type can adopt
/// this protocol later (`down`, `up`, `hold`, `settle`, and `swipeRight` already exist there). This
/// module does not import the router. A right swipe here carries its distance; the router's
/// `swipeRight` does not, and an adoption can drop the distance.
public protocol NotchGestureSample: Equatable, Sendable {
    static func down(clickCount: Int) -> Self
    static func up(clickCount: Int) -> Self
    static func hold(elapsed: TimeInterval) -> Self
    static func settle(elapsed: TimeInterval) -> Self
    static func swipeRight(distance: Double) -> Self
}

/// The five samples above, as one value the notch can store before a router adopts the protocol.
public struct NotchPointerSample: NotchGestureSample, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case down(clickCount: Int)
        case up(clickCount: Int)
        case hold(elapsed: TimeInterval)
        case settle(elapsed: TimeInterval)
        case swipeRight(distance: Double)
    }

    public var kind: Kind

    public init(_ kind: Kind) { self.kind = kind }

    public static func down(clickCount: Int) -> Self { Self(.down(clickCount: clickCount)) }
    public static func up(clickCount: Int) -> Self { Self(.up(clickCount: clickCount)) }
    public static func hold(elapsed: TimeInterval) -> Self { Self(.hold(elapsed: elapsed)) }
    public static func settle(elapsed: TimeInterval) -> Self { Self(.settle(elapsed: elapsed)) }
    public static func swipeRight(distance: Double) -> Self { Self(.swipeRight(distance: distance)) }
}

/// Turns notch pointer events into samples. The phase is the whole gesture.
///
/// Idle, pressed, or settling. A press remembers where it began, how far it has moved, whether the
/// hold already fired, and whether a right swipe already fired. Timings are the caller's dates:
/// hold at half a second inside 6 pt, settle 0.35 s after a click that stayed inside that slop,
/// right swipe at 36 pt with the horizontal move at least 1.5 times the vertical. Those match the
/// router's hold, slop, multi-click window and trackpad threshold so a sample emitted here is one
/// that router already understands. Nothing here opens the notch or starts a file drag.
public struct NotchGestureAdapter<Sample: NotchGestureSample>: Equatable, Sendable {
    public static var holdAfter: TimeInterval { 0.5 }
    public static var settleAfter: TimeInterval { 0.35 }
    public static var clickSlop: Double { 6 }
    public static var swipeDistance: Double { 36 }
    public static var swipeAxisRatio: Double { 1.5 }

    public struct Press: Equatable, Sendable {
        public var originX: Double
        public var originY: Double
        public var clickCount: Int
        public var began: Date
        public var distance: Double
        public var held: Bool
        public var swiped: Bool
    }

    public enum Phase: Equatable, Sendable {
        case idle
        case pressed(Press)
        case settling(clickCount: Int, upAt: Date)
    }

    public enum Event: Equatable, Sendable {
        case down(at: Date, x: Double, y: Double, clickCount: Int)
        case move(at: Date, x: Double, y: Double)
        case up(at: Date, x: Double, y: Double, clickCount: Int)
        case tick(at: Date)
        case cancel
    }

    public enum Effect: Equatable, Sendable {
        case emit(Sample)
        /// Wake the caller with `.tick` at this date. A later effect in the same list replaces it.
        case arm(at: Date)
        case disarm
    }

    public private(set) var phase: Phase = .idle

    public init() {}

    public mutating func reduce(_ event: Event) -> [Effect] {
        switch (phase, event) {
        case (.settling, .cancel):
            phase = .idle
            return [.emit(Sample.settle(elapsed: Self.settleAfter)), .disarm]

        case (_, .cancel):
            phase = .idle
            return [.disarm]

        case (.idle, .down(let at, let x, let y, let count)):
            return begin(at: at, x: x, y: y, clickCount: max(count, 1), disarmFirst: false)

        case (.settling(let previous, _), .down(let at, let x, let y, let count)):
            return begin(at: at, x: x, y: y, clickCount: max(count, previous + 1, 1), disarmFirst: true)

        case (.pressed, .down(let at, let x, let y, let count)):
            return begin(at: at, x: x, y: y, clickCount: max(count, 1), disarmFirst: true)

        case (.pressed(var press), .move(_, let x, let y)):
            let dx = x - press.originX
            let dy = y - press.originY
            press.distance = max(press.distance, Self.length(dx, dy))
            var effects: [Effect] = []
            if !press.swiped, dx >= Self.swipeDistance, dx >= abs(dy) * Self.swipeAxisRatio {
                press.swiped = true
                effects.append(.emit(Sample.swipeRight(distance: dx)))
            }
            phase = .pressed(press)
            return effects

        case (.pressed(var press), .up(let at, _, _, let count)):
            var effects: [Effect] = [.disarm]
            let elapsed = at.timeIntervalSince(press.began)
            if !press.held, press.distance <= Self.clickSlop, elapsed >= Self.holdAfter {
                press.held = true
                effects.append(.emit(Sample.hold(elapsed: elapsed)))
            }
            let clicks = max(count, press.clickCount, 1)
            effects.append(.emit(Sample.up(clickCount: clicks)))
            if press.held || press.swiped || press.distance > Self.clickSlop {
                phase = .idle
                return effects
            }
            phase = .settling(clickCount: clicks, upAt: at)
            effects.append(.arm(at: at.addingTimeInterval(Self.settleAfter)))
            return effects

        case (.pressed(var press), .tick(let at)):
            let elapsed = at.timeIntervalSince(press.began)
            guard !press.held, press.distance <= Self.clickSlop else { return [] }
            guard elapsed >= Self.holdAfter else {
                return [.arm(at: press.began.addingTimeInterval(Self.holdAfter))]
            }
            press.held = true
            phase = .pressed(press)
            return [.emit(Sample.hold(elapsed: elapsed)), .disarm]

        case (.settling(_, let upAt), .tick(let at)):
            let elapsed = at.timeIntervalSince(upAt)
            guard elapsed >= Self.settleAfter else {
                return [.arm(at: upAt.addingTimeInterval(Self.settleAfter))]
            }
            phase = .idle
            return [.emit(Sample.settle(elapsed: elapsed)), .disarm]

        case (.idle, .move), (.idle, .up), (.idle, .tick),
             (.settling, .move), (.settling, .up):
            return []
        }
    }

    private mutating func begin(at: Date, x: Double, y: Double, clickCount: Int, disarmFirst: Bool) -> [Effect] {
        let count = max(clickCount, 1)
        phase = .pressed(Press(originX: x, originY: y, clickCount: count, began: at, distance: 0, held: false, swiped: false))
        var effects: [Effect] = []
        if disarmFirst { effects.append(.disarm) }
        effects.append(.emit(Sample.down(clickCount: count)))
        effects.append(.arm(at: at.addingTimeInterval(Self.holdAfter)))
        return effects
    }

    private static func length(_ dx: Double, _ dy: Double) -> Double {
        (dx * dx + dy * dy).squareRoot()
    }
}
