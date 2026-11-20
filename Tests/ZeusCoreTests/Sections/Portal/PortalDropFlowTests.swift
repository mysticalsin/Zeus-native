import Foundation
import Testing
@testable import ZeusCore

@Suite("Portal drop conversion")
struct PortalDropFlowTests {
    @Test func portalSectionAddsNoKey() {
        let slot = PortalSectionSlot.descriptor
        #expect(slot.id == "glass.portal")
        #expect(slot.title == "Portal")
        #expect(slot.filled == true)
        #expect(slot.keys.isEmpty)
        #expect(slot.order == 120)
        #expect(PortalDevices.existingKeys == [
            "fling.enabled", "fling.receiveInBackground", "fling.deviceName", "fling.visibility",
            "fling.autoAcceptPaired", "fling.saveMode", "fling.papers", "fling.flickSensitivity",
            "fling.openLinks", "fling.pairedMacs",
        ])
        #expect(PortalSectionMetrics.topbarTab == 8)
        #expect(PortalSectionMetrics.panelPadding == 32)
        #expect(PortalSectionMetrics.cardSpacing == 28)
        #expect(PortalSectionMetrics.rowHeight == 52)
    }

    @Test func phasesAreTheFiveNamedStates() throws {
        let admitted = try #require(try PortalFileGate.decide(PortalFixtures.claim()).get())
        let names = [
            PortalPhaseName.name(.idle),
            PortalPhaseName.name(.received(admitted)),
            PortalPhaseName.name(.converting(admitted)),
            PortalPhaseName.name(.done(PortalFixtures.output())),
            PortalPhaseName.name(.failed(.empty)),
        ]
        #expect(names == ["idle", "received", "converting", "done", "failed"])
    }

    @Test func aSoundDropReachesDoneOnlyThroughTheNamedPhases() {
        var flow = PortalDropFlow()
        #expect(flow.phase == .idle)
        #expect(flow.receive(.success(PortalFixtures.claim(size: 4))) == .applied)
        guard case .received(let admitted) = flow.phase else {
            Issue.record("expected received, got \(flow.phase)")
            return
        }
        #expect(admitted.type == .plainText)
        #expect(admitted.outputKind == .utf8Text)
        #expect(flow.begin() == .applied)
        guard case .converting = flow.phase else {
            Issue.record("expected converting")
            return
        }
        #expect(flow.finish(.success(PortalFixtures.output())) == .applied)
        #expect(flow.phase == .done(PortalFixtures.output()))
    }

    @Test func aRejectedDropFailsWithoutConverting() {
        var flow = PortalDropFlow()
        #expect(flow.receive(.success(PortalFixtures.claim(symlink: true))) == .applied)
        #expect(flow.phase == .failed(.symlink))
        #expect(flow.begin() == .refused)
        #expect(flow.phase == .failed(.symlink))
    }

    @Test func anIntakeFailureIsFailed() {
        var flow = PortalDropFlow()
        #expect(flow.receive(.failure(.tooLarge)) == .applied)
        #expect(flow.phase == .failed(.tooLarge))
    }

    @Test func illegalEventsLeaveThePhaseAlone() throws {
        let admitted = try #require(try PortalFileGate.decide(PortalFixtures.claim()).get())
        let done = PortalFixtures.output()
        let samples: [(String, PortalDropFlow.Phase)] = [
            ("idle", .idle),
            ("received", .received(admitted)),
            ("converting", .converting(admitted)),
            ("done", .done(done)),
            ("failed", .failed(.empty)),
        ]
        for (label, phase) in samples {
            var flow = PortalDropFlow(phase)
            let before = flow.phase
            let begin = flow.begin()
            if label == "received" {
                #expect(begin == .applied)
            } else {
                #expect(begin == .refused)
                #expect(flow.phase == before)
            }
        }
    }

    @Test func everyEventMatchesTheTransitionTable() throws {
        let claim = PortalFixtures.claim()
        let admitted = try #require(try PortalFileGate.decide(claim).get())
        let output = PortalFixtures.output()
        let states: [PortalDropFlow.Phase] = [
            .idle, .received(admitted), .converting(admitted), .done(output), .failed(.symlink),
        ]
        for state in states {
            try expect(PortalDropFlow(state), event: .receiveGood, becomes: state == .idle ? .received(admitted) : nil)
            try expect(PortalDropFlow(state), event: .receiveBad, becomes: state == .idle ? .failed(.symlink) : nil)
            try expect(PortalDropFlow(state), event: .begin, becomes: state == .received(admitted) ? .converting(admitted) : nil)
            try expect(PortalDropFlow(state), event: .succeed, becomes: state == .converting(admitted) ? .done(output) : nil)
            try expect(PortalDropFlow(state), event: .fail, becomes: state == .converting(admitted) ? .failed(.invalidContents) : nil)
            let resetTarget: PortalDropFlow.Phase? = {
                switch state {
                case .idle, .done, .failed: return .idle
                case .received, .converting: return nil
                }
            }()
            try expect(PortalDropFlow(state), event: .reset, becomes: resetTarget)
            let cancelTarget: PortalDropFlow.Phase? = {
                switch state {
                case .received, .converting: return .idle
                default: return nil
                }
            }()
            try expect(PortalDropFlow(state), event: .cancel, becomes: cancelTarget)
        }
    }

    @Test func finishGuardsThePayload() throws {
        let admitted = try #require(try PortalFileGate.decide(PortalFixtures.claim()).get())
        var empty = PortalDropFlow(.converting(admitted))
        #expect(empty.finish(.success(PortalFixtures.output(bytes: Data()))) == .applied)
        #expect(empty.phase == .failed(.invalidContents))

        var huge = PortalDropFlow(.converting(admitted))
        #expect(huge.finish(.success(PortalFixtures.output(bytes: Data(count: PortalLimits.maxConversionBytes + 1)))) == .applied)
        #expect(huge.phase == .failed(.outputTooLarge))

        var named = PortalDropFlow(.converting(admitted))
        #expect(named.finish(.success(PortalFixtures.output(name: "../note.txt"))) == .applied)
        #expect(named.phase == .failed(.unsafeName))

        var kind = PortalDropFlow(.converting(admitted))
        #expect(kind.finish(.success(PortalFixtures.output(name: "note.png", kind: .png))) == .applied)
        #expect(kind.phase == .failed(.typeMismatch))
    }

    @Test func cancelDropsTheFileAndResetClearsAnError() {
        var flow = PortalDropFlow()
        #expect(flow.receive(.success(PortalFixtures.claim())) == .applied)
        #expect(flow.cancel() == .applied)
        #expect(flow.phase == .idle)
        #expect(flow.begin() == .refused)
        #expect(flow.receive(.failure(.trayFull)) == .applied)
        #expect(flow.reset() == .applied)
        #expect(flow.phase == .idle)
        #expect(flow.receive(.success(PortalFixtures.claim())) == .applied)
    }

    @Test func aNewDropWhileBusyIsRefusedAndAFinishedDropCanStartAgain() {
        var busy = PortalDropFlow()
        _ = busy.receive(.success(PortalFixtures.claim()))
        #expect(PortalDropCommand.drop(.success(PortalFixtures.claim(name: "other.txt")), on: &busy) == .refused)
        guard case .received = busy.phase else {
            Issue.record("busy drop changed phase")
            return
        }
        var failed = PortalDropFlow()
        _ = failed.receive(.failure(.empty))
        #expect(PortalDropCommand.drop(.success(PortalFixtures.claim()), on: &failed) == .applied)
        guard case .received = failed.phase else {
            Issue.record("expected a fresh receive after failure")
            return
        }
    }

    @Test func theSessionConvertsTextAndStopsOnABadClaim() {
        let bytes = Data("A\r\nB".utf8)
        let claim = PortalFixtures.claim(size: Int64(bytes.count))
        let done = PortalDropSession.run(claim: .success(claim), bytes: bytes)
        #expect(done.phase == .done(PortalConversionOutput(fileName: "note.txt", bytes: Data("A\nB".utf8), kind: .utf8Text)))

        let rejected = PortalDropSession.run(claim: .success(PortalFixtures.claim(size: 0)), bytes: Data())
        #expect(rejected.phase == .failed(.empty))
        let mismatch = PortalDropSession.run(claim: .success(claim), bytes: Data("ABC".utf8))
        #expect(mismatch.phase == .failed(.sizeMismatch))
    }

    private enum Event {
        case receiveGood, receiveBad, begin, succeed, fail, reset, cancel
    }

    private func expect(_ start: PortalDropFlow, event: Event, becomes expected: PortalDropFlow.Phase?) throws {
        var flow = start
        let before = flow.phase
        let step: PortalStep
        switch event {
        case .receiveGood: step = flow.receive(.success(PortalFixtures.claim()))
        case .receiveBad: step = flow.receive(.success(PortalFixtures.claim(symlink: true)))
        case .begin: step = flow.begin()
        case .succeed: step = flow.finish(.success(PortalFixtures.output()))
        case .fail: step = flow.finish(.failure(.invalidContents))
        case .reset: step = flow.reset()
        case .cancel: step = flow.cancel()
        }
        if let expected {
            #expect(step == .applied)
            #expect(flow.phase == expected)
        } else {
            #expect(step == .refused)
            #expect(flow.phase == before)
        }
    }
}
