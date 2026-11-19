import Foundation
import Testing
@testable import ZeusCore

/// M7: the update feed and its download link are HTTPS only. No network is used.
@Suite("Update feed policy")
struct UpdateFeedPolicyTests {
    @Test func onlyHTTPSFeedAddressesAreAccepted() {
        #expect(UpdateFeedPolicy.feedURL(from: "https://updates.example.com/zeus.json")?.host == "updates.example.com")
        #expect(UpdateFeedPolicy.feedURL(from: "  https://updates.example.com/zeus.json \n") != nil)
        #expect(UpdateFeedPolicy.feedURL(from: "http://updates.example.com/zeus.json") == nil)
        #expect(UpdateFeedPolicy.feedURL(from: "file:///Users/me/zeus.json") == nil)
        #expect(UpdateFeedPolicy.feedURL(from: "ftp://updates.example.com/zeus.json") == nil)
        #expect(UpdateFeedPolicy.feedURL(from: "zeus://update") == nil)
        #expect(UpdateFeedPolicy.feedURL(from: "https://") == nil)
        #expect(UpdateFeedPolicy.feedURL(from: "https://user:pass@updates.example.com/zeus.json") == nil)
        #expect(UpdateFeedPolicy.feedURL(from: "") == nil)
        #expect(UpdateFeedPolicy.feedURL(from: nil) == nil)
    }

    @Test func aFeedLinkThatIsNotHTTPSIsDropped() throws {
        let https = Data(#"{"version":"2.0.0","downloadURL":"https://zeus.example.com/Zeus.dmg"}"#.utf8)
        #expect(FeedUpdateFetcher.offer(from: https)?.downloadURL?.absoluteString == "https://zeus.example.com/Zeus.dmg")
        for bad in ["http://zeus.example.com/Zeus.dmg", "file:///Applications/Evil.app", "x-evil://run", "javascript:alert(1)"] {
            let data = Data(#"{"version":"2.0.0","downloadURL":"\#(bad)"}"#.utf8)
            let offer = try #require(FeedUpdateFetcher.offer(from: data))
            #expect(offer.downloadURL == nil, "\(bad) must not reach the browser")
            #expect(offer.latest == ZeusVersion(major: 2, minor: 0, patch: 0))
        }
    }

    @Test func aBrokenFeedGivesNoOffer() {
        #expect(FeedUpdateFetcher.offer(from: Data("not json".utf8)) == nil)
        #expect(FeedUpdateFetcher.offer(from: Data(#"{"downloadURL":"https://a.example/x"}"#.utf8)) == nil)
    }

    @Test func theSourceRefusesANonHTTPSFeedWithoutAnyRequest() async {
        let source = BundleUpdateSource(bundleShortVersion: "1.0.0")
        #expect(await source.latestOffer(feedEnabled: true, feedURL: "http://updates.example.com/zeus.json") == nil)
        #expect(await source.latestOffer(feedEnabled: true, feedURL: "file:///etc/hosts") == nil)
        #expect(await source.latestOffer(feedEnabled: false, feedURL: "https://updates.example.com/zeus.json") == nil)
    }

    @Test func aLimitedFeedSizeIsDeclared() {
        #expect(UpdateFeedPolicy.maximumFeedBytes <= 1_048_576)
    }
}
