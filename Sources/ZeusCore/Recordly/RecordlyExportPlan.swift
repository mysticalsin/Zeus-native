import CoreGraphics
import Foundation

/// Pure export math: sizes, trim, per-frame crop, GIF schedule, and output naming. No AVFoundation, no filesystem.
public enum RecordlyExportPlan {
    public static let zoomEaseSeconds: Double = 0.3
    public static let gifMaxSeconds: Double = 30
    public static let gifMaxFrames = 600
    public static let minTrimSeconds: Double = 0.1
    public static let outputFolderName = "Zeus Recordings"

    public struct PixelSize: Equatable, Sendable {
        public let width: Int
        public let height: Int
        public var cgSize: CGSize { CGSize(width: width, height: height) }
    }

    public struct TimeRange: Equatable, Sendable {
        public let start: Double
        public let end: Double
        public var duration: Double { end - start }
    }

    public struct GIFSchedule: Equatable, Sendable {
        /// Times on the recording timeline, in seconds.
        public let times: [Double]
        /// Per-frame delay in seconds.
        public let frameDelay: Double
        /// True when the trimmed range was longer than the GIF cap.
        public let truncated: Bool
    }

    /// Where the recorded cursor samples sit relative to the captured video: the captured source's frame in global
    /// AppKit points (y-up, the space of `NSEvent.mouseLocation`) plus the captured pixel size. Only built from a
    /// frame that was cross-checked at capture time; nil everywhere else.
    public struct CursorSpace: Equatable, Sendable {
        public let frame: CGRect
        public let pixelWidth: Int
        public let pixelHeight: Int

        /// Aspect drift allowed between the captured pixel size and the video that is exported.
        static let aspectTolerance = 0.01

        /// `streamFrame` is what ScreenCaptureKit reported (global, top-left origin, y-down) and `displayBounds` is the
        /// independent CoreGraphics bounds for the same display; they must agree or the mapping is not trusted.
        /// `primaryHeight` is the primary display's height in points, used to flip into AppKit's y-up space.
        public init?(streamFrame: CGRect, displayBounds: CGRect, primaryHeight: Double, pixelWidth: Int, pixelHeight: Int) {
            let values = [streamFrame.minX, streamFrame.minY, streamFrame.width, streamFrame.height,
                          displayBounds.minX, displayBounds.minY, displayBounds.width, displayBounds.height, primaryHeight]
            guard values.allSatisfy(\.isFinite),
                  streamFrame.width > 0, streamFrame.height > 0, primaryHeight > 0,
                  pixelWidth > 0, pixelHeight > 0,
                  abs(streamFrame.minX - displayBounds.minX) <= 1, abs(streamFrame.minY - displayBounds.minY) <= 1,
                  abs(streamFrame.width - displayBounds.width) <= 1, abs(streamFrame.height - displayBounds.height) <= 1
            else { return nil }
            self.frame = CGRect(x: streamFrame.minX, y: primaryHeight - streamFrame.maxY, width: streamFrame.width, height: streamFrame.height)
            self.pixelWidth = pixelWidth
            self.pixelHeight = pixelHeight
        }

        /// What is known when a display capture starts: the display's global CoreGraphics bounds (top-left origin) and
        /// the primary display's height. The pixel size is only known from the recorded video, so the space is completed
        /// at export time.
        public struct Pending: Equatable, Sendable {
            public let displayBounds: CGRect
            public let primaryHeight: Double

            public init?(displayBounds: CGRect, primaryHeight: Double) {
                guard [displayBounds.minX, displayBounds.minY, displayBounds.width, displayBounds.height, primaryHeight].allSatisfy(\.isFinite),
                      displayBounds.width > 0, displayBounds.height > 0, primaryHeight > 0
                else { return nil }
                self.displayBounds = displayBounds
                self.primaryHeight = primaryHeight
            }

            /// Keeps the pending space only when the display is still where it was when capture started.
            public func verified(currentBounds: CGRect, currentPrimaryHeight: Double) -> Pending? {
                guard [currentBounds.minX, currentBounds.minY, currentBounds.width, currentBounds.height, currentPrimaryHeight].allSatisfy(\.isFinite),
                      abs(currentBounds.minX - displayBounds.minX) <= 1, abs(currentBounds.minY - displayBounds.minY) <= 1,
                      abs(currentBounds.width - displayBounds.width) <= 1, abs(currentBounds.height - displayBounds.height) <= 1,
                      abs(currentPrimaryHeight - primaryHeight) <= 1
                else { return nil }
                return self
            }

            /// The full space for a video of this pixel size, or nil when the video does not have the display's shape.
            public func completed(pixelWidth: Int, pixelHeight: Int) -> CursorSpace? {
                guard pixelWidth > 0, pixelHeight > 0 else { return nil }
                let captured = Double(pixelWidth) / Double(pixelHeight)
                let display = displayBounds.width / displayBounds.height
                guard abs(captured - display) / display <= CursorSpace.aspectTolerance else { return nil }
                return CursorSpace(
                    streamFrame: displayBounds, displayBounds: displayBounds, primaryHeight: primaryHeight,
                    pixelWidth: pixelWidth, pixelHeight: pixelHeight
                )
            }
        }

        /// The frame to map cursor samples with, or nil when the exported video does not have the captured shape.
        public func mappedFrame(videoWidth: Double, videoHeight: Double) -> CGRect? {
            guard videoWidth.isFinite, videoHeight.isFinite, videoWidth > 0, videoHeight > 0 else { return nil }
            let captured = Double(pixelWidth) / Double(pixelHeight)
            let video = videoWidth / videoHeight
            guard abs(captured - video) / captured <= Self.aspectTolerance else { return nil }
            return frame
        }
    }

    // MARK: Size

    /// Scales so the longer side equals `longSide`, keeps the source aspect, and rounds both sides to even values.
    /// Nil for a source with a non-positive or non-finite dimension.
    public static func outputSize(sourceWidth: Double, sourceHeight: Double, longSide: Int) -> PixelSize? {
        guard sourceWidth.isFinite, sourceHeight.isFinite, sourceWidth > 0, sourceHeight > 0, longSide >= 2 else { return nil }
        let scale = Double(longSide) / max(sourceWidth, sourceHeight)
        return PixelSize(width: evenRounded(sourceWidth * scale), height: evenRounded(sourceHeight * scale))
    }

    private static func evenRounded(_ value: Double) -> Int {
        max(2, Int((value / 2).rounded()) * 2)
    }

    // MARK: Trim

    /// Clamps the trim to `0...duration`. Nil when the clamped range is shorter than `minTrimSeconds`.
    public static func trimRange(trimStart: Double, trimEnd: Double?, duration: Double) -> TimeRange? {
        guard duration.isFinite, duration > 0 else { return nil }
        let start = min(max(trimStart.isFinite ? trimStart : 0, 0), duration)
        let rawEnd = trimEnd.flatMap { $0.isFinite ? $0 : nil } ?? duration
        let end = min(max(rawEnd, start), duration)
        guard end - start >= minTrimSeconds else { return nil }
        return TimeRange(start: start, end: end)
    }

    // MARK: Crop

    /// Smooth 0...1 weight for a region at `time`: smoothstep over `zoomEaseSeconds` at each edge, 0 outside.
    /// Regions shorter than two ease spans never reach full weight but stay continuous.
    public static func zoomWeight(at time: Double, region: RecordlyZoomRegion) -> Double {
        guard time >= region.start, time <= region.end, region.end > region.start else { return 0 }
        let ease = zoomEaseSeconds
        let rise = min(max((time - region.start) / ease, 0), 1)
        let fall = min(max((region.end - time) / ease, 0), 1)
        let t = min(rise, fall)
        return t * t * (3 - 2 * t)
    }

    /// Crop rect in top-left-origin source pixels for the frame at `time`.
    ///
    /// `cursorSpace` is the global AppKit (y-up) frame the recorded cursor samples live in, for the captured
    /// source. Without it, region centers cannot be placed on the video, so no zoom is applied (the full frame is
    /// returned) rather than guessing a mapping.
    public static func cropRect(
        at time: Double,
        full: CGRect,
        regions: [RecordlyZoomRegion],
        cursorSpace: CGRect?,
        followPath: RecordlyCursorFollowPath? = nil
    ) -> CGRect {
        guard let cursorSpace, cursorSpace.width > 0, cursorSpace.height > 0,
              let region = RecordlyZoomPlanner.region(at: time, in: regions)
        else { return full }
        let weight = zoomWeight(at: time, region: region)
        let scale = 1 + (max(region.scale, 1) - 1) * weight
        let cursor = followPath?.point(at: time) ?? region.center
        let center = CGPoint(
            x: full.minX + (cursor.x - cursorSpace.minX) / cursorSpace.width * full.width,
            y: full.minY + (cursorSpace.maxY - cursor.y) / cursorSpace.height * full.height
        )
        return RecordlyZoomPlanner.cropRect(full: full, center: center, scale: scale)
    }

    /// The production request path: resolves the saved cursor space against the actual video size, then crops.
    /// With no space, or one that does not match the video, the full frame is returned (no zoom).
    public static func cropRect(at time: Double, full: CGRect, regions: [RecordlyZoomRegion], space: CursorSpace?, followPath: RecordlyCursorFollowPath? = nil) -> CGRect {
        cropRect(at: time, full: full, regions: regions,
                 cursorSpace: space?.mappedFrame(videoWidth: full.width, videoHeight: full.height), followPath: followPath)
    }

    // MARK: GIF

    /// Frame times from `range.start`, at `frameRate`, limited to `gifMaxSeconds` and `gifMaxFrames`.
    public static func gifSchedule(range: TimeRange, frameRate: Double) -> GIFSchedule? {
        guard frameRate.isFinite, frameRate > 0, range.duration > 0 else { return nil }
        let span = min(range.duration, gifMaxSeconds)
        let count = max(1, min(Int((span * frameRate).rounded(.down)), gifMaxFrames))
        let step = 1 / frameRate
        let times = (0..<count).map { range.start + Double($0) * step }
        return GIFSchedule(times: times, frameDelay: step, truncated: range.duration > gifMaxSeconds + 1e-9)
    }

    // MARK: Naming and location

    /// "Zeus Recording <yyyy-MM-dd HH.mm.ss>.<ext>"; no slashes or colons. `collisionIndex` > 1 appends " <n>".
    public static func fileName(date: Date, fileExtension: String, timeZone: TimeZone = .current, collisionIndex: Int = 1) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let ext = fileExtension.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        let suffix = collisionIndex > 1 ? " \(collisionIndex)" : ""
        return "Zeus Recording \(formatter.string(from: date))\(suffix).\(ext.isEmpty ? "bin" : ext)"
    }

    /// ~/Movies/Zeus Recordings. Pure path math: nothing is created here.
    public static func outputDirectory(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Movies", isDirectory: true)
            .appendingPathComponent(outputFolderName, isDirectory: true)
    }
}
