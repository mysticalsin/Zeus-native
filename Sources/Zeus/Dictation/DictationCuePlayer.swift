import AVFoundation
import Foundation
import ZeusCore

/// Plays the start and stop sound of a dictation: Zeus's own synthesized tones (ZeusCore.DictationCueSynth)
/// or the bundled Soft click, at the volume chosen in Settings > Dictation.
@MainActor
enum DictationCuePlayer {
    /// One prepared player per sound, so a cue starts without decoding anything.
    private static var prepared: [String: AVAudioPlayer] = [:]

    /// Plays one cue. `force` is for the Settings preview: it ignores the sound switches.
    static func play(_ phase: DictationCuePhase, force: Bool = false) {
        if !force {
            guard ExtraPreferences.shared.soundsOn, !MeetingState.active else { return }
        }
        let settings = DictationSettings.shared
        let style = settings.cueStyle
        let level = Float(DictationCueSynth.clampedVolume(settings.cueVolume)) / 100
        switch style {
        case .none:
            return
        case .softClick:
            let player = ZeusSound.play(slot: phase == .start ? .dictationBegin : .dictationEnd, style: nil)
            player?.volume = level
        case .glass, .pop, .airy:
            guard let player = synthesizedPlayer(style, phase) else { return }
            player.volume = level
            player.currentTime = 0
            player.play()
        }
    }

    /// Start sound, then the stop sound half a second later.
    static func preview() {
        play(.start, force: true)
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            play(.stop, force: true)
        }
    }

    private static func synthesizedPlayer(_ style: DictationCueStyle, _ phase: DictationCuePhase) -> AVAudioPlayer? {
        let key = "\(style.rawValue)-\(phase)"
        if let existing = prepared[key] { return existing }
        guard let wav = DictationCueSynth.wav(style, phase), let player = try? AVAudioPlayer(data: wav) else { return nil }
        player.prepareToPlay()
        prepared[key] = player
        return player
    }
}
