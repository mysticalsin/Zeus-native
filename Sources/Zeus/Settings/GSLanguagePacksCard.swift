import SwiftUI
import ZeusCore

/// Settings > Dictation: Language packs. English, French, Spanish and Portuguese install after the app, in the
/// background, from a tap here or the ticks in onboarding. Nothing is bundled and nothing downloads unasked.
@MainActor
struct LanguagePacksCard: View {
    private var packs: LanguagePackController { .shared }

    var body: some View {
        let state = packs.state
        GSCard("Language packs") {
            ForEach(Array(LanguagePackID.allCases.enumerated()), id: \.element) { index, pack in
                if index > 0 { GSDivider() }
                GSRow(symbol: "globe", title: pack.title, text: text(for: state.status(of: pack), pack: pack)) {
                    actions(for: state.status(of: pack), pack: pack)
                }
            }
            GSDivider()
            GSRow(symbol: "arrow.down.circle", title: "All four languages", text: "English, French, Spanish and Portuguese. macOS shows the size.") {
                HStack(spacing: 10) {
                    if state.blockedByLowPower && state.isBusy {
                        Button("Install now") { packs.installNow() }
                            .buttonStyle(GSButtonStyle(prominent: true))
                            .accessibilityLabel("Install language packs now, even in Low Power Mode")
                    }
                    if state.isBusy {
                        Button("Cancel") { packs.cancel() }
                            .buttonStyle(GSButtonStyle())
                            .accessibilityLabel("Cancel the language pack installs")
                    } else {
                        Button("Install all four") { packs.installAll() }
                            .buttonStyle(GSButtonStyle(prominent: true))
                            .disabled(!state.analyzerSupported)
                            .accessibilityLabel("Install all four language packs")
                    }
                }
            }
            GSDivider()
            GSRow(symbol: "keyboard", title: "Languages macOS manages",
                  text: "Apple's older on-device dictation languages are added in System Settings, Keyboard, Dictation. Apps cannot install them.") {
                Button("Open System Settings") { packs.openDictationSystemSettings() }
                    .buttonStyle(GSButtonStyle())
                    .accessibilityLabel("Open the Dictation languages in System Settings")
            }
            GSInfo(text: "Best accuracy for every language at once is the Parakeet model in Speech engine below. It is a separate, optional download.")
        }
    }

    private func text(for status: LanguagePackStatus, pack: LanguagePackID) -> String {
        switch status {
        case .installed: "On this Mac."
        case .installing(let progress): "Installing, \(Int((progress * 100).rounded())) percent."
        case .queued: "Waiting for the pack before it."
        case .deferredForLowPower: "Waiting because Low Power Mode is on."
        case .failed(let reason): "Could not install: \(reason)"
        case .unsupportedOnThisMac: "Apple's language models need macOS 26 or later. This Mac uses macOS dictation languages."
        case .notInstalled: "Not installed. Spoken replies use the macOS voice for \(pack.title)."
        }
    }

    @ViewBuilder private func actions(for status: LanguagePackStatus, pack: LanguagePackID) -> some View {
        switch status {
        case .installed:
            HStack(spacing: 10) {
                GSStatus(ok: true, text: "Installed")
                Button("Remove") { packs.remove(pack) }
                    .buttonStyle(GSButtonStyle())
                    .accessibilityLabel("Remove the \(pack.title) language pack")
            }
        case .installing(let progress):
            GSStatus(ok: false, text: "\(Int((progress * 100).rounded()))%")
        case .queued, .deferredForLowPower:
            GSStatus(ok: false, text: "Queued")
        case .failed:
            Button("Try again") { packs.install(pack) }
                .buttonStyle(GSButtonStyle(prominent: true))
                .accessibilityLabel("Try the \(pack.title) language pack again")
        case .unsupportedOnThisMac:
            GSStatus(ok: false, text: "Not available")
        case .notInstalled:
            Button("Install") { packs.install(pack) }
                .buttonStyle(GSButtonStyle(prominent: true))
                .accessibilityLabel("Install the \(pack.title) language pack")
        }
    }
}
