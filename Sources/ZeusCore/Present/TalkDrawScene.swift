import Foundation

/// Turns a talk draw into capture-space Explanation objects, grouped by the sentence they appear with.
/// Pure: no screen, no window. The app supplies the display identity when it builds the geometry.
public enum TalkDrawScene {
    /// The geometry of the delivered shot: the whole image, no crop. Pixel (x, y) maps to the same
    /// point `PresentPointMapping.screenPoint` gives.
    public static func geometry(shot: ScreenShot, displayID: UInt32, backingScale: Double,
                                captureID: UUID) throws -> ExplanationCaptureGeometry {
        let frame = shot.displayFrame
        let display = try ExplanationDisplayContext(
            displayID: displayID,
            frame: ExplanationRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height),
            backingScale: backingScale)
        let size = ExplanationSize2(width: Double(shot.pixelWidth), height: Double(shot.pixelHeight))
        return try ExplanationCaptureGeometry(captureID: captureID, display: display, fullImageSize: size,
                                              crop: ExplanationRect(x: 0, y: 0, width: size.width, height: size.height),
                                              imageSize: size)
    }

    /// The label box the renderer will measure, roughly: 8 px per character up to 230 px, plus padding.
    public static func estimatedLabelSize(text: String) -> CGSize {
        CGSize(width: min(230, Double(text.count) * 8) + 16, height: 28)
    }

    public static func objects(_ draw: TalkDraw, shot: ScreenShot, captureID: UUID) -> [Int: [ExplanationObject]] {
        let width = Double(shot.pixelWidth), height = Double(shot.pixelHeight)
        func inside(_ p: TalkDraw.Point) -> Bool { p.x >= 0 && p.y >= 0 && p.x <= width && p.y <= height }
        func vector(_ p: TalkDraw.Point) -> ExplanationVector3 { .init(x: p.x, y: p.y) }
        func relative(_ p: TalkDraw.Point, to origin: TalkDraw.Point) -> ExplanationVector3 { .init(x: p.x - origin.x, y: p.y - origin.y) }
        var result: [Int: [ExplanationObject]] = [:]
        for (index, mark) in draw.marks.enumerated() {
            let id = "td\(index)"
            var object: ExplanationObject
            switch mark.shape {
            case .ring(let center, let radius):
                guard inside(center) else { continue }
                object = ExplanationObject(id: id, space: .capture, captureID: captureID,
                    geometry: ExplanationGeometry(kind: .ring, radius: radius),
                    transform: ExplanationTransform(position: vector(center)),
                    style: ExplanationStyle(fill: .clear, stroke: .orange, lineWidth: 4),
                    accessibleDescription: "A ring around a spot on the screen")
            case .arrow(let from, let to):
                guard inside(from), inside(to), from != to else { continue }
                object = ExplanationObject(id: id, space: .capture, captureID: captureID,
                    geometry: ExplanationGeometry(kind: .arrow, points: [.zero, relative(to, to: from)]),
                    transform: ExplanationTransform(position: vector(from)),
                    style: ExplanationStyle(fill: .clear, stroke: .orange, lineWidth: 4),
                    accessibleDescription: "An arrow pointing at a spot on the screen")
            case .ink(let points):
                guard points.allSatisfy(inside), let first = points.first else { continue }
                let relativePoints = points.map { relative($0, to: first) }
                guard zip(relativePoints, relativePoints.dropFirst()).contains(where: { $0 != $1 }) else { continue }
                object = ExplanationObject(id: id, space: .capture, captureID: captureID,
                    geometry: ExplanationGeometry(kind: .path, points: relativePoints),
                    transform: ExplanationTransform(position: vector(first)),
                    style: ExplanationStyle(fill: .clear, stroke: .cyan, lineWidth: 3),
                    accessibleDescription: "A line drawn on the screen")
            case .card(let origin, let text):
                // A label, not a card geometry: a label renders in capture space and the renderer
                // places it beside its anchor. The anchor is moved so the whole box stays on the image.
                let size = estimatedLabelSize(text: text)
                let x = min(max(0, origin.x), max(0, width - size.width - 14))
                let y = min(max(size.height / 2 + 4, origin.y), max(size.height / 2 + 4, height - size.height / 2 - 4))
                object = ExplanationObject(id: id, space: .capture, captureID: captureID,
                    geometry: ExplanationGeometry(kind: .label),
                    transform: ExplanationTransform(position: .init(x: x, y: y)),
                    text: text, accessibleDescription: "A label on the screen")
            }
            result[mark.at, default: []].append(object)
        }
        return result
    }
}

/// When a talk turn may carry a screenshot for drawing, and whose answer may draw on it.
public enum TalkDrawPolicy {
    /// Engines whose request carries the image: the app's own Claude provider. The direct Anthropic API
    /// and every CLI engine fed on stdin are text only and never see pixels, so their coordinates mean nothing.
    private static let sighted: Set<String> = ["claude"]

    public static func accepts(winner: String?) -> Bool {
        winner.map(sighted.contains) ?? false
    }

    /// The screenshots a talk turn sends. Drawing off: every capture, as before. Drawing on: only the
    /// first (the cursor display), which is the one the marks are placed on and costs the fewest image tokens.
    public static func requestShots(consent: Bool, shots: [ScreenShot]) -> [ScreenShot] {
        consent ? Array(shots.prefix(1)) : shots
    }

    /// Images are sent for drawing only with the setting on and a capture in hand.
    public static func wantsImages(consent: Bool, shots: Int) -> Bool {
        consent && shots > 0
    }
}
