import Foundation
import Testing
@testable import ZeusCore

@Suite struct ReplyLedgerTests {
    @Test func releaseReportsTheOpenIds() {
        var ledger = ReplyLedger()
        #expect(ledger.open(1))
        #expect(ledger.open(2))
        #expect(ledger.finish(2))
        let dropped = ledger.failOutstanding()
        #expect(dropped == [1])
        #expect(ledger.open(3) == false)
        #expect(ledger.finish(1) == false)
    }

    @Test func droppingTheOwnerReportsWhatWasStillOpen() {
        let box = ReplyBox()
        do {
            let table = ReplyDrop()
            table.onDrop = { box.ids = $0 }
            #expect(table.open(7))
            #expect(table.open(8))
            #expect(table.finish(8))
        }
        #expect(box.ids == [7])
    }

    @Test func randomOpenAndFinishResumesEachIdOnce() {
        var rng = ReplySplitMix(state: 0x4E91)
        for _ in 0..<200 {
            var ledger = ReplyLedger()
            var live = Set<Int>()
            for step in 0..<Int(rng.next() % 12) + 1 {
                if rng.next() % 2 == 0 {
                    if ledger.open(step) { live.insert(step) }
                } else if let id = live.first {
                    #expect(ledger.finish(id))
                    live.remove(id)
                    #expect(ledger.finish(id) == false)
                }
            }
            let dropped = ledger.failOutstanding()
            #expect(dropped == live)
            #expect(ledger.failOutstanding().isEmpty)
        }
    }

    @Test func stressAHundredOpenIdsAllFailOnce() {
        var ledger = ReplyLedger()
        for id in 0..<100 { #expect(ledger.open(id)) }
        let dropped = ledger.failOutstanding()
        #expect(dropped.count == 100)
        #expect(ledger.failOutstanding().isEmpty)
    }
}

final class ReplyBox: @unchecked Sendable {
    var ids: Set<Int> = []
}

struct ReplySplitMix: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
