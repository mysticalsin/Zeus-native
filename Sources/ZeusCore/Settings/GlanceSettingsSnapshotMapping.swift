import Foundation

/// Maps legacy Settings window section ids (used in numbered `--snapshots` PNG names) to live Glance
/// Settings section ids. QA grades `settings-02-appearance.png` and similar against the Glance window.
public enum GlanceSettingsSnapshotMapping {
    /// Live Glance section id for a legacy sidebar section name, or nil when no Glance page exists.
    public static func glanceSectionID(forLegacySection legacy: String) -> String? {
        resolveSectionID(legacy)
    }

    /// Case-insensitive match on GSSection raw ids, titles, and legacy aliases (R24 debug open-settings).
    public static func resolveSectionID(_ name: String) -> String? {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return nil }
        let live: Set<String> = [
            "general", "appearance", "sounds", "notifications", "shortcuts", "insomnia",
            "integrations", "murmure", "polyglot", "dictation", "voice", "engine", "iphone",
            "features", "beamer", "license", "permissions", "privacy", "diagnostics", "about",
        ]
        if live.contains(key) { return key == "iphone" ? "iPhone" : key }
        switch key {
        case "topbar", "top bar", "notch", "halo":
            return "appearance"
        case "todo", "to-do", "tasks", "zeus to-do", "zeus todo":
            return "features"
        case "memory", "about you":
            return "features"
        case "teleprompter", "prompter":
            return "beamer"
        case "agents", "ai", "connections":
            return "integrations"
        case "murmur", "murmure dictation":
            return "murmure"
        case "stickies", "routines", "keepawake", "assistant", "intelligence", "interview":
            return "features"
        default:
            return titleMatch(key)
        }
    }

    private static func titleMatch(_ key: String) -> String? {
        let titles: [(String, String)] = [
            ("general", "general"), ("appearance", "appearance"), ("sounds", "sounds"),
            ("notifications", "notifications"), ("shortcuts", "shortcuts"), ("insomnia", "insomnia"),
            ("integrations", "integrations"), ("murmure", "murmure"), ("polyglot", "polyglot"),
            ("dictation", "dictation"), ("voice", "voice"), ("engine", "engine"),
            ("features", "features"), ("beamer", "beamer"), ("license", "license"),
            ("permissions", "permissions"), ("privacy", "privacy"), ("diagnostics", "diagnostics"),
            ("about", "about"),
        ]
        return titles.first { $0.0 == key }?.1
    }
}
