import Foundation

/// The sound-output list and its switch, as pure state.
///
/// Opening reads the outputs. A press writes the default, then reads it back twice. The current
/// mark moves only when a read names the pick. A late answer whose token is not the live read or
/// the live switch is dropped.
///
/// Routes arrive already chosen and ordered. Filtering, cleaning and transport symbols belong to
/// the route model, which is a separate draft, so this file does not name those types. A later
/// controller copies each route in. Nothing here opens a device or writes a default.
public enum OutputList {
    /// One row the controller has already accepted. `isCurrent` is the last read, not the press.
    public struct Route: Equatable, Sendable, Identifiable {
        public var uid: String
        public var objectID: UInt32
        public var name: String
        public var symbol: String
        public var isCurrent: Bool
        public var id: String { uid }

        public init(uid: String, objectID: UInt32, name: String, symbol: String, isCurrent: Bool) {
            self.uid = uid
            self.objectID = objectID
            self.name = name
            self.symbol = symbol
            self.isCurrent = isCurrent
        }
    }

    public enum Step: Equatable, Sendable {
        case writing
        case firstCheck
        case secondCheck
    }

    /// The switch in flight. `token` makes an older write's answer stale.
    public struct Pending: Equatable, Sendable {
        public var uid: String
        public var name: String
        public var token: UInt64
        public var step: Step
        /// A nil first read-back has already been asked for once.
        public var retried: Bool

        public init(uid: String, name: String, token: UInt64, step: Step, retried: Bool) {
            self.uid = uid
            self.name = name
            self.token = token
            self.step = step
            self.retried = retried
        }
    }

    public struct Failure: Equatable, Sendable {
        public var uid: String
        public var name: String
        public var reason: Reason

        public init(uid: String, name: String, reason: Reason) {
            self.uid = uid
            self.name = name
            self.reason = reason
        }

        public enum Reason: Equatable, Sendable {
            case deviceGone
            case refused(Int32)
            case timedOut
            case elsewhere
            case unread
            /// The second read named a different output. `current` is that output's cleaned name.
            case left(current: String?)
        }
    }

    /// `reading` is the token of the device read in flight, or nil. `run` is the last token handed out.
    public struct Open: Equatable, Sendable {
        public var routes: [Route]
        public var pending: Pending?
        public var failure: Failure?
        public var reading: UInt64?
        public var readQueued: Bool
        public var loaded: Bool
        public var run: UInt64

        public init(
            routes: [Route], pending: Pending?, failure: Failure?, reading: UInt64?, readQueued: Bool, loaded: Bool,
            run: UInt64
        ) {
            self.routes = routes
            self.pending = pending
            self.failure = failure
            self.reading = reading
            self.readQueued = readQueued
            self.loaded = loaded
            self.run = run
        }
    }

    public enum State: Equatable, Sendable {
        case closed(run: UInt64)
        case open(Open)
        /// The list is off screen and a switch is still being checked. `run` keeps tokens from restarting.
        case settling(Pending, run: UInt64)

        public var run: UInt64 {
            switch self {
            case .closed(let run), .settling(_, let run): return run
            case .open(let open): return open.run
            }
        }

        /// Five routes, one of them current, one of them failed.
        public static var snapshotSample: State {
            let routes = [
                Route(uid: "builtin", objectID: 1, name: "MacBook Speakers", symbol: "speaker.wave.2", isCurrent: false),
                Route(uid: "wired", objectID: 2, name: "USB Headphones", symbol: "headphones", isCurrent: true),
                Route(uid: "pods", objectID: 3, name: "AirPods", symbol: "airpods", isCurrent: false),
                Route(uid: "display", objectID: 4, name: "Studio Display", symbol: "display", isCurrent: false),
                Route(uid: "desk", objectID: 5, name: "Desk Speaker", symbol: "hifispeaker", isCurrent: false),
            ]
            return .open(Open(
                routes: routes,
                pending: nil,
                failure: Failure(uid: "desk", name: "Desk Speaker", reason: .timedOut),
                reading: nil,
                readQueued: false,
                loaded: true,
                run: 1
            ))
        }
    }

    public enum Event: Equatable, Sendable {
        case toggled
        case closed
        case interrupted
        case picked(String)
        case devicesChanged
        /// `routes` are the controller's copy of an already built list.
        case facts(token: UInt64, routes: [Route])
        /// Nil means the device was gone before the write. Any other non-zero status was refused.
        case writeFinished(token: UInt64, status: Int32?)
        /// Nil `uid` means the default output could not be read. `name` is that output's cleaned name.
        case readBack(token: UInt64, uid: String?, name: String?)
        case expired(UInt64)
    }

    public enum Effect: Equatable, Sendable {
        case startListening
        case stopListening
        case readDevices(token: UInt64)
        case write(token: UInt64, uid: String)
        case readBackAfter(token: UInt64, seconds: Double)
        case expireAfter(token: UInt64, seconds: Double)
        case announce(String)
        case cue(String)
    }

    public static func reduce(_ state: State, _ event: Event) -> (State, [Effect]) {
        switch event {
        case .toggled: return toggle(state)
        case .closed: return close(state)
        case .interrupted: return interrupt(state)
        case .picked(let uid): return pick(state, uid)
        case .devicesChanged: return devicesChanged(state)
        case .facts(let token, let routes): return facts(state, token: token, routes: routes)
        case .writeFinished(let token, let status): return writeFinished(state, token: token, status: status)
        case .readBack(let token, let uid, let name): return readBack(state, token: token, uid: uid, name: name)
        case .expired(let token): return expired(state, token)
        }
    }

    /// Rows for an open list, in the order the routes arrived. A closed list draws nothing.
    public static func rows(_ state: State) -> [OutputRow] {
        guard case .open(let open) = state else { return [] }
        return open.routes.map { route in
            OutputRow(route: route, symbol: route.symbol, status: rowStatus(route, pending: open.pending, failure: open.failure))
        }
    }

    // MARK: - Events

    private static func toggle(_ state: State) -> (State, [Effect]) {
        switch state {
        case .closed(let run):
            return beginListening(Open(routes: [], pending: nil, failure: nil, reading: nil, readQueued: false, loaded: false, run: run))
        case .open:
            return close(state)
        case .settling(let pending, let run):
            return beginListening(Open(
                routes: [], pending: pending, failure: nil, reading: nil, readQueued: false, loaded: false, run: run
            ))
        }
    }

    private static func close(_ state: State) -> (State, [Effect]) {
        switch state {
        case .open(let open):
            if let pending = open.pending {
                return (.settling(pending, run: open.run), [.stopListening])
            }
            return (.closed(run: open.run), [.stopListening])
        case .settling, .closed:
            // A second close leaves a switch that is still being checked, and stops listening again.
            return (state, [.stopListening])
        }
    }

    private static func interrupt(_ state: State) -> (State, [Effect]) {
        var effects: [Effect] = []
        if case .open = state { effects.append(.stopListening) }
        return (.closed(run: state.run + 1), effects)
    }

    private static func pick(_ state: State, _ uid: String) -> (State, [Effect]) {
        guard case .open(var open) = state else { return (state, []) }
        guard let route = open.routes.first(where: { $0.uid == uid }) else { return (state, []) }
        if route.isCurrent {
            open.failure = nil
            return (.open(open), [])
        }
        let token = allocate(&open.run)
        open.pending = Pending(uid: route.uid, name: route.name, token: token, step: .writing, retried: false)
        open.failure = nil
        return (.open(open), [
            .write(token: token, uid: uid),
            .expireAfter(token: token, seconds: OutputListTiming.writeDeadline),
        ])
    }

    private static func devicesChanged(_ state: State) -> (State, [Effect]) {
        guard case .open(var open) = state else { return (state, []) }
        if open.reading != nil {
            open.readQueued = true
            return (.open(open), [])
        }
        let effects = startRead(&open)
        return (.open(open), effects)
    }

    private static func facts(_ state: State, token: UInt64, routes: [Route]) -> (State, [Effect]) {
        guard case .open(var open) = state, open.reading == token else { return (state, []) }
        if open.pending != nil {
            var previous: [String: Bool] = [:]
            for route in open.routes { previous[route.uid] = route.isCurrent }
            open.routes = routes.map { route in
                var copy = route
                copy.isCurrent = previous[route.uid] ?? false
                return copy
            }
        } else {
            open.routes = routes
        }
        open.reading = nil
        open.loaded = true
        var effects: [Effect] = []
        if let pending = open.pending, !open.routes.contains(where: { $0.uid == pending.uid }) {
            effects += fail(&open, Failure(uid: pending.uid, name: pending.name, reason: .deviceGone))
        } else if let failure = open.failure, open.routes.contains(where: { $0.uid == failure.uid && $0.isCurrent }) {
            open.failure = nil
        }
        if open.readQueued {
            effects += startRead(&open)
        }
        return (.open(open), effects)
    }

    private static func writeFinished(_ state: State, token: UInt64, status: Int32?) -> (State, [Effect]) {
        switch state {
        case .open(var open):
            guard let pending = open.pending, pending.token == token, pending.step == .writing else { return (state, []) }
            switch status {
            case nil:
                var effects = fail(&open, Failure(uid: pending.uid, name: pending.name, reason: .deviceGone))
                effects += requestRead(&open)
                return (.open(open), effects)
            case 0:
                open.pending?.step = .firstCheck
                return (.open(open), [.readBackAfter(token: token, seconds: OutputListTiming.firstReadBack)])
            case let status?:
                let effects = fail(&open, Failure(uid: pending.uid, name: pending.name, reason: .refused(status)))
                return (.open(open), effects)
            }
        case .settling(var pending, let run):
            guard pending.token == token, pending.step == .writing else { return (state, []) }
            switch status {
            case nil:
                return cueAndClose(Failure(uid: pending.uid, name: pending.name, reason: .deviceGone), run: run)
            case 0:
                pending.step = .firstCheck
                return (.settling(pending, run: run), [.readBackAfter(token: token, seconds: OutputListTiming.firstReadBack)])
            case let status?:
                return cueAndClose(Failure(uid: pending.uid, name: pending.name, reason: .refused(status)), run: run)
            }
        case .closed:
            return (state, [])
        }
    }

    private static func readBack(_ state: State, token: UInt64, uid: String?, name: String?) -> (State, [Effect]) {
        switch state {
        case .open(var open):
            guard var pending = open.pending, pending.token == token, pending.step != .writing else { return (state, []) }
            switch applyReadBack(&pending, routes: &open.routes, uid: uid, name: name) {
            case .continue(let effects):
                open.pending = pending
                return (.open(open), effects)
            case .failed(let failure):
                let effects = fail(&open, failure)
                return (.open(open), effects)
            case .done:
                open.pending = nil
                return (.open(open), [])
            }
        case .settling(var pending, let run):
            guard pending.token == token, pending.step != .writing else { return (state, []) }
            var routes: [Route] = []
            switch applyReadBack(&pending, routes: &routes, uid: uid, name: name) {
            case .continue(let effects):
                return (.settling(pending, run: run), effects)
            case .failed(let failure):
                return cueAndClose(failure, run: run)
            case .done:
                return (.closed(run: run), [])
            }
        case .closed:
            return (state, [])
        }
    }

    private static func expired(_ state: State, _ token: UInt64) -> (State, [Effect]) {
        switch state {
        case .open(var open):
            if let pending = open.pending, pending.token == token, pending.step == .writing {
                let effects = fail(&open, Failure(uid: pending.uid, name: pending.name, reason: .timedOut))
                return (.open(open), effects)
            }
            guard open.reading == token else { return (state, []) }
            open.reading = nil
            guard open.readQueued else { return (.open(open), []) }
            let effects = startRead(&open)
            return (.open(open), effects)
        case .settling(let pending, let run):
            guard pending.token == token, pending.step == .writing else { return (state, []) }
            return cueAndClose(Failure(uid: pending.uid, name: pending.name, reason: .timedOut), run: run)
        case .closed:
            return (state, [])
        }
    }

    // MARK: - Steps

    private enum ReadStep {
        case `continue`([Effect])
        case failed(Failure)
        case done
    }

    private static func applyReadBack(
        _ pending: inout Pending, routes: inout [Route], uid: String?, name: String?
    ) -> ReadStep {
        switch pending.step {
        case .writing:
            return .continue([])
        case .firstCheck:
            guard let uid else {
                if pending.retried {
                    return .failed(Failure(uid: pending.uid, name: pending.name, reason: .unread))
                }
                pending.retried = true
                return .continue([.readBackAfter(token: pending.token, seconds: OutputListTiming.nilRetry)])
            }
            guard uid == pending.uid else {
                markCurrent(&routes, uid: uid)
                return .failed(Failure(uid: pending.uid, name: pending.name, reason: .elsewhere))
            }
            markCurrent(&routes, uid: uid)
            pending.step = .secondCheck
            return .continue([
                .announce(OutputListText.soundIsOn(pending.name)),
                .readBackAfter(token: pending.token, seconds: OutputListTiming.secondReadBack),
            ])
        case .secondCheck:
            guard let uid, uid != pending.uid else {
                if let uid { markCurrent(&routes, uid: uid) }
                return .done
            }
            markCurrent(&routes, uid: uid)
            return .failed(Failure(uid: pending.uid, name: pending.name, reason: .left(current: usable(name))))
        }
    }

    private static func beginListening(_ open: Open) -> (State, [Effect]) {
        var open = open
        var effects: [Effect] = [.startListening]
        effects += startRead(&open)
        return (.open(open), effects)
    }

    private static func startRead(_ open: inout Open) -> [Effect] {
        let token = allocate(&open.run)
        open.reading = token
        open.readQueued = false
        return [
            .readDevices(token: token),
            .expireAfter(token: token, seconds: OutputListTiming.readDeadline),
        ]
    }

    /// One read at a time. A request during a read waits and becomes the single follow-up.
    private static func requestRead(_ open: inout Open) -> [Effect] {
        if open.reading != nil {
            open.readQueued = true
            return []
        }
        return startRead(&open)
    }

    private static func fail(_ open: inout Open, _ failure: Failure) -> [Effect] {
        open.failure = failure
        open.pending = nil
        return [.announce(OutputListText.sentence(for: failure))]
    }

    private static func cueAndClose(_ failure: Failure, run: UInt64) -> (State, [Effect]) {
        let text = OutputListText.sentence(for: failure)
        return (.closed(run: run), [.cue(text), .announce(text)])
    }

    private static func allocate(_ run: inout UInt64) -> UInt64 {
        run += 1
        return run
    }

    private static func markCurrent(_ routes: inout [Route], uid: String) {
        for index in routes.indices {
            routes[index].isCurrent = routes[index].uid == uid
        }
    }

    private static func usable(_ name: String?) -> String? {
        OutputListBox.usable(name)
    }

    private static func rowStatus(_ route: Route, pending: Pending?, failure: Failure?) -> OutputRowStatus {
        if let pending, pending.uid == route.uid {
            switch pending.step {
            case .writing, .firstCheck: return .switching
            case .secondCheck: return .current
            }
        }
        if let failure, failure.uid == route.uid {
            if case .left = failure.reason { return .left }
            return .failed
        }
        return route.isCurrent ? .current : .none
    }
}

/// How long each step may take. The reducer schedules these. It does not sleep.
public enum OutputListTiming {
    public static let writeDeadline: Double = 5
    public static let readDeadline: Double = 5
    public static let firstReadBack: Double = 0.25
    public static let secondReadBack: Double = 2
    public static let nilRetry: Double = 0.25
}

/// The sentences VoiceOver and the notch cue share.
public enum OutputListText {
    public static func couldNotSwitch(to name: String) -> String { "Could not switch to \(name)" }
    public static func soundMoved(to name: String) -> String { "Sound moved to \(name)" }
    public static func soundIsOn(_ name: String) -> String { "Sound is on \(name)" }
    public static func soundLeft(_ name: String) -> String { "Sound left \(name)" }

    public static func sentence(for failure: OutputList.Failure) -> String {
        switch failure.reason {
        case .left(let current):
            if let current { return soundMoved(to: current) }
            return soundLeft(failure.name)
        case .deviceGone, .refused, .timedOut, .elsewhere, .unread:
            return couldNotSwitch(to: failure.name)
        }
    }
}

public struct OutputRow: Equatable, Sendable {
    public var route: OutputList.Route
    public var symbol: String
    public var status: OutputRowStatus

    public init(route: OutputList.Route, symbol: String, status: OutputRowStatus) {
        self.route = route
        self.symbol = symbol
        self.status = status
    }
}

public enum OutputRowStatus: Equatable, Sendable {
    case none
    case current
    case switching
    case failed
    case left

    public var word: String {
        switch self {
        case .none: ""
        case .current: "Current"
        case .switching: "Switching"
        case .failed: "Not switched"
        case .left: "Did not stay"
        }
    }

    /// Drawn beside the word. Empty when there is no status.
    public var symbol: String {
        switch self {
        case .none: ""
        case .current: "checkmark"
        case .switching: "arrow.triangle.2.circlepath"
        case .failed: "exclamationmark.triangle"
        case .left: "arrow.uturn.backward"
        }
    }
}

/// The only acts the list view can send. Effects stay inside the controller.
@MainActor
public protocol OutputListControlling: AnyObject {
    var state: OutputList.State { get }
    func toggle()
    func close()
    func pick(uid: String)
}
