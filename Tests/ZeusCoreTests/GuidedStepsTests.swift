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
        tour.click(at: CGPoint(x: 120, y: 110))
        #expect(tour.progress == "Step 2 of 3")
        #expect(tour.target?.label == "Next")
    }

    @Test func step16IsRefused() {
        let one = target(rect: CGRect(x: 0, y: 0, width: 20, height: 20), label: "Item")
        let steps = (1...16).map { GuidedSteps.Step(say: "Step \($0)", target: one) }
        #expect(GuidedSteps(steps: steps) == nil)
        let legal = (1...15).map { GuidedSteps.Step(say: "Step \($0)", target: one) }
        #expect(GuidedSteps(steps: legal) != nil)
    }

    @Test func cancelClearsTheTarget() {
        var tour = threeSteps()
        #expect(tour.target != nil)
        tour.cancel()
        #expect(tour.target == nil)
    }
}
