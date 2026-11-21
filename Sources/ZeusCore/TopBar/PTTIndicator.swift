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

/// Timings and the level clamp. Callers pass `reduceMotion` themselves. It has no default here.
public enum PTTIndicatorMotion {
    /// Spring response, inside the 180 to 240 ms entry window.
    public static let entryDuration: TimeInterval = 0.21
    public static let entryResponse = 0.21
    public static let entryDamping = 0.82
    public static let exitDuration: TimeInterval = 0.15
    /// One frame at 60 Hz. A release leaves `listening` inside this budget.
    public static let frameBudget: TimeInterval = 1.0 / 60.0
    public static let ringRest = 1.0
    public static let ringGain = 0.28
    /// The closed bar the orb is measured against. The live panel already owns this rect.
    public static let barWidth = 185.0
    public static let barHeight = 32.0
    public static let orbX = 92.5
    public static let orbY = 16.0

    public static func clampLevel(_ level: Double) -> Double {
        guard level.isFinite else { return 0 }
        return min(1, max(0, level))
    }

    public static func ringScale(level: Double) -> Double {
        ringRest + ringGain * clampLevel(level)
    }

    /// What is left of a unit spring at `t`. 1 at the start, 0 once settled, negative on an overshoot.
    public static func springRemaining(at t: TimeInterval, response: Double, damping: Double) -> Double {
        guard t.isFinite, t > 0, response > 0, damping.isFinite else { return 1 }
        let omega = 2 * Double.pi / response
        if damping >= 1 {
            return (1 + omega * t) * exp(-omega * t)
        }
        let damped = omega * (1 - damping * damping).squareRoot()
        guard damped > 0 else { return (1 + omega * t) * exp(-omega * t) }
        return exp(-damping * omega * t) * (cos(damped * t) + damping * omega / damped * sin(damped * t))
    }

    public static func entryProgress(elapsed: TimeInterval, reduceMotion: Bool) -> Double {
        if reduceMotion { return 1 }
        guard elapsed.isFinite, elapsed > 0 else { return 0 }
        let remaining = springRemaining(at: elapsed, response: entryResponse, damping: entryDamping)
        return min(1, max(0, 1 - remaining))
    }

    public static func exitOpacity(elapsed: TimeInterval, reduceMotion: Bool) -> Double {
        if reduceMotion { return 0 }
        guard elapsed.isFinite, elapsed > 0 else { return 1 }
        // A sum such as 1 + 0.15 can land a hair under the duration. That hair is not another frame.
        if elapsed >= exitDuration - 1e-6 { return 0 }
        return 1 - elapsed / exitDuration
    }
}

/// Contrast of the round mark against the black notch. The numbers are Zeus's own.
public enum PTTIndicatorContrast {
    public static let ring = (r: 0.93, g: 0.96, b: 1.0)
    public static let ground = (r: 0.02, g: 0.02, b: 0.03)

    public static func ratio(foreground: (r: Double, g: Double, b: Double), background: (r: Double, g: Double, b: Double)) -> Double {
        let lighter = max(luminance(foreground), luminance(background))
        let darker = min(luminance(foreground), luminance(background))
        return (lighter + 0.05) / (darker + 0.05)
    }

    public static var ringOnNotch: Double { ratio(foreground: ring, background: ground) }

    private static func channel(_ value: Double) -> Double {
        let v = min(1, max(0, value))
        if v <= 0.04045 { return v / 12.92 }
        let raised = (v + 0.055) / 1.055
        return exp(2.4 * log(raised))
    }

    private static func luminance(_ color: (r: Double, g: Double, b: Double)) -> Double {
        0.2126 * channel(color.r) + 0.7152 * channel(color.g) + 0.0722 * channel(color.b)
    }
}

/// The capture-failure sentences the notch already shows. Matching them is how a failure is observed.
public enum PTTIndicatorFailure {
    public static let microphoneKeptChanging = "The microphone kept changing, so Zeus stopped listening. Try again."
    public static let recordingTooLong = "That recording got too long, so Zeus stopped listening. Try again."

    public static func isPublished(_ text: String?) -> Bool {
        text == microphoneKeptChanging || text == recordingTooLong
    }
}

/// Pure push-to-talk indicator. It samples published flags and never installs a timer of its own.
public struct PTTIndicatorModel: Equatable, Sendable {
    public private(set) var state: PTTIndicatorState
    private var phaseStarted: TimeInterval
    private var releaseStarted: TimeInterval?
    /// True only after `Listening` was returned, until `Stopped listening` is returned.
    private var announcedListening: Bool

    public init() {
        state = .idle
        phaseStarted = 0
        releaseStarted = nil
        announcedListening = false
    }

    /// False once nothing is moving. Reduce Motion never needs a clock. Idle and error never do.
    public func needsClock(at now: TimeInterval, reduceMotion: Bool) -> Bool {
        if reduceMotion { return false }
        let now = now.isFinite ? now : phaseStarted
        switch state {
        case .idle, .error:
            return false
        case .armed, .listening:
            return now - phaseStarted < PTTIndicatorMotion.entryDuration
        case .releasing:
            return true
        }
    }

    /// One sample. The returned phrase is spoken once per transition, never on a level change.
    public mutating func advance(_ input: PTTIndicatorInput, now: TimeInterval, reduceMotion: Bool) -> String? {
        let now = now.isFinite ? now : 0
        if input.failed {
            return enterError()
        }
        if input.held, input.listening {
            return enterListening(level: input.level, now: now)
        }
        if input.held {
            return enterArmed(now: now)
        }
        return release(now: now, reduceMotion: reduceMotion)
    }

    public func frame(at now: TimeInterval, reduceMotion: Bool) -> PTTIndicatorFrame {
        let now = now.isFinite ? now : phaseStarted
        switch state {
        case .idle, .error:
            return base(opacity: 0, sweep: reduceMotion ? 1 : 0, scale: PTTIndicatorMotion.ringRest, label: "")
        case .armed:
            let progress = PTTIndicatorMotion.entryProgress(elapsed: max(0, now - phaseStarted), reduceMotion: reduceMotion)
            return base(opacity: progress, sweep: reduceMotion ? 1 : progress, scale: PTTIndicatorMotion.ringRest, label: "")
        case .listening(let level):
            let elapsed = max(0, now - phaseStarted)
            let progress = PTTIndicatorMotion.entryProgress(elapsed: elapsed, reduceMotion: reduceMotion)
            let sweep = reduceMotion ? 1 : min(1, max(0, elapsed / PTTIndicatorMotion.entryDuration))
            return base(opacity: progress, sweep: sweep, scale: PTTIndicatorMotion.ringScale(level: level), label: "Listening")
        case .releasing:
            let elapsed = max(0, now - (releaseStarted ?? phaseStarted))
            let opacity = PTTIndicatorMotion.exitOpacity(elapsed: elapsed, reduceMotion: reduceMotion)
            return base(opacity: opacity, sweep: reduceMotion ? 1 : opacity, scale: PTTIndicatorMotion.ringRest, label: "")
        }
    }

    private func base(opacity: Double, sweep: Double, scale: Double, label: String) -> PTTIndicatorFrame {
        PTTIndicatorFrame(
            barOpacity: opacity, barSweep: sweep, orbOpacity: opacity, ringScale: scale, pulse: 0,
            orbX: PTTIndicatorMotion.orbX, orbY: PTTIndicatorMotion.orbY,
            contrast: PTTIndicatorContrast.ringOnNotch, accessibilityLabel: label,
            opensWindow: false, surface: .existingNotchPanel)
    }

    private mutating func enterError() -> String? {
        let phrase = announcedListening ? stopPhrase() : nil
        state = .error
        releaseStarted = nil
        return phrase
    }

    private mutating func enterListening(level: Double, now: TimeInterval) -> String? {
        let clamped = PTTIndicatorMotion.clampLevel(level)
        let starting: Bool
        if case .listening = state {
            starting = false
        } else {
            starting = true
            phaseStarted = now
        }
        state = .listening(level: clamped)
        releaseStarted = nil
        guard starting else { return nil }
        announcedListening = true
        return "Listening"
    }

    private mutating func enterArmed(now: TimeInterval) -> String? {
        let phrase = announcedListening ? stopPhrase() : nil
        if state != .armed { phaseStarted = now }
        state = .armed
        releaseStarted = nil
        return phrase
    }

    private mutating func release(now: TimeInterval, reduceMotion: Bool) -> String? {
        switch state {
        case .idle:
            return nil
        case .error:
            state = .idle
            releaseStarted = nil
            announcedListening = false
            return nil
        case .releasing:
            let started = releaseStarted ?? now
            if reduceMotion || now - started >= PTTIndicatorMotion.exitDuration - 1e-6 {
                state = .idle
                releaseStarted = nil
            }
            return nil
        case .armed:
            if reduceMotion {
                state = .idle
                releaseStarted = nil
                return nil
            }
            state = .releasing
            phaseStarted = now
            releaseStarted = now
            return nil
        case .listening:
            let phrase = stopPhrase()
            if reduceMotion {
                state = .idle
                releaseStarted = nil
                return phrase
            }
            state = .releasing
            phaseStarted = now
            releaseStarted = now
            return phrase
        }
    }

    private mutating func stopPhrase() -> String? {
        guard announcedListening else { return nil }
        announcedListening = false
        return "Stopped listening"
    }
}
