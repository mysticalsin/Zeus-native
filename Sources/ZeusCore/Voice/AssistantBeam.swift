import Foundation

/// Deterministic native adaptation of voice-glow 0.2.1 (MIT, Jakub Antalik).
/// The seven lobes, bell contour and processing timings come from that reference.
/// This is a Canvas geometry model, not its CSS/SVG displacement shader or audio analyser.
/// Callers own their clock and supply a level; no microphone, singleton or timer lives here.
public enum AssistantBeam {
    public static let processingDuration = 1.1
    public static let processingCurve = 2.1
    public static let processingEase = 0.6

    public struct Point: Equatable, Sendable {
        public let x: Double
        public let y: Double
    }

    public struct Lobe: Equatable, Sendable {
        public let center: Point
        public let radiusX: Double
        public let radiusY: Double
        public let colorIndex: Int
    }

    public struct Geometry: Equatable, Sendable {
        public let width: Double
        public let height: Double
        public let scale: Double
        public let cornerRadius: Double
        public let lobes: [Lobe]
        public let band: [Point]
        public let bandWidth: Double
        public let fringeX: Double
        public let fringeY: Double
        public let bandOpacity: Double
        public let glowOpacity: Double
    }

    public struct Frame: Equatable, Sendable {
        public let level: Double
        public let gather: Double
        public let sweep: Double
        public let reducedMotion: Bool
        public let hueDegrees: Double
        fileprivate let phase: Double
        fileprivate let time: Double
        fileprivate let drive: Double
        fileprivate let widthScale: Double
        fileprivate let heightScale: Double

        /// Beam lengths shrink with the host's available height. The host itself is never scaled.
        /// A full 360×340 card uses reference lengths; a compact status bar retains its own layout.
        public func geometry(width: Double, height: Double, cornerRadius: Double = 24) -> Geometry {
            let width = AssistantBeam.dimension(width)
            let height = AssistantBeam.dimension(height)
            let scale = min(1, width / 360, height / 96)
            let radius = min(AssistantBeam.dimension(cornerRadius), width / 2, height / 2)
            guard scale > 0 else {
                return Geometry(width: width, height: height, scale: 0, cornerRadius: radius,
                                lobes: [], band: [], bandWidth: 0, fringeX: 0, fringeY: 0,
                                bandOpacity: 0, glowOpacity: 0)
            }
            let travel = Self.cycleWidth / 2 * 1.55
            let offset = gather * travel * sweep
            let center = width / 2 + offset * widthScale * scale
            let corner = gather * 0.45
            let coreInset = 30 * widthScale * scale
            let lobes = Self.referenceLobes.enumerated().map { index, reference in
                let local = AssistantBeam.wrap(reference.x * 0.85 + phase, period: Self.cycleWidth)
                let x = width / 2 + (offset + local * (1 - gather * 0.6)) * widthScale * scale
                let falloff = max(0, 1 - pow(local / (Self.cycleWidth / 2 + 4), 2))
                let bandLevel: Double
                if reducedMotion { bandLevel = level }
                else {
                    switch reference.band {
                    case 1: bandLevel = level * (0.72 + 0.28 * sin(time * 9.1))
                    case 2: bandLevel = level * (0.6 + 0.4 * sin(time * 13.7 + 2))
                    default: bandLevel = level
                    }
                }
                let heightGain = (0.6 + 0.7 * bandLevel) * falloff
                return Lobe(center: Point(x: x, y: height - AssistantBeam.cornerLift(x: x, width: width,
                                      radius: radius, inset: coreInset) * corner),
                            radiusX: reference.width * 0.65 * widthScale * scale,
                            radiusY: reference.height * 1.25 * heightScale * heightGain * scale,
                            colorIndex: index)
            }

            let halfSpan = 170 * 0.75 * widthScale * (1 - gather * 0.45) * scale
            let rise = min(height * 0.82, (64 * heightScale + 60 * drive) * 0.35 * scale)
            let tail = 0.59 * (1 - AssistantBeam.smoothstep(min(1, gather * 4)))
            let overflow = tail > 0.001 ? 15 * scale : 0
            let start = tail > 0.001 ? -overflow : center - halfSpan
            let end = tail > 0.001 ? width + overflow : center + halfSpan
            let points = (0...56).map { index -> Point in
                let x = start + (end - start) * Double(index) / 56
                let normalized = min(1, max(-1, (x - center) / max(1, halfSpan)))
                let bell = AssistantBeam.bell(normalized)
                let edgeDistance = (x < center ? center : width - center) + overflow
                let distance = abs(x - center)
                let tailStart = max(0, edgeDistance) * 0.67
                let tailProgress = min(1, max(0, (distance - tailStart) / max(1, edgeDistance - tailStart)))
                let tailRise = tail * pow(tailProgress, 2.4)
                let cornerRise = AssistantBeam.cornerLift(x: x, width: width, radius: radius) * gather
                return Point(x: x, y: height + 27 * scale - rise * (bell + tailRise) - cornerRise)
            }
            let aberration = 0.89 * (0.35 + 0.65 * level)
            return Geometry(width: width, height: height, scale: scale, cornerRadius: radius, lobes: lobes,
                            band: points, bandWidth: 2.15 * (1 + 0.35 * level) * scale,
                            fringeX: 4 * aberration * scale, fringeY: (4 + 12 * aberration) * scale,
                            bandOpacity: min(1, 0.6 * 1.55 * drive), glowOpacity: 0.15 + 0.85 * drive)
        }

        private static let cycleWidth = 36.0 * 7 * 0.85
        private static let referenceLobes: [(x: Double, width: Double, height: Double, band: Int)] = [
            (0, 74, 46, 0), (-36, 54, 40, 1), (36, 54, 40, 1),
            (-72, 48, 32, 2), (72, 48, 32, 2), (-108, 42, 26, 1), (108, 42, 26, 1),
        ]
    }

    /// `processingElapsed` is time since the *current* processing phase began, not wall-clock time.
    /// Elapsed time is bounded before trigonometry. Reduce Motion ignores time, level and processing
    /// completely, returning one quiet static frame (including a stationary colour palette).
    public static func frame(elapsed: Double, level: Double, processing: Bool,
                             processingElapsed: Double? = nil, reduceMotion: Bool = false) -> Frame {
        let time = reduceMotion ? 0 : finiteTime(elapsed)
        let input = reduceMotion ? 0.12 : clamp(level)
        let normalized = input <= 0.015 ? 0 : (1 - exp(-3 * (input - 0.015) / 0.985)) / (1 - exp(-3))
        // A stateless frame cannot infer historic audio. This onset follows the donor attack;
        // callers that have a meter envelope retain ownership of its continuous sampling/release.
        let meter = reduceMotion ? 0.12 : normalized * (1 - exp(-time / 0.325))
        let processingTime = finiteTime(processingElapsed ?? elapsed)
        let gather = processing && !reduceMotion ? smoothstep(1 - exp(-processingTime / (processingEase * 0.9))) : 0
        let sweep = reduceMotion ? 0 : processingPosition(elapsed: processingTime)
        let breathing = reduceMotion ? 0.5 : 0.5 + 0.5 * sin(2 * .pi * time / 5.2)
        let quiet = meter + (1 - meter) * 0.18 * breathing
        let processingDrive = 0.55 * smoothstep(clamp((gather - 0.25) / 0.75))
        let drive = reduceMotion ? 0.12 : max(quiet, processingDrive)
        let width = (0.85 + 1.05 * drive) * (1 + gather * 0.3 * (1 - sweep * sweep))
        // The browser integrates 48 * drive * dt. A stateless native frame uses a quiet fixed
        // velocity instead: multiplying today's level by all elapsed time would jump the lobes
        // when a meter changes late in a session. Level still controls their reach and width.
        let phase = reduceMotion ? 0 : (24 * time).truncatingRemainder(dividingBy: 36 * 7 * 0.85)
        return Frame(level: meter, gather: gather, sweep: processing ? sweep : 0, reducedMotion: reduceMotion,
                     hueDegrees: reduceMotion ? 0 : -24 * cos(2 * .pi * time / 12), phase: phase,
                     time: time, drive: drive, widthScale: width, heightScale: 0.5 + 1.2 * drive)
    }

    /// 1.1-second eased edge-to-edge legs; a new processing phase begins at the centre.
    public static func processingPosition(elapsed: Double) -> Double {
        let cycle = (finiteTime(elapsed) + processingDuration / 2)
            .truncatingRemainder(dividingBy: processingDuration * 2) / processingDuration
        let fraction = cycle.truncatingRemainder(dividingBy: 1)
        let eased = fraction < 0.5 ? 0.5 * pow(2 * fraction, processingCurve)
            : 1 - 0.5 * pow(2 - 2 * fraction, processingCurve)
        return cycle < 1 ? 2 * eased - 1 : 1 - 2 * eased
    }

    private static func bell(_ x: Double) -> Double {
        let spread = max(0.05, 0.87 * (x < 0 ? 0.88 : 1.12))
        let edge = exp(-pow(1 / spread, 1.75))
        return max(0, (exp(-pow(abs(x) / spread, 1.75)) - edge) / (1 - edge))
    }

    private static func cornerLift(x: Double, width: Double, radius: Double, inset: Double = 0) -> Double {
        guard radius > 0 else { return 0 }
        let edge = min(x, width - x) - inset
        if edge >= radius { return 0 }
        if edge <= 0 { return radius }
        return radius - sqrt(max(0, radius * radius - pow(radius - edge, 2)))
    }

    private static func clamp(_ value: Double) -> Double { value.isFinite ? min(1, max(0, value)) : 0 }
    private static func finiteTime(_ value: Double) -> Double { value.isFinite ? min(86_400, max(0, value)) : 0 }
    private static func dimension(_ value: Double) -> Double { value.isFinite ? min(16_384, max(0, value)) : 0 }
    private static func smoothstep(_ value: Double) -> Double { value * value * (3 - 2 * value) }
    private static func wrap(_ value: Double, period: Double) -> Double {
        let shifted = (value + period / 2).truncatingRemainder(dividingBy: period)
        return (shifted < 0 ? shifted + period : shifted) - period / 2
    }
}
