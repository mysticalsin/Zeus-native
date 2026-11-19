import Foundation

/// One pointer reading. `time` is `NSEvent.timestamp` / `ProcessInfo.systemUptime` seconds.
/// `x`/`y` are AppKit global points (bottom-left origin).
public struct PointerSample: Equatable, Sendable, Codable {
    public var time: Double
    public var x: Double
    public var y: Double
    public var displayID: UInt32
    public init(time: Double, x: Double, y: Double, displayID: UInt32) {
        self.time = time; self.x = x; self.y = y; self.displayID = displayID
    }
}

public struct PointingStroke: Equatable, Sendable, Codable {
    public var id: String
    public var samples: [PointerSample]
}

public struct PointingDwell: Equatable, Sendable, Codable {
    public var at: PointerSample
    public var duration: Double
}

/// Bounded record of one hold: hover samples, ink strokes and dwells. Memory is capped, and
/// the number of dropped samples is kept so the loss is visible rather than silent.
public struct PointingTrace: Equatable, Sendable {
    public static let maxSamples = 4096
    public static let maxStrokes = 32
    public static let maxStrokeSamples = 1024
    public static let maxDwells = 16
    public static let dwellRadius = SpatialTrail.dwellRadius
    public static let dwellQualification = SpatialTrail.dwellQualification

    public private(set) var samples: [PointerSample] = []
    public private(set) var strokes: [PointingStroke] = []
    public private(set) var dwells: [PointingDwell] = []
    public private(set) var droppedSamples = 0
    private var openStroke = false
    private var dwellAnchor: PointerSample?
    private var dwellRecorded = false

    public init() {}

    /// Hover or drag sample. Returns a dwell the first time the pointer rests in a 12 pt circle
    /// for 350 ms, so the caller can probe that spot once.
    @discardableResult
    public mutating func add(_ sample: PointerSample) -> PointingDwell? {
        guard sample.x.isFinite, sample.y.isFinite, sample.time.isFinite else { droppedSamples += 1; return nil }
        if samples.count >= Self.maxSamples { samples.removeFirst(); droppedSamples += 1 }
        samples.append(sample)
        if openStroke, var stroke = strokes.popLast() {
            if stroke.samples.count < Self.maxStrokeSamples { stroke.samples.append(sample) } else { droppedSamples += 1 }
            strokes.append(stroke)
        }
        if let anchor = dwellAnchor, hypot(sample.x - anchor.x, sample.y - anchor.y) <= Self.dwellRadius {
            let rested = sample.time - anchor.time
            if rested >= Self.dwellQualification, !dwellRecorded, dwells.count < Self.maxDwells {
                dwellRecorded = true
                let dwell = PointingDwell(at: anchor, duration: rested)
                dwells.append(dwell)
                return dwell
            }
        } else {
            dwellAnchor = sample; dwellRecorded = false
        }
        return nil
    }

    public mutating func beginStroke(id: String) {
        guard !openStroke, strokes.count < Self.maxStrokes else { return }
        strokes.append(PointingStroke(id: id, samples: []))
        openStroke = true
    }

    public mutating func endStroke() { openStroke = false }
    public var isDrawing: Bool { openStroke }

    /// The sample closest in time to `audioStart + t`. Used to align a spoken word with where the
    /// pointer was. nil when there are no samples.
    public func sample(atAudioOffset t: Double, audioStart: Double) -> PointerSample? {
        guard t.isFinite, audioStart.isFinite else { return nil }
        let target = audioStart + t
        return samples.min { abs($0.time - target) < abs($1.time - target) }
    }

    /// At most `limit` samples, evenly spread, always keeping the first and the last.
    public func downsampled(limit: Int) -> [PointerSample] {
        guard limit > 1, samples.count > limit else { return samples }
        let step = Double(samples.count - 1) / Double(limit - 1)
        return (0..<limit).map { samples[Int((Double($0) * step).rounded())] }
    }
}
