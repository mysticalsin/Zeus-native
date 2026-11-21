import Foundation
import Testing
@testable import ZeusCore

@Suite("Update badge integrity")
struct UpdateIntegrityTests {
    @Test func aPreferencesFakeCannotHideARealOffer() throws {
        let current = try #require(ZeusVersion(parsing: "1.0.0"))
        let offer = UpdateOffer(latest: try #require(ZeusVersion(parsing: "9.0.0")),
                                downloadURL: URL(string: "https://updates.example/Zeus.dmg"))
        let defaults = UserDefaults(suiteName: NSTemporaryDirectory() + "UpdateIntegrity.\(UUID().uuidString)")!
        let state = UpdateBadgeLogic.badgeState(current: current, offer: offer, feedEnabled: true,
                                                 debugFake: "0.0.1", defaults: defaults)
        guard case .available(let shown, _) = state else {
            Issue.record("the real offer was hidden")
            return
        }
        #expect(shown.latest == offer.latest)
        #expect(shown.downloadURL == offer.downloadURL)
    }

    @Test func aCrossHostFeedRedirectIsRefused() {
        let original = URL(string: "https://updates.example/feed.json")!
        let other = URL(string: "https://other.example/feed.json")!
        let same = URL(string: "https://updates.example/Zeus.dmg")!
        #expect(UpdateFeedPolicy.redirected(other, from: original) == nil)
        #expect(UpdateFeedPolicy.redirected(same, from: original) == same)
    }
}
