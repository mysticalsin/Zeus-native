import Foundation

/// Reads and writes Focus choices in the same place as the rest of Settings: `opt.<id>` strings.
public enum FocusSettingsPersistence {
    public static func storageKey(_ id: String) -> String { "opt." + id }

    public static func load(_ defaults: UserDefaults) -> FocusSectionSettings {
        var settings = FocusSectionSettings()
        settings.transitionOverlay = isOn(FocusSettingKey.transitionOverlay, defaults)
        settings.overlaysAllowed = isOn(FocusSettingKey.overlaysAllowed, defaults)
        settings.lockScreen = isOn(FocusSettingKey.lockScreen, defaults)
        settings.readName = isOn(FocusSettingKey.readName, defaults)
        settings.storeFile = isOn(FocusSettingKey.storeFile, defaults)
        settings.localNetwork = isOn(FocusSettingKey.localNetwork, defaults)
        settings.sharedLink = isOn(FocusSettingKey.sharedLink, defaults)
        if let home = defaults.string(forKey: storageKey(FocusSettingKey.homeWidget)), !home.isEmpty {
            settings.homeWidget = home
        }
        return settings
    }

    public static func isOn(_ id: String, _ defaults: UserDefaults) -> Bool {
        defaults.string(forKey: storageKey(id)) == "true"
    }

    public static func write(_ value: String, id: String, to defaults: UserDefaults) {
        defaults.set(value, forKey: storageKey(id))
    }

    /// Applies a `zeus.settings` file. A `true` for a sensitive Focus key is left out.
    public static func importFile(_ data: Data, into defaults: UserDefaults) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["format"] as? String == "zeus.settings",
              (root["version"] as? Int) == 1 || (root["version"] as? NSNumber)?.intValue == 1,
              let options = root["options"] as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let contributions = Dictionary(uniqueKeysWithValues: FocusSectionSlot.keyContributions.map { ($0.id, $0) })
        for (id, raw) in options {
            guard let value = raw as? String else { continue }
            if let item = contributions[id] {
                let current = defaults.string(forKey: storageKey(id)) ?? item.defaultValue
                guard let applied = SettingsKeyLedger.imported(item, current: current, incoming: value) else { continue }
                write(applied, id: id, to: defaults)
                continue
            }
            if id == FocusSettingKey.homeWidget {
                write(value, id: id, to: defaults)
            }
        }
    }
}
