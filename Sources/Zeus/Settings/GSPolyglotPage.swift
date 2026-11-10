import AppKit
import SwiftUI
import ZeusCore

/// Settings > Polyglot: live translated captions, native to Zeus.
@MainActor
struct PolyglotSettingsPage: View {
    private var settings: PolyglotSettings { .shared }
    private var polyglot: PolyglotController { .shared }

    var body: some View {
        GSPageHeading(section: .polyglot, subtitle: "Understand any language, live, on this Mac.")
            .padding(.bottom, -GS.cardGap)
        GSCard("Polyglot") {
            GSToggleRow(symbol: "globe", title: "Enable Polyglot",
                        text: "Adds live captions to the notch and the shortcut below. Speech and translation run on this Mac.",
                        isOn: Binding(get: { settings.enabled }, set: { settings.enabled = $0 }))
            GSDivider()
            GSRow(symbol: "waveform.badge.mic", title: "Listen to",
                  text: "Mac audio asks for Screen & System Audio Recording the first time you start it, not before. The microphone asks for Microphone.") {
                GSPopup(selection: Binding(get: { settings.source.title },
                                           set: { value in settings.source = PolyglotSource.allCases.first { $0.title == value } ?? .microphone }),
                        options: PolyglotSource.allCases.map(\.title))
            }
            GSDivider()
            GSRow(symbol: "character.bubble", title: "Translate to",
                  text: "Apple's on-device Translation. A language you have not used yet downloads once, and macOS asks you first.") {
                GSPopup(selection: Binding(get: { PolyglotLanguage.name(for: settings.target) },
                                           set: { value in settings.target = PolyglotLanguage.targets.first { $0.name == value }?.code ?? "en" }),
                        options: PolyglotLanguage.targets.map(\.name))
            }
        }
        GSCard("Captions") {
            GSToggleRow(symbol: "text.quote", title: "Show the original text",
                        text: "Keeps what was said, in its own language, under each translation.",
                        isOn: Binding(get: { settings.showOriginal }, set: { settings.showOriginal = $0 }))
            GSDivider()
            GSRow(symbol: "textformat.size", title: "Caption size") {
                GSPopup(selection: Binding(get: { settings.captionSize.title },
                                           set: { value in settings.captionSize = PolyglotCaptionSize.allCases.first { $0.title == value } ?? .medium }),
                        options: PolyglotCaptionSize.allCases.map(\.title))
            }
            GSDivider()
            GSRow(symbol: "pip.enter", title: "Floating captions",
                  text: "A strip that stays on top on every desktop and is hidden from screen sharing and recordings.") {
                Button(polyglot.isPoppedOut ? "Close" : "Pop out") { polyglot.togglePopOut() }.buttonStyle(GSButtonStyle())
            }
        }
        GSCard("Shortcut") {
            ShortcutRecorderRow(symbol: "keyboard", title: "Start or stop Polyglot",
                                text: "Click, then press any key or chord. It works from any app.",
                                shortcut: settings.hotkey, defaultValue: PolyglotSettings.defaultHotkey, allowsOff: true,
                                otherName: "Talk to Zeus", other: Preferences.shared.pushToTalk) { settings.hotkey = $0 }
            KeyAccessRow()
            GSInfo(text: "You can also say \u{201C}Hey Zeus, translate\u{201D} or \u{201C}start Polyglot\u{201D}.")
        }
        GSCard("Engine") {
            GSRow(symbol: "cpu", title: "Speech to text",
                  text: "Parakeet v3 hears 25 European languages and detects them itself. Without it, Apple's on-device recognizer is used. Download Parakeet in Settings, Dictation.") {
                GSStatus(ok: true, text: polyglot.engineName.isEmpty ? "Chosen at start" : polyglot.engineName)
            }
            if #unavailable(macOS 26.0) {
                GSInfo(text: "Heard lines still show. Translating them on device needs macOS 26 and a language pack.")
            }
            if let app = PolyglotSettings.installedAppURL {
                GSDivider()
                GSRow(symbol: "arrow.up.forward.app", title: "Polyglot.app is installed",
                      text: "Your Python-engine Polyglot, with the call modes and reply helper.") {
                    Button("Open Polyglot.app") { NSWorkspace.shared.open(app) }.buttonStyle(GSButtonStyle())
                }
            }
        }
    }
}
