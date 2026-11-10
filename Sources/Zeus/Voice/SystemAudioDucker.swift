import CoreAudio
import Foundation
import ZeusCore

/// Applies `AudioQuiet` to the default output device while Zeus speaks or listens (O21).
@MainActor
enum SystemAudioDucker {
    private static var quiet: AudioQuiet?

    static func snapshotNow() -> AudioQuiet? {
        guard let device = SystemVolume.defaultOutput(),
              let volume = SystemVolume.volume(device) else { return nil }
        return AudioQuiet(snapshotVolume: volume, snapshotMuted: isMuted(device))
    }

    static func begin() {
        guard quiet == nil, var snap = snapshotNow() else { return }
        guard let device = SystemVolume.defaultOutput(),
              let target = snap.beginDuck() else { return }
        _ = SystemVolume.setVolume(target, device)
        quiet = snap
    }

    static func end() {
        guard var snap = quiet, let device = SystemVolume.defaultOutput() else { quiet = nil; return }
        if let restore = snap.restoreVolume(currentVolume: SystemVolume.volume(device) ?? snap.snapshotVolume,
                                            currentMuted: isMuted(device)) {
            _ = SystemVolume.setVolume(restore, device)
        }
        snap.endDuck()
        quiet = nil
    }

    private static func isMuted(_ device: AudioObjectID) -> Bool {
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted) == noErr else { return false }
        return muted != 0
    }
}
