import Foundation

/// Closed-notch recording wing presentation: pulse, spoken elapsed, Stop availability, a11y copy.
/// Pure; the app paints it. Only Recordly has a production producer; `.meetingFixture` is for
/// synthetic tests until Meetings wiring is unblocked.
public enum RecordingMotion {
    public enum Producer: String, Sendable, CaseIterable { case recordly, meetingFixture }
    public enum Phase: Equatable, Sendable { case recording, inactive }
    public enum StopAvailability: Equatable, Sendable { case available, unavailable }

    public enum PulseSpec: Equatable, Sendable {
        /// Today's dot: full opacity, no scale, no halo. Used under Reduce Motion or without a clock.
        case steady
        case breathe(period: TimeInterval, minOpacity: Double, maxScale: Double, maxHalo: Double)
    }

    public struct PulseFrame: Equatable, Sendable {
        public var opacity: Double
        public var scale: Double
        public var haloRadius: Double

        public init(opacity: Double, scale: Double, haloRadius: Double) {
            self.opacity = opacity
            self.scale = scale
            self.haloRadius = haloRadius
        }

        public static let steady = PulseFrame(opacity: 1, scale: 1, haloRadius: 0)
    }

    public struct Input: Equatable, Sendable {
        public var producer: Producer
        public var isRecording: Bool
        /// nil = no verified clock from the producer.
        public var elapsed: TimeInterval?
        public var stopAvailable: Bool

        public init(producer: Producer, isRecording: Bool, elapsed: TimeInterval?, stopAvailable: Bool) {
            self.producer = producer
            self.isRecording = isRecording
            self.elapsed = elapsed
            self.stopAvailable = stopAvailable
        }

        /// ClosedWings shows `.recordly` only while `isRecording`, and Recordly exposes `stop()`.
        public static func recordly(elapsed: TimeInterval) -> Input {
            Input(producer: .recordly, isRecording: true, elapsed: elapsed, stopAvailable: true)
        }
    }

    public struct Accessibility: Equatable, Sendable {
        public var label: String
        public var value: String
        public var stopLabel: String
        public var stopHint: String

        public init(label: String, value: String, stopLabel: String, stopHint: String) {
            self.label = label
            self.value = value
            self.stopLabel = stopLabel
            self.stopHint = stopHint
        }
    }

    public struct Presentation: Equatable, Sendable {
        public var phase: Phase
        public var pulse: PulseSpec
        public var stop: StopAvailability
        public var accessibility: Accessibility

        public init(phase: Phase, pulse: PulseSpec, stop: StopAvailability, accessibility: Accessibility) {
            self.phase = phase
            self.pulse = pulse
            self.stop = stop
            self.accessibility = accessibility
        }
    }

    /// Mirrors RecordlyController's tick timer (0.2 s); used as the per-sample animation length.
    public static let sampleInterval: TimeInterval = 0.2
    public static let breathe = PulseSpec.breathe(period: 2.0, minOpacity: 0.55, maxScale: 1.12, maxHalo: 4)

    static let stopLabel = "Stop recording"
    static let stopHint = "Stops the screen recording."

    public static func present(_ input: Input, reduceMotion: Bool) -> Presentation {
        let label = input.producer == .recordly ? "Screen recording" : "Meeting recording (preview)"
        guard input.isRecording else {
            return Presentation(
                phase: .inactive, pulse: .steady, stop: .unavailable,
                accessibility: Accessibility(label: label, value: "Not recording",
                                             stopLabel: stopLabel, stopHint: stopHint))
        }
        let clockOK = input.elapsed.map { $0.isFinite } ?? false
        let spoken = input.elapsed.flatMap { spokenElapsed($0) }
        return Presentation(
            phase: .recording,
            pulse: (reduceMotion || !clockOK) ? .steady : breathe,
            stop: input.stopAvailable ? .available : .unavailable,
            accessibility: Accessibility(label: label, value: spoken ?? "Elapsed time unavailable",
                                         stopLabel: stopLabel, stopHint: stopHint))
    }

    /// k = 0.5 + 0.5·cos(2πt/period): peak at t=0, trough at period/2. Steady if spec is .steady or t is nil/non-finite.
    public static func frame(_ spec: PulseSpec, at elapsed: TimeInterval?) -> PulseFrame {
        guard case let .breathe(period, minOpacity, maxScale, maxHalo) = spec,
              let t = elapsed, t.isFinite, period > 0 else { return .steady }
        let k = 0.5 + 0.5 * cos(2 * Double.pi * t / period)
        return PulseFrame(opacity: minOpacity + (1 - minOpacity) * k,
                          scale: 1 + (maxScale - 1) * k,
                          haloRadius: maxHalo * k)
    }

    /// Same rounding as RecordlyElapsed; English copy to match the app's "Stop". Non-finite → nil.
    public static func spokenElapsed(_ seconds: TimeInterval) -> String? {
        guard seconds.isFinite else { return nil }
        let total = Int(max(0, min(seconds, 1e9)).rounded())
        let minutes = total / 60
        let secs = total % 60
        func unit(_ n: Int, _ name: String) -> String { "\(n) \(name)\(n == 1 ? "" : "s")" }
        if minutes == 0 { return unit(secs, "second") }
        if secs == 0 { return unit(minutes, "minute") }
        return "\(unit(minutes, "minute")), \(unit(secs, "second"))"
    }
}
