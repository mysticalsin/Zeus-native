import Foundation

/// The regions the desktop card must respect, in AppKit global points. Built only from app-issued
/// data (candidate rectangles, the user's own pointer samples, resolver-placed marks and the
/// focused input's frame), never from a model coordinate.
public struct PointingCardAnchors: Equatable, Sendable {
    /// What the short connector points at.
    public var anchor: ExplanationRect?
    /// Target bounds, pointer trail bounding box, marks and the active input area.
    public var protected: [ExplanationRect]
}

public enum PointingCardAnchorBuilder {
    /// `marks` are the capture-space objects already admitted by playback (resolver-placed, so
    /// their geometry is app-issued). `inputArea` is already global.
    public static func make(context: PointingContext, marks: [ExplanationObject],
                            capture: ExplanationCaptureContext, inputArea: ExplanationRect?) -> PointingCardAnchors {
        let imageSize = capture.geometry.imageSize
        func global(_ image: ExplanationRect) -> ExplanationRect? {
            let x0 = max(0, image.x), y0 = max(0, image.y)
            let x1 = min(imageSize.width, image.x + image.width), y1 = min(imageSize.height, image.y + image.height)
            guard x1 > x0, y1 > y0,
                  let a = capture.geometry.globalPoint(fromImage: .init(x: x0, y: y0), current: capture.currentDisplay),
                  let b = capture.geometry.globalPoint(fromImage: .init(x: x1, y: y1), current: capture.currentDisplay)
            else { return nil }
            return ExplanationRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
        }
        let markRects = marks.compactMap(markRect)
        let candidateRects = context.candidates.compactMap(\.imageRect)
        var protected = (markRects + candidateRects).compactMap(global)
        if let trail = trailBounds(context), let rect = global(trail) { protected.append(rect) }
        if let inputArea { protected.append(inputArea) }
        let anchorImage = union(markRects) ?? candidateRects.first
        return PointingCardAnchors(anchor: anchorImage.flatMap(global), protected: protected)
    }

    /// No capture (Screen Recording is off): a small square around the pointer stands in for the target.
    public static func make(pointer: ExplanationVector3?, inputArea: ExplanationRect?) -> PointingCardAnchors {
        var anchor: ExplanationRect?
        var protected: [ExplanationRect] = []
        if let pointer {
            let square = ExplanationRect(x: pointer.x - 24, y: pointer.y - 24, width: 48, height: 48)
            anchor = square; protected.append(square)
        }
        if let inputArea { protected.append(inputArea) }
        return PointingCardAnchors(anchor: anchor, protected: protected)
    }

    /// Bounding box of the pointer path, the strokes and the dwell points, padded slightly.
    static func trailBounds(_ context: PointingContext) -> ExplanationRect? {
        let points = context.pointerImagePath + context.strokes.flatMap { $0 } + context.dwellImagePoints
        guard let first = points.first else { return nil }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in points { minX = min(minX, p.x); maxX = max(maxX, p.x); minY = min(minY, p.y); maxY = max(maxY, p.y) }
        let pad = 8.0
        return ExplanationRect(x: minX - pad, y: minY - pad, width: maxX - minX + 2 * pad, height: maxY - minY + 2 * pad)
    }

    /// Image-pixel bounds of one capture-space mark. A label is drawn beside its anchor, so it gets
    /// an estimated box rather than a point.
    static func markRect(_ object: ExplanationObject) -> ExplanationRect? {
        guard object.space == .capture else { return nil }
        let p = object.transform.position
        let g = object.geometry
        switch g.kind {
        case .ring, .point, .badge:
            guard let r = g.radius else { return nil }
            return ExplanationRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)
        case .roundedRectangle, .highlight, .region, .card, .image:
            guard let size = g.size else { return nil }
            return ExplanationRect(x: p.x, y: p.y, width: size.x, height: size.y)
        case .arrow, .underline, .path:
            guard let points = g.points, let first = points.first else { return nil }
            var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
            for q in points { minX = min(minX, q.x); maxX = max(maxX, q.x); minY = min(minY, q.y); maxY = max(maxY, q.y) }
            return ExplanationRect(x: p.x + minX, y: p.y + minY, width: max(1, maxX - minX), height: max(1, maxY - minY))
        case .label:
            let characters = Double(min(40, object.text?.count ?? 8))
            return ExplanationRect(x: p.x, y: p.y - 16, width: 16 + characters * 8, height: 32)
        default:
            return nil
        }
    }

    static func union(_ rects: [ExplanationRect]) -> ExplanationRect? {
        guard let first = rects.first else { return nil }
        var minX = first.x, maxX = first.x + first.width, minY = first.y, maxY = first.y + first.height
        for r in rects { minX = min(minX, r.x); maxX = max(maxX, r.x + r.width); minY = min(minY, r.y); maxY = max(maxY, r.y + r.height) }
        return ExplanationRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
