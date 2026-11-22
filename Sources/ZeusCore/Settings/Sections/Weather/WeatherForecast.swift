import Foundation

public struct WeatherPlace: Equatable, Sendable {
    public var name: String
    public var latitude: Double
    public var longitude: Double

    public init(name: String, latitude: Double, longitude: Double) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }
}

public enum WeatherServiceEndpoints {
    public static func geocodeURL(city: String) -> URL? {
        guard case .accepted(let name) = WeatherCityPolicy.decide(city) else { return nil }
        var parts = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")
        parts?.queryItems = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "count", value: "1"),
        ]
        return parts?.url
    }

    public static func forecastURL(latitude: Double, longitude: Double) -> URL {
        WeatherSnapshot.url(latitude: latitude, longitude: longitude)
    }
}

public enum WeatherPlaceDecoder {
    public static func decode(_ data: Data) -> WeatherPlace? {
        struct Response: Decodable { let results: [Place]? }
        struct Place: Decodable {
            let name: String
            let latitude: Double
            let longitude: Double
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              let place = response.results?.first,
              place.latitude.isFinite, place.longitude.isFinite else { return nil }
        return WeatherPlace(name: place.name, latitude: place.latitude, longitude: place.longitude)
    }
}

public enum WeatherChipPhase: Equatable, Sendable {
    case idle(String)
    case loading(String)
    case empty(String)
    case ready(WeatherChip)
    case failed(String)
}

public struct WeatherChip: Equatable, Sendable {
    public var place: String
    public var reading: String
    public var detail: String
    public var symbol: String
    public var unit: WeatherTemperatureUnit
    public var layout: WeatherLayoutChoice
    public var accessibilityLabel: String

    public init(place: String, reading: String, detail: String, symbol: String, unit: WeatherTemperatureUnit, layout: WeatherLayoutChoice, accessibilityLabel: String) {
        self.place = place
        self.reading = reading
        self.detail = detail
        self.symbol = symbol
        self.unit = unit
        self.layout = layout
        self.accessibilityLabel = accessibilityLabel
    }
}

public enum WeatherChipBuilder {
    public static func chip(snapshot: WeatherSnapshot, place: String, unit: WeatherTemperatureUnit, layout: WeatherLayoutChoice) -> WeatherChip? {
        let reading: String
        switch layout {
        case .summary, .hourly:
            guard let degrees = WeatherTemperatureUnit.degrees(celsius: snapshot.temperature, unit: unit) else { return nil }
            reading = "\(degrees)°"
        case .days:
            guard let degrees = WeatherTemperatureUnit.degrees(celsius: snapshot.high, unit: unit) else { return nil }
            reading = "\(degrees)°"
        case .feels:
            guard let degrees = WeatherTemperatureUnit.degrees(celsius: snapshot.apparent, unit: unit) else { return nil }
            reading = "\(degrees)°"
        case .wind:
            guard let speed = WeatherTemperatureUnit.wind(kilometersPerHour: snapshot.wind, unit: unit) else { return nil }
            reading = "\(speed) \(unit.windSuffix)"
        }
        let trimmed = place.trimmingCharacters(in: .whitespacesAndNewlines)
        let shown = trimmed.isEmpty ? "Weather" : trimmed
        return WeatherChip(
            place: shown,
            reading: reading,
            detail: "\(layout.title) · \(snapshot.phrase)",
            symbol: snapshot.symbol,
            unit: unit,
            layout: layout,
            accessibilityLabel: "\(shown), \(reading), \(snapshot.phrase)"
        )
    }
}

public struct WeatherForecastLoader: Sendable {
    public var loadBytes: @Sendable (URL) async throws -> Data

    public init(loadBytes: @escaping @Sendable (URL) async throws -> Data) {
        self.loadBytes = loadBytes
    }

    public func load(city: String, unit: WeatherTemperatureUnit, layout: WeatherLayoutChoice) async -> WeatherChipPhase {
        switch await fetch(city: city) {
        case .idle(let text): .idle(text)
        case .empty(let text): .empty(text)
        case .failed(let text): .failed(text)
        case .forecast(let snapshot, let place):
            if let chip = WeatherChipBuilder.chip(snapshot: snapshot, place: place, unit: unit, layout: layout) {
                .ready(chip)
            } else {
                .failed("Weather is unavailable right now.")
            }
        }
    }

    /// The same service `load` uses, keeping the snapshot so a unit or layout change does not ask again.
    public func fetch(city: String) async -> WeatherFetchOutcome {
        switch WeatherCityPolicy.decide(city) {
        case .empty:
            return .idle("Type a city, or turn on precise location.")
        case .rejected(.tooLong):
            return .failed("Use a city name of 120 characters or fewer.")
        case .rejected(.controlCharacter):
            return .failed("Use a city name without control characters.")
        case .accepted(let name):
            guard let geocode = WeatherServiceEndpoints.geocodeURL(city: name) else {
                return .failed("Weather is unavailable right now.")
            }
            do {
                let placeData = try await loadBytes(geocode)
                guard let place = WeatherPlaceDecoder.decode(placeData) else {
                    return .empty("That city was not found.")
                }
                let forecast = WeatherServiceEndpoints.forecastURL(latitude: place.latitude, longitude: place.longitude)
                let forecastData = try await loadBytes(forecast)
                let snapshot = try WeatherSnapshot.decode(forecastData)
                return .forecast(snapshot, place: place.name)
            } catch {
                return .failed("Weather is unavailable right now.")
            }
        }
    }

    public func fetch(latitude: Double, longitude: Double, place: String) async -> WeatherFetchOutcome {
        let fix = LocationFix(latitude: latitude, longitude: longitude, label: place)
        guard fix.isValid else { return .failed("That location is outside the forecast range.") }
        do {
            let data = try await loadBytes(WeatherServiceEndpoints.forecastURL(latitude: latitude, longitude: longitude))
            let snapshot = try WeatherSnapshot.decode(data)
            return .forecast(snapshot, place: place)
        } catch {
            return .failed("Weather is unavailable right now.")
        }
    }
}

public enum WeatherFetchOutcome: Equatable, Sendable {
    case idle(String)
    case empty(String)
    case failed(String)
    case forecast(WeatherSnapshot, place: String)
}
