import Foundation

/// One pointer sample held in memory. `x` and `y` are points. `time` is seconds.
public struct SpatialTrailSample: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var time: Double

    public init(x: Double, y: Double, time: Double) {
        self.x = x
        self.y = y
        self.time = time
    }
}

/// Bounded memory for a spatial trail.
///
/// `SpatialTrail` on main still appends every raw sample and keeps one dwell.
/// The pointing plan caps that list at 4,096 and asks for several dwells. This
/// value is that rule in Foundation. It does not draw, and it is not wired
/// into `SpatialTrail` or `PointingTrace`.
///
/// A non-finite sample is counted as dropped and does not move the current rest.
/// Past 4,096 samples, the oldest sample is dropped. A rest inside 12 points
/// for 0.350 seconds records the anchor once. Leaving that circle can record
/// another. Dwells stop at 16, the same cap as the pointing trace, so a long
/// hold cannot grow the list without a bound. A dwell stays after its sample
/// has been dropped.
public struct SpatialTrailMemory: Equatable, Sendable {
    public static let maxSamples = 4_096
    public static let maxDwells = 16
    public static let dwellRadius = 12.0
    public static let dwellQualification = 0.350

    public private(set) var samples: [SpatialTrailSample] = []
    public private(set) var dwells: [SpatialTrailSample] = []
    public private(set) var droppedSamples = 0
    private var dwellAnchor: SpatialTrailSample?
    private var dwellRecorded = false

    public init() {}

    public mutating func add(x: Double, y: Double, at time: Double) {
        guard x.isFinite, y.isFinite, time.isFinite else {
            droppedSamples += 1
            return
        }
        if samples.count >= Self.maxSamples {
            samples.removeFirst()
            droppedSamples += 1
        }
        let sample = SpatialTrailSample(x: x, y: y, time: time)
        samples.append(sample)
        noteDwell(sample)
    }

    private mutating func noteDwell(_ sample: SpatialTrailSample) {
        if let anchor = dwellAnchor, distance(sample, anchor) <= Self.dwellRadius {
            let rested = sample.time - anchor.time
            if rested >= Self.dwellQualification, !dwellRecorded, dwells.count < Self.maxDwells {
                dwellRecorded = true
                dwells.append(anchor)
            }
        } else {
            dwellAnchor = sample
            dwellRecorded = false
        }
    }

    private func distance(_ a: SpatialTrailSample, _ b: SpatialTrailSample) -> Double {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }
}
