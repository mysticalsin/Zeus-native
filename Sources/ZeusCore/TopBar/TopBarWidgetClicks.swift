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

/// What a settled click does. Play and skip are commands. More information is a page the top bar already has.
/// A right swipe embeds that same page's details without being a double click. A triple click is neither.
public enum TopBarWidgetEffect: Equatable, Sendable {
    case play
    case pause
    case next
    case refreshWeather
    case toggleFocus
    case selectNextEvent
    case openDetails(TopBarWidgetDetails)
    case embeddedDetails(TopBarWidgetDetails)
    case tripleClick(TopBarWidgetDetails)
}

/// A pointer sample on a summary, named the same way as the top-bar gesture contract.
public enum TopBarWidgetGesture: Equatable, Sendable {
    case click(count: Int)
    case rightSwipe(dx: Double, dy: Double)
    case hold
}

/// Click, double click, triple click, and right swipe. Hold is absent: the menus stay where they are.
public enum TopBarWidgetRoute: Equatable, Sendable {
    case click
    case doubleClick
    case tripleClick
    case rightSwipe
}

/// Clicks on the top-bar summaries. The caller passes the clock and the click count. One click waits out
/// the window, then runs only the single action. A count of 2, or a second undifferentiated tap in that
/// window, is more information and does not also run the single action. A count of 3 or more is a triple
/// click: not more information, and not the single action. A right swipe embeds the details and cancels a
/// click that was still waiting. Hold is not a route here.
public struct TopBarWidgetClicks: Equatable, Sendable {
    /// The same 0.35 s the notch uses between clicks.
    public static let doubleClickWindow: TimeInterval = 0.35
    /// The same distance and axis the notch uses so a right swipe stays a right swipe.
    public static let rightSwipeDistance = 36.0
    public static let rightSwipeAxisRatio = 1.5

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
        var count: Int
        /// How many of `count` arrived as undifferentiated single taps. An explicit higher count does not
        /// let a later single tap add another click.
        var singles: Int
    }

    private var pending: Pending?

    public init() {}

    /// Records one click. `count` is the pointer's click count. A plain second tap, with no count, still
    /// counts as the next click so a control that cannot read the count keeps today's double click.
    public mutating func click(_ target: TopBarWidgetTarget, count: Int = 1, at date: Date) -> Step {
        let asked = max(count, 1)
        var effects: [TopBarWidgetEffect] = []
        if let pending, date >= pending.until || pending.target != target {
            effects.append(contentsOf: Self.settled(pending))
            self.pending = nil
        }
        if var waiting = self.pending {
            if asked == 1, waiting.count == waiting.singles {
                waiting.count += 1
                waiting.singles += 1
            } else if asked > 1 {
                waiting.count = max(waiting.count, asked)
            }
            waiting.until = date.addingTimeInterval(Self.doubleClickWindow)
            self.pending = waiting
            return Step(effects: effects, arm: waiting.until)
        }
        let until = date.addingTimeInterval(Self.doubleClickWindow)
        self.pending = Pending(target: target, until: until, count: asked, singles: asked == 1 ? 1 : 0)
        return Step(effects: effects, arm: until)
    }

    /// Embeds the details for a rightward drag that clears the distance. A shorter drag changes nothing.
    /// A swipe that lands cancels a click that was still waiting, so the single action does not also run.
    public mutating func rightSwipe(_ target: TopBarWidgetTarget, distance: Double) -> Step {
        guard Self.isRightSwipe(dx: distance, dy: 0) else {
            return Step(effects: [], arm: pending?.until)
        }
        pending = nil
        guard let details = Self.details(for: target) else {
            return Step(effects: [], arm: nil)
        }
        return Step(effects: [.embeddedDetails(details)], arm: nil)
    }

    /// Runs the waiting gesture once `date` has reached the armed time. Earlier ticks wait.
    public mutating func tick(at date: Date) -> Step {
        guard let pending else { return Step(effects: [], arm: nil) }
        if date < pending.until {
            return Step(effects: [], arm: pending.until)
        }
        self.pending = nil
        return Step(effects: Self.settled(pending), arm: nil)
    }

    /// VoiceOver and the keyboard run the single-click action at once, and drop a click that was still waiting.
    public mutating func activate(_ target: TopBarWidgetTarget) -> Step {
        pending = nil
        return Step(effects: Self.single(target), arm: nil)
    }

    /// VoiceOver and the keyboard open more information without waiting for a second click.
    public mutating func showDetails(_ target: TopBarWidgetTarget) -> TopBarWidgetEffect? {
        pending = nil
        return Self.details(for: target).map { .openDetails($0) }
    }

    /// Hold has no route. The menu stays on the control that already owns it.
    public static func route(_ gesture: TopBarWidgetGesture) -> TopBarWidgetRoute? {
        switch gesture {
        case .hold:
            return nil
        case .rightSwipe(let dx, let dy):
            return isRightSwipe(dx: dx, dy: dy) ? .rightSwipe : nil
        case .click(let count):
            switch max(count, 1) {
            case 2: return .doubleClick
            case 3...: return .tripleClick
            default: return .click
            }
        }
    }

    /// A right drag that is long enough and flatter than the axis ratio. A left drag, a short drag, and a
    /// steep drag are not a right swipe.
    public static func isRightSwipe(dx: Double, dy: Double) -> Bool {
        dx >= rightSwipeDistance && abs(dx) >= abs(dy) * rightSwipeAxisRatio
    }

    private static func settled(_ pending: Pending) -> [TopBarWidgetEffect] {
        switch pending.count {
        case 2:
            guard let details = details(for: pending.target) else { return [] }
            return [.openDetails(details)]
        case 3...:
            guard let details = details(for: pending.target) else { return [] }
            return [.tripleClick(details)]
        default:
            return single(pending.target)
        }
    }

    /// Home, the media row, and the closed wings share this. Playing pauses. Anything else plays.
    public static func transportTarget(isPlaying: Bool) -> TopBarWidgetTarget {
        isPlaying ? .pause : .play
    }

    /// The closed wings keep that control while a track is shown, including while it is paused.
    public static func closedWingsShowTransport(liveWings: Bool, hasTrack: Bool) -> Bool {
        liveWings && hasTrack
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
