/// "Allow all" in Settings > Permissions, as a pure state machine.
///
/// macOS never lets an app turn on its own privacy access, so one button cannot grant everything.
/// What it can do is ask for everything in the fewest steps: first every in-place macOS prompt, back to
/// back (one click each), then each access that only has a switch in System Settings: the official
/// request adds Zeus to the list, the exact pane opens, a small guide says what to turn on, and the
/// sweep moves on by itself the moment the switch is on. Allowed access is skipped, a prompt macOS
/// already refused (it never asks twice) goes to its pane instead, and nothing is asked twice in one
/// sweep. Progress is saved so the sweep resumes when macOS reopens Zeus for Screen Recording.
public enum PermissionSweep {
    /// Every access Zeus asks for, in sweep order: in-place prompts first, then System Settings switches.
    /// Screen Recording is last because turning it on can make macOS quit and reopen Zeus.
    public enum Item: String, CaseIterable, Codable, Sendable {
        case microphone, speech, camera, calendar, reminders, notifications, location, automation
        case accessibility, inputMonitoring, fullDiskAccess, screenRecording

        /// True when macOS shows an Allow dialog in place (the first time only).
        public var askedInPlace: Bool {
            switch self {
            case .microphone, .speech, .camera, .calendar, .reminders, .notifications, .location, .automation: true
            case .accessibility, .inputMonitoring, .fullDiskAccess, .screenRecording: false
            }
        }

        /// True when an official request call adds Zeus to the System Settings list before the pane opens.
        /// Full Disk Access has none: the person adds Zeus with the + button.
        public var hasRequestCall: Bool {
            switch self {
            case .accessibility, .inputMonitoring, .screenRecording: true
            default: false
            }
        }

        public var title: String {
            switch self {
            case .microphone: "Microphone"
            case .speech: "Speech Recognition"
            case .camera: "Camera"
            case .calendar: "Calendar"
            case .reminders: "Reminders"
            case .notifications: "Notifications"
            case .location: "Location"
            case .automation: "Automation"
            case .accessibility: "Accessibility"
            case .inputMonitoring: "Input Monitoring"
            case .fullDiskAccess: "Full Disk Access"
            case .screenRecording: "Screen Recording"
            }
        }

        /// The exact System Settings pane.
        public var settingsURL: String {
            let privacy = "x-apple.systempreferences:com.apple.preference.security?"
            switch self {
            case .microphone: return privacy + "Privacy_Microphone"
            case .speech: return privacy + "Privacy_SpeechRecognition"
            case .camera: return privacy + "Privacy_Camera"
            case .calendar: return privacy + "Privacy_Calendars"
            case .reminders: return privacy + "Privacy_Reminders"
            case .notifications: return "x-apple.systempreferences:com.apple.preference.notifications"
            case .location: return privacy + "Privacy_LocationServices"
            case .automation: return privacy + "Privacy_Automation"
            case .accessibility: return privacy + "Privacy_Accessibility"
            case .inputMonitoring: return privacy + "Privacy_ListenEvent"
            case .fullDiskAccess: return privacy + "Privacy_AllFiles"
            case .screenRecording: return privacy + "Privacy_ScreenCapture"
            }
        }

        /// Turning it on may only take effect after Zeus reopens.
        public var mayNeedRestart: Bool { self == .screenRecording }
    }

    public enum Access: Equatable, Sendable {
        case allowed
        /// Not asked yet (or, for a System Settings switch, simply off).
        case notAsked
        /// macOS refused it: its in-place prompt will not show again.
        case denied
    }

    public enum Route: String, Codable, Equatable, Sendable {
        /// Raise the in-place macOS prompt.
        case prompt
        /// Open the System Settings pane and wait for the switch.
        case settings
    }

    public struct Step: Equatable, Sendable {
        public var item: Item
        public var route: Route
        public init(item: Item, route: Route) { self.item = item; self.route = route }
    }

    public enum Phase: Equatable, Sendable {
        case idle
        /// An in-place prompt is up for this item.
        case prompting(Item)
        /// The pane is open and the guide is showing for this item.
        case guiding(Item)
        /// Done. `needsRestart`: an access was turned on that only works after Zeus reopens.
        case finished(needsRestart: Bool)
        case cancelled
    }

    /// What survives a relaunch.
    public struct Progress: Codable, Equatable, Sendable {
        public var visited: [Item]
        public var needsRestart: Bool
        public var savedAt: Double
        public init(visited: [Item], needsRestart: Bool, savedAt: Double) {
            self.visited = visited
            self.needsRestart = needsRestart
            self.savedAt = savedAt
        }
    }

    /// A saved sweep older than this is dropped instead of resumed.
    public static let resumeWindow: Double = 30 * 60

    public struct State: Equatable, Sendable {
        public var phase: Phase = .idle
        /// Steps still to come after the current one.
        public var queue: [Step] = []
        /// Items asked or guided in this sweep: never again.
        public var visited: [Item] = []
        public var needsRestart = false
        public init() {}

        public var isRunning: Bool {
            switch phase {
            case .prompting, .guiding: true
            case .idle, .finished, .cancelled: false
            }
        }

        public var current: Item? {
            switch phase {
            case .prompting(let item), .guiding(let item): item
            case .idle, .finished, .cancelled: nil
            }
        }
    }

    public enum Event: Equatable, Sendable {
        /// "Allow all" was pressed, or Zeus reopened with `resumed` progress. `now` stamps saved progress.
        case start(access: [Item: Access], resumed: Progress?, now: Double)
        /// The in-place prompt for `item` returned (any answer).
        case promptAnswered(Item, access: [Item: Access], now: Double)
        /// A periodic read of every access.
        case poll(access: [Item: Access], now: Double)
        /// "I turned it on" for an access that may need a restart before macOS reports it.
        case done(access: [Item: Access], now: Double)
        case skip(access: [Item: Access], now: Double)
        case cancel
    }

    public enum Effect: Equatable, Sendable {
        /// Raise the in-place prompt; report `.promptAnswered` when it returns.
        case ask(Item)
        /// Call the official request (when `request`), then open the item's pane.
        case openSettings(Item, request: Bool)
        case showGuide(Item)
        case hideGuide
        case startPolling
        case stopPolling
        case save(Progress)
        case clearProgress
    }

    public static func access(_ item: Item, in access: [Item: Access]) -> Access { access[item] ?? .notAsked }

    /// "N of M allowed".
    public static func allowedCount(_ access: [Item: Access]) -> Int {
        Item.allCases.filter { Self.access($0, in: access) == .allowed }.count
    }

    public static func progressLine(_ access: [Item: Access]) -> String {
        "\(allowedCount(access)) of \(Item.allCases.count) allowed"
    }

    /// The plan for what is not allowed yet: in-place prompts not asked yet come first; everything else
    /// (switches, and prompts macOS already refused) goes to System Settings. `skipping` were done already.
    public static func plan(_ access: [Item: Access], skipping: [Item] = []) -> [Step] {
        let open = Item.allCases.filter { Self.access($0, in: access) != .allowed && !skipping.contains($0) }
        let prompts = open.filter { $0.askedInPlace && Self.access($0, in: access) == .notAsked }
        let settings = open.filter { !prompts.contains($0) }
        return prompts.map { Step(item: $0, route: .prompt) } + settings.map { Step(item: $0, route: .settings) }
    }

    /// Whether saved progress is recent enough to pick up again.
    public static func shouldResume(_ progress: Progress?, now: Double) -> Bool {
        guard let progress else { return false }
        return now - progress.savedAt >= 0 && now - progress.savedAt < resumeWindow
    }

    /// The guide's one line for the current step.
    public static func guideText(_ phase: Phase) -> String {
        switch phase {
        case .prompting(let item):
            return "Click Allow in the macOS prompt for \(item.title)."
        case .guiding(.fullDiskAccess):
            return "Click +, choose Zeus, turn it on, then come back."
        case .guiding(.automation):
            return "Turn on Zeus for each app in Automation, then come back."
        case .guiding(let item) where item.mayNeedRestart:
            return "Turn on Zeus in \(item.title), then press Done."
        case .guiding(let item):
            return "Turn on Zeus in \(item.title), then come back."
        case .finished(let needsRestart):
            return needsRestart ? "Restart Zeus to finish Screen Recording." : "All set."
        case .idle, .cancelled:
            return ""
        }
    }

    public static func reduce(_ state: State, _ event: Event) -> (State, [Effect]) {
        switch event {
        case .start(let access, let resumed, let now):
            guard !state.isRunning else { return (state, []) }
            var next = State()
            if let resumed {
                next.visited = resumed.visited
                next.needsRestart = resumed.needsRestart
            }
            next.queue = plan(access, skipping: next.visited)
            return advance(next, access: access, now: now, effects: [])

        case .promptAnswered(let item, let access, let now):
            guard state.phase == .prompting(item) else { return (state, []) }
            return advance(state, access: access, now: now, effects: [])

        case .poll(let access, let now):
            switch state.phase {
            case .guiding(let item), .prompting(let item):
                // A prompt without a completion (Location) or a switch turned on: move on.
                let answered = state.phase == .prompting(item) ? Self.access(item, in: access) != .notAsked
                    : Self.access(item, in: access) == .allowed
                guard answered else { return (state, []) }
                return advance(state, access: access, now: now, effects: [])
            default:
                return (state, [])
            }

        case .done(let access, let now):
            guard case .guiding(let item) = state.phase else { return (state, []) }
            var next = state
            if item.mayNeedRestart, Self.access(item, in: access) != .allowed { next.needsRestart = true }
            return advance(next, access: access, now: now, effects: [])

        case .skip(let access, let now):
            guard state.isRunning else { return (state, []) }
            return advance(state, access: access, now: now, effects: [])

        case .cancel:
            guard state.isRunning else { return (state, []) }
            var next = state
            next.phase = .cancelled
            next.queue = []
            return (next, [.hideGuide, .stopPolling, .clearProgress])
        }
    }

    /// Leaves the current step and starts the next one still needed, or finishes.
    private static func advance(_ state: State, access: [Item: Access], now: Double, effects: [Effect]) -> (State, [Effect]) {
        var next = state
        var effects = effects
        let wasRunning = state.isRunning
        while !next.queue.isEmpty {
            let step = next.queue.removeFirst()
            if next.visited.contains(step.item) { continue }
            let current = Self.access(step.item, in: access)
            if current == .allowed { continue }
            // Answered by an earlier prompt in this sweep (Microphone also asks Speech): never ask again.
            if step.route == .prompt, current != .notAsked { continue }
            next.visited.append(step.item)
            effects.append(.save(Progress(visited: next.visited, needsRestart: next.needsRestart, savedAt: now)))
            switch step.route {
            case .prompt:
                next.phase = .prompting(step.item)
                effects.append(.ask(step.item))
            case .settings:
                next.phase = .guiding(step.item)
                effects.append(.openSettings(step.item, request: step.item.hasRequestCall))
            }
            effects.append(.showGuide(step.item))
            if !wasRunning { effects.append(.startPolling) }
            return (next, effects)
        }
        if let restart = Item.allCases.first(where: \.mayNeedRestart), Self.access(restart, in: access) == .allowed {
            next.needsRestart = false
        }
        next.phase = .finished(needsRestart: next.needsRestart)
        if wasRunning { effects += [.hideGuide, .stopPolling] }
        effects.append(.clearProgress)
        return (next, effects)
    }
}
