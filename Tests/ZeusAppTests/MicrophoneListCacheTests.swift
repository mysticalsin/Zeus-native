import AVFoundation
import Foundation
import Testing
import ZeusCore
@testable import Zeus

/// The microphone list is read from a cache, so a talk key press and a SwiftUI render never ask
/// Core Audio (which can stall for tens of milliseconds, longer with Bluetooth) on the main thread.
@Suite("Microphone list cache", .serialized)
struct MicrophoneListCacheTests {
    private static let usb = MicrophoneDevice(uid: "usb-1", name: "USB Mic")
    private static let builtIn = MicrophoneDevice(uid: "built-in", name: "MacBook Microphone", isDefault: true)
    private static let headset = MicrophoneDevice(uid: "bt-1", name: "AirPods")

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        private var onMain = 0
        var enumerations: Int { lock.withLock { count } }
        var mainEnumerations: Int { lock.withLock { onMain } }
        func tick() { lock.withLock { count += 1; if Thread.isMainThread { onMain += 1 } } }
    }

    /// Lets a test hold one enumeration open to race an invalidation against it.
    private final class Gate: @unchecked Sendable {
        private let lock = NSLock()
        private var armed = false
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        func arm() { lock.withLock { armed = true } }
        func passIfArmed() {
            let hold = lock.withLock { () -> Bool in defer { armed = false }; return armed }
            if hold { entered.signal(); release.wait() }
        }
    }

    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var value: [MicrophoneDevice]
        init(_ value: [MicrophoneDevice]) { self.value = value }
        var devices: [MicrophoneDevice] { get { lock.withLock { value } } set { lock.withLock { value = newValue } } }
    }

    private static func gated(_ counter: Counter, _ gate: Gate, _ box: Box) -> MicrophoneListCache {
        MicrophoneListCache(enumerate: {
            counter.tick()
            let list = box.devices   // what the enumeration saw when it began
            gate.passIfArmed()
            return .init(devices: list, builtInUID: builtIn.uid)
        })
    }

    private static func settle(_ cache: MicrophoneListCache) {
        let deadline = Date().addingTimeInterval(5)
        while cache.isRefreshing, Date() < deadline { Thread.sleep(forTimeInterval: 0.005) }
    }

    private static func warm(_ cache: MicrophoneListCache) {
        cache.warmInBackground()
        // The refresh is scheduled synchronously, so it is either running or already stored.
        settle(cache)
    }

    private static func cache(_ counter: Counter, devices: [MicrophoneDevice] = [usb, builtIn, headset]) -> MicrophoneListCache {
        MicrophoneListCache(enumerate: {
            counter.tick()
            return .init(devices: devices, builtInUID: builtIn.uid)
        })
    }

    @Test func manyReadsAfterWarmUpEnumerateOnce() {
        let counter = Counter()
        let cache = Self.cache(counter)
        for _ in 0..<50 { #expect(cache.devices().count == 3); #expect(cache.builtInUID() == "built-in") }
        #expect(counter.enumerations == 1)
    }

    @Test func theFirstReadBeforeWarmUpIsStillCorrect() {
        let counter = Counter()
        let cache = Self.cache(counter)
        #expect(cache.devices() == [Self.usb, Self.builtIn, Self.headset])
        #expect(cache.builtInUID() == "built-in")
        #expect(counter.enumerations == 1)
    }

    @Test @MainActor func readsAfterAnInvalidationReturnThePreviousSnapshotWithoutEnumeratingOnMain() {
        let counter = Counter()
        let gate = Gate()
        let box = Box([Self.usb, Self.builtIn])
        let cache = Self.gated(counter, gate, box)
        Self.warm(cache)
        #expect(counter.enumerations == 1)
        box.devices = [Self.builtIn]
        // Hold the refresh inside its enumeration. A free refresh can store the new list
        // before the next read, which is the feature-map race, not a stale snapshot.
        gate.arm()
        cache.invalidate()
        #expect(cache.devices() == [Self.usb, Self.builtIn], "stale while revalidating")
        gate.entered.wait()
        for _ in 0..<10 { #expect(cache.devices() == [Self.usb, Self.builtIn], "stale while revalidating") }
        #expect(counter.mainEnumerations == 0, "no enumeration on the main thread after a device event")
        gate.release.signal()
        Self.settle(cache)
        #expect(cache.devices() == [Self.builtIn], "the background refresh landed")
        #expect(counter.enumerations == 2)
        #expect(counter.mainEnumerations == 0)
    }

    @Test func anEnumerationThatBeganBeforeAnInvalidationIsNeverStoredAsFresh() {
        let counter = Counter()
        let gate = Gate()
        let box = Box([Self.usb])
        let cache = Self.gated(counter, gate, box)
        gate.arm()
        cache.warmInBackground()
        gate.entered.wait()                       // the first enumeration saw [usb] and is held open
        box.devices = [Self.builtIn]
        cache.invalidate()                        // a device event arrives mid-flight
        gate.release.signal()
        Self.settle(cache)
        #expect(cache.devices() == [Self.builtIn], "the held-open result [usb] was not kept")
        #expect(counter.enumerations == 2, "a refresh followed the invalidation")
    }

    @Test func manyInvalidationsDuringOneRefreshCostExactlyOneMoreEnumeration() {
        let counter = Counter()
        let gate = Gate()
        let box = Box([Self.usb])
        let cache = Self.gated(counter, gate, box)
        Self.warm(cache)
        #expect(counter.enumerations == 1)
        gate.arm()
        cache.invalidate()
        DispatchQueue.global().async { _ = cache.devices() }   // starts the refresh, held open
        gate.entered.wait()
        box.devices = [Self.builtIn]
        for _ in 0..<10 { cache.invalidate(); cache.warmInBackground() }
        gate.release.signal()
        Self.settle(cache)
        #expect(counter.enumerations == 3, "warm-up, the held refresh, and one more: never one per invalidation")
        #expect(cache.devices() == [Self.builtIn])
    }

    @Test @MainActor func aMainThreadReadNeverEnumeratesOnceWarm() {
        let counter = Counter()
        let cache = Self.cache(counter)
        Self.warm(cache)
        #expect(counter.enumerations == 1)
        for _ in 0..<20 { _ = cache.devices(); _ = cache.builtInUID() }
        #expect(counter.mainEnumerations == 0, "warm-up ran off main and main only read the cache")
        #expect(counter.enumerations == 1)
    }

    @Test @MainActor func theChosenMicrophoneThroughTheCacheMatchesTheSameListRead() {
        let suite = NSTemporaryDirectory() + "zeus.miccache.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let counter = Counter()
        let cache = Self.cache(counter)
        let live = [Self.usb, Self.builtIn, Self.headset]
        let speech = SpeechInput()
        func chosen(_ choice: TalkMicrophoneChoice, cached: Bool) -> String? {
            defaults.set(choice.stored, forKey: TalkMicrophoneChoice.defaultsKey)
            if cached {
                VoiceTurnController.applyChosenMicrophone(to: speech, defaults: defaults,
                                                          devices: { cache.devices() }, builtInUID: { cache.builtInUID() })
            } else {
                VoiceTurnController.applyChosenMicrophone(to: speech, defaults: defaults,
                                                          devices: { live }, builtInUID: { Self.builtIn.uid })
            }
            return speech.deviceUID
        }
        for choice in [TalkMicrophoneChoice.automatic, .device("usb-1"), .device("gone-9"), .builtIn] {
            #expect(chosen(choice, cached: true) == chosen(choice, cached: false), "\(choice)")
        }
        #expect(chosen(.device("usb-1"), cached: true) == "usb-1")
        #expect(chosen(.device("gone-9"), cached: true) == nil, "a saved input that is gone falls back to Automatic")
        #expect(counter.enumerations == 1)
    }

    @Test func aSavedInputThatLeavesStopsBeingChosenOnceTheRefreshLands() {
        let counter = Counter()
        let box = Box([Self.usb, Self.builtIn])
        let cache = Self.gated(counter, Gate(), box)
        func resolved() -> String? {
            TalkMicrophoneChoice.device("usb-1").resolvedUID(devices: cache.devices(), builtInUID: cache.builtInUID())
        }
        #expect(resolved() == "usb-1")
        box.devices = [Self.builtIn]
        cache.invalidate()
        Self.settle(cache)
        _ = cache.devices()          // triggers the refresh
        Self.settle(cache)
        #expect(resolved() == nil)
    }

    @Test func aSavedInputThatIsGoneIsRefusedSoTalkFallsBackToTheSystemInput() {
        // Talk and dictation ignore a false result and keep the engine's default input; Explanation (strict) throws.
        // The lookup is a live one, not the cache, so a stale cache can never make a present device look gone.
        #expect(Microphones.use(uid: "no-such-device-\(UUID().uuidString)", on: AVAudioEngine()) == false)
    }

    @Test @MainActor func theExplanationPickerModelFollowsTheCacheAfterARefresh() async {
        let counter = Counter()
        let box = Box([Self.usb])
        let cache = Self.gated(counter, Gate(), box)
        let model = MicrophoneListModel(cache: cache)
        #expect(model.devices.isEmpty, "construction never enumerates")
        Self.warm(cache)
        for _ in 0..<200 where model.devices.isEmpty { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(model.devices == [Self.usb])
        box.devices = [Self.usb, Self.headset]
        cache.invalidate()
        _ = cache.devices()
        Self.settle(cache)
        for _ in 0..<200 where model.devices.count < 2 { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(model.devices == [Self.usb, Self.headset])
        #expect(counter.mainEnumerations == 0)
    }
}
