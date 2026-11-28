import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays on the title trim inside `TodoMarkdown.parse`.
/// These tests name the blanks. Linux `CharacterSet.whitespaces` treats U+200B as blank.
@Suite("Todo markdown title box")
struct TodoMarkdownTitleBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(TodoMarkdownTitleBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(TodoMarkdownTitleBox.blankScalars.count == 5)
        #expect(TodoMarkdownTitleBox.blankScalars.contains(" "))
        #expect(TodoMarkdownTitleBox.blankScalars.contains("\t"))
        #expect(TodoMarkdownTitleBox.blankScalars.contains("\n"))
        #expect(TodoMarkdownTitleBox.blankScalars.contains("\r"))
        #expect(TodoMarkdownTitleBox.blankScalars.contains("\u{00A0}"))
        #expect(!TodoMarkdownTitleBox.blankScalars.contains("\u{200B}"))
        #expect(!TodoMarkdownTitleBox.blankScalars.contains("\u{000B}"))
        #expect(!TodoMarkdownTitleBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysOnTheTrimmedTitle() {
        #expect(TodoMarkdownTitleBox.trimmedTitle("\u{200B}") == "\u{200B}")
        #expect(TodoMarkdownTitleBox.trimmedTitle(" \u{200B} ") == "\u{200B}")
        #expect(TodoMarkdownTitleBox.trimmedTitle("\t\u{200B}\n") == "\u{200B}")
        #expect(TodoMarkdownTitleBox.trimmedTitle("\u{200B}Call") == "\u{200B}Call")
        #expect(TodoMarkdownTitleBox.trimmedTitle("Call\u{200B}") == "Call\u{200B}")
        #expect(TodoMarkdownTitleBox.trimmedTitle(" \t\n\r\u{00A0}") == "")
        #expect(TodoMarkdownTitleBox.trimmedTitle("") == "")
        #expect(TodoMarkdownTitleBox.trimmedTitle("\u{000B}Call") == "\u{000B}Call")
        #expect(TodoMarkdownTitleBox.trimmedTitle("\u{3000}Call") == "\u{3000}Call")
        #expect(TodoMarkdownTitleBox.trimmedTitle(" \tCall\r\n") == "Call")
        #expect(TodoMarkdownTitleBox.trimmedTitle("\u{00A0}Call\u{00A0}") == "Call")
        #expect(TodoMarkdownTitleBox.trimmedTitle("Call") == "Call")
        #expect(TodoMarkdownTitleBox.trimmedTitle("Ca\u{200B}ll") == "Ca\u{200B}ll")
        #expect(TodoMarkdownTitleBox.trimmedTitle("\n") == "")
        #expect(TodoMarkdownTitleBox.trimmedTitle("\r") == "")
        #expect(TodoMarkdownTitleBox.trimmedTitle("\n\u{200B}\r") == "\u{200B}")
    }

    @Test func aZeroWidthSpaceStaysOnTheParsedTitle() {
        #expect(parsed("- [ ] \u{200B}") == line("\u{200B}"))
        #expect(parsed("- [ ]  \u{200B}  ") == line("\u{200B}"))
        #expect(parsed("- [ ] \t\u{200B}\n") == line("\u{200B}"))
        #expect(parsed("- [ ] \n\u{200B}\r") == line("\u{200B}"))
        #expect(parsed("- [ ] \u{200B}Call Anna") == line("\u{200B}Call Anna"))
        #expect(parsed("- [ ] Call Anna\u{200B}") == line("Call Anna\u{200B}"))
        #expect(parsed("- [ ] Call\u{200B}Anna") == line("Call\u{200B}Anna"))
        #expect(parsed("- [ ] \u{3000}") == line("\u{3000}"))
        #expect(parsed("- [ ] \u{3000}Call Anna") == line("\u{3000}Call Anna"))
        #expect(parsed("- [ ] \u{000B}") == line("\u{000B}"))
        #expect(parsed("- [ ] \u{000B}Call Anna") == line("\u{000B}Call Anna"))
        #expect(parsed("- [ ]  \tCall Anna\r\n") == line("Call Anna"))
        #expect(parsed("- [ ] \u{00A0}Call Anna\u{00A0}") == line("Call Anna"))
        #expect(parsed("- [ ] Call Anna") == line("Call Anna"))
        #expect(parsed("- [ ] Call Anna 📅 2026-10-31") == line("Call Anna", due: "2026-10-31"))
        #expect(parsed("- [x] Call Anna") == line("Call Anna", done: true))
        #expect(parsed("  - [ ] Call Anna") == line("Call Anna", indent: "  "))
        #expect(parsed("* [ ] Call Anna") == line("Call Anna", bullet: "*"))
        #expect(parsed("- [ ] ") == nil)
        #expect(parsed("- [ ]") == nil)
        #expect(parsed("Call Anna") == nil)
        for blank in ["", " ", "\t", "\n", "\r", "\u{00A0}", " \t\n\r\u{00A0}", "  "] {
            #expect(parsed("- [ ] \(blank)") == nil)
        }
    }

    private func parsed(_ text: String) -> TodoMarkdown.Line? {
        TodoMarkdown.parse(line: text)
    }

    private func line(
        _ title: String,
        indent: String = "",
        bullet: Character = "-",
        done: Bool = false,
        due: String? = nil
    ) -> TodoMarkdown.Line {
        TodoMarkdown.Line(indent: indent, bullet: bullet, done: done, title: title, due: due)
    }
}
