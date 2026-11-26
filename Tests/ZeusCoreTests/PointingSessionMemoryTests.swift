import Foundation
import Testing
@testable import ZeusCore

@Suite("Pointing session memory")
struct PointingSessionMemoryTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    private let mebibyte = 8 * 1024 * 1024

    private func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012X", n))!
    }

    private func payload(count: Int, tag: UInt8) -> Data {
        guard count > 0 else { return Data() }
        var data = Data(count: count)
        data[0] = tag
        if count > 1 { data[count - 1] = tag }
        return data
    }

    @Test func constantsMatchThePlan() {
        #expect(PointingSessionMemory.snapshotLimit == 3)
        #expect(PointingSessionMemory.snapshotByteLimit == mebibyte)
        #expect(PointingSessionMemory.snapshotRetention == 10 * 60)
        #expect(PointingSessionMemory.sessionRetention == 24 * 60 * 60)
    }

    @Test func anOpenSessionRemembersBytesAndListsNewestFirst() {
        var memory = PointingSessionMemory()
        let older = id(1)
        let newer = id(2)
        let first = id(3)
        let second = id(4)
        let firstBytes = payload(count: 4, tag: 7)
        let secondBytes = payload(count: 6, tag: 9)
        #expect(memory.beginSession(id: older, at: start) == .started)
        #expect(memory.beginSession(id: newer, at: start.addingTimeInterval(1)) == .started)
        #expect(memory.rememberSnapshot(id: first, bytes: firstBytes, sessionID: older, at: start) == .stored)
        #expect(memory.rememberSnapshot(id: second, bytes: secondBytes, sessionID: newer, at: start.addingTimeInterval(1)) == .stored)
        let listed = memory.list(at: start.addingTimeInterval(1))
        #expect(listed.sessions.map(\.id) == [newer, older])
        #expect(listed.sessions.map(\.isOpen) == [true, true])
        #expect(listed.snapshots.map(\.id) == [second, first])
        #expect(listed.snapshots.map(\.sessionID) == [newer, older])
        #expect(listed.snapshots.map(\.bytes) == [secondBytes, firstBytes])
        #expect(listed.snapshots.map(\.byteCount) == [6, 4])
    }

    @Test func emptyAndOversizePayloadsAreRefused() {
        var memory = PointingSessionMemory()
        let session = id(1)
        let kept = id(2)
        let keptBytes = payload(count: 3, tag: 2)
        #expect(memory.beginSession(id: session, at: start) == .started)
        #expect(memory.rememberSnapshot(id: kept, bytes: keptBytes, sessionID: session, at: start) == .stored)
        #expect(memory.rememberSnapshot(id: id(3), bytes: Data(), sessionID: session, at: start) == .rejectedEmpty)
        let oversize = payload(count: mebibyte + 1, tag: 5)
        #expect(memory.rememberSnapshot(id: id(4), bytes: oversize, sessionID: session, at: start) == .rejectedTooLarge)
        let exact = payload(count: mebibyte, tag: 4)
        #expect(memory.rememberSnapshot(id: id(5), bytes: exact, sessionID: session, at: start) == .stored)
        let listed = memory.list(at: start)
        #expect(listed.snapshots.map(\.id) == [id(5), kept])
        #expect(listed.snapshots.first?.byteCount == mebibyte)
        #expect(listed.snapshots.first?.bytes.first == 4)
        #expect(listed.snapshots.first?.bytes.last == 4)
        #expect(listed.snapshots.last?.bytes == keptBytes)
    }

    @Test func theFourthSnapshotDropsTheOldestAcrossSessions() {
        var memory = PointingSessionMemory()
        let firstSession = id(1)
        let secondSession = id(2)
        #expect(memory.beginSession(id: firstSession, at: start) == .started)
        #expect(memory.beginSession(id: secondSession, at: start) == .started)
        #expect(memory.rememberSnapshot(id: id(11), bytes: payload(count: 1, tag: 1), sessionID: firstSession, at: start) == .stored)
        #expect(memory.rememberSnapshot(id: id(12), bytes: payload(count: 1, tag: 2), sessionID: firstSession, at: start.addingTimeInterval(1)) == .stored)
        #expect(memory.rememberSnapshot(id: id(13), bytes: payload(count: 1, tag: 3), sessionID: firstSession, at: start.addingTimeInterval(2)) == .stored)
        #expect(memory.list(at: start.addingTimeInterval(2)).snapshots.map(\.id) == [id(13), id(12), id(11)])
        #expect(memory.rememberSnapshot(id: id(14), bytes: payload(count: 1, tag: 4), sessionID: secondSession, at: start.addingTimeInterval(3)) == .stored)
        let listed = memory.list(at: start.addingTimeInterval(3))
        #expect(listed.snapshots.map(\.id) == [id(14), id(13), id(12)])
        #expect(listed.snapshots.map(\.sessionID) == [secondSession, firstSession, firstSession])
        #expect(listed.sessions.map(\.id).count == 2)
    }

    @Test func theSameTimeDropsTheEarlierSnapshot() {
        var memory = PointingSessionMemory()
        let session = id(1)
        #expect(memory.beginSession(id: session, at: start) == .started)
        for n in 21...23 {
            #expect(memory.rememberSnapshot(id: id(n), bytes: payload(count: 1, tag: UInt8(n)), sessionID: session, at: start) == .stored)
        }
        #expect(memory.rememberSnapshot(id: id(24), bytes: payload(count: 1, tag: 24), sessionID: session, at: start) == .stored)
        #expect(memory.list(at: start).snapshots.map(\.id) == [id(24), id(23), id(22)])
    }

    @Test func snapshotsExpireAtTenMinutes() {
        var memory = PointingSessionMemory()
        let session = id(1)
        let early = id(2)
        let later = id(3)
        #expect(memory.beginSession(id: session, at: start) == .started)
        #expect(memory.rememberSnapshot(id: early, bytes: payload(count: 2, tag: 1), sessionID: session, at: start) == .stored)
        let inside = start.addingTimeInterval(PointingSessionMemory.snapshotRetention - 1)
        #expect(memory.list(at: inside).snapshots.map(\.id) == [early])
        let expired = start.addingTimeInterval(PointingSessionMemory.snapshotRetention)
        #expect(memory.rememberSnapshot(id: later, bytes: payload(count: 2, tag: 8), sessionID: session, at: expired) == .stored)
        let listed = memory.list(at: expired)
        #expect(listed.snapshots.map(\.id) == [later])
        #expect(listed.sessions.map(\.id) == [session])
        #expect(memory.rememberSnapshot(id: early, bytes: payload(count: 2, tag: 3), sessionID: session, at: expired) == .stored)
        #expect(memory.list(at: expired).snapshots.map(\.id) == [early, later])
    }

    @Test func sessionsExpireAtTwentyFourHoursAndTakeTheirSnapshots() {
        var memory = PointingSessionMemory()
        let session = id(1)
        let snap = id(2)
        #expect(memory.beginSession(id: session, at: start) == .started)
        let captured = start.addingTimeInterval(PointingSessionMemory.sessionRetention - 30)
        #expect(memory.rememberSnapshot(id: snap, bytes: payload(count: 2, tag: 6), sessionID: session, at: captured) == .stored)
        let still = start.addingTimeInterval(PointingSessionMemory.sessionRetention - 1)
        let kept = memory.list(at: still)
        #expect(kept.sessions.map(\.id) == [session])
        #expect(kept.snapshots.map(\.id) == [snap])
        let due = start.addingTimeInterval(PointingSessionMemory.sessionRetention)
        let gone = memory.list(at: due)
        #expect(gone.sessions.isEmpty)
        #expect(gone.snapshots.isEmpty)
        #expect(memory.beginSession(id: session, at: due) == .started)
        #expect(memory.list(at: due).sessions.map(\.id) == [session])
    }

    @Test func endingASessionDropsOnlyItsSnapshots() {
        var memory = PointingSessionMemory()
        let ending = id(1)
        let staying = id(2)
        #expect(memory.beginSession(id: ending, at: start) == .started)
        #expect(memory.beginSession(id: staying, at: start) == .started)
        #expect(memory.rememberSnapshot(id: id(3), bytes: payload(count: 2, tag: 1), sessionID: ending, at: start) == .stored)
        #expect(memory.rememberSnapshot(id: id(4), bytes: payload(count: 2, tag: 2), sessionID: staying, at: start.addingTimeInterval(1)) == .stored)
        #expect(memory.endSession(ending, at: start.addingTimeInterval(-1)) == false)
        #expect(memory.list(at: start.addingTimeInterval(1)).snapshots.map(\.id) == [id(4), id(3)])
        let endedAt = start.addingTimeInterval(2)
        #expect(memory.endSession(ending, at: endedAt) == true)
        #expect(memory.endSession(ending, at: endedAt.addingTimeInterval(1)) == false)
        let listed = memory.list(at: endedAt.addingTimeInterval(1))
        #expect(listed.snapshots.map(\.id) == [id(4)])
        #expect(listed.snapshots.map(\.sessionID) == [staying])
        #expect(listed.sessions.map(\.id) == [staying, ending])
        #expect(listed.sessions.first { $0.id == ending }?.endedAt == endedAt)
        #expect(listed.sessions.first { $0.id == ending }?.isOpen == false)
        #expect(listed.sessions.first { $0.id == staying }?.isOpen == true)
        #expect(memory.rememberSnapshot(id: id(5), bytes: payload(count: 1, tag: 1), sessionID: ending, at: endedAt.addingTimeInterval(1)) == .rejectedNoSession)
    }

    @Test func quitAndDisableClearWithoutRestoringRows() {
        var memory = PointingSessionMemory()
        let session = id(1)
        #expect(memory.beginSession(id: session, at: start) == .started)
        #expect(memory.rememberSnapshot(id: id(2), bytes: payload(count: 2, tag: 1), sessionID: session, at: start) == .stored)
        memory.quit()
        #expect(memory.enabled)
        #expect(memory.list(at: start).sessions.isEmpty)
        #expect(memory.list(at: start).snapshots.isEmpty)
        #expect(memory.beginSession(id: session, at: start) == .started)

        var disabled = PointingSessionMemory(enabled: false)
        #expect(disabled.beginSession(id: id(3), at: start) == .rejectedDisabled)
        #expect(disabled.rememberSnapshot(id: id(4), bytes: payload(count: mebibyte + 1, tag: 1), sessionID: id(3), at: start) == .rejectedDisabled)
        disabled.enable()
        #expect(disabled.beginSession(id: id(3), at: start) == .started)

        var turnedOff = PointingSessionMemory()
        #expect(turnedOff.beginSession(id: id(5), at: start) == .started)
        #expect(turnedOff.rememberSnapshot(id: id(6), bytes: payload(count: 2, tag: 3), sessionID: id(5), at: start) == .stored)
        turnedOff.disable()
        #expect(turnedOff.enabled == false)
        #expect(turnedOff.list(at: start).sessions.isEmpty)
        #expect(turnedOff.list(at: start).snapshots.isEmpty)
        #expect(turnedOff.beginSession(id: id(5), at: start) == .rejectedDisabled)
        #expect(turnedOff.rememberSnapshot(id: id(6), bytes: payload(count: 2, tag: 3), sessionID: id(5), at: start) == .rejectedDisabled)
        turnedOff.enable()
        #expect(turnedOff.list(at: start).sessions.isEmpty)
        #expect(turnedOff.list(at: start).snapshots.isEmpty)
        #expect(turnedOff.beginSession(id: id(5), at: start) == .started)
        turnedOff.quit()
        #expect(turnedOff.enabled)
    }

    @Test func deleteRemovesOneSnapshotOrOneSession() {
        var memory = PointingSessionMemory()
        let first = id(1)
        let second = id(2)
        #expect(memory.beginSession(id: first, at: start) == .started)
        #expect(memory.beginSession(id: second, at: start.addingTimeInterval(1)) == .started)
        #expect(memory.rememberSnapshot(id: id(3), bytes: payload(count: 2, tag: 1), sessionID: first, at: start) == .stored)
        #expect(memory.rememberSnapshot(id: id(4), bytes: payload(count: 2, tag: 2), sessionID: first, at: start.addingTimeInterval(1)) == .stored)
        #expect(memory.rememberSnapshot(id: id(5), bytes: payload(count: 2, tag: 3), sessionID: second, at: start.addingTimeInterval(2)) == .stored)
        #expect(memory.delete(id: id(4), at: start.addingTimeInterval(2)) == true)
        #expect(memory.list(at: start.addingTimeInterval(2)).snapshots.map(\.id) == [id(5), id(3)])
        #expect(memory.delete(id: first, at: start.addingTimeInterval(2)) == true)
        let listed = memory.list(at: start.addingTimeInterval(2))
        #expect(listed.sessions.map(\.id) == [second])
        #expect(listed.snapshots.map(\.id) == [id(5)])
        #expect(memory.delete(id: id(9), at: start.addingTimeInterval(2)) == false)
        #expect(memory.list(at: start.addingTimeInterval(2)).snapshots.map(\.id) == [id(5)])
    }

    @Test func aSnapshotRequiresAnOpenSessionAndANewId() {
        var memory = PointingSessionMemory()
        let session = id(1)
        let snap = id(2)
        let bytes = payload(count: 3, tag: 8)
        #expect(memory.rememberSnapshot(id: snap, bytes: bytes, sessionID: session, at: start) == .rejectedNoSession)
        #expect(memory.beginSession(id: session, at: start) == .started)
        #expect(memory.beginSession(id: session, at: start.addingTimeInterval(1)) == .rejectedDuplicate)
        #expect(memory.list(at: start).sessions.map(\.startedAt) == [start])
        #expect(memory.rememberSnapshot(id: snap, bytes: bytes, sessionID: session, at: start) == .stored)
        #expect(memory.rememberSnapshot(id: snap, bytes: payload(count: 3, tag: 1), sessionID: session, at: start) == .rejectedDuplicate)
        #expect(memory.rememberSnapshot(id: session, bytes: bytes, sessionID: session, at: start) == .rejectedDuplicate)
        #expect(memory.list(at: start).snapshots.map(\.bytes) == [bytes])
        #expect(memory.beginSession(id: snap, at: start) == .rejectedDuplicate)
    }

    @Test func aNonFiniteClockDoesNotAdmitOrErase() {
        var memory = PointingSessionMemory()
        let session = id(1)
        let snap = id(2)
        let bytes = payload(count: 3, tag: 9)
        #expect(memory.beginSession(id: session, at: start) == .started)
        #expect(memory.rememberSnapshot(id: snap, bytes: bytes, sessionID: session, at: start) == .stored)
        let nan = Date(timeIntervalSince1970: .nan)
        let infinite = Date(timeIntervalSince1970: .infinity)
        #expect(memory.beginSession(id: id(3), at: nan) == .rejectedClock)
        #expect(memory.rememberSnapshot(id: id(4), bytes: bytes, sessionID: session, at: infinite) == .rejectedClock)
        #expect(memory.endSession(session, at: nan) == false)
        #expect(memory.delete(id: snap, at: infinite) == false)
        let listed = memory.list(at: nan)
        #expect(listed.sessions.map(\.id) == [session])
        #expect(listed.sessions.map(\.isOpen) == [true])
        #expect(listed.snapshots.map(\.id) == [snap])
        #expect(listed.snapshots.map(\.bytes) == [bytes])
    }
}
