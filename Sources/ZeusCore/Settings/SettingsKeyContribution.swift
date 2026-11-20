import Foundation

public enum SettingsKeyKind: String, Equatable, Sendable {
    case toggle, text, choice, number
}

/// Who may carry a contributed key across machines.
public enum SettingsKeyPolicy: Equatable, Sendable {
    /// Saved, exported, and imported.
    case exportable
    /// Saved on this Mac. Export and import leave it out.
    case localOnly
    /// Saved and exported. An import may turn it off and may not turn it on.
    case importCannotEnable
    /// Keychain only. The settings store rejects it, and export and import leave it out.
    case secretNeverStored
}

public struct SettingsKeyContribution: Equatable, Sendable {
    public var id: String
    public var defaultValue: String
    public var kind: SettingsKeyKind
    public var policy: SettingsKeyPolicy

    public init(id: String, defaultValue: String, kind: SettingsKeyKind, policy: SettingsKeyPolicy) {
        self.id = id
        self.defaultValue = defaultValue
        self.kind = kind
        self.policy = policy
    }
}

extension GlassSlotProviding {
    public static var keyContributions: [SettingsKeyContribution] { [] }
}

public enum SettingsKeyLedger {
    public static func load(_ item: SettingsKeyContribution, stored: String?) -> String {
        if item.policy == .secretNeverStored { return item.defaultValue }
        return stored ?? item.defaultValue
    }

    public static func mayStore(_ item: SettingsKeyContribution, value: String) -> Bool {
        if item.policy == .secretNeverStored { return false }
        if looksLikeSecret(value) { return false }
        return true
    }

    public static func persists(_ item: SettingsKeyContribution) -> Bool {
        item.policy != .secretNeverStored
    }

    @discardableResult
    public static func save(_ stored: inout [String: String], _ item: SettingsKeyContribution, _ value: String) -> Bool {
        guard mayStore(item, value: value) else { return false }
        stored[item.id] = value
        return true
    }

    public static func exportMap(stored: [String: String], contributions: [SettingsKeyContribution]) -> [String: String] {
        var out: [String: String] = [:]
        for item in contributions {
            switch item.policy {
            case .localOnly, .secretNeverStored:
                continue
            case .exportable, .importCannotEnable:
                let value = stored[item.id] ?? item.defaultValue
                if looksLikeSecret(value) { continue }
                out[item.id] = value
            }
        }
        return out
    }

    public static func imported(_ item: SettingsKeyContribution, current: String, incoming: String) -> String? {
        switch item.policy {
        case .localOnly, .secretNeverStored:
            return nil
        case .exportable, .importCannotEnable:
            if looksLikeSecret(incoming) { return nil }
            if item.policy == .importCannotEnable, !isOn(current, item), isOn(incoming, item) { return nil }
            return incoming
        }
    }

    public static func resetValue(_ item: SettingsKeyContribution) -> String? {
        item.policy == .secretNeverStored ? nil : item.defaultValue
    }

    public static func search(_ query: String, in contributions: [SettingsKeyContribution]) -> [SettingsKeyContribution] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return contributions }
        return contributions.filter { item in
            let haystack = item.id.lowercased()
            return words.allSatisfy { haystack.contains($0) }
        }
    }

    public static func looksLikeSecret(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower.hasPrefix("sk-") || lower.hasPrefix("sk_") || lower.hasPrefix("xox") { return true }
        if lower.contains("api_key") || lower.contains("api-key") { return true }
        let token = trimmed.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        return trimmed.count >= 24 && token && trimmed.contains(where: \.isNumber) && trimmed.contains(where: \.isLetter)
    }

    /// Blank ids, ids shared with the catalog, and ids repeated among contributions.
    public static func problems(catalogIDs: [String], contributions: [SettingsKeyContribution]) -> [String] {
        var problems: [String] = []
        var seen: [String: Int] = [:]
        let catalog = Set(catalogIDs)
        for item in contributions {
            let id = item.id.trimmingCharacters(in: .whitespacesAndNewlines)
            if id.isEmpty {
                problems.append("blank contribution id")
                continue
            }
            if load(item, stored: nil) != item.defaultValue { problems.append("\(id) has no default") }
            seen[id, default: 0] += 1
            if catalog.contains(id) { problems.append("duplicate id \(id)") }
        }
        for (id, count) in seen where count > 1 { problems.append("duplicate id \(id)") }
        return problems.sorted()
    }

    private static func isOn(_ value: String, _ item: SettingsKeyContribution) -> Bool {
        switch item.kind {
        case .toggle: return value == "true"
        case .text, .choice, .number:
            return value != item.defaultValue && value != "false" && value != "0" && !value.isEmpty
        }
    }
}
