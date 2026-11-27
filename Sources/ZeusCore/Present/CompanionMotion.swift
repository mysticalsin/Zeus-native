import CoreGraphics
import Foundation

/// Decorative companion motion. It never posts a mouse, key, or scroll event.
public enum CompanionActuation {
    public static let movesSystemPointer = CompanionMotionBox.movesSystemPointer
}

/// Damped follow. Response 0.2 s, damping 0.6, with the velocity kept between frames.
/// The rest spot is 35 pt to the right and 25 pt down from the pointer (logical units, y down).
public struct CompanionSpring: Equatable, Sendable {
    public static let response: Double = CompanionMotionBox.Spring.response
    public static let damping: Double = CompanionMotionBox.Spring.damping
    public static let logicalOffset = CGPoint(x: CompanionMotionBox.Spring.offsetX, y: CompanionMotionBox.Spring.offsetY)

    public var position: CGPoint
    public var velocity: CGPoint

    public init(position: CGPoint = .zero, velocity: CGPoint = .zero) {
        self.position = position
        self.velocity = velocity
    }

    /// `pointer` is AppKit global (y up). Down is a smaller y.
    public static func rest(near pointer: CGPoint) -> CGPoint {
        CompanionMotionBox.Spring.rest(near: pointer.motionPoint).cgPoint
    }

    /// Section I: "Never" leaves the companion where it is. Always and on-call still track.
    public static func tracksPointer(_ show: BuddyShow) -> Bool {
        CompanionMotionBox.Spring.tracksPointer(showIsNever: show == .never)
    }

    public func stepped(toward target: CGPoint, dt: Double, reducedMotion: Bool = false) -> CompanionSpring {
        motionSpring.stepped(toward: target.motionPoint, dt: dt, reducedMotion: reducedMotion).companionSpring
    }
}

/// One frame of a flight. `rotation` is degrees, clockwise from up, in screen space (y up).
public struct CompanionFlightSample: Equatable, Sendable {
    public var position: CGPoint
    public var rotation: Double
    public var scale: Double
    public var glow: Double
    public var progress: Double
}

/// Quadratic Bezier flight. Position uses smoothstep. Scale and glow pulse on their own.
/// A 600 pt hop lasts 750 ms. Lift is `min(0.2 * distance, 80)` in screen points (up is +y).
public struct CompanionFlight: Equatable, Sendable {
    public var from: CGPoint
    public var control: CGPoint
    public var to: CGPoint
    public var duration: Double
    public var reducedMotion: Bool

    public init(from: CGPoint, control: CGPoint, to: CGPoint, duration: Double, reducedMotion: Bool) {
        self.from = from
        self.control = control
        self.to = to
        self.duration = duration
        self.reducedMotion = reducedMotion
    }

    public static let scaleRest: Double = CompanionMotionBox.Flight.scaleRest
    public static let scalePeak: Double = CompanionMotionBox.Flight.scalePeak
    public static let glowRest: Double = CompanionMotionBox.Flight.glowRest
    public static let glowPeak: Double = CompanionMotionBox.Flight.glowPeak

    public static func duration(distance: Double, reducedMotion: Bool) -> Double {
        CompanionMotionBox.Flight.duration(distance: distance, reducedMotion: reducedMotion)
    }

    public static func plan(from: CGPoint, to: CGPoint, departureTangent: CGPoint? = nil, reducedMotion: Bool = false) -> CompanionFlight {
        CompanionMotionBox.Flight.plan(from: from.motionPoint, to: to.motionPoint,
                                        departureTangent: departureTangent?.motionPoint,
                                        reducedMotion: reducedMotion).companionFlight
    }

    public func sample(at time: Double) -> CompanionFlightSample {
        let sample = motionFlight.sample(at: time)
        return CompanionFlightSample(position: sample.position.cgPoint, rotation: sample.rotation,
                                     scale: sample.scale, glow: sample.glow, progress: sample.progress)
    }

    /// A new flight from where this one is now. The current tangent is the departure, so the turn does not snap.
    public func retarget(to newTarget: CGPoint, at time: Double) -> CompanionFlight {
        motionFlight.retarget(to: newTarget.motionPoint, at: time).companionFlight
    }

    /// Fly home along the landing tangent, so the rotation at the target does not pop.
    public func returning(home: CGPoint) -> CompanionFlight {
        motionFlight.returning(home: home.motionPoint).companionFlight
    }

    /// Shift the whole curve after a display moves. Unchanged duration.
    public func shifted(by delta: CGPoint) -> CompanionFlight {
        motionFlight.shifted(by: delta.motionPoint).companionFlight
    }

    public func tangent(at time: Double) -> CGPoint {
        motionFlight.tangent(at: time).cgPoint
    }
}

/// Where a display went between two layouts. Nil when it was unplugged or is new.
public enum DisplayRebase {
    public static func shift(of id: Int, from old: [DisplayMap], to new: [DisplayMap]) -> CGPoint? {
        guard let before = old.first(where: { $0.id == id }), let after = new.first(where: { $0.id == id }) else { return nil }
        return CompanionMotionBox.displayShift(oldMinX: Double(before.frame.minX), oldMinY: Double(before.frame.minY),
                                                newMinX: Double(after.frame.minX), newMinY: Double(after.frame.minY)).cgPoint
    }
}

/// A ring on an accessibility element's frame, in overlay points.
public struct TargetRing: Equatable, Sendable {
    public var displayID: Int
    public var center: CGPoint
    public var frame: CGRect
    public var label: String?

    public init(displayID: Int, center: CGPoint, frame: CGRect, label: String? = nil) {
        self.displayID = displayID
        self.center = center
        self.frame = frame
        self.label = label
    }

    /// The ring sits on the element. A pixel guess is not used once a frame is known.
    public static func snap(axFrame: CGRect, displayID: Int, mapper: some CoordinateMapping, label: String? = nil) -> TargetRing? {
        guard let frame = mapper.overlayRect(axFrame, from: .ax, displayID: displayID) else { return nil }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return TargetRing(displayID: displayID, center: center, frame: frame, label: label)
    }
}

/// Shown until the next click or key.
public struct RingSession: Equatable, Sendable {
    public private(set) var ring: TargetRing?

    public init(ring: TargetRing? = nil) { self.ring = ring }

    public mutating func show(_ ring: TargetRing) { self.ring = ring }

    @discardableResult
    public mutating func clearOnUserInput() -> Bool {
        let had = ring != nil
        ring = nil
        return had
    }
}

/// Picks the accessibility frame a point belongs to. The smallest frame that contains the
/// point wins. A point that sits between controls is left alone.
public enum ElementSnap {
    public static func best(
        axFrames: [CGRect],
        around screenPoint: CGPoint,
        displayID: Int,
        mapper: some CoordinateMapping
    ) -> CGRect? {
        guard let axPoint = mapper.convert(screenPoint, from: .screen, to: .ax, context: MapContext()) else { return nil }
        let usable = axFrames.filter { $0.width > 0 && $0.height > 0 && $0.origin.x.isFinite && $0.origin.y.isFinite }
        let containing = usable.filter { $0.contains(axPoint) }
        return containing.min(by: { $0.width * $0.height < $1.width * $1.height })
    }
}

/// Headless reading of the flight and ring contract. `zeus debug present` prints this.
public enum PresentProbe {
    public static func report() -> String {
        let flight = CompanionFlight.plan(from: .zero, to: CGPoint(x: 600, y: 0))
        let mid = flight.sample(at: flight.duration / 2)
        let hd = ScreenCoordinateMapper(displays: [
            DisplayMap(id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), scale: 1),
        ])
        let fourK = ScreenCoordinateMapper(displays: [
            DisplayMap(id: 4, frame: CGRect(x: 0, y: 0, width: 3840, height: 2160), scale: 1),
        ])
        let lines = [
            "pointer=decorative",
            "movesSystemPointer=\(CompanionActuation.movesSystemPointer)",
            "flight600.duration=\(String(format: "%.3f", flight.duration))",
            "flight600.mid=\(fmt(mid.position))",
            "flight600.midScale=\(String(format: "%.2f", mid.scale))",
            "flight600.midGlow=\(String(format: "%.1f", mid.glow))",
            "ring1080.px=\(hd.ringPixelTolerance(displayID: 1).map { String(format: "%.0f", $0) } ?? "none")",
            "ring4k.px=\(fourK.ringPixelTolerance(displayID: 4).map { String(format: "%.0f", $0) } ?? "none")",
            "spring.response=\(CompanionSpring.response)",
            "spring.damping=\(CompanionSpring.damping)",
        ]
        return lines.joined(separator: "\n")
    }

    private static func fmt(_ point: CGPoint) -> String {
        String(format: "%.1f,%.1f", point.x, point.y)
    }
}

/// Fly the companion to an element and ring that element's frame.
public struct ShowMeWhere: Equatable, Sendable {
    public var flight: CompanionFlight
    public var ring: TargetRing
    /// AppKit global point the companion flies to. The center of the element, not the pixel guess.
    public var screenTarget: CGPoint

    public static func plan(
        from companion: CGPoint,
        axFrame: CGRect,
        displayID: Int,
        mapper: some CoordinateMapping,
        label: String? = nil,
        reducedMotion: Bool = false
    ) -> ShowMeWhere? {
        guard let ring = TargetRing.snap(axFrame: axFrame, displayID: displayID, mapper: mapper, label: label) else { return nil }
        guard let screen = mapper.convert(ring.center, from: .overlay, to: .screen, context: MapContext(displayID: displayID)) else { return nil }
        return ShowMeWhere(
            flight: CompanionFlight.plan(from: companion, to: screen, reducedMotion: reducedMotion),
            ring: ring,
            screenTarget: screen
        )
    }
}

private extension CGPoint {
    var motionPoint: CompanionMotionBox.Point {
        CompanionMotionBox.Point(x: Double(x), y: Double(y))
    }
}

private extension CompanionMotionBox.Point {
    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

private extension CompanionSpring {
    var motionSpring: CompanionMotionBox.Spring {
        CompanionMotionBox.Spring(position: position.motionPoint, velocity: velocity.motionPoint)
    }
}

private extension CompanionMotionBox.Spring {
    var companionSpring: CompanionSpring {
        CompanionSpring(position: position.cgPoint, velocity: velocity.cgPoint)
    }
}

private extension CompanionFlight {
    var motionFlight: CompanionMotionBox.Flight {
        CompanionMotionBox.Flight(from: from.motionPoint, control: control.motionPoint, to: to.motionPoint,
                                   duration: duration, reducedMotion: reducedMotion)
    }
}

private extension CompanionMotionBox.Flight {
    var companionFlight: CompanionFlight {
        CompanionFlight(from: from.cgPoint, control: control.cgPoint, to: to.cgPoint,
                        duration: duration, reducedMotion: reducedMotion)
    }
}
