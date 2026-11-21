import Foundation

/// Which `zeus` commands need "Allow command-line control", and who may use them once it is on.
public enum CLIGate {
    /// Debug hooks that capture, inject input, change privacy settings, write files, import keys, read folders
    /// on the caller's behalf (`second-brain-lookup` searches any folder named with `--vault`, and Zeus may hold
    /// access to folders the caller lacks), change the owner's learned shortcuts (`learn`), or open and render
    /// Zeus's own panels (Calendar, Reminders and clipboard content included).
    static let sensitiveDebug: Set<String> = [
        "dictate-file", "wake-file", "record", "hands", "hands-live", "selection", "on-device-speech",
        "import-assistant-key", "engine-logos", "second-brain-lookup", "learn",
        "screenshot", "tab", "open-settings", "onboarding", "animate", "presence", "hud-state",
    ]
    /// The subset that starts capturing audio or screen content.
    static let capturingDebug: Set<String> = ["dictate-file", "wake-file", "record", "on-device-speech"]

    public static func isSensitive(op: ZeusCommand.Op, debugSubcommand: String, argument: String) -> Bool {
        switch op {
        case .listen, .browse, .code, .term, .ask, .research: return true
        case .debug:
            if debugSubcommand == "screen-share" { return argument.lowercased() != "state" }
            return sensitiveDebug.contains(debugSubcommand)
        default: return false
        }
    }

    public static func startsCapture(op: ZeusCommand.Op, debugSubcommand: String) -> Bool {
        op == .listen || (op == .debug && capturingDebug.contains(debugSubcommand))
    }

    public enum Verdict: Equatable, Sendable {
        case allowed
        /// "Allow command-line control" is off.
        case gateOff
        /// The switch is on, but the request did not come from this app's own `zeus` command.
        case peerRejected(String)
    }

    /// The switch and the peer rule must both pass. The peer closure runs only when the switch is on,
    /// so a Mac that never turned the switch on never reads a signature. A peer that was not identified
    /// at all (nil) is refused.
    ///
    /// The peer rule only blocks clients that talk to the socket directly with their own program. It checks which
    /// binary connected, not who started it, so it does not stop a program of the same user from running the
    /// signed `zeus` command with its own arguments once the switch is on.
    public static func verdict(gateEnabled: Bool, peer: () -> PeerVerdict?) -> Verdict {
        guard gateEnabled else { return .gateOff }
        switch peer() {
        case .allow?: return .allowed
        case .deny(let reason)?: return .peerRejected(reason)
        case nil: return .peerRejected("peer not verified")
        }
    }
}

/// Where the switch is kept. Any program of this user can write a UserDefaults value, so the switch lives in
/// the Keychain, where only the Settings toggle writes it and a plain preferences write cannot turn it on.
/// How well the Keychain protects it depends on the build: a signed release keeps it behind the Keychain's
/// access rules for this app, while a development build keeps its items in a local keychain whose password
/// is a file the user can read, so there the switch is a guard against mistakes and preference edits, not
/// against a program that sets out to unlock that keychain. The item is "on" when it exists with value 1.
///
/// Open assumption, not yet probed: nothing here checks who wrote the item. Another program of this user may be
/// able to add one with an access list open to all programs (`security add-generic-password -A`), and whether Zeus
/// then reads it silently depends on the item's partition list, which is the Keychain's behaviour and not something
/// this code proves. The saved origins of the model key and of the license server (`CredentialOrigin`) rest on the
/// same assumption. The data protection keychain with a keychain access group would remove it, but it needs the
/// keychain-access-groups entitlement and a provisioning profile. Until someone plants such an item by hand on a
/// Developer ID build and reads it from Zeus, treat a same-user program that can write the login keychain as able
/// to turn the switch on.
public enum CLIGateStore {
    /// The Keychain account (under the app service) that holds the switch. Present means on.
    public static let account = "cli.control.enabled"
    /// The old UserDefaults key. Never read as a switch again.
    public static let legacyDefaultsKey = "cli.sensitiveCommands.enabled"
    static let migratedKey = "cli.control.migrated.v1"
    static let noticeKey = "cli.control.reenableNotice"

    public static func isEnabled(_ keychain: KeychainStore) -> Bool { keychain.get(account) == "1" }

    /// Turns the switch on or off. False when the Keychain refused, in which case nothing changed.
    @discardableResult
    public static func setEnabled(_ on: Bool, keychain: KeychainStore) -> Bool {
        on ? keychain.set("1", for: account) : keychain.remove(account)
    }

    /// Runs once. An old `true` does not carry over: the owner turns it on again, and a notice says so
    /// until it is dismissed. The writable copy is removed either way.
    public static func migrateLegacy(defaults: UserDefaults) {
        guard !defaults.bool(forKey: migratedKey) else { return }
        if defaults.bool(forKey: legacyDefaultsKey) { defaults.set(true, forKey: noticeKey) }
        defaults.removeObject(forKey: legacyDefaultsKey)
        defaults.set(true, forKey: migratedKey)
    }

    public static func noticePending(defaults: UserDefaults) -> Bool { defaults.bool(forKey: noticeKey) }

    public static func dismissNotice(defaults: UserDefaults) { defaults.removeObject(forKey: noticeKey) }
}

/// A command-line turn with the privacy switch off stays on this Mac.
public enum RestrictedTurn {
    public static func mayUseProvider(restricted: Bool) -> Bool { !restricted }

    public static func memory(_ block: String, restricted: Bool) -> String { restricted ? "" : block }

    public static func history<T>(_ turns: [T], restricted: Bool) -> [T] { restricted ? [] : turns }
}
