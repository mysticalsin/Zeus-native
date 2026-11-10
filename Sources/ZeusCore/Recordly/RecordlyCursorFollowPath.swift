import CoreGraphics
import Foundation

/// A bounded spring path reused by every MP4/GIF frame. Lookup is logarithmic rather than resmoothing per frame.
public struct RecordlyCursorFollowPath: Sendable {
    public static let maxFrameCount = 60_000
    private let frames: [RecordlyCursorSmoother.Frame]
    public var frameCount: Int { frames.count }

    public init(samples: [RecordlyCursorSample]) {
        let valid = samples.filter { $0.time.isFinite && $0.time >= 0 && $0.x.isFinite && $0.y.isFinite }
            .sorted { $0.time < $1.time }
        guard let first = valid.first, let last = valid.last else { frames = []; return }
        // Reserve room for the smoother's settling tail. Longer recordings use a coarser path,
        // interpolated at render time, so they never allocate an array proportional to video frame count.
        let step = max(1.0 / 60.0, (last.time - first.time) / Double(Self.maxFrameCount - 100))
        frames = Array(RecordlyCursorSmoother.smooth(samples: valid, dt: step).prefix(Self.maxFrameCount))
    }

    public func point(at time: Double) -> CGPoint? {
        guard time.isFinite, let first = frames.first, let last = frames.last else { return nil }
        if time <= first.time { return first.point }
        if time >= last.time { return last.point }
        var lower = 0
        var upper = frames.count - 1
        while lower + 1 < upper {
            let middle = lower + (upper - lower) / 2
            if frames[middle].time <= time { lower = middle } else { upper = middle }
        }
        let a = frames[lower]
        let b = frames[upper]
        guard b.time > a.time else { return b.point }
        let fraction = (time - a.time) / (b.time - a.time)
        return CGPoint(x: a.point.x + (b.point.x - a.point.x) * fraction,
                       y: a.point.y + (b.point.y - a.point.y) * fraction)
    }
}
