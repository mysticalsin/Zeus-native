import Foundation
import Testing
@testable import Zeus

@Suite("Earbuds session source")
struct EarbudsSessionSourceTests {
    @Test func theLiveTypeStartsActiveAndUnlocked() {
        let source: any EarbudsSessionReading = LiveEarbudsSessionSource(install: { _, _ in nil })
        #expect(source.active)
        #expect(!source.locked)
        #expect(EarbudsSessionBook.initial == EarbudsSessionNote(active: true, locked: false))
    }

    @Test func theFourNamesChooseABoard() {
        #expect(EarbudsSessionBook.board(EarbudsSessionBook.resign) == .workspace)
        #expect(EarbudsSessionBook.board(EarbudsSessionBook.become) == .workspace)
        #expect(EarbudsSessionBook.board(EarbudsSessionBook.locked) == .distributed)
        #expect(EarbudsSessionBook.board(EarbudsSessionBook.unlocked) == .distributed)
        #expect(EarbudsSessionBook.board("NSWorkspaceScreensDidSleepNotification") == nil)
        #expect(EarbudsSessionBook.board("") == nil)
        #expect(EarbudsSessionBook.watched.count == 4)
    }

    @Test func aSecondApplyOfTheSameFactIsQuiet() {
        let resigned = EarbudsSessionBook.apply(EarbudsSessionBook.resign, to: EarbudsSessionBook.initial)
        #expect(resigned == EarbudsSessionNote(active: false, locked: false))
        #expect(EarbudsSessionBook.apply(EarbudsSessionBook.resign, to: resigned!) == nil)
        let locked = EarbudsSessionBook.apply(EarbudsSessionBook.locked, to: EarbudsSessionBook.initial)
        #expect(locked == EarbudsSessionNote(active: true, locked: true))
        #expect(EarbudsSessionBook.apply(EarbudsSessionBook.locked, to: locked!) == nil)
        #expect(EarbudsSessionBook.apply(EarbudsSessionBook.unlocked, to: EarbudsSessionBook.initial) == nil)
    }

    @Test func sleepWakeBlankAndADifferentCaseChangeNothing() {
        let names = [
            "",
            " ",
            EarbudsSessionBook.resign.lowercased(),
            EarbudsSessionBook.locked + " ",
            EarbudsSessionBook.resign + "X",
            "NSWorkspaceScreensDidSleepNotification",
            "NSWorkspaceScreensDidWakeNotification",
            "NSWorkspaceWillSleepNotification",
            "NSWorkspaceDidWakeNotification",
            "NSWorkspaceActiveSpaceDidChangeNotification",
        ]
        for name in names {
            #expect(EarbudsSessionBook.apply(name, to: EarbudsSessionBook.initial) == nil)
        }
    }

    @Test func startRegistersEachNameOnceAndDoesNotReport() {
        let log = SessionLog()
        let source = LiveEarbudsSessionSource(install: log.installer())
        let notes = Notes()
        source.start { notes.add($0) }
        #expect(log.installed() == EarbudsSessionBook.watched)
        #expect(log.removed().isEmpty)
        #expect(notes.values.isEmpty)
        #expect(source.active)
        #expect(!source.locked)
    }

    @Test func aSecondStartRegistersNothing() {
        let log = SessionLog()
        let source = LiveEarbudsSessionSource(install: log.installer())
        let notes = Notes()
        let second = Flag()
        source.start { notes.add($0) }
        source.start { _ in second.raise() }
        log.fire(EarbudsSessionBook.resign)
        #expect(log.installed() == EarbudsSessionBook.watched)
        #expect(!second.value)
        #expect(notes.values == [EarbudsSessionNote(active: false, locked: false)])
    }

    @Test func resignAndBecomeReportTheSession() {
        let log = SessionLog()
        let source = LiveEarbudsSessionSource(install: log.installer())
        let notes = Notes()
        source.start { notes.add($0) }
        log.fire(EarbudsSessionBook.resign)
        #expect(!source.active)
        #expect(!source.locked)
        log.fire(EarbudsSessionBook.become)
        #expect(source.active)
        #expect(notes.values == [
            EarbudsSessionNote(active: false, locked: false),
            EarbudsSessionNote(active: true, locked: false),
        ])
    }

    @Test func lockAndUnlockLeaveTheSessionActive() {
        let log = SessionLog()
        let source = LiveEarbudsSessionSource(install: log.installer())
        let notes = Notes()
        source.start { notes.add($0) }
        log.fire(EarbudsSessionBook.locked)
        #expect(source.active)
        #expect(source.locked)
        log.fire(EarbudsSessionBook.unlocked)
        #expect(source.active)
        #expect(!source.locked)
        #expect(notes.values == [
            EarbudsSessionNote(active: true, locked: true),
            EarbudsSessionNote(active: true, locked: false),
        ])
    }

    @Test func lockThenResignKeepsTheLock() {
        let log = SessionLog()
        let source = LiveEarbudsSessionSource(install: log.installer())
        let notes = Notes()
        source.start { notes.add($0) }
        log.fire(EarbudsSessionBook.locked)
        log.fire(EarbudsSessionBook.resign)
        #expect(!source.active)
        #expect(source.locked)
        #expect(notes.values.last == EarbudsSessionNote(active: false, locked: true))
    }

    @Test func aRepeatedNameReportsOnce() {
        let log = SessionLog()
        let source = LiveEarbudsSessionSource(install: log.installer())
        let notes = Notes()
        source.start { notes.add($0) }
        log.fire(EarbudsSessionBook.resign)
        log.fire(EarbudsSessionBook.resign)
        log.fire("NSWorkspaceScreensDidSleepNotification")
        log.fire(EarbudsSessionBook.locked.lowercased())
        #expect(notes.values.count == 1)
        #expect(!source.active)
        #expect(!source.locked)
    }

    @Test func aNilRegistrationIsLeftOut() {
        let log = SessionLog()
        log.skip(EarbudsSessionBook.become)
        let source = LiveEarbudsSessionSource(install: log.installer())
        source.start { _ in }
        #expect(log.installed() == [EarbudsSessionBook.resign, EarbudsSessionBook.locked, EarbudsSessionBook.unlocked])
        #expect(log.skippedNames() == [EarbudsSessionBook.become])
        source.stop()
        #expect(log.removed() == [EarbudsSessionBook.resign, EarbudsSessionBook.locked, EarbudsSessionBook.unlocked])
    }

    @Test func stopKeepsTheLastNote() {
        let log = SessionLog()
        let source = LiveEarbudsSessionSource(install: log.installer())
        let notes = Notes()
        source.start { notes.add($0) }
        log.fire(EarbudsSessionBook.locked)
        source.stop()
        log.fire(EarbudsSessionBook.unlocked)
        #expect(source.active)
        #expect(source.locked)
        #expect(notes.values == [EarbudsSessionNote(active: true, locked: true)])
    }

    @Test func stopRemovesTheHeldNamesAndALaterNoteIsQuiet() {
        let log = SessionLog()
        let source = LiveEarbudsSessionSource(install: log.installer())
        let notes = Notes()
        source.start { notes.add($0) }
        source.stop()
        #expect(log.removed() == EarbudsSessionBook.watched)
        log.fire(EarbudsSessionBook.locked)
        #expect(notes.values.isEmpty)
        #expect(source.active)
        #expect(!source.locked)
    }

    @Test func stopBeforeStartRemovesNothing() {
        let log = SessionLog()
        let source = LiveEarbudsSessionSource(install: log.installer())
        source.stop()
        #expect(log.installed().isEmpty)
        #expect(log.removed().isEmpty)
        #expect(source.active)
        #expect(!source.locked)
    }

    @Test func startAfterStopRegistersAgain() {
        let log = SessionLog()
        let source = LiveEarbudsSessionSource(install: log.installer())
        let notes = Notes()
        source.start { notes.add($0) }
        source.stop()
        source.start { notes.add($0) }
        #expect(log.installed() == EarbudsSessionBook.watched + EarbudsSessionBook.watched)
        log.fire(EarbudsSessionBook.locked)
        #expect(notes.values == [EarbudsSessionNote(active: true, locked: true)])
        #expect(source.locked)
    }

    @Test func aReportedNoteStaysPutWhenTheBookMoves() {
        let log = SessionLog()
        let source = LiveEarbudsSessionSource(install: log.installer())
        let notes = Notes()
        source.start { notes.add($0) }
        log.fire(EarbudsSessionBook.locked)
        let first = notes.values[0]
        log.fire(EarbudsSessionBook.unlocked)
        #expect(first == EarbudsSessionNote(active: true, locked: true))
        #expect(notes.values[1] == EarbudsSessionNote(active: true, locked: false))
        #expect(!source.locked)
    }
}

private final class Notes: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [EarbudsSessionNote] = []

    func add(_ note: EarbudsSessionNote) {
        lock.lock()
        items.append(note)
        lock.unlock()
    }

    var values: [EarbudsSessionNote] {
        lock.lock()
        defer { lock.unlock() }
        return items
    }
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var raised = false

    func raise() {
        lock.lock()
        raised = true
        lock.unlock()
    }

    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return raised
    }
}

private final class SessionLog: @unchecked Sendable {
    private let lock = NSLock()
    private var installs: [String] = []
    private var removes: [String] = []
    private var skips: [String] = []
    private var fires: [String: @Sendable () -> Void] = [:]
    private var namesToSkip: Set<String> = []

    func skip(_ name: String) {
        lock.lock()
        namesToSkip.insert(name)
        lock.unlock()
    }

    func installer() -> @Sendable (String, @escaping @Sendable () -> Void) -> EarbudsSessionRegistration? {
        { [self] name, onChange in
            let pass: Bool
            self.lock.lock()
            pass = !self.namesToSkip.contains(name)
            if pass {
                self.installs.append(name)
                self.fires[name] = onChange
            } else {
                self.skips.append(name)
            }
            self.lock.unlock()
            guard pass else { return nil }
            return EarbudsSessionRegistration {
                self.lock.lock()
                self.removes.append(name)
                self.fires[name] = nil
                self.lock.unlock()
            }
        }
    }

    func fire(_ name: String) {
        lock.lock()
        let fire = fires[name]
        lock.unlock()
        fire?()
    }

    func installed() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return installs
    }

    func removed() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return removes
    }

    func skippedNames() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return skips
    }
}
