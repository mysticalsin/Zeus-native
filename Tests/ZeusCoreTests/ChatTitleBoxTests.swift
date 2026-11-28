import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays on a chat title. These tests name the blanks.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Chat title box")
struct ChatTitleBoxTests {
    private let asked = Date(timeIntervalSince1970: 1_700_000_000)

    private func shown(_ title: String, question: String? = nil) -> String {
        var messages: [ChatMessage] = []
        if let question {
            messages.append(ChatMessage(role: .user, text: question, date: asked))
        }
        return ChatConversation(title: title, createdAt: asked, messages: messages).displayTitle
    }

    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(ChatTitleBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(ChatTitleBox.blankScalars.count == 5)
        #expect(ChatTitleBox.blankScalars.contains(" "))
        #expect(ChatTitleBox.blankScalars.contains("\t"))
        #expect(ChatTitleBox.blankScalars.contains("\n"))
        #expect(ChatTitleBox.blankScalars.contains("\r"))
        #expect(ChatTitleBox.blankScalars.contains("\u{00A0}"))
        #expect(!ChatTitleBox.blankScalars.contains("\u{200B}"))
        #expect(!ChatTitleBox.blankScalars.contains("\u{000B}"))
        #expect(!ChatTitleBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysOnTheTrimmedTitle() {
        #expect(ChatTitleBox.trimmedTitle("\u{200B}") == "\u{200B}")
        #expect(ChatTitleBox.trimmedTitle(" \u{200B} ") == "\u{200B}")
        #expect(ChatTitleBox.trimmedTitle("\t\u{200B}\n") == "\u{200B}")
        #expect(ChatTitleBox.trimmedTitle("\u{200B}Roadmap") == "\u{200B}Roadmap")
        #expect(ChatTitleBox.trimmedTitle("Roadmap\u{200B}") == "Roadmap\u{200B}")
        #expect(ChatTitleBox.trimmedTitle(" \t\n\r\u{00A0}") == "")
        #expect(ChatTitleBox.trimmedTitle("") == "")
        #expect(ChatTitleBox.trimmedTitle("\u{000B}Roadmap") == "\u{000B}Roadmap")
        #expect(ChatTitleBox.trimmedTitle("\u{3000}Roadmap") == "\u{3000}Roadmap")
        #expect(ChatTitleBox.trimmedTitle(" \tRoadmap\r\n") == "Roadmap")
        #expect(ChatTitleBox.trimmedTitle("\u{00A0}Roadmap\u{00A0}") == "Roadmap")
        #expect(ChatTitleBox.trimmedTitle("Roadmap") == "Roadmap")
    }

    @Test func aZeroWidthSpaceStaysOnTheShownTitle() {
        #expect(shown("\u{200B}") == "\u{200B}")
        #expect(shown(" \u{200B} ") == "\u{200B}")
        #expect(shown("\u{200B}", question: "Hello") == "\u{200B}")
        #expect(shown("\u{200B}Roadmap") == "\u{200B}Roadmap")
        #expect(shown("Roadmap\u{200B}") == "Roadmap\u{200B}")
        #expect(shown("\u{3000}Roadmap") == "\u{3000}Roadmap")
        #expect(shown("\u{000B}Roadmap") == "\u{000B}Roadmap")
        #expect(shown(" \t\n\r\u{00A0}") == "New chat")
        #expect(shown(" \t\n\r\u{00A0}", question: "Hello") == "Hello")
        #expect(shown("", question: "Hello") == "Hello")
        #expect(shown(" \tRoadmap\r\n") == "Roadmap")
        #expect(shown("\u{00A0}Roadmap\u{00A0}") == "Roadmap")
        #expect(shown("Roadmap") == "Roadmap")
        #expect(shown("New chat") == "New chat")
    }
}
