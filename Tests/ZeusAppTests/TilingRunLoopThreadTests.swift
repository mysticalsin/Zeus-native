import CoreFoundation
import Foundation
import Testing
import ZeusCore
@testable import Zeus

/// The thread that services the tiling key tap. A consuming tap is serviced by the run loop its source is on, and the
/// window server holds every keystroke in every app until that loop answers, so the loop must never be the main
/// one: Accessibility passes run there. These tests use a plain run loop source in place of the system tap.
@Suite("Tiling run loop thread", .serialized) @MainActor
struct TilingRunLoopThreadTests {
    /// Locked list of what happened and on which thread.
    private final class Log: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []
        func add(_ item: String) { lock.lock(); items.append(item); lock.unlock() }
        var all: [String] { lock.lock(); defer { lock.unlock() }; return items }
    }

    /// A custom run loop source that stands in for the tap source: signalled from anywhere, it runs `onFire` on the
    /// thread that services its loop.
    private final class Beacon: @unchecked Sendable {
        private let lock = NSLock()
        private var source: CFRunLoopSource?
        private var loop: CFRunLoop?
        var onFire: @Sendable () -> Void = {}
        let installed = DispatchSemaphore(value: 0)

        func install() {
            var context = CFRunLoopSourceContext(
                version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil,
                equal: nil, hash: nil, schedule: nil, cancel: nil,
                perform: { info in Unmanaged<Beacon>.fromOpaque(info!).takeUnretainedValue().onFire() })
            let made = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &context)
            lock.lock(); source = made; loop = CFRunLoopGetCurrent(); lock.unlock()
            CFRunLoopAddSource(CFRunLoopGetCurrent(), made, .commonModes)
            installed.signal()
        }

        func remove() {
            lock.lock(); let made = source; lock.unlock()
            guard let made else { return }
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), made, .commonModes)
            CFRunLoopSourceInvalidate(made)
        }

        func fire() {
            lock.lock(); let made = source; let current = loop; lock.unlock()
            guard let made, let current else { return }
            CFRunLoopSourceSignal(made)
            CFRunLoopWakeUp(current)
        }
    }

    private func launch(_ beacon: Beacon, log: Log? = nil) -> TilingRunLoopThread {
        TilingRunLoopThread(name: "app.zeus.tiling.test",
                            install: { log?.add("install on \(Thread.isMainThread ? "main" : "tap")"); beacon.install() },
                            teardown: { log?.add("teardown on \(Thread.isMainThread ? "main" : "tap")"); beacon.remove() })
    }

    // MARK: Where it runs

    @Test func theSourceIsInstalledAndRemovedOnTheTapThreadNeverTheMainOne() {
        let beacon = Beacon()
        let log = Log()
        let thread = launch(beacon, log: log)
        #expect(beacon.installed.wait(timeout: .now() + 2) == .success)
        #expect(thread.stop())
        #expect(log.all == ["install on tap", "teardown on tap"], "\(log.all)")
    }

    @Test func aCallbackIsServicedWhileTheMainThreadIsBlocked() {
        let beacon = Beacon()
        let ran = DispatchSemaphore(value: 0)
        let log = Log()
        beacon.onFire = { log.add(Thread.isMainThread ? "main" : "tap"); ran.signal() }
        let thread = launch(beacon)
        defer { thread.stop() }
        #expect(beacon.installed.wait(timeout: .now() + 2) == .success)
        DispatchQueue.global().async { beacon.fire() }
        // This test runs on the main actor, so waiting here blocks the main thread, as a long Accessibility pass does.
        #expect(Thread.isMainThread)
        #expect(ran.wait(timeout: .now() + 2) == .success, "the callback waited for the blocked main thread")
        #expect(log.all == ["tap"])
    }

    // MARK: Stopping

    @Test func stopRemovesTheSourceAndEndsTheThreadBeforeItReturns() {
        let beacon = Beacon()
        let log = Log()
        let thread = launch(beacon, log: log)
        #expect(beacon.installed.wait(timeout: .now() + 2) == .success)
        let started = Date()
        #expect(thread.stop())
        #expect(Date().timeIntervalSince(started) < 1, "stop does not wait for a timeout")
        #expect(log.all.last == "teardown on tap")
        beacon.fire() // a signal after the stop reaches nothing
        #expect(log.all.count == 2)
    }

    @Test func stoppingTwiceIsHarmless() {
        let beacon = Beacon()
        let log = Log()
        let thread = launch(beacon, log: log)
        #expect(beacon.installed.wait(timeout: .now() + 2) == .success)
        #expect(thread.stop())
        #expect(thread.stop(), "the second stop finds the thread already ended")
        #expect(log.all.filter { $0.hasPrefix("teardown") }.count == 1, "removed once")
    }

    @Test func aStopDuringACallbackWaitsForItAndTearsDownAfterwards() {
        let beacon = Beacon()
        let log = Log()
        let started = DispatchSemaphore(value: 0)
        beacon.onFire = { started.signal(); Thread.sleep(forTimeInterval: 0.25); log.add("callback done") }
        let thread = TilingRunLoopThread(name: "app.zeus.tiling.test", install: { beacon.install() },
                                         teardown: { log.add("teardown"); beacon.remove() })
        #expect(beacon.installed.wait(timeout: .now() + 2) == .success)
        beacon.fire()
        #expect(started.wait(timeout: .now() + 2) == .success)
        #expect(thread.stop())
        #expect(log.all == ["callback done", "teardown"], "the port is never invalidated under a callback: \(log.all)")
    }

    @Test func aStopRequestedBeforeTheThreadGotToInstallEndsItWithoutLeavingAnythingBehind() {
        for _ in 0..<200 {
            let beacon = Beacon()
            let log = Log()
            let thread = launch(beacon, log: log)
            #expect(thread.stop())
            let installs = log.all.filter { $0.hasPrefix("install") }.count
            let teardowns = log.all.filter { $0.hasPrefix("teardown") }.count
            #expect(installs == teardowns, "every install is matched by a teardown: \(log.all)")
        }
    }

    // MARK: Many cycles

    private final class Payload: @unchecked Sendable { var value = 0 }

    /// Runs one start and stop and hands back the weak payload the closures held.
    private func oneCycle(counts: Log) -> WeakBox {
        let payload = Payload()
        let box = WeakBox(payload)
        let beacon = Beacon()
        let thread = TilingRunLoopThread(name: "app.zeus.tiling.test",
                                         install: { payload.value += 1; counts.add("install"); beacon.install() },
                                         teardown: { payload.value += 1; counts.add("teardown"); beacon.remove() })
        _ = beacon.installed.wait(timeout: .now() + 2)
        _ = thread.stop()
        return box
    }

    private final class WeakBox { weak var object: AnyObject?; init(_ object: AnyObject) { self.object = object } }

    @Test func switchingOnAndOffManyTimesLeaksNoThreadAndKeepsNothingAlive() {
        let counts = Log()
        var alive = 0
        let started = Date()
        for _ in 0..<300 where oneCycle(counts: counts).object != nil { alive += 1 }
        #expect(alive == 0, "the closures of a stopped thread are released: \(alive) of 300 still held")
        #expect(counts.all.filter { $0 == "install" }.count == 300)
        #expect(counts.all.filter { $0 == "teardown" }.count == 300)
        #expect(Date().timeIntervalSince(started) < 15, "each cycle is quick")
    }
}

/// The real tap object around that thread. A process without Accessibility cannot create the tap, so `start()` says
/// false and the same life rules apply; with it, the tap has an empty keymap and a closed gate and passes every event.
@Suite("Tiling key tap lifecycle", .serialized) @MainActor
struct TilingKeyTapLifecycleTests {
    private final class Seen: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [TileAction] = []
        func add(_ action: TileAction) { lock.lock(); items.append(action); lock.unlock() }
        var all: [TileAction] { lock.lock(); defer { lock.unlock() }; return items }
    }

    /// Blocks the calling thread, which is the main one here. A synchronous helper, because the wait is not available in an async test.
    private func blockMain(until signal: DispatchSemaphore) -> Bool { signal.wait(timeout: .now() + 5) == .success }

    @Test func startingAndStoppingManyTimesLeavesNothingRunning() {
        let tap = TilingKeyTap(sink: { _ in }, onFailure: {})
        for cycle in 0..<40 {
            let started = tap.start()
            #expect(tap.isRunning == started, "cycle \(cycle)")
            #expect(tap.start() == started, "a second start changes nothing")
            tap.stop()
            #expect(!tap.isRunning, "cycle \(cycle)")
        }
        tap.stop()
        #expect(!tap.isRunning)
    }

    @Test func aTapThatIsDroppedWhileRunningEndsItsThreadAndIsFreed() {
        var tap: TilingKeyTap? = TilingKeyTap(sink: { _ in }, onFailure: {})
        weak var observed = tap
        _ = tap?.start()
        tap = nil
        #expect(observed == nil, "nothing keeps a dropped tap alive")
    }

    @Test func aBurstOfFocusRepeatsWhileMainIsBusyRunsOneAction() async throws {
        let seen = Seen()
        let tap = TilingKeyTap(sink: { seen.add($0) }, onFailure: {})
        let sent = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            for _ in 0..<500 { tap.deliver(.focus(.left), joined: nil) }
            sent.signal()
        }
        // The main thread is held here, as a long Accessibility pass holds it: nothing of the burst can run yet.
        #expect(blockMain(until: sent))
        try await Task.sleep(for: .seconds(0.3))
        #expect(seen.all == [.focus(.left)], "one scan for the whole burst, not 500: \(seen.all.count)")
    }

    @Test func repeatsThatArriveDuringARunningScanMergeBehindItAndOnlyTheNewestRuns() async throws {
        let seen = Seen()
        let tap = TilingKeyTap(sink: { action in
            seen.add(action)
            if action == .retile { Thread.sleep(forTimeInterval: 0.4) } // a slow window scan on the main actor
        }, onFailure: {})
        tap.deliver(.retile, joined: nil)
        DispatchQueue.global().async {
            Thread.sleep(forTimeInterval: 0.1)
            for _ in 0..<300 { tap.deliver(.focus(.left), joined: nil) }
            tap.deliver(.focus(.right), joined: nil)
        }
        try await Task.sleep(for: .seconds(1.0))
        #expect(seen.all == [.retile, .focus(.right)], "\(seen.all)")
    }

    @Test func everyOtherActionIsRunInOrder() async throws {
        let seen = Seen()
        let tap = TilingKeyTap(sink: { seen.add($0) }, onFailure: {})
        let order: [TileAction] = [.focus(.left), .swap(.left), .flipSplit, .focus(.up), .toggleFloat, .retile]
        let sent = DispatchSemaphore(value: 0)
        DispatchQueue.global().async { for action in order { tap.deliver(action, joined: nil) }; sent.signal() }
        #expect(blockMain(until: sent))
        try await Task.sleep(for: .seconds(0.3))
        #expect(seen.all == order)
    }
}
