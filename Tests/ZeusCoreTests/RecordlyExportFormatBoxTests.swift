import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays on the format trim inside `RecordlyExportSettings.parseFormats`.
/// These tests name the blanks. Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Recordly export format box")
struct RecordlyExportFormatBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(RecordlyExportFormatBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(RecordlyExportFormatBox.blankScalars.count == 5)
        #expect(RecordlyExportFormatBox.blankScalars.contains(" "))
        #expect(RecordlyExportFormatBox.blankScalars.contains("\t"))
        #expect(RecordlyExportFormatBox.blankScalars.contains("\n"))
        #expect(RecordlyExportFormatBox.blankScalars.contains("\r"))
        #expect(RecordlyExportFormatBox.blankScalars.contains("\u{00A0}"))
        #expect(!RecordlyExportFormatBox.blankScalars.contains("\u{200B}"))
        #expect(!RecordlyExportFormatBox.blankScalars.contains("\u{000B}"))
        #expect(!RecordlyExportFormatBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysOnTheTrimmedFormat() {
        #expect(RecordlyExportFormatBox.trimmedFormat("\u{200B}") == "\u{200B}")
        #expect(RecordlyExportFormatBox.trimmedFormat(" \u{200B} ") == "\u{200B}")
        #expect(RecordlyExportFormatBox.trimmedFormat("\t\u{200B}\n") == "\u{200B}")
        #expect(RecordlyExportFormatBox.trimmedFormat("\u{200B}mp4") == "\u{200B}mp4")
        #expect(RecordlyExportFormatBox.trimmedFormat("mp4\u{200B}") == "mp4\u{200B}")
        #expect(RecordlyExportFormatBox.trimmedFormat(" \t\n\r\u{00A0}") == "")
        #expect(RecordlyExportFormatBox.trimmedFormat("") == "")
        #expect(RecordlyExportFormatBox.trimmedFormat("\u{000B}mp4") == "\u{000B}mp4")
        #expect(RecordlyExportFormatBox.trimmedFormat("\u{3000}mp4") == "\u{3000}mp4")
        #expect(RecordlyExportFormatBox.trimmedFormat(" \tmp4\r\n") == "mp4")
        #expect(RecordlyExportFormatBox.trimmedFormat("\u{00A0}mp4\u{00A0}") == "mp4")
        #expect(RecordlyExportFormatBox.trimmedFormat("mp4") == "mp4")
        #expect(RecordlyExportFormatBox.trimmedFormat("mp\u{200B}4") == "mp\u{200B}4")
        #expect(RecordlyExportFormatBox.trimmedFormat("\n") == "")
        #expect(RecordlyExportFormatBox.trimmedFormat("\r") == "")
        #expect(RecordlyExportFormatBox.trimmedFormat("\n\u{200B}\r") == "\u{200B}")
    }

    @Test func aZeroWidthSpaceStaysWhenAFormatTokenIsParsed() {
        #expect(RecordlyExportFormatBox.trimmedFormat("\u{200B}") == "\u{200B}")
        #expect(RecordlyExportSettings.parseFormats("mp4,gif") == [.mp4, .gif])
        #expect(RecordlyExportSettings.parseFormats(" MP4 , GIF ") == [.mp4, .gif])
        #expect(RecordlyExportSettings.parseFormats("\u{00A0}mp4\u{00A0}") == [.mp4])
        #expect(RecordlyExportSettings.parseFormats("\nmp4\r") == [.mp4])
        #expect(RecordlyExportSettings.parseFormats(" \tmp4\r\n") == [.mp4])
        #expect(RecordlyExportSettings.parseFormats("\u{200B}") == [])
        #expect(RecordlyExportSettings.parseFormats("\u{200B}mp4") == [])
        #expect(RecordlyExportSettings.parseFormats("mp4\u{200B}") == [])
        #expect(RecordlyExportSettings.parseFormats("mp\u{200B}4") == [])
        #expect(RecordlyExportSettings.parseFormats("\u{3000}mp4") == [])
        #expect(RecordlyExportSettings.parseFormats("\u{000B}mp4") == [])
        #expect(RecordlyExportSettings.parseFormats("\u{200B},gif") == [.gif])
        #expect(RecordlyExportSettings.parseFormats("mp4,\u{200B},gif") == [.mp4, .gif])
        #expect(RecordlyExportSettings.parseFormats(" \t\n\r\u{00A0}") == [])
        #expect(RecordlyExportSettings.parseFormats("") == [])
        #expect(RecordlyExportSettings.parseFormats("\n\u{200B}\r") == [])
        #expect(RecordlyExportSettings.parseFormats("\u{200B}MP4") == [])
        #expect(RecordlyExportSettings.parseFormats("mp4, gif , ") == [.mp4, .gif])
    }
}
