import AppKit
import CoreAudio
import ZeusCore

/// The Mac's audio outputs, and a way to make one the system output.
enum OutputDevices {
    struct Device: Equatable {
        var id: AudioDeviceID
        var name: String
        var isDefault: Bool
        /// `kAudioDevicePropertyTransportType`, or 0 when the device does not report one.
        var transport: UInt32 = 0
    }

    static func all() -> [Device] {
        let current = defaultOutput()
        return ids().compactMap { id -> Device? in
            guard channels(id) > 0, let name = name(id) else { return nil }
            return Device(id: id, name: name, isDefault: id == current, transport: transport(id))
        }
    }

    static func transport(_ id: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return 0 }
        return value
    }

    @discardableResult
    static func setDefault(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device = id
        return AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                                          UInt32(MemoryLayout<AudioDeviceID>.size), &device) == noErr
    }

    private static func defaultOutput() -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return id
    }

    private static func ids() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var list = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &list) == noErr else { return [] }
        // The aggregates Zeus builds for shaping and listening are never an output to choose.
        return list.filter { id in
            !ZeusAudioDevices.isOwnAggregate(uid: string(id, kAudioDevicePropertyDeviceUID) ?? "", name: name(id) ?? "")
        }
    }

    private static func string(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private static func channels(_ id: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                                 mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else { return 0 }
        return UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self)).reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func name(_ id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}

struct OutputMenuRow: Equatable {
    var id: AudioDeviceID
    var name: String
    var isDefault: Bool
    var symbol: String
    /// A discovered receiver name is shown and is not a local output that can be selected.
    var selectable: Bool = true
}

enum OutputDeviceMenuRows {
    static func make(_ devices: [OutputDevices.Device]) -> [OutputMenuRow] {
        devices.map { device in
            let kind = OutputDeviceIcon.kind(transport: device.transport)
            return OutputMenuRow(id: device.id, name: device.name, isDefault: device.isDefault,
                                 symbol: OutputDeviceIcon.symbol(for: kind))
        }
    }

    static func receivers(_ names: [String]) -> [OutputMenuRow] {
        names.map { name in
            OutputMenuRow(id: 0, name: name, isDefault: false,
                          symbol: OutputDeviceIcon.symbol(for: .receiver), selectable: false)
        }
    }
}

/// Menu target for the output list.
@MainActor
final class OutputDeviceTarget: NSObject {
    static let shared = OutputDeviceTarget()

    @objc func choose(_ item: NSMenuItem) {
        guard let id = item.representedObject as? AudioDeviceID else { return }
        OutputDevices.setDefault(id)
    }
}
