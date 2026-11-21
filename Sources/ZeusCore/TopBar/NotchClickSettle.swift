import Foundation

/// A point in the same space as the notch click zone. The settle machine does not read the pointer itself.
public struct NotchClickPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// Click-to-open waits until the pointer has stayed inside 6 pt for 0.35 s.
/// Mouse-down does not open. The caller passes the clock.
public struct NotchClickSettle: Equatable, Sendable {
    public static let delay: TimeInterval = 0.35
    public static let slop: Double = 6

    public enum Step: Equatable, Sendable {
        case ignore
        case wait(until: Date)
        case open
    }

    private var armedUntil: Date?
    private var origin: NotchClickPoint?

    public init() {}

    /// Starts the wait. The panel stays closed.
    public mutating func pointerDown(at date: Date, point: NotchClickPoint) -> Step {
        origin = point
        let until = date.addingTimeInterval(Self.delay)
        armedUntil = until
        return .wait(until: until)
    }

    /// Opens once `date` has reached the armed time and the pointer is still inside the slop.
    public mutating func tick(at date: Date, point: NotchClickPoint) -> Step {
        guard let origin, let armedUntil else { return .ignore }
        let dx = point.x - origin.x
        let dy = point.y - origin.y
        if (dx * dx + dy * dy) > Self.slop * Self.slop {
            self.armedUntil = nil
            self.origin = nil
            return .ignore
        }
        if date < armedUntil {
            return .wait(until: armedUntil)
        }
        self.armedUntil = nil
        self.origin = nil
        return .open
    }
}
