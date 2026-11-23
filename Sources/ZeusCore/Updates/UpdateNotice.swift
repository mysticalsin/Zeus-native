import Foundation

/// Whether the update badge should present a notice. The coordinator still shows it.
public struct UpdateAnnouncement: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case hidden
        case due(String)
        case shown(String)
    }

    public enum Effect: Equatable, Sendable {
        case present
    }

    public private(set) var state: State

    public init() {
        state = .hidden
    }

    public mutating func badgeHidden() -> [Effect] {
        state = .hidden
        return []
    }

    /// An available badge whose version equals `shownKey`, or one already due or shown, presents nothing.
    /// A different version becomes due and emits `present` once.
    public mutating func badgeAvailable(_ version: String, shownKey: String?) -> [Effect] {
        if shownKey == version || state == .shown(version) || state == .due(version) {
            if shownKey == version || state == .shown(version) {
                state = .shown(version)
            }
            return []
        }
        state = .due(version)
        return [.present]
    }

    public mutating func didPresent(_ version: String) {
        state = .shown(version)
    }
}

/// The hourly update poll. Each start replaces the timer that is already armed.
public struct UpdatePoll: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case idle
        case armed
    }

    public enum Effect: Equatable, Sendable {
        case replaceTimer
    }

    public private(set) var state: State

    public init() {
        state = .idle
    }

    public mutating func start() -> [Effect] {
        state = .armed
        return [.replaceTimer]
    }
}

/// The link `performUpdate` opens. Only an HTTPS offer is used. Anything else is the existing fallback.
public enum UpdateOpen {
    public static let fallback = "https://zeus.app"

    public static func destination(offer: URL?) -> URL? {
        if let offer, secure(offer) { return offer }
        return URL(string: fallback)
    }

    /// The same transport rule as `UpdateFeedPolicy.isSecure`: HTTPS, a host, and no credentials.
    private static func secure(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty else { return false }
        return url.user == nil && url.password == nil
    }
}
