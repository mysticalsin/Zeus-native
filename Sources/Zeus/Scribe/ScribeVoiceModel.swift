import FluidAudio
import Foundation
import Observation
import ZeusCore

/// The WeSpeaker voice model (about 150 MB, CoreML, Neural Engine) that tells similar voices apart in Scribe.
/// This is the only file that names FluidAudio's `DiarizerModels`. The model downloads only when the owner
/// clicks Download in Settings (`SpeakerModelController.prepare`, called from that button and nowhere else);
/// meetings load it from disk when it is there and otherwise keep the hand-built voiceprint.
enum SpeakerModelStore {
    /// Both compiled models are on disk.
    static var isDownloaded: Bool {
        let directory = DiarizerModels.defaultModelsDirectory()
        return DiarizerModels.requiredModelNames.allSatisfy { name in
            FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path)
        }
    }

    /// Fetches the models. Only the Settings Download button reaches this.
    nonisolated static func download(report: @escaping @Sendable (Double) -> Void) async throws {
        _ = try await DiarizerModels.download(progressHandler: { update in report(update.fractionCompleted) })
    }

    /// An embedder over the models already on disk, or nil when they are not there or do not load. It never
    /// starts a download: the files are checked first.
    nonisolated static func loadEmbedder() async -> FluidVoiceEmbedder? {
        guard isDownloaded, let models = try? await DiarizerModels.load() else { return nil }
        return FluidVoiceEmbedder(models: models)
    }
}

/// WeSpeaker embeddings through FluidAudio. `DiarizerManager` is not `Sendable`: one instance per meeting, owned
/// by the recogniser and called only while its lock is held, never from the main actor.
final class FluidVoiceEmbedder: ScribeVoiceEmbedder, @unchecked Sendable {
    let kind = ScribeEmbeddingKind.wespeaker
    /// The model reads a 10 s window at 16 kHz; a longer chunk is cut to its middle.
    private static let windowSamples = 160_000
    private let manager: DiarizerManager

    init(models: DiarizerModels) {
        let manager = DiarizerManager()
        manager.initialize(models: models)
        self.manager = manager
    }

    /// Nil for a chunk shorter than `ScribeVoiceEmbedding.minimumSeconds` (the model repeat-pads short audio,
    /// which makes a vector that says little about the voice) or when the model fails.
    func embedding(samples: [Float]) -> ScribeVoiceEmbedding? {
        let minimum = Int(ScribeVoiceEmbedding.minimumSeconds(for: .wespeaker) * Double(ScribePCM.sampleRate))
        guard samples.count >= minimum else { return nil }
        let clip: [Float]
        if samples.count > Self.windowSamples {
            let start = (samples.count - Self.windowSamples) / 2
            clip = Array(samples[start..<(start + Self.windowSamples)])
        } else {
            clip = samples
        }
        guard let vector = try? manager.extractSpeakerEmbedding(from: clip) else { return nil }
        return ScribeVoiceEmbedding.wespeaker(vector)
    }
}

/// The Settings row's state: one `ModelPreparation` state, like Parakeet's. Only a click moves it out of idle.
@MainActor
@Observable
final class SpeakerModelController {
    static let shared = SpeakerModelController()

    private(set) var state: ModelPreparation.State
    @ObservationIgnored private var token: UInt64 = 0
    @ObservationIgnored private var task: Task<Void, Never>?

    init() {
        state = SpeakerModelStore.isDownloaded ? .ready : .idle
    }

    var progress: Double? { ModelPreparation.progress(of: state) }
    var problem: String? { ModelPreparation.problem(of: state) }

    /// Re-reads the disk (the page just opened, or a delete outside the app).
    func refresh() {
        switch state {
        case .idle where SpeakerModelStore.isDownloaded: state = .ready
        case .ready where !SpeakerModelStore.isDownloaded: state = .idle
        default: break
        }
    }

    /// The Download button. Never called at launch or from a meeting.
    func prepare() {
        token &+= 1
        send(.startRequested(token: token, trigger: .explicit, downloaded: SpeakerModelStore.isDownloaded, announce: false))
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
                    try await SpeakerModelStore.download { fraction in
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

/// Saved voices for the Settings list: loaded from and written to the local file, never anywhere else.
@MainActor
@Observable
final class SavedVoicesModel {
    static let shared = SavedVoicesModel()

    private(set) var voices: [ScribeSavedVoice] = []
    private(set) var problem: String?
    @ObservationIgnored private let store: ScribeVoiceLibraryStore

    init(store: ScribeVoiceLibraryStore = .standard) {
        self.store = store
        reload()
    }

    func reload() {
        do {
            voices = try store.load().voices
            problem = nil
        } catch {
            problem = error.localizedDescription
        }
    }

    func delete(_ id: UUID) { change { $0.delete(id: id) } }
    func deleteAll() { change { $0.deleteAll() } }

    /// Saves (or folds into) a voice. False when the file could not be written.
    @discardableResult
    func remember(name: String, embedding: ScribeVoiceEmbedding, sampleCount: Int) -> Bool {
        var saved = false
        change { saved = $0.remember(name: name, embedding: embedding, sampleCount: sampleCount) != nil }
        return saved && problem == nil
    }

    var names: [String] { voices.map(\.name) }

    private func change(_ edit: (inout ScribeVoiceLibrary) -> Void) {
        do {
            var library = try store.load()
            edit(&library)
            try store.save(library)
            voices = library.voices
            problem = nil
        } catch {
            problem = error.localizedDescription
        }
    }
}
