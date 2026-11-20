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
        guard celsius.isFinite else { return nil }
        let value = unit == .celsius ? celsius : celsius * 9 / 5 + 32
        guard value.isFinite else { return nil }
        return Int(value.rounded())
    }

    /// The forecast service reports kilometres per hour. Miles use the same factor as the Home wind card.
    public static func wind(kilometersPerHour: Double, unit: WeatherTemperatureUnit) -> Int? {
        guard kilometersPerHour.isFinite else { return nil }
        let value = unit == .celsius ? kilometersPerHour : kilometersPerHour * 0.621371
        guard value.isFinite else { return nil }
        return Int(value.rounded())
    }
}
