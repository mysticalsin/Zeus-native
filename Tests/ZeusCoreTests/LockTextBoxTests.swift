import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays on a cut lock-screen string. These tests name the blanks.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Lock text box")
struct LockTextBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(LockTextBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(LockTextBox.blankScalars.count == 5)
        #expect(LockTextBox.blankScalars.contains(" "))
        #expect(LockTextBox.blankScalars.contains("\t"))
        #expect(LockTextBox.blankScalars.contains("\n"))
        #expect(LockTextBox.blankScalars.contains("\r"))
        #expect(LockTextBox.blankScalars.contains("\u{00A0}"))
        #expect(!LockTextBox.blankScalars.contains("\u{200B}"))
        #expect(!LockTextBox.blankScalars.contains("\u{000B}"))
        #expect(!LockTextBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysInTheTrimmedCut() {
        #expect(LockTextBox.trimmedText("\u{200B}") == "\u{200B}")
        #expect(LockTextBox.trimmedText(" \u{200B} ") == "\u{200B}")
        #expect(LockTextBox.trimmedText("\t\u{200B}\n") == "\u{200B}")
        #expect(LockTextBox.trimmedText("\u{200B}Kind of Blue") == "\u{200B}Kind of Blue")
        #expect(LockTextBox.trimmedText("Kind of Blue\u{200B}") == "Kind of Blue\u{200B}")
        #expect(LockTextBox.trimmedText(" \t\n\r\u{00A0}") == "")
        #expect(LockTextBox.trimmedText("") == "")
        #expect(LockTextBox.trimmedText("\u{000B}Kind of Blue") == "\u{000B}Kind of Blue")
        #expect(LockTextBox.trimmedText("\u{3000}Kind of Blue") == "\u{3000}Kind of Blue")
        #expect(LockTextBox.trimmedText(" \tKind of Blue\r\n") == "Kind of Blue")
        #expect(LockTextBox.trimmedText("\u{00A0}Kind of Blue\u{00A0}") == "Kind of Blue")
        #expect(LockTextBox.trimmedText("Kind of Blue") == "Kind of Blue")
    }

    @Test func aZeroWidthSpaceStaysOnTheCutTitle() {
        let marked = "\u{200B}" + String(repeating: "a", count: 90)
        let prefix = String(marked.prefix(80))
        #expect(LockTextBox.trimmedText(prefix) == prefix)
        #expect(LockText.clean(marked, limit: 80)?.count == 80)
        #expect(LockText.clean("\u{200B}", limit: 80) == nil)
        #expect(LockText.clean("\u{200B}Kind of Blue", limit: 80) == "Kind of Blue")
        #expect(LockText.clean(" \t\n\r\u{00A0}", limit: 80) == nil)
        #expect(LockText.clean("\u{00A0}Kind of Blue\u{00A0}", limit: 80) == "Kind of Blue")
        #expect(LockText.clean("\u{000B}Kind of Blue", limit: 80) == "Kind of Blue")
        #expect(LockText.clean("\u{3000}Kind of Blue", limit: 80) == "Kind of Blue")
        #expect(LockText.clean("Hello\nWorld", limit: 80) == "HelloWorld")
        #expect(LockText.clean("A   B\tC", limit: 80) == "A B C")
        #expect(LockText.clean(" \n\u{200B} ", limit: 80) == nil)
        let cut = String(repeating: "a", count: 9) + " " + String(repeating: "b", count: 20)
        #expect(LockText.clean(cut, limit: 10) == String(repeating: "a", count: 9))
        #expect(LockText.clean(String(repeating: "a", count: 90), limit: 80)?.count == 80)
        let now = Date(timeIntervalSince1970: 1_764_000_000)
        let markedCard = scene(title: "\u{200B}Kind of Blue", at: now)
        #expect(cardTitle(markedCard) == "Kind of Blue")
        let blankCard = scene(title: " \t\n\r\u{00A0}", at: now)
        #expect(cardTitle(blankCard) == "")
        let spacedCard = scene(title: "  Kind of Blue  ", at: now)
        #expect(cardTitle(spacedCard) == "Kind of Blue")
        let longCard = scene(title: String(repeating: "a", count: 90), at: now)
        #expect(cardTitle(longCard)?.count == 80)
    }

    private func scene(title: String, at now: Date) -> LockScene {
        let track = LockTrack(
            kind: .player, playerRunning: true, title: title, artist: "Miles Davis", hue: 0.42,
            isPlaying: true, duration: 200, position: 12, positionAt: now, canControl: true
        )
        let options = LockOptions(showTrackDetails: true, hideDetails: false, lyrics: false, lyricsPrivacy: false, clock: false)
        return LockContentPolicy.scene(track: track, options: options, lyricLine: nil, at: now)
    }

    private func cardTitle(_ scene: LockScene) -> String? {
        guard case .full(let title, _, _, _, _, _, _) = scene.card else { return nil }
        return title
    }
}
