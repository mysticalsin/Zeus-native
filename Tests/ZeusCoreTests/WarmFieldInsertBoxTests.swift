import Foundation
import Testing
@testable import ZeusCore

@Suite("Warm field insert box")
struct WarmFieldInsertBoxTests {
    @Test func blankScalarsAreNamedAndLeaveAZeroWidthSpace() {
        #expect(WarmFieldInsertBox.blankScalars.contains(" "))
        #expect(WarmFieldInsertBox.blankScalars.contains("\t"))
        #expect(WarmFieldInsertBox.blankScalars.contains("\n"))
        #expect(WarmFieldInsertBox.blankScalars.contains("\u{000B}"))
        #expect(WarmFieldInsertBox.blankScalars.contains("\u{000C}"))
        #expect(WarmFieldInsertBox.blankScalars.contains("\r"))
        #expect(WarmFieldInsertBox.blankScalars.contains("\u{0085}"))
        #expect(WarmFieldInsertBox.blankScalars.contains("\u{00A0}"))
        #expect(WarmFieldInsertBox.blankScalars.contains("\u{1680}"))
        #expect(WarmFieldInsertBox.blankScalars.contains("\u{2000}"))
        #expect(WarmFieldInsertBox.blankScalars.contains("\u{2001}"))
        #expect(WarmFieldInsertBox.blankScalars.contains("\u{2002}"))
        #expect(WarmFieldInsertBox.blankScalars.contains("\u{2003}"))
        #expect(WarmFieldInsertBox.blankScalars.contains("\u{2004}"))
        #expect(WarmFieldInsertBox.blankScalars.contains("\u{2005}"))
        #expect(WarmFieldInsertBox.blankScalars.contains("\u{2006}"))
        #expect(WarmFieldInsertBox.blankScalars.contains("\u{2007}"))
        #expect(WarmFieldInsertBox.blankScalars.contains("\u{2008}"))
        #expect(WarmFieldInsertBox.blankScalars.contains("\u{2009}"))
        #expect(WarmFieldInsertBox.blankScalars.contains("\u{200A}"))
        #expect(WarmFieldInsertBox.blankScalars.contains("\u{2028}"))
        #expect(WarmFieldInsertBox.blankScalars.contains("\u{2029}"))
        #expect(WarmFieldInsertBox.blankScalars.contains("\u{202F}"))
        #expect(WarmFieldInsertBox.blankScalars.contains("\u{205F}"))
        #expect(WarmFieldInsertBox.blankScalars.contains("\u{3000}"))
        #expect(WarmFieldInsertBox.blankScalars.count == 25)
        #expect(!WarmFieldInsertBox.blankScalars.contains("\u{200B}"))
        #expect(WarmFieldInsertBox.trimmed("\u{200B}") == "\u{200B}")
        #expect(WarmFieldInsertBox.trimmed(" \u{200B} ") == "\u{200B}")
        #expect(WarmFieldInsertBox.trimmed(" \t\n\u{00A0}\u{3000}") == "")
    }

    @Test func aZeroWidthSpaceIsStillWritten() {
        let steps = WarmFieldInsertBox.steps(text: "\u{200B}", current: "", valueSettable: true,
                                             selectedTextSettable: true, secure: false)
        #expect(steps == [.setValue("\u{200B}"), .setSelectedText("\u{200B}")])
        #expect(WarmFieldInsert.steps(text: "\u{200B}", current: "", valueSettable: true,
                                      selectedTextSettable: true, secure: false) == steps)
        let padded = WarmFieldInsertBox.steps(text: " \u{200B}\n", current: "", valueSettable: true,
                                              selectedTextSettable: false, secure: false)
        #expect(padded == [.setValue("\u{200B}")])
    }

    @Test func namedBlanksAroundWordsAreRemoved() {
        let steps = WarmFieldInsertBox.steps(text: " hello ", current: "", valueSettable: true,
                                             selectedTextSettable: true, secure: false)
        #expect(steps == [.setValue("hello"), .setSelectedText("hello")])
        let wide = WarmFieldInsertBox.steps(text: "\u{00A0}hello\u{3000}", current: "", valueSettable: false,
                                            selectedTextSettable: true, secure: false)
        #expect(wide == [.setSelectedText("hello")])
        let kept = WarmFieldInsertBox.steps(text: "\u{200B}hello", current: "ab", valueSettable: true,
                                            selectedTextSettable: true, secure: false)
        #expect(kept == [.setSelectedText("\u{200B}hello"), .setValue("ab\u{200B}hello")])
        let trailing = WarmFieldInsertBox.steps(text: "hello\u{200B}", current: "\u{200B}", valueSettable: true,
                                                selectedTextSettable: false, secure: false)
        #expect(trailing == [.setValue("\u{200B}hello\u{200B}")])
        #expect(WarmFieldInsert.steps(text: " again ", current: "hello", valueSettable: true,
                                      selectedTextSettable: true, secure: false)
                == [.setSelectedText("again"), .setValue("helloagain")])
    }

    @Test func aBlankBodyAndASecureFieldAreRefused() {
        #expect(WarmFieldInsertBox.steps(text: " \t\n\u{00A0}\u{2028}", current: "", valueSettable: true,
                                         selectedTextSettable: true, secure: false).isEmpty)
        #expect(WarmFieldInsertBox.steps(text: "secret", current: "", valueSettable: true,
                                         selectedTextSettable: true, secure: true).isEmpty)
        #expect(WarmFieldInsert.steps(text: " \u{200B} ", current: "kept", valueSettable: true,
                                      selectedTextSettable: true, secure: true).isEmpty)
        #expect(WarmFieldInsertBox.steps(text: "word", current: "", valueSettable: false,
                                         selectedTextSettable: false, secure: false).isEmpty)
        let onlyValue = WarmFieldInsertBox.steps(text: "word", current: "x", valueSettable: true,
                                                 selectedTextSettable: false, secure: false)
        #expect(onlyValue == [.setValue("xword")])
    }

    @Test func landedKeepsAZeroWidthSpaceAndStillFindsTheWords() {
        #expect(WarmFieldInsertBox.landed(fieldValue: "\u{200B}", selectedText: nil, expected: "\u{200B}"))
        #expect(WarmFieldInsertBox.landed(fieldValue: "hello again", selectedText: nil, expected: " again "))
        #expect(!WarmFieldInsertBox.landed(fieldValue: "hello", selectedText: "", expected: "again"))
        #expect(!WarmFieldInsertBox.landed(fieldValue: "   ", selectedText: nil, expected: " \t\n"))
        #expect(WarmFieldInsertBox.landed(fieldValue: nil, selectedText: "\u{200B}hi", expected: "\u{200B}hi"))
        #expect(!WarmFieldInsertBox.landed(fieldValue: "hi", selectedText: nil, expected: "\u{200B}"))
        #expect(WarmFieldInsert.landed(fieldValue: "hello again", selectedText: nil, expected: "again"))
    }
}
