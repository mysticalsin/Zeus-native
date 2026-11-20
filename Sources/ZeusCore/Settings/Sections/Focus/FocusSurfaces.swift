import Foundation

/// The lock screen shows that a Focus is on. It never shows the name.
public enum FocusLockScreenState: Equatable, Sendable {
    case hidden
    case empty
    case loading
    case showing(String)
    case unavailable(String)
}

public enum FocusLockScreenPolicy {
    public static let label = "Focus on"
    public static let unavailable = "Unavailable"
    public static let empty = "No Focus is on"

    public static func present(enabled: Bool, activity: FocusActivity, permission: FocusPermissionAnswer) -> FocusLockScreenState {
        guard enabled else { return .hidden }
        if permission == .denied && activity == .unknown { return .unavailable(unavailable) }
        switch activity {
        case .unknown:
            return .loading
        case .off:
            return .empty
        case .on:
            return .showing(label)
        }
    }
}

public struct FocusTimerSnapshot: Equatable, Sendable {
    public enum Phase: String, Equatable, Sendable { case idle, focus, rest }

    public var phase: Phase
    public var remainingSeconds: Int

    public init(phase: Phase, remainingSeconds: Int) {
        self.phase = phase
        self.remainingSeconds = remainingSeconds
    }

    public static let ready = FocusTimerSnapshot(phase: .idle, remainingSeconds: 25 * 60)
}

public struct FocusHomeWidgetState: Equatable, Sendable {
    public enum Occupancy: Equatable, Sendable { case empty, ready, running, loading }

    public var occupancy: Occupancy
    public var title: String
    public var subtitle: String
    public var nameStatus: String
    public var accessibilityLabel: String
    public var animates: Bool
}

/// The home Focus widget. `home.widget.2` keeps its stored values. The timer stays usable when the name is unavailable.
public enum FocusHomeWidgetPolicy {
    public static let emptySubtitle = "Home slot 2 is showing another widget."

    public static func isFocusWidget(_ stored: String?) -> Bool {
        HomeSlots([nil, stored, nil, nil])[2] == .focus
    }

    public static func animates(reduceMotion: Bool, running: Bool) -> Bool {
        running && !reduceMotion
    }

    public static func present(
        stored: String?, timer: FocusTimerSnapshot, name: FocusNameMachine, reduceMotion: Bool
    ) -> FocusHomeWidgetState {
        let title = "Focus"
        guard isFocusWidget(stored) else {
            return FocusHomeWidgetState(
                occupancy: .empty, title: title, subtitle: emptySubtitle, nameStatus: "Hidden",
                accessibilityLabel: "\(title), \(emptySubtitle)", animates: false
            )
        }
        let occupancy: FocusHomeWidgetState.Occupancy
        let subtitle: String
        switch timer.phase {
        case .idle:
            occupancy = .ready
            subtitle = "Ready"
        case .focus:
            occupancy = .running
            subtitle = "Focusing"
        case .rest:
            occupancy = .running
            subtitle = "Break"
        }
        let nameStatus = nameLine(name)
        var parts = [title, subtitle]
        if occupancy == .running {
            parts.append(FocusTimer.format(TimeInterval(max(timer.remainingSeconds, 0))))
        }
        if nameStatus != "Hidden" { parts.append(nameStatus) }
        return FocusHomeWidgetState(
            occupancy: occupancy, title: title, subtitle: subtitle, nameStatus: nameStatus,
            accessibilityLabel: parts.joined(separator: ", "),
            animates: animates(reduceMotion: reduceMotion, running: occupancy == .running)
        )
    }

    private static func nameLine(_ name: FocusNameMachine) -> String {
        switch name.phase {
        case .off:
            return "Hidden"
        case .checking:
            return "Checking"
        case .unavailable:
            return "Unavailable"
        case .allowed:
            if let displayName = name.displayName { return displayName }
            if name.activity.isOn { return "Focus on" }
            return "Hidden"
        }
    }
}

public struct FocusControlSpec: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var helper: String
    public var accessibilityLabel: String
    public var accessibilityValue: String
    public var keyboardReachable: Bool
    public var isOn: Bool

    public init(id: String, title: String, helper: String, accessibilityLabel: String, accessibilityValue: String, keyboardReachable: Bool, isOn: Bool) {
        self.id = id
        self.title = title
        self.helper = helper
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityValue = accessibilityValue
        self.keyboardReachable = keyboardReachable
        self.isOn = isOn
    }
}

public enum FocusSectionStatus: Equatable, Sendable {
    case ready
    case loading
    case empty
    case unavailable(String)
}

public struct FocusPreview: Equatable, Sendable {
    public var title: String
    public var line: String
    public var accessibilityLabel: String
    public var animates: Bool
    public var animationDuration: Double

    public init(title: String, line: String, accessibilityLabel: String, animates: Bool, animationDuration: Double) {
        self.title = title
        self.line = line
        self.accessibilityLabel = accessibilityLabel
        self.animates = animates
        self.animationDuration = animationDuration
    }
}

public struct FocusSectionContent: Equatable, Sendable {
    public var title: String
    public var placement: String
    public var placementOrder: Int
    public var rowHeight: Double
    public var panelPadding: Double
    public var cardGap: Double
    public var controls: [FocusControlSpec]
    public var status: FocusSectionStatus
    public var preview: FocusPreview
    public var filterSummary: String

    public init(title: String, placement: String, placementOrder: Int, rowHeight: Double, panelPadding: Double, cardGap: Double, controls: [FocusControlSpec], status: FocusSectionStatus, preview: FocusPreview, filterSummary: String) {
        self.title = title
        self.placement = placement
        self.placementOrder = placementOrder
        self.rowHeight = rowHeight
        self.panelPadding = panelPadding
        self.cardGap = cardGap
        self.controls = controls
        self.status = status
        self.preview = preview
        self.filterSummary = filterSummary
    }
}
