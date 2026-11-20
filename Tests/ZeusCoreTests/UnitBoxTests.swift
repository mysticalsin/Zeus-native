import Foundation
import Testing
@testable import ZeusCore

private struct SplitMix {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    mutating func signed() -> Double { unit() * 8 - 4 }
}

@Suite("Unit box mark geometry")
struct UnitBoxTests {
    @Test func rectCircleSegmentAndLabelBoundsMatchTheMarkRules() {
        #expect(UnitBox.rect(x: 0.2, y: 0.3, width: 0.4, height: 0.5) == UnitBox(x: 0.2, y: 0.3, width: 0.4, height: 0.5))
        #expect(UnitBox.circle(centerX: 0.5, centerY: 0.4, radius: 0.1) == UnitBox(x: 0.4, y: 0.3, width: 0.2, height: 0.2))
        let flat = UnitBox.segment(x0: 0.1, y0: 0.2, x1: 0.7, y1: 0.2)
        #expect(flat == UnitBox(x: 0.1, y: 0.2, width: 0.6, height: 0).insetBy(dx: -0.01, dy: -0.01))
        let short = UnitBox.label(characterCount: 1, x: 0.5, y: 0.5)
        #expect(short.width == 0.03)
        #expect(short == UnitBox(x: 0.5 - 0.015, y: 0.48, width: 0.03, height: 0.04))
        let wide = UnitBox.label(characterCount: 2, x: 0.5, y: 0.5)
        #expect(wide.width == 0.036)
        let plain = UnitBox.math(spokenCount: 4, hasNumerator: false, x: 0.5, y: 0.5)
        #expect(plain.width == 0.08 && plain.height == 0.05)
        let fraction = UnitBox.math(spokenCount: 6, hasNumerator: true, x: 0.5, y: 0.5)
        #expect(fraction.width == 0.096 && fraction.height == 0.09)
    }

    @Test func anEmptyPathHasNoBoxAndOnePointExpandsByOneHundredth() {
        #expect(UnitBox.path([]) == nil)
        let point = UnitBox(x: 1, y: 2, width: 0, height: 0).insetBy(dx: -0.01, dy: -0.01)
        #expect(UnitBox.path([UnitSample(x: 1, y: 2)]) == point)
        let span = UnitBox.path([UnitSample(x: 1, y: 2), UnitSample(x: 4, y: 6)])
        let united = UnitBox(x: 1, y: 2, width: 0, height: 0).union(UnitBox(x: 4, y: 6, width: 0, height: 0))
        #expect(span == united.insetBy(dx: -0.01, dy: -0.01))
    }

    @Test func unionInsetAndContainsFollowTheRectangleEdges() {
        let box = UnitBox(x: 0, y: 0, width: 1, height: 1)
        #expect(box.contains(x: 0, y: 0))
        #expect(box.contains(x: 0.999, y: 0.5))
        #expect(!box.contains(x: 1, y: 0))
        #expect(!box.contains(x: 1, y: 1))
        #expect(!box.contains(x: -0.001, y: 0))
        #expect(!UnitBox(x: 1, y: 2, width: 0, height: 0).contains(x: 1, y: 2))
        #expect(box.insetBy(dx: 0, dy: 0) == box)
        #expect(box.insetBy(dx: 0.6, dy: 0.1).isNull)
        #expect(UnitBox.null.insetBy(dx: -0.01, dy: -0.01).isNull)
        #expect(UnitBox.null.union(box) == box)
        #expect(box.union(.null) == box)
        #expect(UnitBox.null.union(.null).isNull)
        let negative = UnitBox(x: 5, y: 5, width: -2, height: 3)
        #expect(negative.contains(x: 4, y: 6))
        #expect(!negative.contains(x: 5, y: 6))
        #expect(negative.contains(x: 3, y: 6))
        #expect(negative.union(UnitBox(x: 0, y: 0, width: 1, height: 1)) == UnitBox(x: 0, y: 0, width: 5, height: 8))
    }

    @Test func overlapSamplesTheSegmentAndMissesAGapBetweenSamples() {
        let through = UnitBox(x: -0.1, y: -0.1, width: 0.2, height: 0.2)
        #expect(through.hitsSegment(UnitSegment(x0: 0, y0: 0, x1: 1, y1: 0)))
        let gap = UnitBox(x: 0.01, y: -0.1, width: 0.02, height: 0.2)
        #expect(!gap.hitsSegment(UnitSegment(x0: 0, y0: 0, x1: 1, y1: 0)))
        let stroke = UnitStroke.segment(UnitSegment(x0: 0, y0: 0, x1: 1, y1: 0))
        let label = UnitBox(x: 0, y: -0.02, width: 0.1, height: 0.04)
        #expect(label.overlaps(stroke))
        #expect(!UnitBox.null.overlaps(stroke))
        #expect(!label.overlaps(.path([])))
    }

    @Test func labelNudgeStopsWhenClearAndCapsAtEightSteps() {
        let start = UnitBox(x: 0.2, y: -0.02, width: 0.1, height: 0.04)
        let stroke = UnitStroke.segment(UnitSegment(x0: 0, y0: 0, x1: 1, y1: 0))
        let cleared = LabelNudge.place(start) { $0.overlaps(stroke) }
        guard case .settled(let box) = cleared else {
            Issue.record("expected a settled box, got \(cleared)")
            return
        }
        #expect(box.y == start.y + LabelNudge.dy * 2)

        var calls = 0
        let capped = LabelNudge.place(start) { _ in
            calls += 1
            return true
        }
        #expect(calls == LabelNudge.maxSteps)
        guard case .capped(let stuck) = capped else {
            Issue.record("expected a capped box, got \(capped)")
            return
        }
        var added = start.y
        for _ in 0..<LabelNudge.maxSteps { added += LabelNudge.dy }
        #expect(stuck.y == added)
        #expect(stuck.x == start.x && stuck.width == start.width && stuck.height == start.height)
    }

    @Test func nudgeTransitionsAreGuarded() {
        let box = UnitBox(x: 1, y: 2, width: 3, height: 4)
        #expect(LabelNudge.reduce(.checking(step: 0, box: box), .clear) == .settled(box))
        let once = LabelNudge.reduce(.checking(step: 0, box: box), .overlapped)
        #expect(once == .checking(step: 1, box: box.offsetBy(dx: 0, dy: LabelNudge.dy)))
        let atLimit = box.offsetBy(dx: 0, dy: LabelNudge.dy * 8)
        let checkingLimit = LabelNudge.State.checking(step: LabelNudge.maxSteps, box: atLimit)
        #expect(LabelNudge.reduce(checkingLimit, .overlapped) == .capped(atLimit))
        #expect(LabelNudge.reduce(checkingLimit, .clear) == .settled(atLimit))
        let settled = LabelNudge.State.settled(box)
        let capped = LabelNudge.State.capped(atLimit)
        #expect(LabelNudge.reduce(settled, .overlapped) == settled)
        #expect(LabelNudge.reduce(settled, .clear) == settled)
        #expect(LabelNudge.reduce(capped, .clear) == capped)
        #expect(LabelNudge.reduce(capped, .overlapped) == capped)
    }

    @Test func randomBoxesKeepUnionAndInsetInvariants() {
        var rng = SplitMix(state: 0xC0FFEE)
        for _ in 0..<200 {
            let a = UnitBox(x: rng.signed(), y: rng.signed(), width: rng.signed(), height: rng.signed())
            let b = UnitBox(x: rng.signed(), y: rng.signed(), width: rng.signed(), height: rng.signed())
            let c = UnitBox(x: rng.signed(), y: rng.signed(), width: rng.signed(), height: rng.signed())
            #expect(a.union(b) == b.union(a))
            #expect(a.union(b).union(c) == a.union(b.union(c)))
            #expect(a.union(.null) == a)
            #expect(UnitBox.null.union(a) == a)
            if a.width > 0, a.height > 0 {
                #expect(a.insetBy(dx: 0, dy: 0) == a)
                let dx = min(a.width, a.height) * 0.2
                let shrunk = a.insetBy(dx: dx, dy: dx)
                #expect(!shrunk.isNull)
                #expect(shrunk.insetBy(dx: -dx, dy: -dx) == a)
            }
        }
    }

    @Test func randomOverlapRunsNeverNudgePastEight() {
        var rng = SplitMix(state: 11)
        let start = UnitBox(x: 0.25, y: 0.25, width: 0.1, height: 0.04)
        for _ in 0..<100 {
            let budget = Int(rng.next() % 12)
            var seen = 0
            let end = LabelNudge.place(start) { _ in
                if seen < budget {
                    seen += 1
                    return true
                }
                return false
            }
            let moves = min(budget, LabelNudge.maxSteps)
            #expect(seen == moves)
            var y = start.y
            for _ in 0..<moves { y += LabelNudge.dy }
            #expect(end.box.y == y)
            if budget < LabelNudge.maxSteps {
                guard case .settled = end else {
                    Issue.record("a clear answer before eight steps should settle")
                    return
                }
            } else {
                guard case .capped = end else {
                    Issue.record("eight blocked answers should cap")
                    return
                }
            }
        }
    }
}
