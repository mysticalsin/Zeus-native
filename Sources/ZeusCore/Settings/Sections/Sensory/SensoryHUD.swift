import Foundation

/// Volume and brightness overlay for the Sensory section.
/// The three existing keys stay on their current ids. Hold and label are the two controls
/// the overlay was missing. Keyboard backlight, mute and the screen-edge glow are not part of this section.
public enum SensoryHUDPhase: String, Equatable, Sendable, CaseIterable {
    case hidden, showing, extending, fading
}

public enum SensoryHUDLabel: String, Equatable, Sendable, CaseIterable {
    case icon
    case words

    /// Blank and unknown values keep the symbol the overlay already draws.
    public static func parse(_ raw: String?) -> SensoryHUDLabel {
        switch raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "words": .words
        default: .icon
        }
    }
}

public enum SensoryHUDHold {
    public static let minimum = 0.4
    public static let maximum = 6.0
    public static let defaultHold = 1.2
    public static let step = 0.1

    /// A non-finite value keeps today's dwell. A finite value is pulled into 0.4...6.
    public static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return defaultHold }
        return min(maximum, max(minimum, value))
    }

    public static func parse(_ raw: String?) -> Double {
        let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty, let value = Double(text) else { return defaultHold }
        return clamp(value)
    }

    public static func store(_ value: Double) -> String {
        let scaled = (clamp(value) * 10_000).rounded() / 10_000
        var text = String(format: "%.4f", scaled)
        while text.contains(".") && (text.hasSuffix("0") || text.hasSuffix(".")) {
            text.removeLast()
        }
        return text
    }

    /// Snaps onto the 0.1 grid, then moves by one step. The result stays inside the bounds.
    public static func step(_ value: Double, direction: Int) -> Double {
        let tenths = Int((clamp(value) * 10).rounded(.toNearestOrAwayFromZero))
        let moved = tenths + direction
        let bounded = min(Int((maximum * 10).rounded()), max(Int((minimum * 10).rounded()), moved))
        return Double(bounded) / 10
    }
}

public enum SensoryHUDTiming {
    public static let fadeIn: TimeInterval = 0.12
    public static let fadeOut: TimeInterval = 0.25

    public static func fadeIn(reduceMotion: Bool) -> TimeInterval { reduceMotion ? 0 : fadeIn }
    public static func fadeOut(reduceMotion: Bool) -> TimeInterval { reduceMotion ? 0 : fadeOut }
}

public struct SensorySettings: Equatable, Sendable {
    public static let volumeKey = "lights.hud.volume"
    public static let brightnessKey = "lights.hud.brightness"
    public static let replaceSystemKey = "lights.hud.replaceSystem"
    public static let holdKey = "lights.hud.hold"
    public static let labelKey = "lights.hud.label"

    public var volume: Bool
    public var brightness: Bool
    public var replaceSystem: Bool
    public var hold: TimeInterval
    public var label: SensoryHUDLabel

    public init(
        volume: Bool = true,
        brightness: Bool = true,
        replaceSystem: Bool = true,
        hold: TimeInterval = SensoryHUDHold.defaultHold,
        label: SensoryHUDLabel = .icon
    ) {
        self.volume = volume
        self.brightness = brightness
        self.replaceSystem = replaceSystem
        self.hold = SensoryHUDHold.clamp(hold)
        self.label = label
    }

    /// `nil` and blank mean the catalog default. Any other token that is not "true" is off.
    public static func read(_ raw: (String) -> String?) -> SensorySettings {
        func flag(_ key: String, default defaultValue: Bool) -> Bool {
            switch raw(key)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case nil, "": defaultValue
            case "true": true
            default: false
            }
        }
        return SensorySettings(
            volume: flag(volumeKey, default: true),
            brightness: flag(brightnessKey, default: true),
            replaceSystem: flag(replaceSystemKey, default: true),
            hold: SensoryHUDHold.parse(raw(holdKey)),
            label: SensoryHUDLabel.parse(raw(labelKey))
        )
    }

    public func write(_ store: (String, String) -> Void) {
        store(Self.volumeKey, volume ? "true" : "false")
        store(Self.brightnessKey, brightness ? "true" : "false")
        store(Self.replaceSystemKey, replaceSystem ? "true" : "false")
        store(Self.holdKey, SensoryHUDHold.store(hold))
        store(Self.labelKey, label.rawValue)
    }
}

public enum SensoryReplace: Equatable, Sendable {
    case leaveSystemOverlay
    case replaceSystemOverlay
    /// The switch is on, but Accessibility is not trusted. The system overlay is not consumed.
    case blockedUntilTrusted

    public static func decision(enabled: Bool, accessibilityTrusted: Bool) -> SensoryReplace {
        guard enabled else { return .leaveSystemOverlay }
        return accessibilityTrusted ? .replaceSystemOverlay : .blockedUntilTrusted
    }
}

public struct SensoryHUDSnapshot: Equatable, Sendable {
    public var phase: SensoryHUDPhase
    public var kind: SystemHUDKind?
    public var level: Double
    public var muted: Bool
    public var anchor: Date?
    public var fadeAnchor: Date?

    public init(phase: SensoryHUDPhase, kind: SystemHUDKind?, level: Double, muted: Bool, anchor: Date?, fadeAnchor: Date?) {
        self.phase = phase
        self.kind = kind
        self.level = level
        self.muted = muted
        self.anchor = anchor
        self.fadeAnchor = fadeAnchor
    }

    public static let hidden = SensoryHUDSnapshot(phase: .hidden, kind: nil, level: 0, muted: false, anchor: nil, fadeAnchor: nil)
}

public enum SensoryHUDEvent: Equatable, Sendable {
    case changed(SystemHUDKind, level: Double, muted: Bool, at: Date)
    case tick(Date)
    case dismiss
    case configurationChanged(Date)
}

public struct SensoryHUDConfig: Equatable, Sendable {
    public var settings: SensorySettings
    public var reduceMotion: Bool

    public init(settings: SensorySettings, reduceMotion: Bool) {
        self.settings = settings
        self.reduceMotion = reduceMotion
    }
}

public enum SensoryHUDEffect: Equatable, Sendable {
    case announce(String)
    case wake(Date)
}

public enum SensoryHUDLifecycle {
    public static func accepts(_ kind: SystemHUDKind, _ settings: SensorySettings) -> Bool {
        switch kind {
        case .volume: settings.volume
        case .brightness: settings.brightness
        case .keyboardBacklight: false
        }
    }

    /// A sample the preview can play. Nil when both overlays are off.
    public static func sampleChange(settings: SensorySettings, at: Date) -> SensoryHUDEvent? {
        if settings.volume { return .changed(.volume, level: 0.6, muted: false, at: at) }
        if settings.brightness { return .changed(.brightness, level: 0.6, muted: false, at: at) }
        return nil
    }

    public static func reduce(
        _ state: SensoryHUDSnapshot,
        _ event: SensoryHUDEvent,
        config: SensoryHUDConfig
    ) -> (SensoryHUDSnapshot, [SensoryHUDEffect]) {
        switch event {
        case .dismiss:
            return state.phase == .hidden ? (state, []) : (.hidden, [])
        case .tick(let now):
            return advance(state, now: now, config: config, reschedule: false)
        case .configurationChanged(let now):
            guard state.phase != .hidden else { return (state, []) }
            guard let kind = state.kind, accepts(kind, config.settings) else { return (.hidden, []) }
            return advance(state, now: now, config: config, reschedule: true)
        case .changed(let kind, let level, let muted, let at):
            guard accepts(kind, config.settings) else {
                if state.phase != .hidden, state.kind == kind { return (.hidden, []) }
                return (state, [])
            }
            let clamped = finiteLevel(level)
            let phase: SensoryHUDPhase = state.phase == .hidden ? .showing : .extending
            let next = SensoryHUDSnapshot(phase: phase, kind: kind, level: clamped, muted: muted, anchor: at, fadeAnchor: nil)
            let spoken = SensoryHUDCaptioning.caption(
                kind: kind, level: clamped, muted: muted, style: config.settings.label
            ).accessibilityLabel
            guard let deadline = nextBoundary(next, config: config) else { return (next, [.announce(spoken)]) }
            return (next, [.announce(spoken), .wake(deadline)])
        }
    }

    public static func opacity(_ state: SensoryHUDSnapshot, at now: Date, config: SensoryHUDConfig) -> Double {
        switch state.phase {
        case .hidden:
            return 0
        case .extending:
            return 1
        case .showing:
            let fade = SensoryHUDTiming.fadeIn(reduceMotion: config.reduceMotion)
            if fade == 0 { return 1 }
            guard let anchor = state.anchor else { return 1 }
            let elapsed = max(0, now.timeIntervalSince(anchor))
            return min(1, elapsed / fade)
        case .fading:
            let fade = SensoryHUDTiming.fadeOut(reduceMotion: config.reduceMotion)
            if fade == 0 { return 0 }
            guard let anchor = state.fadeAnchor else { return 0 }
            let elapsed = max(0, now.timeIntervalSince(anchor))
            return max(0, min(1, 1 - elapsed / fade))
        }
    }

    /// Seconds from `now` until a tick would report `hidden`.
    /// Measured from the anchor so a hold of 1.2 is 1.2, not a date round-trip.
    public static func timeUntilHidden(_ state: SensoryHUDSnapshot, now: Date, config: SensoryHUDConfig) -> TimeInterval {
        let hold = SensoryHUDHold.clamp(config.settings.hold)
        let fadeOut = SensoryHUDTiming.fadeOut(reduceMotion: config.reduceMotion)
        switch state.phase {
        case .hidden:
            return 0
        case .showing:
            guard let anchor = state.anchor else { return 0 }
            let total = SensoryHUDTiming.fadeIn(reduceMotion: config.reduceMotion) + hold + fadeOut
            return max(0, total - now.timeIntervalSince(anchor))
        case .extending:
            guard let anchor = state.anchor else { return 0 }
            return max(0, hold + fadeOut - now.timeIntervalSince(anchor))
        case .fading:
            guard let fadeAnchor = state.fadeAnchor else { return 0 }
            return max(0, fadeOut - now.timeIntervalSince(fadeAnchor))
        }
    }

    private static func advance(
        _ state: SensoryHUDSnapshot,
        now: Date,
        config: SensoryHUDConfig,
        reschedule: Bool
    ) -> (SensoryHUDSnapshot, [SensoryHUDEffect]) {
        switch state.phase {
        case .hidden:
            return (state, [])
        case .showing, .extending:
            guard let boundary = nextBoundary(state, config: config) else { return (.hidden, []) }
            if now < boundary {
                return reschedule ? (state, [.wake(boundary)]) : (state, [])
            }
            let fade = SensoryHUDTiming.fadeOut(reduceMotion: config.reduceMotion)
            let fadeEnd = boundary.addingTimeInterval(fade)
            if fade == 0 || now >= fadeEnd { return (.hidden, []) }
            let fading = SensoryHUDSnapshot(
                phase: .fading, kind: state.kind, level: state.level, muted: state.muted,
                anchor: state.anchor, fadeAnchor: boundary
            )
            return (fading, [.wake(fadeEnd)])
        case .fading:
            guard let end = nextBoundary(state, config: config) else { return (.hidden, []) }
            if now < end { return reschedule ? (state, [.wake(end)]) : (state, []) }
            return (.hidden, [])
        }
    }

    /// The next clock boundary: fade-in plus hold while showing, hold while extending, fade-out while fading.
    private static func nextBoundary(_ state: SensoryHUDSnapshot, config: SensoryHUDConfig) -> Date? {
        let hold = SensoryHUDHold.clamp(config.settings.hold)
        switch state.phase {
        case .hidden:
            return nil
        case .showing:
            guard let anchor = state.anchor else { return nil }
            return anchor.addingTimeInterval(SensoryHUDTiming.fadeIn(reduceMotion: config.reduceMotion) + hold)
        case .extending:
            guard let anchor = state.anchor else { return nil }
            return anchor.addingTimeInterval(hold)
        case .fading:
            guard let fadeAnchor = state.fadeAnchor else { return nil }
            return fadeAnchor.addingTimeInterval(SensoryHUDTiming.fadeOut(reduceMotion: config.reduceMotion))
        }
    }

    private static func finiteLevel(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(1, max(0, value))
    }
}

public struct SensoryHUDCaption: Equatable, Sendable {
    public var symbol: String?
    public var words: String?
    public var accessibilityLabel: String

    public init(symbol: String?, words: String?, accessibilityLabel: String) {
        self.symbol = symbol
        self.words = words
        self.accessibilityLabel = accessibilityLabel
    }
}

public enum SensoryHUDCaptioning {
    public static func caption(kind: SystemHUDKind, level: Double, muted: Bool, style: SensoryHUDLabel) -> SensoryHUDCaption {
        let clamped = level.isFinite ? min(1, max(0, level)) : 0
        switch kind {
        case .keyboardBacklight:
            return SensoryHUDCaption(symbol: nil, words: nil, accessibilityLabel: "")
        case .volume:
            let percent = percent(clamped)
            let spoken = muted ? "Muted" : "Volume \(percent) percent"
            let symbol = muted || clamped == 0
                ? "speaker.slash.fill"
                : clamped < 0.34 ? "speaker.wave.1.fill" : clamped < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
            if style == .icon {
                return SensoryHUDCaption(symbol: symbol, words: nil, accessibilityLabel: spoken)
            }
            let words = muted ? "Muted" : "Volume \(percent)%"
            return SensoryHUDCaption(symbol: nil, words: words, accessibilityLabel: spoken)
        case .brightness:
            let percent = percent(clamped)
            let spoken = "Brightness \(percent) percent"
            if style == .icon {
                let symbol = clamped < 0.5 ? "sun.min.fill" : "sun.max.fill"
                return SensoryHUDCaption(symbol: symbol, words: nil, accessibilityLabel: spoken)
            }
            return SensoryHUDCaption(symbol: nil, words: "Brightness \(percent)%", accessibilityLabel: spoken)
        }
    }

    private static func percent(_ level: Double) -> Int {
        Int((level * 100).rounded(.toNearestOrAwayFromZero))
    }
}

public struct SensoryControl: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var helper: String
    public var accessibilityLabel: String
    public var accessibilityValue: String
    public var keyboardReachable: Bool

    public init(id: String, title: String, helper: String, accessibilityLabel: String, accessibilityValue: String, keyboardReachable: Bool) {
        self.id = id
        self.title = title
        self.helper = helper
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityValue = accessibilityValue
        self.keyboardReachable = keyboardReachable
    }
}

public enum SensoryControls {
    public static let previewID = "sensory.preview"

    public static func rows(_ settings: SensorySettings, trusted: Bool) -> [SensoryControl] {
        let replace = SensoryReplace.decision(enabled: settings.replaceSystem, accessibilityTrusted: trusted)
        let replaceHelper: String
        let replaceValue: String
        switch replace {
        case .leaveSystemOverlay:
            replaceHelper = "Leaves the system overlay alone. Turning this on needs Accessibility permission."
            replaceValue = "Off"
        case .replaceSystemOverlay:
            replaceHelper = "Hides the system overlay while this one is showing. This needs Accessibility permission."
            replaceValue = "On"
        case .blockedUntilTrusted:
            replaceHelper = "Accessibility is off, so the system overlay stays up. Turn Accessibility on in Permissions. Both overlays can show until then."
            replaceValue = "Accessibility is off"
        }
        let holdText = SensoryHUDHold.store(settings.hold)
        return [
            row(SensorySettings.volumeKey, "Volume overlay", "Shows the overlay when the output volume changes.", settings.volume ? "On" : "Off"),
            row(SensorySettings.brightnessKey, "Brightness overlay", "Shows the overlay when the built-in display brightness changes.", settings.brightness ? "On" : "Off"),
            row(SensorySettings.replaceSystemKey, "Replace the system overlay", replaceHelper, replaceValue),
            row(SensorySettings.holdKey, "How long it stays", "How long the overlay stays fully visible, from 0.4 to 6 seconds.", "\(holdText) seconds"),
            row(SensorySettings.labelKey, "Label", "Show a symbol, or the level in words.", settings.label == .words ? "Words" : "Icon"),
            row(previewID, "Preview", "Plays a sample overlay with the choices above.", "Play sample"),
        ]
    }

    private static func row(_ id: String, _ title: String, _ helper: String, _ value: String) -> SensoryControl {
        SensoryControl(id: id, title: title, helper: helper, accessibilityLabel: title, accessibilityValue: value, keyboardReachable: true)
    }
}

public enum SensoryLayout {
    public static let rowHeight = 52.0
    public static let panelPadding = 32.0
    public static let cardSpacing = 28.0

    public static func animationDuration(reduceMotion: Bool) -> Double {
        reduceMotion ? 0 : 0.22
    }
}

public enum SensoryPreviewStatus: Equatable, Sendable {
    case loading
    case empty
    case live
}

public struct SensoryPreviewFrame: Equatable, Sendable {
    public var status: SensoryPreviewStatus
    public var title: String
    public var detail: String
    public var symbol: String?
    public var words: String?
    public var opacity: Double
    public var hudPhase: SensoryHUDPhase?
    public var error: String?

    public init(status: SensoryPreviewStatus, title: String, detail: String, symbol: String?, words: String?, opacity: Double, hudPhase: SensoryHUDPhase?, error: String?) {
        self.status = status
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.words = words
        self.opacity = opacity
        self.hudPhase = hudPhase
        self.error = error
    }
}

public enum SensoryPreview {
    public static func frame(
        settings: SensorySettings,
        trusted: Bool,
        reading: Bool,
        snapshot: SensoryHUDSnapshot,
        now: Date,
        reduceMotion: Bool
    ) -> SensoryPreviewFrame {
        let blocked = SensoryReplace.decision(enabled: settings.replaceSystem, accessibilityTrusted: trusted) == .blockedUntilTrusted
        let error = blocked
            ? "Accessibility is off, so the system overlay stays up. Turn Accessibility on in Permissions."
            : nil
        if !settings.volume && !settings.brightness {
            return SensoryPreviewFrame(
                status: .empty, title: "Nothing to show",
                detail: "Turn on volume or brightness to see the overlay.",
                symbol: nil, words: nil, opacity: 0, hudPhase: nil, error: error
            )
        }
        if reading {
            return SensoryPreviewFrame(
                status: .loading, title: "Reading the current level",
                detail: "The overlay appears when a level is ready.",
                symbol: nil, words: nil, opacity: 0, hudPhase: nil, error: error
            )
        }
        let config = SensoryHUDConfig(settings: settings, reduceMotion: reduceMotion)
        let caption: SensoryHUDCaption
        if let kind = snapshot.kind, snapshot.phase != .hidden {
            caption = SensoryHUDCaptioning.caption(kind: kind, level: snapshot.level, muted: snapshot.muted, style: settings.label)
        } else {
            caption = SensoryHUDCaption(symbol: nil, words: nil, accessibilityLabel: "Hidden")
        }
        let title = snapshot.phase == .hidden ? "Hidden" : snapshot.phase.rawValue.prefix(1).uppercased() + snapshot.phase.rawValue.dropFirst()
        return SensoryPreviewFrame(
            status: .live, title: title, detail: caption.accessibilityLabel,
            symbol: caption.symbol, words: caption.words,
            opacity: SensoryHUDLifecycle.opacity(snapshot, at: now, config: config),
            hudPhase: snapshot.phase, error: error
        )
    }
}
