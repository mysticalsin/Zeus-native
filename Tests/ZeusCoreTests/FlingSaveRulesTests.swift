import Foundation
import Testing
@testable import ZeusCore

@Suite("Fling save rules")
struct FlingSaveRulesTests {
    private let date = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14 22:13:20 UTC
    private let downloads = URL(fileURLWithPath: "/Users/a/Downloads")
    private let inbox = URL(fileURLWithPath: "/Users/a/Library/Application Support/Zeus/Fling/Inbox")

    private func dest(_ mode: FlingSaveMode, granted: Bool = true, peer: String = "Tony's Mac") -> URL {
        FlingSaveRules.destination(mode: mode, root: downloads, inbox: inbox, peer: peer, date: date, downloadsGranted: granted, timeZone: TimeZone(identifier: "UTC")!)
    }

    /// REG-675: arrivals go to Downloads/Fling/<peer and time>, or the Inbox when Downloads access is missing or the mode is not Downloads.
    @Test func arrivalsGoToDownloadsFlingOrTheInbox() {
        #expect(dest(.downloads).path == "/Users/a/Downloads/Fling/Tony's Mac 2023-11-14 22.13.20")
        #expect(dest(.downloads, granted: false).deletingLastPathComponent().path == inbox.path)
        #expect(dest(.clipboard).deletingLastPathComponent().path == inbox.path)
        #expect(dest(.ask).deletingLastPathComponent().path == inbox.path)
    }

    @Test func aHostilePeerNameCannotEscapeTheFolder() {
        let url = dest(.downloads, peer: "../../etc")
        #expect(FlingNames.isContained(url, in: downloads.appendingPathComponent("Fling")))
        #expect(!url.lastPathComponent.contains("/"))
        #expect(dest(.downloads, peer: "").lastPathComponent.hasPrefix("Mac "))
    }

    @Test func aWeblocFileHoldsTheLinkAndIsNeverAnythingElse() throws {
        let data = FlingSaveRules.weblocData(for: "https://example.com/a?b=1&c=2")
        let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
        #expect(plist == ["URL": "https://example.com/a?b=1&c=2"])
        #expect(FlingSaveRules.linkFileName("Example Domain") == "Example Domain.webloc")
        #expect(FlingSaveRules.linkFileName("Link") == "Link.webloc")
    }

    @Test func theSaveModesHaveStableRawValues() {
        #expect(FlingSaveMode.downloads.rawValue == "downloads")
        #expect(FlingSaveMode.clipboard.rawValue == "clipboard")
        #expect(FlingSaveMode.ask.rawValue == "ask")
        #expect(FlingSaveMode(rawValue: "nonsense") == nil)
    }
}
