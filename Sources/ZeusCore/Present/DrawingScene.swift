import CoreGraphics
import Foundation

/// A point in overlay space, 0...1, origin at the top-left, y down.
public struct UnitPoint: Equatable, Sendable, Codable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public init?(_ pair: [Double]) {
        guard pair.count == 2, pair[0].isFinite, pair[1].isFinite else { return nil }
        self.init(x: pair[0], y: pair[1])
    }
}

/// One mark in the shared drawing schema.
public enum DrawingMark: Equatable, Sendable {
    case rect(origin: UnitPoint, size: UnitPoint)
    case circle(center: UnitPoint, radius: Double)
    case arrow(from: UnitPoint, to: UnitPoint)
    case line(from: UnitPoint, to: UnitPoint)
    case path(points: [UnitPoint])
    case label(text: String, at: UnitPoint)
    case math(tex: String, at: UnitPoint)
}

public struct DrawingStep: Equatable, Sendable {
    public var marks: [DrawingMark]

    public init(marks: [DrawingMark]) { self.marks = marks }
}

/// 1 to 12 steps, each with 1 to 40 marks. Later steps add to earlier ones.
public struct DrawingScene: Equatable, Sendable {
    public static let maxSteps = 12
    public static let maxMarks = 40

    public let steps: [DrawingStep]

    public init?(steps: [DrawingStep]) {
        guard (1...Self.maxSteps).contains(steps.count) else { return nil }
        guard steps.allSatisfy({ (1...Self.maxMarks).contains($0.marks.count) }) else { return nil }
        self.steps = steps
    }

    /// Marks from the first step through `index` (0-based), in order.
    public func cumulative(through index: Int) -> [DrawingMark] {
        guard index >= 0 else { return [] }
        return steps.prefix(index + 1).flatMap(\.marks)
    }

    public func overlay(_ point: UnitPoint, on display: DisplayMap) -> CGPoint {
        CGPoint(x: point.x * display.frame.width, y: point.y * display.frame.height)
    }

    public static func decode(_ json: String) -> DrawingScene? {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawSteps = root["steps"] as? [[String: Any]] else { return nil }
        let steps = rawSteps.compactMap(DrawingStep.init(json:))
        guard steps.count == rawSteps.count else { return nil }
        return DrawingScene(steps: steps)
    }

    public func encode() -> String {
        let payload: [String: Any] = ["steps": steps.map { ["marks": $0.marks.map(\.json)] }]
        let data = (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// Three cumulative steps: the triangle, the side labels, then the identity.
    public static func pythagorean() -> DrawingScene {
        let a = UnitPoint(x: 0.25, y: 0.75)
        let b = UnitPoint(x: 0.75, y: 0.75)
        let c = UnitPoint(x: 0.75, y: 0.25)
        let scene = DrawingScene(steps: [
            DrawingStep(marks: [
                .arrow(from: a, to: b),
                .arrow(from: b, to: c),
                .arrow(from: c, to: a),
            ]),
            DrawingStep(marks: [
                .label(text: "b", at: UnitPoint(x: 0.5, y: 0.875)),
                .label(text: "a", at: UnitPoint(x: 0.875, y: 0.5)),
                .label(text: "c", at: UnitPoint(x: 0.375, y: 0.375)),
            ]),
            DrawingStep(marks: [
                .math(tex: "a^2+b^2=c^2", at: UnitPoint(x: 0.25, y: 0.125)),
            ]),
        ])
        return scene!
    }
}

extension DrawingStep {
    fileprivate init?(json: [String: Any]) {
        guard let raw = json["marks"] as? [[String: Any]] else { return nil }
        let marks = raw.compactMap(DrawingMark.init(json:))
        guard marks.count == raw.count else { return nil }
        self.init(marks: marks)
    }
}

extension DrawingMark {
    fileprivate var json: [String: Any] {
        switch self {
        case .rect(let origin, let size):
            return ["kind": "rect", "at": [origin.x, origin.y], "size": [size.x, size.y]]
        case .circle(let center, let radius):
            return ["kind": "circle", "at": [center.x, center.y], "radius": radius]
        case .arrow(let from, let to):
            return ["kind": "arrow", "from": [from.x, from.y], "to": [to.x, to.y]]
        case .line(let from, let to):
            return ["kind": "line", "from": [from.x, from.y], "to": [to.x, to.y]]
        case .path(let points):
            return ["kind": "path", "points": points.map { [$0.x, $0.y] }]
        case .label(let text, let at):
            return ["kind": "label", "text": text, "at": [at.x, at.y]]
        case .math(let tex, let at):
            return ["kind": "math", "tex": tex, "at": [at.x, at.y]]
        }
    }

    fileprivate init?(json: [String: Any]) {
        guard let kind = json["kind"] as? String else { return nil }
        switch kind {
        case "rect":
            guard let origin = UnitPoint(MarkJSON.pair(json["at"])),
                  let size = UnitPoint(MarkJSON.pair(json["size"])),
                  size.x > 0, size.y > 0 else { return nil }
            self = .rect(origin: origin, size: size)
        case "circle":
            guard let center = UnitPoint(MarkJSON.pair(json["at"])),
                  let radius = MarkJSON.number(json["radius"]), radius > 0 else { return nil }
            self = .circle(center: center, radius: radius)
        case "arrow", "line":
            guard let from = UnitPoint(MarkJSON.pair(json["from"])),
                  let to = UnitPoint(MarkJSON.pair(json["to"])) else { return nil }
            self = kind == "arrow" ? .arrow(from: from, to: to) : .line(from: from, to: to)
        case "path":
            guard let raw = json["points"] as? [Any] else { return nil }
            let points = raw.compactMap { UnitPoint(MarkJSON.pair($0)) }
            guard points.count == raw.count, points.count >= 2 else { return nil }
            self = .path(points: points)
        case "label":
            guard let text = json["text"] as? String, !text.isEmpty,
                  let at = UnitPoint(MarkJSON.pair(json["at"])) else { return nil }
            self = .label(text: text, at: at)
        case "math":
            guard let tex = json["tex"] as? String, !tex.isEmpty,
                  let at = UnitPoint(MarkJSON.pair(json["at"])) else { return nil }
            self = .math(tex: tex, at: at)
        default:
            return nil
        }
    }

}

private enum MarkJSON {
    static func pair(_ value: Any?) -> [Double] {
        let raw = value as? [Any] ?? []
        return raw.compactMap { number($0) }
    }

    static func number(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }
}

public struct PlacedMark: Equatable, Sendable {
    public var mark: DrawingMark
    public var box: CGRect
}

/// Places marks in unit space and nudges labels off arrows and lines.
public enum DrawingLayout {
    public static func place(_ marks: [DrawingMark]) -> [PlacedMark] {
        var placed: [PlacedMark] = []
        var strokes: [DrawingMark] = []
        for mark in marks {
            var box = bounds(of: mark)
            if isLabel(mark) {
                var nudge = 0
                while nudge < 8, strokes.contains(where: { overlaps(box, $0) }) {
                    box.origin.y += 0.03
                    nudge += 1
                }
            } else if isStroke(mark) {
                strokes.append(mark)
            }
            placed.append(PlacedMark(mark: mark, box: box))
        }
        return placed
    }

    /// True when a label box comes within 0.02 of an arrow, line, or path. Uses the stroke, not its bounding box.
    public static func labelsOverlapStrokes(_ placed: [PlacedMark]) -> Bool {
        let labels = placed.filter { isLabel($0.mark) }
        let strokes = placed.filter { isStroke($0.mark) }
        return labels.contains { label in strokes.contains { overlaps(label.box, $0.mark) } }
    }

    private static func overlaps(_ box: CGRect, _ mark: DrawingMark) -> Bool {
        switch mark {
        case .arrow(let from, let to), .line(let from, let to):
            return segmentHits(box.insetBy(dx: -0.02, dy: -0.02), from: from, to: to)
        case .path(let points):
            return zip(points, points.dropFirst()).contains { segmentHits(box.insetBy(dx: -0.02, dy: -0.02), from: $0.0, to: $0.1) }
        default:
            return false
        }
    }

    private static func segmentHits(_ box: CGRect, from: UnitPoint, to: UnitPoint) -> Bool {
        let samples = 16
        for step in 0...samples {
            let t = Double(step) / Double(samples)
            let point = CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
            if box.contains(point) { return true }
        }
        return false
    }

    private static func isLabel(_ mark: DrawingMark) -> Bool {
        switch mark {
        case .label, .math: return true
        default: return false
        }
    }

    private static func isStroke(_ mark: DrawingMark) -> Bool {
        switch mark {
        case .arrow, .line, .path: return true
        default: return false
        }
    }

    private static func bounds(of mark: DrawingMark) -> CGRect {
        switch mark {
        case .rect(let origin, let size):
            return CGRect(x: origin.x, y: origin.y, width: size.x, height: size.y)
        case .circle(let center, let radius):
            return CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        case .arrow(let from, let to), .line(let from, let to):
            return CGRect(x: min(from.x, to.x), y: min(from.y, to.y), width: abs(to.x - from.x), height: abs(to.y - from.y)).insetBy(dx: -0.01, dy: -0.01)
        case .path(let points):
            guard let first = points.first else { return .null }
            var rect = CGRect(x: first.x, y: first.y, width: 0, height: 0)
            for point in points.dropFirst() { rect = rect.union(CGRect(x: point.x, y: point.y, width: 0, height: 0)) }
            return rect.insetBy(dx: -0.01, dy: -0.01)
        case .label(let text, let at):
            let width = max(0.03, Double(text.count) * 0.018)
            return CGRect(x: at.x - width / 2, y: at.y - 0.02, width: width, height: 0.04)
        case .math(let tex, let at):
            let rendered = MathTypeset.render(tex)
            let width = max(0.08, Double(rendered.spoken.count) * 0.016)
            let height = rendered.numerator == nil ? 0.05 : 0.09
            return CGRect(x: at.x - width / 2, y: at.y - height / 2, width: width, height: height)
        }
    }
}

/// Native math layout. Dollar signs and `\frac` never survive into `spoken`.
public struct MathLayout: Equatable, Sendable {
    public var spoken: String
    public var numerator: String?
    public var denominator: String?
    public var hasSuperscript: Bool
}

public enum MathTypeset {
    private static let superscripts: [Character: Character] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
        "+": "⁺", "-": "⁻", "n": "ⁿ",
    ]

    public static func render(_ tex: String) -> MathLayout {
        var source = tex
        source = source.replacingOccurrences(of: "$", with: "")
        source = source.replacingOccurrences(of: "\\(", with: "")
        source = source.replacingOccurrences(of: "\\)", with: "")
        var numerator: String?
        var denominator: String?
        if let start = source.range(of: "\\frac{"),
           let split = source[start.upperBound...].firstIndex(of: "}"),
           source[source.index(after: split)...].hasPrefix("{"),
           let end = source[source.index(split, offsetBy: 2)...].firstIndex(of: "}") {
            numerator = String(source[start.upperBound..<split])
            let denStart = source.index(split, offsetBy: 2)
            denominator = String(source[denStart..<end])
            source.removeSubrange(start.lowerBound...end)
        }
        var spoken = ""
        var supers = false
        var characters = source.makeIterator()
        while let character = characters.next() {
            if character == "^" {
                supers = true
                let next = characters.next() ?? " "
                if next == "{" {
                    var body = ""
                    while let inner = characters.next(), inner != "}" { body.append(inner) }
                    spoken.append(contentsOf: body.map { superscripts[$0] ?? $0 })
                } else {
                    spoken.append(superscripts[next] ?? next)
                }
                continue
            }
            if character == "\\" { continue }
            spoken.append(character)
        }
        if let numerator, let denominator {
            spoken = spoken.trimmingCharacters(in: .whitespaces)
            if spoken.isEmpty { spoken = "\(numerator) over \(denominator)" }
        }
        return MathLayout(spoken: spoken, numerator: numerator, denominator: denominator, hasSuperscript: supers)
    }
}
