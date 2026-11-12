import CoreGraphics
import Foundation

/// A control the app found under the pointer. The model refers to it by `id` only; the app
/// supplies the rectangle, so a model can never place a mark on an arbitrary pixel by claiming
/// a control. Labels are untrusted AX text, truncated to 128 bytes.
public struct PointingTargetCandidate: Equatable, Sendable, Codable {
    public enum Source: String, Codable, Sendable { case axHitTest, axDwell, strokeBounds, pointerOnly }
    public var id: String
    public var role: String
    public var subrole: String?
    public var label: String?
    /// Delivered-image pixels (top-left origin). nil when no capture geometry exists.
    public var imageRect: ExplanationRect?
    /// A secure text field: never acted on and never echoed.
    public var isSecure: Bool
    public var source: Source

    public init(id: String, role: String, subrole: String? = nil, label: String? = nil,
                imageRect: ExplanationRect? = nil, isSecure: Bool = false, source: Source = .axHitTest) {
        self.id = id; self.role = role; self.subrole = subrole
        self.label = isSecure ? nil : label.map { Self.truncate($0, bytes: 128) }
        self.imageRect = imageRect; self.isSecure = isSecure; self.source = source
    }

    static func truncate(_ text: String, bytes: Int) -> String {
        guard text.utf8.count > bytes else { return text }
        var result = ""
        for character in text {
            if (result + String(character)).utf8.count > bytes { break }
            result.append(character)
        }
        return result
    }
}

/// The Sendable request block for one pointing turn. Geometry is always delivered-image pixels
/// tied to `captureID`; AppKit points never reach the model.
public struct PointingContext: Equatable, Sendable, Codable {
    public static let maxCandidates = 16
    public static let maxPathPoints = 256
    public static let maxStrokes = 8
    public static let maxDeixis = 16

    /// A spoken pointing word ("this") and the candidate it was resolved to (nil when unresolved).
    public struct Deixis: Equatable, Sendable, Codable {
        public var word: String
        public var candidateID: String?
        public init(word: String, candidateID: String?) { self.word = word; self.candidateID = candidateID }
    }

    public var version = 1
    public var captureID: UUID?
    public var imageSize: ExplanationSize2?
    public var frontmostBundleID: String?
    public var pointerImagePath: [ExplanationVector3]
    public var strokes: [[ExplanationVector3]]
    public var dwellImagePoints: [ExplanationVector3]
    public var candidates: [PointingTargetCandidate]
    public var deixis: [Deixis]

    public init(captureID: UUID? = nil, imageSize: ExplanationSize2? = nil, frontmostBundleID: String? = nil,
                pointerImagePath: [ExplanationVector3] = [], strokes: [[ExplanationVector3]] = [],
                dwellImagePoints: [ExplanationVector3] = [], candidates: [PointingTargetCandidate] = [],
                deixis: [Deixis] = []) {
        self.captureID = captureID; self.imageSize = imageSize; self.frontmostBundleID = frontmostBundleID
        self.pointerImagePath = Array(pointerImagePath.prefix(Self.maxPathPoints))
        self.strokes = Array(strokes.prefix(Self.maxStrokes)).map { Array($0.prefix(Self.maxPathPoints)) }
        self.dwellImagePoints = Array(dwellImagePoints.prefix(16))
        self.candidates = Array(candidates.prefix(Self.maxCandidates))
        self.deixis = Array(deixis.prefix(Self.maxDeixis))
    }

    public var candidateIDs: Set<String> { Set(candidates.map(\.id)) }

    /// Builds the context from a finished trace. Points outside the delivered image are dropped,
    /// never clamped.
    public static func make(trace: PointingTrace, candidates: [PointingTargetCandidate],
                            geometry: ExplanationCaptureGeometry?, display: ExplanationDisplayContext?,
                            frontmostBundleID: String?, deixis: [Deixis] = []) -> PointingContext {
        guard let geometry, let display else {
            return PointingContext(frontmostBundleID: frontmostBundleID, candidates: candidates, deixis: deixis)
        }
        func image(_ x: Double, _ y: Double) -> ExplanationVector3? {
            geometry.imagePoint(fromGlobal: .init(x: x, y: y), current: display)
        }
        let path = trace.downsampled(limit: maxPathPoints).compactMap { image($0.x, $0.y) }
        let strokes = trace.strokes.prefix(maxStrokes).map { stroke in
            PointingTrace.thin(stroke.samples, limit: maxPathPoints).compactMap { image($0.x, $0.y) }
        }.filter { !$0.isEmpty }
        let dwells = trace.dwells.compactMap { image($0.at.x, $0.at.y) }
        return PointingContext(captureID: geometry.captureID, imageSize: geometry.imageSize,
                               frontmostBundleID: frontmostBundleID, pointerImagePath: path,
                               strokes: strokes, dwellImagePoints: dwells, candidates: candidates, deixis: deixis)
    }
}

extension PointingTrace {
    static func thin(_ samples: [PointerSample], limit: Int) -> [PointerSample] {
        guard limit > 1, samples.count > limit else { return samples }
        let step = Double(samples.count - 1) / Double(limit - 1)
        return (0..<limit).map { samples[Int((Double($0) * step).rounded())] }
    }
}

extension PointingContext {
    /// The trace's strokes in delivered-image pixels, with their end time relative to the first sample.
    /// Points outside the delivered image are dropped. Strokes left empty are skipped.
    public static func imageStrokes(trace: PointingTrace, geometry: ExplanationCaptureGeometry,
                                    display: ExplanationDisplayContext) -> [PointingStrokeTargeting.ImageStroke] {
        let origin = trace.samples.first?.time ?? 0
        return trace.strokes.prefix(maxStrokes).compactMap { (stroke: PointingStroke) -> PointingStrokeTargeting.ImageStroke? in
            let points = PointingTrace.thin(stroke.samples, limit: maxPathPoints).compactMap {
                geometry.imagePoint(fromGlobal: .init(x: $0.x, y: $0.y), current: display)
            }
            guard !points.isEmpty, let end = stroke.samples.last else { return nil }
            return PointingStrokeTargeting.ImageStroke(id: stroke.id, points: points, time: max(0, end.time - origin))
        }
    }
}

public enum PointingGeometry {
    /// An Accessibility frame (Quartz global points, top-left origin) to delivered-image pixels.
    /// Built on the one `ScreenCoordinateMapper` (AX to screen) and the capture geometry
    /// (screen to image). A frame that does not meet the captured display returns nil.
    public static func imageRect(fromAX frame: CGRect, mapper: ScreenCoordinateMapper,
                                 geometry: ExplanationCaptureGeometry,
                                 display: ExplanationDisplayContext) -> ExplanationRect? {
        guard let screen = mapper.convert(frame, from: .ax, to: .screen, context: MapContext()) else { return nil }
        let bounds = CGRect(x: display.frame.x, y: display.frame.y, width: display.frame.width, height: display.frame.height)
        let clipped = screen.intersection(bounds).insetBy(dx: 1e-6, dy: 1e-6)
        guard !clipped.isNull, clipped.width > 0, clipped.height > 0,
              let topLeft = geometry.imagePoint(fromGlobal: .init(x: clipped.minX, y: clipped.maxY), current: display),
              let bottomRight = geometry.imagePoint(fromGlobal: .init(x: clipped.maxX, y: clipped.minY), current: display)
        else { return nil }
        let width = bottomRight.x - topLeft.x, height = bottomRight.y - topLeft.y
        guard width > 0, height > 0 else { return nil }
        return ExplanationRect(x: topLeft.x, y: topLeft.y, width: width, height: height)
    }
}
