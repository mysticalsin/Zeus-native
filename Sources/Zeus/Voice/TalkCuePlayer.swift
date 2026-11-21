import AppKit
import Foundation
import ZeusCore

/// Plays the talk start and end cues. The files named by `TalkCueFiles` are read from disk at
/// runtime and cached on preload. They are not copied into Zeus. A missing or unreadable file
/// falls back to the neutral system sound and is logged once per cue.
@MainActor
protocol TalkCuePlaying: AnyObject {
    func preload()
    func playStart()
    func playEnd()
}

@MainActor
final class InstalledTalkCuePlayer: TalkCuePlaying {
    static let shared = InstalledTalkCuePlayer()

    private var cached: [TalkCueKind: NSSound] = [:]
    private var logged: Set<TalkCueKind> = []

    func preload() {
        cached[.start] = load(.start)
        cached[.end] = load(.end)
    }

    func playStart() { play(.start) }
    func playEnd() { play(.end) }

    private func play(_ kind: TalkCueKind) {
        let sound = cached[kind] ?? load(kind)
        cached[kind] = sound
        sound?.stop()
        sound?.currentTime = 0
        sound?.play()
    }

    private func load(_ kind: TalkCueKind) -> NSSound? {
        let path = TalkCueFiles.path(kind)
        let source = TalkCueFiles.resolve(kind) { FileManager.default.isReadableFile(atPath: $0) }
        if case .file = source, let sound = NSSound(contentsOfFile: path, byReference: true) {
            return sound
        }
        if !logged.contains(kind) {
            logged.insert(kind)
            NSLog("[ZEUS] talk cue %@ unreadable at %@; using %@",
                  kind.rawValue, path, TalkCueFiles.fallbackSystemSound)
        }
        return NSSound(named: NSSound.Name(TalkCueFiles.fallbackSystemSound))
    }
}
