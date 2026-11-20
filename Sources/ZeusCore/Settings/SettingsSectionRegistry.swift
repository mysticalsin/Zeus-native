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

    public static func sections(slots: [GlassSectionSlot], includePhone: Bool = false) -> [SettingsSectionDescriptor] {
        let base = existing(includePhone: includePhone)
        let ranked = slots.filter(\.filled).sorted { lhs, rhs in
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
        let extra = Array(unique.enumerated().map { index, slot in
            SettingsSectionDescriptor(
                id: slot.id,
                title: slot.title,
                order: base.count + index,
                accessibilityLabel: slot.title,
                placeholder: slot.keys.isEmpty ? slot.title : nil
            )
        }.reversed())
        return (base + extra).sorted { lhs, rhs in
            if lhs.order != rhs.order { return lhs.order < rhs.order }
            return lhs.id < rhs.id
        }
    }

    public static var live: [SettingsSectionDescriptor] { live(includePhone: false) }

    public static func live(includePhone: Bool) -> [SettingsSectionDescriptor] {
        sections(slots: GlassSectionManifest.slots, includePhone: includePhone)
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

/// Reads each section file. A new file is a new row; nothing else has to name it.
public enum SettingsSlotDiscovery {
    public static func slots(in directory: URL) -> [GlassSectionSlot] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let sources: [(name: String, text: String)] = files.compactMap { url in
            guard url.pathExtension == "swift", let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return (url.lastPathComponent, text)
        }
        return slots(parsing: sources)
    }

    public static func slots(parsing sources: [(name: String, text: String)]) -> [GlassSectionSlot] {
        sources.sorted { $0.name < $1.name }.compactMap { parse($0.text) }.sorted { lhs, rhs in
            if lhs.order != rhs.order { return lhs.order < rhs.order }
            return lhs.id < rhs.id
        }
    }

    static func parse(_ text: String) -> GlassSectionSlot? {
        guard let args = argumentList(in: text),
              let id = string("id", in: args),
              let title = string("title", in: args),
              let filled = bool("filled", in: args) else { return nil }
        return GlassSectionSlot(id: id, title: title, filled: filled, keys: keys(in: args), order: integer("order", in: args) ?? 0)
    }

    private static func argumentList(in text: String) -> String? {
        guard let start = text.range(of: "GlassSectionSlot(") else { return nil }
        var depth = 1
        var index = start.upperBound
        var result = ""
        while index < text.endIndex && depth > 0 {
            let character = text[index]
            if character == "(" { depth += 1 }
            if character == ")" {
                depth -= 1
                if depth == 0 { break }
            }
            result.append(character)
            index = text.index(after: index)
        }
        return depth == 0 ? result : nil
    }

    private static func string(_ label: String, in text: String) -> String? {
        guard let range = text.range(of: "\(label): \"") else { return nil }
        var value = ""
        var index = range.upperBound
        while index < text.endIndex {
            let character = text[index]
            if character == "\\" {
                let next = text.index(after: index)
                guard next < text.endIndex else { return nil }
                value.append(text[next])
                index = text.index(after: next)
                continue
            }
            if character == "\"" { return value }
            value.append(character)
            index = text.index(after: index)
        }
        return nil
    }

    private static func bool(_ label: String, in text: String) -> Bool? {
        if text.contains("\(label): true") { return true }
        if text.contains("\(label): false") { return false }
        return nil
    }

    private static func integer(_ label: String, in text: String) -> Int? {
        guard let range = text.range(of: "\(label):") else { return nil }
        let digits = text[range.upperBound...].drop(while: { $0 == " " || $0 == "\n" }).prefix(while: \.isNumber)
        return Int(digits)
    }

    private static func keys(in text: String) -> [String] {
        guard let label = text.range(of: "keys:"), let open = text[label.upperBound...].firstIndex(of: "[") else { return [] }
        var values: [String] = []
        var index = text.index(after: open)
        while index < text.endIndex, text[index] != "]" {
            if text[index] == "\"" {
                var value = ""
                index = text.index(after: index)
                while index < text.endIndex {
                    if text[index] == "\\" {
                        let next = text.index(after: index)
                        guard next < text.endIndex else { break }
                        value.append(text[next])
                        index = text.index(after: next)
                        continue
                    }
                    if text[index] == "\"" { values.append(value); break }
                    value.append(text[index])
                    index = text.index(after: index)
                }
            }
            index = text.index(after: index)
        }
        return values
    }
}

/// Glass rows the host can show. Any discovered filled id is hosted; there is no per-id branch.
public enum SettingsSectionHostPlan {
    public static func hostedIDs(in sections: [SettingsSectionDescriptor]) -> [String] {
        sections.filter { $0.id.hasPrefix("glass.") }.map(\.id)
    }
}

/// One selected row. A section and a slot cannot both be selected.
public enum SettingsSelectionState: Equatable, Sendable {
    case section(String)
    case slot(String)
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

    public static func isExclusive(_ state: SettingsSelectionState) -> Bool {
        switch state {
        case .section, .slot: return true
        }
    }
}

/// Sidebar pitch. Every visible row, existing and filled, shares the room above the version line.
public enum SettingsSidebarLayout {
    public static let top = 114.0
    public static let versionY = 751.0
    public static let headingHeight = 20.0
    public static let headingBottom = 5.0
    public static let groupGap = 8.5
    public static let rowHeight = 26.0
    public static let rowGap = 2.0

    public static var headingsHeight: Double {
        let groups = 3.0
        return groups * (headingHeight + headingBottom) + (groups - 1) * groupGap
    }

    public static func rowMetrics(rowCount: Int) -> (height: Double, gap: Double) {
        let full = rowHeight + rowGap
        let room = versionY - top - headingsHeight
        let pitch = min(full, (room / Double(max(rowCount, 1))).rounded(.down))
        let gap = pitch >= full ? rowGap : 1
        return (max(1, min(rowHeight, pitch - gap)), gap)
    }

    public static func bottom(rowCount: Int) -> Double {
        let metrics = rowMetrics(rowCount: rowCount)
        return top + headingsHeight + Double(rowCount) * (metrics.height + metrics.gap)
    }
}
