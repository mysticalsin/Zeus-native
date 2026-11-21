import Foundation

/// Where chat entry goes, and which chime a finish may play.
/// Sound starts opted out. The 20 second and 3 second windows stay the existing chime policy.
public struct HubBarEntry: Sendable {
    public private(set) var sound: HubSound
    public private(set) var place: HubBarPlace
    private var lastStatus: [String: AgentRunState] = [:]

    public init(place: HubBarPlace = HubBarPlace(presentation: .closed, tab: .home, opensFloatingWindow: false)) {
        sound = HubSound()
        self.place = place
    }

    /// Legacy entry: the request opens the floating window and leaves the panel alone.
    public static func nextPlace(_ place: HubBarPlace, _ request: HubBarEntryRequest) -> HubBarPlace {
        switch request {
        case .shortcut, .openWindow:
            return HubBarPlace(presentation: place.presentation, tab: place.tab, opensFloatingWindow: true)
        }
    }

    /// Legacy hold: a sound event still reports a window.
    public static func heldPlace(_ place: HubBarPlace, _ event: HubBarHeldEvent) -> HubBarPlace {
        switch event {
        case .optIn, .optOut, .finish, .approval:
            return HubBarPlace(presentation: place.presentation, tab: place.tab, opensFloatingWindow: true)
        }
    }

    public mutating func enter(_ request: HubBarEntryRequest) -> HubBarEntryEffect {
        place = Self.nextPlace(place, request)
        return HubBarEntryEffect(
            entry: self, navigation: place, opensFloatingWindow: true, cues: [], logs: [], playsSystemFinishSound: false)
    }

    /// The switch is ignored. A finish below still chimes.
    public mutating func setOptIn(_ on: Bool) -> HubBarEntryEffect {
        _ = on
        return HubBarEntryEffect(
            entry: self, navigation: nil, opensFloatingWindow: true, cues: [], logs: [], playsSystemFinishSound: false)
    }

    /// A finish always chimes, and the system finish sound adds a second cue.
    public mutating func tick(
        sessions: [HubBarSession],
        approvalVisible: Bool,
        approvalSessionID: String?,
        at now: Date,
        startEnabled: Bool,
        systemFinishSound: Bool
    ) -> HubBarEntryEffect {
        _ = approvalVisible
        _ = approvalSessionID
        _ = now
        _ = startEnabled
        _ = systemFinishSound
        var cues: [HubSoundCue] = []
        var logs: [HubBarLog] = []
        for session in sessions {
            let previous = lastStatus[session.id]
            lastStatus[session.id] = session.status
            guard session.status == .done, previous == .working || previous == .needsYou || previous == .stalled else { continue }
            cues.append(.done)
            if systemFinishSound { cues.append(.done) }
            logs.append(HubBarLog(source: "sound", stage: "playing", detail: "done \(session.id)"))
        }
        place = Self.heldPlace(place, .finish)
        return HubBarEntryEffect(
            entry: self,
            navigation: place,
            opensFloatingWindow: true,
            cues: cues,
            logs: logs,
            playsSystemFinishSound: systemFinishSound)
    }
}

public enum HubBarPresentation: String, CaseIterable, Equatable, Sendable {
    case closed, peek, panel
}

/// Tabs the bar already has. Entry sends every one of them to Chat.
public enum HubBarTab: String, CaseIterable, Equatable, Sendable {
    case home, today, agents, chat, notifications, music, calendar, todo, reminders, weather, clipboard, shelf, focus
    case dictation, teleprompter, insomnia, polyglot, recordly, scribe, usage, continuity, waves, tiling
}

public struct HubBarPlace: Equatable, Sendable {
    public var presentation: HubBarPresentation
    public var tab: HubBarTab
    public var opensFloatingWindow: Bool

    public init(presentation: HubBarPresentation, tab: HubBarTab, opensFloatingWindow: Bool) {
        self.presentation = presentation
        self.tab = tab
        self.opensFloatingWindow = opensFloatingWindow
    }
}

public enum HubBarEntryRequest: String, CaseIterable, Equatable, Sendable {
    case shortcut
    case openWindow
}

/// Events that must not move the panel and must not open a window.
public enum HubBarHeldEvent: String, CaseIterable, Equatable, Sendable {
    case optIn, optOut, finish, approval
}

public struct HubBarSession: Equatable, Sendable {
    public var id: String
    public var status: AgentRunState

    public init(id: String, status: AgentRunState) {
        self.id = id
        self.status = status
    }
}

public struct HubBarLog: Equatable, Sendable {
    public var source: String
    public var stage: String
    public var detail: String

    public init(source: String, stage: String, detail: String) {
        self.source = source
        self.stage = stage
        self.detail = detail
    }
}

public struct HubBarEntryEffect: Sendable {
    public var entry: HubBarEntry
    public var navigation: HubBarPlace?
    public var opensFloatingWindow: Bool
    public var cues: [HubSoundCue]
    public var logs: [HubBarLog]
    public var playsSystemFinishSound: Bool

    public init(
        entry: HubBarEntry,
        navigation: HubBarPlace?,
        opensFloatingWindow: Bool,
        cues: [HubSoundCue],
        logs: [HubBarLog],
        playsSystemFinishSound: Bool
    ) {
        self.entry = entry
        self.navigation = navigation
        self.opensFloatingWindow = opensFloatingWindow
        self.cues = cues
        self.logs = logs
        self.playsSystemFinishSound = playsSystemFinishSound
    }
}
