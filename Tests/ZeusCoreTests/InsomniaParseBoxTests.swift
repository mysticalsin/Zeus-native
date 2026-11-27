import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays in a volume-settings field. These tests name the blanks.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Insomnia parse box")
struct InsomniaParseBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(InsomniaParseBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(InsomniaParseBox.blankScalars.count == 5)
        #expect(InsomniaParseBox.blankScalars.contains(" "))
        #expect(InsomniaParseBox.blankScalars.contains("\t"))
        #expect(InsomniaParseBox.blankScalars.contains("\n"))
        #expect(InsomniaParseBox.blankScalars.contains("\r"))
        #expect(InsomniaParseBox.blankScalars.contains("\u{00A0}"))
        #expect(!InsomniaParseBox.blankScalars.contains("\u{200B}"))
        #expect(!InsomniaParseBox.blankScalars.contains("\u{000B}"))
        #expect(!InsomniaParseBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysInTheTrimmedField() {
        #expect(InsomniaParseBox.trimmedField("\u{200B}") == "\u{200B}")
        #expect(InsomniaParseBox.trimmedField(" \u{200B} ") == "\u{200B}")
        #expect(InsomniaParseBox.trimmedField("\t\u{200B}\n") == "\u{200B}")
        #expect(InsomniaParseBox.trimmedField("\u{200B}50") == "\u{200B}50")
        #expect(InsomniaParseBox.trimmedField("50\u{200B}") == "50\u{200B}")
        #expect(InsomniaParseBox.trimmedField(" \t\n\r\u{00A0}") == "")
        #expect(InsomniaParseBox.trimmedField("") == "")
        #expect(InsomniaParseBox.trimmedField("\u{000B}50") == "\u{000B}50")
        #expect(InsomniaParseBox.trimmedField("\u{3000}50") == "\u{3000}50")
        #expect(InsomniaParseBox.trimmedField(" \t50\r\n") == "50")
        #expect(InsomniaParseBox.trimmedField("\u{00A0}50\u{00A0}") == "50")
        #expect(InsomniaParseBox.trimmedField("output\u{00A0}volume") == "output\u{00A0}volume")
    }

    @Test func aZeroWidthSpaceDoesNotReadAsAVolume() {
        #expect(InsomniaParse.volume("output volume:\u{200B}50, output muted:false") == nil)
        #expect(InsomniaParse.volume("\u{200B}output volume:50, output muted:false") == nil)
        let hiddenTrue = InsomniaParse.volume("output volume:50, output muted:\u{200B}true")
        #expect(hiddenTrue?.volume == 50)
        #expect(hiddenTrue?.muted == false)
        #expect(InsomniaParse.volume("output volume:50, output muted:true")?.muted == true)
        #expect(InsomniaParse.volume("output volume:50, output muted:\u{00A0}true\u{00A0}")?.muted == true)
        #expect(InsomniaParse.volume("output volume:\u{000B}50, output muted:false") == nil)
        #expect(InsomniaParse.volume("output volume:\u{3000}50, output muted:false") == nil)
        let padded = InsomniaParse.volume(" \toutput volume\r\n: \u{00A0}50\u{00A0} , output muted : false\n")
        #expect(padded?.volume == 50)
        #expect(padded?.muted == false)
        let parsed = InsomniaParse.volume("output volume:50, input volume:75, alert volume:100, output muted:false\n")
        #expect(parsed?.volume == 50)
        #expect(parsed?.muted == false)
        #expect(InsomniaParse.volume("output volume:missing value, output muted:missing value") == nil)
        #expect(InsomniaParse.volume(" \t\n\r\u{00A0}") == nil)
        #expect(InsomniaParse.volume("\u{200B}") == nil)
    }
}
