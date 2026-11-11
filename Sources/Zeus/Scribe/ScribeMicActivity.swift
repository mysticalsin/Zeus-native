import CoreAudio
import Foundation

/// Wakes the call watcher the moment the default microphone starts or stops running anywhere on the Mac, so a
/// meeting is noticed in about a second instead of at the next five second poll. It reads one Core Audio flag
/// ("this device is running somewhere") and captures no audio. The poll stays as the backup: if another app
/// already holds the microphone, the flag does not change when a call app joins it.
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
        }
    }

    func stop() {
        lock.withLock {
            guard started else { return }
            started = false
            detachDevice()
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
