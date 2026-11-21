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

/// Sidebar, search, and VoiceOver order. Existing rows stay first. Filled slots append in file order.
public enum SettingsSectionRegistry {
    public static func id(for rawValue: String) -> String { "settings.\(rawValue)" }

    /// Visible sidebar order while the phone row is hidden.
    public static var existing: [SettingsSectionDescriptor] { existing(includePhone: false) }

    /// The phone row sits between Engine and Features, where the section enum places it, and only when pairing is available.
    public static func existing(includePhone: Bool) -> [SettingsSectionDescriptor] {
        var pairs: [(String, String)] = [
            ("general", "General"),
            ("appearance", "Appearance"),
            ("sounds", "Sounds"),
            ("notifications", "Notifications"),
            ("shortcuts", "Shortcuts"),
            ("insomnia", "Insomnia"),
            ("integrations", "Integrations"),
            ("murmure", "Murmure"),
            ("polyglot", "Polyglot"),
            ("dictation", "Dictation"),
            ("voice", "Voice"),
            ("engine", "Engine"),
        ]
        if includePhone { pairs.append(("iPhone", "iPhone")) }
        pairs += [
            ("features", "Features"),
            ("beamer", "Beamer"),
            ("tiling", "Tiling"),
            ("shelf", "Shelf"),
            ("license", "License"),
            ("permissions", "Permissions"),
            ("privacy", "Privacy"),
            ("diagnostics", "Diagnostics"),
            ("about", "About"),
        ]
        return pairs.enumerated().map { row($0.offset, $0.element.0, $0.element.1) }
    }

    public static let topbarID = "settings.topbar"
    public static let topbarTitle = "Topbar"

    /// One Topbar row follows the existing rows when any topbar tab is filled and enabled.
    public static func sections(slots: [GlassSectionSlot], includePhone: Bool = false) -> [SettingsSectionDescriptor] {
        let base = existing(includePhone: includePhone)
        guard !GlassSectionManifest.topbarTabs(in: slots).isEmpty else { return base }
        return base + [
            SettingsSectionDescriptor(
                id: topbarID,
                title: topbarTitle,
                order: base.count,
                accessibilityLabel: topbarTitle,
                placeholder: nil
            ),
        ]
    }

    /// First id wins. Order is placement order, then the descriptor order. The final sort is load-bearing.
    public static func orderedSlots(_ slots: [GlassSectionSlot]) -> [GlassSectionSlot] {
        let ranked = slots.sorted { lhs, rhs in
            if lhs.placement.order != rhs.placement.order { return lhs.placement.order < rhs.placement.order }
            if lhs.order != rhs.order { return lhs.order < rhs.order }
            if lhs.id != rhs.id { return lhs.id < rhs.id }
            return lhs.title < rhs.title
        }
        var seen: Set<String> = []
        let unique = ranked.filter { slot in
            if seen.contains(slot.id) { return false }
            seen.insert(slot.id)
            return true
        }
        return Array(unique.reversed()).sorted { lhs, rhs in
            if lhs.placement.order != rhs.placement.order { return lhs.placement.order < rhs.placement.order }
            if lhs.order != rhs.order { return lhs.order < rhs.order }
            return lhs.id < rhs.id
        }
    }

    public static var live: [SettingsSectionDescriptor] { live(includePhone: false) }

    public static func live(includePhone: Bool) -> [SettingsSectionDescriptor] {
        sections(slots: GlassSectionManifest.slots, includePhone: includePhone)
    }

    /// The page heading for one shown slot. An unfilled or disabled slot has no heading.
    public static func pageHeading(for slot: GlassSectionSlot) -> SettingsSectionDescriptor? {
        guard slot.isShown else { return nil }
        return SettingsSectionDescriptor(
            id: slot.id,
            title: slot.title,
            order: slot.placement.order,
            accessibilityLabel: slot.title,
            placeholder: nil
        )
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
        case id(for: "integrations"), id(for: "murmure"), id(for: "polyglot"), id(for: "dictation"), id(for: "voice"), id(for: "engine"), id(for: "iPhone"), id(for: "features"), id(for: "beamer"), id(for: "tiling"), id(for: "shelf"):
            return "Your tools"
        case id(for: "license"), id(for: "permissions"), id(for: "privacy"), id(for: "diagnostics"), id(for: "about"), topbarID:
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

/// Glass rows the host can show. A filled descriptor is hosted through its provider type.
public enum SettingsSectionHostPlan {
    public static func hostedIDs(in sections: [SettingsSectionDescriptor]) -> [String] {
        sections.filter { $0.id.hasPrefix("glass.") }.map(\.id)
    }
}

/// One selected row. A section and a slot cannot both be selected.
public enum SettingsSelectionState: Equatable, Sendable {
    case section(String)
    case slot(String)
    case topbar(tab: String)
}

public enum SettingsSelectionRules {
    public static func selectingSection(_ id: String, current: SettingsSelectionState) -> SettingsSelectionState {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return current }
        return .section(trimmed)
    }

    public static func selectingSlot(_ id: String, current: SettingsSelectionState) -> SettingsSelectionState {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return current }
        return .slot(trimmed)
    }

    /// A blank, unknown, unfilled, or disabled tab leaves the current selection alone.
    public static func selectingTopbar(_ id: String, filledTabs: [String], current: SettingsSelectionState) -> SettingsSelectionState {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, filledTabs.contains(trimmed) else { return current }
        return .topbar(tab: trimmed)
    }

    public static func isExclusive(_ state: SettingsSelectionState) -> Bool {
        switch state {
        case .section, .slot, .topbar: return true
        }
    }
}

/// Sidebar rows stay 30 points and scroll above the version line.
public enum SettingsSidebarLayout {
    public static let top = 114.0
    public static let versionY = 751.0
    public static let headingHeight = 20.0
    public static let headingBottom = 5.0
    public static let groupGap = 8.5
    public static let rowHeight = 30.0
    public static let rowGap = 2.0

    public static var headingsHeight: Double {
        let groups = 3.0
        return groups * (headingHeight + headingBottom) + (groups - 1) * groupGap
    }

    public static var scrollHeight: Double { versionY - top }

    public static func rowMetrics(rowCount: Int) -> (height: Double, gap: Double) {
        _ = rowCount
        return (rowHeight, rowGap)
    }

    public static func bottom(rowCount: Int) -> Double {
        let metrics = rowMetrics(rowCount: rowCount)
        return top + headingsHeight + Double(rowCount) * (metrics.height + metrics.gap)
    }
}
