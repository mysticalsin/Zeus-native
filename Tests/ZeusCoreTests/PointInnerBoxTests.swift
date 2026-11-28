import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays on the inner trim inside `ZeusTagParser.parsePoint`.
/// These tests name the blanks. Linux `CharacterSet.whitespaces` treats U+200B as blank.
@Suite("Point inner box")
struct PointInnerBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(PointInnerBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(PointInnerBox.blankScalars.count == 5)
        #expect(PointInnerBox.blankScalars.contains(" "))
        #expect(PointInnerBox.blankScalars.contains("\t"))
        #expect(PointInnerBox.blankScalars.contains("\n"))
        #expect(PointInnerBox.blankScalars.contains("\r"))
        #expect(PointInnerBox.blankScalars.contains("\u{00A0}"))
        #expect(!PointInnerBox.blankScalars.contains("\u{200B}"))
        #expect(!PointInnerBox.blankScalars.contains("\u{000B}"))
        #expect(!PointInnerBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysOnTheTrimmedInner() {
        #expect(PointInnerBox.trimmedInner("\u{200B}") == "\u{200B}")
        #expect(PointInnerBox.trimmedInner(" \u{200B} ") == "\u{200B}")
        #expect(PointInnerBox.trimmedInner("\t\u{200B}\n") == "\u{200B}")
        #expect(PointInnerBox.trimmedInner("\u{200B}none") == "\u{200B}none")
        #expect(PointInnerBox.trimmedInner("none\u{200B}") == "none\u{200B}")
        #expect(PointInnerBox.trimmedInner(" \t\n\r\u{00A0}") == "")
        #expect(PointInnerBox.trimmedInner("") == "")
        #expect(PointInnerBox.trimmedInner("\u{000B}none") == "\u{000B}none")
        #expect(PointInnerBox.trimmedInner("\u{3000}none") == "\u{3000}none")
        #expect(PointInnerBox.trimmedInner(" \tnone\r\n") == "none")
        #expect(PointInnerBox.trimmedInner("\u{00A0}none\u{00A0}") == "none")
        #expect(PointInnerBox.trimmedInner("none") == "none")
        #expect(PointInnerBox.trimmedInner("n\u{200B}one") == "n\u{200B}one")
        #expect(PointInnerBox.trimmedInner("\n") == "")
        #expect(PointInnerBox.trimmedInner("\r") == "")
        #expect(PointInnerBox.trimmedInner("\n\u{200B}\r") == "\u{200B}")
    }

    @Test func aZeroWidthSpaceStaysOnThePointDecision() {
        #expect(tags("[POINT:\u{200B}none]") == [])
        #expect(tags("[POINT:\u{200B}none]") != [.point(nil)])
        #expect(tags("[POINT: \u{200B}none ]") == [])
        #expect(tags("[POINT:\t\u{200B}none\n]") == [])
        #expect(tags("[POINT:none\u{200B}]") == [])
        #expect(tags("[POINT:none\u{200B}]") != [.point(nil)])
        #expect(tags("[POINT:\n\u{200B}\r]") == [])
        #expect(tags("[POINT:\u{3000}none]") == [])
        #expect(tags("[POINT:\u{3000}none]") != [.point(nil)])
        #expect(tags("[POINT:\u{000B}none]") == [])
        #expect(tags("[POINT:\u{000B}none]") != [.point(nil)])
        #expect(tags("[POINT:\nnone]") == [.point(nil)])
        #expect(tags("[POINT:\rnone]") == [.point(nil)])
        #expect(tags("[POINT:\u{00A0}none]") == [.point(nil)])
        #expect(tags("[POINT: \tnone\r\n]") == [.point(nil)])
        #expect(tags("[POINT:none]") == [.point(nil)])
        #expect(tags("[POINT: NONE ]") == [.point(nil)])
        #expect(tags("[POINT:  none  ]") == [.point(nil)])
        #expect(tags("[POINT:\u{00A0}none\u{00A0}]") == [.point(nil)])
        #expect(spoken("[POINT:\u{200B}none] hello") == "hello")
        #expect(tags("[POINT:\u{200B}none] hello") == [])
        #expect(tags("[POINT:10,20]") == [.point(PointTarget(x: 10, y: 20))])
        #expect(tags("[POINT:10, 20]") == [.point(PointTarget(x: 10, y: 20))])
        #expect(tags("[POINT:640,320:export button:screen2]") == [.point(PointTarget(x: 640, y: 320, label: "export button", screen: 2))])
        #expect(spoken("[POINT:none] hi") == "hi")
        #expect(tags("[POINT:none] hi") == [.point(nil)])
    }

    private func tags(_ reply: String) -> [ZeusTag] {
        ZeusTagParser.parse(reply).tags
    }

    private func spoken(_ reply: String) -> String {
        ZeusTagParser.parse(reply).spokenText
    }
}
