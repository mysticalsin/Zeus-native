import AVFoundation
import FluidAudio
import Foundation
import ZeusCore

enum ExplanationAudioError: Error, Equatable {
    case busy, invalidSpeech, voiceNotInstalled, invalidPCM, resourceLimit, noAudio
    case timedOut, unavailable, unknownAudio, invalidPlayback
}

struct ExplanationSpeechRequest: Sendable {
    let sessionID: UUID
    let turnID: UUID
    let sceneID: UUID
    let beatID: String
    let speech: ExplanationSpeech

    init(event: ExplanationEvent) {
        sessionID = event.sessionID; turnID = event.turnID; sceneID = event.sceneID
        beatID = event.beatID; speech = event.speech
    }

    func chunk(duration: Double, sampleRate: Double) -> ExplanationAudioChunk {
        .init(sessionID: sessionID, turnID: turnID, sceneID: sceneID, beatID: beatID,
              chunkID: speech.chunkID, duration: duration, sampleRate: sampleRate)
    }
}

/// The model never supplies this URL. The renderer creates a private directory and
/// transfers its ownership with the prepared clip; its last owner removes the file.
final class ExplanationPreparedAudio: @unchecked Sendable {
    let chunk: ExplanationAudioChunk
    fileprivate let file: URL
    private let directory: URL

    fileprivate init(chunk: ExplanationAudioChunk, file: URL, directory: URL) {
        self.chunk = chunk; self.file = file; self.directory = directory
    }

    deinit { try? FileManager.default.removeItem(at: directory) }
}

@MainActor
protocol SpeechOutputProvider: AnyObject {
    func render(_ request: ExplanationSpeechRequest) async throws -> ExplanationPreparedAudio
}

/// Two admitted beats, including the active renderer. No unbounded synthesis task
/// queue and no automatic provider fallback. The provider itself owns cancellation.
@MainActor
final class ExplanationSpeechRenderQueue {
    private struct Job {
        let request: ExplanationSpeechRequest
        var continuation: CheckedContinuation<ExplanationPreparedAudio, Error>?
    }
    private let provider: any SpeechOutputProvider
    private var jobs: [UUID: Job] = [:]
    private var pending: [UUID] = []
    private var active: UUID?
    private var work: Task<Void, Never>?

    init(provider: any SpeechOutputProvider) { self.provider = provider }
    var admittedCount: Int { jobs.count }

    func render(_ request: ExplanationSpeechRequest) async throws -> ExplanationPreparedAudio {
        try Task.checkCancellation()
        guard jobs.count < 2 else { throw ExplanationAudioError.busy }
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else { continuation.resume(throwing: CancellationError()); return }
                jobs[id] = Job(request: request, continuation: continuation)
                pending.append(id); pump()
            }
        } onCancel: { Task { @MainActor [weak self] in self?.cancel(id) } }
    }

    func cancelAll() { for id in Array(jobs.keys) { cancel(id) } }

    private func cancel(_ id: UUID) {
        guard var job = jobs[id] else { return }
        let continuation = job.continuation; job.continuation = nil
        if active == id {
            jobs[id] = job; work?.cancel() // Keep ownership until the real provider unwinds.
        } else { pending.removeAll { $0 == id }; jobs[id] = nil }
        continuation?.resume(throwing: CancellationError())
    }

    private func pump() {
        guard active == nil, !pending.isEmpty else { return }
        let id = pending.removeFirst()
        guard let job = jobs[id] else { pump(); return }
        active = id
        work = Task { @MainActor [self] in
            let result: Result<ExplanationPreparedAudio, Error>
            do { result = .success(try await provider.render(job.request)) }
            catch { result = .failure(error) }
            let continuation = jobs.removeValue(forKey: id)?.continuation
            active = nil; work = nil
            continuation?.resume(with: result)
            pump()
        }
    }
}

/// A fake writer can deliver synthetic PCM without requesting an installed voice,
/// playing sound, contacting a provider, or opening any capture device.
@MainActor
protocol ExplanationSpeechWriting: AnyObject {
    func write(text: String, voiceIdentifier: String?, language: String,
               receive: @escaping @Sendable (AVAudioBuffer) -> Void) throws
    func stop()
}

enum ExplanationSystemVoices {
    static let preferenceKey = "opt.explanation.voice"
    struct Choice: Identifiable, Equatable, Sendable {
        let id: String
        let name: String
        let language: String
    }

    @MainActor static func installed() -> [Choice] {
        var seen = Set<String>()
        return AVSpeechSynthesisVoice.speechVoices().filter { seen.insert($0.identifier).inserted }
            .map { Choice(id: $0.identifier, name: $0.name, language: $0.language) }
            .sorted { ($0.name, $0.language, $0.id) < ($1.name, $1.language, $1.id) }
    }

    /// Both an explicit choice and the OS default must be in the installed set.
    /// A removed voice is an error, never permission to substitute/download one.
    static func resolve(requested: String?, installedIDs: Set<String>, systemDefaultID: String?) throws -> String {
        let selected = requested.flatMap { $0.isEmpty ? nil : $0 } ?? systemDefaultID
        guard let selected, installedIDs.contains(selected) else { throw ExplanationAudioError.voiceNotInstalled }
        return selected
    }
}

@MainActor
private final class InstalledSystemSpeechWriter: ExplanationSpeechWriting {
    private let synthesizer = AVSpeechSynthesizer()

    func write(text: String, voiceIdentifier: String?, language: String,
               receive: @escaping @Sendable (AVAudioBuffer) -> Void) throws {
        // Enumerate installed voices only. An explicit unavailable choice fails;
        // no default provider chain, asset installer or network service is invoked.
        let installed = AVSpeechSynthesisVoice.speechVoices()
        let selected = try ExplanationSystemVoices.resolve(requested: voiceIdentifier,
            installedIDs: Set(installed.map(\.identifier)),
            systemDefaultID: voiceIdentifier == nil ? AVSpeechSynthesisVoice(language: language)?.identifier : nil)
        guard let voice = installed.first(where: { $0.identifier == selected }) else { throw ExplanationAudioError.voiceNotInstalled }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.write(utterance, toBufferCallback: receive)
    }

    func stop() { synthesizer.stopSpeaking(at: .immediate) }
}

/// Synchronous bounded sink on the synthesis callback: no per-buffer Task backlog,
/// no buffer retained after its callback, and no unbounded in-memory PCM array.
final class ExplanationPCMSink: @unchecked Sendable {
    static let maxSeconds = 90.0
    static let maxBytes = 32 * 1_024 * 1_024
    private let lock = NSLock()
    private let request: ExplanationSpeechRequest
    private let directory: URL
    private let url: URL
    private var file: AVAudioFile?
    private var format: AVAudioFormat?
    private var frames: Int64 = 0
    private var bytes = 0
    private var completed = false
    private var completion: (@Sendable (Result<ExplanationPreparedAudio, Error>) -> Void)?

    init(request: ExplanationSpeechRequest, root: URL = FileManager.default.temporaryDirectory,
         completion: @escaping @Sendable (Result<ExplanationPreparedAudio, Error>) -> Void) throws {
        self.request = request; self.completion = completion
        directory = root.appendingPathComponent("zeus-explanation-" + UUID().uuidString, isDirectory: true)
        url = directory.appendingPathComponent("speech.caf")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
    }

    func receive(_ buffer: AVAudioBuffer) {
        let outcome: (Result<ExplanationPreparedAudio, Error>, @Sendable (Result<ExplanationPreparedAudio, Error>) -> Void)? = lock.withLock {
            guard !completed else { return nil }
            do {
                guard let pcm = buffer as? AVAudioPCMBuffer else { throw ExplanationAudioError.invalidPCM }
                if pcm.frameLength == 0 {
                    guard let format, frames > 0 else { throw ExplanationAudioError.noAudio }
                    file = nil // close and finalize the owned audio container before transfer
                    let result = ExplanationPreparedAudio(chunk: request.chunk(duration: Double(frames) / format.sampleRate,
                                                                                 sampleRate: format.sampleRate),
                                                          file: url, directory: directory)
                    return finishLocked(.success(result))
                }
                let incoming = pcm.format
                guard incoming.sampleRate.isFinite, incoming.sampleRate >= 8_000, incoming.sampleRate <= 192_000,
                      (1...2).contains(incoming.channelCount),
                      incoming.commonFormat == .pcmFormatFloat32 || incoming.commonFormat == .pcmFormatInt16 || incoming.commonFormat == .pcmFormatInt32
                else { throw ExplanationAudioError.invalidPCM }
                if let format, !format.isEqual(incoming) { throw ExplanationAudioError.invalidPCM }
                let bufferBytes = UnsafeMutableAudioBufferListPointer(pcm.mutableAudioBufferList).reduce(0) { $0 + Int($1.mDataByteSize) }
                guard bufferBytes > 0, bufferBytes <= Self.maxBytes - bytes,
                      Double(frames + Int64(pcm.frameLength)) / incoming.sampleRate <= Self.maxSeconds
                else { throw ExplanationAudioError.resourceLimit }
                if incoming.commonFormat == .pcmFormatFloat32 {
                    guard let channels = pcm.floatChannelData else { throw ExplanationAudioError.invalidPCM }
                    let channelBuffers = incoming.isInterleaved ? 1 : Int(incoming.channelCount)
                    let samplesPerBuffer = Int(pcm.frameLength) * (incoming.isInterleaved ? Int(incoming.channelCount) : 1)
                    for channel in 0..<channelBuffers {
                        guard UnsafeBufferPointer(start: channels[channel], count: samplesPerBuffer).allSatisfy(\.isFinite)
                        else { throw ExplanationAudioError.invalidPCM }
                    }
                }
                if file == nil {
                    format = incoming
                    file = try AVAudioFile(forWriting: url, settings: incoming.settings,
                                           commonFormat: incoming.commonFormat, interleaved: incoming.isInterleaved)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                }
                try file?.write(from: pcm)
                frames += Int64(pcm.frameLength); bytes += bufferBytes
                return nil
            } catch { return finishLocked(.failure(error)) }
        }
        if let (result, callback) = outcome { callback(result) }
    }

    func abort(_ error: Error) {
        let result = lock.withLock { completed ? nil : finishLocked(.failure(error)) }
        if let (result, callback) = result { callback(result) }
    }

    private func finishLocked(_ result: Result<ExplanationPreparedAudio, Error>)
        -> (Result<ExplanationPreparedAudio, Error>, @Sendable (Result<ExplanationPreparedAudio, Error>) -> Void)? {
        completed = true; file = nil
        if case .failure = result { try? FileManager.default.removeItem(at: directory) }
        guard let completion else { return nil }
        self.completion = nil
        return (result, completion)
    }
}

@MainActor
final class SystemExplanationSpeechOutput: SpeechOutputProvider {
    private let writer: any ExplanationSpeechWriting
    private let selectedVoice: () -> String?
    private let language: String
    private let temporaryRoot: URL
    private var active: UUID?

    init(voiceIdentifier: String? = nil, language: String = Locale.current.identifier.replacingOccurrences(of: "_", with: "-"),
         writer: (any ExplanationSpeechWriting)? = nil, temporaryRoot: URL = FileManager.default.temporaryDirectory,
         selectedVoice: (() -> String?)? = nil) {
        if let selectedVoice { self.selectedVoice = selectedVoice }
        else if let voiceIdentifier { self.selectedVoice = { voiceIdentifier } }
        else if writer != nil { self.selectedVoice = { nil } } // Synthetic writers never read user preferences.
        else { self.selectedVoice = { UserDefaults.standard.string(forKey: ExplanationSystemVoices.preferenceKey) } }
        self.language = language
        self.writer = writer ?? InstalledSystemSpeechWriter(); self.temporaryRoot = temporaryRoot
    }

    func render(_ request: ExplanationSpeechRequest) async throws -> ExplanationPreparedAudio {
        try Task.checkCancellation()
        guard active == nil else { throw ExplanationAudioError.busy }
        guard !request.speech.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              request.speech.text.utf8.count <= ExplanationLimits.speech else { throw ExplanationAudioError.invalidSpeech }
        // Snapshot once, before any suspension. A settings change stops the active
        // controller turn; the replacement render observes the new preference.
        let voiceIdentifier = selectedVoice().flatMap { $0.isEmpty ? nil : $0 }
        let id = UUID(); active = id
        let cancellation = ExplanationSynthesisCancellation()
        defer { cancellation.cancel(); writer.stop(); active = nil }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                do {
                    let sink = try ExplanationPCMSink(request: request, root: temporaryRoot) { result in
                        continuation.resume(with: result)
                    }
                    cancellation.install(sink)
                    guard !Task.isCancelled else { sink.abort(CancellationError()); return }
                    let timer = Task { @MainActor in
                        do { try await Task.sleep(for: .seconds(60)) } catch { return }
                        sink.abort(ExplanationAudioError.timedOut)
                    }
                    cancellation.setTimer(timer)
                    do {
                        try writer.write(text: request.speech.text, voiceIdentifier: voiceIdentifier,
                                         language: language) { buffer in sink.receive(buffer) }
                    } catch { sink.abort(error) }
                } catch { continuation.resume(throwing: error) }
            }
        } onCancel: { cancellation.cancel() }
    }
}

@MainActor
protocol ExplanationMediaPlaying: AnyObject {
    var duration: Double { get }
    var currentTime: Double { get set }
    var rate: Float { get set }
    var isPlaying: Bool { get }
    var onFinish: ((Bool) -> Void)? { get set }
    func play() -> Bool
    func pause()
    func stop()
}

@MainActor
private final class NativeExplanationMediaPlayer: NSObject, ExplanationMediaPlaying, AVAudioPlayerDelegate {
    private let player: AVAudioPlayer
    var onFinish: ((Bool) -> Void)?
    init(file: URL) throws {
        player = try AVAudioPlayer(contentsOf: file)
        super.init()
        player.enableRate = true; player.delegate = self
        guard player.prepareToPlay() else { throw ExplanationAudioError.invalidPlayback }
    }
    var duration: Double { player.duration }
    var currentTime: Double { get { player.currentTime } set { player.currentTime = newValue } }
    var rate: Float { get { player.rate } set { player.rate = newValue } }
    var isPlaying: Bool { player.isPlaying }
    func play() -> Bool { player.play() }
    func pause() { player.pause() }
    func stop() { player.stop() }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in self?.onFinish?(flag) }
    }
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self] in self?.onFinish?(false) }
    }
    isolated deinit { player.delegate = nil; player.stop() }
}

/// Actual media-clock adapter. A new play/seek creates a fresh native player and
/// ticket; a callback from a stopped player cannot advance its replacement beat.
@MainActor
final class ExplanationAudioPlayer {
    typealias Factory = @MainActor (URL) throws -> any ExplanationMediaPlaying
    var onObservation: ((ExplanationPlaybackObservation) -> Void)?
    /// Window visibility is not proof of display-link delivery: occlusion may
    /// suspend the native link without a SwiftUI disappearance notification.
    var externalDisplayClockActive = false {
        didSet {
            guard externalDisplayClockActive != oldValue else { return }
            lastExternalObservation = nil
            clockTask?.cancel(); clockTask = nil
            startFallbackClock()
        }
    }
    private let factory: Factory
    private let monotonicNow: () -> ContinuousClock.Instant
    private var lastExternalObservation: ContinuousClock.Instant?
    private var prepared: [UUID: ExplanationPreparedAudio] = [:]
    private var ticket: ExplanationPlaybackTicket?
    private var player: (any ExplanationMediaPlaying)?
    private var clockTask: Task<Void, Never>?
    private var observations: [ExplanationPlaybackObservation] = []
    private var observationTask: Task<Void, Never>?
    private var observationEpoch: UInt64 = 0
    var pendingObservationCount: Int { observations.count }

    init(factory: Factory? = nil, monotonicNow: @escaping () -> ContinuousClock.Instant = { .now }) {
        self.factory = factory ?? { try NativeExplanationMediaPlayer(file: $0) }
        self.monotonicNow = monotonicNow
    }

    func register(_ audio: ExplanationPreparedAudio) throws {
        if let known = prepared[audio.chunk.id] {
            guard known === audio else { throw ExplanationAudioError.unknownAudio }
            return
        }
        guard prepared.count < 2 else { throw ExplanationAudioError.busy }
        prepared[audio.chunk.id] = audio
    }

    func unregister(_ id: UUID) {
        if ticket?.audioID == id { discardObservations(); stopCurrent() }
        prepared[id] = nil
    }

    func stopAll() { discardObservations(); stopCurrent(); prepared.removeAll() }

    func execute(_ command: ExplanationPlaybackCommand) {
        switch command {
        case let .play(ticket, audio, position, rate):
            discardObservations()
            stopCurrent()
            do {
                guard let owned = prepared[audio.id], owned.chunk == audio,
                      ticket.audioID == audio.id, ticket.sessionID == audio.sessionID,
                      ticket.turnID == audio.turnID, ticket.sceneID == audio.sceneID, ticket.beatID == audio.beatID
                else { throw ExplanationAudioError.unknownAudio }
                guard position.isFinite, position >= 0, position < audio.duration,
                      rate.isFinite, (0.5...2).contains(rate) else { throw ExplanationAudioError.invalidPlayback }
                let player = try factory(owned.file)
                guard player.duration.isFinite, player.duration > 0,
                      abs(player.duration - audio.duration) <= max(0.05, 2 / audio.sampleRate)
                else { throw ExplanationAudioError.invalidPlayback }
                self.ticket = ticket; self.player = player
                player.onFinish = { [weak self] success in self?.finished(ticketID: ticket.id, success: success) }
                player.rate = Float(rate); player.currentTime = position
                guard player.play() else { throw ExplanationAudioError.invalidPlayback }
                observeClock()
                startFallbackClock()
            } catch {
                stopCurrent()
                emit(.init(ticketID: ticket.id, position: position.isFinite ? max(0, position) : 0,
                           state: .failed("Narration playback is unavailable.")))
            }
        case .pause(let ticketID):
            guard ticket?.id == ticketID, let player else { return }
            player.pause(); clockTask?.cancel(); clockTask = nil
            emit(.init(ticketID: ticketID, position: player.currentTime, state: .paused))
        case .stop(let ticketID):
            guard ticket?.id == ticketID else { return }
            discardObservations()
            stopCurrent()
        case let .setRate(ticketID, rate):
            guard ticket?.id == ticketID, rate.isFinite, (0.5...2).contains(rate) else { return }
            player?.rate = Float(rate)
        }
    }

    /// May also be sampled by the display driver. This reports the media clock;
    /// the polling interval is neither an audio duration nor a display-FPS claim.
    func observeClock() {
        guard let ticket, let player, player.isPlaying else { return }
        let position = player.currentTime
        guard position.isFinite, position >= 0 else { finished(ticketID: ticket.id, success: false); return }
        emit(.init(ticketID: ticket.id, position: min(position, player.duration), state: .playing))
    }

    func observeDisplayClock() {
        lastExternalObservation = monotonicNow()
        observeClock()
    }

    /// Monotonic time only detects a missing display callback. It never advances
    /// speech/cues itself: even this fallback reads AVAudioPlayer.currentTime.
    func sampleFallbackClock() {
        if externalDisplayClockActive, let lastExternalObservation,
           lastExternalObservation.duration(to: monotonicNow()) < .milliseconds(50) { return }
        observeClock()
    }

    private func finished(ticketID: UUID, success: Bool) {
        guard ticket?.id == ticketID, let player else { return }
        let position = success ? player.duration : player.currentTime
        stopCurrent()
        emit(.init(ticketID: ticketID, position: position,
                   state: success ? .finished : .failed("Narration playback failed.")))
    }

    private func stopCurrent() {
        clockTask?.cancel(); clockTask = nil
        lastExternalObservation = nil
        ticket = nil; player?.onFinish = nil; player?.stop(); player = nil
    }

    private func startFallbackClock() {
        guard clockTask == nil, let ticket, player?.isPlaying == true else { return }
        clockTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                let delay = self?.externalDisplayClockActive == true ? 50 : 16
                do { try await Task.sleep(for: .milliseconds(delay)) } catch { return }
                guard let self, self.ticket?.id == ticket.id else { return }
                self.sampleFallbackClock()
            }
        }
    }

    private func emit(_ observation: ExplanationPlaybackObservation) {
        // Commands can have subsequent scene/history effects in the coordinator.
        // One deferred drain preserves playing-before-finished even for a tiny clip.
        // Only adjacent clock samples coalesce; control transitions stay ordered.
        if let last = observations.last, last.ticketID == observation.ticketID,
           last.state == .playing, observation.state == .playing {
            observations[observations.count - 1] = observation
        } else if observations.count < 16 { observations.append(observation) }
        else {
            stopCurrent()
            observations = [.init(ticketID: observation.ticketID, position: 0,
                                  state: .failed("Narration callbacks exceeded their safe queue limit."))]
        }
        guard observationTask == nil else { return }
        let epoch = observationEpoch
        observationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while self.observationEpoch == epoch, !Task.isCancelled, !self.observations.isEmpty {
                let next = self.observations.removeFirst()
                self.onObservation?(next)
            }
            // A callback can replace the playback attempt and schedule its own drain.
            if self.observationEpoch == epoch { self.observationTask = nil }
        }
    }

    private func discardObservations() {
        observationEpoch &+= 1
        observationTask?.cancel(); observationTask = nil
        observations.removeAll(keepingCapacity: true)
    }

    isolated deinit { stopAll() }
}

private final class ExplanationSynthesisCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var sink: ExplanationPCMSink?
    private var timer: Task<Void, Never>?
    private var cancelled = false
    func install(_ sink: ExplanationPCMSink) {
        let shouldCancel = lock.withLock { self.sink = sink; return cancelled }
        if shouldCancel { sink.abort(CancellationError()) }
    }
    func setTimer(_ timer: Task<Void, Never>) {
        let shouldCancel = lock.withLock { self.timer = timer; return cancelled }
        if shouldCancel { timer.cancel() }
    }
    func cancel() {
        let (sink, timer): (ExplanationPCMSink?, Task<Void, Never>?) = lock.withLock {
            self.cancelled = true
            return (self.sink, self.timer)
        }
        timer?.cancel(); sink?.abort(CancellationError())
    }
    deinit { timer?.cancel() }
}

/// Compile-only compatibility seam. Nothing constructs a manager at runtime:
/// FluidAudio 0.18 has lazy downloads outside its global offline setting. An
/// installed/cache-only capability must be verified before this can be selected.
enum ExplanationFluidLegacyCandidate {
    static let unavailableReason = "Native Kokoro needs a verified model installation and cache-only inference boundary."
    static var isAvailable: Bool { false }
    private static func compileReferenceOnly(text: String, directory: URL) async throws -> Data {
        let manager = KokoroAneManager(directory: directory, version: .legacy)
        try await manager.initialize(preloadVoices: ["af_heart"])
        return try await manager.synthesize(text: text, voice: "af_heart", speed: 1)
    }
}
