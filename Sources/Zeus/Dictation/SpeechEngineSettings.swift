import Observation
import SwiftUI
import ZeusCore

/// Download and load state of the local speech model, for Settings.
@MainActor
@Observable
final class SpeechEngineStatus {
    static let shared = SpeechEngineStatus()

    var downloaded = false
    /// 0…1 while downloading or loading.
    var progress: Double?
    var problem: String?

    func refresh(_ engine: ParakeetEngine) {
        downloaded = engine.isDownloaded
    }
}

/// Settings › Dictation › Speech engine.
struct SpeechEngineSection: View {
    let settings: DictationSettings
    let dictation: DictationController?
    let status = SpeechEngineStatus.shared

    var body: some View {
        Section("Speech engine") {
            Picker("Engine", selection: Binding(get: { settings.engine }, set: { settings.engine = $0 })) {
                ForEach(TranscriptionEngineKind.allCases.filter { $0 != .whisper }) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            Text(settings.engine.detail).font(.callout).foregroundStyle(.secondary)
            if settings.engine == .parakeet {
                if let progress = status.progress {
                    ProgressView(value: progress) { Text(status.downloaded ? "Loading Parakeet…" : "Downloading Parakeet…") }
                    if let dictation { Button("Cancel") { dictation.cancelModelPreparation() } }
                } else if status.downloaded {
                    Label("On this Mac. Audio never leaves it.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    HStack {
                        Text("Apple speech is used until Parakeet is downloaded.").foregroundStyle(.secondary)
                        Spacer()
                        if let dictation { Button("Download") { dictation.prepareModel() } }
                    }
                }
                if let problem = status.problem {
                    Text(problem).font(.callout).foregroundStyle(.red)
                }
            }
        }
        .onAppear { if let dictation { status.refresh(dictation.parakeet) } }
    }
}
