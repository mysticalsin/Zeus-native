import Foundation
import Testing
@testable import ZeusCore

@Suite("Fling security rules")
struct FlingSecurityCoreTests {
    private func item(_ i: Int, size: Int64, name: String = "f") -> FlingOfferItem {
        FlingOfferItem(index: i, name: "\(name)\(i)", size: size, kind: .file, uti: nil, sha256: String(repeating: "0", count: 64), url: nil)
    }

    /// REG-773: sizes that would overflow a sum are declined, never trapped on, and one item has a cap.
    @Test func hugeDeclaredSizesAreDeclinedWithoutTrapping() {
        let max = Int64.max
        let free: Int64 = 100 << 30
        #expect(FlingOfferRules.validate(FlingOffer(stackID: UUID(), items: [item(0, size: max), item(1, size: max)]), freeBytes: free) != nil)
        #expect(FlingOfferRules.validate(FlingOffer(stackID: UUID(), items: [item(0, size: max / 2 + 1), item(1, size: max / 2 + 1)]), freeBytes: free) != nil)
        #expect(FlingOfferRules.validate(FlingOffer(stackID: UUID(), items: [item(0, size: FlingLimits.maxItemBytes + 1)]), freeBytes: Int64.max) == .malformed)
        #expect(FlingOfferRules.validate(FlingOffer(stackID: UUID(), items: [item(0, size: 10)]), freeBytes: Int64.min) == .diskFull)
        #expect(FlingOfferRules.validate(FlingOffer(stackID: UUID(), items: [item(0, size: FlingLimits.maxItemBytes)]), freeBytes: Int64.max) == nil)
        // The total used for the prompt saturates instead of trapping.
        #expect(FlingOfferRules.totalFileBytes(FlingOffer(stackID: UUID(), items: [item(0, size: max), item(1, size: max)])) == Int64.max)
        #expect(FlingOfferRules.totalFileBytes(FlingOffer(stackID: UUID(), items: [item(0, size: 5), item(1, size: 7)])) == 12)
    }

    /// REG-774: bidi and other format characters cannot dress a name up as another extension.
    @Test func formatAndBidiCharactersAreRejectedAndCleanedAway() {
        for bad in ["evil\u{202E}gpj.exe", "a\u{200F}b", "a\u{2066}b\u{2069}", "a\u{061C}b", "a\u{FEFF}b", "a\u{200B}b"] {
            #expect(FlingNames.validate(bad) == .failure(.unsafe), "\(bad.unicodeScalars.map(\.value))")
            let clean = FlingNames.clean(bad)
            #expect(FlingNames.validate(clean) == .success(clean))
            #expect(!clean.unicodeScalars.contains { $0.properties.generalCategory == .format })
        }
        // Joiners that emoji need stay.
        #expect(FlingNames.validate("family \u{1F468}\u{200D}\u{1F469}.png") != .failure(.unsafe))
    }

    /// REG-775: a name stays within 255 bytes even with a number added, and case alone is a clash.
    @Test func numberedNamesStayShortAndCaseIsFolded() {
        let long = String(repeating: "a", count: 251) + ".txt"
        #expect(long.utf8.count == 255)
        let numbered = FlingNames.freeName(long, taken: [long])
        #expect(numbered.utf8.count <= 255 && numbered != long && numbered.hasSuffix(".txt"))
        #expect(FlingNames.validate(numbered) != .failure(.tooLong))
        #expect(FlingNames.freeName("a.png", taken: ["A.PNG"]) == "a 2.png")
        #expect(FlingNames.freeName("\u{FF41}.png", taken: ["a.png"]) == "\u{FF41} 2.png", "a full width letter clashes with its plain form")
        let almost = String(repeating: "é", count: 120) + ".png"
        #expect(FlingNames.clean(almost, reserve: 8).utf8.count <= 255 - 8)
    }

    @Test func aHugePeerNameCannotMakeAFolderNameOver255Bytes() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let url = FlingSaveRules.destination(mode: .downloads, root: URL(fileURLWithPath: "/d"), inbox: URL(fileURLWithPath: "/i"),
                                             peer: String(repeating: "x", count: 400), date: date, downloadsGranted: true, timeZone: TimeZone(identifier: "UTC")!)
        #expect(url.lastPathComponent.utf8.count <= 255)
        #expect(FlingNames.clean(String(repeating: "é", count: 200), maxBytes: FlingSaveRules.maxPeerNameBytes).utf8.count <= FlingSaveRules.maxPeerNameBytes)
    }

    /// REG-776: only Zeus's own receiving folders are skipped by the intake watcher, not any folder called Fling.
    @Test func onlyTheConfiguredFlingFoldersAreRecognised() {
        let roots = [URL(fileURLWithPath: "/Users/a/Downloads/Fling"), URL(fileURLWithPath: "/Users/a/Library/Application Support/Zeus/Fling/Inbox")]
        func inside(_ p: String) -> Bool { FlingSaveRules.isInsideFlingFolder(URL(fileURLWithPath: p), roots: roots) }
        #expect(inside("/Users/a/Downloads/Fling/Stack/a.png"))
        #expect(inside("/Users/a/Library/Application Support/Zeus/Fling/Inbox/S/a.png"))
        #expect(!inside("/Users/a/Downloads/Other/Fling/a.png"), "a folder somewhere else with the same name")
        #expect(!inside("/Users/a/Downloads/Fling"))
        #expect(!inside("/Users/a/Downloads/Flingo/a.png"))
        #expect(!inside("/Users/a/Downloads/a.png"))
        #expect(!inside("/Users/a/Downloads/Fling/../a.png"))
    }

    /// REG-777: a received link opens by itself only when it is a public web address.
    @Test func onlyPublicWebAddressesOpenWithoutAClick() {
        for ok in ["https://example.com/a?b=1", "http://example.org", "https://sub.example.co.uk:8443/x", "https://8.8.8.8/", "https://[2001:4860:4860::8888]/"] {
            #expect(FlingLinkPolicy.opensWithoutAClick(ok), "\(ok)")
        }
        for no in ["http://localhost:8080", "http://127.0.0.1/", "http://127.1/", "http://0.0.0.0", "http://10.0.0.5/", "http://172.16.4.4", "http://172.31.255.1",
                   "http://192.168.1.1/admin", "http://169.254.169.254/latest", "http://printer.local/", "http://router/", "https://[::1]/", "https://[fe80::1]/",
                   "https://[fd12:3456::1]/", "http://2130706433/", "http://0x7f.0.0.1/", "http://LOCALHOST/", "http://foo.localhost/", "ftp://example.com", "javascript:alert(1)",
                   "https://", "not a url", "http://[::ffff:127.0.0.1]/"] {
            #expect(!FlingLinkPolicy.opensWithoutAClick(no), "\(no)")
        }
        #expect(FlingLinkPolicy.opensWithoutAClick("http://172.32.0.1/"), "172.32 is public")
    }
}
