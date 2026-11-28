import Foundation

/// Volume, built-in display brightness and keyboard backlight HUD kinds.
public enum SystemHUDKind: String, Equatable, Sendable, CaseIterable {
    case volume, brightness, keyboardBacklight
}

/// Pure math and gating for Glance-style level HUD (no AppKit).
public enum SystemHUDMath {
    public static let coalesceInterval: TimeInterval = SystemHUDBox.coalesceInterval
    public static let valueDeltaThreshold = SystemHUDBox.valueDeltaThreshold
    public static let holdAfterChange: TimeInterval = SystemHUDBox.holdAfterChange
    public static let easeOut: TimeInterval = SystemHUDBox.easeOut
    public static let segmentCount = SystemHUDBox.segmentCount

    public static func shouldReport(previous: Double, next: Double, threshold: Double = valueDeltaThreshold) -> Bool {
        SystemHUDBox.shouldReport(previous: previous, next: next, threshold: threshold)
    }

    public static func segmentIndex(for value: Double) -> Int {
        SystemHUDBox.segmentIndex(for: value)
    }

    public static func filledSegmentCount(for value: Double) -> Int {
        SystemHUDBox.filledSegmentCount(for: value)
    }

    /// Normal key step is 1/16; Shift+Option quarter step is 1/64.
    public static func stepDelta(fine: Bool) -> Double { SystemHUDBox.stepDelta(fine: fine) }

    public static func steppedValue(_ value: Double, direction: Int, fine: Bool) -> Double {
        SystemHUDBox.steppedValue(value, direction: direction, fine: fine)
    }

    public static func cueDuration(sinceLastChange: TimeInterval) -> TimeInterval {
        SystemHUDBox.cueDuration(sinceLastChange: sinceLastChange)
    }

    /// Merges timestamps closer than `coalesceInterval` into one emission at the last time.
    public static func coalesceTimes(_ times: [Date], window: TimeInterval = coalesceInterval) -> [Date] {
        SystemHUDBox.coalesceTimes(times, window: window)
    }
}

/// What a media key press should do, independent of AppKit/CGEvent (pure and unit-testable).
/// `.passThrough` means "don't consume this event" -- used for key codes this tap doesn't own
/// (H6: Caps Lock (4) and Help (5) must never be swallowed).
public enum SystemHUDKeyAction: Equatable, Sendable {
    case volumeUp(fine: Bool)
    case volumeDown(fine: Bool)
    case toggleMute
    case brightnessUp(fine: Bool)
    case brightnessDown(fine: Bool)
    case illuminationUp(fine: Bool)
    case illuminationDown(fine: Bool)
    case illuminationToggle
    case passThrough
}

/// Maps `NSEvent.data1`'s media key codes (the `NX_KEYTYPE_*` constants) to an action.
public enum SystemHUDKeys {
    public static func action(for key: Int, fine: Bool = false) -> SystemHUDKeyAction {
        switch key {
        case 0: .volumeUp(fine: fine) // NX_KEYTYPE_SOUND_UP
        case 1: .volumeDown(fine: fine) // NX_KEYTYPE_SOUND_DOWN
        case 7: .toggleMute // NX_KEYTYPE_MUTE (H4)
        case 2: .brightnessUp(fine: fine) // NX_KEYTYPE_BRIGHTNESS_UP (H5: up, was treated as down)
        case 3: .brightnessDown(fine: fine) // NX_KEYTYPE_BRIGHTNESS_DOWN
        case 21: .illuminationUp(fine: fine) // NX_KEYTYPE_ILLUMINATION_UP (H6: real code, not 4)
        case 22: .illuminationDown(fine: fine) // NX_KEYTYPE_ILLUMINATION_DOWN (H6: real code, not 5)
        case 23: .illuminationToggle // NX_KEYTYPE_ILLUMINATION_TOGGLE
        default: .passThrough // includes 4 (Caps Lock) and 5 (Help): never ours to eat
        }
    }
}

/// Settings keys for each HUD effect (`SettingsStore.bool` reads `opt.<id>`).
public enum SystemHUDSettings {
    public static func settingID(for kind: SystemHUDKind) -> String {
        switch kind {
        case .volume: "lights.hud.volume"
        case .brightness: "lights.hud.brightness"
        case .keyboardBacklight: "lights.hud.keyboard"
        }
    }

    public static func isEnabled(_ kind: SystemHUDKind, bool: (String) -> Bool) -> Bool {
        bool(settingID(for: kind))
    }

    public static let replaceSystemID = "lights.hud.replaceSystem"
    public static let muteEffectsID = "lights.hud.mute"
    /// The level-light rows speak which of the three are on. They do not change them.
    public static var speakLights: () -> Void = {}
    public static let legacyVolumeID = "lights.volume"
    public static let migrationKey = "opt.lights.hud.migrated"

    public static func replaceSystemEnabled(bool: (String) -> Bool) -> Bool { bool(replaceSystemID) }
    public static func muteEffectsEnabled(bool: (String) -> Bool) -> Bool { bool(muteEffectsID) }
}

/// One-shot migration from the old combined `lights.volume` toggle.
public enum SystemHUDMigration {
    public static func run(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: SystemHUDSettings.migrationKey) else { return }
        let legacyOff = defaults.string(forKey: "opt.\(SystemHUDSettings.legacyVolumeID)") == "false"
        if legacyOff {
            for id in SystemHUDKind.allCases.map(SystemHUDSettings.settingID(for:)) + [SystemHUDSettings.muteEffectsID] {
                defaults.set("false", forKey: "opt.\(id)")
            }
        }
        defaults.set("true", forKey: SystemHUDSettings.migrationKey)
    }
}

/// Drops duplicate samples inside one coalesce window; tests use `coalesceTimes` for burst timing.
public struct SystemHUDCoalescer: Sendable {
    public private(set) var lastValue: Double?
    public private(set) var lastMuted = false

    public init() {}

    /// True when the HUD should fire for this sample.
    public mutating func accept(value: Double, muted: Bool) -> Bool {
        defer { lastValue = value; lastMuted = muted }
        guard let lastValue else { return true }
        if muted != lastMuted { return true }
        return SystemHUDMath.shouldReport(previous: lastValue, next: value)
    }

    /// Pre-populates state with the current hardware reading, without reporting (H1). Call this
    /// once before the first real poll/event so that reading the current volume/brightness at
    /// launch never itself presents a HUD; `accept()`'s own "first sample always fires" behavior
    /// is unchanged for callers that never seed.
    public mutating func seed(value: Double, muted: Bool) {
        lastValue = value
        lastMuted = muted
    }
}

/// How often brightness and keyboard backlight are read. macOS posts no public notification for
/// either, so the read is a timer, but a slow one: it speeds up only for a short burst after a
/// known event (a media key, a volume change, a level that just moved) and does not run at all
/// when neither HUD is on or the displays are asleep.
public enum SystemHUDPollPolicy {
    public static let burstInterval: TimeInterval = SystemHUDBox.burstInterval
    public static let idleInterval: TimeInterval = SystemHUDBox.idleInterval
    public static let burstWindow: TimeInterval = SystemHUDBox.burstWindow

    public static func interval(sinceLastChange: TimeInterval) -> TimeInterval {
        SystemHUDBox.interval(sinceLastChange: sinceLastChange)
    }

    public static func shouldPoll(brightnessEnabled: Bool, keyboardBacklightEnabled: Bool, displaysAsleep: Bool) -> Bool {
        SystemHUDBox.shouldPoll(
            brightnessEnabled: brightnessEnabled,
            keyboardBacklightEnabled: keyboardBacklightEnabled,
            displaysAsleep: displaysAsleep
        )
    }
}
