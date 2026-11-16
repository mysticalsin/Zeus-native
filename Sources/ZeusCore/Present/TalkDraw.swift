import Foundation

/// What a talk reply asks the screen to show: marks in screenshot pixels (top-left origin, as
/// `[POINT]`), each tied to the spoken sentence it appears with. Wire form, leading in the reply:
/// `[DRAW:{"s":1,"m":[{"k":"ring","x":412,"y":88,"r":24,"at":0}]}]`.
public struct TalkDraw: Equatable, Sendable {
    public struct Point: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public init(x: Double, y: Double) { self.x = x; self.y = y }
    }

    public enum Shape: Equatable, Sendable {
        case ring(center: Point, radius: Double)
        case arrow(from: Point, to: Point)
        case ink([Point])
        case card(origin: Point, text: String)
    }

    public struct Mark: Equatable, Sendable {
        public var shape: Shape
        /// 0-based index of the spoken sentence this mark appears with.
        public var at: Int
        public init(shape: Shape, at: Int) { self.shape = shape; self.at = at }
    }

    public static let maxMarks = 6
    public static let maxInkPoints = 24
    public static let maxTextCharacters = 60
    public static let maxSentenceIndex = 7
    public static let maxRingRadius = 200.0
    public static let minRingRadius = 4.0

    /// 1-based screen number, as the screenshot labels.
    public var screen: Int
    public var marks: [Mark]

    public init(screen: Int, marks: [Mark]) {
        self.screen = screen
        self.marks = marks
    }

    /// The tag body as a model would write it, keys sorted; `TalkDrawParser.parse` reads it back.
    public var json: String {
        func pair(_ p: Point) -> [Double] { [p.x, p.y] }
        let marks: [[String: Any]] = self.marks.map { mark in
            var object: [String: Any] = ["at": mark.at]
            switch mark.shape {
            case .ring(let center, let radius):
                object["k"] = "ring"; object["x"] = center.x; object["y"] = center.y; object["r"] = radius
            case .arrow(let from, let to):
                object["k"] = "arrow"; object["from"] = pair(from); object["to"] = pair(to)
            case .ink(let points):
                object["k"] = "ink"; object["pts"] = points.map(pair)
            case .card(let origin, let text):
                object["k"] = "card"; object["x"] = origin.x; object["y"] = origin.y; object["t"] = text
            }
            return object
        }
        let body: [String: Any] = ["s": screen, "m": marks]
        let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys, .withoutEscapingSlashes])
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}

public enum TalkDrawParser {
    /// Nil when the JSON is not an object, has no `m` array, or none of its marks is usable. Marks
    /// that are unknown or incomplete are dropped; the limits in `TalkDraw` are enforced here.
    public static func parse(_ json: String) -> TalkDraw? {
        guard let data = json.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let rawMarks = root["m"] as? [Any] else { return nil }
        let screen = max(1, number(root["s"]).map { Int($0) } ?? 1)
        var marks: [TalkDraw.Mark] = []
        for raw in rawMarks {
            guard marks.count < TalkDraw.maxMarks else { break }
            if let object = raw as? [String: Any], let mark = mark(from: object) { marks.append(mark) }
        }
        return marks.isEmpty ? nil : TalkDraw(screen: screen, marks: marks)
    }

    private static func mark(from object: [String: Any]) -> TalkDraw.Mark? {
        let at = min(TalkDraw.maxSentenceIndex, max(0, number(object["at"]).map { Int($0) } ?? 0))
        switch object["k"] as? String {
        case "ring":
            guard let x = number(object["x"]), let y = number(object["y"]),
                  let r = number(object["r"]), r > 0 else { return nil }
            return .init(shape: .ring(center: .init(x: x, y: y), radius: min(TalkDraw.maxRingRadius, max(TalkDraw.minRingRadius, r))), at: at)
        case "arrow":
            guard let from = point(object["from"]), let to = point(object["to"]) else { return nil }
            return .init(shape: .arrow(from: from, to: to), at: at)
        case "ink":
            guard let raw = object["pts"] as? [Any] else { return nil }
            let points = raw.prefix(TalkDraw.maxInkPoints).compactMap(point)
            guard points.count >= 2 else { return nil }
            return .init(shape: .ink(points), at: at)
        case "card":
            guard let x = number(object["x"]), let y = number(object["y"]),
                  let raw = object["t"] as? String else { return nil }
            let text = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(TalkDraw.maxTextCharacters))
            guard !text.isEmpty else { return nil }
            return .init(shape: .card(origin: .init(x: x, y: y), text: text), at: at)
        default:
            return nil
        }
    }

    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        return double.isFinite ? double : nil
    }

    private static func point(_ value: Any?) -> TalkDraw.Point? {
        guard let pair = value as? [Any], pair.count == 2, let x = number(pair[0]), let y = number(pair[1]) else { return nil }
        return .init(x: x, y: y)
    }
}

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
    /// Engines whose request carries the image: the app's own Claude provider and the direct
    /// Anthropic API. A CLI engine fed on stdin never sees pixels, so its coordinates mean nothing.
    private static let sighted: Set<String> = ["claude", "anthropic-api"]

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
