import Foundation

/// `topBar.celsius`. Celsius is stored as true. A missing value follows the locale, as the top bar already does.
public enum WeatherTemperatureUnit: String, Equatable, Sendable, CaseIterable {
    case celsius
    case fahrenheit

    public static let settingKey = "topBar.celsius"

    public var stored: Bool { self == .celsius }

    public var windSuffix: String { self == .celsius ? "km/h" : "mph" }

    public static func resolve(stored: Bool?, localeUsesUSCustomary: Bool) -> WeatherTemperatureUnit {
        if let stored { return stored ? .celsius : .fahrenheit }
        return localeUsesUSCustomary ? .fahrenheit : .celsius
    }

    public static func degrees(celsius: Double, unit: WeatherTemperatureUnit) -> Int? {
        let value = unit == .celsius ? celsius : celsius * 9 / 5 + 32
        return whole(value)
    }

    /// The forecast service reports kilometres per hour. Miles use the same factor as the Home wind card.
    public static func wind(kilometersPerHour: Double, unit: WeatherTemperatureUnit) -> Int? {
        let value = unit == .celsius ? kilometersPerHour : kilometersPerHour * 0.621371
        return whole(value)
    }

    /// Nil when the rounded reading does not fit in Int. `Double(Int.max)` is 2^63, so the last fitting value is the Double below it.
    private static func whole(_ value: Double) -> Int? {
        let rounded = value.rounded()
        guard rounded >= Double(Int.min) else { return nil }
        guard rounded <= Double(Int.max).nextDown else { return nil }
        return Int(rounded)
    }
}
