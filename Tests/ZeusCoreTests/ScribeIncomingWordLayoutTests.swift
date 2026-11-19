import Foundation
import Testing
@testable import ZeusCore

@Suite("Scribe incoming word layout")
struct ScribeIncomingWordLayoutTests {
    @Test func exactSubstringsPreserveWhitespacePunctuationAndLanguages() {
        let text = "  Hello,\tworld!\n你好 👩🏽‍💻  مرحبا\r\nfin. "
        let layout = ScribeIncomingWordLayout(text: text, alreadyShown: 0, since: 10)
        #expect(layout.runs.map(\.text).joined() == text)
        #expect(layout.words == ["Hello,", "world!", "你好", "👩🏽‍💻", "مرحبا", "fin."])
        #expect(layout.runs.compactMap(\.wordIndex) == Array(0..<6))
    }

    @Test func onlyEligibleRealWordsRevealOver350Milliseconds() {
        let layout = ScribeIncomingWordLayout(text: "One two", alreadyShown: 0, since: 10)
        let first = 10 + 1.0 / 12
        #expect(layout.frame(forWord: 0, shownWords: 0, at: first + 1).opacity == 0)
        #expect(layout.frame(forWord: 0, shownWords: 1, at: first).opacity == 0)
        let middle = layout.frame(forWord: 0, shownWords: 1, at: first + 0.175)
        #expect(middle.opacity > 0 && middle.opacity < 1)
        #expect(abs(middle.blur - (1 - middle.opacity)) < 0.000001)
        #expect(layout.frame(forWord: 0, shownWords: 1, at: first + 0.351).opacity == 1)
        #expect(layout.frame(forWord: 1, shownWords: 1, at: first + 1).opacity == 0)
    }

    @Test func eligiblePrefixDoesNotReserveUnarrivedTailOrItsWhitespace() {
        let text = "  First\tvisible\n\n" + Array(repeating: "future", count: 300).joined(separator: " ") + "  "
        let layout = ScribeIncomingWordLayout(text: text, alreadyShown: 0, since: 10)
        #expect(layout.visibleRuns(shownWords: 0).isEmpty)
        #expect(layout.visibleRuns(shownWords: 1).map(\.text).joined() == "  First")
        #expect(layout.visibleRuns(shownWords: 2).map(\.text).joined() == "  First\tvisible")
        #expect(layout.visibleRuns(shownWords: 3).map(\.text).joined() == "  First\tvisible\n\nfuture")
        #expect(layout.visibleRuns(shownWords: layout.words.count).map(\.text).joined() == text)
    }

    @Test func unchangedEligibleWordsDoNotRestartWhenTheBatchGrows() {
        let first = ScribeIncomingWordLayout(text: "One two", alreadyShown: 0, since: 10)
        let revised = ScribeIncomingWordLayout(text: "One two three", alreadyShown: 1, since: 10.12, previous: first)
        #expect(first.frame(forWord: 0, shownWords: 1, at: 10.14) == revised.frame(forWord: 0, shownWords: 1, at: 10.14))
        #expect(revised.revision != first.revision)
        #expect(revised.frame(forWord: 2, shownWords: 2, at: 100).opacity == 0)
    }

    @Test func correctionsReplaceEligibleWordsAndNeverRetainRemovedTokens() {
        let first = ScribeIncomingWordLayout(text: "Send Alice the draft tomorrow", alreadyShown: 0, since: 10)
        let corrected = ScribeIncomingWordLayout(text: "Send Bob the draft", alreadyShown: 4, since: 10.4, previous: first)
        #expect(corrected.words == ["Send", "Bob", "the", "draft"])
        #expect(corrected.frame(forWord: 1, shownWords: 4, at: 10.4).opacity == 1)
        #expect(!corrected.runs.map(\.text).joined().contains("Alice"))
        #expect(!corrected.runs.map(\.text).joined().contains("tomorrow"))
        #expect(corrected.frame(forWord: 0, shownWords: 4, at: 10.4) == first.frame(forWord: 0, shownWords: 4, at: 10.4))
    }

    @Test func newSessionsDoNotInheritAnOldWordsFadeOrigin() {
        let earlier = ScribeIncomingWordLayout(text: "Hello", alreadyShown: 0, since: 10)
        let later = ScribeIncomingWordLayout(text: "Hello", alreadyShown: 0, since: 100)
        #expect(earlier.frame(forWord: 0, shownWords: 1, at: 100.09).opacity == 1)
        #expect(later.frame(forWord: 0, shownWords: 1, at: 100.09).opacity < 0.2)
    }

    @Test func accessibilityPoliciesShowAllWordsOrRemoveBlur() {
        let layout = ScribeIncomingWordLayout(text: "Real words", alreadyShown: 0, since: 10)
        #expect(layout.frame(forWord: 1, shownWords: 0, at: 10, reduceMotion: true) == .init(opacity: 1, blur: 0))
        let normal = layout.frame(forWord: 0, shownWords: 1, at: 10.1)
        let opaque = layout.frame(forWord: 0, shownWords: 1, at: 10.1, reduceTransparency: true)
        #expect(opaque.opacity == normal.opacity)
        #expect(opaque.blur == 0)
    }

    @Test func invalidClocksDoNotHideEligibleTextAndSettledLinesCanBypassRendering() {
        let invalid = ScribeIncomingWordLayout(text: "Ready now", alreadyShown: 0, since: .nan)
        #expect(invalid.frame(forWord: 0, shownWords: 1, at: 10).opacity == 1)
        let layout = ScribeIncomingWordLayout(text: "Ready now", alreadyShown: 0, since: 10)
        #expect(layout.frame(forWord: 0, shownWords: 1, at: .nan).opacity == 1)
        #expect(!layout.isSettled(at: 100, shownWords: 1))
        #expect(!layout.isSettled(at: 10.2, shownWords: 2))
        #expect(layout.isSettled(at: 10.52, shownWords: 2))
        #expect(ScribeIncomingWordLayout(text: "\n\t", alreadyShown: 0, since: 10).isSettled(at: 10, shownWords: 0))
    }
}
