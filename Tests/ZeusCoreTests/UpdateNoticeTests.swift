import Foundation
import Testing
@testable import ZeusCore

@Suite("Update notice")
struct UpdateNoticeTests {
    @Test func aHiddenBadgePresentsNothing() {
        var notice = UpdateAnnouncement()
        let effects = notice.badgeHidden()
        #expect(effects == [])
        #expect(notice.state == .hidden)
    }

    @Test func anAvailableBadgeMatchingTheShownKeyPresentsNothing() {
        var notice = UpdateAnnouncement()
        let effects = notice.badgeAvailable("2.0.0", shownKey: "2.0.0")
        #expect(effects == [])
        #expect(notice.state == .shown("2.0.0"))
    }

    @Test func aNewVersionIsDueAndASecondPresentEmitsNothing() {
        var notice = UpdateAnnouncement()
        let first = notice.badgeAvailable("2.1.0", shownKey: "2.0.0")
        #expect(first == [.present])
        #expect(notice.state == .due("2.1.0"))
        let again = notice.badgeAvailable("2.1.0", shownKey: "2.0.0")
        #expect(again == [])
        notice.didPresent("2.1.0")
        #expect(notice.state == .shown("2.1.0"))
        let after = notice.badgeAvailable("2.1.0", shownKey: nil)
        #expect(after == [])
    }

    @Test func startReplacesThePollTimerFromIdleAndFromArmed() {
        var poll = UpdatePoll()
        let first = poll.start()
        #expect(first == [.replaceTimer])
        #expect(poll.state == .armed)
        let second = poll.start()
        #expect(second == [.replaceTimer])
        #expect(poll.state == .armed)
    }

    @Test func aSecureOfferOpensAndAnInsecureOfferUsesTheFallback() {
        let secure = URL(string: "https://example.com/Zeus.dmg")
        let opened = UpdateOpen.destination(offer: secure)
        #expect(opened == secure)
        let http = URL(string: "http://example.com/Zeus.dmg")
        let fallback = UpdateOpen.destination(offer: http)
        #expect(fallback == URL(string: UpdateOpen.fallback))
        let missing = UpdateOpen.destination(offer: nil)
        #expect(missing == URL(string: UpdateOpen.fallback))
    }
}
