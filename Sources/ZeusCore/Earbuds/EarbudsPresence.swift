/// Grant values this reducer stores.
/// The class-property grant stays in the shared types file and is not declared here.
public enum EarbudsGrant: Hashable, Sendable {
    case notAsked
    case restricted
    case denied
    case allowed
}

/// Opaque address. Its text forms are the word "earbuds" and nothing else.
public struct EarbudsID: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let address: String

    public init(_ address: String) { self.address = address }

    public var description: String { "earbuds" }
    public var debugDescription: String { "earbuds" }
    public var customMirror: Mirror { Mirror(self, children: [] as [Mirror.Child]) }
}

public struct DeviceFacts: Equatable, Hashable, Sendable {
    public static let audioMajor: UInt8 = 0x04
    public static let headset: UInt8 = 0x01
    public static let handsFree: UInt8 = 0x02
    public static let headphones: UInt8 = 0x06

    public var id: EarbudsID
    public var name: String
    public var paired: Bool
    public var major: UInt8
    public var minor: UInt8

    public init(id: EarbudsID, name: String, paired: Bool, major: UInt8, minor: UInt8) {
        self.id = id
        self.name = name
        self.paired = paired
        self.major = major
        self.minor = minor
    }

    /// Paired, audio major class, and a minor of headset, hands-free, or headphones.
    public var qualifies: Bool {
        paired && major == Self.audioMajor
            && (minor == Self.headset || minor == Self.handsFree || minor == Self.headphones)
    }
}

/// A cue value. Description, debug text, and the mirror carry no name and no address.
public struct EarbudsCue: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public enum Event: Hashable, Sendable {
        case connected
        case disconnected
    }

    public var id: EarbudsID
    public var name: String
    public var event: Event
    public var levels: [EarbudsPart: BatteryLevel]

    public init(id: EarbudsID, name: String, event: Event, levels: [EarbudsPart: BatteryLevel]) {
        self.id = id
        self.name = name
        self.event = event
        self.levels = levels
    }

    public var description: String { "earbuds" }
    public var debugDescription: String { "earbuds" }
    public var customMirror: Mirror { Mirror(self, children: [] as [Mirror.Child]) }
}

public struct EarbudsDeviceView: Equatable, Sendable {
    public var id: EarbudsID
    public var name: String
    public var parts: [EarbudsPart]
    public var levels: [EarbudsPart: BatteryLevel]

    public init(id: EarbudsID, name: String, parts: [EarbudsPart], levels: [EarbudsPart: BatteryLevel]) {
        self.id = id
        self.name = name
        self.parts = parts
        self.levels = levels
    }
}

public struct EarbudsStatus: Equatable, Sendable {
    public var switchOn: Bool
    public var access: EarbudsGrant
    public var asking: Bool
    public var eventsClosed: Bool
    public var batteryClosed: Bool
    public var shown: EarbudsDeviceView?

    public init(
        switchOn: Bool, access: EarbudsGrant, asking: Bool, eventsClosed: Bool,
        batteryClosed: Bool, shown: EarbudsDeviceView?
    ) {
        self.switchOn = switchOn
        self.access = access
        self.asking = asking
        self.eventsClosed = eventsClosed
        self.batteryClosed = batteryClosed
        self.shown = shown
    }

    public static let snapshotSample = EarbudsStatus(
        switchOn: true, access: .allowed, asking: false, eventsClosed: false, batteryClosed: false,
        shown: EarbudsDeviceView(
            id: EarbudsID("snapshot"), name: "Earbuds",
            parts: [.left, .right, .case],
            levels: [.left: .fresh(80), .right: .fresh(75), .case: .lastKnown(60)]
        )
    )
}

/// Presence and battery reducer. The only place the route changes.
public enum EarbudsPresence {
    public static let quietWindow: Double = 2
    public static let cueLimit: Double = 10
    public static let levelsWindow: Double = 4
    public static let askWait: Double = 60
    public static let maxDevices = 8
    public static let firstRead: Double = 1
    public static let secondRead: Double = 2.5

    public enum BatteryRoute: Equatable, Sendable {
        case unchecked
        case open
        case closed
    }

    public struct Watch: Equatable, Sendable {
        public struct Device: Equatable, Sendable {
            public var facts: DeviceFacts
            public var book = BatteryBook()
            public var connected: Bool
            public var generation: Int
            public var connectedAt: Double
            public var disconnectedAt: Double?
            public var lastCueAt: Double?
            public var connectCueAt: Double?
            public var levelsCued = false
            public var flight: Int?
            public var due: [Int] = []
            public var answering: Set<EarbudsPart> = []
        }

        public var quietUntil: Double
        public var asleep: Bool
        public var locked: Bool
        public var battery: BatteryRoute
        public var devices: [Device]
    }

    public enum Route: Equatable, Sendable {
        case off
        case needsAccess(EarbudsGrant)
        case asking(Int)
        case watching(Watch)
        case away
        case eventsClosed
    }

    public struct State: Equatable, Sendable {
        public var route: Route
        public var nextToken: Int

        public init(route: Route = .off, nextToken: Int = 1) {
            self.route = route
            self.nextToken = nextToken
        }

        public static var off: State { State() }
    }

    public enum Event: Equatable, Sendable {
        case switched(on: Bool, access: EarbudsGrant)
        case allowPressed(EarbudsGrant)
        case accessAnswered(token: Int, access: EarbudsGrant)
        case askTimedOut(Int)
        case accessRead(EarbudsGrant)
        case started(seed: [DeviceFacts], now: Double)
        case registrationFailed
        case batteryRouteChecked(open: Bool)
        case connected(DeviceFacts, now: Double)
        case disconnected(id: EarbudsID, now: Double)
        case readDue(id: EarbudsID, token: Int)
        case batteryRead(
            id: EarbudsID, token: Int, raw: [EarbudsPart: Int?],
            answering: Set<EarbudsPart>, now: Double
        )
        case panelOpened
        case willSleep
        case woke(Double)
        case resynced(seed: [DeviceFacts], now: Double)
        case session(active: Bool, locked: Bool)
    }

    public enum Effect: Equatable, Sendable {
        case requestAccess(Int)
        case askTimeout(token: Int, after: Double)
        case abandonRequest
        case storeSwitch(Bool)
        case startWatching
        case stopWatching
        case watchDisconnect(EarbudsID)
        case unwatch(EarbudsID)
        case scheduleRead(id: EarbudsID, token: Int, after: Double)
        case readBattery(id: EarbudsID, token: Int)
        case resync
        case showCue(EarbudsCue)
    }

    public static func reduce(_ state: State, _ event: Event) -> (State, [Effect]) {
        switch event {
        case .switched(let on, let access):
            return switched(state, on: on, access: access)
        case .allowPressed(let access):
            return allowPressed(state, access)
        case .accessAnswered(let token, let access):
            return accessAnswered(state, token: token, access: access)
        case .askTimedOut(let token):
            return askTimedOut(state, token)
        case .accessRead(let access):
            return accessRead(state, access)
        case .registrationFailed:
            guard state.route != .eventsClosed else { return (state, []) }
            return (State(route: .eventsClosed, nextToken: state.nextToken), [.stopWatching])
        case .session(let active, let locked):
            return session(state, active: active, locked: locked)
        default:
            return inWatch(state, event)
        }
    }

    public static func status(_ state: State, now: Double) -> EarbudsStatus {
        switch state.route {
        case .off:
            return EarbudsStatus(
                switchOn: false, access: .notAsked, asking: false,
                eventsClosed: false, batteryClosed: false, shown: nil
            )
        case .needsAccess(let access):
            return EarbudsStatus(
                switchOn: true, access: access, asking: false,
                eventsClosed: false, batteryClosed: false, shown: nil
            )
        case .asking:
            return EarbudsStatus(
                switchOn: false, access: .notAsked, asking: true,
                eventsClosed: false, batteryClosed: false, shown: nil
            )
        case .watching(let watch):
            return EarbudsStatus(
                switchOn: true, access: .allowed, asking: false,
                eventsClosed: false, batteryClosed: watch.battery == .closed,
                shown: shown(watch, now: now)
            )
        case .away:
            return EarbudsStatus(
                switchOn: true, access: .allowed, asking: false,
                eventsClosed: false, batteryClosed: false, shown: nil
            )
        case .eventsClosed:
            return EarbudsStatus(
                switchOn: true, access: .allowed, asking: false,
                eventsClosed: true, batteryClosed: false, shown: nil
            )
        }
    }

    private static func switched(_ state: State, on: Bool, access: EarbudsGrant) -> (State, [Effect]) {
        if !on {
            return (State(route: .off, nextToken: state.nextToken), [.stopWatching, .abandonRequest])
        }
        switch state.route {
        case .off, .needsAccess:
            if access == .allowed {
                return (State(route: .watching(emptyWatch()), nextToken: state.nextToken), [.startWatching])
            }
            return (State(route: .needsAccess(access), nextToken: state.nextToken), [])
        case .watching, .asking, .away, .eventsClosed:
            return (state, [])
        }
    }

    private static func allowPressed(_ state: State, _ access: EarbudsGrant) -> (State, [Effect]) {
        if case .asking = state.route { return (state, []) }
        if access == .notAsked {
            let open = state.route == .off || state.route == .needsAccess(.notAsked)
            guard open else { return (state, []) }
            var state = state
            let token = mint(&state)
            state.route = .asking(token)
            return (state, [.requestAccess(token), .askTimeout(token: token, after: askWait)])
        }
        if access == .allowed {
            return (state, [.storeSwitch(true)])
        }
        return (state, [])
    }

    private static func accessAnswered(
        _ state: State, token: Int, access: EarbudsGrant
    ) -> (State, [Effect]) {
        guard case .asking(let pending) = state.route, pending == token else { return (state, []) }
        if access == .allowed {
            return (State(route: .off, nextToken: state.nextToken), [.storeSwitch(true)])
        }
        return (State(route: .needsAccess(access), nextToken: state.nextToken), [])
    }

    private static func askTimedOut(_ state: State, _ token: Int) -> (State, [Effect]) {
        guard case .asking(let pending) = state.route, pending == token else { return (state, []) }
        return (State(route: .needsAccess(.notAsked), nextToken: state.nextToken), [.abandonRequest])
    }

    private static func accessRead(_ state: State, _ access: EarbudsGrant) -> (State, [Effect]) {
        if access != .allowed, state.route == .away || isWatching(state) {
            return (State(route: .needsAccess(access), nextToken: state.nextToken), [.stopWatching])
        }
        if access == .allowed, case .needsAccess = state.route {
            return (State(route: .watching(emptyWatch()), nextToken: state.nextToken), [.startWatching])
        }
        return (state, [])
    }

    private static func session(_ state: State, active: Bool, locked: Bool) -> (State, [Effect]) {
        if case .watching(var watch) = state.route {
            if !active {
                return (State(route: .away, nextToken: state.nextToken), [.stopWatching])
            }
            watch.locked = locked
            return (State(route: .watching(watch), nextToken: state.nextToken), [])
        }
        if case .away = state.route, active {
            var watch = emptyWatch()
            watch.locked = locked
            return (State(route: .watching(watch), nextToken: state.nextToken), [.startWatching])
        }
        return (state, [])
    }

    private static func inWatch(_ state: State, _ event: Event) -> (State, [Effect]) {
        guard case .watching(var watch) = state.route else { return (state, []) }
        var state = state
        let effects = apply(&state, &watch, event)
        state.route = .watching(watch)
        return (state, effects)
    }

    private static func apply(_ state: inout State, _ watch: inout Watch, _ event: Event) -> [Effect] {
        switch event {
        case .started(let seed, let now):
            watch.quietUntil = now + quietWindow
            return recordSeed(&state, &watch, seed, now: now, readNow: true)
        case .batteryRouteChecked(let open):
            watch.battery = open ? .open : .closed
            return []
        case .connected(let facts, let now):
            return connect(&state, &watch, facts, now: now)
        case .disconnected(let id, let now):
            return disconnect(&watch, id: id, now: now)
        case .readDue(let id, let token):
            return readDue(&watch, id: id, token: token)
        case .batteryRead(let id, let token, let raw, let answering, let now):
            return batteryRead(&watch, id: id, token: token, raw: raw, answering: answering, now: now)
        case .panelOpened:
            return panelOpened(&state, &watch)
        case .willSleep:
            watch.asleep = true
            for index in watch.devices.indices { bump(&watch.devices[index]) }
            return []
        case .woke(let now):
            watch.asleep = false
            watch.quietUntil = now + quietWindow
            return [.resync]
        case .resynced(let seed, let now):
            return resync(&watch, seed, now: now)
        default:
            return []
        }
    }

    private static func recordSeed(
        _ state: inout State, _ watch: inout Watch, _ seed: [DeviceFacts], now: Double, readNow: Bool
    ) -> [Effect] {
        var effects: [Effect] = []
        for facts in seed where facts.qualifies {
            if watch.devices.contains(where: { $0.facts.id == facts.id }) { continue }
            guard watch.devices.count < maxDevices else { break }
            var device = newDevice(facts, now: now)
            effects.append(.watchDisconnect(facts.id))
            if readNow {
                effects.append(holdRead(&device, state: &state))
            }
            watch.devices.append(device)
        }
        return effects
    }

    private static func connect(
        _ state: inout State, _ watch: inout Watch, _ facts: DeviceFacts, now: Double
    ) -> [Effect] {
        guard facts.qualifies else { return [] }
        if let index = watch.devices.firstIndex(where: { $0.facts.id == facts.id }) {
            if watch.devices[index].connected {
                watch.devices[index].facts = facts
                return []
            }
            return reopen(&state, &watch, index: index, facts: facts, now: now)
        }
        var effects: [Effect] = []
        if watch.devices.count >= maxDevices {
            guard let victim = oldestDisconnected(watch) else { return [] }
            effects.append(.unwatch(victim))
            watch.devices.removeAll { $0.facts.id == victim }
        }
        var device = newDevice(facts, now: now)
        effects.append(.watchDisconnect(facts.id))
        effects.append(contentsOf: schedulePair(&device, state: &state))
        if noteConnectCue(&device, watch: watch, now: now) {
            effects.append(connectCue(device))
        }
        watch.devices.append(device)
        return effects
    }

    private static func reopen(
        _ state: inout State, _ watch: inout Watch, index: Int, facts: DeviceFacts, now: Double
    ) -> [Effect] {
        var device = watch.devices[index]
        bump(&device)
        device.facts = facts
        device.connected = true
        device.connectedAt = now
        device.disconnectedAt = nil
        var effects: [Effect] = [.watchDisconnect(facts.id)]
        effects.append(contentsOf: schedulePair(&device, state: &state))
        if noteConnectCue(&device, watch: watch, now: now) {
            effects.append(connectCue(device))
        }
        watch.devices[index] = device
        return effects
    }

    private static func disconnect(_ watch: inout Watch, id: EarbudsID, now: Double) -> [Effect] {
        guard let index = watch.devices.firstIndex(where: { $0.facts.id == id }),
              watch.devices[index].connected
        else { return [] }
        bump(&watch.devices[index])
        watch.devices[index].connected = false
        watch.devices[index].disconnectedAt = now
        var effects: [Effect] = [.unwatch(id)]
        if noteAnyCue(&watch.devices[index], watch: watch, now: now) {
            effects.append(EarbudsPresence.Effect.showCue(EarbudsCue(
                id: id, name: watch.devices[index].facts.name, event: .disconnected, levels: [:]
            )))
        }
        return effects
    }

    private static func readDue(_ watch: inout Watch, id: EarbudsID, token: Int) -> [Effect] {
        guard let index = watch.devices.firstIndex(where: { $0.facts.id == id }),
              let due = watch.devices[index].due.firstIndex(of: token)
        else { return [] }
        watch.devices[index].due.remove(at: due)
        if watch.battery == .closed || watch.devices[index].flight != nil || !watch.devices[index].connected {
            return []
        }
        watch.devices[index].flight = token
        return [.readBattery(id: id, token: token)]
    }

    private static func batteryRead(
        _ watch: inout Watch, id: EarbudsID, token: Int, raw: [EarbudsPart: Int?],
        answering: Set<EarbudsPart>, now: Double
    ) -> [Effect] {
        guard let index = watch.devices.firstIndex(where: { $0.facts.id == id }),
              watch.devices[index].flight == token
        else { return [] }
        watch.devices[index].flight = nil
        if watch.battery == .closed { return [] }
        watch.devices[index].answering = answering
        watch.devices[index].book.merge(raw, now: now)
        guard let connectAt = watch.devices[index].connectCueAt,
              now - connectAt < levelsWindow,
              !watch.devices[index].levelsCued,
              watch.devices[index].book.hasAnyFresh(now: now),
              !quiet(watch, now: now)
        else { return [] }
        watch.devices[index].levelsCued = true
        return [.showCue(EarbudsCue(
            id: id, name: watch.devices[index].facts.name, event: .connected,
            levels: cueLevels(watch.devices[index], now: now)
        ))]
    }

    private static func panelOpened(_ state: inout State, _ watch: inout Watch) -> [Effect] {
        guard watch.battery != .closed, let index = shownIndex(watch), watch.devices[index].flight == nil else {
            return []
        }
        return [holdRead(&watch.devices[index], state: &state)]
    }

    private static func resync(_ watch: inout Watch, _ seed: [DeviceFacts], now: Double) -> [Effect] {
        let live = seed.filter(\.qualifies)
        let liveIDs = Set(live.map(\.id))
        var effects: [Effect] = []
        for index in watch.devices.indices where watch.devices[index].connected && !liveIDs.contains(watch.devices[index].facts.id) {
            let id = watch.devices[index].facts.id
            bump(&watch.devices[index])
            watch.devices[index].connected = false
            watch.devices[index].disconnectedAt = now
            effects.append(.unwatch(id))
        }
        for facts in live {
            if let index = watch.devices.firstIndex(where: { $0.facts.id == facts.id }) {
                if !watch.devices[index].connected {
                    bump(&watch.devices[index])
                    watch.devices[index].facts = facts
                    watch.devices[index].connected = true
                    watch.devices[index].connectedAt = now
                    watch.devices[index].disconnectedAt = nil
                    effects.append(.watchDisconnect(facts.id))
                }
                continue
            }
            guard watch.devices.count < maxDevices else { continue }
            let device = newDevice(facts, now: now)
            effects.append(.watchDisconnect(facts.id))
            watch.devices.append(device)
        }
        return effects
    }

    private static func newDevice(_ facts: DeviceFacts, now: Double) -> Watch.Device {
        Watch.Device(facts: facts, connected: true, generation: 1, connectedAt: now)
    }

    private static func schedulePair(_ device: inout Watch.Device, state: inout State) -> [Effect] {
        let first = mint(&state)
        let second = mint(&state)
        device.due.append(first)
        device.due.append(second)
        return [
            .scheduleRead(id: device.facts.id, token: first, after: firstRead),
            .scheduleRead(id: device.facts.id, token: second, after: secondRead),
        ]
    }

    private static func holdRead(_ device: inout Watch.Device, state: inout State) -> Effect {
        let token = mint(&state)
        device.flight = token
        return .readBattery(id: device.facts.id, token: token)
    }

    private static func noteConnectCue(_ device: inout Watch.Device, watch: Watch, now: Double) -> Bool {
        guard !quiet(watch, now: now), !insideLimit(device, now: now) else { return false }
        device.lastCueAt = now
        device.connectCueAt = now
        device.levelsCued = false
        return true
    }

    private static func noteAnyCue(_ device: inout Watch.Device, watch: Watch, now: Double) -> Bool {
        guard !quiet(watch, now: now), !insideLimit(device, now: now) else { return false }
        device.lastCueAt = now
        return true
    }

    private static func connectCue(_ device: Watch.Device) -> Effect {
        .showCue(EarbudsCue(id: device.facts.id, name: device.facts.name, event: .connected, levels: [:]))
    }

    private static func quiet(_ watch: Watch, now: Double) -> Bool {
        now < watch.quietUntil || watch.asleep || watch.locked
    }

    private static func insideLimit(_ device: Watch.Device, now: Double) -> Bool {
        guard let last = device.lastCueAt else { return false }
        return now - last < cueLimit
    }

    private static func cueLevels(_ device: Watch.Device, now: Double) -> [EarbudsPart: BatteryLevel] {
        var levels: [EarbudsPart: BatteryLevel] = [:]
        for part in EarbudsParts.layout(answering: device.answering) {
            let level = device.book.level(part, now: now)
            if case .unknown = level { continue }
            levels[part] = level
        }
        return levels
    }

    private static func oldestDisconnected(_ watch: Watch) -> EarbudsID? {
        watch.devices
            .filter { !$0.connected }
            .min { lhs, rhs in (lhs.disconnectedAt ?? 0) < (rhs.disconnectedAt ?? 0) }?
            .facts.id
    }

    private static func shown(_ watch: Watch, now: Double) -> EarbudsDeviceView? {
        guard let index = shownIndex(watch) else { return nil }
        let device = watch.devices[index]
        let parts = EarbudsParts.layout(answering: device.answering)
        var levels: [EarbudsPart: BatteryLevel] = [:]
        for part in parts {
            levels[part] = device.book.level(part, now: now)
        }
        return EarbudsDeviceView(id: device.facts.id, name: device.facts.name, parts: parts, levels: levels)
    }

    private static func shownIndex(_ watch: Watch) -> Int? {
        let connected = watch.devices.enumerated().filter(\.element.connected)
        return connected.max { lhs, rhs in
            if lhs.element.connectedAt == rhs.element.connectedAt { return lhs.offset < rhs.offset }
            return lhs.element.connectedAt < rhs.element.connectedAt
        }?.offset
    }

    private static func bump(_ device: inout Watch.Device) {
        device.generation += 1
        device.flight = nil
        device.due.removeAll()
    }

    private static func mint(_ state: inout State) -> Int {
        let token = state.nextToken
        state.nextToken += 1
        return token
    }

    private static func emptyWatch() -> Watch {
        Watch(quietUntil: 0, asleep: false, locked: false, battery: .unchecked, devices: [])
    }

    private static func isWatching(_ state: State) -> Bool {
        if case .watching = state.route { return true }
        return false
    }
}
