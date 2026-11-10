import CoreGraphics
import Foundation

/// Spring-smoothed cursor path for re-render (reuses CompanionSpring math).
public enum RecordlyCursorSmoother {
    public struct Frame: Equatable, Sendable {
        public var time: Double
        public var point: CGPoint
    }

    public static func smooth(samples: [RecordlyCursorSample], dt: Double = 1.0 / 60.0, reducedMotion: Bool = false) -> [Frame] {
        guard !samples.isEmpty else { return [] }
        let sorted = samples.sorted { $0.time < $1.time }
        // A step that cannot advance time (zero, negative, NaN or infinite dt) would never terminate, so
        // there is nothing to smooth: return the raw sorted samples as frames.
        guard dt.isFinite, dt > 0 else {
            return sorted.map { Frame(time: $0.time, point: $0.point) }
        }
        var spring = CompanionSpring(position: sorted[0].point)
        var out: [Frame] = [Frame(time: sorted[0].time, point: sorted[0].point)]
        var index = 0
        var t = sorted[0].time
        let end = sorted.last!.time
        // Explicit step bound as well: if `t += dt` stops advancing (dt vanishingly small against t's
        // magnitude), the loop still ends.
        let mainSteps = ((end - t) / dt).rounded(.up) + 2
        guard mainSteps.isFinite, mainSteps < 10_000_000 else {
            return sorted.map { Frame(time: $0.time, point: $0.point) }
        }
        var step = 0
        while t <= end + dt, step < Int(mainSteps) {
            while index + 1 < sorted.count, sorted[index + 1].time <= t { index += 1 }
            let target = sorted[index].point
            spring = spring.stepped(toward: target, dt: dt, reducedMotion: reducedMotion)
            out.append(Frame(time: t, point: spring.position))
            t += dt
            step += 1
        }
        // Settle tail: the spring lags the last sample, so keep stepping toward the final target until it is
        // within 0.5 pt, bounded to ceil(1.5 / dt) iterations so the path can never run unbounded.
        let finalTarget = sorted.last!.point
        let maxTailSteps = Int(min((1.5 / dt).rounded(.up), 10_000_000))
        var tailSteps = 0
        while tailSteps < maxTailSteps, hypot(spring.position.x - finalTarget.x, spring.position.y - finalTarget.y) > 0.5 {
            spring = spring.stepped(toward: finalTarget, dt: dt, reducedMotion: reducedMotion)
            out.append(Frame(time: t, point: spring.position))
            t += dt
            tailSteps += 1
        }
        return out
    }

    /// Optional loop for GIF: shift the tail so the cursor ends where it began.
    public static func loop(samples: [RecordlyCursorSample]) -> [RecordlyCursorSample] {
        guard let first = samples.first, let last = samples.last, samples.count >= 2 else { return samples }
        let dx = first.point.x - last.point.x
        let dy = first.point.y - last.point.y
        guard hypot(dx, dy) > 1 else { return samples }
        let duration = max(last.time - first.time, 0.4)
        let bridge = RecordlyCursorSample(time: last.time + duration * 0.5, point: CGPoint(x: last.point.x + dx * 0.5, y: last.point.y + dy * 0.5))
        let end = RecordlyCursorSample(time: last.time + duration, point: first.point)
        return samples + [bridge, end]
    }
}
