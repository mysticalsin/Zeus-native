import CoreGraphics
import Foundation
import Testing
@testable import ZeusCore

@Suite struct GuidedStepsTests {
    private func target(rect: CGRect, label: String) -> GuidedPresent.ResolvedTarget {
        GuidedPresent.ResolvedTarget(
            screenPoint: CGPoint(x: rect.midX, y: rect.midY),
            label: label,
            waitForClick: true,
            hitRect: rect
        )
    }

    private func threeSteps() -> GuidedSteps {
        let first = target(rect: CGRect(x: 100, y: 100, width: 80, height: 40), label: "Save")
        let second = target(rect: CGRect(x: 300, y: 200, width: 80, height: 40), label: "Next")
        let third = target(rect: CGRect(x: 500, y: 300, width: 80, height: 40), label: "Done")
        return GuidedSteps(steps: [
            .init(say: "Tap Save", target: first),
            .init(say: "Tap Next", target: second),
            .init(say: "Tap Done", target: third),
        ])!
    }

    @Test func aClickOutsideTheRectDoesNotAdvanceStep1Of3() {
        var tour = threeSteps()
        #expect(tour.progress == "Step 1 of 3")
        tour.click(at: CGPoint(x: 10, y: 10))
        #expect(tour.progress == "Step 1 of 3")
        #expect(tour.target?.label == "Save")
    }

    @Test func aClickInsideTheRectAdvancesAndReadsStep2Of3() {
        var tour = threeSteps()
        tour.click(at: CGPoint(x: 10, y: 10))
        #expect(tour.index == 0)
        #expect(tour.progress == "Step 1 of 3")
        tour.click(at: CGPoint(x: 120, y: 110))
        #expect(tour.index == 1)
        #expect(tour.progress == "Step 2 of 3")
        #expect(tour.target?.label == "Next")
        tour.click(at: CGPoint(x: 320, y: 210))
        #expect(tour.index == 2)
        #expect(tour.progress == "Step 3 of 3")
        #expect(tour.accessibilityLabel == "Step 3 of 3, Done")
    }

    @Test func aDoubleClickDoesNotSkipAndADragDoesNotAdvance() {
        let rect = CGRect(x: 100, y: 100, width: 80, height: 40)
        let steps = (0..<3).map { GuidedSteps.Step(say: "S\($0)", target: target(rect: rect, label: "B\($0)")) }
        var tour = GuidedSteps(steps: steps)!
        tour.click(at: CGPoint(x: 120, y: 110), count: 2, pressedAt: CGPoint(x: 120, y: 110))
        #expect(tour.index == 1)
        var dragged = threeSteps()
        dragged.click(at: CGPoint(x: 130, y: 120), count: 1, pressedAt: CGPoint(x: 130, y: 160))
        #expect(dragged.index == 0)
        dragged.click(at: CGPoint(x: 122, y: 112), count: 1, pressedAt: CGPoint(x: 120, y: 110))
        #expect(dragged.index == 1)
    }

    @Test func theHitRectIsReadWhenTheClickArrives() {
        var tour = threeSteps()
        let moved = CGRect(x: 800, y: 800, width: 40, height: 40)
        tour.setRect(moved, forStep: 0)
        tour.click(at: CGPoint(x: 120, y: 110))
        #expect(tour.index == 0)
        tour.click(at: CGPoint(x: 810, y: 810))
        #expect(tour.index == 1)
        #expect(tour.accessibilityLabel == "Step 2 of 3, Next")
    }

    @Test func clickHitsIncludesTheMaxEdgeAndScalesA2xPoint() {
        let rect = CGRect(x: 10, y: 20, width: 30, height: 40)
        let hit = GuidedPresent.ResolvedTarget(screenPoint: CGPoint(x: 25, y: 40), label: "Edge", waitForClick: true, hitRect: rect)
        #expect(GuidedPresent.clickHits(CGPoint(x: 40, y: 20), target: hit))
        #expect(GuidedPresent.clickHits(CGPoint(x: 10, y: 60), target: hit))
        #expect(!GuidedPresent.clickHits(CGPoint(x: 40.2, y: 20), target: hit, scale: 1))
        #expect(GuidedPresent.clickHits(CGPoint(x: 50, y: 80), target: hit, scale: 2))
        #expect(!GuidedPresent.clickHits(CGPoint(x: 50, y: 80), target: hit, scale: 1))
        #expect(GuidedPresent.clickHits(CGPoint(x: 81, y: 40), target: hit, scale: 2))
        #expect(!GuidedPresent.clickHits(CGPoint(x: 84, y: 40), target: hit, scale: 2))
    }

    @Test func step16IsRefused() {
        let one = target(rect: CGRect(x: 0, y: 0, width: 20, height: 20), label: "Item")
        let steps = (1...16).map { GuidedSteps.Step(say: "Step \($0)", target: one) }
        #expect(GuidedSteps(steps: steps) == nil)
        let legal = (1...15).map { GuidedSteps.Step(say: "Step \($0)", target: one) }
        #expect(GuidedSteps(steps: legal) != nil)
    }

    @Test func aClickInsideTheLastStepClearsTheTarget() {
        var tour = threeSteps()
        tour.move(to: 2)
        #expect(tour.index == 2)
        #expect(tour.target?.label == "Done")
        tour.click(at: CGPoint(x: 520, y: 310))
        #expect(tour.index == 2)
        #expect(tour.target == nil)
    }

    @Test func cancelClearsTheTarget() {
        var tour = threeSteps()
        #expect(tour.target != nil)
        tour.cancel()
        #expect(tour.target == nil)
    }
}
