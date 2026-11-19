import Foundation

/// Timing marks of one pointing turn, written as a single log line with offsets only. It carries no
/// transcript, no label and no image data: only mark names and milliseconds.
public struct PointingTraceSpans: Equatable, Sendable {
    public enum Mark: String, CaseIterable, Sendable {
        case keyDown = "key_down"
        case firstMic = "first_mic"
        case transcriptFinal = "transcript_final"
        case screenshotReady = "screenshot_ready"
        case requestSent = "request_sent"
        case firstValidBeat = "first_valid_beat"
        case firstAudio = "first_audio"
        case firstVisual = "first_visual"
        case cancelComplete = "cancel_complete"
    }

    public enum Outcome: String, Sendable { case completed, cancelled, interrupted, failed, empty }

    public private(set) var times: [Mark: Double] = [:]

    public init() {}

    public var isEmpty: Bool { times.isEmpty }

    /// The first write of a mark wins; a later one is ignored.
    public mutating func mark(_ mark: Mark, at time: Double) {
        guard time.isFinite, times[mark] == nil else { return }
        times[mark] = time
    }

    /// `[ZEUS] pointing-trace outcome=completed key_down=0 first_mic=41 ... cancel_complete=-`
    public func line(outcome: Outcome) -> String {
        let base = times[.keyDown] ?? times.values.min() ?? 0
        let fields = Mark.allCases.map { mark -> String in
            guard let time = times[mark] else { return "\(mark.rawValue)=-" }
            return "\(mark.rawValue)=\(max(0, Int(((time - base) * 1000).rounded())))"
        }
        return (["[ZEUS] pointing-trace", "outcome=\(outcome.rawValue)"] + fields).joined(separator: " ")
    }
}

/// The macOS pointer fill colour (System Settings > Accessibility > Display > Pointer), when the user
/// changed it. The default white is treated as "not set": a white trail would vanish on light windows.
public enum PointerFillColor {
    public static func parse(_ values: [String: Double]?) -> (red: Double, green: Double, blue: Double)? {
        guard let values, let red = values["red"], let green = values["green"], let blue = values["blue"],
              [red, green, blue].allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { return nil }
        if red > 0.97, green > 0.97, blue > 0.97 { return nil }
        return (red, green, blue)
    }
}
