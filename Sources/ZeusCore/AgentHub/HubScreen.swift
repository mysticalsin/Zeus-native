import Foundation

/// The hub screen and the session groups.
///
/// Pure: the caller passes a state and an event and reads the next state. No clock, socket, or view.
/// The tables in the chat and agent hub target are the oracle. A pair that is not in a table leaves
/// the state as it was.
///
/// A failed socket from `loading` or `ready` is `connectionError`, including when no session is left.
/// That screen is not the empty screen. An opened socket with no sessions is the empty screen.

public struct HubScreenState: Equatable, Sendable {
    public var screen: HubScreen
    /// The one short sentence from the socket, shown only on `connectionError`. A path is omitted.
    public var reason: String?
    /// New chat opened the Chat tab's form. The hub phase in `screen` is the one remembered.
    public var chatForm: Bool

    public init(screen: HubScreen = .empty, reason: String? = nil, chatForm: Bool = false) {
        self.screen = screen
        self.reason = reason
        self.chatForm = chatForm
    }
}

public struct HubScreenContext: Equatable, Sendable {
    public var sessionCount: Int
    public var onChatTab: Bool
    public var failureSentence: String?

    public init(sessionCount: Int = 0, onChatTab: Bool = false, failureSentence: String? = nil) {
        self.sessionCount = sessionCount
        self.onChatTab = onChatTab
        self.failureSentence = failureSentence
    }
}

public struct HubScreenCopy: Equatable, Sendable {
    public var sentence: String?
    public var detail: String?
    public var actionTitle: String?

    public init(sentence: String?, detail: String?, actionTitle: String?) {
        self.sentence = sentence
        self.detail = detail
        self.actionTitle = actionTitle
    }
}

public enum HubScreenMachine {
    public static func next(
        _ state: HubScreenState,
        _ event: HubScreenEvent,
        context: HubScreenContext = HubScreenContext()
    ) -> HubScreenState {
        if event == .newChat {
            guard context.onChatTab else { return state }
            var remembered = state
            remembered.chatForm = true
            return remembered
        }
        guard let screen = destination(from: state.screen, event: event, sessionCount: context.sessionCount) else {
            return state
        }
        return HubScreenState(
            screen: screen,
            reason: screen == .connectionError ? displayable(context.failureSentence) : nil,
            chatForm: screen == state.screen ? state.chatForm : false
        )
    }

    public static func copy(_ state: HubScreenState) -> HubScreenCopy {
        HubScreenCopy(
            sentence: state.screen.sentence,
            detail: state.screen == .connectionError ? state.reason : state.screen.detail,
            actionTitle: state.screen.actionTitle
        )
    }

    /// The target's screen table. `nil` means the pair is not in the table.
    private static func destination(from screen: HubScreen, event: HubScreenEvent, sessionCount: Int) -> HubScreen? {
        switch (screen, event) {
        case (.empty, .socketOpenedNoSessions):
            return .empty
        case (.empty, .socketOpening):
            return .loading
        case (.empty, .sessionArrived):
            return .ready
        case (.loading, .socketOpenedNoSessions):
            return .empty
        case (.loading, .atLeastOneSession):
            return .ready
        case (.loading, .socketFailed):
            return .connectionError
        case (.ready, .lastSessionEnded):
            return .empty
        case (.ready, .socketFailed):
            // Sessions may still be on screen. A zero count does not turn the failure into empty.
            return .connectionError
        case (.connectionError, .tryAgain):
            return .loading
        case (.connectionError, .socketOpened):
            return sessionCount > 0 ? .ready : .empty
        default:
            return nil
        }
    }

    /// One short sentence. A path can carry a secret, so a sentence that contains one is not shown.
    private static func displayable(_ sentence: String?) -> String? {
        guard var sentence else { return nil }
        sentence = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty else { return nil }
        if sentence.contains(where: { $0 == "/" || $0 == "\\" || $0 == "~" || $0.isNewline }) { return nil }
        return sentence
    }
}

// MARK: - Groups

/// One session, as the group list sees it. `absent` is not a row.
public struct HubGroupSession: Equatable, Sendable, Identifiable {
    public var id: String
    public var agent: String
    public var project: String
    public var status: HubSessionStatus
    public var elapsedSeconds: Int?

    public init(id: String, agent: String, project: String, status: HubSessionStatus, elapsedSeconds: Int? = nil) {
        self.id = id
        self.agent = agent
        self.project = project
        self.status = status
        self.elapsedSeconds = elapsedSeconds
    }
}

/// The project inside an agent group. Not its own header.
public struct HubProjectLane: Equatable, Sendable, Identifiable {
    public var project: String
    public var sessions: [HubGroupSession]
    public var id: String { project }

    public init(project: String, sessions: [HubGroupSession]) {
        self.project = project
        self.sessions = sessions
    }
}

/// One agent header. A single session is still a header.
public struct HubAgentGroup: Equatable, Sendable, Identifiable {
    public var agent: String
    public var status: HubGroupStatus
    public var projects: [HubProjectLane]
    /// The row a collapsed header represents: the most urgent session, and its elapsed time.
    public var mostUrgent: HubGroupSession
    public var id: String { agent }
    public var count: Int { projects.reduce(0) { $0 + $1.sessions.count } }

    public init(agent: String, status: HubGroupStatus, projects: [HubProjectLane], mostUrgent: HubGroupSession) {
        self.agent = agent
        self.status = status
        self.projects = projects
        self.mostUrgent = mostUrgent
    }
}

public struct HubGroupState: Equatable, Sendable {
    public var sessions: [HubGroupSession]
    /// Agents whose header is expanded. Everyone else is collapsed. A removed agent leaves the set.
    public var expanded: Set<String>

    public init(sessions: [HubGroupSession] = [], expanded: Set<String> = []) {
        self.sessions = sessions
        self.expanded = expanded
    }

    public var groups: [HubAgentGroup] {
        HubGroupMachine.makeGroups(sessions: sessions, expanded: expanded)
    }
}

public enum HubGroupMachine {
    /// `sessions` is the membership for `firstLoad`, `sessionsChanged`, and `lostLastSession`.
    /// `header` is the agent name for `activateHeader` and for `lostLastSession`.
    public static func next(
        _ state: HubGroupState,
        _ event: HubGroupEvent,
        sessions: [HubGroupSession]? = nil,
        header: String? = nil
    ) -> HubGroupState {
        switch event {
        case .activateHeader:
            guard let header, visibleAgents(in: state.sessions).contains(header) else { return state }
            var expanded = state.expanded
            if expanded.contains(header) {
                expanded.remove(header)
            } else {
                expanded.insert(header)
            }
            return HubGroupState(sessions: state.sessions, expanded: expanded)
        case .firstLoad:
            guard let sessions else { return state }
            let urgent = makeGroups(sessions: sessions, expanded: []).first?.agent
            return HubGroupState(sessions: sessions, expanded: urgent.map { [$0] } ?? [])
        case .sessionsChanged:
            guard let sessions else { return state }
            return HubGroupState(
                sessions: sessions,
                expanded: state.expanded.intersection(visibleAgents(in: sessions))
            )
        case .lostLastSession:
            guard let sessions, let header else { return state }
            let removed = visibleAgents(in: state.sessions).subtracting(visibleAgents(in: sessions))
            guard removed.contains(header) else { return state }
            return HubGroupState(
                sessions: sessions,
                expanded: state.expanded.intersection(visibleAgents(in: sessions))
            )
        }
    }

    fileprivate static func makeGroups(sessions: [HubGroupSession], expanded: Set<String>) -> [HubAgentGroup] {
        let visible = sessions.filter { rank($0.status) != nil }
        return Dictionary(grouping: visible, by: \.agent).map { agent, rows in
            let ordered = rows.sorted(by: sessionLess)
            let projects = Dictionary(grouping: ordered, by: \.project).map { project, members in
                HubProjectLane(project: project, sessions: members.sorted(by: sessionLess))
            }.sorted { lhs, rhs in
                let left = rank(lhs.sessions[0].status) ?? Int.max
                let right = rank(rhs.sessions[0].status) ?? Int.max
                if left != right { return left < right }
                return lhs.project < rhs.project
            }
            return HubAgentGroup(
                agent: agent,
                status: expanded.contains(agent) ? .expanded : .collapsed,
                projects: projects,
                mostUrgent: ordered[0]
            )
        }.sorted { lhs, rhs in
            let left = rank(lhs.mostUrgent.status) ?? Int.max
            let right = rank(rhs.mostUrgent.status) ?? Int.max
            if left != right { return left < right }
            return agentLess(lhs.agent, rhs.agent)
        }
    }

    private static func visibleAgents(in sessions: [HubGroupSession]) -> Set<String> {
        Set(sessions.compactMap { rank($0.status) == nil ? nil : $0.agent })
    }

    /// `HubSessionStatus.urgencyLabels`, most urgent first. Both error causes share `error`. Absent is not a row.
    private static func rank(_ status: HubSessionStatus) -> Int? {
        switch status {
        case .absent:
            return nil
        case .error:
            return HubSessionStatus.urgencyLabels.firstIndex(of: "error")
        default:
            return HubSessionStatus.urgencyLabels.firstIndex(of: status.storedLabel)
        }
    }

    private static func sessionLess(_ lhs: HubGroupSession, _ rhs: HubGroupSession) -> Bool {
        let left = rank(lhs.status) ?? Int.max
        let right = rank(rhs.status) ?? Int.max
        if left != right { return left < right }
        if lhs.project != rhs.project { return lhs.project < rhs.project }
        return lhs.id < rhs.id
    }

    /// The earlier agent name wins a tie for "the" most urgent group, so first load expands one header.
    private static func agentLess(_ lhs: String, _ rhs: String) -> Bool {
        let left = lhs.lowercased()
        let right = rhs.lowercased()
        if left != right { return left < right }
        return lhs < rhs
    }
}
