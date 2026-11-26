import Foundation

/// Record page visual numbers: phase tokens, the countdown numeral, meter smoothing, the entrance
/// stagger, chip words, and the saved-clip line. Doubles and strings only. The caller supplies the
/// phase and the countdown length. This type does not read a screen, a pointer, a clock, or a stored setting.
public enum RecordlyVisualsBox {
    public enum Phase: Equatable, Sendable {
        case idle
        case countdown
        case starting
        case recording
        case stopping
        case saved
    }

    public struct Tokens: Equatable, Sendable {
        public var previewDim: Double
        public var liveFrameOpacity: Double
        public var ambientGlow: Double
        public var buttonCorner: Double
        public var showsLiveCapsule: Bool
        public var showsMeters: Bool
        public var showsCountdownNumeral: Bool
        public var previewInteractive: Bool

        public init(
            previewDim: Double, liveFrameOpacity: Double, ambientGlow: Double, buttonCorner: Double,
            showsLiveCapsule: Bool, showsMeters: Bool, showsCountdownNumeral: Bool, previewInteractive: Bool
        ) {
            self.previewDim = previewDim
            self.liveFrameOpacity = liveFrameOpacity
            self.ambientGlow = ambientGlow
            self.buttonCorner = buttonCorner
            self.showsLiveCapsule = showsLiveCapsule
            self.showsMeters = showsMeters
            self.showsCountdownNumeral = showsCountdownNumeral
            self.previewInteractive = previewInteractive
        }
    }

    public static func tokens(for phase: Phase) -> Tokens {
        switch phase {
        case .idle:
            Tokens(previewDim: 0, liveFrameOpacity: 0, ambientGlow: 0.34, buttonCorner: 0.5,
                   showsLiveCapsule: false, showsMeters: false, showsCountdownNumeral: false,
                   previewInteractive: true)
        case .countdown:
            Tokens(previewDim: 0.32, liveFrameOpacity: 0, ambientGlow: 0.5, buttonCorner: 0.5,
                   showsLiveCapsule: false, showsMeters: false, showsCountdownNumeral: true,
                   previewInteractive: false)
        case .starting:
            Tokens(previewDim: 0.18, liveFrameOpacity: 0, ambientGlow: 0.2, buttonCorner: 0.5,
                   showsLiveCapsule: false, showsMeters: false, showsCountdownNumeral: false,
                   previewInteractive: false)
        case .recording:
            Tokens(previewDim: 0, liveFrameOpacity: 1, ambientGlow: 0, buttonCorner: 0.3,
                   showsLiveCapsule: true, showsMeters: true, showsCountdownNumeral: false,
                   previewInteractive: false)
        case .stopping:
            Tokens(previewDim: 0.12, liveFrameOpacity: 0.5, ambientGlow: 0, buttonCorner: 0.3,
                   showsLiveCapsule: true, showsMeters: false, showsCountdownNumeral: false,
                   previewInteractive: false)
        case .saved:
            Tokens(previewDim: 0, liveFrameOpacity: 0, ambientGlow: 0.2, buttonCorner: 0.5,
                   showsLiveCapsule: false, showsMeters: false, showsCountdownNumeral: false,
                   previewInteractive: false)
        }
    }

    /// The digit to show, or nil when nothing is counting. Out-of-range values clamp to 1...`seconds`.
    public static func numeral(remaining: Int?, seconds: Int) -> String? {
        guard let remaining else { return nil }
        return String(min(max(remaining, 1), seconds))
    }

    /// Ring progress 0...1 for the time since the countdown began. A non-finite elapsed reads as zero.
    public static func ringProgress(elapsed: Double, seconds: Int) -> Double {
        guard elapsed.isFinite else { return 0 }
        return min(1, max(0, elapsed / Double(seconds)))
    }

    /// Where inside the current second we are, 0...1. A non-finite or negative elapsed reads as zero.
    public static func stepFraction(elapsed: Double) -> Double {
        guard elapsed.isFinite, elapsed >= 0 else { return 0 }
        return elapsed - elapsed.rounded(.down)
    }

    /// Numeral scale: starts large, settles to 1 over the first 0.35 of the second.
    public static func numeralScale(stepFraction: Double) -> Double {
        let t = min(1, max(0, stepFraction / 0.35))
        let eased = 1 - pow(1 - t, 3)
        return 1.35 - 0.35 * eased
    }

    /// Numeral opacity: fades in over 0.12, then fades out over the last quarter of the second.
    public static func numeralOpacity(stepFraction: Double) -> Double {
        let f = min(1, max(0, stepFraction))
        let fadeIn = min(1, f / 0.12)
        let fadeOut = f > 0.75 ? max(0, 1 - (f - 0.75) / 0.25) : 1
        return fadeIn * fadeOut
    }

    /// The Mic row appears only while microphone capture is actually on.
    public static func showsMic(microphone: Bool) -> Bool { microphone }

    public static let attackPerSecond = 18.0
    public static let releasePerSecond = 4.5

    /// Next meter value. A non-finite target reads as zero. A non-finite step reads as no time.
    /// The step is clamped to 0...0.25. A result under 0.001 snaps to zero.
    public static func meterStep(value: Double, target: Double, dt: Double) -> Double {
        let goal = target.isFinite ? min(1, max(0, target)) : 0
        let delta = dt.isFinite ? min(max(dt, 0), 0.25) : 0
        let rate = goal > value ? attackPerSecond : releasePerSecond
        let blend = 1 - exp(-rate * delta)
        var next = value + (goal - value) * blend
        if next < 0.001 { next = 0 }
        return next
    }

    /// Maps linear peak amplitude (0...1) to a perceptual 0...1 meter position over a 48 dB range.
    /// A non-finite, negative, or zero peak reads as zero. Peaks above 1 read as full.
    public static func perceptual(peak: Double) -> Double {
        guard peak.isFinite, peak > 0 else { return 0 }
        let db = 20 * log10(min(peak, 1))
        return min(1, max(0, (db + 48) / 48))
    }

    /// How many of `count` segments are lit for a 0...1 value.
    public static func litSegments(value: Double, count: Int) -> Int {
        guard count > 0, value.isFinite else { return 0 }
        return min(count, max(0, Int((min(1, max(0, value)) * Double(count)).rounded())))
    }

    public static let entranceItemDuration = 0.2
    public static let entranceStagger = 0.05

    /// Start of the last item plus its duration.
    public static func entranceTotal(itemCount: Int) -> Double {
        Double(itemCount - 1) * entranceStagger + entranceItemDuration
    }

    /// Delay before an item starts. Reduce Motion has no stagger.
    public static func entranceDelay(index: Int, reduceMotion: Bool) -> Double {
        reduceMotion ? 0 : Double(index) * entranceStagger
    }

    public static func entranceOffset(reduceMotion: Bool) -> Double { reduceMotion ? 0 : 10 }

    public enum Chip: Equatable, Sendable {
        case on
        case off
        case needsPermission
        case unavailable
    }

    public static func chip(on: Bool, available: Bool, needsPermission: Bool) -> Chip {
        if needsPermission { return .needsPermission }
        if !available { return on ? .on : .unavailable }
        return on ? .on : .off
    }

    public static func chipWord(_ chip: Chip) -> String {
        switch chip {
        case .on: "On"
        case .off: "Off"
        case .needsPermission: "Needs permission"
        case .unavailable: "Soon"
        }
    }

    public static func chipInteractive(_ chip: Chip) -> Bool { chip == .on || chip == .off }

    /// "0:07", "1:05", "1:02:09". A non-finite or non-positive duration reads as "0:00".
    public static func durationText(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// "812 KB", "4.2 MB", "1.3 GB". Decimal units, one decimal from MB up. A non-positive size reads as "0 KB".
    public static func fileSize(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0 KB" }
        let value = Double(bytes)
        if value < 1_000_000 { return "\(max(1, Int((value / 1000).rounded()))) KB" }
        if value < 1_000_000_000 { return String(format: "%.1f MB", value / 1_000_000) }
        return String(format: "%.1f GB", value / 1_000_000_000)
    }

    /// "0:07 · 4.2 MB", skipping whichever part is unknown or not positive.
    public static func summaryLine(duration seconds: Double?, bytes: Int64?) -> String {
        var parts: [String] = []
        if let seconds, seconds > 0 { parts.append(durationText(seconds)) }
        if let bytes, bytes > 0 { parts.append(fileSize(bytes)) }
        return parts.joined(separator: " \u{00B7} ")
    }
}
