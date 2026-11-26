import Foundation

/// Network speaker names and the discovery reducer.
///
/// A sighting is a service announcement. This file cleans the name, drops a computer,
/// and folds the two service types into one row. Turning the setting on reaches the
/// collapsed part. The browse starts when that part opens. Names stay in the reducer
/// value until the part closes or the setting turns off.
public enum SpeakerService: Equatable, Sendable {
    case airplay
    case raop

    /// Bonjour type the browser would watch. This file does not browse.
    public var type: String {
        switch self {
        case .airplay: "_airplay._tcp"
        case .raop: "_raop._tcp"
        }
    }

    /// TXT record key that carries the model.
    public var modelKey: String {
        switch self {
        case .airplay: "model"
        case .raop: "am"
        }
    }
}

/// One announcement. `model` is the single record value, already read by a browser.
public struct SpeakerSighting: Equatable, Sendable {
    public var service: SpeakerService
    public var rawName: String
    public var model: String?

    public init(service: SpeakerService, rawName: String, model: String?) {
        self.service = service
        self.rawName = rawName
        self.model = model
    }
}

/// What a kept announcement is. A computer model is absent, so the sighting is dropped.
public enum SpeakerKind: Equatable, Sendable {
    case homeSpeaker
    case television
    case speaker

    public static let modelLimit = 64

    public var symbol: String {
        switch self {
        case .homeSpeaker: "homepod"
        case .television: "appletv"
        case .speaker: "hifispeaker"
        }
    }

    /// ASCII, at most 64 characters, matched by prefix. Anything else is a plain speaker.
    /// `Mac`, `iMac` and `MacBook` are absent.
    public init?(model: String?) {
        if let model, !model.isEmpty, model.unicodeScalars.allSatisfy(\.isASCII), model.count <= Self.modelLimit {
            if model.hasPrefix("AudioAccessory") {
                self = .homeSpeaker
                return
            }
            if model.hasPrefix("AppleTV") {
                self = .television
                return
            }
            if model.hasPrefix("MacBook") || model.hasPrefix("iMac") || model.hasPrefix("Mac") {
                return nil
            }
        }
        self = .speaker
    }
}

/// One speaker the network part can show.
public struct NetworkSpeaker: Equatable, Sendable {
    public var name: String
    public var kind: SpeakerKind

    public init(name: String, kind: SpeakerKind) {
        self.name = name
        self.kind = kind
    }
}

/// Transport of an output already in the device list. Only `wirelessSpeaker` can take a new symbol.
public enum SpeakerListedTransport: Equatable, Sendable {
    case builtIn
    case wired
    case bluetooth
    case wirelessSpeaker
    case display
    case virtual
    case other
}

/// A device row this reader can mark. The name is the listed route name.
public struct SpeakerListedRoute: Equatable, Sendable {
    public var name: String
    public var transport: SpeakerListedTransport
    public var symbol: String

    public init(name: String, transport: SpeakerListedTransport, symbol: String) {
        self.name = name
        self.transport = transport
        self.symbol = symbol
    }
}

/// Name cleaning, de-duplication, and the symbol upgrade for a wireless route.
public enum NetworkSpeakerRules {
    public static let sightingCap = 128
    public static let rowCap = 24
    public static let nameLimit = 48

    private static let matchLocale = Locale(identifier: "en_US")
    private static let matchOptions: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
    private static let sortOptions: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .numeric]

    /// For `raop`, a leading run of 12 to 16 hex digits followed by `@` is removed. Then the name is cleaned.
    public static func displayName(_ raw: String, service: SpeakerService) -> String? {
        clean(service == .raop ? stripRaopIdentifier(raw) : raw)
    }

    /// At most 128 sightings. Empties, computers, and this Mac's own name are dropped.
    /// One row per name, ignoring case and diacritics. The AirPlay model's kind wins.
    public static func merge(_ sightings: [SpeakerSighting], ownName: String) -> [NetworkSpeaker] {
        let own = clean(ownName)
        var slots: [Slot] = []
        for sighting in sightings.prefix(sightingCap) {
            guard let name = displayName(sighting.rawName, service: sighting.service) else { continue }
            if let own, sameName(own, name) { continue }
            let kind = SpeakerKind(model: sighting.model)
            if sighting.service == .airplay {
                guard let kind else {
                    poison(&slots, name: name)
                    continue
                }
                if let index = slots.firstIndex(where: { sameName($0.name, name) }) {
                    if slots[index].poisoned || slots[index].fromAirplay { continue }
                    slots[index].speaker = NetworkSpeaker(name: slots[index].speaker?.name ?? name, kind: kind)
                    slots[index].fromAirplay = true
                } else {
                    slots.append(Slot(name: name, speaker: NetworkSpeaker(name: name, kind: kind), fromAirplay: true, poisoned: false))
                }
                continue
            }
            if slots.contains(where: { sameName($0.name, name) }) { continue }
            guard let kind else { continue }
            slots.append(Slot(name: name, speaker: NetworkSpeaker(name: name, kind: kind), fromAirplay: false, poisoned: false))
        }
        return slots.compactMap(\.speaker)
    }

    /// Names equal to a listed route are left out. At most 24, sorted by name.
    public static func rows(found: [NetworkSpeaker], routes: [String]) -> [NetworkSpeaker] {
        let listed = routes.compactMap { clean($0) }
        let kept = found.filter { speaker in
            !listed.contains { sameName($0, speaker.name) }
        }
        let sorted = kept.sorted {
            $0.name.compare($1.name, options: sortOptions, locale: matchLocale) == .orderedAscending
        }
        return Array(sorted.prefix(rowCap))
    }

    /// A wireless route whose name matches a found speaker takes that kind's symbol.
    public static func withKindSymbols(_ routes: [SpeakerListedRoute], found: [NetworkSpeaker]) -> [SpeakerListedRoute] {
        routes.map { route in
            guard route.transport == .wirelessSpeaker, let name = clean(route.name) else { return route }
            guard let match = found.first(where: { sameName($0.name, name) }) else { return route }
            var copy = route
            copy.symbol = match.kind.symbol
            return copy
        }
    }

    private struct Slot {
        var name: String
        var speaker: NetworkSpeaker?
        var fromAirplay: Bool
        var poisoned: Bool
    }

    private static func poison(_ slots: inout [Slot], name: String) {
        if let index = slots.firstIndex(where: { sameName($0.name, name) }) {
            slots[index].speaker = nil
            slots[index].poisoned = true
            slots[index].fromAirplay = true
        } else {
            slots.append(Slot(name: name, speaker: nil, fromAirplay: true, poisoned: true))
        }
    }

    private static func sameName(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: matchOptions, locale: matchLocale) == .orderedSame
    }

    /// A drawn name. Keep the emoji joiner and variation selectors, fold whitespace, drop other
    /// control and format scalars, and keep 48 characters. Empty is absent.
    static func clean(_ raw: String) -> String? {
        var scalars: [Unicode.Scalar] = []
        var lastWasSpace = true
        for scalar in raw.unicodeScalars {
            if scalar == "\u{200D}" || scalar == "\u{FE0E}" || scalar == "\u{FE0F}" {
                scalars.append(scalar)
                lastWasSpace = false
                continue
            }
            if scalar.properties.isWhitespace {
                if !lastWasSpace {
                    scalars.append(" ")
                    lastWasSpace = true
                }
                continue
            }
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator, .surrogate:
                continue
            default:
                scalars.append(scalar)
                lastWasSpace = false
            }
        }
        while scalars.last == " " { scalars.removeLast() }
        let text = String(String.UnicodeScalarView(scalars))
        let cut = String(text.prefix(nameLimit))
        guard cut.contains(where: { !$0.unicodeScalars.allSatisfy(isKeptMark) }) else { return nil }
        return cut
    }

    private static func isKeptMark(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "\u{200D}" || scalar == "\u{FE0E}" || scalar == "\u{FE0F}"
    }

    /// A leading run of 12 to 16 hex digits and the `@` after it. Any other shape stays.
    private static func stripRaopIdentifier(_ raw: String) -> String {
        let scalars = Array(raw.unicodeScalars)
        var index = 0
        while index < scalars.count, isHex(scalars[index]) {
            index += 1
        }
        guard (12...16).contains(index), index < scalars.count, scalars[index] == "@" else { return raw }
        return String(String.UnicodeScalarView(scalars[(index + 1)...]))
    }

    private static func isHex(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 48...57, 65...70, 97...102: return true
        default: return false
        }
    }
}

/// The network part of the output list. Pure: a controller runs the effects.
public enum SpeakerDiscovery {
    public enum Phase: Equatable, Sendable {
        case off
        case collapsed
        case searching
        case found
        case waitingForAccess
        case unavailable
    }

    public struct State: Equatable, Sendable {
        public var phase: Phase
        public var token: Int
        public var speakers: [NetworkSpeaker]
        public var recordedAllowed: Bool
        /// This Mac's name. A sighting of that name is left out of `speakers`.
        public var ownName: String

        public init(
            phase: Phase = .off, token: Int = 0, speakers: [NetworkSpeaker] = [],
            recordedAllowed: Bool = false, ownName: String = ""
        ) {
            self.phase = phase
            self.token = token
            self.speakers = speakers
            self.recordedAllowed = recordedAllowed
            self.ownName = ownName
        }

        public static let off = State()
    }

    public enum Access: Equatable, Sendable {
        case allowed
        case noAccess
    }

    public enum Event: Equatable, Sendable {
        case settingChanged(Bool)
        case partToggled
        case listClosed
        case results(token: Int, sightings: [SpeakerSighting])
        case noAccess(token: Int)
        case failed(token: Int)
    }

    public enum Effect: Equatable, Sendable {
        case startBrowse(token: Int)
        case stopBrowse
        /// An access note a later controller can store.
        case record(Access)
    }

    /// Words the part can show. The browser and the menu are outside this file.
    public enum Words {
        public static let onTheNetwork = "On the network"
        public static let searching = "Searching"
        public static let noAccess = "No access"
        public static let notAvailable = "Not available"
        public static let localNetworkSettings = "Local Network settings"
        public static let all = [onTheNetwork, searching, noAccess, notAvailable, localNetworkSettings]
    }

    public static func reduce(_ state: State, _ event: Event) -> (State, [Effect]) {
        var state = state
        switch event {
        case .settingChanged(let on):
            if on {
                guard state.phase == .off else { return (state, []) }
                state.phase = .collapsed
                state.speakers = []
                return (state, [])
            }
            switch state.phase {
            case .off:
                return (state, [])
            case .waitingForAccess:
                return finish(state, phase: .off, forget: true, recordDenial: true)
            default:
                return finish(state, phase: .off, forget: true, recordDenial: false)
            }

        case .partToggled:
            switch state.phase {
            case .collapsed, .unavailable:
                return begin(state)
            case .searching, .found, .waitingForAccess:
                return finish(state, phase: .collapsed, forget: true, recordDenial: state.phase == .waitingForAccess)
            case .off:
                return (state, [])
            }

        case .listClosed:
            switch state.phase {
            case .off, .collapsed:
                return (state, [])
            case .waitingForAccess:
                return finish(state, phase: .collapsed, forget: true, recordDenial: true)
            case .searching, .found, .unavailable:
                return finish(state, phase: .collapsed, forget: true, recordDenial: false)
            }

        case .results(let token, let sightings):
            guard accepts(state, token: token) else { return (state, []) }
            let speakers = NetworkSpeakerRules.merge(sightings, ownName: state.ownName)
            if speakers.isEmpty {
                state.phase = .searching
                state.speakers = []
                return (state, [])
            }
            var effects: [Effect] = []
            if !state.recordedAllowed {
                state.recordedAllowed = true
                effects.append(.record(.allowed))
            }
            state.phase = .found
            state.speakers = speakers
            return (state, effects)

        case .noAccess(let token):
            guard accepts(state, token: token) else { return (state, []) }
            state.phase = .waitingForAccess
            return (state, [])

        case .failed(let token):
            guard accepts(state, token: token) else { return (state, []) }
            return finish(state, phase: .unavailable, forget: false, recordDenial: false)
        }
    }

    private static func accepts(_ state: State, token: Int) -> Bool {
        guard state.token == token else { return false }
        switch state.phase {
        case .searching, .found, .waitingForAccess: return true
        case .off, .collapsed, .unavailable: return false
        }
    }

    private static func begin(_ state: State) -> (State, [Effect]) {
        var state = state
        state.token &+= 1
        state.phase = .searching
        state.speakers = []
        state.recordedAllowed = false
        return (state, [.startBrowse(token: state.token)])
    }

    private static func finish(_ state: State, phase: Phase, forget: Bool, recordDenial: Bool) -> (State, [Effect]) {
        var state = state
        state.token &+= 1
        state.phase = phase
        if forget { state.speakers = [] }
        if phase == .off { state.recordedAllowed = false }
        var effects: [Effect] = [.stopBrowse]
        if recordDenial { effects.append(.record(.noAccess)) }
        return (state, effects)
    }
}

@MainActor
public protocol SpeakerDiscoveryControlling: AnyObject {
    var state: SpeakerDiscovery.State { get }
    func togglePart()
}
