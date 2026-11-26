import Foundation

/// The one reducer for the macOS Focus name. A value goes in and a value comes out.
/// Time arrives on the finished read. This type opens nothing and asks for no permission.
public enum SystemFocusMachine {
    /// How long a store change waits before its read, so a burst becomes one read.
    public static let storeChangeDelay: Double = 0.25
    /// How long a mid-write file waits before the single retry.
    public static let malformedRetryDelay: Double = 1
    /// How often the stamp is checked after a watch cannot start.
    public static let statInterval: Double = 15

    /// One Focus the reducer can hold. The shared store types stay in their own files.
    public struct Focus: Equatable, Sendable {
        public var id: String?
        public var name: String?
        public var symbol: String?

        public init(id: String? = nil, name: String? = nil, symbol: String? = nil) {
            self.id = id
            self.name = name
            self.symbol = symbol
        }
    }

    /// Whether a Focus is on, off, or not yet known.
    public enum Reading: Equatable, Sendable {
        case unknown
        case off
        case on(Focus)
    }

    /// What a finished read is allowed to mean.
    public enum Read: Equatable, Sendable {
        public enum Reason: Equatable, Sendable {
            case malformed
            case tooLarge
            case notAFile
            case refused
            case other
        }

        case ok(Reading)
        /// The stamps match the last finished read, so the bytes were left unread.
        case unchanged
        case denied
        /// The Focus store folder is absent.
        case missing
        case unreadable(Reason)
    }

    /// One store file as the reader reports it.
    public struct Stamp: Equatable, Sendable {
        public var inode: UInt64
        public var size: Int64
        public var seconds: Int64
        public var nanoseconds: Int32

        public init(inode: UInt64, size: Int64, seconds: Int64, nanoseconds: Int32) {
            self.inode = inode
            self.size = size
            self.seconds = seconds
            self.nanoseconds = nanoseconds
        }
    }

    /// The stamps of the last finished read. Nil until a read lands.
    public struct Stamps: Equatable, Sendable {
        public var assertions: Stamp?
        public var configurations: Stamp?

        public init(assertions: Stamp? = nil, configurations: Stamp? = nil) {
            self.assertions = assertions
            self.configurations = configurations
        }
    }

    public enum Route: Equatable, Sendable {
        public enum Reason: Equatable, Sendable {
            case missing
            case unreadable(Read.Reason)
        }

        case off
        case checking
        case named
        case needsAccess
        case unavailable(Reason)
    }

    public enum Flight: Equatable, Sendable {
        case idle
        case reading(Int)
        case readingStale(Int)
    }

    public enum Watch: Equatable, Sendable {
        case none
        case events
        case stat
    }

    /// The whole decision. `reduce` is the only place the route changes.
    public struct State: Equatable, Sendable {
        public var enabled: Bool
        public var route: Route
        public var reading: Reading
        public var flight: Flight
        public var watch: Watch
        public var stamps: Stamps?
        public var detailsHidden: Bool
        public var baselineTaken: Bool
        public var cueTimes: [Double]
        public var malformedStreak: Int
        public var generation: Int

        public init(
            enabled: Bool = false,
            route: Route = .off,
            reading: Reading = .unknown,
            flight: Flight = .idle,
            watch: Watch = .none,
            stamps: Stamps? = nil,
            detailsHidden: Bool = false,
            baselineTaken: Bool = false,
            cueTimes: [Double] = [],
            malformedStreak: Int = 0,
            generation: Int = 0
        ) {
            self.enabled = enabled
            self.route = route
            self.reading = reading
            self.flight = flight
            self.watch = watch
            self.stamps = stamps
            self.detailsHidden = detailsHidden
            self.baselineTaken = baselineTaken
            self.cueTimes = cueTimes
            self.malformedStreak = malformedStreak
            self.generation = generation
        }
    }

    public enum Event: Equatable, Sendable {
        case launched(enabled: Bool, detailsHidden: Bool)
        case settingChanged(Bool)
        case detailsHidden(Bool)
        case appBecameActive
        case sessionBecameActive
        case rowAppeared
        case didWake
        case storeChanged
        case statTick
        case readFinished(generation: Int, result: Read, stamps: Stamps?, now: Double)
        case watchStarted
        case watchFailed
        case openSettingsPressed
    }

    /// One announcement the notch may show. The wing builds the words.
    public struct Cue: Equatable, Sendable {
        public var label: String
        public var symbol: String
        public var on: Bool

        public init(label: String, symbol: String, on: Bool) {
            self.label = label
            self.symbol = symbol
            self.on = on
        }
    }

    public enum Effect: Equatable, Sendable {
        case read(generation: Int, after: Double, ifChangedFrom: Stamps?)
        case cancelRead
        case startWatch
        case stopWatch
        case scheduleStat(after: Double)
        case cancelStat
        case cue(Cue)
        case withdrawCue
        case openPane
    }

    /// The only place the route changes. An old generation is ignored, so a stale read never lands.
    public static func reduce(_ state: State, _ event: Event) -> (State, [Effect]) {
        var state = state
        if !state.enabled {
            switch event {
            case .launched(let enabled, let hidden):
                state.detailsHidden = hidden
                if enabled { return beginChecking(state) }
                return (state, [])
            case .settingChanged(true):
                return beginChecking(state)
            case .detailsHidden(let hidden):
                state.detailsHidden = hidden
                return (state, [])
            default:
                return (state, [])
            }
        }

        switch event {
        case .launched(let enabled, let hidden):
            if !enabled { return turnOff(state) }
            return applyHidden(state, hidden)
        case .settingChanged(let on):
            if on { return (state, []) }
            return turnOff(state)
        case .detailsHidden(let hidden):
            return applyHidden(state, hidden)
        case .appBecameActive, .sessionBecameActive, .rowAppeared, .didWake:
            guard rechecks(state.route), case .idle = state.flight else { return (state, []) }
            return scheduleRead(state, after: 0, ifChangedFrom: nil)
        case .storeChanged:
            guard state.route != .off else { return (state, []) }
            switch state.flight {
            case .idle:
                return scheduleRead(state, after: storeChangeDelay, ifChangedFrom: nil)
            case .reading(let generation):
                state.flight = .readingStale(generation)
                return (state, [])
            case .readingStale:
                return (state, [])
            }
        case .statTick:
            guard state.watch == .stat else { return (state, []) }
            var effects: [Effect] = []
            if case .idle = state.flight {
                let read: [Effect]
                (state, read) = scheduleRead(state, after: 0, ifChangedFrom: state.stamps)
                effects.append(contentsOf: read)
            }
            effects.append(.scheduleStat(after: statInterval))
            return (state, effects)
        case .readFinished(let generation, let result, let stamps, let now):
            return finish(state, generation: generation, result: result, stamps: stamps, now: now)
        case .watchStarted:
            // The watch is asked for only after a reading has landed.
            guard case .named = state.route else { return (state, []) }
            let cancelStat = state.watch == .stat
            state.watch = .events
            return (state, cancelStat ? [.cancelStat] : [])
        case .watchFailed:
            guard state.route != .off else { return (state, []) }
            state.watch = .stat
            return (state, [.scheduleStat(after: statInterval)])
        case .openSettingsPressed:
            guard case .needsAccess = state.route else { return (state, []) }
            return (state, [.openPane])
        }
    }

    // MARK: Transitions

    private static func beginChecking(_ state: State) -> (State, [Effect]) {
        var state = state
        state.enabled = true
        state.route = .checking
        return scheduleRead(state, after: 0, ifChangedFrom: nil)
    }

    private static func scheduleRead(
        _ state: State,
        after: Double,
        ifChangedFrom stamps: Stamps?
    ) -> (State, [Effect]) {
        var state = state
        state.generation += 1
        let generation = state.generation
        state.flight = .reading(generation)
        return (state, [.read(generation: generation, after: after, ifChangedFrom: stamps)])
    }

    /// Switch off from any route. The generation moves, so a read already in flight cannot land.
    private static func turnOff(_ state: State) -> (State, [Effect]) {
        var state = state
        state.enabled = false
        state.route = .off
        state.reading = .unknown
        state.stamps = nil
        state.baselineTaken = false
        state.malformedStreak = 0
        state.flight = .idle
        state.watch = .none
        state.generation += 1
        return (state, [.cancelRead, .stopWatch, .cancelStat, .withdrawCue])
    }

    private static func applyHidden(_ state: State, _ hidden: Bool) -> (State, [Effect]) {
        var state = state
        if hidden == state.detailsHidden { return (state, []) }
        state.detailsHidden = hidden
        if hidden { return (state, [.withdrawCue]) }
        return (state, [])
    }

    private static func rechecks(_ route: Route) -> Bool {
        switch route {
        case .named, .needsAccess, .unavailable: return true
        case .off, .checking: return false
        }
    }

    private static func finish(
        _ state: State,
        generation: Int,
        result: Read,
        stamps: Stamps?,
        now: Double
    ) -> (State, [Effect]) {
        let stale: Bool
        switch state.flight {
        case .reading(let flight) where flight == generation:
            stale = false
        case .readingStale(let flight) where flight == generation:
            stale = true
        default:
            return (state, [])
        }

        var state = state
        state.flight = .idle
        var effects: [Effect] = []
        switch result {
        case .unchanged:
            break
        case .denied:
            (state, effects) = clear(state, to: .needsAccess)
        case .missing:
            (state, effects) = clear(state, to: .unavailable(.missing))
        case .unreadable(let reason):
            if keepsLastReading(state, malformed: reason) {
                state.malformedStreak = 1
                (state, effects) = scheduleRead(state, after: malformedRetryDelay, ifChangedFrom: nil)
            } else {
                (state, effects) = clear(state, to: .unavailable(.unreadable(reason)))
            }
        case .ok(let reading):
            (state, effects) = accept(state, reading: reading, stamps: stamps, now: now)
        }
        if stale, case .idle = state.flight {
            let more: [Effect]
            (state, more) = scheduleRead(state, after: 0, ifChangedFrom: nil)
            effects.append(contentsOf: more)
        }
        return (state, effects)
    }

    /// One malformed read while a name is showing keeps that name and tries once more.
    private static func keepsLastReading(_ state: State, malformed reason: Read.Reason) -> Bool {
        guard reason == .malformed, state.malformedStreak == 0, case .named = state.route else { return false }
        if case .on = state.reading { return true }
        return false
    }

    private static func clear(_ state: State, to route: Route) -> (State, [Effect]) {
        var state = state
        state.route = route
        state.reading = .unknown
        state.stamps = nil
        state.baselineTaken = false
        state.malformedStreak = 0
        state.flight = .idle
        state.watch = .none
        return (state, [.stopWatch, .cancelStat])
    }

    /// The first settled reading after off, a refusal, or an unavailable route draws no cue.
    private static func accept(
        _ state: State,
        reading: Reading,
        stamps: Stamps?,
        now: Double
    ) -> (State, [Effect]) {
        var state = state
        let previous = state.reading
        let baseline = !state.baselineTaken
        state.route = .named
        state.reading = reading
        state.stamps = stamps
        state.malformedStreak = 0
        state.baselineTaken = true
        var effects: [Effect] = []
        if !baseline,
           let edge = SystemFocusEdge.between(previous, reading),
           SystemFocusCueLimit.allows(times: state.cueTimes, now: now) {
            effects.append(.cue(SystemFocusDisplay.cue(for: edge, reading: reading, hidden: state.detailsHidden)))
            state.cueTimes.append(now)
            if state.cueTimes.count > SystemFocusCueLimit.maximum {
                state.cueTimes.removeFirst(state.cueTimes.count - SystemFocusCueLimit.maximum)
            }
        }
        if state.watch == .none {
            effects.append(.startWatch)
        }
        return (state, effects)
    }
}

/// On, replaced, off, or no change. The same id and the same name are no change.
public enum SystemFocusEdge: Equatable, Sendable {
    case turnedOn
    case replaced
    case turnedOff

    public static func between(
        _ previous: SystemFocusMachine.Reading,
        _ next: SystemFocusMachine.Reading
    ) -> SystemFocusEdge? {
        switch (previous, next) {
        case (.on(let old), .on(let new)):
            if old.id == new.id && old.name == new.name { return nil }
            return .replaced
        case (.on, .off):
            return .turnedOff
        case (.off, .on), (.unknown, .on):
            return .turnedOn
        default:
            return nil
        }
    }
}

/// At most three cues in any 30 seconds. A fourth inside that window is withheld.
public enum SystemFocusCueLimit {
    public static let window: Double = 30
    public static let maximum = 3

    public static func allows(times: [Double], now: Double) -> Bool {
        let inside = times.filter { now - $0 >= 0 && now - $0 <= window }
        return inside.count < maximum
    }
}
