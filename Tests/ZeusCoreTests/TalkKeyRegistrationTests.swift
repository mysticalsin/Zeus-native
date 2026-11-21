import Foundation
import Testing
@testable import ZeusCore

@Suite struct TalkKeyRegistrationTests {
    @Test func previewDoesNotSubscribe() {
        var book = TalkKeyRegistration()
        #expect(book.register(subscribes: false) == nil)
        #expect(book.tokens.isEmpty)
    }

    @Test func unregisterDropsTheToken() {
        var book = TalkKeyRegistration()
        let token = book.register(subscribes: true)
        book.unregister(token)
        #expect(book.tokens.isEmpty)
    }

    @Test func randomSubscribeAndDropLeavesNoLeakedTokens() {
        var rng = TalkSplitMix(state: 0x7A1C)
        var book = TalkKeyRegistration()
        var live: [Int] = []
        for _ in 0..<300 {
            if rng.next() % 2 == 0 {
                if let token = book.register(subscribes: rng.next() % 3 != 0) {
                    live.append(token)
                }
            } else if !live.isEmpty {
                let index = Int(rng.next() % UInt64(live.count))
                let token = live.remove(at: index)
                book.unregister(token)
            }
            #expect(Set(book.tokens) == Set(live))
        }
    }

    @Test func stressEverySpeakerCanLeave() {
        var book = TalkKeyRegistration()
        var live: [Int] = []
        for _ in 0..<200 {
            if let token = book.register(subscribes: true) { live.append(token) }
            _ = book.register(subscribes: false)
        }
        for token in live { book.unregister(token) }
        #expect(book.tokens.isEmpty)
    }
}

struct TalkSplitMix: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
