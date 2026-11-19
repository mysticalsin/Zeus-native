import AppKit
import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import os
import ScreenCaptureKit
import ZeusCore

enum RecordlyScreenCaptureCatalog {
    static func snapshot(from content: SCShareableContent) -> RecordlySourceSelection.CatalogSnapshot {
        RecordlySourceSelection.CatalogSnapshot(
            displays: content.displays.compactMap { display in
                guard display.displayID != 0 else { return nil }
                return .init(id: display.displayID, frame: display.frame)
            },
            windows: content.windows.compactMap { window in
                RecordlySourceSelection.windowBinding(
                    number: Int(window.windowID),
                    ownerProcessID: window.owningApplication?.processID,
                    title: window.title,
                    frame: window.frame,
                    isOnScreen: window.isOnScreen,
                    ownerName: window.owningApplication?.applicationName
                )
            }
        )
    }
}

struct RecordlyScreenCaptureCatalogProvider: RecordlySourceCatalogProvider {
    func loadCatalog() async -> RecordlySourceCatalogLoadResult {
        guard RecordlyPermissionGate.screenRecordingReady() else {
            return .denied(reason: RecordlyCaptureError.permissionDenied.localizedDescription)
        }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            return .loaded(RecordlyScreenCaptureCatalog.snapshot(from: content))
        } catch {
            return .failed(reason: error.localizedDescription)
        }
    }
}

enum RecordlyCaptureError: LocalizedError {
    case permissionDenied
    case noSource(String)
    case writer(String)
    case stream(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Screen Recording is off. Turn Zeus on in System Settings, Privacy and Security, Screen & System Audio Recording."
        case .noSource(let reason): reason
        case .writer(let message): message
        case .stream(let message): message
        }
    }
}

/// ScreenCaptureKit capture to MP4 via AVAssetWriter.
///
/// Everything a recording owns (stream, writer, inputs, file) lives in one `Active` value tagged with its attempt.
/// It is published under `stateLock` before the stream starts, so the sample and stop callbacks can check stream
/// identity, and every failure or cancel path unwinds exactly that attempt. One attempt owns the engine at a time;
/// the legacy `beginCapture`/`endCapture` pair uses attempt 0 and shares the same gate.
final class RecordlyCaptureEngine: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private typealias StopHook = @Sendable (RecordlyRecordingAttempt, String) -> Void

    private struct Active {
        let attempt: RecordlyRecordingAttempt
        let stream: SCStream
        let writer: AVAssetWriter
        let videoInput: AVAssetWriterInput
        let audioInput: AVAssetWriterInput?
        let url: URL
        let onUnexpectedStop: StopHook?
        /// Set once the stream's stop is expected or already reported, so the delegate reports at most once.
        var finishing = false
        var writerFailureReported = false
        var timeline = RecordlyCaptureTimeline()
    }

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Zeus", category: "recordly")
    private static let legacyAttempt = RecordlyRecordingAttempt(id: 0)

    private let queue = DispatchQueue(label: "zeus.recordly.capture")
    private let stateLock = OSAllocatedUnfairLock()
    /// Latest system-audio peak (0...1) and when it arrived. Written on the capture queue, read by the page's meter.
    private let levelLock = OSAllocatedUnfairLock<(peak: Float, at: TimeInterval)>(initialState: (0, 0))
    // Guarded by stateLock.
    private var owner: RecordlyRecordingAttempt?
    private var beginInFlight = false
    private var cancelRequested = false
    private var active: Active?
    // Main actor only.
    private var cursorSamples: [RecordlyCursorSample] = []
    private var cursorTimer: Timer?

    @MainActor
    func record(
        intent: RecordlySourceSelection.SelectionIntent,
        audio: RecordlyAudioOptions,
        exclusions: RecordlyCaptureExclusions,
        duration: TimeInterval,
        to directory: URL
    ) async throws -> (URL, [RecordlyCursorSample], RecordlySourceSelection.ResolvedSource) {
        let (_, resolved) = try await beginCapture(intent: intent, audio: audio, exclusions: exclusions, directory: directory)
        do {
            try await Task.sleep(for: .seconds(duration))
        } catch {
            await cancelAttempt(Self.legacyAttempt)
            throw error
        }
        let (url, samples) = try await endCapture()
        return (url, samples, resolved)
    }

    /// Legacy/debug entry. Shares the engine's single-owner gate with the session port.
    @MainActor
    func beginCapture(
        intent: RecordlySourceSelection.SelectionIntent,
        audio: RecordlyAudioOptions,
        exclusions: RecordlyCaptureExclusions,
        directory: URL
    ) async throws -> (URL, RecordlySourceSelection.ResolvedSource) {
        try await startAttempt(
            intent: intent,
            systemAudio: audio.systemAudio,
            excludeZeusWindows: exclusions.excludeZeusWindows,
            directory: directory,
            attempt: Self.legacyAttempt,
            onUnexpectedStop: nil
        )
    }

    @MainActor
    func endCapture() async throws -> (URL, [RecordlyCursorSample]) {
        try await endAttempt(Self.legacyAttempt)
    }

    // MARK: Ownership gate

    private func claim(_ attempt: RecordlyRecordingAttempt) throws {
        let busy = stateLock.withLockUnchecked { () -> Bool in
            if self.owner != nil { return true }
            self.owner = attempt
            self.beginInFlight = true
            self.cancelRequested = false
            return false
        }
        if busy { throw RecordlyCaptureError.stream("Another recording is already starting or running.") }
    }

    private func finishBegin(_ attempt: RecordlyRecordingAttempt, keepOwner: Bool) {
        stateLock.withLockUnchecked {
            guard self.owner == attempt else { return }
            self.beginInFlight = false
            if !keepOwner {
                self.owner = nil
                self.cancelRequested = false
            }
        }
    }

    private func isCancelled(_ attempt: RecordlyRecordingAttempt) -> Bool {
        stateLock.withLockUnchecked { () -> Bool in self.owner == attempt && self.cancelRequested }
    }

    private func release(_ attempt: RecordlyRecordingAttempt) {
        stateLock.withLockUnchecked {
            guard self.owner == attempt else { return }
            self.owner = nil
            self.beginInFlight = false
            self.cancelRequested = false
        }
    }

    private func takeActive(_ attempt: RecordlyRecordingAttempt) -> Active? {
        stateLock.withLockUnchecked { () -> Active? in
            guard let current = self.active, current.attempt == attempt else { return nil }
            self.active = nil
            return current
        }
    }

    // MARK: Start

    @MainActor
    private func startAttempt(
        intent: RecordlySourceSelection.SelectionIntent,
        systemAudio: Bool,
        excludeZeusWindows: Bool,
        directory: URL,
        attempt: RecordlyRecordingAttempt,
        onUnexpectedStop: StopHook?
    ) async throws -> (URL, RecordlySourceSelection.ResolvedSource) {
        try claim(attempt)
        do {
            let result = try await startOwned(
                intent: intent,
                systemAudio: systemAudio,
                excludeZeusWindows: excludeZeusWindows,
                directory: directory,
                attempt: attempt,
                onUnexpectedStop: onUnexpectedStop
            )
            finishBegin(attempt, keepOwner: true)
            return result
        } catch {
            finishBegin(attempt, keepOwner: false)
            throw error
        }
    }

    private func throwIfCancelled(_ attempt: RecordlyRecordingAttempt) throws {
        if isCancelled(attempt) { throw CancellationError() }
    }

    @MainActor
    private func startOwned(
        intent: RecordlySourceSelection.SelectionIntent,
        systemAudio: Bool,
        excludeZeusWindows: Bool,
        directory: URL,
        attempt: RecordlyRecordingAttempt,
        onUnexpectedStop: StopHook?
    ) async throws -> (URL, RecordlySourceSelection.ResolvedSource) {
        guard RecordlyPermissionGate.screenRecordingReady() else { throw RecordlyCaptureError.permissionDenied }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        // Stop or Cancel may have landed while the catalog was loading; check before anything native starts.
        try throwIfCancelled(attempt)
        let catalog = RecordlyScreenCaptureCatalog.snapshot(from: content)
        let outcome = RecordlySourceSelection.resolve(intent: intent, in: catalog, permission: .granted)
        let validatedSource: RecordlySourceSelection.ResolvedSource
        switch outcome {
        case .ready(let value): validatedSource = value
        case .denied(let reason), .lostSource(let reason), .invalidIntent(let reason): throw RecordlyCaptureError.noSource(reason)
        }
        let source = validatedSource
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownApps = excludeZeusWindows ? content.applications.filter { $0.processID == ownPID } : []

        let filter: SCContentFilter
        let width: Int
        let height: Int

        switch source.kind {
        case .display:
            guard let id = source.displayID else { throw RecordlyCaptureError.noSource("Choose a display explicitly.") }
            let matches = content.displays.filter { $0.displayID == id }
            guard matches.count == 1, let display = matches.first else {
                throw RecordlyCaptureError.noSource("The selected display is no longer available. Choose another display explicitly.")
            }
            filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
            width = display.width
            height = display.height
        case .window:
            guard let number = source.windowNumber, let token = source.windowIdentityToken else {
                throw RecordlyCaptureError.noSource("Choose a window explicitly.")
            }
            let matches = content.windows.filter { window in
                guard let binding = RecordlySourceSelection.windowBinding(number: Int(window.windowID), ownerProcessID: window.owningApplication?.processID, title: window.title, frame: window.frame, isOnScreen: window.isOnScreen) else { return false }
                return binding.number == number && binding.identityToken == token
            }
            guard matches.count == 1, let window = matches.first else { throw RecordlyCaptureError.noSource("The selected window is no longer available. Choose another window explicitly.") }
            filter = SCContentFilter(desktopIndependentWindow: window)
            width = Int(window.frame.width)
            height = Int(window.frame.height)
        case .region:
            throw RecordlyCaptureError.noSource("Region capture is unavailable until its coordinate-space contract is verified.")
        }

        let configuration = SCStreamConfiguration()
        configuration.width = max(width, 2)
        configuration.height = max(height, 2)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        // The export currently crops the recorded image; it does not render a replacement cursor.
        configuration.showsCursor = true
        configuration.capturesAudio = systemAudio
        configuration.excludesCurrentProcessAudio = true

        try Self.preparePrivateDirectory(directory)
        let url = directory.appendingPathComponent("capture-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString).mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)

        // From here on this attempt owns a writer (and soon a stream); any throw unwinds exactly that.
        // The stream is also held here, because a cancel can take the published copy while startCapture is still
        // pending; the stream must then be stopped again once startCapture has returned.
        var attemptStream: SCStream?
        do {
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: configuration.width,
                AVVideoHeightKey: configuration.height,
            ]
            let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoInput.expectsMediaDataInRealTime = true
            guard writer.canAdd(videoInput) else { throw RecordlyCaptureError.writer("Video track unavailable.") }
            writer.add(videoInput)

            var audioInput: AVAssetWriterInput?
            if systemAudio {
                let audioSettings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 48_000,
                    AVNumberOfChannelsKey: 2,
                    AVEncoderBitRateKey: 128_000,
                ]
                let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
                input.expectsMediaDataInRealTime = true
                guard writer.canAdd(input) else {
                    throw RecordlyCaptureError.writer("System audio could not be recorded. Turn off System Audio or try again.")
                }
                writer.add(input)
                audioInput = input
            }

            guard writer.startWriting() else {
                throw RecordlyCaptureError.writer(writer.error?.localizedDescription ?? "Writer failed.")
            }
            try Self.restrictFile(url)
            try throwIfCancelled(attempt)

            let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            attemptStream = stream
            // Published before any output is registered or capture starts, so callbacks can match this stream.
            stateLock.withLockUnchecked {
                self.active = Active(
                    attempt: attempt,
                    stream: stream,
                    writer: writer,
                    videoInput: videoInput,
                    audioInput: audioInput,
                    url: url,
                    onUnexpectedStop: onUnexpectedStop
                )
            }
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
            if systemAudio {
                try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
            }
            try await stream.startCapture()

            // A cancel during the await already took the active value; never report success for it.
            let stillOwned = stateLock.withLockUnchecked { () -> Bool in
                self.active?.attempt == attempt && !(self.owner == attempt && self.cancelRequested)
            }
            guard stillOwned else { throw CancellationError() }
        } catch {
            await unwind(attempt, writer: writer, url: url)
            // Whether or not unwind found the published copy, a started stream must not outlive a failed attempt.
            if let attemptStream { try? await attemptStream.stopCapture() }
            throw error
        }

        cursorSamples = []
        startCursorLogging()
        return (url, validatedSource)
    }

    /// Tears down one attempt's native resources and removes its partial file. Safe to repeat; a published
    /// attempt is taken exactly once, otherwise the caller's local writer is cancelled.
    @MainActor
    private func unwind(_ attempt: RecordlyRecordingAttempt, writer: AVAssetWriter?, url: URL?) async {
        cursorTimer?.invalidate()
        cursorTimer = nil
        cursorSamples = []
        if let taken = takeActive(attempt) {
            // Stopping a stream that never started throws; that is fine here.
            try? await taken.stream.stopCapture()
            Self.cancelIfLive(taken.writer)
            try? FileManager.default.removeItem(at: taken.url)
        } else if let writer {
            Self.cancelIfLive(writer)
            if let url { try? FileManager.default.removeItem(at: url) }
        }
    }

    private static func cancelIfLive(_ writer: AVAssetWriter) {
        if writer.status == .writing || writer.status == .unknown { writer.cancelWriting() }
    }

    // MARK: Private storage (privacy: owner-only media directory and files)

    private static func preparePrivateDirectory(_ directory: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let attributes = try fileManager.attributesOfItem(atPath: directory.path)
        guard (attributes[.type] as? FileAttributeType) == .typeDirectory,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid()
        else {
            throw RecordlyCaptureError.writer("The recordings folder is not a private folder owned by you, so nothing was recorded.")
        }
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }

    /// The writer creates the file inside the 0700 folder; this narrows it to owner-only as well.
    private static func restrictFile(_ url: URL) throws {
        if chmod(url.path, 0o600) != 0, errno != ENOENT {
            throw RecordlyCaptureError.writer("The recording file could not be made private.")
        }
    }

    // MARK: Cursor

    private func startCursorLogging() {
        cursorTimer?.invalidate()
        cursorTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let hostTime = CMClockGetTime(CMClockGetHostTimeClock()).seconds
                guard let t = self.stateLock.withLockUnchecked({
                    self.active?.timeline.elapsed(at: hostTime)
                }) else { return }
                let point = NSEvent.mouseLocation
                let flags = NSEvent.pressedMouseButtons
                let clicked = flags != 0
                RecordlyCursorLog.append(&self.cursorSamples, time: t, point: point, clicked: clicked)
            }
        }
    }

    // MARK: Callbacks

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
        let track = RecordlySampleRoute.track(for: sampleKind(for: type))
        if track == .audio {
            let peak = Self.peak(of: sampleBuffer)
            let now = ProcessInfo.processInfo.systemUptime
            levelLock.withLock { $0 = (peak, now) }
        }
        if track == .video {
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let rawStatus = attachments.first?[.status] as? Int,
                  SCFrameStatus(rawValue: rawStatus) == .complete
            else { return }
        }
        // withLock is @Sendable. CMSampleBuffer and AVAssetWriterInput are not, so append stays here.
        let failure = stateLock.withLockUnchecked { () -> (RecordlyRecordingAttempt, StopHook, String)? in
            // Only the stream the current attempt owns may feed its writer; frames from an older stream are dropped.
            guard var current = self.active, current.stream === stream, current.writer.status == .writing else { return nil }
            let input: AVAssetWriterInput?
            switch track {
            case .video: input = current.videoInput
            case .audio: input = current.audioInput
            case .drop: input = nil
            }
            guard let input, input.isReadyForMoreMediaData else { return nil }
            switch current.timeline.admit(presentationTime: sampleBuffer.presentationTimeStamp.seconds, isVideo: track == .video) {
            case .drop: return nil
            case .startSession: current.writer.startSession(atSourceTime: sampleBuffer.presentationTimeStamp)
            case .append: break
            }
            self.active = current
            guard !input.append(sampleBuffer), !current.writerFailureReported, let hook = current.onUnexpectedStop else { return nil }
            current.writerFailureReported = true
            self.active = current
            return (current.attempt, hook, current.writer.error?.localizedDescription ?? "A recording frame could not be written.")
        }
        if let (attempt, hook, message) = failure { hook(attempt, message) }
    }

    /// Linear peak (0...1) of the system audio the stream is delivering, or 0 once no audio arrived for 0.3 s.
    /// Read-only: it never touches the writer.
    func currentLevel() -> Float {
        let latest = levelLock.withLock { $0 }
        return ProcessInfo.processInfo.systemUptime - latest.at > 0.3 ? 0 : latest.peak
    }

    /// Peak of the first contiguous run of 32-bit float samples, which is what ScreenCaptureKit delivers.
    /// Any other layout reads as silence rather than guessing.
    private static func peak(of sampleBuffer: CMSampleBuffer) -> Float {
        guard let format = CMSampleBufferGetFormatDescription(sampleBuffer),
              let description = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
              description.mFormatID == kAudioFormatLinearPCM,
              description.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              description.mBitsPerChannel == 32,
              let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { return 0 }
        var length = 0
        var pointer: UnsafeMutablePointer<CChar>?
        guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: &length, totalLengthOut: nil,
                                          dataPointerOut: &pointer) == kCMBlockBufferNoErr,
              let pointer, length >= MemoryLayout<Float>.size else { return 0 }
        let count = length / MemoryLayout<Float>.size
        return pointer.withMemoryRebound(to: Float.self, capacity: count) { samples in
            var peak: Float = 0
            for index in 0..<count {
                let value = abs(samples[index])
                if value.isFinite, value > peak { peak = value }
            }
            return min(peak, 1)
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        let report = stateLock.withLockUnchecked { () -> (attempt: RecordlyRecordingAttempt, hook: StopHook)? in
            guard var current = self.active, current.stream === stream, !current.finishing,
                  let hook = current.onUnexpectedStop else { return nil }
            current.finishing = true
            self.active = current
            return (current.attempt, hook)
        }
        guard let report else { return }
        report.hook(report.attempt, "Screen recording stopped unexpectedly: \(error.localizedDescription)")
    }

    private func sampleKind(for type: SCStreamOutputType) -> RecordlySampleKind {
        if #available(macOS 15.0, *), type == .microphone {
            return .microphone
        }
        switch type {
        case .screen: return .screen
        case .audio: return .systemAudio
        default: return .microphone
        }
    }

    // MARK: Finish and cancel

    @MainActor
    private func endAttempt(_ attempt: RecordlyRecordingAttempt) async throws -> (URL, [RecordlyCursorSample]) {
        cursorTimer?.invalidate()
        cursorTimer = nil
        var streamAlreadyStopped = false
        let current = stateLock.withLockUnchecked { () -> Active? in
            guard var value = self.active, value.attempt == attempt else { return nil }
            streamAlreadyStopped = value.finishing
            value.finishing = true
            self.active = value
            return value
        }
        guard let current else {
            release(attempt)
            throw RecordlyCaptureError.writer("Nothing was written.")
        }

        var stopError: Error?
        // The stop callback already marked this stream finished; stopping a dead stream again could never return.
        if !streamAlreadyStopped {
            do {
                try await current.stream.stopCapture()
            } catch {
                stopError = error
            }
        }
        guard let taken = takeActive(attempt) else {
            release(attempt)
            throw RecordlyCaptureError.writer("The recording was cancelled before it finished.")
        }
        if taken.writer.status == .writing, taken.timeline.origin != nil {
            taken.videoInput.markAsFinished()
            taken.audioInput?.markAsFinished()
            await taken.writer.finishWriting()
        } else {
            Self.cancelIfLive(taken.writer)
        }

        let samples = cursorSamples
        cursorSamples = []

        if taken.writer.status == .completed {
            if let stopError {
                Self.log.error("Recordly stream stop reported an error: \(stopError.localizedDescription, privacy: .public)")
            }
            do { try Self.restrictFile(taken.url) } catch {
                Self.log.error("Recordly could not restrict the finished recording's permissions.")
            }
            release(attempt)
            return (taken.url, samples)
        }

        let writerMessage = taken.writer.error?.localizedDescription
            ?? (taken.timeline.origin == nil ? "The recording stopped before a complete video frame arrived. Please try again." : "Export incomplete.")
        try? FileManager.default.removeItem(at: taken.url)
        release(attempt)
        if let stopError {
            throw RecordlyCaptureError.writer("\(writerMessage) The capture stream also reported: \(stopError.localizedDescription)")
        }
        throw RecordlyCaptureError.writer(writerMessage)
    }

    /// Marks the attempt cancelled and unwinds whatever it has published. A begin still in flight sees the mark at
    /// its next check and unwinds its own local resources before it returns.
    @MainActor
    private func cancelAttempt(_ attempt: RecordlyRecordingAttempt) async {
        let ownsAttempt = stateLock.withLockUnchecked { () -> Bool in
            guard self.owner == attempt else { return false }
            self.cancelRequested = true
            return true
        }
        guard ownsAttempt else { return }
        await unwind(attempt, writer: nil, url: nil)
        stateLock.withLockUnchecked {
            guard self.owner == attempt, !self.beginInFlight else { return }
            self.owner = nil
            self.cancelRequested = false
        }
    }

    private static func portFailure(_ error: RecordlyCaptureError) -> RecordlyPortFailure {
        switch error {
        case .permissionDenied: .permissionDenied(error.localizedDescription)
        case .noSource(let reason): .noSource(reason)
        case .writer(let message), .stream(let message): .engine(message)
        }
    }
}

extension RecordlyCaptureEngine: RecordlyRecordingPort {
    @MainActor
    func begin(
        request: RecordlyStartRequest,
        attempt: RecordlyRecordingAttempt,
        onUnexpectedStop: @escaping @Sendable (RecordlyRecordingAttempt, String) -> Void
    ) async throws -> RecordlySourceSelection.ResolvedSource {
        do {
            let (_, resolved) = try await startAttempt(
                intent: request.intent,
                systemAudio: request.systemAudio,
                excludeZeusWindows: request.excludeZeusWindows,
                directory: request.directory,
                attempt: attempt,
                onUnexpectedStop: onUnexpectedStop
            )
            return resolved
        } catch is CancellationError {
            throw RecordlyPortFailure.cancelled
        } catch let error as RecordlyCaptureError {
            throw Self.portFailure(error)
        } catch {
            throw RecordlyPortFailure.engine(error.localizedDescription)
        }
    }

    @MainActor
    func cancel(attempt: RecordlyRecordingAttempt) async {
        await cancelAttempt(attempt)
    }

    @MainActor
    func end(attempt: RecordlyRecordingAttempt) async throws -> RecordlyRecordingOutput {
        do {
            let (url, samples) = try await endAttempt(attempt)
            return RecordlyRecordingOutput(url: url, cursorSamples: samples)
        } catch let error as RecordlyCaptureError {
            throw Self.portFailure(error)
        }
    }
}
