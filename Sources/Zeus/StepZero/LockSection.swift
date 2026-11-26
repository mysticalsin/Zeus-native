import Foundation

/// The step-zero lock section. Pure: it reads no session, opens no space, and sends no script itself.
///
/// The caller feeds host results, automation results, and the seconds it waited. A space is made only
/// inside a lock part, and only after both players have been read. The four ways out are the unlock
/// notice, the session dictionary reading unlocked, a session-active or session-resigned notice, and
/// the hard limit. Each of those hides when the card was shown, destroys, closes, and then takes a
/// census. An L6 transition makes no space. The loader that names the space symbols stays out of this file.
public enum LockSection {
    /// The card and its space after a lock. The two looking parts wait longer.
    public static let cardLimitSeconds = 120
    public static let lookingLimitSeconds = 300
    /// The session dictionary is polled on this interval while a lock part is up. This reducer does not sleep.
    public static let pollMilliseconds = 100
    /// Next is withheld until the position reads this many seconds.
    public static let nextNotBeforeSeconds = 21

    public enum Player: String, Sendable, Equatable, CaseIterable {
        case music
        case spotify
    }

    /// What one automation check returned. Only `allowed` may later receive a script.
    public enum Automation: String, Sendable, Equatable {
        case allowed
        case refused
        case notAsked
        case notRunning
        case timedOut
    }

    /// The host calls. A false result ends the part and keeps this name.
    public enum Call: String, Sendable, Equatable, CaseIterable {
        case makeSpace
        case attach
        case show
        case hide
        case destroy
    }

    public enum WayOut: String, Sendable, Equatable {
        case unlock
        case dictionary
        case sessionResigned
        case sessionActive
        case hardLimit
    }

    /// L6. No space is made for any of these.
    public enum Transition: String, Sendable, Equatable, CaseIterable {
        case lock
        case unlock
        case switchOut
        case switchBack
        case saverStart
        case saverStop
        case displaySleep
        case displayWake
    }

    /// What the card counted. A key has no code here.
    public enum PanelInput: Sendable, Equatable {
        case button
        case mouseDown
        case key
    }

    public enum Verb: String, Sendable, Equatable, CaseIterable {
        case playpause
        case next
        case previous
    }

    public struct KeyCounter: Sendable, Equatable {
        public var buttonActions: Int
        public var mouseDowns: Int
        public var keyEvents: Int

        public init() {
            buttonActions = 0
            mouseDowns = 0
            keyEvents = 0
        }
    }

    public struct Script: Sendable, Equatable {
        public var player: Player
        public var verb: Verb

        public init(player: Player, verb: Verb) {
            self.player = player
            self.verb = verb
        }
    }

    public enum Effect: Sendable, Equatable {
        case readAutomation(Player, asking: Bool)
        case makeSpace
        case attach
        case show
        case hide
        case destroy
        case close
        case census
        case script(Player, Verb)
    }

    public enum Phase: Sendable, Equatable {
        case idle
        case checking(Player, asking: Bool)
        case asking(Player)
        case ready
        case awaitMake
        case awaitAttach
        case awaitShow
        case locked
        case timeline
        case stopped
        case done
    }

    public enum Event: Sendable, Equatable {
        case begin
        case automation(Player, Automation)
        case continueAsked
        case lock
        case host(Call, ok: Bool)
        case unlockNotice
        case dictionary(unlocked: Bool)
        case sessionResigned
        case sessionActive
        case waited(seconds: Int)
        case looking
        case transition(Transition)
        case transitionEnded
        case panel(PanelInput)
        case scriptAck(Player)
        case position(Int)
    }

    public struct State: Sendable, Equatable {
        public var phase: Phase
        public var checks: [Player: Automation]
        public var spaceUp: Bool
        public var windowUp: Bool
        public var failedStep: Call?
        public var wayOut: WayOut?
        public var waited: Int
        public var looking: Bool
        public var keys: KeyCounter
        public var transition: Transition?
        public var position: Int
        public var scripts: [Script]
        /// The phase an L6 transition returns to. Empty while no transition is in progress.
        public var resume: Phase?

        public init() {
            phase = .idle
            checks = [:]
            spaceUp = false
            windowUp = false
            failedStep = nil
            wayOut = nil
            waited = 0
            looking = false
            keys = KeyCounter()
            transition = nil
            position = 0
            scripts = []
            resume = nil
        }
    }

    public static func fresh() -> State { State() }

    public static func reduce(_ state: State, _ event: Event) -> (state: State, effects: [Effect]) {
        var state = state
        var effects: [Effect] = []
        switch event {
        case .begin:
            begin(&state, &effects)
        case .automation(let player, let result):
            automation(player, result, &state, &effects)
        case .continueAsked:
            continueAsked(&state, &effects)
        case .lock:
            lock(&state, &effects)
        case .host(let call, let ok):
            host(call, ok, &state, &effects)
        case .unlockNotice:
            leave(.unlock, &state, &effects)
        case .dictionary(let unlocked):
            if unlocked { leave(.dictionary, &state, &effects) }
        case .sessionResigned:
            leave(.sessionResigned, &state, &effects)
        case .sessionActive:
            leave(.sessionActive, &state, &effects)
        case .waited(let seconds):
            waited(seconds, &state, &effects)
        case .looking:
            if state.phase == .locked { state.looking = true }
        case .transition(let transition):
            enterTransition(transition, &state, &effects)
        case .transitionEnded:
            endTransition(&state)
        case .panel(let input):
            panel(input, &state)
        case .scriptAck(let player):
            scriptAck(player, &state, &effects)
        case .position(let seconds):
            position(seconds, &state, &effects)
        }
        return (state, effects)
    }

    private static func begin(_ state: inout State, _ effects: inout [Effect]) {
        guard state.phase == .idle, state.transition == nil else { return }
        ask(.music, asking: false, &state, &effects)
    }

    private static func ask(_ player: Player, asking: Bool, _ state: inout State, _ effects: inout [Effect]) {
        state.phase = .checking(player, asking: asking)
        effects.append(.readAutomation(player, asking: asking))
    }

    private static func automation(
        _ player: Player,
        _ result: Automation,
        _ state: inout State,
        _ effects: inout [Effect]
    ) {
        guard case .checking(let expected, let asking) = state.phase, expected == player else { return }
        state.checks[player] = result
        if result == .notAsked, !asking {
            state.phase = .asking(player)
            return
        }
        advance(after: player, &state, &effects)
    }

    private static func continueAsked(_ state: inout State, _ effects: inout [Effect]) {
        guard case .asking(let player) = state.phase else { return }
        ask(player, asking: true, &state, &effects)
    }

    private static func advance(after player: Player, _ state: inout State, _ effects: inout [Effect]) {
        let order = Player.allCases
        guard let index = order.firstIndex(of: player) else { return }
        let next = order.index(after: index)
        if next < order.endIndex {
            ask(order[next], asking: false, &state, &effects)
        } else {
            state.phase = .ready
        }
    }

    private static func lock(_ state: inout State, _ effects: inout [Effect]) {
        guard state.transition == nil, state.phase == .ready, !state.spaceUp else { return }
        state.phase = .awaitMake
        effects.append(.makeSpace)
    }

    private static func host(_ call: Call, _ ok: Bool, _ state: inout State, _ effects: inout [Effect]) {
        switch (state.phase, call, ok) {
        case (.awaitMake, .makeSpace, true):
            state.spaceUp = true
            state.phase = .awaitAttach
            effects.append(.attach)
        case (.awaitMake, .makeSpace, false):
            fail(.makeSpace, &state, &effects)
        case (.awaitAttach, .attach, true):
            state.phase = .awaitShow
            effects.append(.show)
        case (.awaitAttach, .attach, false):
            fail(.attach, &state, &effects)
        case (.awaitShow, .show, true):
            state.windowUp = true
            state.phase = .locked
            startScripts(&state, &effects)
        case (.awaitShow, .show, false):
            fail(.show, &state, &effects)
        case (.done, .hide, false), (.done, .destroy, false):
            if state.failedStep == nil { state.failedStep = call }
        default:
            break
        }
    }

    private static func fail(_ call: Call, _ state: inout State, _ effects: inout [Effect]) {
        let shown = state.windowUp
        let hadSpace = state.spaceUp || shown
        state.failedStep = call
        state.windowUp = false
        state.spaceUp = false
        state.phase = .stopped
        if hadSpace {
            cleanup(shown: shown, &effects)
        }
    }

    private static func leave(_ reason: WayOut, _ state: inout State, _ effects: inout [Effect]) {
        let live = state.phase == .locked || state.spaceUp || state.windowUp
        guard live, state.wayOut == nil, state.phase != .stopped, state.phase != .timeline else { return }
        let shown = state.windowUp
        state.wayOut = reason
        state.windowUp = false
        state.spaceUp = false
        state.phase = .done
        cleanup(shown: shown, &effects)
    }

    private static func cleanup(shown: Bool, _ effects: inout [Effect]) {
        if shown { effects.append(.hide) }
        effects.append(.destroy)
        effects.append(.close)
        effects.append(.census)
    }

    private static func waited(_ seconds: Int, _ state: inout State, _ effects: inout [Effect]) {
        guard seconds > 0, state.phase == .locked, state.wayOut == nil else { return }
        state.waited += seconds
        let limit = state.looking ? lookingLimitSeconds : cardLimitSeconds
        if state.waited >= limit {
            leave(.hardLimit, &state, &effects)
        }
    }

    private static func enterTransition(
        _ transition: Transition,
        _ state: inout State,
        _ effects: inout [Effect]
    ) {
        if state.phase != .timeline {
            state.resume = resume(from: state.phase)
        }
        let shown = state.windowUp
        let live = state.spaceUp || state.windowUp
        state.transition = transition
        state.windowUp = false
        state.spaceUp = false
        state.phase = .timeline
        if live {
            cleanup(shown: shown, &effects)
        }
    }

    private static func resume(from phase: Phase) -> Phase {
        switch phase {
        case .locked, .awaitMake, .awaitAttach, .awaitShow, .done, .stopped:
            return .ready
        case .timeline:
            return .ready
        case .idle, .checking, .asking, .ready:
            return phase
        }
    }

    private static func endTransition(_ state: inout State) {
        guard state.phase == .timeline else { return }
        let back = state.resume ?? .idle
        state.transition = nil
        state.resume = nil
        state.phase = back
    }

    private static func panel(_ input: PanelInput, _ state: inout State) {
        guard state.phase == .locked, state.windowUp else { return }
        switch input {
        case .button:
            state.keys.buttonActions += 1
        case .mouseDown:
            state.keys.mouseDowns += 1
        case .key:
            state.keys.keyEvents += 1
        }
    }

    private static func startScripts(_ state: inout State, _ effects: inout [Effect]) {
        for player in Player.allCases where state.checks[player] == .allowed {
            guard !state.scripts.contains(where: { $0.player == player }) else { continue }
            send(.playpause, to: player, &state, &effects)
        }
    }

    private static func scriptAck(_ player: Player, _ state: inout State, _ effects: inout [Effect]) {
        guard state.phase == .locked, state.checks[player] == .allowed else { return }
        let sent = state.scripts.filter { $0.player == player }
        let pauses = sent.filter { $0.verb == .playpause }.count
        let nexts = sent.filter { $0.verb == .next }.count
        let previous = sent.filter { $0.verb == .previous }.count
        if pauses < 2 {
            send(.playpause, to: player, &state, &effects)
        } else if nexts == 0, state.position >= nextNotBeforeSeconds {
            send(.next, to: player, &state, &effects)
        } else if nexts > 0, previous == 0 {
            send(.previous, to: player, &state, &effects)
        }
    }

    private static func position(_ seconds: Int, _ state: inout State, _ effects: inout [Effect]) {
        guard state.phase == .locked, seconds >= 0 else { return }
        state.position = seconds
        guard seconds >= nextNotBeforeSeconds else { return }
        for player in Player.allCases where state.checks[player] == .allowed {
            let sent = state.scripts.filter { $0.player == player }
            let pauses = sent.filter { $0.verb == .playpause }.count
            let nexts = sent.filter { $0.verb == .next }.count
            if pauses >= 2, nexts == 0 {
                send(.next, to: player, &state, &effects)
            }
        }
    }

    private static func send(
        _ verb: Verb,
        to player: Player,
        _ state: inout State,
        _ effects: inout [Effect]
    ) {
        guard state.checks[player] == .allowed else { return }
        state.scripts.append(Script(player: player, verb: verb))
        effects.append(.script(player, verb))
    }
}
