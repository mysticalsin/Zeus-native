import Foundation

/// `home.variant.weather`. Ids and titles stay aligned with the Home weather widget.
public enum WeatherLayoutChoice: String, Equatable, Sendable, CaseIterable {
    case summary
    case hourly
    case days
    case feels
    case wind

    public static let settingKey = "home.variant.weather"

    public var title: String {
        switch self {
        case .summary: "Summary"
        case .hourly: "Hourly curve"
        case .days: "Days"
        case .feels: "Feels like"
        case .wind: "Wind"
        }
    }

    public static func resolve(_ stored: String?) -> WeatherLayoutChoice {
        guard let stored, !stored.isEmpty else { return .summary }
        if let exact = WeatherLayoutChoice(rawValue: stored) { return exact }
        return allCases.first { $0.title == stored } ?? .summary
    }
}
