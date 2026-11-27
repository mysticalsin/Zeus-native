import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays in a sanitized reply. These tests name the blanks.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Sanitized reply box")
struct SanitizedReplyBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(SanitizedReplyBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(SanitizedReplyBox.blankScalars.count == 5)
        #expect(SanitizedReplyBox.blankScalars.contains(" "))
        #expect(SanitizedReplyBox.blankScalars.contains("\t"))
        #expect(SanitizedReplyBox.blankScalars.contains("\n"))
        #expect(SanitizedReplyBox.blankScalars.contains("\r"))
        #expect(SanitizedReplyBox.blankScalars.contains("\u{00A0}"))
        #expect(!SanitizedReplyBox.blankScalars.contains("\u{200B}"))
        #expect(!SanitizedReplyBox.blankScalars.contains("\u{000B}"))
        #expect(!SanitizedReplyBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysInTheTrimmedText() {
        #expect(SanitizedReplyBox.trimmedText("\u{200B}") == "\u{200B}")
        #expect(SanitizedReplyBox.trimmedText(" \u{200B} ") == "\u{200B}")
        #expect(SanitizedReplyBox.trimmedText("\t\u{200B}\n") == "\u{200B}")
        #expect(SanitizedReplyBox.trimmedText("\u{200B}hello") == "\u{200B}hello")
        #expect(SanitizedReplyBox.trimmedText("hello\u{200B}") == "hello\u{200B}")
        #expect(SanitizedReplyBox.trimmedText(" \t\n\r\u{00A0}") == "")
        #expect(SanitizedReplyBox.trimmedText("") == "")
        #expect(SanitizedReplyBox.trimmedText("\u{000B}hello") == "\u{000B}hello")
        #expect(SanitizedReplyBox.trimmedText("\u{3000}hello") == "\u{3000}hello")
        #expect(SanitizedReplyBox.trimmedText(" \thello\r\n") == "hello")
        #expect(SanitizedReplyBox.trimmedText("\u{00A0}hello\u{00A0}") == "hello")
        #expect(SanitizedReplyBox.trimmedText("hello\u{00A0}there") == "hello\u{00A0}there")
    }

    @Test func aZeroWidthSpaceStaysInTheSanitizedReply() {
        let zwsp = "\u{200B}"
        #expect(ResponseSanitizer.sanitize(zwsp) == zwsp)
        #expect(ResponseSanitizer.sanitize(" \(zwsp) ") == zwsp)
        #expect(ResponseSanitizer.sanitize("\t\(zwsp)\n") == zwsp)
        #expect(ResponseSanitizer.sanitize("\(zwsp)hello") == "\(zwsp)hello")
        #expect(ResponseSanitizer.sanitize("hello\(zwsp)") == "hello\(zwsp)")
        #expect(ResponseSanitizer.sanitize(" \t\n\r\u{00A0}") == "")
        #expect(ResponseSanitizer.sanitize("") == "")
        #expect(ResponseSanitizer.sanitize("\u{000B}hello") == "\u{000B}hello")
        #expect(ResponseSanitizer.sanitize("\u{3000}hello") == "\u{3000}hello")
        #expect(ResponseSanitizer.sanitize(" \thello\r\n") == "hello")
        #expect(ResponseSanitizer.sanitize("\u{00A0}hello\u{00A0}") == "hello")
        #expect(ResponseSanitizer.sanitize("hello") == "hello")
    }
}
