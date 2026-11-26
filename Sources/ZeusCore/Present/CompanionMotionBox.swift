import Foundation

/// Companion spring and flight as `Double` points. The caller supplies the pointer, the step,
/// and the display edges. This type does not read a pointer, a screen, or a clock.
public enum CompanionMotionBox {
    /// The companion never posts a mouse, key, or scroll event.
    public static let movesSystemPointer = false

    public struct Point: Equatable, Sendable {
        public var x: Double
        public var y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }

        public static let zero = Point(x: 0, y: 0)
    }

    /// Damped follow. Response 0.2 s, damping 0.6, with the velocity kept between frames.
    /// The rest spot is 35 pt to the right and 25 pt down from the pointer (y down).
    public struct Spring: Equatable, Sendable {
        public static let response = 0.2
        public static let damping = 0.6
        public static let offsetX = 35.0
        public static let offsetY = 25.0

        public var position: Point
        public var velocity: Point

        public init(position: Point = .zero, velocity: Point = .zero) {
            self.position = position
            self.velocity = velocity
        }

        /// `pointer` uses a y-up axis. Down is a smaller y.
        public static func rest(near pointer: Point) -> Point {
            Point(x: pointer.x + offsetX, y: pointer.y - offsetY)
        }

        /// "Never" leaves the companion where it is. Any other show policy still tracks.
        public static func tracksPointer(showIsNever: Bool) -> Bool { !showIsNever }

        public func stepped(toward target: Point, dt: Double, reducedMotion: Bool = false) -> Spring {
            guard !reducedMotion else { return Spring(position: target, velocity: .zero) }
            guard dt.isFinite, dt > 0 else { return self }
            let x = Self.axis(position.x, velocity.x, target.x, dt)
            let y = Self.axis(position.y, velocity.y, target.y, dt)
            return Spring(position: Point(x: x.pos, y: y.pos), velocity: Point(x: x.vel, y: y.vel))
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

    public struct FlightSample: Equatable, Sendable {
        public var position: Point
        public var rotation: Double
        public var scale: Double
        public var glow: Double
        public var progress: Double
    }

    /// Quadratic Bezier flight. Position uses smoothstep. Scale and glow pulse on their own.
    /// A 600 pt hop lasts 750 ms. Lift is `min(0.2 * distance, 80)` (up is +y).
    public struct Flight: Equatable, Sendable {
        public static let scaleRest = 1.0
        public static let scalePeak = 1.3
        public static let glowRest = 8.0
        public static let glowPeak = 14.0

        public var from: Point
        public var control: Point
        public var to: Point
        public var duration: Double
        public var reducedMotion: Bool

        public init(from: Point, control: Point, to: Point, duration: Double, reducedMotion: Bool) {
            self.from = from
            self.control = control
            self.to = to
            self.duration = duration
            self.reducedMotion = reducedMotion
        }

        public static func duration(distance: Double, reducedMotion: Bool) -> Double {
            guard !reducedMotion else { return 0 }
            let clamped = min(max(distance / 800, 0.6), 1.4)
            return (clamped * 1000).rounded() / 1000
        }

        public static func plan(from: Point, to: Point, departureTangent: Point? = nil,
                                 reducedMotion: Bool = false) -> Flight {
            let distance = hypot(to.x - from.x, to.y - from.y)
            let lift = min(0.2 * distance, 80)
            let control: Point
            if let tangent = unit(departureTangent), lift > 0 {
                control = Point(x: from.x + tangent.x * lift, y: from.y + tangent.y * lift)
            } else {
                control = Point(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2 + lift)
            }
            return Flight(from: from, control: control, to: to,
                          duration: duration(distance: distance, reducedMotion: reducedMotion),
                          reducedMotion: reducedMotion)
        }

        public func sample(at time: Double) -> FlightSample {
            let linear = Self.linear(time, duration: duration)
            let eased = linear * linear * (3 - 2 * linear)
            let position = bezier(eased)
            let tangent = bezierTangent(eased)
            let rotation = hypot(tangent.x, tangent.y) > 0.0001 ? atan2(tangent.x, tangent.y) * 180 / Double.pi : 0
            let pulse = reducedMotion ? 0 : sin(Double.pi * linear)
            return FlightSample(
                position: position,
                rotation: rotation,
                scale: Self.scaleRest + (Self.scalePeak - Self.scaleRest) * pulse,
                glow: Self.glowRest + (Self.glowPeak - Self.glowRest) * pulse,
                progress: linear
            )
        }

        /// A new flight from where this one is now. The current tangent is the departure, so the turn does not snap.
        public func retarget(to newTarget: Point, at time: Double) -> Flight {
            let here = sample(at: time).position
            return Self.plan(from: here, to: newTarget, departureTangent: tangent(at: time), reducedMotion: reducedMotion)
        }

        /// Fly home along the landing tangent, so the rotation at the target does not pop.
        public func returning(home: Point) -> Flight {
            Self.plan(from: to, to: home, departureTangent: tangent(at: duration), reducedMotion: reducedMotion)
        }

        /// Shift the whole curve after a display moves. Unchanged duration.
        public func shifted(by delta: Point) -> Flight {
            Flight(from: Point(x: from.x + delta.x, y: from.y + delta.y),
                   control: Point(x: control.x + delta.x, y: control.y + delta.y),
                   to: Point(x: to.x + delta.x, y: to.y + delta.y),
                   duration: duration,
                   reducedMotion: reducedMotion)
        }

        public func tangent(at time: Double) -> Point {
            let linear = Self.linear(time, duration: duration)
            let eased = linear * linear * (3 - 2 * linear)
            return bezierTangent(eased)
        }

        private static func linear(_ time: Double, duration: Double) -> Double {
            guard duration > 0 else { return 1 }
            return min(max(time / duration, 0), 1)
        }

        private func bezier(_ t: Double) -> Point {
            let u = 1 - t
            return Point(x: u * u * from.x + 2 * u * t * control.x + t * t * to.x,
                         y: u * u * from.y + 2 * u * t * control.y + t * t * to.y)
        }

        private func bezierTangent(_ t: Double) -> Point {
            Point(x: 2 * (1 - t) * (control.x - from.x) + 2 * t * (to.x - control.x),
                  y: 2 * (1 - t) * (control.y - from.y) + 2 * t * (to.y - control.y))
        }

        private static func unit(_ vector: Point?) -> Point? {
            guard let vector else { return nil }
            let length = hypot(vector.x, vector.y)
            guard length > 0.001, length.isFinite else { return nil }
            return Point(x: vector.x / length, y: vector.y / length)
        }
    }

    /// How far a display origin moved. The caller decides whether both layouts still contain that display.
    public static func displayShift(oldMinX: Double, oldMinY: Double, newMinX: Double, newMinY: Double) -> Point {
        Point(x: newMinX - oldMinX, y: newMinY - oldMinY)
    }
}
