import Foundation
import Testing
@testable import ZeusCore

/// Old rectangle union, written from the rectangle rules rather than from `UnitBox.union`.
/// A positive-infinity origin is null and is dropped. A NaN origin or size makes that edge NaN,
/// and `min`/`max` then keep a NaN only when it is the first argument.
private func referenceUnion(_ a: UnitBox, _ b: UnitBox) -> UnitBox {
    func null(_ box: UnitBox) -> Bool { box.x == .infinity || box.y == .infinity }
    if null(a) { return b }
    if null(b) { return a }
    func low(_ origin: Double, _ size: Double) -> Double {
        if origin.isNaN || size.isNaN { return .nan }
        return size < 0 ? origin + size : origin
    }
    func high(_ origin: Double, _ size: Double) -> Double {
        if origin.isNaN || size.isNaN { return .nan }
        return size < 0 ? origin : origin + size
    }
    let left = min(low(a.x, a.width), low(b.x, b.width))
    let top = min(low(a.y, a.height), low(b.y, b.height))
    let right = max(high(a.x, a.width), high(b.x, b.width))
    let bottom = max(high(a.y, a.height), high(b.y, b.height))
    return UnitBox(x: left, y: top, width: right - left, height: bottom - top)
}

private func sameBox(_ lhs: UnitBox, _ rhs: UnitBox) -> Bool {
    if lhs.isNull || rhs.isNull { return lhs.isNull && rhs.isNull }
    func same(_ a: Double, _ b: Double) -> Bool { (a.isNaN && b.isNaN) || a == b }
    return same(lhs.x, rhs.x) && same(lhs.y, rhs.y) && same(lhs.width, rhs.width) && same(lhs.height, rhs.height)
}

private struct SplitMix {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    /// Whole numbers, so union of the edges is exact in binary floating point.
    mutating func whole() -> Double { Double(Int(next() % 17) - 8) }
}

@Suite("Unit box mark geometry")
struct UnitBoxTests {
    @Test func rectCircleSegmentAndLabelBoundsMatchTheMarkRules() {
        #expect(UnitBox.rect(x: 0.2, y: 0.3, width: 0.4, height: 0.5) == UnitBox(x: 0.2, y: 0.3, width: 0.4, height: 0.5))
        let circle = UnitBox.circle(centerX: 0.5, centerY: 0.4, radius: 0.1)
        #expect(circle.x == 0.4 && circle.width == 0.2 && circle.height == 0.2)
        #expect(abs(circle.y - 0.3) < 1e-12)
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

    @Test func aNonFinitePointIsDroppedTheWayTheOldRectangleDroppedIt() {
        let kept = UnitBox(x: 0.99, y: 1.99, width: 0.02, height: 0.02)
        #expect(UnitBox.path([UnitSample(x: .infinity, y: .infinity), UnitSample(x: 1, y: 2)]) == kept)
        #expect(UnitBox.path([UnitSample(x: 1, y: 2), UnitSample(x: .infinity, y: .infinity)]) == kept)
        #expect(UnitBox.path([UnitSample(x: .infinity, y: 0), UnitSample(x: 1, y: 2)]) == kept)
        #expect(UnitBox.path([UnitSample(x: .infinity, y: .infinity)])?.isNull == true)
        let extended = UnitBox.path([UnitSample(x: -.infinity, y: 0), UnitSample(x: 1, y: 2)])
        #expect(extended?.isNull == false)
        #expect(extended?.x == -.infinity)
        #expect(extended?.y == -0.01)
        #expect(extended?.width == .infinity)
        #expect(extended?.height == 2.02)
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
        let zeroWidth = box.insetBy(dx: 0.5, dy: 0)
        #expect(!zeroWidth.isNull)
        #expect(zeroWidth.width == 0)
        #expect(zeroWidth.x == 0.5)
        let zeroHeight = UnitBox(x: 0, y: 0, width: 2, height: 1).insetBy(dx: 0, dy: 0.5)
        #expect(!zeroHeight.isNull)
        #expect(zeroHeight.height == 0)
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
        // The t=1 sample sits in the 0.02 pad and outside a 0.01 pad. A smaller pad misses it.
        let endpoint = UnitBox(x: 0.96, y: -0.01, width: 0.025, height: 0.02)
        #expect(endpoint.overlaps(stroke))
        #expect(!endpoint.insetBy(dx: -0.01, dy: -0.01).hitsSegment(UnitSegment(x0: 0, y0: 0, x1: 1, y1: 0)))
        #expect(endpoint.insetBy(dx: -0.02, dy: -0.02).hitsSegment(UnitSegment(x0: 0, y0: 0, x1: 1, y1: 0)))
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
        #expect(LabelNudge.dy == 0.03)
        #expect(LabelNudge.maxSteps == 8)
        #expect(box.y == start.y + 0.03 + 0.03)

        var calls = 0
        let capped = LabelNudge.place(start) { _ in
            calls += 1
            return true
        }
        #expect(calls == 8)
        guard case .capped(let stuck) = capped else {
            Issue.record("expected a capped box, got \(capped)")
            return
        }
        var added = start.y
        for _ in 0..<8 { added += 0.03 }
        #expect(stuck.y == added)
        #expect(stuck.x == start.x && stuck.width == start.width && stuck.height == start.height)
    }

    @Test func nudgeTransitionsAreGuarded() {
        let box = UnitBox(x: 1, y: 2, width: 3, height: 4)
        #expect(LabelNudge.reduce(.checking(step: 0, box: box), .clear) == .settled(box))
        let once = LabelNudge.reduce(.checking(step: 0, box: box), .overlapped)
        #expect(once == .checking(step: 1, box: box.offsetBy(dx: 0, dy: 0.03)))
        let atLimit = box.offsetBy(dx: 0, dy: 0.03 * 8)
        let checkingLimit = LabelNudge.State.checking(step: 8, box: atLimit)
        #expect(LabelNudge.reduce(checkingLimit, .overlapped) == .capped(atLimit))
        #expect(LabelNudge.reduce(checkingLimit, .clear) == .settled(atLimit))
        let settled = LabelNudge.State.settled(box)
        let capped = LabelNudge.State.capped(atLimit)
        #expect(LabelNudge.reduce(settled, .overlapped) == settled)
        #expect(LabelNudge.reduce(settled, .clear) == settled)
        #expect(LabelNudge.reduce(capped, .clear) == capped)
        #expect(LabelNudge.reduce(capped, .overlapped) == capped)
    }

    @Test func unionMatchesTheOldRectangleOnNaNCorners() {
        let samples: [Double] = [0, 1, -2, .nan, .infinity, -.infinity]
        let sizes: [Double] = [0, 1, -1, .nan, .infinity]
        var mismatch: String?
        for x1 in samples {
            for y1 in samples {
                for w1 in sizes {
                    for h1 in sizes {
                        for x2 in samples {
                            for y2 in samples {
                                for w2 in sizes {
                                    for h2 in sizes {
                                        let left = UnitBox(x: x1, y: y1, width: w1, height: h1)
                                        let right = UnitBox(x: x2, y: y2, width: w2, height: h2)
                                        let got = left.union(right)
                                        let want = referenceUnion(left, right)
                                        if !sameBox(got, want) {
                                            mismatch = "(\(x1),\(y1),\(w1),\(h1)) U (\(x2),\(y2),\(w2),\(h2))"
                                        }
                                        if mismatch != nil { break }
                                    }
                                    if mismatch != nil { break }
                                }
                                if mismatch != nil { break }
                            }
                            if mismatch != nil { break }
                        }
                        if mismatch != nil { break }
                    }
                    if mismatch != nil { break }
                }
                if mismatch != nil { break }
            }
            if mismatch != nil { break }
        }
        #expect(mismatch == nil, "union left the old rectangle at \(mismatch ?? "")")
        let dropped = UnitBox.path([UnitSample(x: 1, y: 2), UnitSample(x: .nan, y: 4)])
        #expect(dropped == UnitBox(x: 0.99, y: 1.99, width: 0.02, height: 2.02))
    }

    @Test func randomBoxesKeepUnionAndInsetInvariants() {
        var rng = SplitMix(state: 0xC0FFEE)
        for _ in 0..<200 {
            let a = UnitBox(x: rng.whole(), y: rng.whole(), width: rng.whole(), height: rng.whole())
            let b = UnitBox(x: rng.whole(), y: rng.whole(), width: rng.whole(), height: rng.whole())
            let c = UnitBox(x: rng.whole(), y: rng.whole(), width: rng.whole(), height: rng.whole())
            #expect(a.union(b) == b.union(a))
            #expect(a.union(b).union(c) == a.union(b.union(c)))
            #expect(a.union(.null) == a)
            #expect(UnitBox.null.union(a) == a)
            if a.width > 2, a.height > 2 {
                #expect(a.insetBy(dx: 0, dy: 0) == a)
                let shrunk = a.insetBy(dx: 1, dy: 1)
                #expect(!shrunk.isNull)
                #expect(shrunk.insetBy(dx: -1, dy: -1) == a)
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
            let moves = min(budget, 8)
            #expect(seen == moves)
            var y = start.y
            for _ in 0..<moves { y += 0.03 }
            #expect(end.box.y == y)
            if budget < 8 {
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
