import Foundation

/// The weather keys Zeus already stores. City and units use the top bar defaults. Layout uses the catalog
/// key with the settings store's `opt.` prefix. Precise location is the string "true" or "false" at `perm.location`.
public enum WeatherSettingsDisk {
    public static let cityKey = "topBar.weatherCity"
    public static let celsiusKey = "topBar.celsius"
    public static let layoutKey = "opt.home.variant.weather"
    public static let locationKey = "perm.location"

    public struct Values: Equatable, Sendable {
        public var city: String
        public var unit: WeatherTemperatureUnit
        public var layout: WeatherLayoutChoice
        public var preciseLocation: Bool

        public init(city: String, unit: WeatherTemperatureUnit, layout: WeatherLayoutChoice, preciseLocation: Bool) {
            self.city = city
            self.unit = unit
            self.layout = layout
            self.preciseLocation = preciseLocation
        }
    }

    public static func load(defaults: UserDefaults, localeUsesUSCustomary: Bool) -> Values {
        let storedCelsius: Bool? = defaults.object(forKey: celsiusKey) == nil ? nil : defaults.bool(forKey: celsiusKey)
        return Values(
            city: defaults.string(forKey: cityKey) ?? "",
            unit: WeatherTemperatureUnit.resolve(stored: storedCelsius, localeUsesUSCustomary: localeUsesUSCustomary),
            layout: WeatherLayoutChoice.resolve(defaults.string(forKey: layoutKey)),
            preciseLocation: defaults.string(forKey: locationKey) == "true"
        )
    }

    /// `preciseLocation` nil leaves that key alone. A value writes "true" or "false" and never removes it.
    public static func save(city: String, unit: WeatherTemperatureUnit, layout: WeatherLayoutChoice, preciseLocation: Bool? = nil, defaults: UserDefaults) {
        let storedCity: String
        switch WeatherCityPolicy.decide(city) {
        case .accepted(let name): storedCity = name
        case .empty, .rejected: storedCity = ""
        }
        defaults.set(storedCity, forKey: cityKey)
        defaults.set(unit.stored, forKey: celsiusKey)
        defaults.set(layout.title, forKey: layoutKey)
        if let preciseLocation {
            defaults.set(preciseLocation ? "true" : "false", forKey: locationKey)
        }
    }

    /// An imported file may change the city, the unit, and the layout. It cannot turn precise location on.
    public static func applyingImport(_ incoming: [String: Any], onto current: Values) -> Values {
        var next = current
        if let flag = incoming[locationKey] as? String, flag == "false" { next.preciseLocation = false }
        if let flag = incoming[locationKey] as? Bool, flag == false { next.preciseLocation = false }
        if let city = incoming[cityKey] as? String {
            switch WeatherCityPolicy.decide(city) {
            case .accepted(let name): next.city = name
            case .empty: next.city = ""
            case .rejected: break
            }
        }
        if let flag = incoming[celsiusKey] as? Bool {
            next.unit = WeatherTemperatureUnit.resolve(stored: flag, localeUsesUSCustomary: false)
        }
        if let layout = incoming[layoutKey] as? String,
           WeatherLayoutChoice.allCases.contains(where: { $0.rawValue == layout || $0.title == layout }) {
            next.layout = WeatherLayoutChoice.resolve(layout)
        }
        return next
    }
}
