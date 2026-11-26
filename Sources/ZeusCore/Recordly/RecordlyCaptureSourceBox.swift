import Foundation

/// Display, window, or dragged-region numbers for a Recordly capture.
/// A selection that is not a region reads as a zero rectangle.
/// This type does not read a screen, a pointer, or a clock.
public enum RecordlyCaptureSourceBox {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case display, window, region
    }

    public enum Stored: Equatable, Sendable {
        case display(id: UInt32)
        case window(number: Int)
        case region(x: Double, y: Double, width: Double, height: Double)
    }

    public struct Region: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }

        public static let zero = Region(x: 0, y: 0, width: 0, height: 0)
    }

    public static func kind(of stored: Stored) -> Kind {
        switch stored {
        case .display: .display
        case .window: .window
        case .region: .region
        }
    }

    public static func region(of stored: Stored) -> Region {
        switch stored {
        case .region(let x, let y, let width, let height):
            Region(x: x, y: y, width: width, height: height)
        case .display, .window:
            .zero
        }
    }

    public static func region(x: Double, y: Double, width: Double, height: Double) -> Region {
        Region(x: x, y: y, width: width, height: height)
    }

    public static func decode(from decoder: Decoder) throws -> Stored {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try box.decode(Kind.self, forKey: .kind)
        switch kind {
        case .display:
            return .display(id: try box.decode(UInt32.self, forKey: .id))
        case .window:
            return .window(number: try box.decode(Int.self, forKey: .number))
        case .region:
            return .region(
                x: try box.decode(Double.self, forKey: .x),
                y: try box.decode(Double.self, forKey: .y),
                width: try box.decode(Double.self, forKey: .width),
                height: try box.decode(Double.self, forKey: .height)
            )
        }
    }

    public static func encode(_ stored: Stored, to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(kind(of: stored), forKey: .kind)
        switch stored {
        case .display(let id):
            try box.encode(id, forKey: .id)
        case .window(let number):
            try box.encode(number, forKey: .number)
        case .region(let x, let y, let width, let height):
            try box.encode(x, forKey: .x)
            try box.encode(y, forKey: .y)
            try box.encode(width, forKey: .width)
            try box.encode(height, forKey: .height)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind, id, number, x, y, width, height
    }
}
