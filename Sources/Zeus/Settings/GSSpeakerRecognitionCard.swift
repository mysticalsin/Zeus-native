import ApplicationServices
import SwiftUI
import ZeusCore

/// Settings: Speaker recognition for Scribe. One optional model (about 150 MB, on this Mac) that tells similar
/// voices apart, and the voices the owner chose to remember. The model downloads only when Download is clicked.
@MainActor
struct SpeakerRecognitionCard: View {
    private var model: SpeakerModelController { .shared }
    private var live: StreamingDiarizerModelController { .shared }
    private var voices: SavedVoicesModel { .shared }
    @State private var confirmingDeleteAll = false

    var body: some View {
        GSCard("Speaker recognition") {
            modelRow
            GSDivider()
            liveRow
            GSDivider()
            callWindowRow
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
            live.refresh()
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

    @ViewBuilder private var liveRow: some View {
        GSRow(symbol: "waveform.path.ecg", title: "Follow speakers live", text: liveText) {
            HStack(spacing: 10) {
                switch live.state {
                case .ready:
                    GSStatus(ok: true, text: "Ready")
                case .preparing:
                    if let progress = live.progress { GSStatus(ok: false, text: "\(Int((progress * 100).rounded()))%") }
                    Button("Cancel") { live.cancel() }
                        .buttonStyle(GSButtonStyle())
                        .accessibilityLabel("Cancel the live speaker model download")
                case .failed:
                    GSStatus(ok: false, text: "Failed")
                    Button("Try again") { live.prepare() }
                        .buttonStyle(GSButtonStyle(prominent: true))
                case .idle:
                    Button("Download") { live.prepare() }
                        .buttonStyle(GSButtonStyle(prominent: true))
                        .accessibilityLabel("Download the live speaker model")
                }
            }
        }
    }

    private var liveText: String {
        switch live.state {
        case .ready: "On this Mac. Scribe tells call voices apart as they speak and checks again when the meeting ends."
        case .preparing: "Downloading. Scribe works without it meanwhile."
        case .failed(let message): "The download failed: \(message)"
        case .idle: "Optional extra download. Without it Scribe uses the voice model above, and tells voices apart a turn at a time."
        }
    }

    /// Names from the call window need Accessibility. Zeus only reports whether it is already on: it never asks.
    private var callWindowRow: some View {
        GSRow(
            symbol: "person.crop.rectangle",
            title: "Names from the call window",
            text: AXIsProcessTrusted()
                ? "On. Scribe reads who is speaking in Zoom, Teams, Meet in a browser and Slack huddles while it records."
                : "Off. Turn on Zeus in System Settings > Privacy & Security > Accessibility and Scribe will name voices from the call window. Zeus never asks for it by itself."
        ) {
            GSStatus(ok: AXIsProcessTrusted(), text: AXIsProcessTrusted() ? "On" : "Off")
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
