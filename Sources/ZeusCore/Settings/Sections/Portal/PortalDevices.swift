import Foundation

public struct PortalPairedDevice: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var lastSeen: Date?

    public init(id: String, name: String, lastSeen: Date?) {
        self.id = id
        self.name = name
        self.lastSeen = lastSeen
    }
}

public enum PortalDevicePhase: Equatable, Sendable {
    case off, hidden, pairedOnly, everyone, loading, unavailable
}

public struct PortalRemovalFlow: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        case confirming(String)
        case removed(String)
    }

    public private(set) var phase: Phase

    public init(_ phase: Phase = .idle) { self.phase = phase }

    public mutating func ask(id: String, known: Set<String>) -> PortalStep {
        guard case .idle = phase, known.contains(id), !id.isEmpty else { return .refused }
        phase = .confirming(id)
        return .applied
    }

    public mutating func confirm() -> PortalStep {
        guard case .confirming(let id) = phase else { return .refused }
        phase = .removed(id)
        return .applied
    }

    public mutating func dismiss() -> PortalStep {
        switch phase {
        case .confirming, .removed:
            phase = .idle
            return .applied
        case .idle:
            return .refused
        }
    }
}

/// The existing Fling keys, read as strings. Nothing here is a new setting.
public struct PortalFlingReading: Equatable, Sendable {
    public var enabled: String
    public var receiveInBackground: String
    public var deviceName: String
    public var visibility: String
    public var autoAcceptPaired: String
    public var saveMode: String
    public var papers: String
    public var flickSensitivity: String
    public var openLinks: String
    public var localNetworkDenied: Bool
    public var peersKnown: Bool
    public var notchOpen: Bool
    public var paired: [PortalPairedDevice]
    public var removal: PortalRemovalFlow.Phase

    public init(enabled: String, receiveInBackground: String, deviceName: String, visibility: String, autoAcceptPaired: String, saveMode: String, papers: String, flickSensitivity: String, openLinks: String, localNetworkDenied: Bool, peersKnown: Bool, notchOpen: Bool, paired: [PortalPairedDevice], removal: PortalRemovalFlow.Phase) {
        self.enabled = enabled
        self.receiveInBackground = receiveInBackground
        self.deviceName = deviceName
        self.visibility = visibility
        self.autoAcceptPaired = autoAcceptPaired
        self.saveMode = saveMode
        self.papers = papers
        self.flickSensitivity = flickSensitivity
        self.openLinks = openLinks
        self.localNetworkDenied = localNetworkDenied
        self.peersKnown = peersKnown
        self.notchOpen = notchOpen
        self.paired = paired
        self.removal = removal
    }

    public static var off: PortalFlingReading {
        PortalFlingReading(
            enabled: "false", receiveInBackground: "false", deviceName: "", visibility: "Off",
            autoAcceptPaired: "false", saveMode: "Downloads/Fling", papers: "false", flickSensitivity: "Normal",
            openLinks: "false", localNetworkDenied: false, peersKnown: false, notchOpen: false, paired: [], removal: .idle
        )
    }
}

public enum PortalDevices {
    public static let existingKeys = [
        "fling.enabled", "fling.receiveInBackground", "fling.deviceName", "fling.visibility",
        "fling.autoAcceptPaired", "fling.saveMode", "fling.papers", "fling.flickSensitivity",
        "fling.openLinks", "fling.pairedMacs",
    ]
}

public struct PortalDeviceBoard: Equatable, Sendable {
    public var phase: PortalDevicePhase
    public var canSend: Bool
    public var canReceive: Bool
    public var opensLinks: Bool
    public var shownName: String
    public var devices: [PortalPairedDevice]
    public var status: String
    public var removal: PortalRemovalFlow.Phase
}

public enum PortalDeviceBoardBuilder {
    public static func make(_ reading: PortalFlingReading) -> PortalDeviceBoard {
        let devices = reading.paired.sorted { lhs, rhs in
            let order = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if order == .orderedSame { return lhs.id < rhs.id }
            return order == .orderedAscending
        }
        let name = shownName(reading.deviceName)
        if reading.enabled != "true" {
            return board(.off, send: false, receive: false, links: false, name: name, devices: devices, status: "Nearby sync is off. Nothing is sent or received.", removal: reading.removal)
        }
        if reading.localNetworkDenied {
            return board(.unavailable, send: false, receive: false, links: false, name: name, devices: devices, status: "Local network access is off, so nearby devices stay hidden.", removal: reading.removal)
        }
        switch visibility(reading.visibility) {
        case .off:
            return board(.hidden, send: false, receive: false, links: false, name: name, devices: devices, status: "This Mac is hidden from nearby devices.", removal: reading.removal)
        case .everyone, .pairedOnly:
            break
        }
        if !reading.peersKnown {
            return board(.loading, send: false, receive: false, links: false, name: name, devices: [], status: "Looking for paired devices.", removal: reading.removal)
        }
        let phase: PortalDevicePhase = visibility(reading.visibility) == .everyone ? .everyone : .pairedOnly
        let receive = reading.notchOpen || reading.receiveInBackground == "true"
        let links = receive && reading.openLinks == "true"
        let status = devices.isEmpty ? "No paired devices yet." : "\(devices.count) paired."
        return board(phase, send: true, receive: receive, links: links, name: name, devices: devices, status: status, removal: reading.removal)
    }

    public static func shownName(_ raw: String) -> String {
        let cleaned = String(String.UnicodeScalarView(raw.unicodeScalars.filter { $0.properties.generalCategory != .control }))
        let text = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "This Mac" : text
    }

    private enum Visibility { case everyone, pairedOnly, off }

    private static func visibility(_ raw: String) -> Visibility {
        switch raw {
        case "Everyone nearby": return .everyone
        case "Paired only": return .pairedOnly
        default: return .off
        }
    }

    private static func board(_ phase: PortalDevicePhase, send: Bool, receive: Bool, links: Bool, name: String, devices: [PortalPairedDevice], status: String, removal: PortalRemovalFlow.Phase) -> PortalDeviceBoard {
        PortalDeviceBoard(phase: phase, canSend: send, canReceive: receive, opensLinks: links, shownName: name, devices: devices, status: status, removal: removal)
    }
}
