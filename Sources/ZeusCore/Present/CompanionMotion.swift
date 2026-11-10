import CoreGraphics
import Foundation

/// Decorative companion motion. It never posts a mouse, key, or scroll event.
public enum CompanionActuation {
    public static let movesSystemPointer = false
}

/// Damped follow. Response 0.2 s, damping 0.6, with the velocity kept between frames.
/// The rest spot is 35 pt to the right and 25 pt down from the pointer (logical units, y down).
public struct CompanionSpring: Equatable, Sendable {
    public static let response: Double = 0.2
    public static let damping: Double = 0.6
    public static let logicalOffset = CGPoint(x: 35, y: 25)

    public var position: CGPoint
    public var velocity: CGPoint

    public init(position: CGPoint = .zero, velocity: CGPoint = .zero) {
        self.position = position
        self.velocity = velocity
    }

    /// `pointer` is AppKit global (y up). Down is a smaller y.
    public static func rest(near pointer: CGPoint) -> CGPoint {
        CGPoint(x: pointer.x + logicalOffset.x, y: pointer.y - logicalOffset.y)
    }

    /// Section I: "Never" leaves the companion where it is. Always and on-call still track.
    public static func tracksPointer(_ show: BuddyShow) -> Bool { show != .never }

    public func stepped(toward target: CGPoint, dt: Double, reducedMotion: Bool = false) -> CompanionSpring {
        guard !reducedMotion else { return CompanionSpring(position: target, velocity: .zero) }
        guard dt.isFinite, dt > 0 else { return self }
        let x = Self.axis(position.x, velocity.x, target.x, dt)
        let y = Self.axis(position.y, velocity.y, target.y, dt)
        return CompanionSpring(position: CGPoint(x: x.pos, y: y.pos), velocity: CGPoint(x: x.vel, y: y.vel))
    }

    /// Underdamped oscillator, displacement measured from `target`.
    private static func axis(_ pos: Double, _ vel: Double, _ target: Double, _ dt: Double) -> (pos: Double, vel: Double) {
        let omega = 2 * Double.pi / response
        let zeta = damping
        let x0 = pos - target
        let beta = zeta * omega
        let omegaD = omega * sqrt(max(0, 1 - zeta * zeta))
        let decay = exp(-beta * dt)
        let sine = sin(omegaD * dt)
        let cosine = cos(omegaD * dt)
        let swing = (vel + beta * x0) / omegaD
        let offset = decay * (x0 * cosine + swing * sine)
        let speed = -beta * offset + decay * omegaD * (-x0 * sine + swing * cosine)
        guard offset.isFinite, speed.isFinite else { return (target, 0) }
        return (target + offset, speed)
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

    public static let scaleRest: Double = 1
    public static let scalePeak: Double = 1.3
    public static let glowRest: Double = 8
    public static let glowPeak: Double = 14

    public static func duration(distance: Double, reducedMotion: Bool) -> Double {
        guard !reducedMotion else { return 0 }
        let clamped = min(max(distance / 800, 0.6), 1.4)
        return (clamped * 1000).rounded() / 1000
    }

    public static func plan(from: CGPoint, to: CGPoint, departureTangent: CGPoint? = nil, reducedMotion: Bool = false) -> CompanionFlight {
        let distance = hypot(to.x - from.x, to.y - from.y)
        let lift = min(0.2 * distance, 80)
        let control: CGPoint
        if let tangent = unit(departureTangent), lift > 0 {
            control = CGPoint(x: from.x + tangent.x * lift, y: from.y + tangent.y * lift)
        } else {
            control = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2 + lift)
        }
        return CompanionFlight(
            from: from,
            control: control,
            to: to,
            duration: duration(distance: distance, reducedMotion: reducedMotion),
            reducedMotion: reducedMotion
        )
    }

    public func sample(at time: Double) -> CompanionFlightSample {
        let linear: Double
        if duration <= 0 { linear = 1 }
        else { linear = min(max(time / duration, 0), 1) }
        let eased = linear * linear * (3 - 2 * linear)
        let position = bezier(eased)
        let tangent = bezierTangent(eased)
        let rotation = hypot(tangent.x, tangent.y) > 0.0001 ? atan2(tangent.x, tangent.y) * 180 / .pi : 0
        let pulse = reducedMotion ? 0 : sin(.pi * linear)
        return CompanionFlightSample(
            position: position,
            rotation: rotation,
            scale: Self.scaleRest + (Self.scalePeak - Self.scaleRest) * pulse,
            glow: Self.glowRest + (Self.glowPeak - Self.glowRest) * pulse,
            progress: linear
        )
    }

    /// A new flight from where this one is now. The current tangent is the departure, so the turn does not snap.
    public func retarget(to newTarget: CGPoint, at time: Double) -> CompanionFlight {
        let here = sample(at: time).position
        return Self.plan(from: here, to: newTarget, departureTangent: tangent(at: time), reducedMotion: reducedMotion)
    }

    /// Fly home along the landing tangent, so the rotation at the target does not pop.
    public func returning(home: CGPoint) -> CompanionFlight {
        Self.plan(from: to, to: home, departureTangent: tangent(at: duration), reducedMotion: reducedMotion)
    }

    /// Shift the whole curve after a display moves. Unchanged duration.
    public func shifted(by delta: CGPoint) -> CompanionFlight {
        CompanionFlight(
            from: CGPoint(x: from.x + delta.x, y: from.y + delta.y),
            control: CGPoint(x: control.x + delta.x, y: control.y + delta.y),
            to: CGPoint(x: to.x + delta.x, y: to.y + delta.y),
            duration: duration,
            reducedMotion: reducedMotion
        )
    }

    public func tangent(at time: Double) -> CGPoint {
        let linear: Double
        if duration <= 0 { linear = 1 }
        else { linear = min(max(time / duration, 0), 1) }
        let eased = linear * linear * (3 - 2 * linear)
        return bezierTangent(eased)
    }

    private func bezier(_ t: Double) -> CGPoint {
        let u = 1 - t
        return CGPoint(
            x: u * u * from.x + 2 * u * t * control.x + t * t * to.x,
            y: u * u * from.y + 2 * u * t * control.y + t * t * to.y
        )
    }

    private func bezierTangent(_ t: Double) -> CGPoint {
        CGPoint(
            x: 2 * (1 - t) * (control.x - from.x) + 2 * t * (to.x - control.x),
            y: 2 * (1 - t) * (control.y - from.y) + 2 * t * (to.y - control.y)
        )
    }

    private static func unit(_ vector: CGPoint?) -> CGPoint? {
        guard let vector else { return nil }
        let length = hypot(vector.x, vector.y)
        guard length > 0.001, length.isFinite else { return nil }
        return CGPoint(x: vector.x / length, y: vector.y / length)
    }
}

/// Where a display went between two layouts. Nil when it was unplugged or is new.
public enum DisplayRebase {
    public static func shift(of id: Int, from old: [DisplayMap], to new: [DisplayMap]) -> CGPoint? {
        guard let before = old.first(where: { $0.id == id }), let after = new.first(where: { $0.id == id }) else { return nil }
        return CGPoint(x: after.frame.minX - before.frame.minX, y: after.frame.minY - before.frame.minY)
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
/// point wins. Otherwise the nearest center inside the ring budget.
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
        if let tightest = containing.min(by: { $0.width * $0.height < $1.width * $1.height }) {
            return tightest
        }
        guard let budget = mapper.ringPointTolerance(displayID: displayID) else { return nil }
        let ranked = usable.compactMap { frame -> (CGRect, Double)? in
            let center = CGPoint(x: frame.midX, y: frame.midY)
            guard let screen = mapper.convert(center, from: .ax, to: .screen, context: MapContext()) else { return nil }
            return (frame, hypot(screen.x - screenPoint.x, screen.y - screenPoint.y))
        }
        guard let nearest = ranked.min(by: { $0.1 < $1.1 }), nearest.1 <= budget else { return nil }
        return nearest.0
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
