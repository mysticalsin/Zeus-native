import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays in a markdown line. These tests name the blanks.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Markdown line box")
struct MarkdownLineBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(MarkdownLineBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(MarkdownLineBox.blankScalars.count == 5)
        #expect(MarkdownLineBox.blankScalars.contains(" "))
        #expect(MarkdownLineBox.blankScalars.contains("\t"))
        #expect(MarkdownLineBox.blankScalars.contains("\n"))
        #expect(MarkdownLineBox.blankScalars.contains("\r"))
        #expect(MarkdownLineBox.blankScalars.contains("\u{00A0}"))
        #expect(!MarkdownLineBox.blankScalars.contains("\u{200B}"))
        #expect(!MarkdownLineBox.blankScalars.contains("\u{000B}"))
        #expect(!MarkdownLineBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysInTheTrimmedText() {
        #expect(MarkdownLineBox.trimmedText("\u{200B}") == "\u{200B}")
        #expect(MarkdownLineBox.trimmedText(" \u{200B} ") == "\u{200B}")
        #expect(MarkdownLineBox.trimmedText("\t\u{200B}\n") == "\u{200B}")
        #expect(MarkdownLineBox.trimmedText("\u{200B}Hello") == "\u{200B}Hello")
        #expect(MarkdownLineBox.trimmedText("Hello\u{200B}") == "Hello\u{200B}")
        #expect(MarkdownLineBox.trimmedText(" \t\n\r\u{00A0}") == "")
        #expect(MarkdownLineBox.trimmedText("") == "")
        #expect(MarkdownLineBox.trimmedText("\u{000B}Hello") == "\u{000B}Hello")
        #expect(MarkdownLineBox.trimmedText("\u{3000}Hello") == "\u{3000}Hello")
        #expect(MarkdownLineBox.trimmedText(" \tHello\r\n") == "Hello")
        #expect(MarkdownLineBox.trimmedText("\u{00A0}Hello\u{00A0}") == "Hello")
        #expect(MarkdownLineBox.trimmedText("Hello\u{00A0}there") == "Hello\u{00A0}there")
    }

    @Test func aZeroWidthSpaceStaysInTheParsedLine() {
        let zwsp = "\u{200B}"
        let item = MarkdownBlock.Item(text: zwsp, depth: 0, number: nil, checked: nil)
        #expect(MarkdownBlock.parse(zwsp) == [.paragraph(zwsp)])
        #expect(MarkdownBlock.parse(" \(zwsp) ") == [.paragraph(zwsp)])
        #expect(MarkdownBlock.parse("\t\(zwsp)\n") == [.paragraph(zwsp)])
        #expect(MarkdownBlock.parse("\(zwsp)Hello") == [.paragraph("\(zwsp)Hello")])
        #expect(MarkdownBlock.parse("Hello\(zwsp)") == [.paragraph("Hello\(zwsp)")])
        #expect(MarkdownBlock.parse(" \t\n\r\u{00A0}") == [])
        #expect(MarkdownBlock.parse("\u{000B}Hello") == [.paragraph("\u{000B}Hello")])
        #expect(MarkdownBlock.parse("\u{3000}Hello") == [.paragraph("\u{3000}Hello")])
        #expect(MarkdownBlock.parse(" \tHello\r\n") == [.paragraph("Hello")])
        #expect(MarkdownBlock.parse("\u{00A0}Hello\u{00A0}") == [.paragraph("Hello")])
        #expect(MarkdownBlock.parse("Hello\u{00A0}there") == [.paragraph("Hello\u{00A0}there")])
        #expect(MarkdownBlock.parse("# \(zwsp)") == [.heading(level: 1, text: zwsp)])
        #expect(MarkdownBlock.parse("# \(zwsp)Intro") == [.heading(level: 1, text: "\(zwsp)Intro")])
        #expect(MarkdownBlock.parse("# \u{00A0}Intro\u{00A0}") == [.heading(level: 1, text: "Intro")])
        #expect(MarkdownBlock.parse("> \(zwsp)") == [.quote(zwsp)])
        #expect(MarkdownBlock.parse("- \(zwsp)") == [.list(ordered: false, items: [item])])
        #expect(MarkdownBlock.parse("- \u{00A0}item\u{00A0}") == [.list(ordered: false, items: [
            .init(text: "item", depth: 0, number: nil, checked: nil),
        ])])
        #expect(MarkdownBlock.parse("```\(zwsp)\ncode\n```") == [.code(language: zwsp, text: "code")])
        #expect(MarkdownBlock.parse("```\u{00A0}\ncode\n```") == [.code(language: nil, text: "code")])
    }
}
