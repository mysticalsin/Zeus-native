import CoreAudio
import Foundation
import ZeusCore

/// Applies `AudioQuiet` to the default output device while Zeus speaks or listens (O21).
@MainActor
enum SystemAudioDucker {
    private static var quiet: AudioQuiet?
    /// The output device that was lowered. Restored even if the default output changed in between (a headset
    /// plugged in for a call), so no device is left at the ducked volume.
    private static var duckedDevice: AudioObjectID?

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
        duckedDevice = device
    }

    static func end() {
        defer {
            quiet = nil
            duckedDevice = nil
        }
        guard var snap = quiet, let device = duckedDevice else { return }
        // A device that went away has nothing left to restore.
        guard let current = SystemVolume.volume(device) else { return }
        if let restore = snap.restoreVolume(currentVolume: current, currentMuted: isMuted(device)) {
            _ = SystemVolume.setVolume(restore, device)
        }
        snap.endDuck()
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
