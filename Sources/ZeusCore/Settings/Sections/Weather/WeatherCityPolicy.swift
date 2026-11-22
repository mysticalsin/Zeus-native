import Foundation

/// `topBar.weatherCity`. A blank name requests nothing. The forecast service sees the trimmed name only.
public enum WeatherCityPolicy {
    public static let settingKey = "topBar.weatherCity"
    public static let maxLength = 120

    public enum Decision: Equatable, Sendable {
        case empty
        case accepted(String)
        case rejected(Reason)
    }

    public enum Reason: Equatable, Sendable {
        case tooLong(Int)
        case controlCharacter
    }

    public static func decide(_ raw: String) -> Decision {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .empty }
        if trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
            return .rejected(.controlCharacter)
        }
        if trimmed.count > maxLength { return .rejected(.tooLong(trimmed.count)) }
        return .accepted(trimmed)
    }
}
