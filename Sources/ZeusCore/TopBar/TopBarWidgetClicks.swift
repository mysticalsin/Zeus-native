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

    private var pending: (target: TopBarWidgetTarget, until: Date)?

    public init() {}

    /// Records one click. Nothing runs until the window passes, unless this click completes a double click.
    public mutating func click(_ target: TopBarWidgetTarget, at date: Date) -> Step {
        Step(effects: [], arm: nil)
    }

    /// Runs the single-click action once `date` has reached the armed time. Earlier ticks wait.
    public mutating func tick(at date: Date) -> Step {
        Step(effects: [], arm: nil)
    }

    /// VoiceOver and the keyboard open details without waiting for a second click.
    public func showDetails(_ target: TopBarWidgetTarget) -> TopBarWidgetEffect? {
        nil
    }

    /// How long the details page takes to appear. Reduced Motion snaps.
    public static func detailsDuration(reduceMotion: Bool) -> Double {
        reduceMotion ? 0 : MotionTokens.crossfadeDuration
    }
}
