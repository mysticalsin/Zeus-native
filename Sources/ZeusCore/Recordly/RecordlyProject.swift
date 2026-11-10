import Foundation

/// Saved editor state (Zeus project format, not .recordly).
public struct RecordlyProject: Equatable, Codable, Sendable {
    public static let fileExtension = "zeuscast"
    public static let formatVersion = 1

    public var version: Int
    public var createdAt: Date
    public var source: RecordlyCaptureSource
    public var audio: RecordlyAudioOptions
    public var rawMediaPath: String
    public var trimStart: Double
    public var trimEnd: Double?
    public var cursorSamples: [RecordlyCursorSample]
    public var zoomRegions: [RecordlyZoomRegion]
    public var export: RecordlyExportSettings
    public var frameStyle: RecordlyFrameStyle
    public var loopCursor: Bool

    public init(
        version: Int = formatVersion,
        createdAt: Date = Date(),
        source: RecordlyCaptureSource,
        audio: RecordlyAudioOptions = RecordlyAudioOptions(),
        rawMediaPath: String,
        trimStart: Double = 0,
        trimEnd: Double? = nil,
        cursorSamples: [RecordlyCursorSample] = [],
        zoomRegions: [RecordlyZoomRegion] = [],
        export: RecordlyExportSettings = RecordlyExportSettings(),
        frameStyle: RecordlyFrameStyle = .default,
        loopCursor: Bool = false
    ) {
        self.version = version
        self.createdAt = createdAt
        self.source = source
        self.audio = audio
        self.rawMediaPath = rawMediaPath
        self.trimStart = trimStart
        self.trimEnd = trimEnd
        self.cursorSamples = cursorSamples
        self.zoomRegions = zoomRegions
        self.export = export
        self.frameStyle = frameStyle
        self.loopCursor = loopCursor
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> RecordlyProject {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RecordlyProject.self, from: data)
    }

    public mutating func applyAutoZoomFromClicks() {
        zoomRegions = RecordlyZoomPlanner.regions(from: RecordlyCursorLog.clicks(in: cursorSamples))
    }
}
