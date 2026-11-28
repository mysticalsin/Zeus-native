import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays on the coordinate trim inside `ZeusTagParser.parsePoint`.
/// These tests name the blanks. Linux `CharacterSet.whitespaces` treats U+200B as blank.
@Suite("Point coordinate box")
struct PointCoordBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(PointCoordBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(PointCoordBox.blankScalars.count == 5)
        #expect(PointCoordBox.blankScalars.contains(" "))
        #expect(PointCoordBox.blankScalars.contains("\t"))
        #expect(PointCoordBox.blankScalars.contains("\n"))
        #expect(PointCoordBox.blankScalars.contains("\r"))
        #expect(PointCoordBox.blankScalars.contains("\u{00A0}"))
        #expect(!PointCoordBox.blankScalars.contains("\u{200B}"))
        #expect(!PointCoordBox.blankScalars.contains("\u{000B}"))
        #expect(!PointCoordBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysOnTheTrimmedCoordinate() {
        #expect(PointCoordBox.trimmedCoord("\u{200B}") == "\u{200B}")
        #expect(PointCoordBox.trimmedCoord(" \u{200B} ") == "\u{200B}")
        #expect(PointCoordBox.trimmedCoord("\t\u{200B}\n") == "\u{200B}")
        #expect(PointCoordBox.trimmedCoord("\u{200B}10") == "\u{200B}10")
        #expect(PointCoordBox.trimmedCoord("10\u{200B}") == "10\u{200B}")
        #expect(PointCoordBox.trimmedCoord(" \t\n\r\u{00A0}") == "")
        #expect(PointCoordBox.trimmedCoord("") == "")
        #expect(PointCoordBox.trimmedCoord("\u{000B}10") == "\u{000B}10")
        #expect(PointCoordBox.trimmedCoord("\u{3000}10") == "\u{3000}10")
        #expect(PointCoordBox.trimmedCoord(" \t10\r\n") == "10")
        #expect(PointCoordBox.trimmedCoord("\u{00A0}10\u{00A0}") == "10")
        #expect(PointCoordBox.trimmedCoord("10") == "10")
        #expect(PointCoordBox.trimmedCoord("1\u{200B}0") == "1\u{200B}0")
        #expect(PointCoordBox.trimmedCoord("\n") == "")
        #expect(PointCoordBox.trimmedCoord("\r") == "")
        #expect(PointCoordBox.trimmedCoord("\n\u{200B}\r") == "\u{200B}")
    }

    @Test func aZeroWidthSpaceStaysOnTheCoordinateDecision() {
        #expect(tags("[POINT:10\u{200B},20]") == [])
        #expect(tags("[POINT:10\u{200B},20]") != [.point(PointTarget(x: 10, y: 20))])
        #expect(tags("[POINT:10,\u{200B}20]") == [])
        #expect(tags("[POINT:10,\u{200B}20]") != [.point(PointTarget(x: 10, y: 20))])
        #expect(tags("[POINT:10\u{3000},20]") == [])
        #expect(tags("[POINT:10\u{3000},20]") != [.point(PointTarget(x: 10, y: 20))])
        #expect(tags("[POINT:10\u{000B},20]") == [])
        #expect(tags("[POINT:10\u{000B},20]") != [.point(PointTarget(x: 10, y: 20))])
        #expect(tags("[POINT:10\n,20]") == [.point(PointTarget(x: 10, y: 20))])
        #expect(tags("[POINT:10,\r20]") == [.point(PointTarget(x: 10, y: 20))])
        #expect(tags("[POINT:\n10,20]") == [.point(PointTarget(x: 10, y: 20))])
        #expect(tags("[POINT:10,20\n]") == [.point(PointTarget(x: 10, y: 20))])
        #expect(tags("[POINT:10\n, 20]") == [.point(PointTarget(x: 10, y: 20))])
        #expect(tags("[POINT: 10\r,20]") == [.point(PointTarget(x: 10, y: 20))])
        #expect(tags("[POINT:10, 20]") == [.point(PointTarget(x: 10, y: 20))])
        #expect(tags("[POINT:10,\t20]") == [.point(PointTarget(x: 10, y: 20))])
        #expect(tags("[POINT: \t10 , 20\t ]") == [.point(PointTarget(x: 10, y: 20))])
        #expect(tags("[POINT:10\u{00A0},20]") == [.point(PointTarget(x: 10, y: 20))])
        #expect(tags("[POINT:\u{00A0}10,20\u{00A0}]") == [.point(PointTarget(x: 10, y: 20))])
        #expect(tags("[POINT:10,20]") == [.point(PointTarget(x: 10, y: 20))])
        #expect(tags("[POINT:\u{200B}10,20]") == [.point(PointTarget(x: 10, y: 20))])
        #expect(tags("[POINT:10,20\u{200B}]") == [.point(PointTarget(x: 10, y: 20))])
        #expect(tags("[POINT:640,320:export button:screen2]") == [.point(PointTarget(x: 640, y: 320, label: "export button", screen: 2))])
        #expect(spoken("[POINT:10\u{200B},20] hello") == "hello")
        #expect(tags("[POINT:10\u{200B},20] hello") == [])
        #expect(tags("[POINT:10\u{200B},20] hello") != [.point(PointTarget(x: 10, y: 20))])
    }

    private func tags(_ reply: String) -> [ZeusTag] {
        ZeusTagParser.parse(reply).tags
    }

    private func spoken(_ reply: String) -> String {
        ZeusTagParser.parse(reply).spokenText
    }
}
