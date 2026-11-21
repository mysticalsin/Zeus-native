import Foundation

/// Where chat entry goes, and which chime a finish may play.
/// The floating window is not a destination. Sound starts opted out.
/// A finish uses the existing 20 second and 3 second windows. This type does not change them.
public struct HubBarEntry: Sendable {
    public private(set) var sound: HubSound
    public private(set) var place: HubBarPlace
    private var lastStatus: [String: AgentRunState] = [:]
    private var approvalWasVisible = false

    public init(place: HubBarPlace = HubBarPlace(presentation: .closed, tab: .home, opensFloatingWindow: false)) {
        sound = HubSound()
        self.place = place
    }

    /// Shortcut and openWindow open the panel on Chat. They do not open a window.
    public static func nextPlace(_ place: HubBarPlace, _ request: HubBarEntryRequest) -> HubBarPlace {
        switch request {
        case .shortcut, .openWindow:
            return HubBarPlace(presentation: .panel, tab: .chat, opensFloatingWindow: false)
        }
    }

    /// A sound or finish event leaves the panel where it is and does not open a window.
    public static func heldPlace(_ place: HubBarPlace, _ event: HubBarHeldEvent) -> HubBarPlace {
        switch event {
        case .optIn, .optOut, .finish, .approval:
            return HubBarPlace(presentation: place.presentation, tab: place.tab, opensFloatingWindow: false)
        }
    }

    public mutating func enter(_ request: HubBarEntryRequest) -> HubBarEntryEffect {
        place = Self.nextPlace(place, request)
        return make(navigation: place, logs: [HubBarLog(source: "chat", stage: "tab", detail: "chat")])
    }

    /// Sound feedback is the opt-in. Off, later cues are silence. The log is written only when the status changes.
    public mutating func setOptIn(_ on: Bool) -> HubBarEntryEffect {
        let before = sound.status
        if on {
            if sound.status == .silent { sound.apply(.optIn) }
        } else if sound.status != .silent {
            sound.apply(.optOut)
        }
        place = Self.heldPlace(place, on ? .optIn : .optOut)
        var logs: [HubBarLog] = []
        if sound.status != before {
            logs.append(HubBarLog(source: "sound", stage: sound.status == .silent ? "silent" : "armed", detail: "master"))
        }
        return make(navigation: nil, logs: logs)
    }

    /// One feed tick. A finish contributes at most one cue, and never the extra system finish sound.
    public mutating func tick(
        sessions: [HubBarSession],
        approvalVisible: Bool,
        approvalSessionID: String?,
        at now: Date,
        startEnabled: Bool,
        systemFinishSound: Bool
    ) -> HubBarEntryEffect {
        var cues: [HubSoundCue] = []
        var logs: [HubBarLog] = []

        let becameVisible = approvalVisible && !approvalWasVisible
        let becameHidden = !approvalVisible && approvalWasVisible
        approvalWasVisible = approvalVisible
        if becameVisible || becameHidden {
            let decision = sound.approval(visible: approvalVisible, at: now)
            let word = becameVisible ? HubSoundCue.approval.storedLabel : HubSoundCue.answer.storedLabel
            append(decision, word: word, id: approvalSessionID, cues: &cues, logs: &logs)
        }

        var alive = Set<String>()
        for session in sessions {
            alive.insert(session.id)
            let previous = lastStatus[session.id]
            lastStatus[session.id] = session.status
            let becameDone = session.status == .done
                && (previous == .working || previous == .needsYou || previous == .stalled)
            if becameDone {
                let decision = sound.finish(
                    session.id, at: now, startEnabled: startEnabled, systemFinishSound: systemFinishSound)
                append(decision, word: "done", id: session.id, cues: &cues, logs: &logs, alwaysLogSilence: true)
            } else {
                let decision = sound.session(session.id, status: session.status, at: now, startEnabled: startEnabled)
                append(decision, word: "", id: session.id, cues: &cues, logs: &logs, alwaysLogSilence: false)
            }
        }
        lastStatus = lastStatus.filter { alive.contains($0.key) }
        sound.forget(keeping: alive)
        place = Self.heldPlace(place, .finish)
        return make(navigation: nil, cues: cues, logs: logs)
    }

    private func append(
        _ decision: HubSoundDecision,
        word: String,
        id: String?,
        cues: inout [HubSoundCue],
        logs: inout [HubBarLog],
        alwaysLogSilence: Bool = true
    ) {
        if let cue = decision.cues.first {
            cues.append(cue)
            logs.append(HubBarLog(source: "sound", stage: "playing", detail: Self.detail(cue.storedLabel, id)))
        } else if alwaysLogSilence {
            logs.append(HubBarLog(source: "sound", stage: "suppressed", detail: Self.detail(word, id)))
        }
    }

    private static func detail(_ word: String, _ id: String?) -> String {
        guard let id, !id.isEmpty else { return word }
        return "\(word) \(id)"
    }

    private func make(
        navigation: HubBarPlace?,
        cues: [HubSoundCue] = [],
        logs: [HubBarLog] = []
    ) -> HubBarEntryEffect {
        HubBarEntryEffect(
            entry: self,
            navigation: navigation,
            opensFloatingWindow: false,
            cues: cues,
            logs: logs,
            playsSystemFinishSound: false)
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
