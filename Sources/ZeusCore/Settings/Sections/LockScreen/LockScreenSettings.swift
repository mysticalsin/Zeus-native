import Foundation

/// New keys for this section. They are not in the existing settings list.
public enum LockScreenSettingKey {
    public static let playerCard = "lockScreen.playerCard"
    public static let lockSound = "lockScreen.lockSound"
    public static let unlockSound = "lockScreen.unlockSound"
    public static let soundLevel = "lockScreen.soundLevel"
    public static let all = [playerCard, lockSound, unlockSound, soundLevel]
}

/// Who wrote the stored values. An import and a missing store stay off.
public enum LockScreenOrigin: Equatable, Sendable {
    case owner
    case imported
    case absent
}

/// How loud a lock or unlock sound is. Off plays nothing.
public enum LockScreenSoundLevel: String, Equatable, Sendable, CaseIterable {
    case off = "Off"
    case quiet = "Quiet"
    case loud = "Loud"

    public var gain: Double {
        switch self {
        case .off: 0
        case .quiet: 0.35
        case .loud: 1
        }
    }

    public static func resolve(_ stored: String?) -> LockScreenSoundLevel {
        guard let stored, let level = LockScreenSoundLevel(rawValue: stored) else { return .off }
        return level
    }
}

/// A sound Zeus already ships, or silence. Unknown stored names are silence.
public struct LockScreenSoundOption: Equatable, Sendable, Hashable {
    public var title: String
    public var fileName: String?

    public static let off = LockScreenSoundOption(title: "Off", fileName: nil)

    public static let all: [LockScreenSoundOption] = [
        .off,
        LockScreenSoundOption(title: "Gentle", fileName: "success_gentle.m4a"),
        LockScreenSoundOption(title: "Listening", fileName: "listen_start.m4a"),
        LockScreenSoundOption(title: "Stopped listening", fileName: "listen_stop.m4a"),
        LockScreenSoundOption(title: "To-do", fileName: "todo_check.m4a"),
    ]

    public static func resolve(_ stored: String?) -> LockScreenSoundOption {
        guard let stored else { return .off }
        return all.first { $0.title == stored } ?? .off
    }
}

public enum LockScreenMoment: String, Equatable, Sendable {
    case lock
    case unlock
}

public struct LockScreenCue: Equatable, Sendable {
    public var fileName: String
    public var gain: Double
    public var moment: LockScreenMoment

    public init(fileName: String, gain: Double, moment: LockScreenMoment) {
        self.fileName = fileName
        self.gain = gain
        self.moment = moment
    }
}

/// The four lock-screen controls. The default value is off, and an import cannot turn them on.
public struct LockScreenSettings: Equatable, Sendable {
    public var playerCard: Bool
    public var lockSound: LockScreenSoundOption
    public var unlockSound: LockScreenSoundOption
    public var soundLevel: LockScreenSoundLevel

    public init(playerCard: Bool, lockSound: LockScreenSoundOption, unlockSound: LockScreenSoundOption, soundLevel: LockScreenSoundLevel) {
        self.playerCard = playerCard
        self.lockSound = lockSound
        self.unlockSound = unlockSound
        self.soundLevel = soundLevel
    }

    public static let off = LockScreenSettings(playerCard: false, lockSound: .off, unlockSound: .off, soundLevel: .off)

    public static func resolve(
        playerCard: Bool?,
        lockSound: String?,
        unlockSound: String?,
        soundLevel: String?,
        origin: LockScreenOrigin
    ) -> LockScreenSettings {
        guard origin == .owner else { return .off }
        return LockScreenSettings(
            playerCard: playerCard ?? false,
            lockSound: LockScreenSoundOption.resolve(lockSound),
            unlockSound: LockScreenSoundOption.resolve(unlockSound),
            soundLevel: LockScreenSoundLevel.resolve(soundLevel)
        )
    }
}

/// The value table behind the lock screen settings. A second store on the same table reads what the first saved.
public struct LockScreenSettingsStore: Equatable, Sendable {
    public static let contributions: [SettingsKeyContribution] = [
        SettingsKeyContribution(id: LockScreenSettingKey.playerCard, defaultValue: "false", kind: .toggle, policy: .importCannotEnable),
        SettingsKeyContribution(id: LockScreenSettingKey.lockSound, defaultValue: LockScreenSoundOption.off.title, kind: .choice, policy: .importCannotEnable),
        SettingsKeyContribution(id: LockScreenSettingKey.unlockSound, defaultValue: LockScreenSoundOption.off.title, kind: .choice, policy: .importCannotEnable),
        SettingsKeyContribution(id: LockScreenSettingKey.soundLevel, defaultValue: LockScreenSoundLevel.off.rawValue, kind: .choice, policy: .importCannotEnable),
    ]

    public private(set) var values: [String: String]

    public init(values: [String: String] = [:]) {
        self.values = values
    }

    public var settings: LockScreenSettings {
        func load(_ id: String) -> String {
            guard let item = Self.contributions.first(where: { $0.id == id }) else { return "" }
            return SettingsKeyLedger.load(item, stored: values[id])
        }
        let card = load(LockScreenSettingKey.playerCard)
        return LockScreenSettings.resolve(
            playerCard: card == "true",
            lockSound: load(LockScreenSettingKey.lockSound),
            unlockSound: load(LockScreenSettingKey.unlockSound),
            soundLevel: load(LockScreenSettingKey.soundLevel),
            origin: .owner
        )
    }

    public mutating func save(_ settings: LockScreenSettings) {
        let encoded = [
            LockScreenSettingKey.playerCard: settings.playerCard ? "true" : "false",
            LockScreenSettingKey.lockSound: settings.lockSound.title,
            LockScreenSettingKey.unlockSound: settings.unlockSound.title,
            LockScreenSettingKey.soundLevel: settings.soundLevel.rawValue,
        ]
        for item in Self.contributions {
            guard let value = encoded[item.id] else { continue }
            _ = SettingsKeyLedger.save(&values, item, value)
        }
    }

    /// An import may turn a control off. It cannot turn the card on, choose a sound, or raise the level.
    public static func importing(_ incoming: [String: String], into existing: [String: String] = [:]) -> [String: String] {
        var result = existing
        for item in contributions {
            guard let raw = incoming[item.id] else { continue }
            let current = SettingsKeyLedger.load(item, stored: result[item.id])
            if let applied = SettingsKeyLedger.imported(item, current: current, incoming: raw) {
                result[item.id] = applied
            }
        }
        return result
    }
}

public enum LockScreenSounds {
    /// A cue only when a lock or unlock finishes, the level is on, and the file is still there.
    public static func cue(
        settings: LockScreenSettings,
        from: LockObservation,
        to: LockObservation,
        fileExists: (String) -> Bool
    ) -> LockScreenCue? {
        let moment: LockScreenMoment?
        if to == .locked && (from == .locking || from == .unlocked) {
            moment = .lock
        } else if to == .unlocked && (from == .unlocking || from == .locked) {
            moment = .unlock
        } else {
            moment = nil
        }
        guard let moment, settings.soundLevel.gain > 0 else { return nil }
        let option = moment == .lock ? settings.lockSound : settings.unlockSound
        guard let fileName = option.fileName, fileExists(fileName) else { return nil }
        return LockScreenCue(fileName: fileName, gain: settings.soundLevel.gain, moment: moment)
    }
}
