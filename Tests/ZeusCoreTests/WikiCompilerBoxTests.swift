import Foundation
import Testing
@testable import ZeusCore

/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank, so these tests name the scalars.
@Suite("Wiki compiler box")
struct WikiCompilerBoxTests {
    @Test func blankScalarsAreNamedAndLeaveAZeroWidthSpace() {
        #expect(WikiCompilerBox.blankScalars.contains(" "))
        #expect(WikiCompilerBox.blankScalars.contains("\t"))
        #expect(WikiCompilerBox.blankScalars.contains("\n"))
        #expect(WikiCompilerBox.blankScalars.contains("\u{000B}"))
        #expect(WikiCompilerBox.blankScalars.contains("\u{000C}"))
        #expect(WikiCompilerBox.blankScalars.contains("\r"))
        #expect(WikiCompilerBox.blankScalars.contains("\u{0085}"))
        #expect(WikiCompilerBox.blankScalars.contains("\u{00A0}"))
        #expect(WikiCompilerBox.blankScalars.contains("\u{1680}"))
        #expect(WikiCompilerBox.blankScalars.contains("\u{2000}"))
        #expect(WikiCompilerBox.blankScalars.contains("\u{200A}"))
        #expect(WikiCompilerBox.blankScalars.contains("\u{2028}"))
        #expect(WikiCompilerBox.blankScalars.contains("\u{2029}"))
        #expect(WikiCompilerBox.blankScalars.contains("\u{202F}"))
        #expect(WikiCompilerBox.blankScalars.contains("\u{205F}"))
        #expect(WikiCompilerBox.blankScalars.contains("\u{3000}"))
        #expect(!WikiCompilerBox.blankScalars.contains("\u{200B}"))
        #expect(WikiCompilerBox.trimmedTitle("\u{200B}") == "\u{200B}")
        #expect(WikiCompilerBox.trimmedTitle(" \u{200B} ") == "\u{200B}")
        #expect(WikiCompilerBox.trimmedTitle(" \t\n\u{00A0}\u{3000}") == "")
    }

    @Test func aTitleOfOnlyNamedBlanksIsEmpty() {
        #expect(WikiCompilerBox.trimmedTitle("") == "")
        #expect(WikiCompilerBox.trimmedTitle(" \t\n\r") == "")
        #expect(WikiCompilerBox.trimmedTitle("\u{00A0}") == "")
        #expect(WikiCompilerBox.trimmedTitle("\u{1680}\u{2000}\u{2028}\u{202F}\u{205F}\u{3000}") == "")
        #expect(WikiCompilerBox.trimmedTitle("\u{200B}") == "\u{200B}")
    }

    @Test func aZeroWidthSpaceStaysInsideTheTitle() {
        #expect(WikiCompilerBox.trimmedTitle("\u{00A0}\u{200B}\u{00A0}") == "\u{200B}")
        #expect(WikiCompilerBox.trimmedTitle("\u{200B}週次") == "\u{200B}週次")
        #expect(WikiCompilerBox.trimmedTitle("週次\u{200B}") == "週次\u{200B}")
        #expect(WikiCompilerBox.trimmedTitle(" \n週次\t") == "週次")
    }

    @Test func aZeroWidthSpaceIsItsOwnTopic() {
        let only = WikiCompiler.topicID(forTitle: "\u{200B}")
        #expect(only.hasPrefix("topic-t-"))
        #expect(only != "topic-meetings")
        #expect(only == WikiCompiler.topicID(forTitle: " \u{200B} "))
        #expect(WikiCompiler.topicID(forTitle: "\u{200B}週次会議") != WikiCompiler.topicID(forTitle: "週次会議"))
    }

    @Test func namedBlanksStillFoldIntoTheSameTopic() {
        #expect(WikiCompiler.topicID(forTitle: "\u{00A0}週次会議\u{3000}") == WikiCompiler.topicID(forTitle: "週次会議"))
        #expect(WikiCompiler.topicID(forTitle: "\u{00A0}\u{3000}") == "topic-meetings")
        #expect(WikiCompiler.topicID(forTitle: " \t\n") == "topic-meetings")
        #expect(WikiCompiler.topicID(forTitle: "  Weekly sync ") == "topic-weekly-sync")
        #expect(WikiCompiler.topicID(forTitle: "2026-11-07") == "topic-meetings")
    }
}
