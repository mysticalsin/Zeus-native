import AVFoundation
import Foundation
import ZeusCore

/// Plays the start, stop and cancel sounds of a dictation at the volume chosen in Settings > Dictation:
/// the bundled Crystal chimes (scripts/gen-dictation-sounds.py), the bundled Soft click, or Zeus's
/// own synthesized tones (ZeusCore.DictationCueSynth). Which one is `DictationCueSource.resolve`.
@MainActor
enum DictationCuePlayer {
    /// One prepared player per sound, so a cue starts without opening or decoding anything.
    private static var prepared: [String: AVAudioPlayer] = [:]

    /// Plays one cue. `force` is for the Settings preview: it ignores the sound switches.
    static func play(_ phase: DictationCuePhase, force: Bool = false) {
        let settings = DictationSettings.shared
        let style = settings.cueStyle
        if !force {
            guard ExtraPreferences.shared.soundsOn else {
                FlightRecorder.shared.record("sound", "dictation \(phase) muted", "Sound feedback is off")
                return
            }
            guard !MeetingState.active else {
                FlightRecorder.shared.record("sound", "dictation \(phase) muted", "Meeting mode")
                return
            }
        }
        guard let player = player(DictationCueSource.resolve(style, phase)) else { return }
        FlightRecorder.shared.record("sound", "dictation \(phase)", style.rawValue)
        player.volume = Float(DictationCueSynth.clampedVolume(settings.cueVolume)) / 100
        player.currentTime = 0
        player.play()
    }

    /// Loads the chosen style's three cues ahead of the first key press.
    static func prepare() {
        let style = DictationSettings.shared.cueStyle
        for phase in DictationCuePhase.allCases { _ = player(DictationCueSource.resolve(style, phase)) }
    }

    /// Start sound, then the stop sound half a second later.
    static func preview() {
        play(.start, force: true)
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            play(.stop, force: true)
        }
    }

    private static func player(_ source: DictationCueSource) -> AVAudioPlayer? {
        let key: String
        let make: () -> AVAudioPlayer?
        switch source {
        case .silent:
            return nil
        case .synthesized(let style, let phase):
            key = "synth-\(style.rawValue)-\(phase)"
            make = { DictationCueSynth.wav(style, phase).flatMap { try? AVAudioPlayer(data: $0) } }
        case .bundled(let slot, let style):
            key = "file-\(slot.rawValue)-\(style)"
            make = { ZeusSound.url(slot: slot, style: style).flatMap { try? AVAudioPlayer(contentsOf: $0) } }
        }
        if let existing = prepared[key] { return existing }
        guard let player = make() else {
            FlightRecorder.shared.record("sound", "dictation cue missing", key)
            return nil
        }
        player.prepareToPlay()
        prepared[key] = player
        return player
    }
}
