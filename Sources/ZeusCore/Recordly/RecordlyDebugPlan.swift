import AVFoundation
import CoreGraphics
import Foundation

public struct RecordlyDebugPlan: Equatable, Sendable {
    public var seconds: Double
    public var windowName: String?
    public var noMic: Bool
    public var exportFormats: [RecordlyExportFormat]
    public var outputDirectory: String?

    public init(seconds: Double = 5, windowName: String? = nil, noMic: Bool = true, exportFormats: [RecordlyExportFormat] = [.mp4, .gif], outputDirectory: String? = nil) {
        self.seconds = seconds
        self.windowName = windowName
        self.noMic = noMic
        self.exportFormats = exportFormats
        self.outputDirectory = outputDirectory
    }
}

public enum RecordlyDebugPlanParser {
    public static func parse(_ argument: String?) -> RecordlyDebugPlan {
        var plan = RecordlyDebugPlan()
        guard let argument, !argument.isEmpty else { return plan }
        var tokens = argument.split(whereSeparator: \.isWhitespace).map(String.init)
        while !tokens.isEmpty {
            let token = tokens.removeFirst()
            switch token {
            case "--seconds":
                if let next = tokens.first, let value = Double(next) {
                    tokens.removeFirst()
                    plan.seconds = min(max(value, 0.5), 120)
                }
            case "--window":
                if let next = tokens.first {
                    tokens.removeFirst()
                    plan.windowName = next
                }
            case "--no-mic":
                plan.noMic = true
            case "--export":
                if let next = tokens.first {
                    tokens.removeFirst()
                    plan.exportFormats = RecordlyExportSettings.parseFormats(next)
                }
            case "--out":
                if let next = tokens.first {
                    tokens.removeFirst()
                    plan.outputDirectory = next
                }
            default:
                break
            }
        }
        if plan.exportFormats.isEmpty { plan.exportFormats = [.mp4, .gif] }
        return plan
    }
}

/// Headless checks on exported artifacts (silent E2E assertions).
public enum RecordlyExportValidator {
    public struct Report: Equatable, Sendable {
        public var ok: Bool
        public var durationSeconds: Double?
        public var byteCount: Int?
        public var zoomFramesDiffer: Bool
        public var detail: String
    }

    public static func validate(url: URL, expectedMinDuration: Double, expectedMaxDuration: Double? = nil) async -> Report {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard bytes > 512 else {
            return Report(ok: false, durationSeconds: nil, byteCount: bytes, zoomFramesDiffer: false, detail: "file too small")
        }
        do {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration).seconds
            let video = try await asset.loadTracks(withMediaType: .video)
            let durationOK = duration.isFinite && duration >= expectedMinDuration
                && (expectedMaxDuration.map { duration <= $0 } ?? true)
            let ok = durationOK && !video.isEmpty
            // Planned crop coordinates are not rendered-frame evidence. This check verifies the
            // raw recording only; motion and zoom require inspection of a real rendered export.
            return Report(ok: ok, durationSeconds: duration.isFinite ? duration : nil, byteCount: bytes,
                          zoomFramesDiffer: false, detail: "bytes=\(bytes) measuredDuration=\(duration) videoTracks=\(video.count) zoom=unverified")
        } catch {
            return Report(ok: false, durationSeconds: nil, byteCount: bytes, zoomFramesDiffer: false,
                          detail: "Media could not be inspected: \(error.localizedDescription)")
        }
    }
}

public enum RecordlyPermissionGate {
    /// Preflight only: never opens the system prompt (PERMISSION-GATE and silent tests).
    public static func screenRecordingReady() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    public static func cameraReady() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }
}
