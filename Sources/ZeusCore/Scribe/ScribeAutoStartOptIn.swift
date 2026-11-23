import Foundation

// What must hold before "Start automatically" may count down, and the stamp that records the owner's own click.
// Pure: the app reads the microphone answer and the saved meetings, and passes them in.

/// The stamp the owner's click on "Start automatically" leaves behind, and the first recording on this Mac.
/// Both are timestamps in `UserDefaults`. Neither is a catalog option, so neither is ever exported or imported.
public enum ScribeAutoStartOptIn {
    public static let key = "scribe.autoStart.optInAt"
    /// The old consent card's stamp. Read once at launch, then removed.
    public static let legacyKey = "scribe.autoStart.consentAt"
    public static let firstRecordingKey = "scribe.firstRecordingAt"

    /// Run once at launch, before anything reads the stamp. An old consent carries over only while "Start
    /// automatically" is the current choice; the old key is always removed. A Mac that already holds a saved
    /// meeting has recorded before. A stamp left under any other choice is removed.
    public static func migrate(mode: ScribeAutoStartMode, hasSavedMeetings: Bool, defaults: UserDefaults = .standard) {
        if let legacy = defaults.object(forKey: legacyKey) {
            if mode == .automatic, let stamp = legacy as? Double, defaults.object(forKey: key) == nil {
                defaults.set(stamp, forKey: key)
            }
            discard(legacyKey, from: defaults)
        }
        if hasSavedMeetings, defaults.object(forKey: firstRecordingKey) == nil {
            defaults.set(Date().timeIntervalSince1970, forKey: firstRecordingKey)
        }
        reconcile(mode: mode, defaults: defaults)
    }

    /// The choice was made: "Start automatically" writes the stamp, any other choice removes it.
    public static func record(mode: ScribeAutoStartMode, now: Date = Date(), defaults: UserDefaults = .standard) {
        if mode == .automatic {
            defaults.set(now.timeIntervalSince1970, forKey: key)
        } else {
            discard(key, from: defaults)
        }
    }

    /// A stamp found while the choice is not "Start automatically" is stale: remove it.
    public static func reconcile(mode: ScribeAutoStartMode, defaults: UserDefaults = .standard) {
        if mode != .automatic { discard(key, from: defaults) }
    }

    /// Removes a stamp and flushes the suite. A CFPreferences write in another suite can put the
    /// removed value back before the next read unless this suite is synchronized afterwards.
    /// A later opt-in time that lands during that flush is a new choice and stays.
    private static func discard(_ key: String, from defaults: UserDefaults) {
        let removed = defaults.object(forKey: key) as? Double
        defaults.removeObject(forKey: key)
        _ = defaults.synchronize()
        guard defaults.object(forKey: key) != nil else { return }
        // A greater opt-in time is a newer choice and stays. The time just removed, an older one,
        // or anything that is not an opt-in time, is removed again.
        if key == Self.key, let stamp = defaults.object(forKey: key) as? Double,
           stamp > (removed ?? -Double.greatestFiniteMagnitude) {
            return
        }
        defaults.removeObject(forKey: key)
        _ = defaults.synchronize()
    }

    /// Written the first time a recording begins on this Mac, and never again.
    public static func noteRecordingBegan(now: Date = Date(), defaults: UserDefaults = .standard) {
        guard defaults.object(forKey: firstRecordingKey) == nil else { return }
        defaults.set(now.timeIntervalSince1970, forKey: firstRecordingKey)
    }

    public static func date(defaults: UserDefaults = .standard) -> Date? {
        (defaults.object(forKey: key) as? Double).map(Date.init(timeIntervalSince1970:))
    }

    public static func hasRecorded(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: firstRecordingKey) is Double
    }
}

/// What macOS says about the microphone for Zeus.
public enum ScribeMicrophoneAccess: Equatable, Sendable {
    case allowed
    case notAsked
    /// Denied or restricted: either way Zeus cannot ask again.
    case denied

    /// From `AVAuthorizationStatus.rawValue`: 0 not determined, 1 restricted, 2 denied, 3 authorized.
    public init(authorizationRaw: Int) {
        switch authorizationRaw {
        case 3: self = .allowed
        case 0: self = .notAsked
        default: self = .denied
        }
    }
}

/// Whether an automatic start may count down now, or the first thing missing.
public enum ScribeAutoStartReadiness: Equatable, Sendable {
    case ready
    case blocked(ScribeAutoStartBlock)

    public var isReady: Bool { self == .ready }

    public var block: ScribeAutoStartBlock? {
        if case .blocked(let block) = self { return block }
        return nil
    }

    /// Checks in the order the Settings row would show them to the owner.
    public static func resolve(mode: ScribeAutoStartMode, optIn: Bool, microphone: ScribeMicrophoneAccess,
                               hasRecorded: Bool) -> ScribeAutoStartReadiness {
        guard mode == .automatic else { return .blocked(.notChosen) }
        guard optIn else { return .blocked(.noOptIn) }
        switch microphone {
        case .denied: return .blocked(.microphoneDenied)
        case .notAsked: return .blocked(.microphoneNotAsked)
        case .allowed: break
        }
        return hasRecorded ? .ready : .blocked(.firstRecordingOwed)
    }
}
