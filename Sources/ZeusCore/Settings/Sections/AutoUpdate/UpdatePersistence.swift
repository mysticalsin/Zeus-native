import Foundation

/// Feed address and public key shipped with the build. Settings cannot replace them.
public struct UpdateBuildConfiguration: Equatable, Sendable {
    public var feedURL: String
    public var publicKey: String

    public init(feedURL: String, publicKey: String) {
        self.feedURL = feedURL
        self.publicKey = publicKey
    }

    public static func from(info: [String: String]) -> UpdateBuildConfiguration {
        UpdateBuildConfiguration(
            feedURL: info[UpdateConfiguration.bundledFeedInfoKey] ?? "",
            publicKey: info[UpdateConfiguration.publicKeyInfoKey] ?? ""
        )
    }
}

/// Non-secret update state. Automatic install is never on.
public struct UpdatePersistedState: Equatable, Sendable {
    public var automaticChecks: Bool
    public var automaticInstall: Bool
    public var lastChecked: Date?
    public var status: String
    public var notes: [String]

    public init(automaticChecks: Bool, automaticInstall: Bool, lastChecked: Date?, status: String, notes: [String]) {
        self.automaticChecks = automaticChecks
        self.automaticInstall = automaticInstall
        self.lastChecked = lastChecked
        self.status = status
        self.notes = notes
    }
}

/// The same `opt.` keys Settings already uses. A cold launch reads this store.
public enum UpdateSettingsStore {
    public static let automaticChecksID = "about.autoUpdate"
    public static let lastCheckedID = "about.lastChecked"
    public static let statusID = "about.updateStatus"
    public static let notesID = "about.updateNotes"
    public static let automaticInstallID = "about.autoInstall"

    public static func load(from defaults: UserDefaults) -> UpdatePersistedState {
        let notes = (defaults.string(forKey: key(notesID)) ?? "")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
        return UpdatePersistedState(
            automaticChecks: defaults.string(forKey: key(automaticChecksID)) == "true",
            automaticInstall: false,
            lastChecked: defaults.string(forKey: key(lastCheckedID)).flatMap(UpdateClock.date(from:)),
            status: defaults.string(forKey: key(statusID)) ?? "",
            notes: notes
        )
    }

    public static func save(_ state: UpdatePersistedState, to defaults: UserDefaults) {
        defaults.set(state.automaticChecks ? "true" : "false", forKey: key(automaticChecksID))
        defaults.set("false", forKey: key(automaticInstallID))
        if let lastChecked = state.lastChecked {
            defaults.set(UpdateClock.checkedLine(lastChecked), forKey: key(lastCheckedID))
        } else {
            defaults.removeObject(forKey: key(lastCheckedID))
        }
        defaults.set(state.status, forKey: key(statusID))
        defaults.set(state.notes.joined(separator: "\n"), forKey: key(notesID))
    }

    /// Settings stores catalog id `x.y` at `opt.x.y`.
    static func key(_ id: String) -> String { "opt." + id }
}

/// An imported settings file cannot turn install on, and cannot replace the build feed or key.
public enum UpdateImportPolicy {
    private static let feedAndKeyIDs: Set<String> = [
        "about.updateFeedURL", "SUFeedURL", "SUPublicEDKey",
        "about.publicKey", "about.updatePublicKey", "updates.publicKey", "updates.feedURL",
    ]

    public static func rejectsImportedKey(_ id: String) -> Bool {
        feedAndKeyIDs.contains(id)
    }

    public static func allowsImportedOption(id: String, value: String) -> Bool {
        if rejectsImportedKey(id) { return false }
        if id == UpdateSettingsStore.automaticChecksID && value == "true" { return false }
        if id == UpdateSettingsStore.automaticInstallID && value == "true" { return false }
        if id == "updates.automaticInstall" && value == "true" { return false }
        return true
    }

    public static func apply(_ data: Data, to defaults: UserDefaults, build: UpdateBuildConfiguration) -> Result<UpdatePersistedState, UpdateFailureReason> {
        _ = build
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["format"] as? String == "zeus.settings",
              root["version"] as? Int == 1 else { return .failure(.unreadable) }
        let options = root["options"] as? [String: Any] ?? [:]
        for (id, raw) in options {
            guard let value = raw as? String, allowsImportedOption(id: id, value: value) else { continue }
            if id == UpdateSettingsStore.automaticChecksID, value == "false" {
                defaults.set(value, forKey: UpdateSettingsStore.key(id))
            }
            if id == UpdateSettingsStore.lastCheckedID, UpdateClock.date(from: value) != nil {
                defaults.set(value, forKey: UpdateSettingsStore.key(id))
            }
        }
        return .success(UpdateSettingsStore.load(from: defaults))
    }
}

/// HTTPS only. A different host is accepted only when the appcast signature matches the build key.
public enum UpdateFeedTrust {
    public static func allows(proposed: URL, pinned: URL, appcastSignature: UpdateSignatureVerdict) -> Bool {
        guard UpdateFeedPolicy.isSecure(proposed), UpdateFeedPolicy.isSecure(pinned),
              let proposedHost = proposed.host?.lowercased(), let pinnedHost = pinned.host?.lowercased(),
              !proposedHost.isEmpty, !pinnedHost.isEmpty else { return false }
        if proposedHost == pinnedHost { return true }
        return appcastSignature == .valid
    }
}
