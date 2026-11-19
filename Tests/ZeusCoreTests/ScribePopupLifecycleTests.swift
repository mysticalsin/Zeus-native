import Foundation
import Testing
@testable import ZeusCore

/// A card asking about "m1" at 0, alive for 45 s.
private func shownCard() -> ScribePopupLifecycle {
    var card = ScribePopupLifecycle()
    card.handle(.present(key: "m1", lifetime: 45, now: 0))
    return card
}

@Suite("Scribe meeting card lifecycle")
struct ScribePopupLifecycleTests {
    @Test func theCardNeverExpiresUnderThePointer() {
        var card = shownCard()
        card.handle(.pointer(inside: true, now: 40))
        let held = card.handle(.tick(now: 100))
        #expect(held.isEmpty)
        #expect(card.phase == .shown)
        card.handle(.pointer(inside: false, now: 100))
        let grace = card.handle(.tick(now: 102))
        #expect(grace.isEmpty)
        let gone = card.handle(.tick(now: 104))
        #expect(gone == [.hide, .timedOut])
        #expect(card.phase == .expired)
    }
}
