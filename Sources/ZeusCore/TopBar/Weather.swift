import Foundation

/// Current weather and today's outlook, decoded from Open-Meteo (free, no key, no account).
public struct WeatherSnapshot: Equatable, Sendable {
    public enum Sky: String, Sendable { case clear, partlyCloudy, cloudy, fog, drizzle, rain, snow, storm }

    public struct Hour: Equatable, Sendable {
        public var time: Date
        public var temperature: Double
        public var sky: Sky
        public var rainChance: Int

        public init(time: Date, temperature: Double, sky: Sky, rainChance: Int) {
            self.time = time
            self.temperature = temperature
            self.sky = sky
            self.rainChance = rainChance
        }
    }

    /// One day of the forecast (the Days variant on Home).
    public struct Day: Equatable, Sendable {
        public var date: Date
        public var high: Double
        public var low: Double
        public var sky: Sky

        public init(date: Date, high: Double, low: Double, sky: Sky) {
            self.date = date
            self.high = high
            self.low = low
            self.sky = sky
        }
    }

    public var temperature: Double
    public var apparent: Double
    public var high: Double
    public var low: Double
    public var sky: Sky
    public var isDay: Bool
    public var humidity: Int
    public var wind: Double
    public var hours: [Hour]
    /// Today and the next days; empty when the forecast carried none.
    public var days: [Day]
    public var fetchedAt: Date

    public init(temperature: Double, apparent: Double, high: Double, low: Double, sky: Sky, isDay: Bool,
                humidity: Int, wind: Double, hours: [Hour], days: [Day] = [], fetchedAt: Date = Date()) {
        self.temperature = temperature
        self.apparent = apparent
        self.high = high
        self.low = low
        self.sky = sky
        self.isDay = isDay
        self.humidity = humidity
        self.wind = wind
        self.hours = hours
        self.days = days
        self.fetchedAt = fetchedAt
    }

    public static func sky(forCode code: Int) -> Sky {
        switch code {
        case 0: .clear
        case 1, 2: .partlyCloudy
        case 3: .cloudy
        case 45, 48: .fog
        case 51...57: .drizzle
        case 61...67, 80...82: .rain
        case 71...77, 85, 86: .snow
        case 95...99: .storm
        default: .cloudy
        }
    }

    public var phrase: String {
        switch sky {
        case .clear: isDay ? "Clear and sunny" : "Clear night"
        case .partlyCloudy: "Partly cloudy"
        case .cloudy: "Overcast"
        case .fog: "Foggy"
        case .drizzle: "Light drizzle"
        case .rain: "Rain"
        case .snow: "Snow"
        case .storm: "Thunderstorms"
        }
    }

    public var symbol: String { Self.symbol(for: sky, isDay: isDay) }

    /// SF Symbol for a sky condition, also used for the hourly strip.
    public static func symbol(for sky: Sky, isDay: Bool) -> String {
        switch sky {
        case .clear: isDay ? "sun.max.fill" : "moon.stars.fill"
        case .partlyCloudy: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case .cloudy: "cloud.fill"
        case .fog: "cloud.fog.fill"
        case .drizzle: "cloud.drizzle.fill"
        case .rain: "cloud.rain.fill"
        case .snow: "cloud.snow.fill"
        case .storm: "cloud.bolt.rain.fill"
        }
    }

    /// The first hour in the next six with a 50%+ chance of rain, for a gentle heads-up.
    public func rainSoon(after now: Date = Date()) -> Hour? {
        hours.filter { $0.time > now && $0.time < now.addingTimeInterval(6 * 3600) }.first { $0.rainChance >= 50 }
    }

    public static func url(latitude: Double, longitude: Double) -> URL {
        var parts = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        parts.queryItems = [
            .init(name: "latitude", value: String(format: "%.3f", latitude)),
            .init(name: "longitude", value: String(format: "%.3f", longitude)),
            .init(name: "current", value: "temperature_2m,apparent_temperature,weather_code,is_day,relative_humidity_2m,wind_speed_10m"),
            .init(name: "hourly", value: "temperature_2m,weather_code,precipitation_probability"),
            .init(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min"),
            .init(name: "forecast_days", value: "5"),
            .init(name: "timezone", value: "auto"),
            .init(name: "timeformat", value: "unixtime"),
        ]
        return parts.url!
    }

    private struct Response: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let apparent_temperature: Double
            let weather_code: Int
            let is_day: Int
            let relative_humidity_2m: Int
            let wind_speed_10m: Double
        }
        struct Hourly: Decodable {
            let time: [Double]
            let temperature_2m: [Double]
            let weather_code: [Int]
            let precipitation_probability: [Int?]
        }
        struct Daily: Decodable {
            let time: [Double]?
            let weather_code: [Int]?
            let temperature_2m_max: [Double]
            let temperature_2m_min: [Double]
        }
        let current: Current
        let hourly: Hourly
        let daily: Daily
    }

    public static func decode(_ data: Data, now: Date = Date()) throws -> WeatherSnapshot {
        let r = try JSONDecoder().decode(Response.self, from: data)
        let count = min(r.hourly.time.count, r.hourly.temperature_2m.count, r.hourly.weather_code.count)
        let hours = (0..<count).map { i in
            Hour(time: Date(timeIntervalSince1970: r.hourly.time[i]), temperature: r.hourly.temperature_2m[i],
                 sky: sky(forCode: r.hourly.weather_code[i]),
                 rainChance: i < r.hourly.precipitation_probability.count ? (r.hourly.precipitation_probability[i] ?? 0) : 0)
        }.filter { $0.time > now.addingTimeInterval(-3600) }
        let dayCount = min(r.daily.temperature_2m_max.count, r.daily.temperature_2m_min.count, r.daily.time?.count ?? 0)
        let days = (0..<dayCount).map { i in
            Day(date: Date(timeIntervalSince1970: r.daily.time![i]), high: r.daily.temperature_2m_max[i], low: r.daily.temperature_2m_min[i],
                sky: i < (r.daily.weather_code?.count ?? 0) ? sky(forCode: r.daily.weather_code![i]) : .cloudy)
        }
        return WeatherSnapshot(
            temperature: r.current.temperature_2m, apparent: r.current.apparent_temperature,
            high: r.daily.temperature_2m_max.first ?? r.current.temperature_2m,
            low: r.daily.temperature_2m_min.first ?? r.current.temperature_2m,
            sky: sky(forCode: r.current.weather_code), isDay: r.current.is_day == 1,
            humidity: r.current.relative_humidity_2m, wind: r.current.wind_speed_10m,
            hours: Array(hours.prefix(12)), days: days, fetchedAt: now
        )
    }
}
