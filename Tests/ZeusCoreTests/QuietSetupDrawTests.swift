import Testing
@testable import ZeusCore

struct QuietSetupDrawTests {
    private func cards(_ plan: QuietSetupDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aFreshInstallMutesNothing() {
        let usual = QuietSetupDraw.plan(muted: "0", trusted: "0")
        #expect(cards(usual) == ["Quiet", "Muted: 0", "Trusted: 0"])
        #expect(QuietSetupAsk.line(muted: "0", trusted: "0") == "No apps are muted, and no chats are trusted.")
        #expect(usual.boltCaption(at: 0) == "Quiet")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Trusted: 0")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(QuietSetupAsk.line(muted: "1", trusted: "1") == "1 app is muted, and 1 chat is trusted.")
        #expect(QuietSetupAsk.line(muted: "2", trusted: "3") == "2 apps are muted, and 3 chats are trusted.")
        #expect(cards(QuietSetupDraw.plan(muted: "4", trusted: "0")) == ["Quiet", "Muted: 4", "Trusted: 0"])
        #expect(cards(QuietSetupDraw.plan(muted: "00", trusted: "0")) == ["Quiet", "Can't"])
        #expect(QuietSetupAsk.line(muted: "Mail", trusted: "0") == "I can't read muted apps or trusted chats.")
    }

    @Test func waitingNotificationsStayOffThisAsk() {
        #expect(QuietSetupAsk.matches("how many apps are muted"))
        #expect(QuietSetupAsk.matches("Hey Zeus, are any chats trusted?"))
        #expect(QuietSetupAsk.matches("quiet app settings"))
        #expect(!QuietSetupAsk.matches("how many notifications"))
        #expect(!QuietSetupAsk.matches("how is other apps set"))
        #expect(!QuietSetupAsk.matches("how is the closed notch set"))
        #expect(!QuietSetupAsk.matches("how is command line control set"))
    }
}
