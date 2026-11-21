import Foundation

public enum NotchParityControl: Equatable, Sendable {
    case status
    case unavailable
}

public struct NotchParityRow: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var status: String
    public var control: NotchParityControl
    public var isHeld: Bool
    public var isReachable: Bool
    public var canTurnOn: Bool
}

/// One plain settings row per notch contract. Held rows say they are not available yet and cannot be turned on.
public enum NotchParitySettings {
    private enum Kind {
        case wave1
        case wave2
        case held
    }

    private static let contracts: [(id: String, title: String, kind: Kind)] = [
        ("R-001", "Shuffle and repeat", .wave1),
        ("R-002", "Lyrics", .wave1),
        ("R-003", "Word timing", .wave1),
        ("R-004", "Keep the display awake while music plays", .wave1),
        ("R-005", "Open on click and collapse on pause", .wave1),
        ("R-006", "Rounded corners and click-through", .wave1),
        ("R-007", "Live resource rows", .wave1),
        ("R-008", "Output devices", .wave1),
        ("R-009", "Drawn notch", .wave1),
        ("R-010", "Media readers", .wave1),
        ("R-011", "Browser media", .wave1),
        ("R-012", "Word times in the lyrics file", .wave1),
        ("R-013", "Per-app volume", .wave1),
        ("R-014", "Now playing across the whole system", .held),
        ("R-015", "Earbud battery", .wave2),
        ("R-016", "Listening mode", .wave2),
        ("R-017", "Focus name", .wave2),
        ("R-018", "Lock screen music card", .wave2),
        ("R-019", "Speaker names on the local network", .wave2),
        ("R-020", "Phone drop", .wave2),
        ("R-021", "Light appearance", .wave1),
        ("R-022", "Signed updates", .wave2),
        ("R-023", "Face approval", .wave2),
        ("R-024", "Setup inside the notch", .held),
        ("R-025", "Animated artwork", .held),
    ]

    public static let rows: [NotchParityRow] = contracts.map { contract in
        switch contract.kind {
        case .held:
            NotchParityRow(id: contract.id, title: contract.title, status: "not available yet",
                           control: .unavailable, isHeld: true, isReachable: true, canTurnOn: false)
        case .wave2:
            NotchParityRow(id: contract.id, title: contract.title, status: "Off",
                           control: .status, isHeld: false, isReachable: true, canTurnOn: false)
        case .wave1:
            NotchParityRow(id: contract.id, title: contract.title, status: "Shown",
                           control: .status, isHeld: false, isReachable: true, canTurnOn: false)
        }
    }

    public static func turnOn(_ id: String) -> Bool {
        guard let row = rows.first(where: { $0.id == id }) else { return false }
        return row.canTurnOn
    }
}
