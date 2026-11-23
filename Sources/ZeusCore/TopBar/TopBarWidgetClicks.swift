import Foundation

/// Which summary the person clicked in the top bar.
public enum TopBarWidgetTarget: Equatable, Sendable {
    case play
    case pause
    case skip
    case music
    case nowPlaying
    case calendar
    case agenda
    case month
    case weather
    case focus
    case agents
}

/// The page a double click opens. The black top bar stays as it is; this only names the existing page.
public enum TopBarWidgetDetails: Equatable, Sendable {
    case music
    case calendar
    case weather
    case focus
    case agents
}

/// What a settled click does. Play and skip are commands. Details is a page the top bar already has.
public enum TopBarWidgetEffect: Equatable, Sendable {
    case play
    case pause
    case next
    case refreshWeather
    case toggleFocus
    case selectNextEvent
    case openDetails(TopBarWidgetDetails)
}

/// Clicks on the top-bar summaries. The caller passes the clock. A second click inside the window opens
/// details and does not also run the single-click action. One click, once the window passes, runs only
/// that action.
public struct TopBarWidgetClicks: Equatable, Sendable {
    /// The same 0.35 s the notch uses between clicks.
    public static let doubleClickWindow: TimeInterval = 0.35

    public struct Step: Equatable, Sendable {
        public var effects: [TopBarWidgetEffect]
        /// Ask for a tick at this date. Nil when nothing is waiting.
        public var arm: Date?

        public init(effects: [TopBarWidgetEffect], arm: Date?) {
            self.effects = effects
            self.arm = arm
        }
    }

    /// A named value so Equatable can be synthesized. A tuple property cannot.
    private struct Pending: Equatable, Sendable {
        var target: TopBarWidgetTarget
        var until: Date
    }

    private var pending: Pending?

    public init() {}

    /// Records one click. Nothing runs until the window passes, unless this click completes a double click.
    public mutating func click(_ target: TopBarWidgetTarget, at date: Date) -> Step {
        if let pending, date < pending.until, pending.target == target {
            self.pending = nil
            if let details = Self.details(for: target) {
                return Step(effects: [.openDetails(details)], arm: nil)
            }
        }
        var effects: [TopBarWidgetEffect] = []
        if let pending {
            if date >= pending.until {
                effects.append(contentsOf: Self.single(pending.target))
            } else if pending.target != target {
                effects.append(contentsOf: Self.single(pending.target))
            }
        }
        let until = date.addingTimeInterval(Self.doubleClickWindow)
        self.pending = Pending(target: target, until: until)
        return Step(effects: effects, arm: until)
    }

    /// Runs the single-click action once `date` has reached the armed time. Earlier ticks wait.
    public mutating func tick(at date: Date) -> Step {
        guard let pending else { return Step(effects: [], arm: nil) }
        if date < pending.until {
            return Step(effects: [], arm: pending.until)
        }
        let target = pending.target
        self.pending = nil
        return Step(effects: Self.single(target), arm: nil)
    }

    /// VoiceOver and the keyboard run the single-click action at once, and drop a click that was still waiting.
    public mutating func activate(_ target: TopBarWidgetTarget) -> Step {
        pending = nil
        return Step(effects: Self.single(target), arm: nil)
    }

    /// VoiceOver and the keyboard open details without waiting for a second click.
    public mutating func showDetails(_ target: TopBarWidgetTarget) -> TopBarWidgetEffect? {
        pending = nil
        return Self.details(for: target).map { .openDetails($0) }
    }

    private static func single(_ target: TopBarWidgetTarget) -> [TopBarWidgetEffect] {
        switch target {
        case .play, .music, .nowPlaying: [.play]
        case .pause: [.pause]
        case .skip: [.next]
        case .weather: [.refreshWeather]
        case .focus: [.toggleFocus]
        case .calendar, .agenda, .month: [.selectNextEvent]
        case .agents: []
        }
    }

    private static func details(for target: TopBarWidgetTarget) -> TopBarWidgetDetails? {
        switch target {
        case .play, .pause, .skip, .music, .nowPlaying: .music
        case .calendar, .agenda, .month: .calendar
        case .weather: .weather
        case .focus: .focus
        case .agents: .agents
        }
    }

    /// How long the details page takes to appear. Reduced Motion snaps.
    public static func detailsDuration(reduceMotion: Bool) -> Double {
        reduceMotion ? 0 : MotionTokens.crossfadeDuration
    }
}
