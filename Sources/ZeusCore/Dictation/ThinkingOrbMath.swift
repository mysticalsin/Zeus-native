import Foundation

/// Dotted-sphere geometry for the Murmure pill's "thinking orb" (P0 item F, QA7 -- Tony: "maybe an
/// orb animation instead of the red dot"). Loosely ported from thinking-orbs 0.3.2's `listening`
/// state (a waveform rolling through the sphere's latitude rings) and `working` state (particles
/// on tilted orbits) -- MIT, Jakub Antalik, https://libraries.dev/orbs; the notice is kept in
/// `Resources/NOTICES.txt`. Pure math over `(mode, time)`, no rendering surface, mirroring the
/// reference engine's own `ModeFrame` contract, so this is unit-testable without a `Canvas` and
/// the drawing code (`Sources/Zeus/Voice/ThinkingOrb.swift`) just paints whatever comes out.
public enum ThinkingOrbMath {
    public struct Dot: Equatable {
        /// Projected position, both in roughly -1...1 (not yet scaled to a view size).
        public let x: Double
        public let y: Double
        /// 0 (far side of the sphere) ... 1 (near side). Scales radius and opacity.
        public let depth: Double
        /// Dot radius, already depth-scaled, in the same unit frame as x/y.
        public let radius: Double
        /// 0...1.
        public let opacity: Double
    }

    public enum Mode: Equatable {
        /// Listening: `level` is the live mic level, 0 (silence) ... 1 (loud). Drives how far
        /// past its idle baseline ripple the wave reaches.
        case listening(level: Double)
        /// Transcribing: a busier, faster pattern of its own -- no mic level to follow.
        case working
    }

    private static let tilt = 0.45 // radians: a fixed camera tilt so the poles aren't dead-on
    private static let goldenAngle = Double.pi * (3 - 2.2360679774997896) // pi * (3 - sqrt(5))

    /// A direction on the unit sphere from the Fibonacci lattice: `n` of these sit as close to
    /// evenly spaced as a single deterministic formula gets, for any `n`.
    static func fibonacciDirection(_ i: Int, _ n: Int) -> (x: Double, y: Double, z: Double) {
        guard n > 1 else { return (0, 0, 1) }
        let z = 1 - (2 * Double(i) + 1) / Double(n)
        let radiusAtZ = max(0, 1 - z * z).squareRoot()
        let theta = goldenAngle * Double(i)
        return (cos(theta) * radiusAtZ, sin(theta) * radiusAtZ, z)
    }

    /// Every dot for one instant.
    public static func dots(mode: Mode, time: Double, listeningCount: Int = 46, workingCount: Int = 18) -> [Dot] {
        switch mode {
        case .listening(let level): return listeningDots(time: time, level: level, count: listeningCount)
        case .working: return workingDots(time: time, count: workingCount)
        }
    }

    private static func listeningDots(time: Double, level: Double, count: Int) -> [Dot] {
        let level = min(1, max(0, level))
        let yaw = time * 0.35 // slow idle spin
        let waveSpeed = 2.2
        let ringFrequency = 5.0
        // A gentle ripple even in near-silence, so the orb never looks dead while still listening.
        let baseline = 0.18
        let amplitude = baseline + level * 0.75
        return (0..<count).map { i in
            let dir = fibonacciDirection(i, count)
            let rotated = rotate(dir, yaw: yaw, tilt: tilt)
            // The wave rides the sphere's own latitude (the pre-rotation z), so it reads as rings
            // rolling over the surface, not smearing sideways as the sphere turns.
            let wave = sin(dir.z * ringFrequency - time * waveSpeed)
            let depth = (rotated.z + 1) / 2
            let radius = (0.05 + depth * 0.05) * (1 + amplitude * wave * 0.5)
            let opacity = (0.25 + depth * 0.55) * (0.7 + 0.3 * amplitude * (wave * 0.5 + 0.5))
            return Dot(x: rotated.x, y: rotated.y, depth: depth, radius: max(0.01, radius), opacity: min(1, max(0, opacity)))
        }
    }

    private static func workingDots(time: Double, count: Int) -> [Dot] {
        let orbitCount = 3
        let perOrbit = max(1, count / orbitCount)
        var dots: [Dot] = []
        for orbit in 0..<orbitCount {
            let orbitTilt = tilt + Double(orbit) * (Double.pi / 3)
            let speed = 0.9 + Double(orbit) * 0.35
            for j in 0..<perOrbit {
                let angle = (Double(j) / Double(perOrbit)) * 2 * .pi + time * speed
                let dir = (x: cos(angle), y: 0.0, z: sin(angle))
                let rotated = rotate(dir, yaw: 0, tilt: orbitTilt)
                let depth = (rotated.z + 1) / 2
                dots.append(Dot(x: rotated.x, y: rotated.y, depth: depth, radius: 0.045 + depth * 0.045, opacity: 0.3 + depth * 0.6))
            }
        }
        return dots
    }

    /// Yaw around the vertical axis, then a fixed tilt around the horizontal axis; orthographic
    /// (z is kept only for depth, never foreshortened into x/y).
    private static func rotate(_ p: (x: Double, y: Double, z: Double), yaw: Double, tilt: Double) -> (x: Double, y: Double, z: Double) {
        let cosY = cos(yaw), sinY = sin(yaw)
        let x1 = p.x * cosY + p.z * sinY
        let z1 = -p.x * sinY + p.z * cosY
        let cosT = cos(tilt), sinT = sin(tilt)
        let y2 = p.y * cosT - z1 * sinT
        let z2 = p.y * sinT + z1 * cosT
        return (x1, y2, z2)
    }
}
