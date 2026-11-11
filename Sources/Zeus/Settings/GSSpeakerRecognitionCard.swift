import SwiftUI
import ZeusCore

/// Settings: Speaker recognition for Scribe. One optional model (about 150 MB, on this Mac) that tells similar
/// voices apart, and the voices the owner chose to remember. The model downloads only when Download is clicked.
@MainActor
struct SpeakerRecognitionCard: View {
    private var model: SpeakerModelController { .shared }
    private var voices: SavedVoicesModel { .shared }
    @State private var confirmingDeleteAll = false

    var body: some View {
        GSCard("Speaker recognition") {
            modelRow
            GSDivider()
            voicesHeader
            if voices.voices.isEmpty {
                GSInfo(text: "No saved voices. Zeus saves one only when you rename a speaker and tick Remember this voice.")
            } else {
                ForEach(voices.voices) { voice in
                    GSDivider()
                    GSRow(symbol: "person.wave.2", title: voice.name, text: "Saved \(voice.updatedAt.formatted(date: .abbreviated, time: .omitted))") {
                        Button("Delete") { voices.delete(voice.id) }
                            .buttonStyle(GSButtonStyle())
                            .accessibilityLabel("Delete the saved voice of \(voice.name)")
                    }
                }
            }
            if let problem = voices.problem { GSInfo(text: problem) }
            GSInfo(text: "Only save voices of people who agreed.")
        }
        .onAppear {
            model.refresh()
            voices.reload()
        }
    }

    @ViewBuilder private var modelRow: some View {
        GSRow(symbol: "waveform.badge.person.crop", title: "Tell voices apart", text: modelText) {
            HStack(spacing: 10) {
                switch model.state {
                case .ready:
                    GSStatus(ok: true, text: "Ready")
                case .preparing:
                    if let progress = model.progress { GSStatus(ok: false, text: "\(Int((progress * 100).rounded()))%") }
                    Button("Cancel") { model.cancel() }
                        .buttonStyle(GSButtonStyle())
                        .accessibilityLabel("Cancel the speaker model download")
                case .failed:
                    GSStatus(ok: false, text: "Failed")
                    Button("Try again") { model.prepare() }
                        .buttonStyle(GSButtonStyle(prominent: true))
                case .idle:
                    Button("Download") { model.prepare() }
                        .buttonStyle(GSButtonStyle(prominent: true))
                        .accessibilityLabel("Download the speaker recognition model")
                }
            }
        }
    }

    private var modelText: String {
        switch model.state {
        case .ready: "On this Mac. Scribe uses it for the next meeting."
        case .preparing: "Downloading about 150 MB. Scribe works without it meanwhile."
        case .failed(let message): "The download failed: \(message)"
        case .idle: "Optional, about 150 MB. Without it Scribe still separates clearly different voices, and is weaker on similar ones."
        }
    }

    @ViewBuilder private var voicesHeader: some View {
        GSRow(symbol: "person.2", title: "Saved voices", text: "Kept only on this Mac, never uploaded.") {
            if confirmingDeleteAll {
                HStack(spacing: 8) {
                    Button("Delete all") { voices.deleteAll(); confirmingDeleteAll = false }
                        .buttonStyle(GSButtonStyle(prominent: true))
                    Button("Keep") { confirmingDeleteAll = false }
                        .buttonStyle(GSButtonStyle())
                }
            } else {
                Button("Delete all") { confirmingDeleteAll = true }
                    .buttonStyle(GSButtonStyle())
                    .disabled(voices.voices.isEmpty)
                    .accessibilityLabel("Delete all saved voices")
            }
        }
    }
}
