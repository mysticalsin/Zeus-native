import CoreAudio
import Foundation
import ZeusCore

/// Applies `DuckLease` to the default output while Zeus listens or speaks (O21).
/// The ducked device follows the default output. A holder that ends after a newer one began
/// does not restore the volume.
@MainActor
enum SystemAudioDucker {
    private static var lease = DuckLease()
    private static var watcher: AudioObjectPropertyListenerBlock?

    static func begin() -> Int {
        watchDefaultOutput()
        let began = lease.begin(currentDevice())
        apply(began.commands)
        return began.token
    }

    static func end(_ token: Int) {
        apply(lease.end(token: token))
    }

    static func endAll() {
        apply(lease.endAll())
    }

    /// The output Zeus lowered, when a duck is held. Tests read this.
    static var holding: Bool { lease.isHolding }

    private static func currentDevice() -> DuckDevice {
        guard let device = SystemVolume.defaultOutput(),
              let volume = SystemVolume.volume(device) else {
            return DuckDevice(id: "none", volume: 0, muted: true)
        }
        return DuckDevice(id: String(device), volume: volume, muted: isMuted(device))
    }

    private static func apply(_ commands: [DuckVolumeCommand]) {
        for command in commands {
            guard let raw = UInt32(command.device) else { continue }
            _ = SystemVolume.setVolume(command.volume, AudioObjectID(raw))
        }
    }

    private static func watchDefaultOutput() {
        guard watcher == nil else { return }
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            Task { @MainActor in
                apply(lease.follow(currentDevice()))
            }
        }
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
        if status == noErr { watcher = block }
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
