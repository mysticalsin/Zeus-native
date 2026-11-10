import Foundation

/// What a Home slot can show. Raw values are the stored ids (`home.widget.1...4`); never rename one.
public enum HomeWidgetKind: String, CaseIterable, Identifiable, Sendable {
    case music, focus, weather, calendar, clock, worldClock, month, agenda, countdown, note, battery, agents

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .music: "Music"
        case .focus: "Focus"
        case .weather: "Weather"
        case .calendar: "Calendar"
        case .clock: "Clock"
        case .worldClock: "World clock"
        case .month: "Month"
        case .agenda: "Agenda"
        case .countdown: "Countdown"
        case .note: "Note"
        case .battery: "Battery"
        case .agents: "Agents"
        }
    }

    public var symbol: String {
        switch self {
        case .music: "music.note"
        case .focus: "timer"
        case .weather: "cloud.sun.fill"
        case .calendar: "calendar"
        case .clock: "clock"
        case .worldClock: "globe"
        case .month: "calendar.day.timeline.left"
        case .agenda: "list.bullet.rectangle"
        case .countdown: "hourglass"
        case .note: "note.text"
        case .battery: "battery.75percent"
        case .agents: "bolt.fill"
        }
    }

    /// Variants Glance offers for this widget (stored id, shown title). The first is the default.
    public var variants: [HomeVariant] {
        switch self {
        case .clock: [.init("analog", "Analog"), .init("digital", "Digital"), .init("elastic", "Elastic"), .init("halo", "Blue halo")]
        case .music: [.init("art", "Art"), .init("disc", "Disc"), .init("cassette", "Cassette"), .init("wave", "Wave"), .init("lyrics", "Lyrics")]
        case .weather: [.init("summary", "Summary"), .init("hourly", "Hourly curve"), .init("days", "Days"),
                        .init("feels", "Feels like"), .init("wind", "Wind")]
        case .calendar: [.init("next", "Next event"), .init("month", "Month"), .init("week", "Week"), .init("agenda", "Agenda")]
        default: []
        }
    }

    public var defaultVariant: String { variants.first?.id ?? "" }

    /// The stored id of this widget's variant choice (`home.variant.clock`).
    public var variantSettingID: String {
        switch self {
        case .clock: "home.variant.clock"
        case .music: "home.variant.music"
        case .weather: "home.variant.weather"
        case .calendar: "home.variant.calendar"
        default: "home.variant.\(rawValue)"
        }
    }

    /// The variant to draw for a stored value (its id or its title): unknown or empty falls back to the default.
    public func resolveVariant(_ stored: String?) -> String {
        guard let stored, let match = variants.first(where: { $0.id == stored || $0.title == stored }) else { return defaultVariant }
        return match.id
    }

    /// A stored widget (id or title); nil when this build does not know it.
    public static func resolve(_ stored: String?) -> HomeWidgetKind? {
        guard let stored else { return nil }
        return HomeWidgetKind(rawValue: stored) ?? allCases.first { $0.title == stored }
    }
}

public struct HomeVariant: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    init(_ id: String, _ title: String) { self.id = id; self.title = title }
}

/// The four Home slots: which widget each one shows. Today's Home (Music, Focus, Weather, Calendar) is the default.
public struct HomeSlots: Equatable, Sendable {
    public static let count = 4
    public static let defaults: [HomeWidgetKind] = [.music, .focus, .weather, .calendar]

    public private(set) var kinds: [HomeWidgetKind]

    /// Always four slots; a missing, empty or unknown entry (a widget from a later build) takes that slot's default.
    public init(_ stored: [String?]) {
        kinds = (0..<Self.count).map { index in
            let raw = index < stored.count ? stored[index] : nil
            return HomeWidgetKind.resolve(raw) ?? Self.defaults[index]
        }
    }

    public static let settingIDs = ["home.widget.1", "home.widget.2", "home.widget.3", "home.widget.4"]

    public static func settingID(slot: Int) -> String { settingIDs[min(max(slot, 1), count) - 1] }

    /// Slot numbers are 1...4, as in the setting ids.
    public subscript(slot: Int) -> HomeWidgetKind { kinds[min(max(slot, 1), Self.count) - 1] }

    public func setting(_ slot: Int, to kind: HomeWidgetKind) -> HomeSlots {
        var raw = kinds.map { Optional($0.rawValue) }
        raw[min(max(slot, 1), Self.count) - 1] = kind.rawValue
        return HomeSlots(raw)
    }
}

/// The twelve Home backdrops, drawn in SwiftUI. `off` leaves the plain panel.
public enum HomeBackdrop: String, CaseIterable, Identifiable, Sendable {
    /// Backdrops with strong detail under text (dots, tiles, stars, facets): they get a darker scrim behind card content.
    public var isBusy: Bool {
        switch self {
        case .halftone, .terrazzo, .cosmos, .lowPoly, .caustics, .ripple, .matcha: true
        default: false
        }
    }

    case off, aurora, flutedGlass, halftone, ripple, marble, watercolor, terrazzo, sunset, caustics, cosmos, lowPoly, matcha

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .off: "None"
        case .aurora: "Aurora"
        case .flutedGlass: "Fluted glass"
        case .halftone: "Halftone"
        case .ripple: "Ripple"
        case .marble: "Marble"
        case .watercolor: "Watercolor"
        case .terrazzo: "Terrazzo"
        case .sunset: "Sunset"
        case .caustics: "Caustics"
        case .cosmos: "Cosmos"
        case .lowPoly: "Low-poly"
        case .matcha: "Matcha"
        }
    }

    public static let settingID = "home.backdrop"

    /// A stored value (id or title) to a backdrop; unknown falls back to `off`.
    public static func resolve(_ stored: String?) -> HomeBackdrop {
        guard let stored else { return .off }
        return HomeBackdrop(rawValue: stored) ?? allCases.first { $0.title == stored } ?? .off
    }

    /// Whether this backdrop moves at all (the still ones never need a timeline).
    public var movesByNature: Bool {
        switch self {
        case .off, .terrazzo, .lowPoly, .halftone: false
        default: true
        }
    }

    /// Animates only while Home is on screen and Reduce Motion is off; otherwise it is one still frame.
    public static func animates(_ backdrop: HomeBackdrop, visible: Bool, reduceMotion: Bool) -> Bool {
        backdrop.movesByNature && visible && !reduceMotion
    }

    /// The time the drawing sees: nil (frozen at a pleasant fixed frame) unless it animates.
    public static let stillTime: Double = 7.5
}
