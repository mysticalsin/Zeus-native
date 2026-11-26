import Foundation
import Testing
@testable import ZeusCore

@Suite("Lyrics limits box")
struct LyricsLimitsBoxTests {
    @Test func blankScalarsAreNamedAndLeaveAZeroWidthSpace() {
        #expect(LyricsLimitsBox.blankScalars.contains(" "))
        #expect(LyricsLimitsBox.blankScalars.contains("\t"))
        #expect(LyricsLimitsBox.blankScalars.contains("\n"))
        #expect(LyricsLimitsBox.blankScalars.contains("\u{000B}"))
        #expect(LyricsLimitsBox.blankScalars.contains("\u{000C}"))
        #expect(LyricsLimitsBox.blankScalars.contains("\r"))
        #expect(LyricsLimitsBox.blankScalars.contains("\u{0085}"))
        #expect(LyricsLimitsBox.blankScalars.contains("\u{00A0}"))
        #expect(LyricsLimitsBox.blankScalars.contains("\u{1680}"))
        #expect(LyricsLimitsBox.blankScalars.contains("\u{2000}"))
        #expect(LyricsLimitsBox.blankScalars.contains("\u{200A}"))
        #expect(LyricsLimitsBox.blankScalars.contains("\u{2028}"))
        #expect(LyricsLimitsBox.blankScalars.contains("\u{2029}"))
        #expect(LyricsLimitsBox.blankScalars.contains("\u{202F}"))
        #expect(LyricsLimitsBox.blankScalars.contains("\u{205F}"))
        #expect(LyricsLimitsBox.blankScalars.contains("\u{3000}"))
        #expect(!LyricsLimitsBox.blankScalars.contains("\u{200B}"))
        #expect(LyricsLimitsBox.trimmedLine("\u{200B}") == "\u{200B}")
        #expect(LyricsLimitsBox.trimmedLine(" \u{200B} ") == "\u{200B}")
        #expect(LyricsLimitsBox.trimmedLine(" \t\n\u{00A0}\u{3000}") == "")
    }

    @Test func aLineOfOnlyNamedBlanksIsEmpty() {
        #expect(LyricsLimitsBox.trimmedLine("") == "")
        #expect(LyricsLimitsBox.trimmedLine(" \t\n\r") == "")
        #expect(LyricsLimitsBox.trimmedLine("\u{00A0}") == "")
        #expect(LyricsLimitsBox.trimmedLine("\u{1680}\u{2000}\u{2028}\u{202F}\u{205F}\u{3000}") == "")
        #expect(LyricsLimitsBox.trimmedLine("\u{200B}") == "\u{200B}")
    }

    @Test func aZeroWidthSpaceStaysInsideTheLine() {
        #expect(LyricsLimitsBox.trimmedLine("\u{00A0}\u{200B}\u{00A0}") == "\u{200B}")
        #expect(LyricsLimitsBox.trimmedLine("\u{200B}la") == "\u{200B}la")
        #expect(LyricsLimitsBox.trimmedLine("la\u{200B}") == "la\u{200B}")
        #expect(LyricsLimitsBox.trimmedLine(" \nla\t") == "la")
    }

    @Test func aCutThatEndsOnAZeroWidthSpaceKeepsIt() {
        let limit = LyricsLimits.maxLineCharacters
        let marks = String(repeating: "\u{200B}", count: limit + 5)
        #expect(LyricsLimits.clipped(marks) == String(repeating: "\u{200B}", count: limit))
        let short = "\u{200B}"
        #expect(LyricsLimits.clipped(short) == short)
        let kept = String(repeating: "a", count: limit - 1) + "\u{200B}" + "tail"
        #expect(LyricsLimits.clipped(kept) == String(repeating: "a", count: limit - 1) + "\u{200B}")
        let lines = LyricsLimits.clamped([LyricLine(time: 1, text: marks)])
        #expect(lines.count == 1)
        #expect(lines[0].text == String(repeating: "\u{200B}", count: limit))
        #expect(lines[0].time == 1)
    }

    @Test func namedBlanksAtTheCutAreRemovedAndARealLineStays() {
        let limit = LyricsLimits.maxLineCharacters
        let cutInSpace = String(repeating: "a", count: limit - 1) + " tail"
        #expect(LyricsLimits.clipped(cutInSpace) == String(repeating: "a", count: limit - 1))
        let blanks = String(repeating: "\u{00A0}", count: limit + 2)
        #expect(LyricsLimits.clipped(blanks) == "")
        let spaces = String(repeating: " ", count: limit) + "more"
        #expect(LyricsLimits.clipped(spaces) == "")
        let exact = String(repeating: "a", count: limit)
        #expect(LyricsLimits.clipped(exact) == exact)
        #expect(LyricsLimits.clipped("short") == "short")
        let marked = String(repeating: "a", count: limit - 1) + "\u{200B} more"
        #expect(LyricsLimits.clipped(marked) == String(repeating: "a", count: limit - 1) + "\u{200B}")
    }
}
