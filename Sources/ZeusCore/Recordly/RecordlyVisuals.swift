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
        let box = RecordlyVisualsBox.tokens(for: boxPhase(phase))
        return RecordlyVisualTokens(
            previewDim: box.previewDim, liveFrameOpacity: box.liveFrameOpacity, ambientGlow: box.ambientGlow,
            buttonCorner: box.buttonCorner, showsLiveCapsule: box.showsLiveCapsule, showsMeters: box.showsMeters,
            showsCountdownNumeral: box.showsCountdownNumeral, previewInteractive: box.previewInteractive)
    }

    private static func boxPhase(_ phase: RecordlyVisualPhase) -> RecordlyVisualsBox.Phase {
        switch phase {
        case .idle: .idle
        case .countdown: .countdown
        case .starting: .starting
        case .recording: .recording
        case .stopping: .stopping
        case .saved: .saved
        }
    }
}

/// The large 3-2-1 numeral and the ring around the button.
public enum RecordlyCountdownVisual {
    /// The digit to show, or nil outside a countdown. Out-of-range values clamp to 1...seconds.
    public static func numeral(remaining: Int?) -> String? {
        RecordlyVisualsBox.numeral(remaining: remaining, seconds: RecordlyCountdown.seconds)
    }

    /// Ring progress 0...1 for the time since the countdown began.
    public static func ringProgress(elapsed: TimeInterval) -> Double {
        RecordlyVisualsBox.ringProgress(elapsed: elapsed, seconds: RecordlyCountdown.seconds)
    }

    /// Where inside the current second we are, 0...1. The numeral springs in at 0 and settles by about 0.35.
    public static func stepFraction(elapsed: TimeInterval) -> Double {
        RecordlyVisualsBox.stepFraction(elapsed: elapsed)
    }

    /// Numeral scale: starts large, settles to 1 with a small overshoot-free ease, then rests.
    public static func numeralScale(stepFraction: Double) -> Double {
        RecordlyVisualsBox.numeralScale(stepFraction: stepFraction)
    }

    /// Numeral opacity: fades in fast, fades out over the last quarter second so the next digit replaces it.
    public static func numeralOpacity(stepFraction: Double) -> Double {
        RecordlyVisualsBox.numeralOpacity(stepFraction: stepFraction)
    }
}

/// Which rows the live capsule's level meters show.
public enum RecordlyLiveMeterRows {
    /// The Mic row appears only while microphone capture is actually on.
    public static func showsMic(_ audio: RecordlyAudioOptions) -> Bool {
        RecordlyVisualsBox.showsMic(microphone: audio.microphone)
    }
}

/// One level meter: 0...1 in, smoothed 0...1 out. Fast attack, slow release, so bars rise quickly and fall gently.
public struct RecordlyLevelMeter: Equatable, Sendable {
    public static let attackPerSecond = RecordlyVisualsBox.attackPerSecond
    public static let releasePerSecond = RecordlyVisualsBox.releasePerSecond
    public private(set) var value: Double = 0

    public init() {}

    /// Advances the meter toward `target` over `dt` seconds and returns the new value.
    @discardableResult
    public mutating func step(target: Double, dt: TimeInterval) -> Double {
        value = RecordlyVisualsBox.meterStep(value: value, target: target, dt: dt)
        return value
    }

    public mutating func reset() { value = 0 }

    /// Maps linear peak amplitude (0...1) to a perceptual 0...1 meter position over a 48 dB range.
    public static func perceptual(peak: Float) -> Double {
        RecordlyVisualsBox.perceptual(peak: Double(peak))
    }

    /// How many of `count` segments are lit for a 0...1 value.
    public static func litSegments(value: Double, count: Int) -> Int {
        RecordlyVisualsBox.litSegments(value: value, count: count)
    }
}

/// The staggered entrance: preview, picker, chips, button, about 0.35 s from start to the last item settling.
public enum RecordlyEntrance {
    public enum Item: Int, CaseIterable, Sendable {
        case preview = 0, picker, chips, button
    }

    public static let itemDuration = RecordlyVisualsBox.entranceItemDuration
    public static let stagger = RecordlyVisualsBox.entranceStagger
    /// Start of the last item plus its duration.
    public static var totalDuration: Double { RecordlyVisualsBox.entranceTotal(itemCount: Item.allCases.count) }

    /// Delay before an item starts. Reduce Motion has no stagger: everything cross-fades together.
    public static func delay(_ item: Item, reduceMotion: Bool) -> Double {
        RecordlyVisualsBox.entranceDelay(index: item.rawValue, reduceMotion: reduceMotion)
    }

    public static func offset(reduceMotion: Bool) -> Double {
        RecordlyVisualsBox.entranceOffset(reduceMotion: reduceMotion)
    }
}

/// State of one source chip (System audio, Microphone, Cursor zoom, and so on).
public enum RecordlySourceChipState: Equatable, Sendable {
    case on
    case off
    case needsPermission
    case unavailable

    public static func resolve(on: Bool, available: Bool, needsPermission: Bool) -> RecordlySourceChipState {
        switch RecordlyVisualsBox.chip(on: on, available: available, needsPermission: needsPermission) {
        case .on: .on
        case .off: .off
        case .needsPermission: .needsPermission
        case .unavailable: .unavailable
        }
    }

    /// The short word shown or spoken next to the chip title.
    public var word: String { RecordlyVisualsBox.chipWord(Self.boxChip(self)) }

    public var isInteractive: Bool { RecordlyVisualsBox.chipInteractive(Self.boxChip(self)) }

    private static func boxChip(_ state: RecordlySourceChipState) -> RecordlyVisualsBox.Chip {
        switch state {
        case .on: .on
        case .off: .off
        case .needsPermission: .needsPermission
        case .unavailable: .unavailable
        }
    }
}

/// Text for the saved clip card.
public enum RecordlyClipSummary {
    /// "0:07", "1:05", "1:02:09".
    public static func duration(_ seconds: TimeInterval) -> String {
        RecordlyVisualsBox.durationText(seconds)
    }

    /// "812 KB", "4.2 MB", "1.3 GB". Decimal units, one decimal from MB up.
    public static func fileSize(_ bytes: Int64) -> String {
        RecordlyVisualsBox.fileSize(bytes)
    }

    /// "0:07 · 4.2 MB", skipping whichever part is unknown.
    public static func line(duration seconds: TimeInterval?, bytes: Int64?) -> String {
        RecordlyVisualsBox.summaryLine(duration: seconds, bytes: bytes)
    }
}
