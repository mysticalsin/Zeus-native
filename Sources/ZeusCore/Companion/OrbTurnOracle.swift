import Foundation

/// Spec oracle for the companion turn table in `specs/007-companion-parity/plan.md`.
/// S1 owns `CompanionTurnMachine.swift` and `CompanionTurnPhase.swift`. This type is not that
/// machine. The end-to-end suite asserts this table, including every pair that is not in it.
public enum OrbTurnOracle {
    public static let phases = ["idle", "listening", "transcribing", "thinking", "speaking", "interrupted", "error"]

    public struct Edge: Equatable, Sendable {
        public var from: String
        public var event: String
        public var to: String
        public var effects: [String]

        public init(from: String, event: String, to: String, effects: [String]) {
            self.from = from
            self.event = event
            self.to = to
            self.effects = effects
        }
    }

    /// Rows whose `from` is `any` apply to every phase.
    public static let edges: [Edge] = [
        Edge(from: "idle", event: "key_confirmed", to: "listening",
             effects: ["show buddy", "lamp mic on", "arm capture", "start mic"]),
        Edge(from: "idle", event: "key_tap_inside_confirm", to: "idle", effects: []),
        Edge(from: "idle", event: "mouse_down_while_arming", to: "idle", effects: []),
        Edge(from: "listening", event: "key_up", to: "transcribing",
             effects: ["lamp mic off when the device closes", "commit partial"]),
        Edge(from: "listening", event: "double_tap_latch", to: "listening",
             effects: ["stay", "arm the silence timer"]),
        Edge(from: "listening", event: "silence_timer_on_latch", to: "transcribing",
             effects: ["lamp mic off when the device closes", "commit partial"]),
        Edge(from: "listening", event: "escape", to: "idle",
             effects: ["stop mic", "lamp off", "hide after linger"]),
        Edge(from: "listening", event: "capture_denied_at_start", to: "error",
             effects: ["speak the short line"]),
        Edge(from: "transcribing", event: "partial_committed_instant", to: "speaking",
             effects: ["no brain", "no capture wait"]),
        Edge(from: "transcribing", event: "partial_committed_needs_brain", to: "thinking",
             effects: ["send transcript", "attach capture if it succeeded"]),
        Edge(from: "transcribing", event: "empty_partial", to: "idle", effects: ["no request"]),
        Edge(from: "transcribing", event: "recognizer_failure", to: "error",
             effects: ["speak the short line"]),
        Edge(from: "thinking", event: "first_sentence_ready", to: "speaking",
             effects: ["schedule that sentence", "fly if a point tag is already parsed"]),
        Edge(from: "thinking", event: "brain_failure", to: "error",
             effects: ["speak the short line", "do not invent a screen"]),
        Edge(from: "thinking", event: "key_down", to: "interrupted",
             effects: ["cancel brain", "cancel speech"]),
        Edge(from: "speaking", event: "playback_ended", to: "idle",
             effects: ["lamps off", "linger"]),
        Edge(from: "speaking", event: "key_down", to: "interrupted",
             effects: ["stop speech", "stop flight", "stop capture"]),
        Edge(from: "speaking", event: "escape", to: "interrupted",
             effects: ["stop speech", "stop flight", "stop capture"]),
        Edge(from: "interrupted", event: "cleanup_key_held", to: "listening",
             effects: ["start a new mic"]),
        Edge(from: "interrupted", event: "cleanup_key_up", to: "idle", effects: ["linger"]),
        Edge(from: "error", event: "line_spoken", to: "idle",
             effects: ["lamps off", "pointer cleared"]),
        Edge(from: "error", event: "key_down", to: "listening", effects: ["the line may be cut"]),
        Edge(from: "any", event: "sleep_or_display_change", to: "interrupted",
             effects: ["discard capture"]),
    ]

    public static var events: [String] {
        Array(Set(edges.map(\.event))).sorted()
    }

    /// Legal applications, with `any` expanded onto every phase.
    public static func legalApplications() -> [Edge] {
        var applied: [Edge] = []
        for edge in edges where edge.from != "any" {
            applied.append(edge)
        }
        for phase in phases {
            for edge in edges where edge.from == "any" {
                applied.append(Edge(from: phase, event: edge.event, to: edge.to, effects: edge.effects))
            }
        }
        return applied
    }

    public static func step(_ phase: String, _ event: String) -> Edge? {
        legalApplications().first { $0.from == phase && $0.event == event }
    }

    /// Every phase/event pair that is not a legal application.
    public static func illegalPairs() -> [(phase: String, event: String)] {
        let legal = Set(legalApplications().map { "\($0.from)\t\($0.event)" })
        var pairs: [(String, String)] = []
        for phase in phases {
            for event in events where !legal.contains("\(phase)\t\(event)") {
                pairs.append((phase, event))
            }
        }
        return pairs
    }

    /// One top bar for each display. The orb draws inside the buddy overlay and opens no window.
    public static func surface(displayCount: Int) -> (topBars: Int, extraWindows: Int) {
        (max(0, displayCount), 0)
    }
}
