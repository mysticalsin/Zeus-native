import Foundation
import Testing
@testable import ZeusCore

@Suite struct PlaybackClipBookTests {
    @Test func anInterruptionClearsPlayback() {
        var book = PlaybackClipBook()
        _ = book.begin()
        book.interrupt()
        #expect(book.playing == false)
    }

    @Test func replacingAClipEndsThePreviousOne() {
        var book = PlaybackClipBook()
        let first = book.begin()
        let second = book.replace()
        #expect(second != first)
        #expect(book.live == [second])
        #expect(book.playing)
    }

    @Test func randomReplaceAndInterruptNeverKeepTwoClips() {
        var rng = PlaybackSplitMix(state: 0x91A7)
        for _ in 0..<200 {
            var book = PlaybackClipBook()
            for _ in 0..<Int(rng.next() % 8) + 1 {
                switch rng.next() % 3 {
                case 0:
                    if book.playing { _ = book.replace() } else { _ = book.begin() }
                case 1:
                    _ = book.replace()
                default:
                    book.interrupt()
                }
                if book.live.count > 1 {
                    Issue.record("two clips were live")
                }
            }
        }
    }

    @Test func stressInterruptsAlwaysGoQuiet() {
        var book = PlaybackClipBook()
        for _ in 0..<100 {
            _ = book.begin()
            _ = book.replace()
            book.interrupt()
            #expect(book.playing == false)
            #expect(book.live.isEmpty)
        }
    }
}

struct PlaybackSplitMix: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
