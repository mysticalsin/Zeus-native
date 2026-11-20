import Foundation

/// One settings row. Existing rows and glass slots share this shape.
public struct SettingsSectionDescriptor: Equatable, Sendable {
    public var id: String
    public var title: String
    public var order: Int
    public var accessibilityLabel: String
    public var placeholder: String?

    public init(id: String, title: String, order: Int, accessibilityLabel: String, placeholder: String?) {
        self.id = id
        self.title = title
        self.order = order
        self.accessibilityLabel = accessibilityLabel
        self.placeholder = placeholder
    }
}

/// Sidebar, search, and VoiceOver order. Existing rows stay first. Filled slots append in manifest order.
public enum SettingsSectionRegistry {
    public static func id(for rawValue: String) -> String { "settings.\(rawValue)" }

    /// Visible sidebar order. The hidden phone row is not part of this list.
    public static let existing: [SettingsSectionDescriptor] = [
        row(0, "general", "General"),
        row(1, "appearance", "Appearance"),
        row(2, "sounds", "Sounds"),
        row(3, "notifications", "Notifications"),
        row(4, "shortcuts", "Shortcuts"),
        row(5, "insomnia", "Insomnia"),
        row(6, "integrations", "Integrations"),
        row(7, "murmure", "Murmure"),
        row(8, "polyglot", "Polyglot"),
        row(9, "dictation", "Dictation"),
        row(10, "voice", "Voice"),
        row(11, "engine", "Engine"),
        row(12, "features", "Features"),
        row(13, "beamer", "Beamer"),
        row(14, "tiling", "Tiling"),
        row(15, "shelf", "Shelf"),
        row(16, "license", "License"),
        row(17, "permissions", "Permissions"),
        row(18, "privacy", "Privacy"),
        row(19, "diagnostics", "Diagnostics"),
        row(20, "about", "About"),
    ]

    public static func sections(slots: [GlassSectionSlot]) -> [SettingsSectionDescriptor] {
        let base = existing
        let extra = slots.filter(\.filled).enumerated().map { offset, slot in
            SettingsSectionDescriptor(
                id: slot.id,
                title: slot.title,
                order: base.count + offset,
                accessibilityLabel: slot.title,
                placeholder: slot.keys.isEmpty ? slot.title : nil
            )
        }
        return (base + extra).sorted { $0.order < $1.order }
    }

    public static var live: [SettingsSectionDescriptor] {
        sections(slots: GlassSectionManifest.slots)
    }

    /// Case-insensitive match on title, id, or accessibility label. Results stay in registry order.
    public static func search(_ query: String, in sections: [SettingsSectionDescriptor]) -> [SettingsSectionDescriptor] {
        let key = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return sections }
        let exact = sections.filter {
            $0.title.lowercased() == key || $0.id.lowercased() == key || $0.accessibilityLabel.lowercased() == key
        }
        if !exact.isEmpty { return exact }
        return sections.filter {
            $0.title.lowercased().contains(key) || $0.id.lowercased().contains(key) || $0.accessibilityLabel.lowercased().contains(key)
        }
    }

    public static func groupTitle(for sectionID: String) -> String? {
        switch sectionID {
        case id(for: "general"), id(for: "appearance"), id(for: "sounds"), id(for: "notifications"), id(for: "shortcuts"), id(for: "insomnia"):
            return "Settings"
        case id(for: "integrations"), id(for: "murmure"), id(for: "polyglot"), id(for: "dictation"), id(for: "voice"), id(for: "engine"), id(for: "features"), id(for: "beamer"), id(for: "tiling"), id(for: "shelf"):
            return "Your tools"
        case id(for: "license"), id(for: "permissions"), id(for: "privacy"), id(for: "diagnostics"), id(for: "about"):
            return "Zeus"
        default:
            return nil
        }
    }

    public static func heading(before current: SettingsSectionDescriptor, previous: SettingsSectionDescriptor?) -> String? {
        let group = groupTitle(for: current.id)
        let prior = previous.flatMap { groupTitle(for: $0.id) }
        guard let group, group != prior else { return nil }
        return group
    }

    private static func row(_ order: Int, _ raw: String, _ title: String) -> SettingsSectionDescriptor {
        SettingsSectionDescriptor(id: id(for: raw), title: title, order: order, accessibilityLabel: title, placeholder: nil)
    }
}
