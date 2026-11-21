import Foundation
import Testing
@testable import ZeusCore

@Suite struct MonitorBookTests {
    @Test func aSecondStartAddsNothing() {
        var book = MonitorBook()
        let first = book.startLocal()
        let second = book.startLocal()
        #expect(first)
        #expect(second == false)
        #expect(book.local == 1)
        let global = book.startGlobal()
        let again = book.startGlobal()
        #expect(global)
        #expect(again == false)
        #expect(book.global == 1)
    }

    @Test func randomStartsStayAtOne() {
        var rng = MonitorSplitMix(state: 0xB001)
        for _ in 0..<200 {
            var book = MonitorBook()
            var localInstalled = false
            var globalInstalled = false
            for _ in 0..<Int(rng.next() % 8) + 1 {
                if rng.next() % 2 == 0 {
                    let added = book.startLocal()
                    #expect(added == !localInstalled)
                    localInstalled = true
                } else {
                    let added = book.startGlobal()
                    #expect(added == !globalInstalled)
                    globalInstalled = true
                }
            }
            #expect(book.local <= 1)
            #expect(book.global <= 1)
        }
    }

    @Test func stressAHundredStartsIsStillOneMonitor() {
        var book = MonitorBook()
        for _ in 0..<100 {
            _ = book.startLocal()
            _ = book.startGlobal()
        }
        #expect(book.local == 1)
        #expect(book.global == 1)
    }
}

struct MonitorSplitMix: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
