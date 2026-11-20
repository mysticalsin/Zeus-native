import Foundation

public struct NearbySpeaker: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    public var displayName: String {
        guard name.count > 64 else { return name }
        return String(name.prefix(61)) + "..."
    }

    public static func normalize(_ speakers: [NearbySpeaker]) -> [NearbySpeaker] {
        var seen: Set<String> = []
        var kept: [NearbySpeaker] = []
        for speaker in speakers {
            let id = speaker.id.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = speaker.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, !name.isEmpty, seen.insert(id).inserted else { continue }
            kept.append(NearbySpeaker(id: id, name: name))
        }
        return kept.sorted { lhs, rhs in
            let left = lhs.name.lowercased()
            let right = rhs.name.lowercased()
            if left == right { return lhs.id < rhs.id }
            return left < right
        }
    }
}

public enum NearbySpeakerBlock: Equatable, Sendable {
    case denied
    case restricted
}

public enum NearbySpeakerFault: Equatable, Sendable {
    case searchFailed
}

public enum NearbySpeakerPhase: Equatable, Sendable {
    case off
    case askingPermission
    case searching
    case names([NearbySpeaker])
    case empty
    case unavailable(NearbySpeakerBlock)
    case error(NearbySpeakerFault)

    public var status: String {
        switch self {
        case .off:
            "Nearby speaker names are off. Nothing is searched until you turn this on."
        case .askingPermission:
            "Waiting for local network permission."
        case .searching:
            "Looking for nearby speakers."
        case .names(let speakers):
            speakers.count == 1 ? "1 nearby speaker." : "\(speakers.count) nearby speakers."
        case .empty:
            "No nearby speakers."
        case .unavailable(.denied):
            "Nearby speaker names are unavailable because local network access was denied."
        case .unavailable(.restricted):
            "Nearby speaker names are unavailable because local network access is restricted."
        case .error:
            "Nearby speaker names could not be loaded."
        }
    }

    public var accessibilityLabel: String {
        switch self {
        case .names(let speakers):
            ([status] + speakers.map(\.name)).joined(separator: " ")
        default:
            status
        }
    }

    public var isLoading: Bool {
        switch self {
        case .askingPermission, .searching: true
        default: false
        }
    }

    public var isEmpty: Bool {
        if case .empty = self { return true }
        return false
    }

    public var isError: Bool {
        if case .error = self { return true }
        return false
    }

    public var isUnavailable: Bool {
        if case .unavailable = self { return true }
        return false
    }
}

public enum NearbySpeakerEvent: Equatable, Sendable {
    case userEnabled
    case userDisabled
    case permissionAllowed
    case permissionDenied
    case permissionRestricted
    case found([NearbySpeaker])
    case searchFailed
}

public enum NearbySpeakerEffect: Equatable, Sendable {
    case requestPermission
    case startSearch
    case stopSearch
}

public struct NearbySpeakerMachine: Equatable, Sendable {
    public private(set) var phase: NearbySpeakerPhase = .off
    private var pending: [NearbySpeaker]?

    public init() {}

    public static func == (lhs: NearbySpeakerMachine, rhs: NearbySpeakerMachine) -> Bool {
        lhs.phase == rhs.phase && lhs.pending == rhs.pending
    }

    public mutating func handle(_ event: NearbySpeakerEvent) -> [NearbySpeakerEffect] {
        switch event {
        case .userEnabled:
            switch phase {
            case .off, .unavailable, .error:
                pending = nil
                phase = .askingPermission
                return [.requestPermission]
            default:
                return []
            }
        case .userDisabled:
            guard phase != .off else { return [] }
            pending = nil
            phase = .off
            return [.stopSearch]
        case .permissionAllowed:
            guard case .askingPermission = phase else { return [] }
            let held = pending
            pending = nil
            if let held {
                phase = held.isEmpty ? .empty : .names(held)
            } else {
                phase = .searching
            }
            return [.startSearch]
        case .permissionDenied:
            return block(.denied)
        case .permissionRestricted:
            return block(.restricted)
        case .found(let raw):
            let names = NearbySpeaker.normalize(raw)
            switch phase {
            case .askingPermission:
                pending = names
                return []
            case .searching, .names, .empty:
                phase = names.isEmpty ? .empty : .names(names)
                return []
            default:
                return []
            }
        case .searchFailed:
            switch phase {
            case .searching, .names, .empty:
                pending = nil
                phase = .error(.searchFailed)
                return [.stopSearch]
            default:
                return []
            }
        }
    }

    private mutating func block(_ reason: NearbySpeakerBlock) -> [NearbySpeakerEffect] {
        switch phase {
        case .off, .unavailable:
            return []
        default:
            pending = nil
            phase = .unavailable(reason)
            return [.stopSearch]
        }
    }
}

public enum NearbySpeakerDiscovery {
    /// Service types browsed only after the owner confirms. The app declares the same types.
    public static let serviceTypes = ["_airplay._tcp", "_raop._tcp"]
}

public enum NearbySpeakerBrowserSignal: Equatable, Sendable {
    case ready
    case denied
    case failed
    case results([NearbySpeaker])
}

public enum NearbySpeakerBrowserRules {
    public static let deniedDNSCode = -65570

    public static func events(dnsCode: Int?, failed: Bool, ready: Bool, names: [NearbySpeaker]?) -> [NearbySpeakerEvent] {
        if dnsCode == deniedDNSCode { return [.permissionDenied] }
        if failed { return [.searchFailed] }
        var events: [NearbySpeakerEvent] = []
        if ready { events.append(.permissionAllowed) }
        if let names { events.append(.found(names)) }
        return events
    }
}
