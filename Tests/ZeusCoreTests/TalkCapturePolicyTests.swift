import CoreGraphics
import Foundation
import Testing
@testable import ZeusCore

@Suite struct TalkCapturePolicyTests {
    private let left = TalkCapturePolicy.Display(id: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900))
    private let right = TalkCapturePolicy.Display(id: 2, frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080))

    @Test func seeingOffCapturesNothing() {
        let ids = TalkCapturePolicy.displayIDs(seeing: false, pointer: CGPoint(x: 100, y: 100), displays: [left, right])
        #expect(ids.isEmpty)
    }

    @Test func seeingOnCapturesOnlyTheDisplayUnderThePointer() {
        let onRight = TalkCapturePolicy.displayIDs(seeing: true, pointer: CGPoint(x: 1500, y: 40), displays: [left, right])
        #expect(onRight == [right.id])
        let onLeft = TalkCapturePolicy.displayIDs(seeing: true, pointer: CGPoint(x: 20, y: 20), displays: [left, right])
        #expect(onLeft == [left.id])
        #expect(onRight != [left.id, right.id])
    }

    @Test func aPointerOnNoDisplayCapturesNothing() {
        let ids = TalkCapturePolicy.displayIDs(seeing: true, pointer: CGPoint(x: -10, y: -10), displays: [left, right])
        #expect(ids.isEmpty)
    }

    @Test func aShotReadyAt80msWithTheFinalAt200msMayBeIncluded() {
        let decision = TalkCapturePolicy.decision(shotReadyMs: 80, sttFinalMs: 200, capMs: 450)
        #expect(decision.includeShot)
        #expect(decision.speechStarts)
        #expect(!decision.lateRelativeToCap)
    }

    @Test func the50msBoundaryIncludes399AndDrops400() {
        let inside = TalkCapturePolicy.decision(shotReadyMs: 399, sttFinalMs: nil, capMs: 450)
        #expect(TalkCapturePolicy.speechWaitBoundMs == 400)
        #expect(!inside.lateRelativeToCap)
        #expect(inside.includeShot)
        #expect(inside.speechStarts)
        let edge = TalkCapturePolicy.decision(shotReadyMs: 400, sttFinalMs: 450, capMs: 450)
        #expect(edge.lateRelativeToCap)
        #expect(!edge.includeShot)
    }

    @Test func aShotAfterTheTranscriptFinalIsLeftOut() {
        let after = TalkCapturePolicy.decision(shotReadyMs: 300, sttFinalMs: 200, capMs: 450)
        #expect(!after.includeShot)
        #expect(after.speechStarts)
        let before = TalkCapturePolicy.decision(shotReadyMs: 150, sttFinalMs: 200, capMs: 450)
        #expect(before.includeShot)
        #expect(!before.lateRelativeToCap)
    }

    @Test func aShotReadyAt400msAgainstThe450msCapIsLeftOutAndSpeechStillStarts() {
        let decision = TalkCapturePolicy.decision(shotReadyMs: 400, sttFinalMs: nil, capMs: 450)
        #expect(decision.lateRelativeToCap)
        #expect(!decision.includeShot)
        #expect(decision.speechStarts)
    }

    @Test func overlapKeepsOneDisplayAndTheSeamBelongsToTheNextDisplay() {
        let back = TalkCapturePolicy.Display(id: 7, frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        let front = TalkCapturePolicy.Display(id: 8, frame: CGRect(x: 50, y: 0, width: 100, height: 100))
        let overlap = TalkCapturePolicy.displayIDs(seeing: true, pointer: CGPoint(x: 60, y: 10), displays: [back, front])
        #expect(overlap == [front.id])
        let seam = TalkCapturePolicy.displayIDs(seeing: true, pointer: CGPoint(x: 1440, y: 10), displays: [left, right])
        #expect(seam == [right.id])
        let justInsideLeft = TalkCapturePolicy.displayIDs(seeing: true, pointer: CGPoint(x: 1439, y: 10), displays: [left, right])
        #expect(justInsideLeft == [left.id])
    }

    @Test func aSlowShotIsDroppedAtTheBoundAndSpeechStillStarts() {
        let outcome = TalkCapturePolicy.waitOutcome(shotReadyMs: 800, sttFinalMs: nil, capMs: 450)
        #expect(TalkCapturePolicy.speechWaitBoundMs == 400)
        #expect(!outcome.includeShot)
        #expect(outcome.waitedMs == 400)
        #expect(outcome.waitedMs < 800)
        #expect(outcome.speechStarts)
    }

    @Test func seeingOffAndUnplugDropTheArmedFrameImmediately() {
        var session = TalkCaptureSession()
        let turn = UUID()
        session.begin(turnID: turn, seeing: true, pointer: CGPoint(x: 20, y: 20), displays: [left, right])
        let frame = session.frameID!
        let offer = TalkCaptureSession.Offer(turnID: turn, frameID: frame, displayID: left.id, shotReadyMs: 80, sttFinalMs: 200)
        #expect(session.accept(offer).includeShot)
        session.setSeeing(false)
        #expect(session.displayIDs().isEmpty)
        #expect(!session.accept(offer).includeShot)
        #expect(session.accept(offer).speechStarts)
        session.setSeeing(true)
        session.begin(turnID: turn, seeing: true, pointer: CGPoint(x: 20, y: 20), displays: [left, right])
        let again = session.frameID!
        let live = TalkCaptureSession.Offer(turnID: turn, frameID: again, displayID: left.id, shotReadyMs: 80, sttFinalMs: 200)
        session.unplug(left.id)
        #expect(!session.accept(live).includeShot)
    }

    @Test func aStaleTurnOrFrameIsNotIncluded() {
        var session = TalkCaptureSession()
        let turn = UUID()
        session.begin(turnID: turn, seeing: true, pointer: CGPoint(x: 20, y: 20), displays: [left, right])
        let frame = session.frameID!
        let otherTurn = TalkCaptureSession.Offer(turnID: UUID(), frameID: frame, displayID: left.id, shotReadyMs: 80, sttFinalMs: 200)
        let otherFrame = TalkCaptureSession.Offer(turnID: turn, frameID: UUID(), displayID: left.id, shotReadyMs: 80, sttFinalMs: 200)
        #expect(!session.accept(otherTurn).includeShot)
        #expect(!session.accept(otherFrame).includeShot)
        #expect(session.accept(otherTurn).speechStarts)
    }
}
