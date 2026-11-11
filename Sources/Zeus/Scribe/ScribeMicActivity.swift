import CoreAudio
import Foundation

/// Wakes the call watcher the moment a call app starts or stops using the microphone, so a meeting (or its end)
/// is noticed at once instead of at the next five second poll. Two Core Audio flags, no audio:
/// - `kAudioProcessPropertyIsRunningInput` on every audio process that belongs to a known call app (Zoom, Teams,
///   Slack, FaceTime, Webex, browsers for Meet...), added and removed as the process list changes;
/// - `kAudioDevicePropertyDeviceIsRunningSomewhere` on the default input device, as a second wake-up.
/// The poll stays as the backup for anything these miss.
///
/// Core Audio calls these blocks on its own queue. This type is deliberately not main-actor isolated (a block
/// written inside a `@MainActor` type inherits that isolation and Swift 6 traps), and every notification reaches
/// `onChange` on the main actor through an explicit hop.
final class ScribeMicActivityObserver: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.zeus.scribe.mic-activity")
    private let onChange: @MainActor @Sendable () -> Void
    private let lock = NSLock()
    private var started = false
    private var device = AudioObjectID(kAudioObjectUnknown)
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var defaultListener: AudioObjectPropertyListenerBlock?
    private var processListListener: AudioObjectPropertyListenerBlock?
    private var processListeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]

    init(onChange: @escaping @MainActor @Sendable () -> Void) {
        self.onChange = onChange
    }

    func start() {
        lock.withLock {
            guard !started else { return }
            started = true
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.defaultInputChanged() }
            var address = ScribeCoreAudio.address(kAudioHardwarePropertyDefaultInputDevice)
            if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, block) == noErr {
                defaultListener = block
            }
            attachDevice()
            let listBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.processListChanged() }
            var listAddress = ScribeCoreAudio.address(kAudioHardwarePropertyProcessObjectList)
            if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &listAddress, queue, listBlock) == noErr {
                processListListener = listBlock
            }
            syncProcessListeners()
        }
    }

    func stop() {
        lock.withLock {
            guard started else { return }
            started = false
            detachDevice()
            removeAllProcessListeners()
            if let block = processListListener {
                var address = ScribeCoreAudio.address(kAudioHardwarePropertyProcessObjectList)
                AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, block)
            }
            processListListener = nil
            if let block = defaultListener {
                var address = ScribeCoreAudio.address(kAudioHardwarePropertyDefaultInputDevice)
                AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, block)
            }
            defaultListener = nil
        }
    }

    /// Called with `lock` held.
    private func attachDevice() {
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard let id = ScribeCoreAudio.readObjectID(system, ScribeCoreAudio.address(kAudioHardwarePropertyDefaultInputDevice)) else { return }
        var address = ScribeCoreAudio.address(kAudioDevicePropertyDeviceIsRunningSomewhere)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.notify() }
        guard AudioObjectAddPropertyListenerBlock(id, &address, queue, block) == noErr else { return }
        device = id
        deviceListener = block
    }

    /// Called with `lock` held.
    private func detachDevice() {
        if let block = deviceListener {
            var address = ScribeCoreAudio.address(kAudioDevicePropertyDeviceIsRunningSomewhere)
            AudioObjectRemovePropertyListenerBlock(device, &address, queue, block)
        }
        deviceListener = nil
        device = AudioObjectID(kAudioObjectUnknown)
    }

    /// Called with `lock` held: listen to the input flag of each audio process that belongs to a known call app,
    /// and let go of processes that have gone.
    private func syncProcessListeners() {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var listAddress = ScribeCoreAudio.address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        var objects: [AudioObjectID] = []
        if AudioObjectGetPropertyDataSize(system, &listAddress, 0, nil, &size) == noErr, size > 0 {
            objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
            if AudioObjectGetPropertyData(system, &listAddress, 0, nil, &size, &objects) != noErr { objects = [] }
        }
        let live = Set(objects)
        for (object, block) in processListeners where !live.contains(object) {
            var address = ScribeCoreAudio.address(kAudioProcessPropertyIsRunningInput)
            AudioObjectRemovePropertyListenerBlock(object, &address, queue, block)
            processListeners[object] = nil
        }
        for object in objects where processListeners[object] == nil {
            guard let bundleID = ScribeCoreAudio.readString(object, ScribeCoreAudio.address(kAudioProcessPropertyBundleID)),
                  ScribeCallDetection.appBundleID(for: bundleID) != nil else { continue }
            var address = ScribeCoreAudio.address(kAudioProcessPropertyIsRunningInput)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.notify() }
            if AudioObjectAddPropertyListenerBlock(object, &address, queue, block) == noErr {
                processListeners[object] = block
            }
        }
    }

    /// Called with `lock` held.
    private func removeAllProcessListeners() {
        for (object, block) in processListeners {
            var address = ScribeCoreAudio.address(kAudioProcessPropertyIsRunningInput)
            AudioObjectRemovePropertyListenerBlock(object, &address, queue, block)
        }
        processListeners = [:]
    }

    private func processListChanged() {
        lock.withLock {
            guard started else { return }
            syncProcessListeners()
        }
        notify()
    }

    private func defaultInputChanged() {
        lock.withLock {
            guard started else { return }
            detachDevice()
            attachDevice()
        }
        notify()
    }

    private func notify() {
        let handler = onChange
        DispatchQueue.main.async { MainActor.assumeIsolated { handler() } }
    }
}
