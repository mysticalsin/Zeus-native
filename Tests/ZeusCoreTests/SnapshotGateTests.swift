import Foundation
import Testing
@testable import ZeusCore

@Suite struct SnapshotGateTests {
    @Test func anOlderFetchDoesNotApply() {
        var gate = SnapshotGate()
        let first = gate.begin()
        let second = gate.begin()
        #expect(gate.accepts(first) == false)
        #expect(gate.accepts(second))
    }

    @Test func zeroIsNeverAToken() {
        let gate = SnapshotGate()
        #expect(gate.accepts(0) == false)
    }

    @Test func randomBeginsAcceptOnlyTheLatest() {
        var rng = SnapshotSplitMix(state: 0x5A09)
        var gate = SnapshotGate()
        var tokens: [UInt64] = []
        for _ in 0..<300 {
            if rng.next() % 3 == 0 || tokens.isEmpty {
                tokens.append(gate.begin())
            }
            let latest = tokens.last!
            for token in tokens {
                #expect(gate.accepts(token) == (token == latest))
            }
        }
    }

    @Test func stressABurstOfRefreshesKeepsTheLast() {
        var gate = SnapshotGate()
        var last: UInt64 = 0
        for _ in 0..<400 {
            last = gate.begin()
        }
        #expect(gate.accepts(last))
        #expect(gate.accepts(last - 1) == false)
    }
}

struct SnapshotSplitMix: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
