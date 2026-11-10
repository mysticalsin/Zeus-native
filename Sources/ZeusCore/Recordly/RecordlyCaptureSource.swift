import CoreGraphics
import Foundation

/// What gets recorded (display, one window, or a dragged rectangle in global space).
public enum RecordlyCaptureSource: Equatable, Sendable {
    case display(id: UInt32)
    case window(number: Int)
    case region(x: Double, y: Double, width: Double, height: Double)

    public enum Kind: String, Codable, CaseIterable, Sendable {
        case display, window, region
    }

    public var kind: Kind {
        switch self {
        case .display: .display
        case .window: .window
        case .region: .region
        }
    }

    public var regionRect: CGRect {
        switch self {
        case .region(let x, let y, let width, let height): CGRect(x: x, y: y, width: width, height: height)
        default: .zero
        }
    }

    public static func region(_ rect: CGRect) -> RecordlyCaptureSource {
        .region(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: rect.height)
    }
}

extension RecordlyCaptureSource: Codable {
    enum CodingKeys: String, CodingKey { case kind, id, number, x, y, width, height }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try box.decode(Kind.self, forKey: .kind)
        switch kind {
        case .display: self = .display(id: try box.decode(UInt32.self, forKey: .id))
        case .window: self = .window(number: try box.decode(Int.self, forKey: .number))
        case .region:
            self = .region(
                x: try box.decode(Double.self, forKey: .x),
                y: try box.decode(Double.self, forKey: .y),
                width: try box.decode(Double.self, forKey: .width),
                height: try box.decode(Double.self, forKey: .height)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(kind, forKey: .kind)
        switch self {
        case .display(let id): try box.encode(id, forKey: .id)
        case .window(let number): try box.encode(number, forKey: .number)
        case .region(let x, let y, let width, let height):
            try box.encode(x, forKey: .x)
            try box.encode(y, forKey: .y)
            try box.encode(width, forKey: .width)
            try box.encode(height, forKey: .height)
        }
    }
}

/// Mic and system audio toggles for a session.
public struct RecordlyAudioOptions: Equatable, Codable, Sendable {
    public var microphone: Bool
    public var systemAudio: Bool

    public init(microphone: Bool = false, systemAudio: Bool = false) {
        self.microphone = microphone
        self.systemAudio = systemAudio
    }
}

/// Whether Zeus surfaces appear in the capture (N1).
public struct RecordlyCaptureExclusions: Equatable, Sendable {
    public var excludeZeusWindows: Bool

    public init(excludeZeusWindows: Bool) {
        self.excludeZeusWindows = excludeZeusWindows
    }

    public static func fromScreenSharePolicy(showInScreenSharing: Bool, meetingActive: Bool, teleprompterSessionHidden: Bool) -> RecordlyCaptureExclusions {
        let visible = ZeusScreenSharePolicy.zeusSurfacesVisible(
            showInScreenSharing: showInScreenSharing,
            meetingActive: meetingActive,
            teleprompterSessionHidden: teleprompterSessionHidden
        )
        return RecordlyCaptureExclusions(excludeZeusWindows: !visible)
    }
}

/// Which ScreenCaptureKit callback a sample arrived on.
public enum RecordlySampleKind: String, Equatable, Sendable, CaseIterable {
    case screen
    case systemAudio
    case microphone
}

/// Writer track that receives a sample. Microphone callbacks are dropped here.
public enum RecordlyWriterTrack: String, Equatable, Sendable {
    case video
    case audio
    case drop
}

public enum RecordlySampleRoute {
    /// Screen frames stay on the video input. System audio stays on the audio input.
    public static func track(for kind: RecordlySampleKind) -> RecordlyWriterTrack {
        switch kind {
        case .screen: .video
        case .systemAudio: .audio
        case .microphone: .drop
        }
    }
}
