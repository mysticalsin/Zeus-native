import Foundation

/// Maps one drawn stroke (delivered-image pixels) to the best target candidate, or to the screen
/// region the stroke encloses. Pure: no Accessibility, no capture.
///
/// Shapes: a dot is a tap (hit test only); a closed stroke is a circle around something, so the
/// element whose frame the loop encloses wins; an open stroke is an underline or scribble, so the
/// element the stroke passes through wins.
public enum PointingStrokeTargeting {
    public enum Shape: String, Equatable, Sendable { case dot, closed, open }

    public struct Scored: Equatable, Sendable {
        public var candidateID: String
        public var score: Double
    }

    public struct Result: Equatable, Sendable {
        public var shape: Shape
        public var bounds: ExplanationRect
        /// Best first; only candidates scoring at least `minimumScore`.
        public var ranked: [Scored]
        public var best: Scored? { ranked.first }
        /// True when no candidate qualified and the caller should use `bounds` as a region target.
        public var useRegion: Bool { ranked.isEmpty }
    }

    public static let minimumScore = 0.25
    /// A loop whose end is within this fraction of its diagonal from its start counts as closed.
    public static let closeFraction = 0.35
    /// Below this diagonal (image px) a stroke is a dot.
    public static let dotDiagonal = 12.0

    public static func bounds(of points: [ExplanationVector3]) -> ExplanationRect? {
        let finite = points.filter { $0.x.isFinite && $0.y.isFinite }
        guard let first = finite.first else { return nil }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in finite { minX = min(minX, p.x); maxX = max(maxX, p.x); minY = min(minY, p.y); maxY = max(maxY, p.y) }
        return ExplanationRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    public static func shape(of points: [ExplanationVector3]) -> Shape {
        guard let box = bounds(of: points), let first = points.first, let last = points.last else { return .dot }
        let diagonal = hypot(box.width, box.height)
        if diagonal < dotDiagonal { return .dot }
        let gap = hypot(last.x - first.x, last.y - first.y)
        return gap <= diagonal * closeFraction && points.count >= 6 ? .closed : .open
    }

    public static func target(stroke points: [ExplanationVector3], candidates: [PointingTargetCandidate]) -> Result? {
        guard let box = bounds(of: points) else { return nil }
        let kind = shape(of: points)
        var scored: [Scored] = []
        for candidate in candidates where !candidate.isSecure {
            guard let rect = candidate.imageRect, rect.width > 0, rect.height > 0 else { continue }
            let value: Double
            switch kind {
            case .dot:
                value = contains(rect, points[0]) ? 1.0 / (1.0 + area(rect) / 1_000_000) : 0
            case .closed:
                value = closedScore(box: box, rect: rect)
            case .open:
                value = openScore(points: points, rect: rect)
            }
            if value >= minimumScore { scored.append(Scored(candidateID: candidate.id, score: value)) }
        }
        scored.sort { $0.score != $1.score ? $0.score > $1.score : $0.candidateID < $1.candidateID }
        return Result(shape: kind, bounds: box, ranked: scored)
    }

    /// A strokeBounds candidate for a region no element matched. The caller assigns the id.
    public static func regionCandidate(id: String, bounds: ExplanationRect, imageSize: ExplanationSize2?) -> PointingTargetCandidate? {
        var rect = bounds
        let pad = 8.0
        rect.x -= pad; rect.y -= pad; rect.width += 2 * pad; rect.height += 2 * pad
        if let size = imageSize {
            let x0 = max(0, rect.x), y0 = max(0, rect.y)
            let x1 = min(size.width, rect.x + rect.width), y1 = min(size.height, rect.y + rect.height)
            guard x1 > x0, y1 > y0 else { return nil }
            rect = ExplanationRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
        }
        guard rect.width.isFinite, rect.height.isFinite else { return nil }
        return PointingTargetCandidate(id: id, role: "region", imageRect: rect, source: .strokeBounds)
    }

    // MARK: Scoring

    /// A circle around a control: how much of the control the loop encloses, discounted when the
    /// loop is far larger than the control (it then circles a group, not this control).
    private static func closedScore(box: ExplanationRect, rect: ExplanationRect) -> Double {
        let overlap = intersectionArea(box, rect)
        let target = area(rect), loop = area(box)
        guard target > 0, loop > 0, overlap > 0 else { return 0 }
        let enclosed = overlap / target
        let tightness = overlap / loop
        return enclosed * (0.4 + 0.6 * min(1, tightness * 2))
    }

    /// An underline or scribble: the share of stroke points inside the control (grown by 6 px).
    private static func openScore(points: [ExplanationVector3], rect: ExplanationRect) -> Double {
        let grown = ExplanationRect(x: rect.x - 6, y: rect.y - 6, width: rect.width + 12, height: rect.height + 12)
        let inside = points.filter { contains(grown, $0) }.count
        return Double(inside) / Double(points.count)
    }

    private static func contains(_ r: ExplanationRect, _ p: ExplanationVector3) -> Bool {
        p.x >= r.x && p.x <= r.x + r.width && p.y >= r.y && p.y <= r.y + r.height
    }

    private static func area(_ r: ExplanationRect) -> Double { max(0, r.width) * max(0, r.height) }

    private static func intersectionArea(_ a: ExplanationRect, _ b: ExplanationRect) -> Double {
        let w = min(a.x + a.width, b.x + b.width) - max(a.x, b.x)
        let h = min(a.y + a.height, b.y + b.height) - max(a.y, b.y)
        return w > 0 && h > 0 ? w * h : 0
    }

    // MARK: Whole-turn resolution

    public struct ImageStroke: Equatable, Sendable {
        public var id: String
        public var points: [ExplanationVector3]
        /// Seconds from the start of the hold to the end of the stroke.
        public var time: Double
        public init(id: String, points: [ExplanationVector3], time: Double) { self.id = id; self.points = points; self.time = time }
    }

    public struct Resolution: Equatable, Sendable {
        /// The input candidates plus any region candidates, at most `PointingContext.maxCandidates`.
        public var candidates: [PointingTargetCandidate]
        /// Stroke id to the candidate it was matched to. A stroke with no usable match is absent.
        public var assignments: [String: String]
    }

    /// Matches each stroke to its best candidate; a stroke no element fits becomes a region candidate.
    public static func resolve(strokes: [ImageStroke], candidates: [PointingTargetCandidate],
                               imageSize: ExplanationSize2?) -> Resolution {
        var list = candidates
        var assignments: [String: String] = [:]
        for stroke in strokes {
            guard let result = target(stroke: stroke.points, candidates: list) else { continue }
            if let best = result.best {
                assignments[stroke.id] = best.candidateID
            } else if list.count < PointingContext.maxCandidates {
                let id = nextID(in: list)
                if let region = regionCandidate(id: id, bounds: result.bounds, imageSize: imageSize) {
                    list.append(region)
                    assignments[stroke.id] = id
                }
            }
        }
        return Resolution(candidates: list, assignments: assignments)
    }

    private static func nextID(in list: [PointingTargetCandidate]) -> String {
        var index = list.count
        while list.contains(where: { $0.id == "t\(index)" }) { index += 1 }
        return "t\(index)"
    }
}
