import Foundation
import Testing
@testable import Zeus

@MainActor
@Suite("Default output watch")
struct DefaultOutputWatchTests {
    @Test func twoSubscribersShareOneBlock() {
        let log = InstallLog()
        let watch = DefaultOutputWatch(installer: log.installer())
        _ = watch.subscribe { }
        _ = watch.subscribe { }
        let shot = log.snapshot()
        #expect(shot.installs == 1)
        #expect(shot.removes == 0)
        #expect(shot.armed)
    }

    @Test func removingOneKeepsTheOther() {
        let log = InstallLog()
        let watch = DefaultOutputWatch(installer: log.installer())
        let left = Counter()
        let right = Counter()
        let first = watch.subscribe { left.add() }
        _ = watch.subscribe { right.add() }
        watch.unsubscribe(first)
        log.emit()
        let shot = log.snapshot()
        #expect(shot.installs == 1)
        #expect(shot.removes == 0)
        #expect(shot.armed)
        #expect(left.value == 0)
        #expect(right.value == 1)
    }

    @Test func removingBothRemovesTheBlock() {
        let log = InstallLog()
        let watch = DefaultOutputWatch(installer: log.installer())
        let first = watch.subscribe { }
        let second = watch.subscribe { }
        watch.unsubscribe(first)
        #expect(log.snapshot().removes == 0)
        watch.unsubscribe(second)
        let shot = log.snapshot()
        #expect(shot.installs == 1)
        #expect(shot.removes == 1)
        #expect(!shot.armed)
    }

    @Test func aChangeReachesEverySubscriberOnce() {
        let log = InstallLog()
        let watch = DefaultOutputWatch(installer: log.installer())
        let left = Counter()
        let right = Counter()
        _ = watch.subscribe { left.add() }
        _ = watch.subscribe { right.add() }
        log.emit()
        #expect(left.value == 1)
        #expect(right.value == 1)
        #expect(log.snapshot().installs == 1)
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func add() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

private final class InstallLog: @unchecked Sendable {
    private let lock = NSLock()
    private var installs = 0
    private var removes = 0
    private var fire: (@Sendable () -> Void)?

    func installer() -> @Sendable (@escaping @Sendable () -> Void) -> DefaultOutputHandle {
        { [self] onChange in
            self.lock.lock()
            self.installs += 1
            self.fire = onChange
            self.lock.unlock()
            return DefaultOutputHandle {
                self.lock.lock()
                self.removes += 1
                self.fire = nil
                self.lock.unlock()
            }
        }
    }

    func emit() {
        lock.lock()
        let fire = self.fire
        lock.unlock()
        fire?()
    }

    func snapshot() -> (installs: Int, removes: Int, armed: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (installs, removes, fire != nil)
    }
}
