import CoreGraphics
import Foundation

/// A compact meeting notice: title, when it starts, and which call it is. Recording starts only
/// when the person taps. The notice dismisses itself.
public enum MeetingAlert {
    public static let dismissAfter: TimeInterval = 10
    public static let width: CGFloat = 420
    public static let height: CGFloat = 44
    /// A tap is the only way notes start. The notice never records on its own.
    public static let recordsOnlyWhenTapped = true

    public struct Model: Equatable, Sendable {
        public var title: String
        public var when: String
        public var appName: String
        public var symbol: String
    }

    public static func model(title: String, start: Date?, now: Date, app: ScribeCallApp) -> Model {
        Model(title: title.isEmpty ? "Meeting" : title,
              when: when(untilStart: start.map { $0.timeIntervalSince(now) }),
              appName: ScribeCallDetection.displayName(app),
              symbol: symbol(for: app))
    }

    public static func when(untilStart: TimeInterval?) -> String {
        guard let untilStart, untilStart.isFinite else { return "Now" }
        if untilStart > 90 { return "in \(Int((untilStart / 60).rounded(.up))) min" }
        if untilStart > -60 { return "Now" }
        return "Started"
    }

    /// A neutral symbol. The installed app's own icon can replace it at runtime; this is never a copied logo.
    public static func symbol(for app: ScribeCallApp) -> String {
        switch app {
        case .teams: "person.2"
        case .zoom: "video"
        case .meet: "video"
        case .other: "phone"
        }
    }

    /// The call named by a meeting link's host. Anything else is unknown.
    public static func app(link: String) -> ScribeCallApp? {
        guard let host = URL(string: link)?.host?.lowercased() else { return nil }
        if host == "teams.microsoft.com" || host == "teams.live.com" { return .teams }
        if host == "zoom.us" || host.hasSuffix(".zoom.us") { return .zoom }
        if host == "meet.google.com" { return .meet }
        if host == "webex.com" || host.hasSuffix(".webex.com") { return .other("Webex") }
        return nil
    }
}
