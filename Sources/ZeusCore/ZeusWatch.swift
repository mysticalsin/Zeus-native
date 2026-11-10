import Foundation

/// A $0 watch: poll a window title or a shell test on an interval. No model calls while waiting.
public struct ZeusWatch: Codable, Equatable, Identifiable, Sendable {
    public enum Trigger: Codable, Equatable, Sendable {
        case windowGone(titleContains: String)
        case windowShows(titleContains: String)
        case shellTest(exitZeroWhen: String)
    }

    public var id: UUID
    public var label: String
    public var trigger: Trigger
    public var intervalSeconds: TimeInterval
    public var created: Date

    public init(id: UUID = UUID(), label: String, trigger: Trigger, intervalSeconds: TimeInterval = 5, created: Date = Date()) {
        self.id = id
        self.label = label
        self.trigger = trigger
        self.intervalSeconds = max(1, intervalSeconds)
        self.created = created
    }
}

public struct FakeMacSnapshot: Equatable, Sendable {
    public var frontApp: String
    public var frontWindowTitle: String
    public var shellTests: [String: Bool]
    /// Names of every running app, so "Preview is gone" holds only once Preview has quit,
    /// not whenever another app is in front.
    public var openTitles: [String]
    /// False when the window list could not be read (no Accessibility, or an app did not answer):
    /// the titles are then unknown, so a "gone" watch must wait instead of firing.
    public var windowsObserved: Bool

    public init(frontApp: String = "Fixture", frontWindowTitle: String = "", shellTests: [String: Bool] = [:],
                openTitles: [String] = [], windowsObserved: Bool = true) {
        self.frontApp = frontApp
        self.frontWindowTitle = frontWindowTitle
        self.shellTests = shellTests
        self.openTitles = openTitles
        self.windowsObserved = windowsObserved
    }

    /// Whether the front window or any running app matches `needle`.
    public func shows(_ needle: String) -> Bool {
        guard !needle.isEmpty else { return false }
        return frontWindowTitle.localizedCaseInsensitiveContains(needle)
            || openTitles.contains { $0.localizedCaseInsensitiveContains(needle) }
    }
}

public enum ZeusWatchEvaluator {
    public struct TickResult: Equatable, Sendable {
        public var fired: Bool
        public var message: String
    }

    public static func evaluate(_ watch: ZeusWatch, mac: FakeMacSnapshot) -> TickResult {
        switch watch.trigger {
        case .windowGone(let needle):
            let hit = mac.shows(needle)
            // Unknown is not gone: with the windows unreadable, absence proves nothing.
            guard mac.windowsObserved || hit else { return TickResult(fired: false, message: "Can't see windows right now") }
            return TickResult(fired: !hit && !needle.isEmpty, message: hit ? "Still showing \(needle)" : "\(needle) is gone")
        case .windowShows(let needle):
            let hit = mac.shows(needle)
            return TickResult(fired: hit, message: hit ? "\(needle) appeared" : "Waiting for \(needle)")
        case .shellTest(let command):
            let ok = mac.shellTests[command] ?? false
            return TickResult(fired: ok, message: ok ? "\(command) succeeded" : "\(command) not ready")
        }
    }

    /// Simulates polling every `interval` until `deadline` or fired. Returns ticks and LLM call count (always 0).
    public static func pollUntilFire(watch: ZeusWatch, macStates: [FakeMacSnapshot], interval: TimeInterval = 5,
                                     llmCalls: inout Int) -> (fired: Bool, ticks: Int) {
        var ticks = 0
        for mac in macStates {
            ticks += 1
            let result = evaluate(watch, mac: mac)
            if result.fired { return (true, ticks) }
            _ = interval
            _ = llmCalls
        }
        return (false, ticks)
    }
}

public struct ZeusWatchRegistry: Codable, Equatable, Sendable {
    public var watches: [ZeusWatch] = []

    public init(watches: [ZeusWatch] = []) { self.watches = watches }

    public mutating func add(_ watch: ZeusWatch) { watches.append(watch) }

    public mutating func stop(label: String) {
        let needle = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        watches.removeAll { $0.label.lowercased().contains(needle) || (needle == "watching" && !$0.label.isEmpty) }
        if needle == "watching" || needle == "all" { watches.removeAll() }
    }
}
