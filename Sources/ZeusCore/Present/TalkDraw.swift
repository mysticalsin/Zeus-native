import Foundation
#if canImport(CoreFoundation)
import CoreFoundation
#endif

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
        // Darwin JSON booleans are CFBooleans, distinct from the number 1. Linux's boolean
        // type-id check also rejects 1, and 1 is a real sentence index, so that check stays on Darwin.
        #if canImport(Darwin)
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        #else
        guard let number = value as? NSNumber else { return nil }
        #endif
        let double = number.doubleValue
        return double.isFinite ? double : nil
    }

    private static func point(_ value: Any?) -> TalkDraw.Point? {
        guard let pair = value as? [Any], pair.count == 2, let x = number(pair[0]), let y = number(pair[1]) else { return nil }
        return .init(x: x, y: y)
    }
}
