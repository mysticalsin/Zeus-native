import Foundation

/// Pure presentation rules for the Record page: which visual tokens each phase uses, the 3-2-1 numeral
/// choreography, level smoothing for the meters, the staggered entrance and the saved-clip summary text.
/// No SwiftUI, no AppKit, no I/O, so every number the page animates with is testable.

/// The visual phase of the Record page. One value drives preview dimming, frame, capsule and button shape.
public enum RecordlyVisualPhase: Equatable, Sendable {
    case idle
    case countdown(Int)
    case starting
    case recording
    case stopping
    case saved
}

/// Everything a view needs to dress one phase. Opacities are 0...1, `buttonCorner` is a fraction of the side
/// (0.5 is a circle, 0.3 a rounded square).
public struct RecordlyVisualTokens: Equatable, Sendable {
    /// Black overlay on the preview. The countdown dims it slightly.
    public let previewDim: Double
    /// Red frame around the preview. Only while capturing.
    public let liveFrameOpacity: Double
    /// Soft ambient glow behind the capture button. Calm at rest, gone while capturing.
    public let ambientGlow: Double
    public let buttonCorner: Double
    public let showsLiveCapsule: Bool
    public let showsMeters: Bool
    public let showsCountdownNumeral: Bool
    /// The preview stage is interactive (display tiles can be chosen).
    public let previewInteractive: Bool

    public static func tokens(for phase: RecordlyVisualPhase) -> RecordlyVisualTokens {
        switch phase {
        case .idle:
            RecordlyVisualTokens(previewDim: 0, liveFrameOpacity: 0, ambientGlow: 0.34, buttonCorner: 0.5,
                                 showsLiveCapsule: false, showsMeters: false, showsCountdownNumeral: false,
                                 previewInteractive: true)
        case .countdown:
            RecordlyVisualTokens(previewDim: 0.32, liveFrameOpacity: 0, ambientGlow: 0.5, buttonCorner: 0.5,
                                 showsLiveCapsule: false, showsMeters: false, showsCountdownNumeral: true,
                                 previewInteractive: false)
        case .starting:
            RecordlyVisualTokens(previewDim: 0.18, liveFrameOpacity: 0, ambientGlow: 0.2, buttonCorner: 0.5,
                                 showsLiveCapsule: false, showsMeters: false, showsCountdownNumeral: false,
                                 previewInteractive: false)
        case .recording:
            RecordlyVisualTokens(previewDim: 0, liveFrameOpacity: 1, ambientGlow: 0, buttonCorner: 0.3,
                                 showsLiveCapsule: true, showsMeters: true, showsCountdownNumeral: false,
                                 previewInteractive: false)
        case .stopping:
            RecordlyVisualTokens(previewDim: 0.12, liveFrameOpacity: 0.5, ambientGlow: 0, buttonCorner: 0.3,
                                 showsLiveCapsule: true, showsMeters: false, showsCountdownNumeral: false,
                                 previewInteractive: false)
        case .saved:
            RecordlyVisualTokens(previewDim: 0, liveFrameOpacity: 0, ambientGlow: 0.2, buttonCorner: 0.5,
                                 showsLiveCapsule: false, showsMeters: false, showsCountdownNumeral: false,
                                 previewInteractive: false)
        }
    }
}

/// The large 3-2-1 numeral and the ring around the button.
public enum RecordlyCountdownVisual {
    /// The digit to show, or nil outside a countdown. Out-of-range values clamp to 1...seconds.
    public static func numeral(remaining: Int?) -> String? {
        guard let remaining else { return nil }
        return String(min(max(remaining, 1), RecordlyCountdown.seconds))
    }

    /// Ring progress 0...1 for the time since the countdown began.
    public static func ringProgress(elapsed: TimeInterval) -> Double {
        guard elapsed.isFinite else { return 0 }
        return min(1, max(0, elapsed / Double(RecordlyCountdown.seconds)))
    }

    /// Where inside the current second we are, 0...1. The numeral springs in at 0 and settles by about 0.35.
    public static func stepFraction(elapsed: TimeInterval) -> Double {
        guard elapsed.isFinite, elapsed >= 0 else { return 0 }
        return elapsed - elapsed.rounded(.down)
    }

    /// Numeral scale: starts large, settles to 1 with a small overshoot-free ease, then rests.
    public static func numeralScale(stepFraction: Double) -> Double {
        let t = min(1, max(0, stepFraction / 0.35))
        let eased = 1 - pow(1 - t, 3)
        return 1.35 - 0.35 * eased
    }

    /// Numeral opacity: fades in fast, fades out over the last quarter second so the next digit replaces it.
    public static func numeralOpacity(stepFraction: Double) -> Double {
        let f = min(1, max(0, stepFraction))
        let fadeIn = min(1, f / 0.12)
        let fadeOut = f > 0.75 ? max(0, 1 - (f - 0.75) / 0.25) : 1
        return fadeIn * fadeOut
    }
}

/// One level meter: 0...1 in, smoothed 0...1 out. Fast attack, slow release, so bars rise quickly and fall gently.
public struct RecordlyLevelMeter: Equatable, Sendable {
    public static let attackPerSecond = 18.0
    public static let releasePerSecond = 4.5
    public private(set) var value: Double = 0

    public init() {}

    /// Advances the meter toward `target` over `dt` seconds and returns the new value.
    @discardableResult
    public mutating func step(target: Double, dt: TimeInterval) -> Double {
        let goal = target.isFinite ? min(1, max(0, target)) : 0
        let delta = dt.isFinite ? min(max(dt, 0), 0.25) : 0
        let rate = goal > value ? Self.attackPerSecond : Self.releasePerSecond
        let blend = 1 - exp(-rate * delta)
        value += (goal - value) * blend
        if value < 0.001 { value = 0 }
        return value
    }

    public mutating func reset() { value = 0 }

    /// Maps linear peak amplitude (0...1) to a perceptual 0...1 meter position over a 48 dB range.
    public static func perceptual(peak: Float) -> Double {
        guard peak.isFinite, peak > 0 else { return 0 }
        let db = 20 * log10(Double(min(peak, 1)))
        return min(1, max(0, (db + 48) / 48))
    }

    /// How many of `count` segments are lit for a 0...1 value.
    public static func litSegments(value: Double, count: Int) -> Int {
        guard count > 0, value.isFinite else { return 0 }
        return min(count, max(0, Int((min(1, max(0, value)) * Double(count)).rounded())))
    }
}

/// The staggered entrance: preview, picker, chips, button, about 0.35 s from start to the last item settling.
public enum RecordlyEntrance {
    public enum Item: Int, CaseIterable, Sendable {
        case preview = 0, picker, chips, button
    }

    public static let itemDuration = 0.2
    public static let stagger = 0.05
    /// Start of the last item plus its duration.
    public static var totalDuration: Double { Double(Item.allCases.count - 1) * stagger + itemDuration }

    /// Delay before an item starts. Reduce Motion has no stagger: everything cross-fades together.
    public static func delay(_ item: Item, reduceMotion: Bool) -> Double {
        reduceMotion ? 0 : Double(item.rawValue) * stagger
    }

    public static func offset(reduceMotion: Bool) -> Double { reduceMotion ? 0 : 10 }
}

/// State of one source chip (System audio, Microphone, Cursor zoom, and so on).
public enum RecordlySourceChipState: Equatable, Sendable {
    case on
    case off
    case needsPermission
    case unavailable

    public static func resolve(on: Bool, available: Bool, needsPermission: Bool) -> RecordlySourceChipState {
        if needsPermission { return .needsPermission }
        if !available { return on ? .on : .unavailable }
        return on ? .on : .off
    }

    /// The short word shown or spoken next to the chip title.
    public var word: String {
        switch self {
        case .on: "On"
        case .off: "Off"
        case .needsPermission: "Needs permission"
        case .unavailable: "Soon"
        }
    }

    public var isInteractive: Bool { self == .on || self == .off }
}

/// Text for the saved clip card.
public enum RecordlyClipSummary {
    /// "0:07", "1:05", "1:02:09".
    public static func duration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// "812 KB", "4.2 MB", "1.3 GB". Decimal units, one decimal from MB up.
    public static func fileSize(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0 KB" }
        let value = Double(bytes)
        if value < 1_000_000 { return "\(max(1, Int((value / 1000).rounded()))) KB" }
        if value < 1_000_000_000 { return String(format: "%.1f MB", value / 1_000_000) }
        return String(format: "%.1f GB", value / 1_000_000_000)
    }

    /// "0:07 · 4.2 MB", skipping whichever part is unknown.
    public static func line(duration seconds: TimeInterval?, bytes: Int64?) -> String {
        var parts: [String] = []
        if let seconds, seconds > 0 { parts.append(Self.duration(seconds)) }
        if let bytes, bytes > 0 { parts.append(fileSize(bytes)) }
        return parts.joined(separator: " \u{00B7} ")
    }
}
