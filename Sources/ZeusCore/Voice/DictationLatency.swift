import Foundation

/// Durations for one push-to-talk turn, in milliseconds from key down. The log line is numbers only.
public struct DictationLatency: Equatable, Sendable {
    public enum Stage: String, CaseIterable, Sendable {
        case micHot = "mic_hot"
        case firstFrame = "first_frame"
        case partial = "partial"
        case finalTranscript = "final"
        case inserted = "inserted"
        case actionDone = "action"
    }

    public private(set) var marks: [Stage: Int] = [:]

    public init() {}

    /// The first mark for a stage wins. A negative time is stored as zero.
    public mutating func mark(_ stage: Stage, atMs: Int) {
        guard marks[stage] == nil else { return }
        marks[stage] = max(0, atMs)
    }

    public func milliseconds(_ stage: Stage) -> Int? { marks[stage] }

    /// `dictation-latency mic_hot=12 first_frame=40 ...` Missing stages are `-`.
    public var logLine: String {
        var parts = ["dictation-latency"]
        for stage in Stage.allCases {
            parts.append("\(stage.rawValue)=\(marks[stage].map(String.init) ?? "-")")
        }
        return parts.joined(separator: " ")
    }
}

/// Whether a press has to build an audio engine. Listening stays armed, and a press reuses the
/// prepared engine while its format is still valid.
public struct ListeningEnginePlan: Equatable, Sendable {
    public private(set) var builds = 0
    public private(set) var armed = false

    public init() {}

    /// Prepare once. A second call does not build again.
    public mutating func arm() {
        guard !armed else { return }
        armed = true
        builds += 1
    }

    /// True when this press must build an engine. A valid prepared format does not.
    public mutating func press(formatValid: Bool) -> Bool {
        if armed, formatValid { return false }
        builds += 1
        armed = true
        return true
    }
}
