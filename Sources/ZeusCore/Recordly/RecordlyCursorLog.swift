import CoreGraphics
import Foundation

public struct RecordlyCursorSample: Equatable, Codable, Sendable {
    public var time: Double
    public var x: Double
    public var y: Double
    public var clicked: Bool

    public init(time: Double, point: CGPoint, clicked: Bool = false) {
        self.time = time
        self.x = point.x
        self.y = point.y
        self.clicked = clicked
    }

    public var point: CGPoint { CGPoint(x: x, y: y) }
}

/// Logs pointer samples during capture (global AppKit space, y up).
public enum RecordlyCursorLog {
    public static func append(_ samples: inout [RecordlyCursorSample], time: Double, point: CGPoint, clicked: Bool) {
        if let last = samples.last, last.time == time, last.point == point, last.clicked == clicked { return }
        samples.append(RecordlyCursorSample(time: time, point: point, clicked: clicked))
    }

    public static func clicks(in samples: [RecordlyCursorSample]) -> [RecordlyCursorSample] {
        samples.filter(\.clicked)
    }
}
