import Foundation

/// A file the owner picked. The bookmark and the path are references. The audio stays where it is.
public struct ChimeFileReference: Equatable, Sendable {
    public var path: String
    public var bookmark: Data?

    public init(path: String, bookmark: Data?) {
        self.path = path
        self.bookmark = bookmark
    }
}

/// The lock and wake chime settings, independent of the agent-cue volume.
public struct ChimeSettingsSnapshot: Equatable, Sendable {
    public static let defaultVolume = 0.7

    public var enabled: Bool
    public var volume: Double
    public var close: ChimeFileReference?
    public var open: ChimeFileReference?

    public init(enabled: Bool, volume: Double, close: ChimeFileReference?, open: ChimeFileReference?) {
        self.enabled = enabled
        self.volume = volume
        self.close = close
        self.open = open
    }

    public func file(for event: ChimeEvent) -> ChimeFileReference? {
        switch event {
        case .close: close
        case .open: open
        }
    }
}

/// Keys in the existing settings store (`opt.` plus the catalog id). Bookmarks are raw data beside the path.
public enum ChimeSettingsKey {
    public static let enabled = "chime.lockWake"
    public static let volume = "chime.lockWake.volume"
    public static let closePath = "chime.lockWake.closePath"
    public static let openPath = "chime.lockWake.openPath"

    public static func defaultsKey(_ id: String) -> String { "opt." + id }

    public static func pathID(_ event: ChimeEvent) -> String {
        switch event {
        case .close: closePath
        case .open: openPath
        }
    }

    public static func event(forPathID id: String) -> ChimeEvent? {
        switch id {
        case closePath: .close
        case openPath: .open
        default: nil
        }
    }

    public static func bookmarkDefaultsKey(_ event: ChimeEvent) -> String {
        "opt.chime.lockWake." + event.rawValue + "Bookmark"
    }
}

public enum ChimeSettingsPersistence {
    public static func load(defaults: UserDefaults) -> ChimeSettingsSnapshot {
        let enabled = defaults.string(forKey: ChimeSettingsKey.defaultsKey(ChimeSettingsKey.enabled)).map { $0 == "true" } ?? true
        return ChimeSettingsSnapshot(
            enabled: enabled,
            volume: volume(from: defaults.string(forKey: ChimeSettingsKey.defaultsKey(ChimeSettingsKey.volume))),
            close: file(.close, defaults),
            open: file(.open, defaults))
    }

    public static func save(_ snapshot: ChimeSettingsSnapshot, defaults: UserDefaults) {
        defaults.set(snapshot.enabled ? "true" : "false", forKey: ChimeSettingsKey.defaultsKey(ChimeSettingsKey.enabled))
        let percent = Int((snapshot.volume * 100).rounded())
        defaults.set(String(percent), forKey: ChimeSettingsKey.defaultsKey(ChimeSettingsKey.volume))
        write(snapshot.close, .close, defaults)
        write(snapshot.open, .open, defaults)
    }

    public static func saveBookmark(_ data: Data?, event: ChimeEvent, defaults: UserDefaults) {
        let key = ChimeSettingsKey.bookmarkDefaultsKey(event)
        if let data { defaults.set(data, forKey: key) } else { defaults.removeObject(forKey: key) }
    }

    public static func removeBookmark(_ event: ChimeEvent, defaults: UserDefaults) {
        defaults.removeObject(forKey: ChimeSettingsKey.bookmarkDefaultsKey(event))
    }

    public static func clearChosenFiles(defaults: UserDefaults) {
        for event in ChimeEvent.allCases {
            defaults.removeObject(forKey: ChimeSettingsKey.defaultsKey(ChimeSettingsKey.pathID(event)))
            removeBookmark(event, defaults: defaults)
        }
    }

    private static func write(_ file: ChimeFileReference?, _ event: ChimeEvent, _ defaults: UserDefaults) {
        let pathKey = ChimeSettingsKey.defaultsKey(ChimeSettingsKey.pathID(event))
        if let file {
            defaults.set(file.path, forKey: pathKey)
            saveBookmark(file.bookmark, event: event, defaults: defaults)
        } else {
            defaults.removeObject(forKey: pathKey)
            removeBookmark(event, defaults: defaults)
        }
    }

    private static func file(_ event: ChimeEvent, _ defaults: UserDefaults) -> ChimeFileReference? {
        let stored = defaults.string(forKey: ChimeSettingsKey.defaultsKey(ChimeSettingsKey.pathID(event))) ?? ""
        let path = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        return ChimeFileReference(path: path, bookmark: defaults.data(forKey: ChimeSettingsKey.bookmarkDefaultsKey(event)))
    }

    /// A stored percent (0 to 100). Missing or unreadable text keeps the default.
    private static func volume(from text: String?) -> Double {
        guard let text, let number = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)), number.isFinite else {
            return ChimeSettingsSnapshot.defaultVolume
        }
        return min(max(number / 100, 0), 1)
    }
}

/// An imported settings file never chooses a chime file. The toggle and the volume still apply.
/// The closure is accepted so older call sites compile; it is not used to accept a path.
public enum ChimeSettingsImport {
    /// The string a person stores from the file picker. Empty means the built-in chime.
    /// A path is stored only when it is a regular file, not a symlink, within the size cap, and short enough.
    /// The check opens the file. The sandbox is off, so the path itself is what gets measured.
    public static func storedPath(path: String, readable: Bool, seconds: Double = 0, maxBytes: Int = ChimeAudioLimits.maxFileBytes) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, readable else { return "" }
        guard seconds.isFinite, seconds > 0, seconds <= ChimeAudioLimits.maxSeconds else { return "" }
        guard case .success = ChimeFileAccess.measureRegularFile(at: trimmed, maxBytes: maxBytes) else { return "" }
        return trimmed
    }

    public static func applying(imported: ChimeSettingsSnapshot, canAccess _: (String) -> Bool) -> ChimeSettingsSnapshot {
        ChimeSettingsSnapshot(
            enabled: imported.enabled,
            volume: clamp(imported.volume),
            close: nil,
            open: nil)
    }

    private static func clamp(_ volume: Double) -> Double {
        guard volume.isFinite else { return ChimeSettingsSnapshot.defaultVolume }
        return min(max(volume, 0), 1)
    }
}

/// Chime file paths stay on this Mac. An export leaves them out.
public enum ChimeSettingsExport {
    public static func includes(id: String) -> Bool {
        ChimeSettingsKey.event(forPathID: id) == nil
    }
}

/// A stale security-scoped bookmark is replaced. A fresh one is left as stored.
public enum ChimeBookmark {
    public static func replacement(stale: Bool, refreshed: Data?) -> Data? {
        guard stale, let refreshed, !refreshed.isEmpty else { return nil }
        return refreshed
    }
}
