import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays on the query trim inside `ChatConversation.matches`.
/// These tests name the blanks. Linux `CharacterSet.whitespaces` treats U+200B as blank.
@Suite("Chat query box")
struct ChatQueryBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(ChatQueryBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(ChatQueryBox.blankScalars.count == 5)
        #expect(ChatQueryBox.blankScalars.contains(" "))
        #expect(ChatQueryBox.blankScalars.contains("\t"))
        #expect(ChatQueryBox.blankScalars.contains("\n"))
        #expect(ChatQueryBox.blankScalars.contains("\r"))
        #expect(ChatQueryBox.blankScalars.contains("\u{00A0}"))
        #expect(!ChatQueryBox.blankScalars.contains("\u{200B}"))
        #expect(!ChatQueryBox.blankScalars.contains("\u{000B}"))
        #expect(!ChatQueryBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysOnTheTrimmedQuery() {
        #expect(ChatQueryBox.trimmedQuery("\u{200B}") == "\u{200B}")
        #expect(ChatQueryBox.trimmedQuery(" \u{200B} ") == "\u{200B}")
        #expect(ChatQueryBox.trimmedQuery("\t\u{200B}\n") == "\u{200B}")
        #expect(ChatQueryBox.trimmedQuery("\u{200B}Hello") == "\u{200B}Hello")
        #expect(ChatQueryBox.trimmedQuery("Hello\u{200B}") == "Hello\u{200B}")
        #expect(ChatQueryBox.trimmedQuery("He\u{200B}llo") == "He\u{200B}llo")
        #expect(ChatQueryBox.trimmedQuery(" \t\n\r\u{00A0}") == "")
        #expect(ChatQueryBox.trimmedQuery("") == "")
        #expect(ChatQueryBox.trimmedQuery("\u{000B}Hello") == "\u{000B}Hello")
        #expect(ChatQueryBox.trimmedQuery("\u{3000}Hello") == "\u{3000}Hello")
        #expect(ChatQueryBox.trimmedQuery(" \tHello\r\n") == "Hello")
        #expect(ChatQueryBox.trimmedQuery("\u{00A0}Hello\u{00A0}") == "Hello")
        #expect(ChatQueryBox.trimmedQuery("Hello") == "Hello")
        #expect(ChatQueryBox.trimmedQuery("\n") == "")
        #expect(ChatQueryBox.trimmedQuery("\r") == "")
        #expect(ChatQueryBox.trimmedQuery("\n\u{200B}\r") == "\u{200B}")
    }

    @Test func aZeroWidthSpaceStillCountsAsAChatQuery() {
        let hello = ChatConversation(title: "Hello")
        let marked = ChatConversation(title: "", messages: [ChatMessage(role: .user, text: "\u{200B}")])
        #expect(hello.matches("\u{200B}") == false)
        #expect(hello.matches(" \u{200B} ") == false)
        #expect(hello.matches("\u{200B}Hello") == false)
        #expect(hello.matches("Hello\u{200B}") == false)
        #expect(hello.matches("\u{3000}") == false)
        #expect(hello.matches("\u{3000}Hello") == false)
        #expect(hello.matches("\n"))
        #expect(hello.matches("\r"))
        #expect(marked.matches("\n\u{200B}\r"))
        #expect(marked.matches("\u{200B}"))
        #expect(marked.matches(" \u{200B} "))
        #expect(hello.matches("Hello"))
        #expect(hello.matches(" \tHello\r\n"))
        #expect(hello.matches("\u{00A0}Hello\u{00A0}"))
        #expect(hello.matches("  "))
        #expect(hello.matches(" "))
        #expect(hello.matches(""))
        #expect(hello.matches("   "))
        #expect(hello.matches("\u{00A0}"))
        #expect(hello.matches("\t\n\r"))
        #expect(hello.matches("ferry") == false)
        #expect(hello.matches("\u{000B}") == false)
        #expect(ChatConversation(title: "", messages: [ChatMessage(role: .user, text: "\u{000B}")]).matches("\u{000B}"))
        #expect(ChatConversation(title: "  Picnic  ").displayTitle == "Picnic")
        #expect(ChatConversation(title: "\u{200B}Picnic").displayTitle == "Picnic")
        #expect(marked.displayTitle == "")
    }
}
