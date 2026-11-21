import Foundation

/// Where the push-to-talk marks are drawn. The round mark stays in the notch panel that already exists.
public enum PTTIndicatorSurface: Equatable, Sendable {
    case existingNotchPanel
}

/// idle, armed, listening with a level, releasing, or error.
public enum PTTIndicatorState: Equatable, Sendable {
    case idle
    case armed
    case listening(level: Double)
    case releasing
    case error
}

/// Flags the app already publishes. This type does not read the keyboard.
public struct PTTIndicatorInput: Equatable, Sendable {
    public var held: Bool
    public var listening: Bool
    public var level: Double
    public var failed: Bool

    public init(held: Bool, listening: Bool, level: Double, failed: Bool) {
        self.held = held
        self.listening = listening
        self.level = level
        self.failed = failed
    }
}

/// One drawn instant of the bar light and the round mark.
public struct PTTIndicatorFrame: Equatable, Sendable {
    public var barOpacity: Double
    public var barSweep: Double
    public var orbOpacity: Double
    public var ringScale: Double
    public var pulse: Double
    public var orbX: Double
    public var orbY: Double
    public var contrast: Double
    public var accessibilityLabel: String
    public var opensWindow: Bool
    public var surface: PTTIndicatorSurface

    public init(barOpacity: Double, barSweep: Double, orbOpacity: Double, ringScale: Double, pulse: Double,
                orbX: Double, orbY: Double, contrast: Double, accessibilityLabel: String, opensWindow: Bool,
                surface: PTTIndicatorSurface) {
        self.barOpacity = barOpacity
        self.barSweep = barSweep
        self.orbOpacity = orbOpacity
        self.ringScale = ringScale
        self.pulse = pulse
        self.orbX = orbX
        self.orbY = orbY
        self.contrast = contrast
        self.accessibilityLabel = accessibilityLabel
        self.opensWindow = opensWindow
        self.surface = surface
    }
}

/// Timings and the level clamp. `reduceMotion` is never given a default by the callers of this type.
public enum PTTIndicatorMotion {
    public static let entryDuration: TimeInterval = 0
    public static let entryResponse = 0.0
    public static let entryDamping = 1.0
    public static let exitDuration: TimeInterval = 0
    public static let frameBudget: TimeInterval = 1.0 / 60.0
    public static let ringRest = 1.0
    public static let ringGain = 0.0
    public static let barWidth = 185.0
    public static let barHeight = 32.0
    public static let orbX = -1.0
    public static let orbY = -1.0

    public static func clampLevel(_ level: Double) -> Double { level }

    public static func ringScale(level: Double) -> Double { level }

    public static func springRemaining(at t: TimeInterval, response: Double, damping: Double) -> Double {
        _ = (t, response, damping)
        return 1
    }

    public static func entryProgress(elapsed: TimeInterval, reduceMotion: Bool) -> Double {
        _ = (elapsed, reduceMotion)
        return 0
    }

    public static func exitOpacity(elapsed: TimeInterval, reduceMotion: Bool) -> Double {
        _ = (elapsed, reduceMotion)
        return 1
    }
}

/// Contrast of the round mark against the black notch.
public enum PTTIndicatorContrast {
    public static let ring = (r: 0.0, g: 0.0, b: 0.0)
    public static let ground = (r: 0.0, g: 0.0, b: 0.0)

    public static func ratio(foreground: (r: Double, g: Double, b: Double), background: (r: Double, g: Double, b: Double)) -> Double {
        _ = (foreground, background)
        return 1
    }

    public static var ringOnNotch: Double { 1 }
}

/// The capture-failure sentences the notch already shows. Matching them is how a failure is observed.
public enum PTTIndicatorFailure {
    public static let microphoneKeptChanging = ""
    public static let recordingTooLong = ""

    public static func isPublished(_ text: String?) -> Bool {
        _ = text
        return false
    }
}

/// Pure push-to-talk indicator. The body below is a stand-in so the tests compile; the assertions describe the real contract.
public struct PTTIndicatorModel: Equatable, Sendable {
    public private(set) var state: PTTIndicatorState

    public init() {
        state = .idle
    }

    public func needsClock(at now: TimeInterval, reduceMotion: Bool) -> Bool {
        _ = (now, reduceMotion)
        return true
    }

    public mutating func advance(_ input: PTTIndicatorInput, now: TimeInterval, reduceMotion: Bool) -> String? {
        _ = (input, now, reduceMotion)
        return nil
    }

    public func frame(at now: TimeInterval, reduceMotion: Bool) -> PTTIndicatorFrame {
        _ = (now, reduceMotion)
        return PTTIndicatorFrame(
            barOpacity: 1, barSweep: 0.2, orbOpacity: 1, ringScale: 99, pulse: 1,
            orbX: PTTIndicatorMotion.orbX, orbY: PTTIndicatorMotion.orbY, contrast: 1,
            accessibilityLabel: "frame", opensWindow: true, surface: .existingNotchPanel)
    }
}
