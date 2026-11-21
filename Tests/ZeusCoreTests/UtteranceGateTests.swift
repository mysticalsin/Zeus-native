import Foundation
import Testing
@testable import ZeusCore

@Suite struct UtteranceGateTests {
    @Test func aLaterSpeakDoesNotClearAnEarlierCancel() {
        let gate = UtteranceGate()
        let first = gate.begin()
        gate.cancelActive()
        let second = gate.begin()
        #expect(first != second)
        #expect(gate.isCancelled(first))
        #expect(gate.isCancelled(second) == false)
    }

    @Test func cancelOneIdLeavesTheOther() {
        let gate = UtteranceGate()
        let first = gate.begin()
        let second = gate.begin()
        gate.cancel(first)
        #expect(gate.isCancelled(first))
        #expect(gate.isCancelled(second) == false)
    }

    @Test func randomInterleavingKeepsEveryCancelledId() {
        let gate = UtteranceGate()
        var rng = UtteranceSplitMix(state: 0x5EED)
        var ids: [UInt64] = []
        var dead = Set<UInt64>()
        for _ in 0..<300 {
            switch rng.next() % 3 {
            case 0:
                ids.append(gate.begin())
            case 1:
                gate.cancelActive()
                if let last = ids.last { dead.insert(last) }
            default:
                if ids.isEmpty { continue }
                let index = Int(rng.next() % UInt64(ids.count))
                let id = ids[index]
                gate.cancel(id)
                dead.insert(id)
            }
            for id in dead {
                #expect(gate.isCancelled(id))
            }
        }
    }

    @Test func stressCancelledIdsStayCancelledAcrossNewSpeaks() {
        let gate = UtteranceGate()
        var dead: [UInt64] = []
        for index in 0..<200 {
            let id = gate.begin()
            if index % 2 == 0 {
                gate.cancel(id)
                dead.append(id)
            }
        }
        for _ in 0..<50 { _ = gate.begin() }
        for id in dead {
            #expect(gate.isCancelled(id))
        }
    }
}

struct UtteranceSplitMix: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
