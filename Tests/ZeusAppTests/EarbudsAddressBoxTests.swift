import Foundation
import Testing
@testable import Zeus

/// A zero-width space stays in a Bluetooth address. These tests name the blanks.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Earbuds address box")
struct EarbudsAddressBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(EarbudsAddressBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(EarbudsAddressBox.blankScalars.count == 5)
        #expect(EarbudsAddressBox.blankScalars.contains(" "))
        #expect(EarbudsAddressBox.blankScalars.contains("\t"))
        #expect(EarbudsAddressBox.blankScalars.contains("\n"))
        #expect(EarbudsAddressBox.blankScalars.contains("\r"))
        #expect(EarbudsAddressBox.blankScalars.contains("\u{00A0}"))
        #expect(!EarbudsAddressBox.blankScalars.contains("\u{200B}"))
        #expect(!EarbudsAddressBox.blankScalars.contains("\u{000B}"))
        #expect(!EarbudsAddressBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysInTheTrimmedAddress() {
        #expect(EarbudsAddressBox.trimmedAddress("\u{200B}") == "\u{200B}")
        #expect(EarbudsAddressBox.trimmedAddress(" \u{200B} ") == "\u{200B}")
        #expect(EarbudsAddressBox.trimmedAddress("\t\u{200B}\n") == "\u{200B}")
        #expect(EarbudsAddressBox.trimmedAddress("\u{200B}AA:BB") == "\u{200B}AA:BB")
        #expect(EarbudsAddressBox.trimmedAddress("AA:BB\u{200B}") == "AA:BB\u{200B}")
        #expect(EarbudsAddressBox.trimmedAddress(" \t\n\r\u{00A0}") == "")
        #expect(EarbudsAddressBox.trimmedAddress("") == "")
        #expect(EarbudsAddressBox.trimmedAddress("\u{000B}AA") == "\u{000B}AA")
        #expect(EarbudsAddressBox.trimmedAddress("\u{3000}AA") == "\u{3000}AA")
        #expect(EarbudsAddressBox.trimmedAddress(" \tAA:BB\r\n") == "AA:BB")
        #expect(EarbudsAddressBox.trimmedAddress("\u{00A0}AA:BB\u{00A0}") == "AA:BB")
        #expect(EarbudsAddressBox.trimmedAddress("AA:BB") == "AA:BB")
    }

    @Test func aZeroWidthSpaceStaysInTheAddressCheck() {
        #expect(EarbudsAddressBox.trimmedAddress(" \u{200B} ") == "\u{200B}")
        let feed = EarbudsBluetoothFeed.self
        let kept = earbuds("\u{200B}")
        #expect(feed.qualifies(kept))
        #expect(feed.qualifies(earbuds(" \u{200B} ")))
        #expect(feed.qualifies(earbuds("\u{3000}")))
        #expect(feed.qualifies(earbuds("\u{000B}AA")))
        #expect(!feed.qualifies(earbuds(" \t\n\r\u{00A0}")))
        #expect(!feed.qualifies(earbuds("")))
        #expect(feed.qualifies(earbuds("\u{00A0}AA:BB\u{00A0}")))
        let (watch, book) = feed.watchDisconnect(
            feed.Book(connectHeld: true), address: "\u{200B}", gate()
        )
        #expect(watch == .held)
        #expect(book.disconnects == ["\u{200B}"])
        let blanks = feed.watchDisconnect(book, address: " \t\n\r\u{00A0}", gate())
        #expect(blanks.0 == .ignored)
        #expect(blanks.1.disconnects == ["\u{200B}"])
        let started = feed.start(.empty, gate(devices: [earbuds("\u{200B}"), earbuds(" \n\t")]))
        #expect(started.0 == .started(
            feed.Book(connectHeld: true, disconnects: ["\u{200B}"]),
            devices: [earbuds("\u{200B}")]
        ))
        #expect(started.1.disconnects == ["\u{200B}"])
    }
}

private func earbuds(
    _ address: String,
    name: String = "Buds",
    paired: Bool = true,
    connected: Bool = true,
    major: UInt8 = EarbudsBluetoothFeed.AudioClass.major,
    minor: UInt8 = EarbudsBluetoothFeed.AudioClass.headset
) -> EarbudsBluetoothFeed.Record {
    EarbudsBluetoothFeed.Record(
        address: address, name: name, paired: paired,
        major: major, minor: minor, connected: connected
    )
}

private func gate(
    devices: [EarbudsBluetoothFeed.Record] = []
) -> EarbudsBluetoothFeed.Gate {
    EarbudsBluetoothFeed.Gate(
        allowed: { true },
        registerConnect: { true },
        devices: { devices },
        registerDisconnect: { _ in true },
        unregisterDisconnect: { _ in },
        unregisterConnect: {}
    )
}
