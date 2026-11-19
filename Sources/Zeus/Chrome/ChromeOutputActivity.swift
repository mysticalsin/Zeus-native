import CoreAudio
import Foundation

/// Tells the browser media poll when Chrome is making sound, so it does not ask Chrome anything while nothing plays.
/// Two Core Audio flags and no audio at all, no IO proc and no tap:
/// - `kAudioProcessPropertyIsRunningOutput` on every audio process whose bundle ID starts with `com.google.Chrome`,
///   added and removed as the process list changes;
/// - `kAudioDevicePropertyDeviceIsRunningSomewhere` on the default output device, used only when the system gives
///   no process list to read.
///
/// Core Audio calls these blocks on its own queue. This type is deliberately not main-actor isolated (a block written
/// inside a `@MainActor` type inherits that isolation and Swift 6 traps), and every change reaches `onChange` on the
/// main actor through an explicit hop, only when the answer differs from the last one.
final class ChromeOutputActivity: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.zeus.chrome.output-activity")
    private let onChange: @MainActor @Sendable (Bool) -> Void
    private let lock = NSLock()
    private var started = false
    private var last = false
    private var processListListener: AudioObjectPropertyListenerBlock?
    private var processListeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private var defaultListener: AudioObjectPropertyListenerBlock?
    private var device = AudioObjectID(kAudioObjectUnknown)
    private var deviceListener: AudioObjectPropertyListenerBlock?

    init(onChange: @escaping @MainActor @Sendable (Bool) -> Void) {
        self.onChange = onChange
    }

    func start() {
        let answer: Bool = lock.withLock {
            guard !started else { return last }
            started = true
            let listBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.processListChanged() }
            var listAddress = ScribeCoreAudio.address(kAudioHardwarePropertyProcessObjectList)
            if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &listAddress, queue, listBlock) == noErr {
                processListListener = listBlock
            }
            let defaultBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.defaultOutputChanged() }
            var defaultAddress = ScribeCoreAudio.address(kAudioHardwarePropertyDefaultOutputDevice)
            if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultAddress, queue, defaultBlock) == noErr {
                defaultListener = defaultBlock
            }
            syncListeners()
            return computeLocked()
        }
        publish(answer)
    }

    func stop() {
        lock.withLock {
            guard started else { return }
            started = false
            removeProcessListeners()
            detachDevice()
            if let block = processListListener {
                var address = ScribeCoreAudio.address(kAudioHardwarePropertyProcessObjectList)
                AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, block)
            }
            processListListener = nil
            if let block = defaultListener {
                var address = ScribeCoreAudio.address(kAudioHardwarePropertyDefaultOutputDevice)
                AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, block)
            }
            defaultListener = nil
            last = false
        }
    }

    // MARK: Listeners (called with `lock` held)

    private func processObjects() -> [AudioObjectID]? {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = ScribeCoreAudio.address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return nil }
        guard size > 0 else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else { return nil }
        return objects
    }

    private func isChrome(_ object: AudioObjectID) -> Bool {
        guard let bundleID = ScribeCoreAudio.readString(object, ScribeCoreAudio.address(kAudioProcessPropertyBundleID)) else { return false }
        return bundleID.hasPrefix("com.google.Chrome")
    }

    private func syncListeners() {
        guard let objects = processObjects() else {
            // No process list: read the default output device instead.
            removeProcessListeners()
            attachDevice()
            return
        }
        detachDevice()
        let live = Set(objects)
        for (object, block) in processListeners where !live.contains(object) {
            var address = ScribeCoreAudio.address(kAudioProcessPropertyIsRunningOutput)
            AudioObjectRemovePropertyListenerBlock(object, &address, queue, block)
            processListeners[object] = nil
        }
        for object in objects where processListeners[object] == nil && isChrome(object) {
            var address = ScribeCoreAudio.address(kAudioProcessPropertyIsRunningOutput)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.changed() }
            if AudioObjectAddPropertyListenerBlock(object, &address, queue, block) == noErr {
                processListeners[object] = block
            }
        }
    }

    private func removeProcessListeners() {
        for (object, block) in processListeners {
            var address = ScribeCoreAudio.address(kAudioProcessPropertyIsRunningOutput)
            AudioObjectRemovePropertyListenerBlock(object, &address, queue, block)
        }
        processListeners = [:]
    }

    private func attachDevice() {
        guard device == AudioObjectID(kAudioObjectUnknown),
              let id = ScribeCoreAudio.readObjectID(AudioObjectID(kAudioObjectSystemObject), ScribeCoreAudio.address(kAudioHardwarePropertyDefaultOutputDevice)) else { return }
        var address = ScribeCoreAudio.address(kAudioDevicePropertyDeviceIsRunningSomewhere)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.changed() }
        guard AudioObjectAddPropertyListenerBlock(id, &address, queue, block) == noErr else { return }
        device = id
        deviceListener = block
    }

    private func detachDevice() {
        if let block = deviceListener {
            var address = ScribeCoreAudio.address(kAudioDevicePropertyDeviceIsRunningSomewhere)
            AudioObjectRemovePropertyListenerBlock(device, &address, queue, block)
        }
        deviceListener = nil
        device = AudioObjectID(kAudioObjectUnknown)
    }

    /// Whether Chrome is outputting sound now: a Chrome process with its output flag set, or, with no process list,
    /// the default output device running.
    private func computeLocked() -> Bool {
        if processObjects() != nil {
            return processListeners.keys.contains {
                ScribeCoreAudio.readUInt32($0, ScribeCoreAudio.address(kAudioProcessPropertyIsRunningOutput)) ?? 0 != 0
            }
        }
        guard device != AudioObjectID(kAudioObjectUnknown) else { return false }
        return ScribeCoreAudio.readUInt32(device, ScribeCoreAudio.address(kAudioDevicePropertyDeviceIsRunningSomewhere)) ?? 0 != 0
    }

    // MARK: Changes

    private func processListChanged() {
        let answer: Bool? = lock.withLock {
            guard started else { return nil }
            syncListeners()
            return computeLocked()
        }
        if let answer { publish(answer) }
    }

    private func defaultOutputChanged() {
        let answer: Bool? = lock.withLock {
            guard started else { return nil }
            syncListeners()
            return computeLocked()
        }
        if let answer { publish(answer) }
    }

    private func changed() {
        let answer: Bool? = lock.withLock { started ? computeLocked() : nil }
        if let answer { publish(answer) }
    }

    /// Hops to the main actor, and only when the answer differs from the last one sent.
    private func publish(_ running: Bool) {
        let send: Bool = lock.withLock {
            guard started, last != running else { return false }
            last = running
            return true
        }
        guard send else { return }
        let handler = onChange
        DispatchQueue.main.async { MainActor.assumeIsolated { handler(running) } }
    }
}
