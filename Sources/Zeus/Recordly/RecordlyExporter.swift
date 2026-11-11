import AVFoundation
import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers
import ZeusCore

/// Everything an export needs, captured as plain values so the work can leave the main actor.
struct RecordlyExportRequest: Sendable {
    /// The Controller's pinned handle. The source asset is built from it only; no path is ever reopened.
    let media: RecordlyValidatedMedia
    let settings: RecordlyExportSettings
    let trimStart: Double
    let trimEnd: Double?
    let zoomRegions: [RecordlyZoomRegion]
    let cursorSamples: [RecordlyCursorSample]
    /// Display position saved at capture, completed here with the video's pixel size. Nil when the screen position was
    /// not saved or not verified (no zoom is applied).
    let cursorSpace: RecordlyExportPlan.CursorSpace.Pending?
}

struct RecordlyExportOutput: Sendable {
    var urls: [URL] = []
    /// Things the user should know about files that were written (limits applied, features skipped).
    var notes: [String] = []
    /// One message per format that did not produce a file.
    var failures: [String] = []
}

enum RecordlyExportError: LocalizedError, Sendable {
    case noFormats
    case noVideoTrack
    case badSource
    case emptyTrim
    case outputFolder(String)
    case reader(String)
    case writer(String)
    case frames(String)
    case gifFinalize
    /// Files from formats that finished before the cancel stay on disk.
    case cancelled(completed: [URL])

    var errorDescription: String? {
        switch self {
        case .noFormats: "Choose at least one export format."
        case .noVideoTrack: "The recording has no video track."
        case .badSource: "The recording's size or duration could not be read."
        case .emptyTrim: "The trimmed range is too short to export."
        case .outputFolder(let message): message
        case .reader(let message): "The recording could not be read: \(message)"
        case .writer(let message): "The export file could not be written: \(message)"
        case .frames(let message): message
        case .gifFinalize: "The GIF could not be finished."
        case .cancelled: "Export cancelled."
        }
    }
}

/// Renders the pinned recording to MP4 and/or GIF in ~/Movies/Zeus Recordings. Stateless: cancel by cancelling the
/// Task that awaits `export`. Output is written to a hidden temp file in the destination folder and renamed into
/// place only on success; the temp file is removed on failure or cancel. The recording itself is never modified.
final class RecordlyExporter: Sendable {
    typealias Progress = @Sendable (Double) -> Void

    static let gifMaxLongSide = 1280

    private struct SourceInfo {
        let width: Double
        let height: Double
        let duration: Double
    }

    func export(_ request: RecordlyExportRequest, progress: @escaping Progress) async throws -> RecordlyExportOutput {
        let formats = RecordlyExportFormat.allCases.filter { request.settings.formats.contains($0) }
        guard !formats.isEmpty else { throw RecordlyExportError.noFormats }
        guard let loader = RecordlyMediaResourceLoader(media: request.media, purpose: .export) else {
            throw RecordlyExportError.reader("The trusted recording could not be opened for export.")
        }
        defer { loader.invalidate() }
        let asset = loader.makeAsset()

        let source = try await Self.inspect(asset)
        guard let trim = RecordlyExportPlan.trimRange(trimStart: request.trimStart, trimEnd: request.trimEnd, duration: source.duration) else {
            throw RecordlyExportError.emptyTrim
        }
        let directory = RecordlyExportPlan.outputDirectory()
        try Self.prepareDirectory(directory)

        var output = RecordlyExportOutput()
        try Task.checkCancellation()
        let space = request.cursorSpace?.completed(pixelWidth: Int(source.width.rounded()), pixelHeight: Int(source.height.rounded()))
        let followPath = request.settings.followCursor && space != nil && !request.zoomRegions.isEmpty
            ? RecordlyCursorFollowPath(samples: request.cursorSamples) : nil
        try Task.checkCancellation()
        if !request.zoomRegions.isEmpty, space == nil {
            output.notes.append("Zoom isn't applied to this recording because its screen position wasn't saved.")
        }
        let stamp = Date()
        let total = Double(formats.count)
        for (index, format) in formats.enumerated() {
            let position = Double(index)
            let scoped: Progress = { value in progress((position + min(max(value, 0), 1)) / total) }
            let temp = directory.appendingPathComponent(".Recordly-export-\(UUID().uuidString).part")
            do {
                try Task.checkCancellation()
                switch format {
                case .mp4:
                    output.notes += try await exportMP4(asset: asset, source: source, trim: trim, request: request, space: space, followPath: followPath, temp: temp, progress: scoped)
                case .gif:
                    output.notes += try await exportGIF(asset: asset, source: source, trim: trim, request: request, space: space, followPath: followPath, temp: temp, progress: scoped)
                }
                try Task.checkCancellation()
                output.urls.append(try Self.commit(temp: temp, directory: directory, date: stamp, fileExtension: format.rawValue))
            } catch is CancellationError {
                try? FileManager.default.removeItem(at: temp)
                throw RecordlyExportError.cancelled(completed: output.urls)
            } catch {
                try? FileManager.default.removeItem(at: temp)
                if Task.isCancelled { throw RecordlyExportError.cancelled(completed: output.urls) }
                output.failures.append("\(format.rawValue.uppercased()) export failed: \(error.localizedDescription)")
            }
        }
        progress(1)
        return output
    }

    // MARK: Source and destination

    private static func inspect(_ asset: AVURLAsset) async throws -> SourceInfo {
        let duration: CMTime
        let tracks: [AVAssetTrack]
        do {
            duration = try await asset.load(.duration)
            tracks = try await asset.loadTracks(withMediaType: .video)
        } catch {
            throw RecordlyExportError.reader(error.localizedDescription)
        }
        guard let track = tracks.first else { throw RecordlyExportError.noVideoTrack }
        let natural: CGSize
        let transform: CGAffineTransform
        do {
            natural = try await track.load(.naturalSize)
            transform = try await track.load(.preferredTransform)
        } catch {
            throw RecordlyExportError.reader(error.localizedDescription)
        }
        let applied = natural.applying(transform)
        let seconds = duration.seconds
        guard seconds.isFinite, seconds > 0, applied.width.isFinite, applied.height.isFinite,
              abs(applied.width) > 0, abs(applied.height) > 0 else {
            throw RecordlyExportError.badSource
        }
        return SourceInfo(width: Double(abs(applied.width)), height: Double(abs(applied.height)), duration: seconds)
    }

    private static func prepareDirectory(_ directory: URL) throws {
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            let type = try manager.attributesOfItem(atPath: directory.path)[.type] as? FileAttributeType
            guard type == .typeDirectory else {
                throw RecordlyExportError.outputFolder("\(directory.path) is not a regular folder, so nothing was exported.")
            }
        } catch let error as RecordlyExportError {
            throw error
        } catch {
            throw RecordlyExportError.outputFolder("The export folder \(directory.path) could not be created: \(error.localizedDescription)")
        }
    }

    /// Renames the finished temp file to its final name; never overwrites an existing file.
    private static func commit(temp: URL, directory: URL, date: Date, fileExtension: String) throws -> URL {
        do {
            return try RecordlyExportFiles.publish(temp: temp, directory: directory, date: date, fileExtension: fileExtension)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw RecordlyExportError.outputFolder("The finished export could not be saved: \(error.localizedDescription)")
        }
    }

    static func videoBitrate(quality: RecordlyExportQuality, size: RecordlyExportPlan.PixelSize) -> Int {
        let ratio = max(1.0, Double(size.width * size.height) / (1920.0 * 1080.0))
        return Int(Double(quality.videoBitrate) * ratio)
    }

    // MARK: MP4

    private func exportMP4(
        asset: AVURLAsset,
        source: SourceInfo,
        trim: RecordlyExportPlan.TimeRange,
        request: RecordlyExportRequest,
        space: RecordlyExportPlan.CursorSpace?,
        followPath: RecordlyCursorFollowPath?,
        temp: URL,
        progress: @escaping Progress
    ) async throws -> [String] {
        guard let size = RecordlyExportPlan.outputSize(sourceWidth: source.width, sourceHeight: source.height, longSide: request.settings.preset.longSide) else {
            throw RecordlyExportError.badSource
        }
        let videoTrack: AVAssetTrack
        let audioTrack: AVAssetTrack?
        var audioHint: CMFormatDescription?
        do {
            guard let first = try await asset.loadTracks(withMediaType: .video).first else { throw RecordlyExportError.noVideoTrack }
            videoTrack = first
            audioTrack = try await asset.loadTracks(withMediaType: .audio).first
            if let audioTrack { audioHint = try await audioTrack.load(.formatDescriptions).first }
        } catch let error as RecordlyExportError {
            throw error
        } catch {
            throw RecordlyExportError.reader(error.localizedDescription)
        }

        let regions = request.zoomRegions
        let outW = CGFloat(size.width)
        let outH = CGFloat(size.height)
        let composition = AVMutableVideoComposition(asset: asset) { filterRequest in
            let time = filterRequest.compositionTime.seconds
            let image = filterRequest.sourceImage
            let extent = image.extent
            let crop = RecordlyExportPlan.cropRect(
                at: time,
                full: CGRect(x: 0, y: 0, width: extent.width, height: extent.height),
                regions: regions,
                space: space,
                followPath: followPath
            )
            // Plan rects are top-left origin; Core Image is bottom-left.
            let ciCrop = CGRect(
                x: extent.minX + crop.minX,
                y: extent.minY + (extent.height - crop.maxY),
                width: crop.width,
                height: crop.height
            )
            let move = CGAffineTransform(translationX: -ciCrop.minX, y: -ciCrop.minY)
            let scale = CGAffineTransform(scaleX: outW / ciCrop.width, y: outH / ciCrop.height)
            let result = image.cropped(to: ciCrop)
                .transformed(by: move.concatenating(scale))
                .cropped(to: CGRect(x: 0, y: 0, width: outW, height: outH))
            filterRequest.finish(with: result, context: nil)
        }
        composition.renderSize = size.cgSize

        let reader: AVAssetReader
        let writer: AVAssetWriter
        do {
            reader = try AVAssetReader(asset: asset)
            writer = try AVAssetWriter(outputURL: temp, fileType: .mp4)
        } catch {
            throw RecordlyExportError.reader(error.localizedDescription)
        }
        reader.timeRange = CMTimeRange(
            start: CMTime(seconds: trim.start, preferredTimescale: 600),
            duration: CMTime(seconds: trim.duration, preferredTimescale: 600)
        )

        let videoOutput = AVAssetReaderVideoCompositionOutput(
            videoTracks: [videoTrack],
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        videoOutput.videoComposition = composition
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else { throw RecordlyExportError.reader("The video could not be set up for reading.") }
        reader.add(videoOutput)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: Self.videoBitrate(quality: request.settings.quality, size: size),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoInput) else { throw RecordlyExportError.writer("The video format could not be set up.") }
        writer.add(videoInput)

        var notes: [String] = []
        var audioPair: (AVAssetReaderTrackOutput, AVAssetWriterInput)?
        if let audioTrack {
            let audioOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
            audioOutput.alwaysCopiesSampleData = false
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: audioHint)
            audioInput.expectsMediaDataInRealTime = false
            if reader.canAdd(audioOutput), writer.canAdd(audioInput) {
                reader.add(audioOutput)
                writer.add(audioInput)
                audioPair = (audioOutput, audioInput)
            } else {
                notes.append("The recording's audio could not be carried into the MP4, so it has no sound.")
            }
        }
        writer.shouldOptimizeForNetworkUse = true

        let job = RecordlyMP4Job(
            reader: reader,
            writer: writer,
            videoOutput: videoOutput,
            videoInput: videoInput,
            audio: audioPair,
            trim: trim,
            progress: progress
        )
        try await withTaskCancellationHandler {
            try await job.run()
        } onCancel: {
            job.cancel()
        }
        return notes
    }

    // MARK: GIF

    private func exportGIF(
        asset: AVURLAsset,
        source: SourceInfo,
        trim: RecordlyExportPlan.TimeRange,
        request: RecordlyExportRequest,
        space: RecordlyExportPlan.CursorSpace?,
        followPath: RecordlyCursorFollowPath?,
        temp: URL,
        progress: @escaping Progress
    ) async throws -> [String] {
        guard let schedule = RecordlyExportPlan.gifSchedule(range: trim, frameRate: request.settings.quality.gifFrameRate) else {
            throw RecordlyExportError.emptyTrim
        }
        let longSide = min(request.settings.preset.longSide, Self.gifMaxLongSide)
        guard let size = RecordlyExportPlan.outputSize(sourceWidth: source.width, sourceHeight: source.height, longSide: longSide) else {
            throw RecordlyExportError.badSource
        }
        var notes: [String] = []
        if request.settings.preset.longSide > Self.gifMaxLongSide {
            notes.append("The GIF is limited to \(Self.gifMaxLongSide) px on its long side.")
        }
        if schedule.truncated {
            notes.append("The GIF holds only the first \(Int(RecordlyExportPlan.gifMaxSeconds)) seconds of the trimmed range.")
        }

        let count = schedule.times.count
        guard let destination = CGImageDestinationCreateWithURL(temp as CFURL, UTType.gif.identifier as CFString, count, nil) else {
            throw RecordlyExportError.writer("The GIF file could not be created.")
        }
        let fileProperties: [String: Any] = [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFLoopCount as String: 0]]
        CGImageDestinationSetProperties(destination, fileProperties as CFDictionary)
        let frameProperties: [String: Any] = [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFDelayTime as String: schedule.frameDelay]]

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let tolerance = CMTime(seconds: schedule.frameDelay / 2, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        let times = schedule.times.map { CMTime(seconds: $0, preferredTimescale: 600) }
        var written = 0
        let canceller = GeneratorCanceller(generator: generator)
        try await withTaskCancellationHandler {
            // Also covers early exits: pending requests are cancelled however the loop ends.
            defer { canceller.cancel() }
            for await result in generator.images(for: times) {
                try Task.checkCancellation()
                let image: CGImage
                do {
                    image = try result.image
                } catch {
                    throw RecordlyExportError.frames("A frame could not be read from the recording: \(error.localizedDescription)")
                }
                let crop = RecordlyExportPlan.cropRect(
                    at: result.requestedTime.seconds,
                    full: CGRect(x: 0, y: 0, width: image.width, height: image.height),
                    regions: request.zoomRegions,
                    space: space,
                    followPath: followPath
                )
                guard let frame = Self.render(image, crop: crop, size: size) else {
                    throw RecordlyExportError.frames("A GIF frame could not be rendered.")
                }
                CGImageDestinationAddImage(destination, frame, frameProperties as CFDictionary)
                written += 1
                progress(Double(written) / Double(count))
            }
        } onCancel: {
            canceller.cancel()
        }
        try Task.checkCancellation()
        guard written == count else {
            throw RecordlyExportError.frames("Only \(written) of \(count) GIF frames could be read from the recording.")
        }
        guard CGImageDestinationFinalize(destination) else { throw RecordlyExportError.gifFinalize }
        try Task.checkCancellation()
        return notes
    }

    private static func render(_ image: CGImage, crop: CGRect, size: RecordlyExportPlan.PixelSize) -> CGImage? {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let region = crop.integral.intersection(bounds)
        guard !region.isNull, region.width >= 1, region.height >= 1,
              let cropped = image.cropping(to: region),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: size.width,
                  height: size.height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              )
        else { return nil }
        context.interpolationQuality = .high
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        return context.makeImage()
    }
}

/// One reader-to-writer pass. All AVFoundation state is touched only on `queue`; `cancel()` sets a locked flag and
/// queues an abort that cancels the reader and writer. Completion is exactly-once through `complete`.
private final class RecordlyMP4Job: @unchecked Sendable {
    private let queue = DispatchQueue(label: "zeus.recordly.export.mp4")
    private let reader: AVAssetReader
    private let writer: AVAssetWriter
    private let videoOutput: AVAssetReaderVideoCompositionOutput
    private let videoInput: AVAssetWriterInput
    private let audio: (AVAssetReaderTrackOutput, AVAssetWriterInput)?
    private let trim: RecordlyExportPlan.TimeRange
    private let progress: RecordlyExporter.Progress
    private let lock = NSLock()
    private var cancelled = false
    private var failure: RecordlyExportError?
    private var continuation: CheckedContinuation<Void, Error>?

    private enum Phase { case idle, pumping, finishing, done }
    // Queue-confined.
    private var phase = Phase.idle
    private var remainingPumps = 0

    init(
        reader: AVAssetReader,
        writer: AVAssetWriter,
        videoOutput: AVAssetReaderVideoCompositionOutput,
        videoInput: AVAssetWriterInput,
        audio: (AVAssetReaderTrackOutput, AVAssetWriterInput)?,
        trim: RecordlyExportPlan.TimeRange,
        progress: @escaping RecordlyExporter.Progress
    ) {
        self.reader = reader
        self.writer = writer
        self.videoOutput = videoOutput
        self.videoInput = videoInput
        self.audio = audio
        self.trim = trim
        self.progress = progress
    }

    /// Actively aborts: the flag is set at once, and the abort runs on the job's queue where all AVFoundation state lives.
    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
        queue.async { self.abort() }
    }

    private var shouldStop: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled || failure != nil
    }

    private var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    private func fail(_ error: RecordlyExportError) {
        lock.lock()
        if failure == nil { failure = error }
        lock.unlock()
    }

    private var currentFailure: RecordlyExportError? {
        lock.lock()
        defer { lock.unlock() }
        return failure
    }

    /// Exactly-once: the first terminal path takes the continuation; every later one is a no-op.
    private func complete(_ result: Result<Void, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }

    func run() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.lock()
            self.continuation = continuation
            let alreadyCancelled = cancelled
            lock.unlock()
            if alreadyCancelled {
                complete(.failure(CancellationError()))
            } else {
                queue.async { self.begin() }
            }
        }
    }

    /// Stops reading and writing and reports `error`. Queue only. Never called once `finishWriting` has started.
    private func teardown(_ error: Error) {
        phase = .done
        reader.cancelReading()
        if writer.status == .writing { writer.cancelWriting() }
        complete(.failure(error))
    }

    private func abort() {
        switch phase {
        case .idle:
            complete(.failure(CancellationError()))
        case .pumping:
            teardown(CancellationError())
        case .finishing:
            // finishWriting cannot be interrupted; its handler reports the cancellation once it returns.
            break
        case .done:
            break
        }
    }

    private func begin() {
        guard phase == .idle, !isCancelled else {
            complete(.failure(CancellationError()))
            return
        }
        guard reader.startReading() else {
            phase = .done
            complete(.failure(RecordlyExportError.reader(reader.error?.localizedDescription ?? "reading did not start.")))
            return
        }
        guard writer.startWriting() else {
            teardown(RecordlyExportError.writer(writer.error?.localizedDescription ?? "writing did not start."))
            return
        }
        writer.startSession(atSourceTime: CMTime(seconds: trim.start, preferredTimescale: 600))

        phase = .pumping
        remainingPumps = audio == nil ? 1 : 2
        pump(output: videoOutput, input: videoInput, reportsProgress: true)
        if let audio { pump(output: audio.0, input: audio.1, reportsProgress: false) }
    }

    private func pump(output: AVAssetReaderOutput, input: AVAssetWriterInput, reportsProgress: Bool) {
        let state = PumpState()
        input.requestMediaDataWhenReady(on: queue) { [self] in
            // After an abort the writer is cancelled; touching its inputs would raise.
            guard phase == .pumping, !state.finished else { return }
            while input.isReadyForMoreMediaData {
                if shouldStop {
                    endPump(input, state)
                    return
                }
                guard let sample = output.copyNextSampleBuffer() else {
                    endPump(input, state)
                    return
                }
                if reportsProgress {
                    let fraction = (sample.presentationTimeStamp.seconds - trim.start) / trim.duration
                    if fraction.isFinite { progress(min(max(fraction, 0), 1)) }
                }
                if !input.append(sample) {
                    fail(.writer(writer.error?.localizedDescription ?? "a frame could not be appended."))
                    endPump(input, state)
                    return
                }
            }
        }
    }

    private func endPump(_ input: AVAssetWriterInput, _ state: PumpState) {
        state.finished = true
        if writer.status == .writing { input.markAsFinished() }
        remainingPumps -= 1
        if remainingPumps == 0 { finish() }
    }

    private func finish() {
        if isCancelled {
            teardown(CancellationError())
            return
        }
        if let failure = currentFailure {
            teardown(failure)
            return
        }
        if reader.status == .failed {
            teardown(RecordlyExportError.reader(reader.error?.localizedDescription ?? "reading failed."))
            return
        }
        phase = .finishing
        writer.finishWriting { [self] in
            if isCancelled {
                complete(.failure(CancellationError()))
            } else if writer.status == .completed {
                progress(1)
                complete(.success(()))
            } else {
                complete(.failure(RecordlyExportError.writer(writer.error?.localizedDescription ?? "writing did not finish.")))
            }
        }
    }
}

/// Per-input flag, touched only on the job's queue.
private final class PumpState: @unchecked Sendable {
    var finished = false
}

/// `AVAssetImageGenerator.cancelAllCGImageGeneration` is safe to call from any thread.
private struct GeneratorCanceller: @unchecked Sendable {
    let generator: AVAssetImageGenerator
    func cancel() { generator.cancelAllCGImageGeneration() }
}
