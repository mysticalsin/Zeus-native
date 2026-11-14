import CoreFoundation
import Foundation

/// A thread that owns one run loop and nothing else, for the tiling key tap.
///
/// A consuming event tap is serviced by the run loop its source sits on, and the window server holds every keystroke in
/// every app until that loop answers. The main thread cannot be that loop: every Accessibility pass runs there, and
/// one slow app would freeze typing everywhere. This thread does only what the owner's two closures do.
///
/// `install` runs on the new thread, before its loop starts, and adds the source to `CFRunLoopGetCurrent()`.
/// `teardown` runs on the same thread, in its loop, after a stop was asked for: it removes the source and invalidates
/// the port there, so no callback is ever running while the port goes away (a callback and the teardown are two
/// items of one loop). `teardown` runs exactly once for every thread, and never before `install` when both run. A
/// stop that wins the race against the thread's first step skips `install`, and the thread runs `teardown` on its own
/// before it ends: the owner made the port before the thread started, so without the teardown the port would stay
/// registered with the window server, and switched on by a later enable, with no loop to service it. When the loop has
/// ended both closures are released.
///
/// Nonisolated on purpose, like the tap itself: no `@MainActor` type may sit between a system callback and its owner.
final class TilingRunLoopThread: @unchecked Sendable {
    private let lock = NSLock()
    private var install: (@Sendable () -> Void)?
    private var teardown: (@Sendable () -> Void)?
    private var runLoop: CFRunLoop?
    private var keepAlive: CFRunLoopTimer?
    private var stopRequested = false
    private var thread: Thread?
    private let finished = DispatchGroup()

    private let beforeRun: (@Sendable () -> Void)?

    /// Starts the thread. Call `stop()` to end it; dropping the object without a stop leaves the thread running.
    /// `beforeRun` runs on the new thread before its first step. It exists for tests, to hold the thread back so a stop
    /// reaches it first.
    init(name: String, install: @escaping @Sendable () -> Void, teardown: @escaping @Sendable () -> Void,
         beforeRun: (@Sendable () -> Void)? = nil) {
        self.install = install
        self.teardown = teardown
        self.beforeRun = beforeRun
        finished.enter()
        let thread = Thread { [self] in run() }
        thread.name = name
        // Keystrokes wait on this thread, so it must not be starved by background work.
        thread.qualityOfService = .userInteractive
        self.thread = thread
        thread.start()
    }

    /// Asks the thread to tear down and end, and waits until it has, for at most `timeout` seconds. True when it
    /// ended. A stop that comes from the tap thread itself cannot wait for itself: it asks and returns false.
    /// Safe to call more than once.
    @discardableResult
    func stop(timeout: TimeInterval = 2) -> Bool {
        lock.lock()
        let first = !stopRequested
        stopRequested = true
        let loop = runLoop
        let onThread = thread != nil && thread === Thread.current
        lock.unlock()
        // With a loop, the teardown is queued on it and runs after the callback in flight, if any. Without one the
        // thread has not started its loop yet: it sees the flag, runs the teardown itself without installing, and ends.
        if first, let loop {
            CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue) { [self] in tearDownOnLoop() }
            CFRunLoopWakeUp(loop)
        }
        guard !onThread else { return false }
        return finished.wait(timeout: .now() + timeout) == .success
    }

    // MARK: On the thread

    private func run() {
        beforeRun?()
        let loop = CFRunLoopGetCurrent()!
        lock.lock()
        if stopRequested {
            lock.unlock()
            // The stop came first: nothing was installed, but what the owner made for this thread still has to go.
            runTeardownWithoutInstall()
            end()
            return
        }
        runLoop = loop
        lock.unlock()

        runInstall()
        // A run loop with no source or timer returns at once. This timer, a thousand million seconds away, keeps it
        // alive for the tap source; the teardown removes it.
        let timer = CFRunLoopTimerCreateWithHandler(kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + 1e9, 0, 0, 0) { _ in }
        lock.lock()
        keepAlive = timer
        lock.unlock()
        CFRunLoopAddTimer(loop, timer, .commonModes)
        // A stop that arrived while `install` ran is already queued on this loop and runs as soon as it does.
        CFRunLoopRun()
        end()
    }

    // These two take a closure into a local of their own, so no copy of it outlives them: `stop()` returns once `end()`
    // has run, and by then the owner's captures must be released.
    private func runInstall() {
        lock.lock()
        let work = install
        lock.unlock()
        work?()
    }

    private func runTeardownWithoutInstall() {
        lock.lock()
        let work = teardown
        teardown = nil
        lock.unlock()
        work?()
    }

    /// Runs on the tap thread, inside its loop.
    private func tearDownOnLoop() {
        lock.lock()
        let work = teardown
        teardown = nil
        let timer = keepAlive
        keepAlive = nil
        lock.unlock()
        work?()
        let loop = CFRunLoopGetCurrent()!
        if let timer { CFRunLoopRemoveTimer(loop, timer, .commonModes) }
        CFRunLoopStop(loop)
    }

    private func end() {
        lock.lock()
        install = nil
        teardown = nil
        runLoop = nil
        thread = nil
        lock.unlock()
        finished.leave()
    }
}
