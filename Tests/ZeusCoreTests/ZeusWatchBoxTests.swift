import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays in a watch label. These tests name the blanks.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Zeus watch box")
struct ZeusWatchBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(ZeusWatchBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(ZeusWatchBox.blankScalars.count == 5)
        #expect(ZeusWatchBox.blankScalars.contains(" "))
        #expect(ZeusWatchBox.blankScalars.contains("\t"))
        #expect(ZeusWatchBox.blankScalars.contains("\n"))
        #expect(ZeusWatchBox.blankScalars.contains("\r"))
        #expect(ZeusWatchBox.blankScalars.contains("\u{00A0}"))
        #expect(!ZeusWatchBox.blankScalars.contains("\u{200B}"))
        #expect(!ZeusWatchBox.blankScalars.contains("\u{000B}"))
        #expect(!ZeusWatchBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysInALabel() {
        #expect(ZeusWatchBox.trimmedLabel("\u{200B}") == "\u{200B}")
        #expect(ZeusWatchBox.trimmedLabel(" \u{200B} ") == "\u{200B}")
        #expect(ZeusWatchBox.trimmedLabel("\t\u{200B}\n") == "\u{200B}")
        #expect(ZeusWatchBox.trimmedLabel("\u{200B}Save") == "\u{200B}Save")
        #expect(ZeusWatchBox.trimmedLabel("Save\u{200B}") == "Save\u{200B}")
        #expect(ZeusWatchBox.trimmedLabel(" \t\n\r\u{00A0}") == "")
        #expect(ZeusWatchBox.trimmedLabel("\u{000B}Save") == "\u{000B}Save")
        #expect(ZeusWatchBox.trimmedLabel("\u{3000}Save") == "\u{3000}Save")
    }

    @Test func aZeroWidthSpaceDoesNotStopAnotherWatch() {
        #expect(labels(after: "\u{200B}Save") == ["Save the file", "Build"])
        #expect(labels(after: "\u{200B}") == ["Save the file", "Build"])
        #expect(labels(after: " \u{200B} ") == ["Save the file", "Build"])
        #expect(labels(after: "\u{000B}Save") == ["Save the file", "Build"])
        #expect(labels(after: "\u{3000}Save") == ["Save the file", "Build"])
        #expect(labels(after: " \t\n\r\u{00A0}Save\u{00A0} ") == ["Build"])
        #expect(labels(after: "\u{00A0}Build\u{00A0}") == ["Save the file"])
        #expect(labels(after: " \t\n\r\u{00A0}") == ["Save the file", "Build"])
        #expect(labels(after: "\u{200B}all") == ["Save the file", "Build"])
        #expect(labels(after: "\u{200B}watching") == ["Save the file", "Build"])
        #expect(labels(after: " \u{00A0}all\u{00A0} ") == [])
        #expect(labels(after: " watching ") == [])
        #expect(labels(after: "Save") == ["Build"])
    }
}

private func labels(after stopping: String) -> [String] {
    var registry = ZeusWatchRegistry(watches: [watch("Save the file"), watch("Build")])
    registry.stop(label: stopping)
    return registry.watches.map(\.label)
}

private func watch(_ label: String) -> ZeusWatch {
    ZeusWatch(
        id: UUID(),
        label: label,
        trigger: .shellTest(exitZeroWhen: "true"),
        created: Date(timeIntervalSince1970: 0)
    )
}
