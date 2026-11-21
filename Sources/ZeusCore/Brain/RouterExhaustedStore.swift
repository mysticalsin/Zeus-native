import Foundation

/// Quota expiries saved as a property-list dictionary. Values are read one by one: a cast of the
/// whole dictionary to `[String: Date]` does not succeed.
public enum RouterExhaustedStore {
    public static let key = "router.exhausted"

    public static func load(_ defaults: UserDefaults, now: Date = Date()) -> [String: Date] {
        guard let raw = defaults.dictionary(forKey: key) else { return [:] }
        var out: [String: Date] = [:]
        for (name, value) in raw {
            let date: Date?
            if let value = value as? Date {
                date = value
            } else {
                date = nil
            }
            if let date, date > now { out[name] = date }
        }
        return out
    }
}
