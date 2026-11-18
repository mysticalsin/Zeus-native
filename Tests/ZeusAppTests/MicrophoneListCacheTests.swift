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

    @Test func aDeviceChangeInvalidatesSoTheNextReadEnumeratesAgain() {
        let counter = Counter()
        let cache = Self.cache(counter)
        _ = cache.devices()
        _ = cache.devices()
        #expect(counter.enumerations == 1)
        cache.invalidate()
        _ = cache.devices()
        #expect(counter.enumerations == 2)
        _ = cache.devices()
        #expect(counter.enumerations == 2, "the fresh list is cached again")
    }

    @Test func theFirstReadBeforeWarmUpIsStillCorrect() {
        let counter = Counter()
        let cache = Self.cache(counter)
        #expect(cache.devices() == [Self.usb, Self.builtIn, Self.headset])
        #expect(cache.builtInUID() == "built-in")
        #expect(counter.enumerations == 1)
    }

    @Test @MainActor func aMainThreadReadNeverEnumeratesOnceWarm() async {
        let counter = Counter()
        let cache = Self.cache(counter)
        await Task.detached { _ = cache.devices() }.value
        #expect(counter.enumerations == 1)
        for _ in 0..<20 { _ = cache.devices(); _ = cache.builtInUID() }
        #expect(counter.mainEnumerations == 0, "warm-up ran off main and main only read the cache")
        #expect(counter.enumerations == 1)
    }

    @Test @MainActor func theChosenMicrophoneIsTheSameThroughTheCacheAsFromALiveList() {
        let suite = NSTemporaryDirectory() + "zeus.miccache.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let counter = Counter()
        let cache = Self.cache(counter)
        let speech = SpeechInput()
        func chosen(_ choice: TalkMicrophoneChoice) -> String? {
            defaults.set(choice.stored, forKey: TalkMicrophoneChoice.defaultsKey)
            VoiceTurnController.applyChosenMicrophone(to: speech, defaults: defaults,
                                                      devices: { cache.devices() }, builtInUID: { cache.builtInUID() })
            return speech.deviceUID
        }
        #expect(chosen(.automatic) == nil)
        #expect(chosen(.device("usb-1")) == "usb-1", "a saved input that is present")
        #expect(chosen(.device("gone-9")) == nil, "a saved input that is gone falls back to Automatic")
        #expect(chosen(.builtIn) == "built-in")
        #expect(counter.enumerations == 1, "four presses, one enumeration")
    }

    @Test func aCacheWithTheSavedInputRemovedStopsChoosingItAfterAChange() {
        let counter = Counter()
        final class Box: @unchecked Sendable {
            let lock = NSLock()
            private var value = [MicrophoneListCacheTests.usb, MicrophoneListCacheTests.builtIn]
            var devices: [MicrophoneDevice] { get { lock.withLock { value } } set { lock.withLock { value = newValue } } }
        }
        let box = Box()
        let cache = MicrophoneListCache(enumerate: {
            counter.tick()
            return .init(devices: box.devices, builtInUID: Self.builtIn.uid)
        })
        #expect(TalkMicrophoneChoice.device("usb-1").resolvedUID(devices: cache.devices(), builtInUID: cache.builtInUID()) == "usb-1")
        box.devices = [Self.builtIn]
        cache.invalidate()
        #expect(TalkMicrophoneChoice.device("usb-1").resolvedUID(devices: cache.devices(), builtInUID: cache.builtInUID()) == nil)
    }
}
