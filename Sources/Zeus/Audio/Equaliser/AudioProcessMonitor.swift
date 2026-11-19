import AppKit
import AudioToolbox
import CoreAudio
import Foundation
import ZeusCore

/// Watches the Core Audio process list, each process's output and input, and the default output's rate, layout and
/// liveness, and reads them on request. Listeners are installed only between `start()` and `stop()`; nothing is
/// installed while the equaliser is off.
///
/// Every listener block is made in a `nonisolated static` function and delivered to the main actor through
/// `DispatchQueue.main.async`, so none of them can inherit main-actor isolation and trap on the Core Audio queue.
@MainActor
final class AudioProcessMonitor: EqualiserMonitoring {
    var onEvent: (@MainActor (EqualiserMonitorEvent) -> Void)?

    /// A listener that is installed, with what removing it needs.
    private struct Registration {
        let object: AudioObjectID
        var address: AudioObjectPropertyAddress
        let block: AudioObjectPropertyListenerBlock
    }

    private let queue = DispatchQueue(label: "zeus.equaliser.monitor", qos: .userInitiated)
    private var running = false
    private var systemListeners: [Registration] = []
    private var processListeners: [AudioObjectID: [Registration]] = [:]
    private var deviceListeners: [Registration] = []
    private var watchedDevice = AudioObjectID(kAudioObjectUnknown)

    func start() {
        guard !running else { return }
        running = true
        let notify = Self.deliver { [weak self] event in self?.handle(event) }
        let system = AudioObjectID(kAudioObjectSystemObject)
        systemListeners = [
            Self.add(system, kAudioHardwarePropertyProcessObjectList, queue: queue, event: .processes, notify: notify),
            Self.add(system, kAudioHardwarePropertyDefaultOutputDevice, queue: queue, event: .output, notify: notify),
        ].compactMap { $0 }
        resync()
    }

    func stop() {
        running = false
        for registration in systemListeners { Self.remove(registration, queue: queue) }
        for registrations in processListeners.values { for registration in registrations { Self.remove(registration, queue: queue) } }
        for registration in deviceListeners { Self.remove(registration, queue: queue) }
        systemListeners = []
        processListeners = [:]
        deviceListeners = []
        watchedDevice = AudioObjectID(kAudioObjectUnknown)
    }

    private func handle(_ event: EqualiserMonitorEvent) {
        guard running else { return }
        resync()
        onEvent?(event)
    }

    /// Listeners follow the process list and the default output, which both change under us.
    private func resync() {
        let notify = Self.deliver { [weak self] event in self?.handle(event) }
        let objects = Set(Self.processObjectIDs())
        for object in processListeners.keys where !objects.contains(object) {
            for registration in processListeners[object] ?? [] { Self.remove(registration, queue: queue) }
            processListeners[object] = nil
        }
        for object in objects where processListeners[object] == nil {
            processListeners[object] = [
                Self.add(object, kAudioProcessPropertyIsRunningOutput, queue: queue, event: .processes, notify: notify),
                Self.add(object, kAudioProcessPropertyIsRunningInput, queue: queue, event: .processes, notify: notify),
            ].compactMap { $0 }
        }
        let device = Self.defaultOutputDeviceID()
        guard device != watchedDevice else { return }
        for registration in deviceListeners { Self.remove(registration, queue: queue) }
        deviceListeners = []
        watchedDevice = device
        guard device != AudioObjectID(kAudioObjectUnknown) else { return }
        deviceListeners = [
            Self.add(device, kAudioDevicePropertyNominalSampleRate, queue: queue, event: .format, notify: notify),
            Self.add(device, kAudioDevicePropertyStreamConfiguration, scope: kAudioDevicePropertyScopeOutput,
                     queue: queue, event: .format, notify: notify),
            Self.add(device, kAudioDevicePropertyDeviceIsAlive, queue: queue, event: .deviceGone, notify: notify),
        ].compactMap { $0 }
    }

    // MARK: Listener plumbing (nonisolated)

    /// Wraps a main-actor handler in a block that hops to the main queue. Made here, not in a main-actor method, so
    /// the block it returns carries no isolation.
    nonisolated private static func deliver(
        _ handler: @escaping @MainActor @Sendable (EqualiserMonitorEvent) -> Void
    ) -> @Sendable (EqualiserMonitorEvent) -> Void {
        { event in
            DispatchQueue.main.async { MainActor.assumeIsolated { handler(event) } }
        }
    }

    nonisolated private static func add(
        _ object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        queue: DispatchQueue,
        event: EqualiserMonitorEvent,
        notify: @escaping @Sendable (EqualiserMonitorEvent) -> Void
    ) -> Registration? {
        var address = ScribeCoreAudio.address(selector, scope: scope)
        let block: AudioObjectPropertyListenerBlock = { _, _ in notify(event) }
        guard AudioObjectAddPropertyListenerBlock(object, &address, queue, block) == noErr else { return nil }
        return Registration(object: object, address: address, block: block)
    }

    nonisolated private static func remove(_ registration: Registration, queue: DispatchQueue) {
        var address = registration.address
        AudioObjectRemovePropertyListenerBlock(registration.object, &address, queue, registration.block)
    }

    // MARK: Reading

    func read() -> EqualiserReading {
        let apps = NSWorkspace.shared.runningApplications.compactMap { app -> (String, String)? in
            guard let id = app.bundleIdentifier, !id.isEmpty else { return nil }
            return (id, app.localizedName ?? id)
        }
        var names: [String: String] = [:]
        for (id, name) in apps { names[id] = name }
        return EqualiserReading(
            processes: Self.processFacts(),
            runningAppBundleIDs: apps.map(\.0),
            names: names,
            output: Self.outputFacts())
    }

    func pidIsAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    private static func processObjectIDs() -> [AudioObjectID] {
        readObjectIDs(AudioObjectID(kAudioObjectSystemObject), ScribeCoreAudio.address(kAudioHardwarePropertyProcessObjectList))
    }

    private static func processFacts() -> [AudioProcessFacts] {
        processObjectIDs().compactMap { object -> AudioProcessFacts? in
            guard let pid = ScribeCoreAudio.readUInt32(object, ScribeCoreAudio.address(kAudioProcessPropertyPID))
                .flatMap({ Int32(exactly: $0) }) else { return nil }
            let output = ScribeCoreAudio.readUInt32(object, ScribeCoreAudio.address(kAudioProcessPropertyIsRunningOutput)) == 1
            let input = ScribeCoreAudio.readUInt32(object, ScribeCoreAudio.address(kAudioProcessPropertyIsRunningInput))
                .map { $0 == 1 }
            let bundleID = ScribeCoreAudio.readString(object, ScribeCoreAudio.address(kAudioProcessPropertyBundleID))
            let devices = readObjectIDs(
                object, ScribeCoreAudio.address(kAudioProcessPropertyDevices, scope: kAudioObjectPropertyScopeOutput))
                .compactMap { ScribeCoreAudio.readString($0, ScribeCoreAudio.address(kAudioDevicePropertyDeviceUID)) }
            return AudioProcessFacts(
                objectID: object, pid: pid, bundleID: bundleID, runningOutput: output, runningInput: input,
                devices: devices)
        }
    }

    static func defaultOutputDeviceID() -> AudioObjectID {
        ScribeCoreAudio.readObjectID(
            AudioObjectID(kAudioObjectSystemObject), ScribeCoreAudio.address(kAudioHardwarePropertyDefaultOutputDevice))
            ?? AudioObjectID(kAudioObjectUnknown)
    }

    /// The default output as the engine judges it. Nil when there is none or its uid cannot be read.
    static func outputFacts() -> EqualiserOutputFacts? {
        let device = defaultOutputDeviceID()
        guard device != AudioObjectID(kAudioObjectUnknown),
              let uid = ScribeCoreAudio.readString(device, ScribeCoreAudio.address(kAudioDevicePropertyDeviceUID))
        else { return nil }
        let transport = ScribeCoreAudio.readUInt32(device, ScribeCoreAudio.address(kAudioDevicePropertyTransportType))
        let aggregate = transport == kAudioDeviceTransportTypeAggregate || transport == kAudioDeviceTransportTypeAutoAggregate
        var rate = 0.0
        var rateSize = UInt32(MemoryLayout<Float64>.size)
        var rateAddress = ScribeCoreAudio.address(kAudioDevicePropertyNominalSampleRate)
        AudioObjectGetPropertyData(device, &rateAddress, 0, nil, &rateSize, &rate)

        let channels = outputChannelCount(device)
        var format = EqualiserStreamFormat(
            isLinearPCM: false, isFloat: false, bitsPerChannel: 0, sampleRate: rate, channelCount: channels)
        if let stream = readObjectIDs(
            device, ScribeCoreAudio.address(kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput)).first {
            var description = AudioStreamBasicDescription()
            var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            var address = ScribeCoreAudio.address(kAudioStreamPropertyVirtualFormat)
            if AudioObjectGetPropertyData(stream, &address, 0, nil, &size, &description) == noErr {
                format = EqualiserStreamFormat(
                    isLinearPCM: description.mFormatID == kAudioFormatLinearPCM,
                    isFloat: description.mFormatFlags & kAudioFormatFlagIsFloat != 0,
                    bitsPerChannel: Int(description.mBitsPerChannel),
                    sampleRate: rate > 0 ? rate : description.mSampleRate,
                    channelCount: channels)
            }
        }

        var pair = (left: 0, right: 1)
        var stereo = [UInt32](repeating: 0, count: 2)
        var stereoSize = UInt32(MemoryLayout<UInt32>.size * 2)
        var stereoAddress = ScribeCoreAudio.address(
            kAudioDevicePropertyPreferredChannelsForStereo, scope: kAudioDevicePropertyScopeOutput)
        if AudioObjectGetPropertyData(device, &stereoAddress, 0, nil, &stereoSize, &stereo) == noErr,
           stereo[0] >= 1, stereo[1] >= 1 {
            pair = (Int(stereo[0]) - 1, Int(stereo[1]) - 1)
        }
        return EqualiserOutputFacts(
            uid: uid, format: format, isAggregate: aggregate, stereoLeft: pair.left, stereoRight: pair.right)
    }

    static func outputChannelCount(_ device: AudioObjectID) -> Int {
        var address = ScribeCoreAudio.address(kAudioDevicePropertyStreamConfiguration, scope: kAudioDevicePropertyScopeOutput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, raw) == noErr else { return 0 }
        return UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
            .reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    static func readObjectIDs(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> [AudioObjectID] {
        var address = address
        guard AudioObjectHasProperty(object, &address) else { return [] }
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var list = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &list) == noErr else { return [] }
        return list
    }
}
