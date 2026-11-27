import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays in a music mode answer. These tests name the blanks.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Music mode answer box")
struct MusicModesAnswerBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(MusicModesAnswerBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(MusicModesAnswerBox.blankScalars.count == 5)
        #expect(MusicModesAnswerBox.blankScalars.contains(" "))
        #expect(MusicModesAnswerBox.blankScalars.contains("\t"))
        #expect(MusicModesAnswerBox.blankScalars.contains("\n"))
        #expect(MusicModesAnswerBox.blankScalars.contains("\r"))
        #expect(MusicModesAnswerBox.blankScalars.contains("\u{00A0}"))
        #expect(!MusicModesAnswerBox.blankScalars.contains("\u{200B}"))
        #expect(!MusicModesAnswerBox.blankScalars.contains("\u{000B}"))
        #expect(!MusicModesAnswerBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysInTheTrimmedText() {
        #expect(MusicModesAnswerBox.trimmedText("\u{200B}") == "\u{200B}")
        #expect(MusicModesAnswerBox.trimmedText(" \u{200B} ") == "\u{200B}")
        #expect(MusicModesAnswerBox.trimmedText("\t\u{200B}\n") == "\u{200B}")
        #expect(MusicModesAnswerBox.trimmedText("\u{200B}true") == "\u{200B}true")
        #expect(MusicModesAnswerBox.trimmedText("true\u{200B}") == "true\u{200B}")
        #expect(MusicModesAnswerBox.trimmedText(" \t\n\r\u{00A0}") == "")
        #expect(MusicModesAnswerBox.trimmedText("") == "")
        #expect(MusicModesAnswerBox.trimmedText("\u{000B}true") == "\u{000B}true")
        #expect(MusicModesAnswerBox.trimmedText("\u{3000}true") == "\u{3000}true")
        #expect(MusicModesAnswerBox.trimmedText(" \ttrue\r\n") == "true")
        #expect(MusicModesAnswerBox.trimmedText("\u{00A0}true\u{00A0}") == "true")
        #expect(MusicModesAnswerBox.trimmedText("true\u{00A0}all") == "true\u{00A0}all")
    }

    @Test func aZeroWidthSpaceStaysInTheParsedAnswer() {
        let sep = MusicModesBox.separator
        let zwsp = "\u{200B}"
        let music = MusicModesBox.Player.music
        let on = MusicModes(shuffle: true, repeatMode: .all)
        #expect(MusicModesBox.parse("\(zwsp)true\(sep)all", player: music) == nil)
        #expect(MusicModesBox.parse(" \(zwsp) ", player: music) == nil)
        #expect(MusicModesBox.parse("\t\(zwsp)\n", player: music) == nil)
        #expect(MusicModesBox.parse("\(zwsp)true", player: music) == nil)
        #expect(MusicModesBox.parse("true\(sep)\(zwsp)all", player: music) == nil)
        #expect(MusicModesBox.parse(" \t\n\r\u{00A0}", player: music) == nil)
        #expect(MusicModesBox.parse("", player: music) == nil)
        #expect(MusicModesBox.parse("\u{000B}true\(sep)all", player: music) == nil)
        #expect(MusicModesBox.parse("\u{3000}true\(sep)all", player: music) == nil)
        #expect(MusicModesBox.parse(" \ttrue\(sep)all\r\n", player: music) == on)
        #expect(MusicModesBox.parse("\u{00A0}true\u{00A0}\(sep)\u{00A0}all\u{00A0}", player: music) == on)
        #expect(MusicModesBox.parse("true\(sep)all", player: music) == on)
    }
}
