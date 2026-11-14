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

    @Test func aStopRequestedBeforeTheThreadGotToInstallStillRunsTheTeardownOnTheTapThread() {
        // The thread is held before its first step, so the stop surely wins the race.
        let log = Log()
        let release = DispatchSemaphore(value: 0)
        let thread = TilingRunLoopThread(
            name: "app.zeus.tiling.test", install: { log.add("install") },
            teardown: { log.add("teardown on \(Thread.isMainThread ? "main" : "tap")") },
            beforeRun: { _ = release.wait(timeout: .now() + 2) })
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { release.signal() }
        #expect(thread.stop())
        #expect(log.all == ["teardown on tap"], "the port made before the thread started is still turned off and invalidated: \(log.all)")
    }

    @Test func everyThreadTearsDownExactlyOnceWhateverTheStopTiming() {
        for _ in 0..<200 {
            let beacon = Beacon()
            let log = Log()
            let thread = launch(beacon, log: log)
            #expect(thread.stop())
            let installs = log.all.filter { $0.hasPrefix("install") }.count
            let teardowns = log.all.filter { $0.hasPrefix("teardown") }.count
            #expect(teardowns == 1 && installs <= 1, "a teardown for every thread, installed or not: \(log.all)")
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

    /// The one test that uses the real system tap. It must pass whether or not this process may create one: without
    /// Accessibility `start()` says false and nothing runs, with it the tap has a closed gate and passes every event.
    @Test func aLiveSmokeTapStartsAndStopsWhetherOrNotTheRunnerIsTrusted() {
        let tap = TilingKeyTap(sink: { _, _ in }, onFailure: {})
        let started = tap.start()
        #expect(tap.isRunning == started)
        #expect(tap.stop())
        #expect(!tap.isRunning)
    }

    @Test func aBurstOfFocusRepeatsWhileMainIsBusyRunsOneAction() async throws {
        let seen = Seen()
        let tap = TilingKeyTap(sink: { action, _ in seen.add(action) }, onFailure: {})
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
        let tap = TilingKeyTap(sink: { action, _ in
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
        let tap = TilingKeyTap(sink: { action, _ in seen.add(action) }, onFailure: {})
        let order: [TileAction] = [.focus(.left), .swap(.left), .flipSplit, .focus(.up), .toggleFloat, .retile]
        let sent = DispatchSemaphore(value: 0)
        DispatchQueue.global().async { for action in order { tap.deliver(action, joined: nil) }; sent.signal() }
        #expect(blockMain(until: sent))
        // Wait for the drains, not for a fixed time: other suites share the main thread and can hold it for a moment.
        let deadline = Date().addingTimeInterval(5)
        while seen.all.count < order.count, Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(seen.all == order)
    }
}

/// The real tap object on a stand-in system: a run loop source in place of the event tap, so the object's own wiring is
/// tested without Accessibility. This is what pins the tap to a thread of its own, and what proves a stop leaves no
/// port behind in each of the paths (normal, stop winning the race, a thread that is slow to end).
@Suite("Tiling key tap on a stand-in system", .serialized) @MainActor
struct TilingKeyTapStandInTests {
    /// Locked record of what the tap did to its port and where.
    private final class Standin: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var created = 0
        private(set) var ports: [CFMachPort] = []
        private(set) var enables: [(on: Bool, main: Bool)] = []
        private var source: CFRunLoopSource?
        private var loop: CFRunLoop?
        var onFire: @Sendable () -> Void = {}
        /// Called inside the `setEnabled(false)` of the teardown, on the thread that tears the tap down. The first switch
        /// of a port, the one right after it is made, does not call it.
        var duringDisable: @Sendable () -> Void = {}
        /// Called inside every `setEnabled(true)`.
        var duringEnable: @Sendable () -> Void = {}

        func system() -> TilingTapSystem {
            TilingTapSystem(
                create: { [self] _ in
                    var context = CFRunLoopSourceContext(
                        version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil,
                        copyDescription: nil, equal: nil, hash: nil,
                        schedule: { info, loop, _ in
                            let me = Unmanaged<Standin>.fromOpaque(info!).takeUnretainedValue()
                            me.lock.lock(); me.loop = loop; me.lock.unlock()
                        },
                        cancel: nil,
                        perform: { info in Unmanaged<Standin>.fromOpaque(info!).takeUnretainedValue().onFire() })
                    guard let made = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &context) else { return nil }
                    var free = DarwinBoolean(false)
                    guard let port = CFMachPortCreate(kCFAllocatorDefault, { _, _, _, _ in }, nil, &free) else { return nil }
                    lock.lock(); created += 1; ports.append(port); source = made; lock.unlock()
                    return (port, made)
                },
                setEnabled: { [self] _, on in
                    lock.lock(); enables.append((on, Thread.isMainThread)); let first = enables.count == 1; lock.unlock()
                    if on { duringEnable() } else if !first { duringDisable() }
                })
        }

        func fire() {
            lock.lock(); let made = source; let current = loop; lock.unlock()
            guard let made, let current else { return }
            CFRunLoopSourceSignal(made)
            CFRunLoopWakeUp(current)
        }

        var valid: [Bool] { lock.lock(); defer { lock.unlock() }; return ports.map { CFMachPortIsValid($0) } }
        var enableLog: [(on: Bool, main: Bool)] { lock.lock(); defer { lock.unlock() }; return enables }
    }

    private func waitLive(_ standin: Standin) -> Bool {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if standin.enableLog.contains(where: { $0.on }) { return true }
            Thread.sleep(forTimeInterval: 0.002)
        }
        return false
    }

    @Test func theTapIsEnabledAndServicedOnAThreadOfItsOwnWhileMainIsBlocked() {
        let standin = Standin()
        let tap = TilingKeyTap(sink: { _, _ in }, onFailure: {}, system: standin.system())
        defer { tap.stop() }
        let ran = DispatchSemaphore(value: 0)
        let onMain = TapFlag()
        standin.onFire = { onMain.set(Thread.isMainThread); ran.signal() }
        #expect(tap.start())
        #expect(waitLive(standin))
        #expect(standin.enableLog.first(where: { $0.on })?.main == false, "the tap is turned on by its own thread, not the main one")
        DispatchQueue.global().async { standin.fire() }
        #expect(Thread.isMainThread)
        #expect(ran.wait(timeout: .now() + 2) == .success, "the source waited for the blocked main thread")
        #expect(onMain.value == false)
    }

    @Test func theTapIsMadeOffAndOnlyItsOwnThreadSwitchesItOn() {
        let standin = Standin()
        let tap = TilingKeyTap(sink: { _, _ in }, onFailure: {}, system: standin.system())
        defer { tap.stop() }
        #expect(tap.start())
        #expect(waitLive(standin))
        let log = standin.enableLog
        #expect(log.count >= 2, "\(log)")
        #expect(log.first?.on == false && log.first?.main == true, "the owner switches the port off as soon as it is made: \(log)")
        #expect(log.dropFirst().first?.on == true && log.dropFirst().first?.main == false,
                "the tap thread switches it on once its source is on the loop: \(log)")
    }

    @Test func aBoundChordDecidedAfterStopTookTheLockPassesThrough() {
        let standin = Standin()
        let reached = DispatchSemaphore(value: 0)
        let hold = DispatchSemaphore(value: 0)
        standin.duringDisable = { reached.signal(); _ = hold.wait(timeout: .now() + 5) } // the teardown, held open
        let tap = TilingKeyTap(sink: { _, _ in }, onFailure: {}, system: standin.system())
        tap.update(keymap: TileKeymap.defaults(base: .controlOptionCommand), enabled: true, paused: false)
        #expect(tap.start())
        #expect(waitLive(standin))
        let chord = TileKeyEvent(phase: .down, keyCode: 123, modifiers: [.control, .option, .command])
        #expect(tap.decide(chord, secure: false) == .consume(.focus(.left)), "while tiling runs the chord is taken")
        let stopped = DispatchSemaphore(value: 0)
        DispatchQueue.global().async { tap.stop(); stopped.signal() }
        #expect(reached.wait(timeout: .now() + 2) == .success)
        #expect(tap.decide(chord, secure: false) == .passThrough, "stop closed the gate under its lock, before the teardown ran")
        hold.signal()
        #expect(stopped.wait(timeout: .now() + 5) == .success)
    }

    @Test func aSetEnabledThatTakesTheTapsLockReturnsWhenStartAsksForAnEnable() {
        let standin = Standin()
        let tap = TilingKeyTap(sink: { _, _ in }, onFailure: {}, system: standin.system())
        standin.duringEnable = { _ = tap.isRunning } // takes the lock the callback takes
        #expect(tap.start())
        #expect(waitLive(standin))
        let enabled = standin.enableLog.filter(\.on).count
        let returned = DispatchSemaphore(value: 0)
        DispatchQueue.global().async { _ = tap.start(); returned.signal() }
        let done = returned.wait(timeout: .now() + 2) == .success
        #expect(done, "start() made a window server call while holding the lock the callback needs")
        guard done else { return } // a stuck lock cannot be stopped
        let deadline = Date().addingTimeInterval(2)
        while standin.enableLog.filter(\.on).count == enabled, Date() < deadline { Thread.sleep(forTimeInterval: 0.002) }
        let log = standin.enableLog.filter(\.on)
        #expect(log.count == enabled + 1 && log.last?.main == false, "the enable ran once, on the tap thread: \(standin.enableLog)")
        tap.stop()
    }

    @Test func anEnableAskedForBeforeAStopIsNotAppliedAfterIt() {
        let standin = Standin()
        let tap = TilingKeyTap(sink: { _, _ in }, onFailure: {}, system: standin.system())
        #expect(tap.start())
        #expect(waitLive(standin))
        // The tap thread is busy in a callback, so an enable asked for now can only wait behind it.
        let busy = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        standin.onFire = { busy.signal(); _ = release.wait(timeout: .now() + 5) }
        DispatchQueue.global().async { standin.fire() }
        #expect(busy.wait(timeout: .now() + 2) == .success)
        #expect(tap.start())
        let stopped = DispatchSemaphore(value: 0)
        DispatchQueue.global().async { tap.stop(); stopped.signal() }
        let deadline = Date().addingTimeInterval(2)
        while tap.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.002) }
        release.signal()
        #expect(stopped.wait(timeout: .now() + 5) == .success)
        #expect(standin.enableLog.map(\.on) == [false, true, false],
                "off when made, on once installed, off by the teardown, and no enable after the stop: \(standin.enableLog)")
    }

    @Test func stopTurnsTheTapOffAndInvalidatesItsPortBeforeItReturns() {
        let standin = Standin()
        let tap = TilingKeyTap(sink: { _, _ in }, onFailure: {}, system: standin.system())
        #expect(tap.start())
        #expect(waitLive(standin))
        tap.stop()
        #expect(!tap.isRunning)
        #expect(standin.valid == [false])
        #expect(standin.enableLog.last?.on == false && standin.enableLog.last?.main == false)
    }

    @Test func startingAndStoppingManyTimesLeavesNothingRunning() {
        let standin = Standin()
        let tap = TilingKeyTap(sink: { _, _ in }, onFailure: {}, system: standin.system())
        for cycle in 0..<40 {
            let started = tap.start()
            #expect(started)
            #expect(tap.isRunning == started, "cycle \(cycle)")
            #expect(tap.start() == started, "a second start changes nothing")
            #expect(tap.stop())
            #expect(!tap.isRunning, "cycle \(cycle)")
        }
        #expect(tap.stop())
        #expect(!tap.isRunning)
        #expect(standin.created == 40 && !standin.valid.contains(true))
    }

    @Test func aTapThatIsDroppedWhileRunningEndsItsThreadAndIsFreed() {
        let standin = Standin()
        var tap: TilingKeyTap? = TilingKeyTap(sink: { _, _ in }, onFailure: {}, system: standin.system())
        weak var observed = tap
        #expect(tap?.start() == true)
        tap = nil
        #expect(observed == nil, "nothing keeps a dropped tap alive")
        #expect(standin.valid == [false], "and its port went with it")
    }

    @Test func aStopThatWinsTheRaceStillInvalidatesThePort() {
        for round in 0..<300 {
            let standin = Standin()
            let tap = TilingKeyTap(sink: { _, _ in }, onFailure: {}, system: standin.system())
            #expect(tap.start())
            tap.stop() // in the same main-thread turn: the thread may not have run yet
            #expect(standin.valid == [false], "round \(round): a port made by start is always invalidated by stop")
            #expect(standin.enableLog.last?.on == false, "round \(round): and it is turned off, not left enabled with no loop")
        }
    }

    @Test func startingAndStoppingManyTimesCreatesOnePortEachAndLeavesNoneValid() {
        let standin = Standin()
        let tap = TilingKeyTap(sink: { _, _ in }, onFailure: {}, system: standin.system())
        for _ in 0..<60 {
            #expect(tap.start())
            tap.stop()
        }
        #expect(standin.created == 60)
        #expect(!standin.valid.contains(true))
    }

    @Test func aStopThatTimesOutKeepsTheRunSoNoSecondTapIsCreatedBesideIt() {
        let standin = Standin()
        let hold = DispatchSemaphore(value: 0)
        standin.duringDisable = { _ = hold.wait(timeout: .now() + 5) } // a thread that is slow to end
        let tap = TilingKeyTap(sink: { _, _ in }, onFailure: {}, system: standin.system(), stopTimeout: 0.1)
        #expect(tap.start())
        #expect(waitLive(standin))
        #expect(!tap.stop(), "gives up waiting after 0.1 s and says the thread has not ended")
        #expect(standin.created == 1)
        #expect(!tap.start(), "the old thread and tap may still exist, so no second tap is made")
        #expect(standin.created == 1, "still one tap")
        hold.signal() // the old thread finishes
        #expect(tap.stop(), "a later stop waits for it again and sees it end")
        #expect(standin.valid == [false])
        #expect(tap.start(), "once the old one is gone a new tap can start")
        #expect(standin.created == 2)
        tap.stop()
    }

    @Test func twoStopsAtOnceBothReturnOnlyWhenTheTapIsGone() {
        let standin = Standin()
        standin.duringDisable = { Thread.sleep(forTimeInterval: 0.15) }
        let tap = TilingKeyTap(sink: { _, _ in }, onFailure: {}, system: standin.system())
        #expect(tap.start())
        #expect(waitLive(standin))
        let gone = TapFlags()
        let group = DispatchGroup()
        for index in 0..<2 {
            group.enter()
            DispatchQueue.global().async { tap.stop(); gone.set(index, standin.valid == [false]); group.leave() }
        }
        group.wait()
        #expect(gone.all == [true, true], "a second caller does not return while the thread may still be consuming keys")
    }
}

private final class TapFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Bool?
    func set(_ value: Bool) { lock.lock(); stored = value; lock.unlock() }
    var value: Bool? { lock.lock(); defer { lock.unlock() }; return stored }
}

private final class TapFlags: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Int: Bool] = [:]
    func set(_ index: Int, _ value: Bool) { lock.lock(); stored[index] = value; lock.unlock() }
    var all: [Bool] { lock.lock(); defer { lock.unlock() }; return stored.keys.sorted().map { stored[$0]! } }
}
