/// The preflight result the feed hands in. A pass spawns the helper. A refusal is Unavailable and does not spawn.
/// The launch file keeps the path rules and does not own this verdict.
public enum PreflightVerdict: Equatable, Sendable {
    case passed
    case systemTooOld
    case interpreterMissing
    case helperInvalid
}

/// What the status row says. The feed publishes it. Holds other than a pin read "Checking".
public struct SystemSourceStatus: Equatable, Sendable {
    public var word: String
    public var symbol: String
    /// `R1` to `R6` while Unavailable. Nil for every other phase.
    public var reasonCode: String?

    public init(word: String, symbol: String, reasonCode: String? = nil) {
        self.word = word
        self.symbol = symbol
        self.reasonCode = reasonCode
    }

    public static func text(for phase: SystemSourceMachine.Phase) -> SystemSourceStatus {
        switch phase {
        case .off:
            return SystemSourceStatus(word: "Off", symbol: "circle")
        case .held(.pinned):
            return SystemSourceStatus(word: "Pinned", symbol: "pin")
        case .held:
            return checking
        case .starting, .proving:
            return checking
        case .live:
            return SystemSourceStatus(word: "Ready", symbol: "checkmark.circle")
        case .backingOff:
            return SystemSourceStatus(word: "Restarting", symbol: "arrow.clockwise")
        case .unavailable(let reason):
            return SystemSourceStatus(word: "Unavailable", symbol: "exclamationmark.triangle",
                                      reasonCode: reasonCode(reason))
        }
    }

    public static func reasonCode(_ reason: SystemSourceMachine.Reason) -> String {
        switch reason {
        case .systemTooOld: return "R1"
        case .interpreterMissing: return "R2"
        case .helperInvalid: return "R3"
        case .symbolsMissing: return "R4"
        case .routeClosed: return "R5"
        case .keepsFailing: return "R6"
        }
    }

    private static let checking = SystemSourceStatus(word: "Checking", symbol: "arrow.triangle.2.circlepath")
}

/// Pure supervisor for the system now-playing helper. `now` is monotonic seconds from the feed.
/// The reducer makes no time and no randomness. A stale run changes nothing.
public enum SystemSourceMachine {
    /// Back-off delays for the first four failures, in seconds. The fifth failure does not arm another.
    public static let backoffSeconds: [Double] = [1, 2, 4, 8]

    public struct Gates: OptionSet, Equatable, Sendable {
        public var rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let switchOn = Gates(rawValue: 1 << 0)
        public static let services = Gates(rawValue: 1 << 1)
        public static let sessionActive = Gates(rawValue: 1 << 2)
        public static let awake = Gates(rawValue: 1 << 3)
        public static let unlocked = Gates(rawValue: 1 << 4)
        public static let anyPlayer = Gates(rawValue: 1 << 5)

        public static let all: Gates = [.switchOn, .services, .sessionActive, .awake, .unlocked, .anyPlayer]
    }

    public enum Hold: Equatable, Sendable {
        case servicesStopped
        case sessionInactive
        case asleep
        case locked
        case pinned
    }

    public enum Proof: Equatable, Sendable {
        case waiting
        case canary
    }

    public enum Reason: Equatable, Sendable {
        case systemTooOld
        case interpreterMissing
        case helperInvalid
        case symbolsMissing
        case routeClosed
        case keepsFailing
    }

    public enum Phase: Equatable, Sendable {
        case off
        case held(Hold)
        case starting
        case proving(Proof)
        case live
        case backingOff
        case unavailable(Reason)
    }

    public enum Report: Equatable, Sendable {
        case unknown
        case nothing
        case item
    }

    /// A command the owner asked for. The wire file owns the JSON codec; this value is the command itself.
    public struct Command: Equatable, Sendable {
        public enum Name: String, Equatable, Sendable {
            case play, pause, next, previous, seek
        }

        public var name: Name
        public var seconds: Double
        public var app: String

        public init(name: Name, seconds: Double, app: String) {
            self.name = name
            self.seconds = seconds
            self.app = app
        }
    }

    /// One line the feed writes. The wire codec turns it into JSON.
    public enum Line: Equatable, Sendable {
        case read(id: Int)
        case ping(id: Int)
        case command(id: Int, Command)
    }

    public enum Deadline: Equatable, Sendable {
        case settle
        case hello
        case read
        case canaryRead
        case canary
        case doubt
        case ack(Int)
        case pong(Int)
        case backoff
        case stable
    }

    public enum Event: Equatable, Sendable {
        case settingChanged(on: Bool)
        case followChanged(any: Bool)
        case servicesStarted
        case willSleep
        case didWake
        case screenLocked
        case screenUnlocked
        case sessionResigned
        case sessionActive
        case quit
        case checkAgain
        case musicPageOpened
        case preflight(run: Int, verdict: PreflightVerdict, token: String)
        case hello(run: Int, version: Int, missing: Int, childIsVendor: Bool)
        case item(run: Int, own: Bool, token: String)
        case nothing(run: Int)
        case playerEvidence(playing: Bool)
        case ack(run: Int, id: Int, ok: Bool)
        case pong(run: Int, id: Int)
        case deadline(run: Int, Deadline)
        case exited(run: Int, status: Int32)
        case badLine(run: Int)
        case flood(run: Int)
        case command(Command)

        var taggedRun: Int? {
            switch self {
            case .preflight(let run, _, _),
                 .hello(let run, _, _, _),
                 .item(let run, _, _),
                 .nothing(let run),
                 .ack(let run, _, _),
                 .pong(let run, _),
                 .deadline(let run, _),
                 .exited(let run, _),
                 .badLine(let run),
                 .flood(let run):
                return run
            default:
                return nil
            }
        }
    }

    public enum Effect: Equatable, Sendable {
        case sweepOrphans
        case preflight(Int)
        case spawn(Int)
        case stop(Int)
        case arm(Int, Deadline, Double)
        case disarm(Int)
        case publishCanary(String)
        case clearCanary
        case send(Int, Line)
        case dropEntry
        case publish(SystemSourceStatus)
    }

    public struct State: Equatable, Sendable {
        public var phase: Phase
        public var gates: Gates
        /// Rises with every new run and is never reset, including by Off.
        public var run: Int
        public var failures: Int
        public var report: Report
        public var playerPlaying: Bool
        public var doubtSpent: Bool
        public var pending: [Int]
        public var nextID: Int
        public var lastPingAt: Double?
        public var token: String?
        /// Twenty undecodable lines in a row are one failure. A decoded line clears it.
        public var badLineStreak: Int
        /// The doubt timer is still open. Cleared when it fires, when an item arrives, or when the player stops.
        public var doubtArmed: Bool
        /// The first read is still unanswered. A `nothing` or an item answers it.
        public var awaitingRead: Bool
        public var pingID: Int?
        public var settleArmed: Bool

        public init(phase: Phase, gates: Gates, run: Int, failures: Int, report: Report, playerPlaying: Bool,
                    doubtSpent: Bool, pending: [Int], nextID: Int, lastPingAt: Double?, token: String?,
                    badLineStreak: Int = 0, doubtArmed: Bool = false, awaitingRead: Bool = false,
                    pingID: Int? = nil, settleArmed: Bool = false) {
            self.phase = phase
            self.gates = gates
            self.run = run
            self.failures = failures
            self.report = report
            self.playerPlaying = playerPlaying
            self.doubtSpent = doubtSpent
            self.pending = pending
            self.nextID = nextID
            self.lastPingAt = lastPingAt
            self.token = token
            self.badLineStreak = badLineStreak
            self.doubtArmed = doubtArmed
            self.awaitingRead = awaitingRead
            self.pingID = pingID
            self.settleArmed = settleArmed
        }
    }

    /// Session, awake, and unlocked. The switch, services, and follow are still off, so nothing starts.
    public static let initial = State(phase: .off, gates: [.sessionActive, .awake, .unlocked], run: 0, failures: 0,
                                      report: .unknown, playerPlaying: false, doubtSpent: false, pending: [],
                                      nextID: 1, lastPingAt: nil, token: nil)

    public static let helloSeconds = 5.0
    public static let readSeconds = 3.0
    public static let canaryReadSeconds = 1.0
    public static let canarySeconds = 3.0
    public static let doubtSeconds = 5.0
    public static let ackSeconds = 2.0
    public static let pongSeconds = 2.0
    public static let settleSeconds = 2.0
    public static let stableSeconds = 300.0
    public static let pingGap = 30.0
    public static let pendingLimit = 4
    public static let badLineLimit = 20

    public static func reduce(_ state: State, _ event: Event, now: Double) -> (State, [Effect]) {
        if let run = event.taggedRun, run != state.run { return (state, []) }
        let before = state
        var state = state
        let effects = apply(&state, event, now: now)
        return finish(before: before, state: state, effects: effects)
    }

    private static func apply(_ state: inout State, _ event: Event, now: Double) -> [Effect] {
        switch event {
        case .settingChanged(let on):
            return setGate(&state, .switchOn, on: on)
        case .followChanged(let any):
            return setGate(&state, .anyPlayer, on: any)
        case .servicesStarted:
            return setGate(&state, .services, on: true)
        case .willSleep:
            state.settleArmed = false
            return setGate(&state, .awake, on: false)
        case .didWake:
            state.settleArmed = true
            return [.arm(state.run, .settle, settleSeconds)]
        case .screenLocked:
            return setGate(&state, .unlocked, on: false)
        case .screenUnlocked:
            return setGate(&state, .unlocked, on: true)
        case .sessionResigned:
            return setGate(&state, .sessionActive, on: false)
        case .sessionActive:
            return setGate(&state, .sessionActive, on: true)
        case .quit:
            return turnOff(&state)
        case .checkAgain:
            guard case .unavailable = state.phase else { return [] }
            guard state.gates == Gates.all else { return [] }
            return startRun(&state, resetFailures: true)
        case .musicPageOpened:
            return ping(&state, now: now)
        case .preflight(_, let verdict, let token):
            return preflight(&state, verdict, token: token)
        case .hello(_, let version, let missing, let childIsVendor):
            return hello(&state, version: version, missing: missing, childIsVendor: childIsVendor)
        case .item(_, let own, let token):
            return item(&state, own: own, token: token)
        case .nothing:
            return nothing(&state)
        case .playerEvidence(let playing):
            state.playerPlaying = playing
            if !playing {
                state.doubtSpent = false
                state.doubtArmed = false
            }
            return []
        case .ack(_, let id, _):
            guard acceptsLines(state.phase) else { return [] }
            state.badLineStreak = 0
            if let index = state.pending.firstIndex(of: id) {
                state.pending.remove(at: index)
            }
            return []
        case .pong(_, let id):
            guard acceptsLines(state.phase) else { return [] }
            state.badLineStreak = 0
            if state.pingID == id { state.pingID = nil }
            return []
        case .deadline(_, let deadline):
            return self.deadline(&state, deadline)
        case .exited:
            guard acceptsLines(state.phase) else { return [] }
            return fail(&state)
        case .badLine:
            guard acceptsLines(state.phase) else { return [] }
            state.badLineStreak += 1
            guard state.badLineStreak >= badLineLimit else { return [] }
            return fail(&state)
        case .flood:
            guard acceptsLines(state.phase) else { return [] }
            return fail(&state)
        case .command(let command):
            return self.command(&state, command)
        }
    }

    private static func setGate(_ state: inout State, _ gate: Gates, on: Bool) -> [Effect] {
        let had = state.gates.contains(gate)
        if on {
            state.gates.insert(gate)
        } else {
            state.gates.remove(gate)
        }
        let gained = on && !had
        return reconcile(&state, gained: gained)
    }

    private static func reconcile(_ state: inout State, gained: Bool) -> [Effect] {
        if !state.gates.contains(.switchOn) {
            return turnOff(&state)
        }
        if let hold = firstHold(state.gates) {
            return enterHold(&state, hold)
        }
        switch state.phase {
        case .off, .held, .unavailable:
            guard gained else { return [] }
            return startRun(&state, resetFailures: true)
        case .starting, .proving, .live, .backingOff:
            return []
        }
    }

    /// The first missing gate after the switch, in the order of the gate table.
    private static func firstHold(_ gates: Gates) -> Hold? {
        if !gates.contains(.services) { return .servicesStopped }
        if !gates.contains(.sessionActive) { return .sessionInactive }
        if !gates.contains(.awake) { return .asleep }
        if !gates.contains(.unlocked) { return .locked }
        if !gates.contains(.anyPlayer) { return .pinned }
        return nil
    }

    private static func turnOff(_ state: inout State) -> [Effect] {
        guard state.phase != .off else { return [] }
        let effects = halt(&state)
        state.phase = .off
        return effects
    }

    private static func enterHold(_ state: inout State, _ hold: Hold) -> [Effect] {
        if case .held(let current) = state.phase, current == hold { return [] }
        var effects: [Effect] = []
        if isRunning(state.phase) {
            effects = halt(&state)
        }
        state.phase = .held(hold)
        return effects
    }

    private static func startRun(_ state: inout State, resetFailures: Bool) -> [Effect] {
        if resetFailures { state.failures = 0 }
        let previous = state.run
        state.run += 1
        state.phase = .starting
        state.token = nil
        state.pending = []
        state.badLineStreak = 0
        state.doubtArmed = false
        state.awaitingRead = false
        state.pingID = nil
        state.report = .unknown
        var effects: [Effect] = []
        if previous > 0 {
            effects.append(.disarm(previous))
        }
        effects.append(.sweepOrphans)
        effects.append(.preflight(state.run))
        return effects
    }

    private static func preflight(_ state: inout State, _ verdict: PreflightVerdict, token: String) -> [Effect] {
        guard state.phase == .starting, state.token == nil else { return [] }
        switch verdict {
        case .passed:
            state.token = token
            return [.spawn(state.run), .arm(state.run, .hello, helloSeconds)]
        case .systemTooOld:
            state.phase = .unavailable(.systemTooOld)
        case .interpreterMissing:
            state.phase = .unavailable(.interpreterMissing)
        case .helperInvalid:
            state.phase = .unavailable(.helperInvalid)
        }
        return []
    }

    private static func hello(_ state: inout State, version: Int, missing: Int, childIsVendor: Bool) -> [Effect] {
        guard state.phase == .starting, state.token != nil else { return [] }
        state.badLineStreak = 0
        if version != 1 || missing != 0 {
            return refuse(&state, .symbolsMissing)
        }
        if !childIsVendor {
            return refuse(&state, .interpreterMissing)
        }
        state.phase = .proving(.waiting)
        state.awaitingRead = true
        let id = allocate(&state)
        return [.send(state.run, .read(id: id)), .arm(state.run, .read, readSeconds)]
    }

    private static func item(_ state: inout State, own: Bool, token: String) -> [Effect] {
        guard acceptsLines(state.phase) else { return [] }
        if state.phase == .starting { return closeRoute(&state) }
        state.badLineStreak = 0
        state.awaitingRead = false
        state.doubtArmed = false
        state.doubtSpent = false
        if own {
            if let expected = state.token, !expected.isEmpty, token == expected {
                return enterLive(&state, clearCanary: true)
            }
            if case .proving = state.phase { return closeRoute(&state) }
            return []
        }
        state.report = .item
        let clear = isCanary(state.phase)
        return enterLive(&state, clearCanary: clear)
    }

    private static func nothing(_ state: inout State) -> [Effect] {
        guard acceptsLines(state.phase) else { return [] }
        if state.phase == .starting { return closeRoute(&state) }
        state.badLineStreak = 0
        state.awaitingRead = false
        state.report = .nothing
        if state.playerPlaying && (state.phase == .live || isProving(state.phase)) {
            guard !state.doubtSpent else { return [] }
            state.doubtSpent = true
            state.doubtArmed = true
            return [.arm(state.run, .doubt, doubtSeconds)]
        }
        if case .proving(.waiting) = state.phase {
            return beginCanary(&state)
        }
        return []
    }

    private static func beginCanary(_ state: inout State) -> [Effect] {
        guard let token = state.token, !token.isEmpty else { return closeRoute(&state) }
        state.phase = .proving(.canary)
        state.awaitingRead = false
        let id = allocate(&state)
        return [
            .publishCanary(token),
            .send(state.run, .read(id: id)),
            .arm(state.run, .canaryRead, canaryReadSeconds),
            .arm(state.run, .canary, canarySeconds),
        ]
    }

    private static func enterLive(_ state: inout State, clearCanary: Bool) -> [Effect] {
        let wasLive = state.phase == .live
        state.phase = .live
        var effects: [Effect] = []
        if clearCanary { effects.append(.clearCanary) }
        if !wasLive {
            effects.append(.arm(state.run, .stable, stableSeconds))
        }
        return effects
    }

    private static func deadline(_ state: inout State, _ deadline: Deadline) -> [Effect] {
        switch deadline {
        case .hello:
            guard state.phase == .starting, state.token != nil else { return [] }
            return fail(&state)
        case .read:
            guard state.awaitingRead, case .proving(.waiting) = state.phase else { return [] }
            return fail(&state)
        case .canaryRead:
            return []
        case .canary:
            guard case .proving(.canary) = state.phase else { return [] }
            return closeRoute(&state)
        case .doubt:
            guard state.doubtArmed else { return [] }
            guard state.phase == .live || isProving(state.phase) else { return [] }
            state.doubtArmed = false
            return beginCanary(&state)
        case .ack(let id):
            guard state.pending.contains(id) else { return [] }
            return fail(&state)
        case .pong(let id):
            guard state.pingID == id else { return [] }
            return fail(&state)
        case .backoff:
            guard state.phase == .backingOff else { return [] }
            if state.gates.contains(.switchOn), firstHold(state.gates) == nil {
                return startRun(&state, resetFailures: false)
            }
            return reconcile(&state, gained: false)
        case .settle:
            guard state.settleArmed else { return [] }
            state.settleArmed = false
            let gained = !state.gates.contains(.awake)
            state.gates.insert(.awake)
            return reconcile(&state, gained: gained)
        case .stable:
            guard state.phase == .live else { return [] }
            state.failures = 0
            return [.arm(state.run, .stable, stableSeconds)]
        }
    }

    private static func ping(_ state: inout State, now: Double) -> [Effect] {
        guard state.phase == .live, now.isFinite, state.pingID == nil else { return [] }
        if let last = state.lastPingAt, now - last < pingGap { return [] }
        let id = allocate(&state)
        state.pingID = id
        state.lastPingAt = now
        return [.send(state.run, .ping(id: id)), .arm(state.run, .pong(id), pongSeconds)]
    }

    private static func command(_ state: inout State, _ command: Command) -> [Effect] {
        guard state.phase == .live, state.pending.count < pendingLimit else { return [] }
        let id = allocate(&state)
        state.pending.append(id)
        return [
            .send(state.run, .command(id: id, command)),
            .arm(state.run, .ack(id), ackSeconds),
        ]
    }

    private static func fail(_ state: inout State) -> [Effect] {
        state.failures += 1
        let effects = halt(&state)
        if state.failures >= 5 {
            state.phase = .unavailable(.keepsFailing)
            return effects
        }
        state.phase = .backingOff
        let delay = backoffSeconds[state.failures - 1]
        return effects + [.arm(state.run, .backoff, delay)]
    }

    private static func closeRoute(_ state: inout State) -> [Effect] {
        return refuse(&state, .routeClosed)
    }

    private static func refuse(_ state: inout State, _ reason: Reason) -> [Effect] {
        let effects = halt(&state)
        state.phase = .unavailable(reason)
        return effects
    }

    /// Stop, clear the canary, and drop the entry. The run counter stays.
    private static func halt(_ state: inout State) -> [Effect] {
        let effects: [Effect] = [.stop(state.run), .clearCanary, .dropEntry]
        state.token = nil
        state.pending = []
        state.doubtArmed = false
        state.awaitingRead = false
        state.pingID = nil
        state.badLineStreak = 0
        return effects
    }

    private static func allocate(_ state: inout State) -> Int {
        let id = state.nextID
        state.nextID += 1
        return id
    }

    private static func acceptsLines(_ phase: Phase) -> Bool {
        switch phase {
        case .starting, .proving, .live:
            return true
        case .off, .held, .backingOff, .unavailable:
            return false
        }
    }

    private static func isRunning(_ phase: Phase) -> Bool {
        switch phase {
        case .starting, .proving, .live, .backingOff:
            return true
        case .off, .held, .unavailable:
            return false
        }
    }

    private static func isProving(_ phase: Phase) -> Bool {
        if case .proving = phase { return true }
        return false
    }

    private static func isCanary(_ phase: Phase) -> Bool {
        if case .proving(.canary) = phase { return true }
        return false
    }

    private static func finish(before: State, state: State, effects: [Effect]) -> (State, [Effect]) {
        var effects = effects
        let previous = SystemSourceStatus.text(for: before.phase)
        let next = SystemSourceStatus.text(for: state.phase)
        if previous != next {
            effects.append(.publish(next))
        }
        return (state, effects)
    }
}
