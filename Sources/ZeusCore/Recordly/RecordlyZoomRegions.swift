import CoreGraphics
import Foundation

public struct RecordlyZoomRegion: Equatable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var start: Double
    public var end: Double
    public var centerX: Double
    public var centerY: Double
    public var scale: Double

    public init(id: UUID = UUID(), start: Double, end: Double, center: CGPoint, scale: Double) {
        self.id = id
        self.start = start
        self.end = end
        self.centerX = center.x
        self.centerY = center.y
        self.scale = scale
    }

    public var center: CGPoint { CGPoint(x: centerX, y: centerY) }
}

/// Suggests zoom regions from click events (clean-room behavior, not copied layouts).
public enum RecordlyZoomPlanner {
    public static let defaultScale: Double = 1.8
    public static let defaultDuration: Double = 2.4
    public static let minGap: Double = 0.35

    public static func regions(from clicks: [RecordlyCursorSample], scale: Double = defaultScale, duration: Double = defaultDuration) -> [RecordlyZoomRegion] {
        var out: [RecordlyZoomRegion] = []
        var lastEnd = -Double.infinity
        for click in clicks.sorted(by: { $0.time < $1.time }) {
            guard click.time >= lastEnd + minGap else { continue }
            let end = click.time + duration
            out.append(RecordlyZoomRegion(start: click.time, end: end, center: click.point, scale: scale))
            lastEnd = end
        }
        return out
    }

    public static func cropRect(full: CGRect, center: CGPoint, scale: Double) -> CGRect {
        guard scale > 1.001, full.width > 0, full.height > 0 else { return full }
        let w = full.width / scale
        let h = full.height / scale
        var rect = CGRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h)
        rect.origin.x = min(max(rect.origin.x, full.minX), full.maxX - w)
        rect.origin.y = min(max(rect.origin.y, full.minY), full.maxY - h)
        return rect
    }

    public static func region(at time: Double, in regions: [RecordlyZoomRegion]) -> RecordlyZoomRegion? {
        regions.first { time >= $0.start && time <= $0.end }
    }
}
