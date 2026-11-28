import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays in the text left in front of a trailing tag. These tests name the blanks.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Zeus tag remainder box")
struct ZeusTagRemainderBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(ZeusTagRemainderBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(ZeusTagRemainderBox.blankScalars.count == 5)
        #expect(ZeusTagRemainderBox.blankScalars.contains(" "))
        #expect(ZeusTagRemainderBox.blankScalars.contains("\t"))
        #expect(ZeusTagRemainderBox.blankScalars.contains("\n"))
        #expect(ZeusTagRemainderBox.blankScalars.contains("\r"))
        #expect(ZeusTagRemainderBox.blankScalars.contains("\u{00A0}"))
        #expect(!ZeusTagRemainderBox.blankScalars.contains("\u{200B}"))
        #expect(!ZeusTagRemainderBox.blankScalars.contains("\u{000B}"))
        #expect(!ZeusTagRemainderBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysInTheTrimmedRemainder() {
        #expect(ZeusTagRemainderBox.trimmedRemainder("\u{200B}") == "\u{200B}")
        #expect(ZeusTagRemainderBox.trimmedRemainder(" \u{200B} ") == "\u{200B}")
        #expect(ZeusTagRemainderBox.trimmedRemainder("\t\u{200B}\n") == "\u{200B}")
        #expect(ZeusTagRemainderBox.trimmedRemainder("\u{200B}hi") == "\u{200B}hi")
        #expect(ZeusTagRemainderBox.trimmedRemainder("hi\u{200B}") == "hi\u{200B}")
        #expect(ZeusTagRemainderBox.trimmedRemainder(" \t\n\r\u{00A0}") == "")
        #expect(ZeusTagRemainderBox.trimmedRemainder("") == "")
        #expect(ZeusTagRemainderBox.trimmedRemainder("\u{000B}hi") == "\u{000B}hi")
        #expect(ZeusTagRemainderBox.trimmedRemainder("\u{3000}hi") == "\u{3000}hi")
        #expect(ZeusTagRemainderBox.trimmedRemainder(" \thi\r\n") == "hi")
        #expect(ZeusTagRemainderBox.trimmedRemainder("\u{00A0}hi\u{00A0}") == "hi")
        #expect(ZeusTagRemainderBox.trimmedRemainder("hi") == "hi")
    }

    @Test func aZeroWidthSpaceStaysInFrontOfATrailingTag() {
        var keptTags: [ZeusTag] = []
        let kept = ZeusTagParser.stripTrailingTags(from: "hi\u{200B}[POINT:10,20]", into: &keptTags)
        #expect(kept == "hi\u{200B}")
        #expect(keptTags == [.point(PointTarget(x: 10, y: 20))])
        var paddedTags: [ZeusTag] = []
        let padded = ZeusTagParser.stripTrailingTags(from: "a \u{200B} [POINT:10,20]", into: &paddedTags)
        #expect(padded == "a \u{200B}")
        #expect(paddedTags == [.point(PointTarget(x: 10, y: 20))])
        var blankTags: [ZeusTag] = []
        let blanks = ZeusTagParser.stripTrailingTags(from: " \t\n\r\u{00A0}[POINT:10,20]", into: &blankTags)
        #expect(blanks == "")
        #expect(blankTags == [.point(PointTarget(x: 10, y: 20))])
        var ideographTags: [ZeusTag] = []
        let ideograph = ZeusTagParser.stripTrailingTags(from: "hi\u{3000}[POINT:10,20]", into: &ideographTags)
        #expect(ideograph == "hi\u{3000}")
        var verticalTags: [ZeusTag] = []
        let vertical = ZeusTagParser.stripTrailingTags(from: "hi\u{000B}[POINT:10,20]", into: &verticalTags)
        #expect(vertical == "hi\u{000B}")
        var nobreakTags: [ZeusTag] = []
        let nobreak = ZeusTagParser.stripTrailingTags(from: "hi\u{00A0}[POINT:10,20]", into: &nobreakTags)
        #expect(nobreak == "hi")
        var plainTags: [ZeusTag] = []
        let plain = ZeusTagParser.stripTrailingTags(from: " hi [POINT:10,20]", into: &plainTags)
        #expect(plain == "hi")
        #expect(plainTags == [.point(PointTarget(x: 10, y: 20))])
    }
}
