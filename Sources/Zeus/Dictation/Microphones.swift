import AVFoundation
import CoreAudio
import Observation
import ZeusCore

/// Audio inputs from Core Audio, and how to point an audio engine at one.
enum Microphones {
    /// The list every main-thread caller reads: Core Audio is asked off main and again only after a device change.
    static let cache: MicrophoneListCache = {
        let cache = MicrophoneListCache(enumerate: { snapshot() })
        cache.startListening()
        cache.warmInBackground()
        return cache
    }()

    /// Enumerates Core Audio now. It can block for tens of milliseconds (more with Bluetooth or aggregate devices),
    /// so main-thread code reads `cache` instead.
    static func all() -> [MicrophoneDevice] { devices(in: deviceIDs()) }

    /// The UID of the Mac's own microphone: an input whose transport is built-in. Nil when there is none.
    static func builtInUID() -> String? { builtInUID(in: deviceIDs()) }

    /// Devices and built-in UID from one device-list read.
    static func snapshot() -> MicrophoneListCache.Snapshot {
        let ids = deviceIDs()
        return .init(devices: devices(in: ids), builtInUID: builtInUID(in: ids))
    }

    private static func devices(in ids: [AudioDeviceID]) -> [MicrophoneDevice] {
        let defaultID = defaultInputID()
        return ids.compactMap { id -> MicrophoneDevice? in
            guard inputChannels(id) > 0, let uid = string(id, kAudioDevicePropertyDeviceUID),
                  let name = string(id, kAudioObjectPropertyName) else { return nil }
            return MicrophoneDevice(uid: uid, name: name, isDefault: id == defaultID)
        }
    }

    private static func builtInUID(in ids: [AudioDeviceID]) -> String? {
        ids.first { id in
            inputChannels(id) > 0 && integer(id, kAudioDevicePropertyTransportType) == kAudioDeviceTransportTypeBuiltIn
        }.flatMap { string($0, kAudioDevicePropertyDeviceUID) }
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
        // The aggregates Zeus builds for shaping and listening are never a microphone to choose.
        return ids.filter { id in
            !ZeusAudioDevices.isOwnAggregate(
                uid: string(id, kAudioDevicePropertyDeviceUID) ?? "", name: string(id, kAudioObjectPropertyName) ?? "")
        }
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

    private static func integer(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func string(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}

/// The audio inputs and the built-in one, cached, stale-while-revalidate. A read returns the last snapshot at once; a
/// Core Audio device-list or default-input change marks it dirty and the next read (or the listener) starts one
/// background refresh. Only a read before any snapshot exists enumerates itself, once, so it is never wrong.
final class MicrophoneListCache: @unchecked Sendable {
    struct Snapshot: Equatable, Sendable {
        var devices: [MicrophoneDevice]
        var builtInUID: String?
    }

    private let enumerate: @Sendable () -> Snapshot
    private let lock = NSLock()
    private var cached: Snapshot?
    private var dirty = false
    /// Bumped by every invalidation, so an enumeration that began before a change never counts as fresh.
    private var generation = 0
    /// True from the moment a refresh is scheduled until it stores a fresh snapshot: at most one runs at a time.
    private var refreshing = false
    private var onChange: (@Sendable (Snapshot) -> Void)?
    private let queue = DispatchQueue(label: "zeus.microphone-list", qos: .utility)
    private var listenerBlocks: [AudioObjectPropertyListenerBlock] = []

    init(enumerate: @escaping @Sendable () -> Snapshot) { self.enumerate = enumerate }

    /// The cached snapshot, or nil before the first enumeration. Never enumerates.
    func peek() -> Snapshot? { lock.withLock { cached } }
    var isRefreshing: Bool { lock.withLock { refreshing } }

    /// Called off the main thread with each fresh snapshot that differs from the one before it.
    func setOnChange(_ handler: (@Sendable (Snapshot) -> Void)?) { lock.withLock { onChange = handler } }

    func devices() -> [MicrophoneDevice] { snapshot().devices }
    func builtInUID() -> String? { snapshot().builtInUID }

    func invalidate() {
        lock.withLock { dirty = true; generation += 1 }
    }

    /// Starts a background refresh unless one is already running or the snapshot is current and present.
    func warmInBackground() {
        lock.withLock { scheduleLocked(force: cached == nil || dirty) }
    }

    private func snapshot() -> Snapshot {
        let (hit, started) = lock.withLock { () -> (Snapshot?, Int) in
            if cached != nil, dirty { scheduleLocked(force: true) }
            return (cached, generation)
        }
        if let hit { return hit }
        let fresh = enumerate()
        let changed = lock.withLock { () -> Bool in
            guard cached == nil, generation == started else { return false }
            cached = fresh
            return true
        }
        if changed { notify(fresh) }
        return fresh
    }

    private func scheduleLocked(force: Bool) {
        guard force, !refreshing else { return }
        refreshing = true
        queue.async { [self] in refreshLoop() }
    }

    /// Enumerates until one result is stored under an unchanged generation; an invalidation mid-flight costs one more pass.
    private func refreshLoop() {
        while true {
            let started = lock.withLock { generation }
            let fresh = enumerate()
            let (stored, previous, handler) = lock.withLock { () -> (Bool, Snapshot?, (@Sendable (Snapshot) -> Void)?) in
                guard generation == started else { return (false, nil, nil) }
                let previous = cached
                cached = fresh
                dirty = false
                refreshing = false
                return (true, previous, onChange)
            }
            if stored {
                if previous != fresh { handler?(fresh) }
                return
            }
        }
    }

    private func notify(_ snapshot: Snapshot) {
        lock.withLock { onChange }?(snapshot)
    }

    /// Watches the system device list and default input for the life of the app. Each selector registers on its own.
    func startListening() {
        lock.withLock {
            guard listenerBlocks.isEmpty else { return }
            for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice] {
                let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                    self?.invalidate()
                    self?.warmInBackground()
                }
                var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                         mElement: kAudioObjectPropertyElementMain)
                let status = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, block)
                if status == noErr {
                    listenerBlocks.append(block)
                } else {
                    VoiceLog.log("mic", "microphone list watch not registered for selector \(selector) (OSStatus \(status))")
                }
            }
        }
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

/// What the Explanation microphone picker reads, so a SwiftUI body never enumerates and still updates on a device change.
@MainActor
@Observable
final class MicrophoneListModel {
    static let shared = MicrophoneListModel(cache: Microphones.cache)
    private(set) var devices: [MicrophoneDevice]

    init(cache: MicrophoneListCache) {
        devices = cache.peek()?.devices ?? []
        cache.setOnChange { [weak self] snapshot in
            Task { @MainActor in self?.devices = snapshot.devices }
        }
        // A snapshot that landed between the peek and the handler would otherwise be missed.
        if let landed = cache.peek()?.devices, landed != devices { devices = landed }
    }
}
