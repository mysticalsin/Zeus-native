import AVFoundation
import CoreAudio
import Observation
import ZeusCore

/// Audio inputs from Core Audio, and how to point an audio engine at one.
enum Microphones {
    static func all() -> [MicrophoneDevice] {
        let defaultID = defaultInputID()
        return deviceIDs().compactMap { id -> MicrophoneDevice? in
            guard inputChannels(id) > 0, let uid = string(id, kAudioDevicePropertyDeviceUID),
                  let name = string(id, kAudioObjectPropertyName) else { return nil }
            return MicrophoneDevice(uid: uid, name: name, isDefault: id == defaultID)
        }
    }

    /// Sets the input device of an engine's input node (nil: the system input). Returns false
    /// when the chosen device is gone.
    @discardableResult
    static func use(uid: String?, on engine: AVAudioEngine) -> Bool {
        let found = uid.map { uid in deviceIDs().first { string($0, kAudioDevicePropertyDeviceUID) == uid } } ?? defaultInputID()
        guard let id = found, id != 0, let unit = engine.inputNode.audioUnit else { return false }
        var device = id
        let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                          &device, UInt32(MemoryLayout<AudioDeviceID>.size))
        return status == noErr
    }

    private static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func deviceIDs() -> [AudioDeviceID] {
        var address = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func defaultInputID() -> AudioDeviceID {
        var address = address(kAudioHardwarePropertyDefaultInputDevice)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return id
    }

    private static func inputChannels(_ id: AudioDeviceID) -> Int {
        var address = address(kAudioDevicePropertyStreamConfiguration, scope: kAudioDevicePropertyScopeInput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func string(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}

/// Settings › Dictation › Test microphone: a few seconds of live level from the chosen input.
@MainActor
@Observable
final class MicrophoneTester {
    static let shared = MicrophoneTester()
    /// Inputs listed in Settings, refreshed when the section appears.
    var devices: [MicrophoneDevice] = []
    /// The whole test as one state (`MicTest`); the values below are read from it.
    private(set) var state = MicTest.State.idle
    @ObservationIgnored private var lastSession: UInt64 = 0
    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var stopTask: Task<Void, Never>?

    var level: Double { state.level }
    var peak: Double { state.peak }
    var running: Bool { state.isRunning }
    var problem: String? { state.problem }
    var verdict: String? { state.verdict }

    func start(uid: String?, seconds: Double = 5) {
        stop()
        lastSession &+= 1
        let session = lastSession
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            send(.failed(session: session, problem: "Allow the microphone for Zeus first."))
            return
        }
        let engine = AVAudioEngine()
        var note: String?
        if uid != nil, !Microphones.use(uid: uid, on: engine) {
            note = "That microphone is not connected. Using the system input."
        }
        let input = engine.inputNode
        // With no input device the format has no sample rate or channels, and installTap would raise.
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            send(.failed(session: session, problem: "No microphone is connected."))
            return
        }
        OffMainAudioCallbacks.installLevelTap(on: input, format: format,
                                              measure: { MicLevel.level(samples: $0) }) { [weak self] value in
            // Only this test's own levels count: one measured in an earlier test is dropped.
            self?.send(.level(session: session, value: value))
        }
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            send(.failed(session: session, problem: error.localizedDescription))
            return
        }
        self.engine = engine
        send(.opened(session: session, note: note))
        stopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            self?.send(.timedOut(session: session))
        }
    }

    func stop() { send(.stopRequested) }

    private func send(_ event: MicTest.Event) {
        let (next, effects) = MicTest.reduce(state, event)
        if next != state { state = next }
        for effect in effects {
            switch effect {
            case .stopCapture, .discardCapture: releaseCapture()
            }
        }
    }

    private func releaseCapture() {
        stopTask?.cancel()
        stopTask = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
    }
}
