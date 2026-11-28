import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays in spoken text after a tag parse. These tests name the blanks.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Zeus tag spoken box")
struct ZeusTagSpokenBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(ZeusTagSpokenBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(ZeusTagSpokenBox.blankScalars.count == 5)
        #expect(ZeusTagSpokenBox.blankScalars.contains(" "))
        #expect(ZeusTagSpokenBox.blankScalars.contains("\t"))
        #expect(ZeusTagSpokenBox.blankScalars.contains("\n"))
        #expect(ZeusTagSpokenBox.blankScalars.contains("\r"))
        #expect(ZeusTagSpokenBox.blankScalars.contains("\u{00A0}"))
        #expect(!ZeusTagSpokenBox.blankScalars.contains("\u{200B}"))
        #expect(!ZeusTagSpokenBox.blankScalars.contains("\u{000B}"))
        #expect(!ZeusTagSpokenBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysInTheTrimmedSpokenText() {
        #expect(ZeusTagSpokenBox.trimmedSpoken("\u{200B}") == "\u{200B}")
        #expect(ZeusTagSpokenBox.trimmedSpoken(" \u{200B} ") == "\u{200B}")
        #expect(ZeusTagSpokenBox.trimmedSpoken("\t\u{200B}\n") == "\u{200B}")
        #expect(ZeusTagSpokenBox.trimmedSpoken("\u{200B}hi") == "\u{200B}hi")
        #expect(ZeusTagSpokenBox.trimmedSpoken("hi\u{200B}") == "hi\u{200B}")
        #expect(ZeusTagSpokenBox.trimmedSpoken(" \t\n\r\u{00A0}") == "")
        #expect(ZeusTagSpokenBox.trimmedSpoken("") == "")
        #expect(ZeusTagSpokenBox.trimmedSpoken("\u{000B}hi") == "\u{000B}hi")
        #expect(ZeusTagSpokenBox.trimmedSpoken("\u{3000}hi") == "\u{3000}hi")
        #expect(ZeusTagSpokenBox.trimmedSpoken(" \thi\r\n") == "hi")
        #expect(ZeusTagSpokenBox.trimmedSpoken("\u{00A0}hi\u{00A0}") == "hi")
        #expect(ZeusTagSpokenBox.trimmedSpoken("hi") == "hi")
    }

    @Test func aZeroWidthSpaceStaysWhenTrailingTagsAreStripped() {
        var keptTags: [ZeusTag] = []
        let kept = ZeusTagParser.stripTrailingTags(from: "\u{200B}", into: &keptTags)
        #expect(kept == "\u{200B}")
        #expect(keptTags.isEmpty)
        var paddedTags: [ZeusTag] = []
        let padded = ZeusTagParser.stripTrailingTags(from: " \u{200B} ", into: &paddedTags)
        #expect(padded == "\u{200B}")
        #expect(paddedTags.isEmpty)
        var blankTags: [ZeusTag] = []
        let blanks = ZeusTagParser.stripTrailingTags(from: " \t\n\r\u{00A0}", into: &blankTags)
        #expect(blanks == "")
        #expect(blankTags.isEmpty)
        var ideographTags: [ZeusTag] = []
        let ideograph = ZeusTagParser.stripTrailingTags(from: "\u{3000}hi", into: &ideographTags)
        #expect(ideograph == "\u{3000}hi")
        var verticalTags: [ZeusTag] = []
        let vertical = ZeusTagParser.stripTrailingTags(from: "\u{000B}hi", into: &verticalTags)
        #expect(vertical == "\u{000B}hi")
        var nobreakTags: [ZeusTag] = []
        let nobreak = ZeusTagParser.stripTrailingTags(from: "\u{00A0}hi\u{00A0}", into: &nobreakTags)
        #expect(nobreak == "hi")
        var plainTags: [ZeusTag] = []
        let plain = ZeusTagParser.stripTrailingTags(from: " hi ", into: &plainTags)
        #expect(plain == "hi")
    }
}
