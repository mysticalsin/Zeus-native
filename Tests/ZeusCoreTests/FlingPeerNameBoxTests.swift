import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays on a Fling peer name. These tests name the blanks.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Fling peer name box")
struct FlingPeerNameBoxTests {
    private let date = Date(timeIntervalSince1970: 1_700_000_000)
    private let downloads = URL(fileURLWithPath: "/Users/a/Downloads")
    private let inbox = URL(fileURLWithPath: "/Users/a/Library/Application Support/Zeus/Fling/Inbox")

    private func folder(_ peer: String) -> String {
        FlingSaveRules.destination(
            mode: .downloads,
            root: downloads,
            inbox: inbox,
            peer: peer,
            date: date,
            downloadsGranted: true,
            timeZone: TimeZone(identifier: "UTC")!
        ).lastPathComponent
    }

    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(FlingPeerNameBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(FlingPeerNameBox.blankScalars.count == 5)
        #expect(FlingPeerNameBox.blankScalars.contains(" "))
        #expect(FlingPeerNameBox.blankScalars.contains("\t"))
        #expect(FlingPeerNameBox.blankScalars.contains("\n"))
        #expect(FlingPeerNameBox.blankScalars.contains("\r"))
        #expect(FlingPeerNameBox.blankScalars.contains("\u{00A0}"))
        #expect(!FlingPeerNameBox.blankScalars.contains("\u{200B}"))
        #expect(!FlingPeerNameBox.blankScalars.contains("\u{000B}"))
        #expect(!FlingPeerNameBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysOnTheTrimmedPeer() {
        #expect(FlingPeerNameBox.trimmedPeer("\u{200B}") == "\u{200B}")
        #expect(FlingPeerNameBox.trimmedPeer(" \u{200B} ") == "\u{200B}")
        #expect(FlingPeerNameBox.trimmedPeer("\t\u{200B}\n") == "\u{200B}")
        #expect(FlingPeerNameBox.trimmedPeer("\u{200B}Tony") == "\u{200B}Tony")
        #expect(FlingPeerNameBox.trimmedPeer("Tony\u{200B}") == "Tony\u{200B}")
        #expect(FlingPeerNameBox.trimmedPeer(" \t\n\r\u{00A0}") == "")
        #expect(FlingPeerNameBox.trimmedPeer("") == "")
        #expect(FlingPeerNameBox.trimmedPeer("\u{000B}Tony") == "\u{000B}Tony")
        #expect(FlingPeerNameBox.trimmedPeer("\u{3000}Tony") == "\u{3000}Tony")
        #expect(FlingPeerNameBox.trimmedPeer(" \tTony\r\n") == "Tony")
        #expect(FlingPeerNameBox.trimmedPeer("\u{00A0}Tony\u{00A0}") == "Tony")
        #expect(FlingPeerNameBox.trimmedPeer("Tony") == "Tony")
    }

    @Test func aZeroWidthSpaceStaysOnAPeerFolder() {
        #expect(folder("\u{200B}") == "_ 2023-11-14 22.13.20")
        #expect(folder(" \u{200B} ") == "_ 2023-11-14 22.13.20")
        #expect(folder("\u{200B}Tony") == "_Tony 2023-11-14 22.13.20")
        #expect(folder("\u{3000}Tony") == "\u{3000}Tony 2023-11-14 22.13.20")
        #expect(folder("\u{000B}Tony") == "_Tony 2023-11-14 22.13.20")
        #expect(folder(" \t\n\r\u{00A0}") == "Mac 2023-11-14 22.13.20")
        #expect(folder("") == "Mac 2023-11-14 22.13.20")
        #expect(folder(" \tTony\r\n") == "Tony 2023-11-14 22.13.20")
        #expect(folder("\u{00A0}Tony\u{00A0}") == "Tony 2023-11-14 22.13.20")
        #expect(folder("Tony") == "Tony 2023-11-14 22.13.20")
        #expect(folder("Tony's Mac") == "Tony's Mac 2023-11-14 22.13.20")
    }
}
