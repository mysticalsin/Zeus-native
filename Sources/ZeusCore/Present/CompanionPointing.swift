import Foundation

/// Geometry that must move together when the pointed-at display changes layout. Keeping the
/// eventual pointing target beside the flight prevents a correct landing followed by a stale jump.
public struct CompanionPointingGeometry: Equatable, Sendable {
    public var flight: CompanionFlight?
    public var target: CGPoint?
    public var position: CGPoint
    public var ringFrame: CGRect?
    public var strikeCenter: CGPoint

    public init(flight: CompanionFlight?, target: CGPoint?, position: CGPoint,
                ringFrame: CGRect?, strikeCenter: CGPoint) {
        self.flight = flight
        self.target = target
        self.position = position
        self.ringFrame = ringFrame
        self.strikeCenter = strikeCenter
    }

    /// Nil means the target's display is gone or cannot be identified: abandon pointing instead
    /// of drawing its label/ring on an unrelated replacement display.
    public func rebased(from old: [DisplayMap], to new: [DisplayMap]) -> Self? {
        guard let anchor = target ?? flight?.to,
              let display = old.first(where: { $0.frame.contains(anchor) }),
              let delta = DisplayRebase.shift(of: display.id, from: old, to: new) else { return nil }
        func shifted(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x + delta.x, y: point.y + delta.y)
        }
        return Self(flight: flight?.shifted(by: delta), target: target.map(shifted),
                    position: shifted(position),
                    ringFrame: ringFrame?.offsetBy(dx: delta.x, dy: delta.y),
                    strikeCenter: shifted(strikeCenter))
    }
}

/// The real pointing label's reveal state. Reduce Motion reveals all text on arrival or on the
/// next update if the setting changes mid-label; the reading hold is owned by the controller.
public struct CompanionPointingLabel: Equatable, Sendable {
    public let text: String
    public private(set) var visibleCount: Int
    public private(set) var nextCharacterAt: TimeInterval

    public init(text: String, beganAt: TimeInterval, reduceMotion: Bool) {
        self.text = text
        visibleCount = reduceMotion ? text.count : 0
        nextCharacterAt = beganAt + 0.12
    }

    public var visibleText: String { String(text.prefix(visibleCount)) }
    public var isComplete: Bool { visibleCount >= text.count }

    public mutating func advance(at now: TimeInterval, reduceMotion: Bool, characterDelay: TimeInterval) {
        guard !isComplete else { return }
        if reduceMotion {
            visibleCount = text.count
        } else if now >= nextCharacterAt {
            visibleCount += 1
            nextCharacterAt = now + characterDelay
        }
    }
}
