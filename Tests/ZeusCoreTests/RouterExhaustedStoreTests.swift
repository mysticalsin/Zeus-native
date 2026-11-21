import Foundation
import Testing
@testable import ZeusCore

@Suite("Router exhausted store")
struct RouterExhaustedStoreTests {
    private func fresh() throws -> UserDefaults {
        let name = NSTemporaryDirectory() + "zeus.router-exhausted.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func aFutureExpirySurvivesTheDictionaryRoundTrip() throws {
        let defaults = try fresh()
        let until = Date().addingTimeInterval(3_600)
        defaults.set(["engine": until], forKey: RouterExhaustedStore.key)
        let loaded = RouterExhaustedStore.load(defaults, now: Date())
        let saved = try #require(loaded["engine"])
        #expect(abs(saved.timeIntervalSince(until)) < 1)
    }

    @Test func aPastExpiryAndANonDateAreDropped() throws {
        let defaults = try fresh()
        defaults.set(["old": Date().addingTimeInterval(-10), "note": "later"], forKey: RouterExhaustedStore.key)
        #expect(RouterExhaustedStore.load(defaults).isEmpty)
    }
}
