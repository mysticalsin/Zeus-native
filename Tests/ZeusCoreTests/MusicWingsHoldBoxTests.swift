import Foundation
import Testing
@testable import ZeusCore

@Suite("Music wings hold box")
struct MusicWingsHoldBoxTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func blankScalarsAreNamedAndLeaveAZeroWidthSpace() {
        #expect(MusicWingsHoldBox.blankScalars.contains(" "))
        #expect(MusicWingsHoldBox.blankScalars.contains("\t"))
        #expect(MusicWingsHoldBox.blankScalars.contains("\n"))
        #expect(MusicWingsHoldBox.blankScalars.contains("\u{000B}"))
        #expect(MusicWingsHoldBox.blankScalars.contains("\u{000C}"))
        #expect(MusicWingsHoldBox.blankScalars.contains("\r"))
        #expect(MusicWingsHoldBox.blankScalars.contains("\u{0085}"))
        #expect(MusicWingsHoldBox.blankScalars.contains("\u{00A0}"))
        #expect(MusicWingsHoldBox.blankScalars.contains("\u{1680}"))
        #expect(MusicWingsHoldBox.blankScalars.contains("\u{2000}"))
        #expect(MusicWingsHoldBox.blankScalars.contains("\u{200A}"))
        #expect(MusicWingsHoldBox.blankScalars.contains("\u{2028}"))
        #expect(MusicWingsHoldBox.blankScalars.contains("\u{2029}"))
        #expect(MusicWingsHoldBox.blankScalars.contains("\u{202F}"))
        #expect(MusicWingsHoldBox.blankScalars.contains("\u{205F}"))
        #expect(MusicWingsHoldBox.blankScalars.contains("\u{3000}"))
        #expect(!MusicWingsHoldBox.blankScalars.contains("\u{200B}"))
        #expect(MusicWingsHoldBox.trimmedLabel("\u{200B}") == "\u{200B}")
        #expect(MusicWingsHoldBox.trimmedLabel(" \u{200B} ") == "\u{200B}")
        #expect(MusicWingsHoldBox.trimmedLabel(" \t\n\u{00A0}\u{3000}") == "")
    }

    @Test func aZeroWidthSpaceDoesNotChangeThePauseLabel() {
        #expect(MusicWingsHoldBox.collapse(label: " After 10 s ") == .after(10))
        #expect(MusicWingsHoldBox.collapse(label: "\u{00A0}After 1 min\u{00A0}") == .after(60))
        #expect(MusicWingsHoldBox.collapse(label: "\tNever\n") == .never)
        #expect(MusicWingsHoldBox.collapse(label: "At once") == .atOnce)
        #expect(MusicWingsHoldBox.collapse(label: "\u{200B}After 10 s") == .atOnce)
        #expect(MusicWingsHoldBox.collapse(label: "After 10 s\u{200B}") == .atOnce)
        #expect(MusicWingsHoldBox.collapse(label: "After\u{200B}10 s") == .atOnce)
        #expect(PauseCollapse(label: "\u{200B}After 10 s") == .atOnce)
        #expect(PauseCollapse(label: " After 10 s ") == .after(10))
    }

    @Test func anUnknownLabelOrABadDelayCollapsesAtOnce() {
        #expect(MusicWingsHoldBox.collapse(label: "") == .atOnce)
        #expect(MusicWingsHoldBox.collapse(label: "Later") == .atOnce)
        #expect(MusicWingsHoldBox.collapse(label: "   ") == .atOnce)
        #expect(MusicWingsHoldBox.collapse(delay: 10) == .after(10))
        #expect(MusicWingsHoldBox.collapse(delay: 0) == .atOnce)
        #expect(MusicWingsHoldBox.collapse(delay: -3) == .atOnce)
        #expect(MusicWingsHoldBox.collapse(delay: .nan) == .atOnce)
        #expect(MusicWingsHoldBox.collapse(delay: .infinity) == .atOnce)
        #expect(PauseCollapse(delay: .nan) == .atOnce)
    }

    @Test func aPauseFromPlayingHoldsUntilThePolicy() {
        let playing = MusicWingsHoldBox.reduce(
            .hidden,
            .playback(.playing, wingsOnScreen: false, now: start),
            policy: .atOnce)
        #expect(playing.0 == .playing)
        #expect(playing.1.isEmpty)
        let held = MusicWingsHoldBox.reduce(
            playing.0,
            .playback(.paused, wingsOnScreen: true, now: start),
            policy: .after(10))
        #expect(held.0 == .held(since: start, until: start.addingTimeInterval(10)))
        #expect(held.1 == [.wake(at: start.addingTimeInterval(10))])
        #expect(MusicWingsHoldBox.showsWings(held.0))
        #expect(MusicWingsHoldBox.isPaused(held.0))
        #expect(!MusicWingsHoldBox.showsWings(.hidden))
        #expect(!MusicWingsHoldBox.isPaused(.playing))
    }

    @Test func aZeroWidthLabelDoesNotHoldTheWings() {
        let policy = MusicWingsHoldBox.collapse(label: "\u{200B}After 10 s")
        let paused = MusicWingsHoldBox.reduce(
            .playing,
            .playback(.paused, wingsOnScreen: true, now: start),
            policy: policy)
        #expect(policy == .atOnce)
        #expect(paused.0 == .hidden)
        #expect(paused.1.isEmpty)
    }
}
