import FluidAudio
import Foundation
import Observation
import ZeusCore

/// NVIDIA Nemotron 3 Diarization through FluidAudio 0.18 (`Nemotron3Diarizer`), the live speaker separation
/// Scribe prefers when its model is on disk. This file and `GSSpeakerRecognitionCard` are the only places that
/// name it. The model downloads only when the owner clicks Download in Settings
/// (`StreamingDiarizerModelController.prepare`); meetings load it from disk and otherwise keep WeSpeaker, then the
/// hand-built voiceprint.
enum StreamingDiarizerStore {
    /// The 2.88 s latency preset FluidAudio recommends when a little delay is fine.
    static let config = Nemotron3Config.fast32

    private static var repositoryDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FluidAudio/Models")
            .appendingPathComponent(Repo.nemotron3Diarization.folderName)
    }

    /// The preset's compiled model, the silence embedding and the weights marker are all on disk.
    static var isDownloaded: Bool {
        let manager = FileManager.default
        let directory = repositoryDirectory
        let manifest = directory.appendingPathComponent(config.hubSubdirectory)
            .appendingPathComponent(config.modelFileName).appendingPathComponent("coremldata.bin")
        let silence = directory.appendingPathComponent(ModelNames.Nemotron3.silenceEmbeddingFile)
        let marker = directory.appendingPathComponent(ModelNames.Nemotron3.weightsVersionFile)
        guard manager.fileExists(atPath: manifest.path), manager.fileExists(atPath: silence.path),
              let version = try? String(contentsOf: marker, encoding: .utf8) else { return false }
        return version.trimmingCharacters(in: .whitespacesAndNewlines) == ModelNames.Nemotron3.weightsVersion
    }

    /// Fetches the model. Only the Settings Download button reaches this.
    nonisolated static func download(report: @escaping @Sendable (Double) -> Void) async throws {
        _ = try await Nemotron3Models.loadFromHuggingFace(config: config, progressHandler: { report($0.fractionCompleted) })
    }

    /// A diarizer over the files already on disk, or nil when they are not there or do not load. The files are
    /// checked first, so this never starts a download.
    nonisolated static func load() async -> FluidStreamingDiarizer? {
        guard isDownloaded, let models = try? await Nemotron3Models.loadFromHuggingFace(config: config) else { return nil }
        return FluidStreamingDiarizer(models: models)
    }
}

/// Streams the system channel through Nemotron. Each closed turn is fed in order, followed by enough silence for
/// the model to emit every frame of the turn at once; the speaker with the most active frames inside the turn is
/// its voice. Slots are numbered by first arrival, so slot 0 is "Speaker 1". When the meeting ends the stream is
/// flushed and every turn is read again with the whole timeline in hand: the final relabel.
///
/// Not thread-safe: one instance per meeting, used only while the recogniser's lock is held.
final class FluidStreamingDiarizer: @unchecked Sendable {
    private static let sampleRate = 16_000
    private static let samplesPerFrame = 160
    /// Fewer active frames than this (0.2 s) is not enough to name a voice.
    private static let minimumFrames = 20
    private static let activeThreshold: Float = 0.5

    private let diarizer: Nemotron3Diarizer
    private let config: Nemotron3Config
    private var probabilities: [Float] = []
    private var fedSamples = 0
    private var ranges: [String: Range<Int>] = [:]
    private var liveSlot: [String: Int] = [:]
    private var failed = false
    private var finished = false
    /// The slot of the last turn that had one, for a turn too short to decide.
    private(set) var lastSlot: Int?

    init(models: Nemotron3Models) {
        let config = StreamingDiarizerStore.config
        self.config = config
        self.diarizer = Nemotron3Diarizer(config: config, models: models)
    }

    /// The slot (0...7) that spoke this turn, or nil when the model could not decide.
    func assign(id: String, samples: [Float]) -> Int? {
        guard !failed, !finished, !samples.isEmpty else { return nil }
        let startFrame = fedSamples / Self.samplesPerFrame
        let padding = [Float](repeating: 0, count: Int((config.latencySeconds + config.chunkSeconds) * Double(Self.sampleRate)))
        do {
            diarizer.appendAudio(samples)
            diarizer.appendAudio(padding)
            fedSamples += samples.count + padding.count
            for result in try diarizer.processBufferedAudio() { probabilities.append(contentsOf: result.probabilities) }
        } catch {
            failed = true
            return nil
        }
        let range = startFrame..<(startFrame + samples.count / Self.samplesPerFrame)
        ranges[id] = range
        guard let slot = dominantSlot(in: range) else { return nil }
        liveSlot[id] = slot
        lastSlot = slot
        return slot
    }

    /// The turn took its name from somewhere else (a saved voice): the final relabel must leave it alone.
    func exclude(id: String) {
        ranges[id] = nil
        liveSlot[id] = nil
    }

    /// Flushes the stream and returns, for every turn whose final slot differs from the live one, that slot.
    func finish() -> [String: Int] {
        guard !failed, !finished else { return [:] }
        finished = true
        if let rest = try? diarizer.finishStream() {
            for result in rest { probabilities.append(contentsOf: result.probabilities) }
        }
        var changed: [String: Int] = [:]
        for (id, range) in ranges {
            guard let slot = dominantSlot(in: range), slot != liveSlot[id] else { continue }
            changed[id] = slot
        }
        return changed
    }

    private func dominantSlot(in range: Range<Int>) -> Int? {
        let speakers = config.numSpeakers
        let frames = probabilities.count / speakers
        let low = max(0, range.lowerBound)
        let high = min(range.upperBound, frames)
        guard low < high else { return nil }
        var counts = [Int](repeating: 0, count: speakers)
        for frame in low..<high {
            for slot in 0..<speakers where probabilities[frame * speakers + slot] > Self.activeThreshold { counts[slot] += 1 }
        }
        guard let best = counts.max(), best >= Self.minimumFrames else { return nil }
        return counts.firstIndex(of: best)
    }
}

/// The Settings row's state for the Nemotron model: one `ModelPreparation` state, like the speaker model's.
/// Only a click moves it out of idle.
@MainActor
@Observable
final class StreamingDiarizerModelController {
    static let shared = StreamingDiarizerModelController()

    private(set) var state: ModelPreparation.State
    @ObservationIgnored private var token: UInt64 = 0
    @ObservationIgnored private var task: Task<Void, Never>?

    init() {
        state = StreamingDiarizerStore.isDownloaded ? .ready : .idle
    }

    var progress: Double? { ModelPreparation.progress(of: state) }

    /// Re-reads the disk (the page just opened, or a delete outside the app).
    func refresh() {
        switch state {
        case .idle where StreamingDiarizerStore.isDownloaded: state = .ready
        case .ready where !StreamingDiarizerStore.isDownloaded: state = .idle
        default: break
        }
    }

    /// The Download button. Never called at launch or from a meeting.
    func prepare() {
        token &+= 1
        send(.startRequested(token: token, trigger: .explicit, downloaded: StreamingDiarizerStore.isDownloaded, announce: false))
    }

    func cancel() { send(.cancelRequested) }

    private func send(_ event: ModelPreparation.Event) {
        let (next, effects) = ModelPreparation.reduce(state, event)
        guard next != state || !effects.isEmpty else { return }
        state = next
        for effect in effects { perform(effect) }
    }

    private func perform(_ effect: ModelPreparation.Effect) {
        switch effect {
        case .startWork(let token, _):
            task = Task { @MainActor [weak self] in
                do {
                    try await StreamingDiarizerStore.download { fraction in
                        DispatchQueue.main.async { MainActor.assumeIsolated { self?.send(.progress(token: token, fraction: fraction)) } }
                    }
                    self?.send(.succeeded(token: token))
                } catch {
                    self?.send(.failed(token: token, message: error.localizedDescription))
                }
            }
        case .cancelWork:
            task?.cancel()
            task = nil
        case .announce:
            break
        }
    }
}
