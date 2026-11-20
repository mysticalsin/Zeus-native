import Foundation

public enum LocationAuthorization: Equatable, Sendable {
    case notDetermined
    case allowed
    case denied
    case restricted
}

public enum PreciseLocationPhase: Equatable, Sendable {
    case off
    case prompting
    case using
    case denied
    case restricted
}

public enum PreciseLocationEvent: Equatable, Sendable {
    case userEnabled
    case userDisabled
    case authorization(LocationAuthorization)
}

public enum PreciseLocationEffect: Equatable, Sendable {
    /// The system permission prompt. This is the only effect that may show it.
    case requestPrompt
    /// The system already decided. Open its settings page. Do not show a prompt.
    case revealSystemSettings
    case stopReadingLocation
}

/// `perm.location`. Precise location stays off until the user turns it on, and the prompt is that turn.
public struct PreciseLocationMachine: Equatable, Sendable {
    public static let settingKey = "perm.location"
    public var settingKey: String { Self.settingKey }

    public private(set) var wantsPreciseLocation: Bool
    public private(set) var authorization: LocationAuthorization
    public private(set) var promptOutstanding: Bool

    public init() {
        wantsPreciseLocation = false
        authorization = .notDetermined
        promptOutstanding = false
    }

    public var phase: PreciseLocationPhase {
        guard wantsPreciseLocation else { return .off }
        switch authorization {
        case .notDetermined: return promptOutstanding ? .prompting : .off
        case .allowed: return .using
        case .denied: return .denied
        case .restricted: return .restricted
        }
    }

    public var readsCoordinates: Bool {
        wantsPreciseLocation && authorization == .allowed
    }

    public var showsPrompt: Bool {
        wantsPreciseLocation && promptOutstanding && authorization == .notDetermined
    }

    public var statusLabel: String {
        switch phase {
        case .off: "Optional"
        case .prompting: "Asking"
        case .using: "Allowed"
        case .denied: "Denied"
        case .restricted: "No access"
        }
    }

    public mutating func send(_ event: PreciseLocationEvent) -> PreciseLocationEffect? {
        switch event {
        case .userEnabled:
            let alreadyPrompting = promptOutstanding && authorization == .notDetermined
            wantsPreciseLocation = true
            if authorization == .notDetermined {
                if alreadyPrompting { return nil }
                promptOutstanding = true
                return .requestPrompt
            }
            promptOutstanding = false
            if authorization == .allowed { return nil }
            return .revealSystemSettings
        case .userDisabled:
            let active = readsCoordinates || showsPrompt
            wantsPreciseLocation = false
            promptOutstanding = false
            return active ? .stopReadingLocation : nil
        case .authorization(let next):
            let wasReading = readsCoordinates
            authorization = next
            if next != .notDetermined { promptOutstanding = false }
            if wasReading && !readsCoordinates { return .stopReadingLocation }
            return nil
        }
    }
}

public struct LocationFix: Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public var label: String

    public init(latitude: Double, longitude: Double, label: String) {
        self.latitude = latitude
        self.longitude = longitude
        self.label = label
    }

    public var isValid: Bool {
        latitude.isFinite && longitude.isFinite
            && (-90...90).contains(latitude)
            && (-180...180).contains(longitude)
    }
}
