import Foundation
import Testing
@testable import ZeusCore

@Suite("Guide preview")
struct GuidePreviewTests {
    private func rect(
        _ x: Double = 40, _ y: Double = 80, _ width: Double = 120, _ height: Double = 32
    ) -> GuidePreview.Rect {
        GuidePreview.Rect(x: x, y: y, width: width, height: height)
    }

    private func preview(_ kind: GuidePreview.Kind = .type, at now: TimeInterval = 10) -> GuidePreview {
        var guide = GuidePreview()
        let mark = guide.reveal(kind, rect: rect(), at: now)
        #expect(mark == .revealed)
        return guide
    }

    @Test func theIdleBudgetIsFortyFiveSeconds() {
        #expect(GuidePreview.idleBudget == 45)
    }

    @Test func aTypeStepRevealsAPreviewAndDoesNotFinish() {
        var guide = GuidePreview()
        let mark = guide.reveal(.type, rect: rect(), at: 10)
        #expect(mark == .revealed)
        #expect(mark != .advanced)
        #expect(guide.phase == .preview)
        #expect(guide.kind == .type)
        #expect(guide.revealedAt == 10)
    }

    @Test func aWaitStepRevealsAPreviewAndDoesNotFinish() {
        var guide = GuidePreview()
        let mark = guide.reveal(.wait, rect: rect(), at: 3)
        #expect(mark == .revealed)
        #expect(guide.phase == .preview)
        #expect(guide.kind == .wait)
        #expect(guide.phase != .advanced)
    }

    @Test func aClickStepDoesNotEnterPreview() {
        var guide = GuidePreview()
        let mark = guide.reveal(.click, rect: rect(), at: 10)
        #expect(mark == .waiting)
        #expect(guide.phase == .idle)
        #expect(guide.kind == nil)
        #expect(guide.rect == nil)
        let click = guide.click(GuidePreview.Point(x: 50, y: 90), at: 11)
        #expect(click == .waiting)
        #expect(guide.phase == .idle)
    }

    @Test func aClickInsideTheRectangleFinishesThePreview() {
        var guide = preview()
        let mark = guide.click(GuidePreview.Point(x: 50, y: 90), at: 12)
        #expect(mark == .advanced)
        #expect(guide.phase == .advanced)
    }

    @Test func theNearCornerIsInsideAndTheFarEdgeIsOutside() {
        var inside = preview()
        let hit = inside.click(GuidePreview.Point(x: 40, y: 80), at: 11)
        #expect(hit == .advanced)
        var outside = preview()
        let farX = outside.click(GuidePreview.Point(x: 160, y: 90), at: 11)
        #expect(farX == .stayed)
        #expect(outside.phase == .preview)
        let farY = outside.click(GuidePreview.Point(x: 50, y: 112), at: 11)
        #expect(farY == .stayed)
        #expect(outside.phase == .preview)
    }

    @Test func aClickOutsideStaysInPreview() {
        var guide = preview()
        let mark = guide.click(GuidePreview.Point(x: 0, y: 0), at: 20)
        #expect(mark == .stayed)
        #expect(guide.phase == .preview)
    }

    @Test func aSecondClickDoesNotFinishTheStepAgain() {
        var guide = preview()
        let point = GuidePreview.Point(x: 50, y: 90)
        #expect(guide.click(point, at: 12) == .advanced)
        #expect(guide.click(point, at: 12.2) == .waiting)
        #expect(guide.phase == .advanced)
        #expect(guide.tick(at: 80) == .waiting)
        #expect(guide.phase == .advanced)
    }

    @Test func aClockBeforeTheBudgetStaysInPreview() {
        var guide = preview(.wait, at: 100)
        for now in [100.0, 101.0, 120.0, 144.0] {
            let mark = guide.tick(at: now)
            #expect(mark == .stayed)
            #expect(mark != .advanced)
            #expect(guide.phase == .preview)
        }
        let almost = guide.tick(at: 100 + GuidePreview.idleBudget - 1)
        #expect(almost == .stayed)
        #expect(guide.phase == .preview)
    }

    @Test func theIdleBudgetCancelsAndDoesNotFinish() {
        var guide = preview(.type, at: 100)
        let mark = guide.tick(at: 100 + GuidePreview.idleBudget)
        #expect(mark == .cancelled)
        #expect(mark != .advanced)
        #expect(guide.phase == .cancelled)
        let later = guide.click(GuidePreview.Point(x: 50, y: 90), at: 200)
        #expect(later == .waiting)
        #expect(guide.phase == .cancelled)
    }

    @Test func aClickAfterTheBudgetCancelsInsteadOfFinishing() {
        var guide = preview(.wait, at: 0)
        let mark = guide.click(GuidePreview.Point(x: 50, y: 90), at: GuidePreview.idleBudget)
        #expect(mark == .cancelled)
        #expect(guide.phase == .cancelled)
    }

    @Test func aFlatOrNonFiniteRectangleIsRefused() {
        var guide = GuidePreview()
        let flat = guide.reveal(.type, rect: rect(40, 80, 0, 32), at: 1)
        #expect(flat == .waiting)
        #expect(guide.phase == .idle)
        let broken = GuidePreview.Rect(x: .infinity, y: 1, width: 4, height: 4)
        #expect(guide.reveal(.wait, rect: broken, at: 1) == .waiting)
        #expect(guide.phase == .idle)
        #expect(guide.reveal(.type, rect: rect(), at: .nan) == .waiting)
        #expect(guide.phase == .idle)
    }

    @Test func aNegativeOriginStillAcceptsAClickInside() {
        var guide = GuidePreview()
        let area = GuidePreview.Rect(x: -1200, y: 20, width: 40, height: 18)
        #expect(guide.reveal(.type, rect: area, at: 5) == .revealed)
        let mark = guide.click(GuidePreview.Point(x: -1190, y: 30), at: 6)
        #expect(mark == .advanced)
        #expect(guide.rect?.x == -1200)
    }

    @Test func aNonFiniteClockOrPointDoesNotFinishOrCancel() {
        var guide = preview(.type, at: 10)
        #expect(guide.tick(at: .nan) == .stayed)
        #expect(guide.tick(at: 9) == .stayed)
        #expect(guide.click(GuidePreview.Point(x: .infinity, y: 90), at: 11) == .stayed)
        #expect(guide.phase == .preview)
        #expect(guide.click(GuidePreview.Point(x: 50, y: 90), at: .nan) == .stayed)
        #expect(guide.phase == .preview)
    }

    @Test func aSecondRevealDoesNotReplaceThePreview() {
        var guide = preview(.type, at: 10)
        let other = GuidePreview.Rect(x: 1, y: 1, width: 8, height: 8)
        #expect(guide.reveal(.wait, rect: other, at: 12) == .waiting)
        #expect(guide.kind == .type)
        #expect(guide.rect == rect())
        #expect(guide.revealedAt == 10)
        #expect(guide.phase == .preview)
    }
}
