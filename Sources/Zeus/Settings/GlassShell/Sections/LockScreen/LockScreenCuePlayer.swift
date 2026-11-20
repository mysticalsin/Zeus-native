import AVFoundation
import Foundation
import ZeusCore

/// Plays a lock or unlock cue from Zeus's own sound files. A missing file plays nothing.
enum LockScreenCuePlayer {
    private static var players: [AVAudioPlayer] = []

    static func exists(_ fileName: String) -> Bool {
        url(fileName) != nil
    }

    static func play(_ cue: LockScreenCue?) {
        guard !ZeusSound.isMutedForTesting, let cue, cue.gain > 0, let url = url(cue.fileName) else { return }
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.volume = Float(min(max(cue.gain, 0), 1))
        players.removeAll { !$0.isPlaying }
        players.append(player)
        player.play()
    }

    private static func url(_ fileName: String) -> URL? {
        guard SoundCatalog.everySpec.contains(where: { $0.fileName == fileName }) else { return nil }
        let bundled = ZeusResources.bundle?.resourceURL?.appendingPathComponent("Sounds/\(fileName)")
        let main = Bundle.main.resourceURL?.appendingPathComponent("Sounds/\(fileName)")
        return [bundled, main].compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}
