import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays on a step-zero question field list. These tests name the blanks.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Step zero field body box")
struct StepZeroFieldBodyBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(StepZeroFieldBodyBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(StepZeroFieldBodyBox.blankScalars.count == 5)
        #expect(StepZeroFieldBodyBox.blankScalars.contains(" "))
        #expect(StepZeroFieldBodyBox.blankScalars.contains("\t"))
        #expect(StepZeroFieldBodyBox.blankScalars.contains("\n"))
        #expect(StepZeroFieldBodyBox.blankScalars.contains("\r"))
        #expect(StepZeroFieldBodyBox.blankScalars.contains("\u{00A0}"))
        #expect(!StepZeroFieldBodyBox.blankScalars.contains("\u{200B}"))
        #expect(!StepZeroFieldBodyBox.blankScalars.contains("\u{000B}"))
        #expect(!StepZeroFieldBodyBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysInTheTrimmedFieldList() {
        #expect(StepZeroFieldBodyBox.trimmedBody("\u{200B}") == "\u{200B}")
        #expect(StepZeroFieldBodyBox.trimmedBody(" \u{200B} ") == "\u{200B}")
        #expect(StepZeroFieldBodyBox.trimmedBody("\t\u{200B}\n") == "\u{200B}")
        #expect(StepZeroFieldBodyBox.trimmedBody("\u{200B}*p9") == "\u{200B}*p9")
        #expect(StepZeroFieldBodyBox.trimmedBody("*p9\u{200B}") == "*p9\u{200B}")
        #expect(StepZeroFieldBodyBox.trimmedBody(" \t\n\r\u{00A0}") == "")
        #expect(StepZeroFieldBodyBox.trimmedBody("") == "")
        #expect(StepZeroFieldBodyBox.trimmedBody("\u{000B}*p9") == "\u{000B}*p9")
        #expect(StepZeroFieldBodyBox.trimmedBody("\u{3000}*p9") == "\u{3000}*p9")
        #expect(StepZeroFieldBodyBox.trimmedBody(" \t*p9\r\n") == "*p9")
        #expect(StepZeroFieldBodyBox.trimmedBody("\u{00A0}*p9\u{00A0}") == "*p9")
        #expect(StepZeroFieldBodyBox.trimmedBody("*p9") == "*p9")
    }

    @Test func aZeroWidthSpaceStaysOnTheQuestionFieldList() {
        #expect(StepZeroFieldBodyBox.trimmedBody(" \u{200B}*p9") == "\u{200B}*p9")
        #expect(StepZeroFieldBodyBox.trimmedBody(" *p9") == "*p9")
        #expect(StepZeroFieldBodyBox.trimmedBody(" \t\n\r\u{00A0}") == "")
        #expect(StepZeroFieldBodyBox.trimmedBody(" p1.itemSeen:flag ") == "p1.itemSeen:flag")
        #expect(StepZeroCatalogue.questions.count == 45)
        let p9 = StepZeroCatalogue.byID["P9"]
        #expect(p9?.fields.first?.id == "p9.privateWindow.seen")
        #expect(p9?.fields.first?.kind == .flag)
        #expect(p9?.fields.isEmpty == false)
        #expect(StepZeroCatalogue.byID["E7"]?.fields.isEmpty == true)
        #expect(StepZeroCatalogue.byID["F10"]?.fields.isEmpty == true)
        let p1 = StepZeroCatalogue.byID["P1"]
        #expect(p1?.fields.map(\.id) == ["p1.itemSeen", "p1.fields", "p1.ownerSaysPlaying"])
        #expect(p1?.fields.map(\.kind) == [.flag, .codes, .flag])
    }
}
