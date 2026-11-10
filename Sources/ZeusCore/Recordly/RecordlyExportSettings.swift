import Foundation

public enum RecordlyExportFormat: String, Codable, CaseIterable, Sendable {
    case mp4
    case gif
}

public enum RecordlyVideoPreset: String, Codable, CaseIterable, Sendable {
    case hd1080
    case uhd4K

    public var longSide: Int {
        switch self {
        case .hd1080: 1920
        case .uhd4K: 3840
        }
    }

    public var label: String {
        switch self {
        case .hd1080: "1080p"
        case .uhd4K: "4K"
        }
    }
}

public enum RecordlyExportQuality: String, Codable, CaseIterable, Sendable {
    case balanced, high, light

    public var videoBitrate: Int {
        switch self {
        case .light: 4_000_000
        case .balanced: 8_000_000
        case .high: 14_000_000
        }
    }

    public var gifFrameRate: Double {
        switch self {
        case .light: 10
        case .balanced: 15
        case .high: 20
        }
    }
}

public struct RecordlyExportSettings: Equatable, Codable, Sendable {
    public var preset: RecordlyVideoPreset
    public var quality: RecordlyExportQuality
    public var formats: [RecordlyExportFormat]
    public var followCursor: Bool

    public init(preset: RecordlyVideoPreset = .hd1080, quality: RecordlyExportQuality = .balanced, formats: [RecordlyExportFormat] = [.mp4], followCursor: Bool = true) {
        self.preset = preset
        self.quality = quality
        self.formats = formats
        self.followCursor = followCursor
    }

    private enum CodingKeys: String, CodingKey { case preset, quality, formats, followCursor }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        preset = try values.decode(RecordlyVideoPreset.self, forKey: .preset)
        quality = try values.decode(RecordlyExportQuality.self, forKey: .quality)
        formats = try values.decode([RecordlyExportFormat].self, forKey: .formats)
        followCursor = try values.decodeIfPresent(Bool.self, forKey: .followCursor) ?? true
    }

    public static func parseFormats(_ string: String) -> [RecordlyExportFormat] {
        string.split(separator: ",").compactMap { RecordlyExportFormat(rawValue: String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) }
    }
}

public struct RecordlyFrameStyle: Equatable, Codable, Sendable {
    public var padding: Double
    public var cornerRadius: Double
    public var shadowOpacity: Double
    public var backgroundHex: UInt32?

    public static let `default` = RecordlyFrameStyle(padding: 24, cornerRadius: 16, shadowOpacity: 0.35, backgroundHex: 0x1A1A1E)
}
