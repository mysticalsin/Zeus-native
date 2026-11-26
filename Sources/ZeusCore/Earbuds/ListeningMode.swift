/// Listening mode rules. The panel shows what was read, never what was asked.
/// The class-property grant stays in the shared types file and is not declared here.
/// The shared route type stays in the route file and is not declared here.
/// This file checks the two Bluetooth transport codes itself.

/// Off, noise cancelling, transparency, and adaptive. Adaptive is shown and is never a choice.
public enum ListeningMode: Equatable, Hashable, Sendable {
    case off
    case noiseCancelling
    case transparency
    case adaptive
}

public enum ListeningModeCode {
    /// 1 off, 2 noise cancelling, 3 transparency, 4 adaptive. Any other raw value is nil.
    public static func mode(_ raw: UInt32) -> ListeningMode? {
        switch raw {
        case 1: .off
        case 2: .noiseCancelling
        case 3: .transparency
        case 4: .adaptive
        default: nil
        }
    }

    public static func code(_ mode: ListeningMode) -> UInt32 {
        switch mode {
        case .off: 1
        case .noiseCancelling: 2
        case .transparency: 3
        case .adaptive: 4
        }
    }
}

/// A mode the mask offers, still available or already refused.
public struct ModeChoice: Equatable, Hashable, Sendable {
    public enum Offer: Equatable, Hashable, Sendable {
        case available
        case refused
    }

    public var mode: ListeningMode
    public var offer: Offer

    public init(mode: ListeningMode, offer: Offer) {
        self.mode = mode
        self.offer = offer
    }
}

public enum ListeningModeMask {
    /// Off is always offered. Noise cancelling is bit 0. Transparency is bit 1.
    /// Nil when the mask cannot be read, or when the current mode is 2, 3, or 4 and its own bit is clear.
    /// Adaptive is bit 2 for that check only. It is never a choice.
    public static func choices(raw: UInt32?, current: ListeningMode) -> [ModeChoice]? {
        guard let raw else { return nil }
        if let bit = ownBit(current), raw & bit == 0 { return nil }
        var choices = [ModeChoice(mode: .off, offer: .available)]
        if raw & 1 != 0 { choices.append(ModeChoice(mode: .noiseCancelling, offer: .available)) }
        if raw & 2 != 0 { choices.append(ModeChoice(mode: .transparency, offer: .available)) }
        return choices
    }

    private static func ownBit(_ mode: ListeningMode) -> UInt32? {
        switch mode {
        case .off: nil
        case .noiseCancelling: 1
        case .transparency: 2
        case .adaptive: 4
        }
    }
}

public enum ListeningModeRelease {
    /// The floor stays at 27.2 until an owner check lowers it.
    public static let verifiedFrom: (major: Int, minor: Int) = (major: 27, minor: 2)

    public static func allowed(major: Int, minor: Int) -> Bool {
        major > verifiedFrom.major || (major == verifiedFrom.major && minor >= verifiedFrom.minor)
    }
}

/// Object id plus generation. A later generation is a different device.
public struct ModeKey: Equatable, Hashable, Sendable {
    public var objectID: UInt32
    public var generation: Int

    public init(objectID: UInt32, generation: Int) {
        self.objectID = objectID
        self.generation = generation
    }
}

public struct ModeProbe: Equatable, Sendable {
    public var key: ModeKey
    public var uid: String
    public var name: String
    public var transportCode: UInt32?
    public var hasProperty: Bool
    public var byteSize: Int
    public var rawMode: UInt32?
    public var rawMask: UInt32?

    public init(
        key: ModeKey, uid: String, name: String, transportCode: UInt32?,
        hasProperty: Bool, byteSize: Int, rawMode: UInt32?, rawMask: UInt32?
    ) {
        self.key = key
        self.uid = uid
        self.name = name
        self.transportCode = transportCode
        self.hasProperty = hasProperty
        self.byteSize = byteSize
        self.rawMode = rawMode
        self.rawMask = rawMask
    }

    /// Release allowed, a Bluetooth transport code, the property present, size 4,
    /// a known mode, and trusted choices with at least two entries. Otherwise nil.
    public func bound(release: (major: Int, minor: Int)) -> ListeningModeMachine.Bound? {
        guard ListeningModeRelease.allowed(major: release.major, minor: release.minor) else { return nil }
        guard ListeningModeLink.isBluetooth(transportCode) else { return nil }
        guard hasProperty, byteSize == 4 else { return nil }
        guard let rawMode, let current = ListeningModeCode.mode(rawMode) else { return nil }
        guard let choices = ListeningModeMask.choices(raw: rawMask, current: current), choices.count >= 2 else {
            return nil
        }
        return ListeningModeMachine.Bound(
            key: key, uid: uid, name: name, current: current, choices: choices, refused: nil
        )
    }
}

public enum ModeOutcome: Equatable, Sendable {
    case changed(ListeningMode)
    case stayed(ListeningMode)
}

public enum ListeningModeStatus: Equatable, Sendable {
    case hidden
    case shown(
        deviceName: String, outputUID: String, current: ListeningMode,
        choices: [ModeChoice], pending: ListeningMode?
    )
}

/// The only place the listening-mode route changes.
public enum ListeningModeMachine {
    public static let readBackDelay: Double = 0.5
    public static let readBackRetry: Double = 1

    public struct Bound: Equatable, Sendable {
        public var key: ModeKey
        public var uid: String
        public var name: String
        public var current: ListeningMode
        public var choices: [ModeChoice]
        public var refused: ListeningMode?

        public init(
            key: ModeKey, uid: String, name: String, current: ListeningMode,
            choices: [ModeChoice], refused: ListeningMode?
        ) {
            self.key = key
            self.uid = uid
            self.name = name
            self.current = current
            self.choices = choices
            self.refused = refused
        }
    }

    public struct Setting: Equatable, Sendable {
        public var bound: Bound
        public var target: ListeningMode
        public var token: Int
        public var attempt: Int
        public var closeAfter: Bool

        public init(bound: Bound, target: ListeningMode, token: Int, attempt: Int, closeAfter: Bool) {
            self.bound = bound
            self.target = target
            self.token = token
            self.attempt = attempt
            self.closeAfter = closeAfter
        }
    }

    public enum Route: Equatable, Sendable {
        case off
        case dormant
        case absent
        case ready(Bound)
        case setting(Setting)
    }

    public struct State: Equatable, Sendable {
        public var route: Route
        public var releaseMajor: Int
        public var releaseMinor: Int
        public var nextToken: Int
        public var flight: Int?

        public init(
            route: Route = .off,
            releaseMajor: Int = ListeningModeRelease.verifiedFrom.major,
            releaseMinor: Int = ListeningModeRelease.verifiedFrom.minor,
            nextToken: Int = 1,
            flight: Int? = nil
        ) {
            self.route = route
            self.releaseMajor = releaseMajor
            self.releaseMinor = releaseMinor
            self.nextToken = nextToken
            self.flight = flight
        }

        public static var off: State { State() }
    }

    public enum Event: Equatable, Sendable {
        case switched(on: Bool)
        case panelOpened
        case panelClosed
        case probed(token: Int, probe: ModeProbe?)
        case outputChanged
        case externalChange(key: ModeKey, raw: UInt32)
        case chosen(ListeningMode)
        case writeFinished(token: Int, ok: Bool)
        case readBack(token: Int, raw: UInt32?)
    }

    public enum Effect: Equatable, Sendable {
        case watchOutput
        case unwatchOutput
        case probe(Int)
        case listen(ModeKey)
        case stopListening
        case write(key: ModeKey, code: UInt32, token: Int)
        case scheduleReadBack(key: ModeKey, token: Int, after: Double)
        case announce(ModeOutcome)
    }

    public static func reduce(_ state: State, _ event: Event) -> (State, [Effect]) {
        switch event {
        case .switched(let on):
            return switched(state, on: on)
        case .panelOpened:
            return panelOpened(state)
        case .panelClosed:
            return panelClosed(state)
        case .probed(let token, let probe):
            return probed(state, token: token, probe: probe)
        case .outputChanged:
            return outputChanged(state)
        case .externalChange(let key, let raw):
            return externalChange(state, key: key, raw: raw)
        case .chosen(let mode):
            return chosen(state, mode)
        case .writeFinished(let token, let ok):
            return writeFinished(state, token: token, ok: ok)
        case .readBack(let token, let raw):
            return readBack(state, token: token, raw: raw)
        }
    }

    public static func status(_ state: State) -> ListeningModeStatus {
        switch state.route {
        case .ready(let bound):
            return .shown(
                deviceName: bound.name, outputUID: bound.uid, current: bound.current,
                choices: bound.choices, pending: nil
            )
        case .setting(let setting):
            return .shown(
                deviceName: setting.bound.name, outputUID: setting.bound.uid,
                current: setting.bound.current, choices: setting.bound.choices, pending: setting.target
            )
        case .off, .dormant, .absent:
            return .hidden
        }
    }

    private static func switched(_ state: State, on: Bool) -> (State, [Effect]) {
        if !on {
            return (parked(state, .off), [.stopListening, .unwatchOutput])
        }
        guard state.route == .off else { return (state, []) }
        return (parked(state, .dormant), [])
    }

    private static func panelOpened(_ state: State) -> (State, [Effect]) {
        guard state.route == .dormant else { return (state, []) }
        var next = state
        next.route = .absent
        let token = mint(&next)
        next.flight = token
        return (next, [.watchOutput, .probe(token)])
    }

    private static func panelClosed(_ state: State) -> (State, [Effect]) {
        switch state.route {
        case .off, .dormant:
            return (state, [])
        case .setting(var setting):
            if setting.closeAfter { return (state, []) }
            setting.closeAfter = true
            var next = state
            next.route = .setting(setting)
            return (next, [])
        case .absent, .ready:
            return (parked(state, .dormant), [.stopListening, .unwatchOutput])
        }
    }

    private static func probed(_ state: State, token: Int, probe: ModeProbe?) -> (State, [Effect]) {
        guard state.flight == token else { return (state, []) }
        var next = state
        next.flight = nil
        let release = (major: state.releaseMajor, minor: state.releaseMinor)
        guard let probe, let bound = probe.bound(release: release) else {
            next.route = .absent
            return (next, [])
        }
        next.route = .ready(bound)
        return (next, [.listen(bound.key)])
    }

    private static func outputChanged(_ state: State) -> (State, [Effect]) {
        if case .setting(let setting) = state.route, setting.closeAfter {
            return (parked(state, .dormant), [.stopListening, .unwatchOutput])
        }
        switch state.route {
        case .off, .dormant:
            return (state, [])
        case .absent, .ready, .setting:
            var next = state
            next.route = .absent
            let token = mint(&next)
            next.flight = token
            return (next, [.stopListening, .probe(token)])
        }
    }

    private static func externalChange(_ state: State, key: ModeKey, raw: UInt32) -> (State, [Effect]) {
        guard case .ready(var bound) = state.route, bound.key == key else { return (state, []) }
        guard let mode = ListeningModeCode.mode(raw) else {
            return (parked(state, .absent), [.stopListening])
        }
        guard mode != bound.current else { return (state, []) }
        bound.current = mode
        bound.choices = bound.choices.map { choice in
            guard choice.mode == mode else { return choice }
            return ModeChoice(mode: choice.mode, offer: .available)
        }
        if bound.refused == mode { bound.refused = nil }
        var next = state
        next.route = .ready(bound)
        return (next, [])
    }

    private static func chosen(_ state: State, _ mode: ListeningMode) -> (State, [Effect]) {
        guard case .ready(let bound) = state.route else { return (state, []) }
        guard mode != bound.current, bound.refused != mode else { return (state, []) }
        guard bound.choices.contains(where: { $0.mode == mode && $0.offer == .available }) else {
            return (state, [])
        }
        var next = state
        let token = mint(&next)
        next.route = .setting(Setting(
            bound: bound, target: mode, token: token, attempt: 1, closeAfter: false
        ))
        return (next, [.write(key: bound.key, code: ListeningModeCode.code(mode), token: token)])
    }

    private static func writeFinished(_ state: State, token: Int, ok: Bool) -> (State, [Effect]) {
        guard case .setting(let setting) = state.route, setting.token == token else { return (state, []) }
        if !ok {
            return settle(state, setting: setting, current: setting.bound.current, refuse: setting.target, outcome: .stayed(setting.bound.current))
        }
        return (state, [.scheduleReadBack(key: setting.bound.key, token: token, after: readBackDelay)])
    }

    private static func readBack(_ state: State, token: Int, raw: UInt32?) -> (State, [Effect]) {
        guard case .setting(let setting) = state.route, setting.token == token else { return (state, []) }
        guard let raw, let mode = ListeningModeCode.mode(raw) else {
            if setting.closeAfter {
                return (parked(state, .dormant), [.stopListening, .unwatchOutput])
            }
            return (parked(state, .absent), [.stopListening])
        }
        if mode == setting.target {
            return settle(state, setting: setting, current: mode, refuse: nil, outcome: .changed(mode))
        }
        if setting.attempt == 1 {
            var next = state
            var retry = setting
            retry.attempt = 2
            next.route = .setting(retry)
            return (next, [.scheduleReadBack(key: setting.bound.key, token: token, after: readBackRetry)])
        }
        return settle(state, setting: setting, current: mode, refuse: setting.target, outcome: .stayed(mode))
    }

    private static func settle(
        _ state: State, setting: Setting, current: ListeningMode, refuse: ListeningMode?, outcome: ModeOutcome
    ) -> (State, [Effect]) {
        var bound = setting.bound
        bound.current = current
        if let refuse, refuse != current {
            bound.refused = refuse
            bound.choices = bound.choices.map { choice in
                guard choice.mode == refuse else { return choice }
                return ModeChoice(mode: choice.mode, offer: .refused)
            }
        } else if bound.refused == current {
            bound.refused = nil
        }
        bound.choices = bound.choices.map { choice in
            guard choice.mode == current else { return choice }
            return ModeChoice(mode: choice.mode, offer: .available)
        }
        let announced: [Effect] = [.announce(outcome)]
        if setting.closeAfter {
            return (parked(state, .dormant), announced + [.stopListening, .unwatchOutput])
        }
        var next = state
        next.route = .ready(bound)
        next.flight = nil
        return (next, announced)
    }

    private static func parked(_ state: State, _ route: Route) -> State {
        var next = state
        next.route = route
        next.flight = nil
        return next
    }

    private static func mint(_ state: inout State) -> Int {
        let token = state.nextToken
        state.nextToken += 1
        return token
    }
}

enum ListeningModeLink {
    static func isBluetooth(_ code: UInt32?) -> Bool {
        guard let code, code != 0 else { return false }
        return code == fourCC("blue") || code == fourCC("blea")
    }

    /// Four-character code, big endian, the same width Core Audio uses.
    static func fourCC(_ text: String) -> UInt32 {
        let bytes = Array(text.utf8)
        guard bytes.count == 4 else { return 0 }
        return bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }
}
