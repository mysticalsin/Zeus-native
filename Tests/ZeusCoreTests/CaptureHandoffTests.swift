import Foundation
import Testing
@testable import ZeusCore

@Suite struct CaptureHandoffTests {
    @Test func theNextCaptureWaitsForThePreviousRelease() {
        var handoff = CaptureHandoff()
        var open = Set<Int>()
        apply(handoff.start(1), open: &open)
        #expect(open == [1])
        apply(handoff.start(2), open: &open)
        #expect(open.isEmpty)
        apply(handoff.didRelease(), open: &open)
        #expect(open == [2])
    }

    @Test func randomStartsNeverHoldTwoMicrophones() {
        var rng = HandoffSplitMix(state: 0x5C1B)
        for _ in 0..<250 {
            var handoff = CaptureHandoff()
            var open = Set<Int>()
            var next = 1
            for _ in 0..<Int(rng.next() % 8) + 1 {
                if rng.next() % 4 == 0, !open.isEmpty || handoff.releasing {
                    apply(handoff.didRelease(), open: &open)
                } else {
                    apply(handoff.start(next), open: &open)
                    next += 1
                }
                #expect(open.count <= 1)
            }
        }
    }

    @Test func stressReplacementReleasesBeforeBegin() {
        var handoff = CaptureHandoff()
        var open = Set<Int>()
        for session in 1...200 {
            apply(handoff.start(session), open: &open)
            #expect(open.count <= 1)
            if open.isEmpty {
                apply(handoff.didRelease(), open: &open)
                #expect(open == [session] || open.isEmpty)
            }
        }
    }

    private func apply(_ effects: [CaptureHandoff.Effect], open: inout Set<Int>) {
        for effect in effects {
            switch effect {
            case .release(let id):
                open.remove(id)
            case .begin(let id):
                #expect(open.isEmpty)
                open.insert(id)
            }
        }
    }
}

struct HandoffSplitMix: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
