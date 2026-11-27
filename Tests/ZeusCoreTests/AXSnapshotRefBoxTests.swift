import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays in an accessibility snapshot ref. These tests name the blanks.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("AX snapshot ref box")
struct AXSnapshotRefBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(AXSnapshotRefBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(AXSnapshotRefBox.blankScalars.count == 5)
        #expect(AXSnapshotRefBox.blankScalars.contains(" "))
        #expect(AXSnapshotRefBox.blankScalars.contains("\t"))
        #expect(AXSnapshotRefBox.blankScalars.contains("\n"))
        #expect(AXSnapshotRefBox.blankScalars.contains("\r"))
        #expect(AXSnapshotRefBox.blankScalars.contains("\u{00A0}"))
        #expect(!AXSnapshotRefBox.blankScalars.contains("\u{200B}"))
        #expect(!AXSnapshotRefBox.blankScalars.contains("\u{000B}"))
        #expect(!AXSnapshotRefBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysInTheTrimmedRef() {
        #expect(AXSnapshotRefBox.trimmedRef("\u{200B}") == "\u{200B}")
        #expect(AXSnapshotRefBox.trimmedRef(" \u{200B} ") == "\u{200B}")
        #expect(AXSnapshotRefBox.trimmedRef("\t\u{200B}\n") == "\u{200B}")
        #expect(AXSnapshotRefBox.trimmedRef("\u{200B}s4:e1") == "\u{200B}s4:e1")
        #expect(AXSnapshotRefBox.trimmedRef("s4:e1\u{200B}") == "s4:e1\u{200B}")
        #expect(AXSnapshotRefBox.trimmedRef(" \t\n\r\u{00A0}") == "")
        #expect(AXSnapshotRefBox.trimmedRef("") == "")
        #expect(AXSnapshotRefBox.trimmedRef("\u{000B}s4:e1") == "\u{000B}s4:e1")
        #expect(AXSnapshotRefBox.trimmedRef("\u{3000}s4:e1") == "\u{3000}s4:e1")
        #expect(AXSnapshotRefBox.trimmedRef(" \ts4:e1\r\n") == "s4:e1")
        #expect(AXSnapshotRefBox.trimmedRef("\u{00A0}s4:e1\u{00A0}") == "s4:e1")
        #expect(AXSnapshotRefBox.trimmedRef("s4\u{00A0}e1") == "s4\u{00A0}e1")
    }

    @Test func aZeroWidthSpaceStaysInTheSnapshotRef() {
        let zwsp = "\u{200B}"
        #expect(AXSnapshotBox.lookup(zwsp, snapshot: 4, count: 2) == .malformed)
        #expect(AXSnapshotBox.lookup("\u{200B}s4:e1", snapshot: 4, count: 2) == .malformed)
        #expect(AXSnapshotBox.lookup(" \u{200B} ", snapshot: 4, count: 2) == .malformed)
        #expect(AXSnapshotBox.lookup("   ", snapshot: 4, count: 2) == .malformed)
        #expect(AXSnapshotBox.lookup(" \n ", snapshot: 4, count: 2) == .malformed)
        #expect(AXSnapshotBox.lookup("\u{00A0}", snapshot: 4, count: 2) == .malformed)
        #expect(AXSnapshotBox.lookup(" \t\n\r\u{00A0}", snapshot: 4, count: 2) == .malformed)
        #expect(AXSnapshotBox.lookup("\u{000B}s4:e1", snapshot: 4, count: 2) == .malformed)
        #expect(AXSnapshotBox.lookup("\u{3000}s4:e1", snapshot: 4, count: 2) == .malformed)
        #expect(AXSnapshotBox.lookup("\u{00A0}s4:e1\u{00A0}", snapshot: 4, count: 2) == .found(0))
        #expect(AXSnapshotBox.lookup("\n\ts4:e1\r", snapshot: 4, count: 2) == .found(0))
        #expect(AXSnapshotBox.lookup("  [S12:E40] ", snapshot: 12, count: 40) == .found(39))
    }
}
