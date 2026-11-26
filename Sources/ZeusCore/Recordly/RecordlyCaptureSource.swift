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
        switch RecordlyCaptureSourceBox.kind(of: stored) {
        case .display: .display
        case .window: .window
        case .region: .region
        }
    }

    public var regionRect: CGRect {
        let region = RecordlyCaptureSourceBox.region(of: stored)
        return CGRect(x: region.x, y: region.y, width: region.width, height: region.height)
    }

    public static func region(_ rect: CGRect) -> RecordlyCaptureSource {
        let region = RecordlyCaptureSourceBox.region(
            x: Double(rect.origin.x),
            y: Double(rect.origin.y),
            width: Double(rect.size.width),
            height: Double(rect.size.height)
        )
        return .region(x: region.x, y: region.y, width: region.width, height: region.height)
    }

    fileprivate var stored: RecordlyCaptureSourceBox.Stored {
        switch self {
        case .display(let id): .display(id: id)
        case .window(let number): .window(number: number)
        case .region(let x, let y, let width, let height):
            .region(x: x, y: y, width: width, height: height)
        }
    }

    fileprivate init(_ stored: RecordlyCaptureSourceBox.Stored) {
        switch stored {
        case .display(let id): self = .display(id: id)
        case .window(let number): self = .window(number: number)
        case .region(let x, let y, let width, let height):
            self = .region(x: x, y: y, width: width, height: height)
        }
    }
}

extension RecordlyCaptureSource: Codable {
    public init(from decoder: Decoder) throws {
        self.init(try RecordlyCaptureSourceBox.decode(from: decoder))
    }

    public func encode(to encoder: Encoder) throws {
        try RecordlyCaptureSourceBox.encode(stored, to: encoder)
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
