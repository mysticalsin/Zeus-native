import Foundation
import Testing
import ZeusCore
@testable import Zeus

/// Monotonic clock whose wall time can jump without moving `now`.
/// Sleep suspends until `advance` passes the deadline, or until the task is cancelled.
final class MediaManualClock: MediaCommandClock, @unchecked Sendable {
    private let lock = NSLock()
    private var instant: ContinuousClock.Instant
    private var wallDate: Date
    private var sleepers: [Sleeper] = []
    private var cancelled: Set<UUID> = []

    init() {
        instant = ContinuousClock.now
        wallDate = Date()
    }

    var now: ContinuousClock.Instant {
        lock.lock()
        defer { lock.unlock() }
        return instant
    }

    var wall: Date {
        lock.lock()
        defer { lock.unlock() }
        return wallDate
    }

    func advance(by duration: Duration) {
        lock.lock()
        instant = instant.advanced(by: duration)
        let due = sleepers.filter { $0.deadline <= instant }
        sleepers.removeAll { $0.deadline <= instant }
        lock.unlock()
        for sleeper in due { sleeper.resume() }
    }

    func jumpWall(by duration: Duration) {
        let parts = duration.components
        let seconds = Double(parts.seconds) + Double(parts.attoseconds) / 1e18
        lock.lock()
        wallDate = wallDate.addingTimeInterval(seconds)
        lock.unlock()
    }

    func sleep(for duration: Duration) async throws {
        if duration <= .zero { return }
        let deadline = now.advanced(by: duration)
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.lock()
                let alreadyCancelled = cancelled.remove(id) != nil || Task.isCancelled
                if alreadyCancelled {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                if instant >= deadline {
                    lock.unlock()
                    continuation.resume()
                    return
                }
                sleepers.append(Sleeper(id: id, deadline: deadline, continuation: continuation))
                lock.unlock()
            }
        } onCancel: {
            lock.lock()
            if let index = sleepers.firstIndex(where: { $0.id == id }) {
                let sleeper = sleepers.remove(at: index)
                lock.unlock()
                sleeper.cancel()
            } else {
                cancelled.insert(id)
                lock.unlock()
            }
        }
    }

    private final class Sleeper: @unchecked Sendable {
        let id: UUID
        let deadline: ContinuousClock.Instant
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Void, Error>?
        private var resumed = false

        init(id: UUID, deadline: ContinuousClock.Instant, continuation: CheckedContinuation<Void, Error>) {
            self.id = id
            self.deadline = deadline
            self.continuation = continuation
        }

        func resume() { finish(nil) }
        func cancel() { finish(CancellationError()) }

        private func finish(_ error: Error?) {
            lock.lock()
            guard !resumed, let continuation else {
                lock.unlock()
                return
            }
            resumed = true
            self.continuation = nil
            lock.unlock()
            if let error {
                continuation.resume(throwing: error)
            } else {
                continuation.resume()
            }
        }
    }
}

/// Holds the open callback until the test completes it. `finished` is what the poll reads.
@MainActor
final class HoldingPlayerLaunch: MediaPlayerLaunching {
    private(set) var bundleID: String?
    private(set) var activates: Bool?
    var finished = true
    private var done: (@Sendable (Bool) -> Void)?

    func startOpen(bundleID: String, activates: Bool, done: @escaping @Sendable (Bool) -> Void) {
        self.bundleID = bundleID
        self.activates = activates
        self.done = done
    }

    func complete(opened: Bool) {
        let done = self.done
        self.done = nil
        done?(opened)
    }

    func isFinishedLaunching(bundleID: String) -> Bool { finished }
}

@MainActor
final class AcceptingMediaTransport: MediaCommandTransport {
    var advanceOnDeliver: (@MainActor () -> Void)?

    func deliver(_ command: MediaControlCommand, route: MediaCommandRoute) async -> MediaCommandDelivery {
        advanceOnDeliver?()
        return .accepted
    }

    func readBack(_ route: MediaCommandRoute) async {}
}

@MainActor
private struct MediaLaunchRig {
    let clock = MediaManualClock()
    let launch = HoldingPlayerLaunch()
    let transport = AcceptingMediaTransport()
    let driver: MediaCommandDriver

    init() {
        driver = MediaCommandDriver(clock: clock, opener: launch, transport: transport)
    }

    func pausedPlayer() {
        let route = MediaCommandRoute(
            endpoint: .scriptedPlayer(bundleID: MediaCommandRouter.defaultLaunchBundleID),
            canSkip: true,
            canSeek: true)
        driver.resync(MediaNowPlayingSample(isPlaying: false, position: 1, duration: 180, route: route))
    }
}

@MainActor
@Suite struct MediaCommandCoordinatorTests {
    @Test func deadlinesFollowTheInjectedMonotonicClockWhenTheWallClockJumps() async {
        #expect(MediaCommandRouter.launchTimeout == 8)
        #expect(MediaCommandRouter.debounceWindow == 0.25)
        #expect(MediaCommandRouter.resyncDelay == 0.12)

        let late = MediaLaunchRig()
        late.driver.resync(nil)
        late.driver.press(.play)
        let wallAtLaunch = late.clock.wall
        // Past the bound on the monotonic clock, still inside the extra second before the give-up sleep.
        // A wall-clock reading here is only a few milliseconds, so a Date() budget would still accept the open.
        late.clock.advance(by: .seconds(MediaCommandRouter.launchTimeout + 0.5))
        #expect(late.clock.wall.timeIntervalSince(wallAtLaunch) < 2)
        late.launch.complete(opened: true)
        await late.driver.waitUntilLaunchSettled()
        #expect(late.driver.sent.isEmpty)
        #expect(late.driver.state == .failed(.launchFailed))
        #expect(late.launch.activates == false)
        #expect(late.launch.bundleID == MediaCommandRouter.defaultLaunchBundleID)

        let onTime = MediaLaunchRig()
        onTime.driver.resync(nil)
        onTime.driver.press(.play)
        let sleep = onTime.driver.pendingSleep
        let wallBeforeJump = onTime.clock.wall
        onTime.clock.jumpWall(by: .seconds(MediaCommandRouter.launchTimeout + 30))
        onTime.clock.advance(by: .seconds(MediaCommandRouter.launchTimeout))
        #expect(onTime.clock.wall.timeIntervalSince(wallBeforeJump) > MediaCommandRouter.launchTimeout)
        onTime.launch.complete(opened: true)
        await onTime.driver.waitUntilLaunchSettled()
        await onTime.driver.waitUntilParked()
        #expect(onTime.driver.sent == [.play])
        #expect(onTime.driver.state == .playing)
        #expect(sleep?.isCancelled == true)
        onTime.driver.stop()
    }

    @Test func pendingSleepIsCancelledOnANewCommandOrTeardownAndDoesNotPlayLate() async {
        let rig = MediaLaunchRig()
        rig.transport.advanceOnDeliver = { rig.clock.advance(by: .seconds(MediaCommandRouter.debounceWindow)) }
        rig.pausedPlayer()
        rig.driver.press(.play)
        await rig.driver.waitUntilParked()
        let commandSleep = rig.driver.pendingSleep
        #expect(commandSleep != nil)
        #expect(commandSleep?.isCancelled == false)
        #expect(rig.driver.sent == [.play])
        #expect(rig.driver.state == .playing)

        rig.driver.press(.pause)
        #expect(commandSleep?.isCancelled == true)
        await rig.driver.waitUntilParked()
        #expect(rig.driver.sent == [.play, .pause])
        #expect(rig.driver.state == .paused)

        rig.clock.advance(by: .seconds(MediaCommandRouter.debounceWindow))
        rig.driver.resync(nil)
        rig.driver.press(.play)
        let launchSleep = rig.driver.pendingSleep
        #expect(launchSleep != nil)
        #expect(launchSleep?.isCancelled == false)
        #expect(rig.driver.state == .launchingSource)
        let sentBeforeStop = rig.driver.sent

        rig.driver.stop()
        #expect(launchSleep?.isCancelled == true)
        rig.launch.complete(opened: true)
        await rig.driver.waitUntilLaunchSettled()
        #expect(rig.driver.sent == sentBeforeStop)
        #expect(rig.driver.sent == [.play, .pause])
        #expect(rig.driver.state != .playing)
        #expect(rig.driver.state != .commandPending(.play))
    }

    @Test func rapidPlayPauseTogglingStaysBounded() async {
        let rig = MediaLaunchRig()
        rig.pausedPlayer()
        let toggles = 24
        for index in 0..<toggles {
            let command: MediaControlCommand = index.isMultiple(of: 2) ? .play : .pause
            rig.driver.press(command)
            await rig.driver.waitUntilParked()
            if index == 0 {
                let before = rig.driver.sent.count
                rig.clock.jumpWall(by: .seconds(10))
                rig.clock.advance(by: .milliseconds(10))
                rig.driver.press(.pause)
                #expect(rig.driver.sent.count == before)
            }
            rig.clock.advance(by: .seconds(MediaCommandRouter.debounceWindow))
        }
        #expect(rig.driver.sent.count == toggles)
        for (index, command) in rig.driver.sent.enumerated() {
            #expect(command == (index.isMultiple(of: 2) ? MediaControlCommand.play : .pause))
        }
        #expect(rig.driver.state == .paused)

        let burst = 32
        let beforeBurst = rig.driver.sent.count
        rig.driver.press(.play)
        for _ in 0..<burst {
            rig.driver.press(.play)
            rig.driver.press(.pause)
        }
        await rig.driver.waitUntilParked()
        #expect(rig.driver.sent.count == beforeBurst + 1)
        #expect(rig.driver.sent.count <= toggles + 1)
        #expect(rig.driver.sent.last == .play)
        #expect(rig.driver.state == .playing)
        rig.driver.stop()
    }
}
