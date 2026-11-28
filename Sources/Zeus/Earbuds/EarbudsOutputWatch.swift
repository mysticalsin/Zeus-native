import CoreAudio
import Foundation
import ZeusCore

/// Notices when the Mac's default output becomes a Bluetooth device, or leaves one.
/// The first look is remembered and not announced. A later change shows the earbud notch.
/// This does not read a battery and does not ask for Bluetooth permission.
@MainActor
final class EarbudsOutputWatch {
    var present: (EarbudsCueFacts, String, Bool) -> Void = { _, _, _ in }

    private var primed = false
    private var last = Snap(id: 0, name: "Earbuds", bluetooth: false)

    /// The output Zeus would treat as earbuds right now. `seen` is false when the device cannot be read.
    /// This does not read a battery.
    static func currentLink() -> CurrentLink {
        let snap = read()
        return CurrentLink(seen: snap.id != 0, connected: snap.bluetooth, name: snap.name)
    }

    struct CurrentLink: Equatable {
        var seen: Bool
        var connected: Bool
        var name: String
    }

    func poll() {
        let snap = Self.read()
        let previous = last
        last = snap
        guard primed else {
            primed = true
            return
        }
        if snap.bluetooth, snap.id != previous.id {
            present(EarbudsCueFacts(name: snap.name, connected: true), snap.token, true)
        } else if previous.bluetooth, !snap.bluetooth {
            present(EarbudsCueFacts(name: previous.name, connected: false), previous.token, true)
        }
    }

    private struct Snap {
        var id: AudioDeviceID
        var name: String
        var bluetooth: Bool
        var token: String { id == 0 ? "" : "output-\(id)" }
    }

    private static func read() -> Snap {
        let id = defaultOutput()
        let name = deviceName(id) ?? "Earbuds"
        return Snap(id: id, name: name, bluetooth: id != 0 && isBluetooth(id))
    }

    private static func defaultOutput() -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr else { return 0 }
        return id
    }

    private static func isBluetooth(_ id: AudioDeviceID) -> Bool {
        let transport = integer(id, kAudioDevicePropertyTransportType)
        return transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    private static func deviceName(_ id: AudioDeviceID) -> String? {
        guard id != 0 else { return nil }
        var address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        let name = value.takeRetainedValue() as String
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func integer(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> UInt32 {
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return 0 }
        return value
    }
}
