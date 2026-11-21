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

    @Test func aShotReadyAt400msAgainstThe450msCapIsLeftOutAndSpeechStillStarts() {
        let decision = TalkCapturePolicy.decision(shotReadyMs: 400, sttFinalMs: nil, capMs: 450)
        #expect(decision.lateRelativeToCap)
        #expect(!decision.includeShot)
        #expect(decision.speechStarts)
    }
}
