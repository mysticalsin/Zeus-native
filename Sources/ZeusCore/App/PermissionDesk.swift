import Foundation

/// One capability Zeus can ask for. A row never says it is allowed unless the system said so.
public enum PermissionDesk {
    public enum Kind: String, CaseIterable, Sendable {
        case microphone, speech, camera, screen, accessibility, automation, bluetooth, localNetwork, fullDisk, calendar
    }

    public enum Status: Equatable, Sendable {
        case unknown, allowed, denied, unavailable
    }

    public struct Row: Equatable, Sendable {
        public var kind: Kind
        public var title: String
        public var pane: String
        public var canPrompt: Bool
    }

    public static let rows: [Row] = [
        Row(kind: .microphone, title: "Microphone", pane: "Privacy_Microphone", canPrompt: true),
        Row(kind: .speech, title: "Speech", pane: "Privacy_SpeechRecognition", canPrompt: true),
        Row(kind: .camera, title: "Camera", pane: "Privacy_Camera", canPrompt: true),
        Row(kind: .screen, title: "Screen Recording", pane: "Privacy_ScreenCapture", canPrompt: false),
        Row(kind: .accessibility, title: "Accessibility", pane: "Privacy_Accessibility", canPrompt: false),
        Row(kind: .automation, title: "Automation", pane: "Privacy_Automation", canPrompt: false),
        Row(kind: .bluetooth, title: "Bluetooth", pane: "Privacy_Bluetooth", canPrompt: true),
        Row(kind: .localNetwork, title: "Local Network", pane: "Privacy_LocalNetwork", canPrompt: false),
        Row(kind: .fullDisk, title: "Full Disk Access", pane: "Privacy_AllFiles", canPrompt: false),
        Row(kind: .calendar, title: "Calendars", pane: "Privacy_Calendars", canPrompt: true),
    ]

    public static func url(for kind: Kind) -> String {
        let pane = rows.first { $0.kind == kind }?.pane ?? ""
        return "x-apple.systempreferences:com.apple.preference.security?\(pane)"
    }

    /// The next missing capability, in the guided order. Allowed and unavailable rows are skipped.
    public static func nextMissing(_ status: [Kind: Status]) -> Kind? {
        rows.first { row in
            let state = status[row.kind] ?? .unknown
            return state != .allowed && state != .unavailable
        }?.kind
    }

    /// A grant is recorded only when the probe says it is allowed.
    public static func record(probe: Status) -> Status { probe }
}
